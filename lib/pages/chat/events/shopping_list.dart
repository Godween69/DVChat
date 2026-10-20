// SPDX-License-Identifier: AGPL-3.0-or-later

// DVChat: Список покупок в чате. Карточка висит в переписке, пункты отмечаются касанием
// (общие отметки через те же события-чекбоксы, что и в обычных списках задач).
// Запасной вариант для чужих клиентов: обычный текст с «☐ пункт».

import 'package:dvchat/pages/chat/trust_user_key_dialog.dart';
import 'package:dvchat/utils/event_checkbox_extension.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

const String dvShoppingKey = 'online.dvbstudio.dvchat.shopping';

/// Достаёт список из события, если это список покупок
({String title, List<String> items})? dvShoppingOf(Event event) {
  final raw = event.content[dvShoppingKey];
  if (raw is! Map) return null;
  final items = raw['items'];
  if (items is! List) return null;
  return (
    title: '${raw['title'] ?? 'Список покупок'}',
    items: items.map((e) => '$e').toList(),
  );
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

    final total = data.items.length;
    var done = 0;
    for (var i = 1; i <= total; i++) {
      if (checkOf(i) != null) done++;
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
          for (var i = 0; i < total; i++)
            _row(context, room, i + 1, data.items[i], checkOf(i + 1), canTap),
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
    int index,
    String text,
    Event? check,
    bool canTap,
  ) {
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
  const ShoppingListSheet({required this.room, super.key});

  final Room room;

  @override
  State<ShoppingListSheet> createState() => _ShoppingListSheetState();
}

class _ShoppingListSheetState extends State<ShoppingListSheet> {
  final _title = TextEditingController(text: 'Список покупок');
  final List<TextEditingController> _items = [TextEditingController()];
  final List<FocusNode> _nodes = [FocusNode()];
  bool _busy = false;

  static const _max = 40;

  @override
  void dispose() {
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

  @override
  Widget build(BuildContext context) {
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
