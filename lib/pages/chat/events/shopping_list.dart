// SPDX-License-Identifier: AGPL-3.0-or-later

// DVChat: Список покупок в чате. Карточка висит в переписке, пункты отмечаются касанием
// (общие отметки через те же события-чекбоксы, что и в обычных списках задач).
// Запасной вариант для чужих клиентов: обычный текст с «☐ пункт».

import 'package:dvchat/pages/chat/trust_user_key_dialog.dart';
import 'package:dvchat/utils/adaptive_bottom_sheet.dart';
import 'package:dvchat/utils/dv_nicknames.dart';
import 'package:dvchat/utils/dv_shopping_keys.dart';
import 'package:dvchat/utils/event_checkbox_extension.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

const String dvShoppingKey = 'online.dvbstudio.dvchat.shopping';

/// Достаёт список из события, если это список покупок
({String title, List<String> items, Set<int> removed})? dvShoppingOf(
  Event event,
) {
  final raw = event.content[dvShoppingKey];
  if (raw is! Map) return null;
  final items = raw['items'];
  if (items is! List) return null;
  // removed: номера (с 1) пунктов, которые автор убрал; номера не сдвигаются, чтобы отметки не путались
  final removed = raw['removed'];
  return (
    title: '${raw['title'] ?? 'Список покупок'}',
    items: items.map((e) => '$e').toList(),
    removed: removed is List
        ? removed.whereType<int>().toSet()
        : <int>{},
  );
}

/// Автор убирает пункт: правка исходного сообщения (в ленте остаётся одно сообщение)
Future<void> removeShoppingItem(Event event, int index) async {
  final data = dvShoppingOf(event);
  if (data == null) return;
  final removed = {...data.removed, index}.toList()..sort();
  final body = StringBuffer('🛒 ${data.title}');
  for (var i = 0; i < data.items.length; i++) {
    if (!removed.contains(i + 1)) body.write('\n☐ ${data.items[i]}');
  }
  await event.room.sendEvent({
    'msgtype': MessageTypes.Text,
    'body': body.toString(),
    dvShoppingKey: {
      'title': data.title,
      'items': data.items,
      'removed': removed,
    },
  }, editEventId: event.eventId);
}

Future<void> sendShoppingList(
  Room room,
  String title,
  List<String> items,
) async {
  final body = StringBuffer('🛒 $title');
  for (final i in items) {
    body.write('\n☐ $i');
  }
  await room.sendEvent({
    'msgtype': MessageTypes.Text,
    'body': body.toString(),
    dvShoppingKey: {'title': title, 'items': items},
  });
}

/// Один пункт списка: начальный (из самого сообщения) или добавленный позже отдельным событием
class DvShopItem {
  const DvShopItem({
    required this.id,
    required this.text,
    required this.senderId,
    required this.initial,
    this.events = const <Event>[],
    this.at = 0,
  });

  /// У начальных пунктов номер с 1, у добавленных большое число (время и счётчик)
  final int id;
  final String text;

  /// Кто добавил пункт: только он может его менять и убирать
  final String senderId;
  final bool initial;

  /// События добавленного пункта (у начальных пусто)
  final List<Event> events;

  /// Время добавления: по нему добавленные пункты стоят по порядку, даже после правки текста
  final int at;
}

/// Все пункты списка по порядку: сначала начальные, потом добавленные участниками чата.
/// Добавленный пункт это скрытое событие-реакция (тип связи dvShopItemRel) на сообщение со списком.
/// Правки чужого пункта не принимаются: пункт принадлежит тому, кто прислал его первым.
List<DvShopItem> dvShoppingItems(Event event, Timeline timeline) {
  final data = dvShoppingOf(event);
  if (data == null) return const <DvShopItem>[];
  final out = <DvShopItem>[
    for (var i = 1; i <= data.items.length; i++)
      if (!data.removed.contains(i))
        DvShopItem(
          id: i,
          text: data.items[i - 1],
          senderId: event.senderId,
          initial: true,
        ),
  ];
  final events =
      event
          .aggregatedEvents(timeline, dvShopItemRel)
          .where((e) => !e.redacted)
          .toList()
        ..sort((a, b) => a.originServerTs.compareTo(b.originServerTs));
  final owner = <int, String>{};
  final text = <int, String>{};
  final at = <int, int>{};
  final evs = <int, List<Event>>{};
  final order = <int>[];
  for (final e in events) {
    final raw = e.content[dvShopItemKey];
    if (raw is! Map) continue;
    final id = raw['id'];
    final t = raw['text'];
    if (id is! int || t is! String || t.trim().isEmpty) continue;
    if (id <= data.items.length) continue;
    if (!owner.containsKey(id)) {
      owner[id] = e.senderId;
      order.add(id);
      final a = raw['at'];
      at[id] = a is int ? a : e.originServerTs.millisecondsSinceEpoch;
    }
    if (owner[id] != e.senderId) continue;
    text[id] = t.trim();
    (evs[id] ??= <Event>[]).add(e);
  }
  final added = <DvShopItem>[
    for (final id in order)
      DvShopItem(
        id: id,
        text: text[id] ?? '',
        senderId: owner[id] ?? '',
        initial: false,
        events: evs[id] ?? const <Event>[],
        at: at[id] ?? 0,
      ),
  ]..sort((a, b) {
      final c = a.at.compareTo(b.at);
      return c != 0 ? c : a.id.compareTo(b.id);
    });
  return [...out, ...added];
}

int _shopSeq = 0;

Future<void> _sendShopItem(
  Room room,
  String listId,
  int id,
  String text,
  int at,
) async {
  await room.sendEvent({
    'm.relates_to': {'rel_type': dvShopItemRel, 'event_id': listId},
    dvShopItemKey: {'id': id, 'text': text, 'at': at},
  }, type: EventTypes.Reaction);
}

/// Добавляет новый пункт в список (может любой участник чата)
Future<void> addShoppingItem(Room room, String listId, String text) {
  final now = DateTime.now().millisecondsSinceEpoch;
  _shopSeq = (_shopSeq + 1) % 1000;
  return _sendShopItem(room, listId, now * 1000 + _shopSeq, text, now);
}

/// Меняет текст своего добавленного пункта: новое событие с тем же номером, старые убираются
Future<void> updateShoppingAdded(
  Room room,
  String listId,
  DvShopItem item,
  String text,
) async {
  await _sendShopItem(room, listId, item.id, text, item.at);
  for (final e in item.events) {
    try {
      await room.redactEvent(e.eventId);
    } catch (_) {
      // старое событие не убралось: новое всё равно главнее (берётся последнее)
    }
  }
}

/// Убирает свой добавленный пункт
Future<void> removeShoppingAdded(Room room, DvShopItem item) async {
  for (final e in item.events) {
    await room.redactEvent(e.eventId);
  }
}

/// Автор списка меняет текст и убранные пункты начального набора: правка исходного сообщения
Future<void> editShoppingBase(
  Event event,
  String title,
  List<String> items,
  Set<int> removed,
) async {
  final sorted = removed.toList()..sort();
  final body = StringBuffer('🛒 $title');
  for (var i = 0; i < items.length; i++) {
    if (!removed.contains(i + 1)) body.write('\n☐ ${items[i]}');
  }
  await event.room.sendEvent({
    'msgtype': MessageTypes.Text,
    'body': body.toString(),
    dvShoppingKey: {'title': title, 'items': items, 'removed': sorted},
  }, editEventId: event.eventId);
}

/// Открывает окно списка: добавить пункт, поправить или убрать свои
void openShoppingEditor(
  BuildContext context,
  Event event,
  Timeline timeline, {
  bool focusNew = true,
}) {
  showAdaptiveBottomSheet<void>(
    context: context,
    builder: (context) => ShoppingListSheet(
      room: event.room,
      list: event.getDisplayEvent(timeline),
      timeline: timeline,
      focusNew: focusNew,
    ),
  );
}

class ShoppingListCard extends StatelessWidget {
  const ShoppingListCard({
    required this.event,
    required this.timeline,
    required this.textColor,
    super.key,
  });

  final Event event;
  final Timeline timeline;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    final data = dvShoppingOf(event);
    if (data == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final room = event.room;
    final checks = event
        .aggregatedEvents(timeline, EventCheckboxRoomExtension.relationshipType)
        .toList();
    Event? checkOf(int index) {
      for (final c in checks) {
        if (c.checkedCheckboxId == index) return c;
      }
      return null;
    }

    final items = dvShoppingItems(event, timeline);
    final total = items.length;
    var done = 0;
    for (final it in items) {
      if (checkOf(it.id) != null) done++;
    }
    final all = total > 0 && done == total;
    final canTap = room.canSendDefaultMessages;
    final accent = all ? Colors.green : theme.colorScheme.primary;

    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 230, maxWidth: 330),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
        child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: accent.withAlpha(46),
                ),
                child: Icon(
                  all ? Icons.check_circle : Icons.shopping_cart_outlined,
                  color: accent,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  data.title,
                  style: TextStyle(
                    color: textColor,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
              ),
              Text(
                '$done/$total',
                style: TextStyle(
                  color: textColor.withAlpha(180),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: total == 0 ? 0 : done / total,
              minHeight: 6,
              color: accent,
              backgroundColor: textColor.withAlpha(40),
            ),
          ),
          const SizedBox(height: 10),
          for (final it in items)
            _row(context, room, it, checkOf(it.id), canTap),
          // DVChat: добавить пункт может любой участник чата; окно списка откроется заново
          if (canTap && event.eventId.isNotEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => openShoppingEditor(context, event, timeline),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Добавить пункт'),
                style: TextButton.styleFrom(foregroundColor: textColor),
              ),
            ),
          if (all)
            Padding(
              padding: const EdgeInsets.only(top: 6, bottom: 2),
              child: Row(
                children: [
                  const Text('🎉', style: TextStyle(fontSize: 18)),
                  const SizedBox(width: 6),
                  Text(
                    'Всё куплено!',
                    style: TextStyle(
                      color: Colors.green.shade600,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
      ),
    );
  }

  Widget _row(
    BuildContext context,
    Room room,
    DvShopItem item,
    Event? check,
    bool canTap,
  ) {
    final index = item.id;
    final text = item.text;
    final checked = check != null;
    // снять отметку может только тот, кто её поставил
    final mine = check == null || check.senderId == room.client.userID;
    final enabled = canTap && mine && event.eventId.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: checked ? Colors.green.withAlpha(26) : textColor.withAlpha(18),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: !enabled
          ? null
          : () async {
              try {
                if (check != null) {
                  await room.redactEvent(check.eventId);
                } else {
                  await room.checkCheckbox(event.eventId, index);
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text('$e')));
                }
              }
            },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: checked ? Colors.green : Colors.transparent,
                border: Border.all(
                  color: checked ? Colors.green : textColor.withAlpha(150),
                  width: 2,
                ),
              ),
              child: checked
                  ? const Icon(Icons.check, size: 16, color: Colors.white)
                  : null,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 180),
                style: TextStyle(
                  fontSize: 15,
                  color: checked ? textColor.withAlpha(120) : textColor,
                  decoration: checked
                      ? TextDecoration.lineThrough
                      : TextDecoration.none,
                  decorationColor: textColor,
                  decorationThickness: 2,
                ),
                child: Text(text),
              ),
            ),
            // DVChat: убрать пункт может только тот, кто его добавил
            if (!checked &&
                canTap &&
                item.senderId == room.client.userID &&
                event.eventId.isNotEmpty)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () async {
                  try {
                    if (item.initial) {
                      await removeShoppingItem(event, index);
                    } else {
                      await removeShoppingAdded(room, item);
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(SnackBar(content: Text('$e')));
                    }
                  }
                },
                child: Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Icon(
                    Icons.close,
                    size: 18,
                    color: textColor.withAlpha(150),
                  ),
                ),
              ),
          ],
        ),
      ),
        ),
      ),
    );
  }
}

/// Окно составления списка
class ShoppingListSheet extends StatefulWidget {
  const ShoppingListSheet({
    required this.room,
    this.list,
    this.timeline,
    this.focusNew = true,
    super.key,
  });

  final Room room;

  /// Если задан, окно правит этот список (добавить пункт, поправить или убрать свои)
  final Event? list;
  final Timeline? timeline;

  /// Сразу поставить курсор в поле нового пункта
  final bool focusNew;

  @override
  State<ShoppingListSheet> createState() => _ShoppingListSheetState();
}

class _ShoppingListSheetState extends State<ShoppingListSheet> {
  final _title = TextEditingController(text: 'Список покупок');
  final List<TextEditingController> _items = [TextEditingController()];
  final List<FocusNode> _nodes = [FocusNode()];
  bool _busy = false;

  static const _max = 40;
  static const _maxTotal = 60;

  // ---------- окно правки существующего списка ----------
  bool get _editing => widget.list != null && widget.timeline != null;
  List<DvShopItem> _all = const <DvShopItem>[];
  Set<int> _checkedIds = <int>{};
  final Map<int, _EditRow> _edit = {}; // мои пункты, которые можно менять
  final List<_EditRow> _fresh = []; // новые пункты
  final List<DvShopItem> _deleted = []; // мои пункты, убранные в этом окне
  final List<_EditRow> _graveyard = []; // убранные поля: освобождаем при закрытии окна

  @override
  void initState() {
    super.initState();
    final list = widget.list;
    final tl = widget.timeline;
    if (list == null || tl == null) return;
    final me = widget.room.client.userID;
    _all = dvShoppingItems(list, tl);
    _checkedIds = {
      for (final c in list.aggregatedEvents(
        tl,
        EventCheckboxRoomExtension.relationshipType,
      ))
        if (c.checkedCheckboxId != null) c.checkedCheckboxId!,
    };
    for (final it in _all) {
      // поставленную отметку менять нельзя: пункт показывается только для чтения
      if (it.senderId == me && !_checkedIds.contains(it.id)) {
        _edit[it.id] = _EditRow(it.text, it);
      }
    }
    _fresh.add(_EditRow('', null));
    if (widget.focusNew) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _fresh.isNotEmpty) _fresh.last.n.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    for (final r in [..._edit.values, ..._fresh, ..._graveyard]) {
      r.c.dispose();
      r.n.dispose();
    }
    _title.dispose();
    for (final c in _items) {
      c.dispose();
    }
    for (final n in _nodes) {
      n.dispose();
    }
    super.dispose();
  }

  void _add() {
    if (_items.length >= _max) return;
    setState(() {
      _items.add(TextEditingController());
      _nodes.add(FocusNode());
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _nodes.last.requestFocus();
    });
  }

  void _remove(int i) {
    if (_items.length <= 1) {
      _items[0].clear();
      return;
    }
    setState(() {
      _items.removeAt(i).dispose();
      _nodes.removeAt(i).dispose();
    });
  }

  List<String> get _filled =>
      _items.map((c) => c.text.trim()).where((t) => t.isNotEmpty).toList();

  Future<void> _send() async {
    final list = _filled;
    if (list.isEmpty || _busy) return;
    final proceed = await showTrustUserInRoomDialog(context, widget.room);
    if (!proceed || !mounted) return;
    setState(() => _busy = true);
    try {
      final t = _title.text.trim();
      await sendShoppingList(
        widget.room,
        t.isEmpty ? 'Список покупок' : t,
        list,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Не отправилось: $e')));
    }
  }

  void _addFresh() {
    setState(() => _fresh.add(_EditRow('', null)));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _fresh.isNotEmpty) _fresh.last.n.requestFocus();
    });
  }

  void _removeFresh(_EditRow r) {
    setState(() {
      _fresh.remove(r);
      _graveyard.add(r);
    });
  }

  void _removeMine(DvShopItem it) {
    setState(() {
      final r = _edit.remove(it.id);
      if (r != null) _graveyard.add(r);
      _deleted.add(it);
    });
  }

  Future<void> _saveEdit() async {
    if (_busy) return;
    final list = widget.list;
    final data = list == null ? null : dvShoppingOf(list);
    if (list == null || data == null) return;
    final newTexts = [
      for (final r in _fresh) r.c.text.trim(),
    ].where((t) => t.isNotEmpty).toList();
    final changed = <MapEntry<DvShopItem, String>>[];
    final deleted = <DvShopItem>[..._deleted];
    for (final e in _edit.values) {
      final it = e.item;
      if (it == null) continue;
      final t = e.c.text.trim();
      if (t.isEmpty) {
        deleted.add(it);
      } else if (t != it.text) {
        changed.add(MapEntry(it, t));
      }
    }
    if (newTexts.isEmpty && changed.isEmpty && deleted.isEmpty) {
      Navigator.of(context).pop();
      return;
    }
    if (_all.length - deleted.length + newTexts.length > _maxTotal) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('В списке может быть не больше 60 пунктов')),
      );
      return;
    }
    final proceed = await showTrustUserInRoomDialog(context, widget.room);
    if (!proceed || !mounted) return;
    setState(() => _busy = true);
    try {
      final items = [...data.items];
      final removed = {...data.removed};
      var baseChanged = false;
      for (final it in deleted) {
        if (it.initial) {
          removed.add(it.id);
          baseChanged = true;
        } else {
          await removeShoppingAdded(widget.room, it);
        }
      }
      for (final ch in changed) {
        final it = ch.key;
        if (it.initial) {
          items[it.id - 1] = ch.value;
          baseChanged = true;
        } else {
          await updateShoppingAdded(widget.room, list.eventId, it, ch.value);
        }
      }
      for (final t in newTexts) {
        await addShoppingItem(widget.room, list.eventId, t);
      }
      if (baseChanged) {
        await editShoppingBase(list, data.title, items, removed);
      }
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Не сохранилось: $e')));
    }
  }

  Widget _field(_EditRow r, String hint, VoidCallback onRemove) {
    return Row(
      key: ObjectKey(r),
      children: [
        Expanded(
          child: TextField(
            controller: r.c,
            focusNode: r.n,
            maxLength: 80,
            textInputAction: TextInputAction.next,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              hintText: hint,
              counter: const SizedBox.shrink(),
              prefixIcon: const Icon(Icons.radio_button_unchecked),
            ),
          ),
        ),
        IconButton(icon: const Icon(Icons.close), onPressed: onRemove),
      ],
    );
  }

  Widget _readRow(DvShopItem it) {
    final done = _checkedIds.contains(it.id);
    final me = widget.room.client.userID;
    final who = it.senderId == me
        ? 'Вы'
        : widget.room.unsafeGetUserFromMemoryOrFallback(it.senderId).dvName();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(
            done ? Icons.check_circle : Icons.radio_button_unchecked,
            color: done ? Colors.green : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  it.text,
                  style: TextStyle(
                    decoration: done
                        ? TextDecoration.lineThrough
                        : TextDecoration.none,
                  ),
                ),
                Text(who, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEdit(BuildContext context) {
    final data = dvShoppingOf(widget.list!);
    final total = _all.length - _deleted.length + _fresh.length;
    return Scaffold(
      appBar: AppBar(
        leading: CloseButton(onPressed: Navigator.of(context).pop),
        title: Text(data?.title ?? 'Список покупок'),
        actions: [
          TextButton.icon(
            onPressed: _busy ? null : _saveEdit,
            icon: const Icon(Icons.check),
            label: const Text('Сохранить'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
        children: [
          for (final it in _all)
            if (_edit[it.id] != null)
              _field(_edit[it.id]!, 'Пункт', () => _removeMine(it))
            else
              _readRow(it),
          for (final r in _fresh)
            _field(r, 'Новый пункт', () => _removeFresh(r)),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: total >= _maxTotal ? null : _addFresh,
              icon: const Icon(Icons.add),
              label: const Text('Добавить пункт'),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_editing) return _buildEdit(context);
    return Scaffold(
      appBar: AppBar(
        leading: CloseButton(onPressed: Navigator.of(context).pop),
        title: const Text('Список покупок'),
        actions: [
          TextButton.icon(
            onPressed: _busy || _filled.isEmpty ? null : _send,
            icon: const Icon(Icons.send),
            label: const Text('Отправить'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
        children: [
          TextField(
            controller: _title,
            maxLength: 60,
            decoration: const InputDecoration(
              labelText: 'Название',
              counter: SizedBox.shrink(),
            ),
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < _items.length; i++)
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _items[i],
                    focusNode: _nodes[i],
                    maxLength: 80,
                    textInputAction: TextInputAction.next,
                    textCapitalization: TextCapitalization.sentences,
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) {
                      if (_items[i].text.trim().isNotEmpty) {
                        i == _items.length - 1
                            ? _add()
                            : _nodes[i + 1].requestFocus();
                      }
                    },
                    decoration: InputDecoration(
                      hintText: 'Пункт ${i + 1}',
                      counter: const SizedBox.shrink(),
                      prefixIcon: const Icon(Icons.radio_button_unchecked),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => _remove(i),
                ),
              ],
            ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _items.length >= _max ? null : _add,
              icon: const Icon(Icons.add),
              label: const Text('Добавить пункт'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Поле ввода одного пункта в окне правки списка
class _EditRow {
  _EditRow(String text, this.item) : c = TextEditingController(text: text);

  /// null у нового пункта
  final DvShopItem? item;
  final TextEditingController c;
  final FocusNode n = FocusNode();
}
