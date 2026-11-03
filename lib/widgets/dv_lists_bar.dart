// SPDX-License-Identifier: AGPL-3.0-or-later

// DVChat: общие списки в личном чате (покупки, дела). Над полем ввода торчат «папочки»: слева всегда
// плюс (создать список), дальше по одной вкладке на список: цветная, полупрозрачная, с названием и счётчиком
// («3/8»). Выполненный список становится серым с зелёной галочкой и надписью «Готово». Нажатие открывает
// панель со списком, долгое нажатие на выполненный список убирает его у себя.
// Логика, правила и хранение: utils/dv_lists.dart.

import 'package:dvchat/utils/adaptive_bottom_sheet.dart';
import 'package:dvchat/utils/dv_lists.dart';
import 'package:dvchat/widgets/adaptive_dialogs/show_text_input_dialog.dart';
import 'package:dvchat/widgets/dv_glass.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

const Color _doneColor = Color(0xFF34B27B);

// Цвета вкладок: спокойные, у каждого списка свой (по номеру списка, не меняется со временем).
// Зелёный занят под «Готово».
const List<Color> _tabColors = [
  DvMenuColors.blue,
  DvMenuColors.purple,
  DvMenuColors.orange,
  DvMenuColors.pink,
  DvMenuColors.teal,
  DvMenuColors.amber,
];

Color _colorOf(String listId) {
  var sum = 0;
  for (final c in listId.codeUnits) {
    sum += c;
  }
  return _tabColors[sum % _tabColors.length];
}

/// Имя человека для подписей: «вы» или имя собеседника
String _who(Room room, String userId) {
  if (userId.isEmpty) return '';
  if (userId == room.client.userID) return 'вы';
  final name = room.getLocalizedDisplayname().trim();
  return name.isEmpty ? 'собеседник' : name;
}

/// Создать список: спросить название, создать, открыть панель с курсором в поле нового пункта
Future<void> dvCreateList(BuildContext context, Room room) async {
  final messenger = ScaffoldMessenger.of(context);
  if (!DvLists.canEdit(room)) {
    messenger.showSnackBar(
      const SnackBar(
        content: Text(
          'Пока нельзя создавать списки в этом чате. Откройте DVChat у того, кто создал чат: права выровняются сами.',
        ),
      ),
    );
    return;
  }
  final title = await showTextInputDialog(
    context: context,
    title: 'Новый список',
    hintText: 'Например, Покупки или Дела',
    okLabel: 'Создать',
    cancelLabel: 'Отмена',
    maxLength: DvLists.maxTitle,
  );
  if (title == null || title.trim().isEmpty) return;
  try {
    final id = await DvLists.create(room, title);
    if (!context.mounted) return;
    await dvOpenList(context, room, id, focusNew: true);
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('$e')));
  }
}

Future<void> dvOpenList(
  BuildContext context,
  Room room,
  String listId, {
  bool focusNew = false,
}) => showAdaptiveBottomSheet<void>(
  context: context,
  builder: (_) => DvListSheet(room: room, listId: listId, focusNew: focusNew),
);

/// Убрать список только у себя (после подтверждения). Убрать можно выполненный или пустой список.
Future<void> dvHideList(BuildContext context, Room room, DvList list) async {
  final messenger = ScaffoldMessenger.of(context);
  if (!list.canHide) {
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Убрать список можно, когда все пункты отмечены'),
      ),
    );
    return;
  }
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Убрать «${list.title}» у себя?'),
      content: const Text(
        'Список исчезнет только у вас, у собеседника он останется. '
        'Он вернётся к вам, если в нём что-то изменят.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Отмена'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Убрать'),
        ),
      ],
    ),
  );
  if (ok != true) return;
  try {
    await DvLists.hide(room, list);
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Не получилось: $e')));
  }
}

// =============================================================== лента «папочек»

const BorderRadius _tabShape = BorderRadius.vertical(top: Radius.circular(16));

class DvListsBar extends StatelessWidget {
  const DvListsBar(this.room, {super.key});

  final Room room;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return StreamBuilder<SyncUpdate>(
      stream: room.client.onSync.stream,
      builder: (context, snapshot) => ValueListenableBuilder<int>(
        valueListenable: DvLists.tick,
        builder: (context, tick, child) {
          final lists = DvLists.visible(room);
          return SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(30, 0, 14, 0),
              children: [
                // Плюс стоит слева всегда
                Align(
                  alignment: Alignment.bottomLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: _AddTab(room),
                  ),
                ),
                if (lists.isEmpty)
                  Center(
                    child: Text(
                      'Создай список дел или покупок',
                      style: TextStyle(
                        fontSize: 13,
                        color: theme.colorScheme.onSurface.withAlpha(105),
                      ),
                    ),
                  ),
                for (final list in lists)
                  Align(
                    alignment: Alignment.bottomLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: _ListTab(room: room, list: list),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ListTab extends StatelessWidget {
  const _ListTab({required this.room, required this.list});

  final Room room;
  final DvList list;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final done = list.complete;
    // Выполненный список серый, остальные цветные и полупрозрачные
    final base = done ? theme.colorScheme.onSurface : _colorOf(list.id);
    return Material(
      color: base.withAlpha(done ? 18 : 40),
      shape: RoundedRectangleBorder(
        borderRadius: _tabShape,
        side: BorderSide(color: base.withAlpha(done ? 36 : 85)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => dvOpenList(context, room, list.id),
        onLongPress: () => dvHideList(context, room, list),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 116),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  done ? Icons.check_circle : Icons.checklist_rounded,
                  size: 17,
                  color: done ? _doneColor : base,
                ),
                const SizedBox(width: 7),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 140),
                  child: Text(
                    list.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: done
                          ? theme.colorScheme.onSurfaceVariant
                          : theme.colorScheme.onSurface,
                    ),
                  ),
                ),
                const SizedBox(width: 7),
                Text(
                  done
                      ? 'Готово'
                      : list.total == 0
                      ? 'пусто'
                      : '${list.doneCount}/${list.total}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: done ? FontWeight.bold : FontWeight.normal,
                    color: done
                        ? _doneColor
                        : theme.colorScheme.onSurfaceVariant,
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

class _AddTab extends StatelessWidget {
  const _AddTab(this.room);

  final Room room;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return Tooltip(
      message: 'Новый список',
      child: Material(
        color: color.withAlpha(34),
        shape: RoundedRectangleBorder(
          borderRadius: _tabShape,
          side: BorderSide(color: color.withAlpha(75)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => dvCreateList(context, room),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            child: Icon(Icons.add, size: 20, color: color),
          ),
        ),
      ),
    );
  }
}

// =============================================================== панель списка

class DvListSheet extends StatefulWidget {
  const DvListSheet({
    required this.room,
    required this.listId,
    this.focusNew = false,
    super.key,
  });

  final Room room;
  final String listId;

  /// Сразу поставить курсор в поле нового пункта
  final bool focusNew;

  @override
  State<DvListSheet> createState() => _DvListSheetState();
}

class _DvListSheetState extends State<DvListSheet> {
  final TextEditingController _field = TextEditingController();
  final FocusNode _focus = FocusNode();
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    if (widget.focusNew) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focus.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _field.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() job) async {
    try {
      await job();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Не получилось: $e')));
    }
  }

  Future<void> _add() async {
    final text = _field.text.trim();
    if (text.isEmpty) return;
    _field.clear();
    _focus.requestFocus();
    await _run(() => DvLists.addItem(widget.room, widget.listId, text));
  }

  Future<void> _rename(DvList list) async {
    final title = await showTextInputDialog(
      context: context,
      title: 'Название списка',
      initialText: list.title,
      okLabel: 'Сохранить',
      cancelLabel: 'Отмена',
      maxLength: DvLists.maxTitle,
    );
    if (title == null || title.trim().isEmpty) return;
    await _run(() => DvLists.rename(widget.room, list.id, title));
  }

  void _info() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Как работает список'),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _InfoLine('Добавлять пункты может каждый из вас.'),
              _InfoLine('Свой пункт можно удалить, чужой нельзя.'),
              _InfoLine(
                'Отметить пункт может любой, а снять отметку только тот, кто её поставил.',
              ),
              _InfoLine(
                'Название меняет тот, кто создал список: нажмите на название.',
              ),
              _InfoLine(
                'Придёт уведомление, когда отмечена половина, остался один пункт и когда всё готово. '
                'Отключить его можно в настройках уведомлений.',
              ),
              _InfoLine(
                'Когда всё отмечено, вкладка становится серой с пометкой «Готово». '
                'Убрать её у себя можно кнопкой в списке или долгим нажатием на вкладку. '
                'У собеседника список останется, пока он не уберёт его сам.',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Понятно'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final room = widget.room;
    return StreamBuilder<SyncUpdate>(
      stream: room.client.onSync.stream,
      builder: (context, snapshot) => ValueListenableBuilder<int>(
        valueListenable: DvLists.tick,
        builder: (context, tick, child) {
          final list = DvLists.all(room)[widget.listId];
          final gone =
              list == null ||
              DvLists.isHidden(list, DvLists.hiddenOf(room));
          if (gone) {
            if (!_closing) {
              _closing = true;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) Navigator.of(context).maybePop();
              });
            }
            return const SizedBox(height: 120);
          }
          return _body(context, list);
        },
      ),
    );
  }

  Widget _body(BuildContext context, DvList list) {
    final room = widget.room;
    final theme = Theme.of(context);
    final me = room.client.userID ?? '';
    final canEdit = DvLists.canEdit(room);
    final canRename = canEdit && list.canRename(me);
    final complete = list.complete;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 8, 0),
              child: Row(
                children: [
                  Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: canRename ? () => _rename(list) : null,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  list.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.titleLarge,
                                ),
                              ),
                              if (canRename)
                                Padding(
                                  padding: const EdgeInsets.only(left: 6),
                                  child: Icon(
                                    Icons.edit_outlined,
                                    size: 15,
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                            ],
                          ),
                          Text(
                            complete
                                ? 'Готово'
                                : list.total == 0
                                ? 'Пока пусто'
                                : 'Отмечено ${list.doneCount} из ${list.total}',
                            style: TextStyle(
                              color: complete
                                  ? _doneColor
                                  : theme.colorScheme.onSurfaceVariant,
                              fontWeight: complete
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Как работает список',
                    icon: const Icon(Icons.info_outline),
                    onPressed: _info,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: list.total == 0 ? 0 : list.doneCount / list.total,
                  minHeight: 5,
                  color: complete ? _doneColor : null,
                ),
              ),
            ),
            if (list.canHide)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                child: FilledButton.tonalIcon(
                  onPressed: () => dvHideList(context, room, list),
                  icon: const Icon(Icons.visibility_off_outlined),
                  label: const Text('Убрать список у меня'),
                ),
              ),
            Flexible(
              child: list.items.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        canEdit
                            ? 'Добавьте первый пункт ниже. Собеседник увидит его сразу.'
                            : 'В списке пока ничего нет.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: list.items.length,
                      itemBuilder: (context, index) => _ItemRow(
                        room: room,
                        listId: list.id,
                        item: list.items[index],
                        canEdit: canEdit,
                        onError: (e) => ScaffoldMessenger.of(
                          context,
                        ).showSnackBar(SnackBar(content: Text('$e'))),
                      ),
                    ),
            ),
            if (canEdit)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 8, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _field,
                        focusNode: _focus,
                        maxLength: DvLists.maxText,
                        textCapitalization: TextCapitalization.sentences,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _add(),
                        decoration: const InputDecoration(
                          hintText: 'Новый пункт',
                          counterText: '',
                          border: InputBorder.none,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Добавить',
                      icon: const Icon(Icons.add_circle),
                      color: theme.colorScheme.primary,
                      onPressed: _add,
                    ),
                  ],
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                child: Text(
                  'Менять список пока нельзя: права выровняются, когда создатель чата откроет DVChat.',
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 6, right: 8),
          child: Icon(Icons.circle, size: 5),
        ),
        Expanded(child: Text(text)),
      ],
    ),
  );
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({
    required this.room,
    required this.listId,
    required this.item,
    required this.canEdit,
    required this.onError,
  });

  final Room room;
  final String listId;
  final DvListItem item;
  final bool canEdit;
  final void Function(Object error) onError;

  Future<void> _toggle() async {
    try {
      await DvLists.toggle(room, listId, item.id);
    } catch (e) {
      onError(e);
    }
  }

  Future<void> _remove() async {
    try {
      await DvLists.removeItem(room, listId, item.id);
    } catch (e) {
      onError(e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final me = room.client.userID ?? '';
    final doneBy = _who(room, item.doneBy);
    // Отметку чужого пункта-галочки снять нельзя: она неактивна, но видна
    final canToggle = canEdit && item.canUntick(me);
    final canRemove = canEdit && item.canRemove(me);
    return InkWell(
      onTap: canToggle ? _toggle : null,
      child: Padding(
        padding: const EdgeInsets.only(left: 12, right: 4),
        child: Row(
          children: [
            Checkbox(
              value: item.done,
              activeColor: _doneColor,
              onChanged: canToggle ? (_) => _toggle() : null,
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.text,
                      style: item.done
                          ? TextStyle(
                              decoration: TextDecoration.lineThrough,
                              color: theme.colorScheme.onSurfaceVariant,
                            )
                          : null,
                    ),
                    if (item.done && doneBy.isNotEmpty)
                      Text(
                        'отметил(а): $doneBy',
                        style: TextStyle(
                          fontSize: 11,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (canRemove)
              IconButton(
                tooltip: 'Убрать пункт',
                icon: const Icon(Icons.close, size: 18),
                color: theme.colorScheme.onSurfaceVariant,
                onPressed: _remove,
              )
            else
              const SizedBox(width: 48),
          ],
        ),
      ),
    );
  }
}
