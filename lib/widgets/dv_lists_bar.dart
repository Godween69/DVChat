// SPDX-License-Identifier: AGPL-3.0-or-later

// DVChat: общие списки в личном чате (покупки, дела). Над полем ввода торчат «папочки»: по одной на список,
// с названием и счётчиком («3/8») или зелёной галочкой «Выполнен». Нажатие открывает панель со списком:
// пункты с галочками, поле нового пункта. Оба участника видят изменения сразу.
// Логика и хранение: utils/dv_lists.dart.

import 'package:dvchat/utils/adaptive_bottom_sheet.dart';
import 'package:dvchat/utils/dv_lists.dart';
import 'package:dvchat/widgets/adaptive_dialogs/show_text_input_dialog.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

const Color _doneColor = Color(0xFF34B27B);

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
    hintText: 'Например, Покупки',
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

// =============================================================== лента «папочек»

class DvListsBar extends StatelessWidget {
  const DvListsBar(this.room, {super.key});

  final Room room;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<SyncUpdate>(
      stream: room.client.onSync.stream,
      builder: (context, snapshot) => ValueListenableBuilder<int>(
        valueListenable: DvLists.tick,
        builder: (context, tick, child) {
          final lists = DvLists.visible(room);
          if (lists.isEmpty) return const SizedBox.shrink();
          return SizedBox(
            height: 36,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(30, 0, 14, 0),
              children: [
                for (final list in lists)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: _ListTab(room: room, list: list),
                  ),
                if (DvLists.canEdit(room)) _AddTab(room),
              ],
            ),
          );
        },
      ),
    );
  }
}

const BorderRadius _tabShape = BorderRadius.vertical(top: Radius.circular(14));

class _ListTab extends StatelessWidget {
  const _ListTab({required this.room, required this.list});

  final Room room;
  final DvList list;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final done = list.complete;
    return Material(
      color: theme.colorScheme.surfaceContainer,
      borderRadius: _tabShape,
      child: InkWell(
        borderRadius: _tabShape,
        onTap: () => dvOpenList(context, room, list.id),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                done ? Icons.check_circle : Icons.checklist_rounded,
                size: 17,
                color: done ? _doneColor : theme.colorScheme.primary,
              ),
              const SizedBox(width: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 130),
                child: Text(
                  list.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                done
                    ? 'Выполнен'
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
    );
  }
}

class _AddTab extends StatelessWidget {
  const _AddTab(this.room);

  final Room room;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainer,
      borderRadius: _tabShape,
      child: InkWell(
        borderRadius: _tabShape,
        onTap: () => dvCreateList(context, room),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Tooltip(
            message: 'Новый список',
            child: Icon(
              Icons.add,
              size: 20,
              color: theme.colorScheme.onSurfaceVariant,
            ),
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

  Future<void> _hide(DvList list) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Убрать список у себя?'),
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
    await _run(() => DvLists.hide(widget.room, list));
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
    final canEdit = DvLists.canEdit(room);
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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          list.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleLarge,
                        ),
                        Text(
                          complete
                              ? 'Выполнен'
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
                  PopupMenuButton<String>(
                    tooltip: 'Действия со списком',
                    onSelected: (value) {
                      switch (value) {
                        case 'rename':
                          _rename(list);
                        case 'clear':
                          _run(() => DvLists.clearDone(room, list.id));
                        case 'hide':
                          _hide(list);
                      }
                    },
                    itemBuilder: (context) => [
                      if (canEdit)
                        const PopupMenuItem(
                          value: 'rename',
                          child: Text('Переименовать'),
                        ),
                      if (canEdit && list.doneCount > 0)
                        const PopupMenuItem(
                          value: 'clear',
                          child: Text('Убрать выполненные'),
                        ),
                      const PopupMenuItem(
                        value: 'hide',
                        child: Text('Убрать список у меня'),
                      ),
                    ],
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
                        ).showSnackBar(SnackBar(content: Text('Не получилось: $e'))),
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
    final doneBy = _who(room, item.doneBy);
    return InkWell(
      onTap: canEdit ? _toggle : null,
      child: Padding(
        padding: const EdgeInsets.only(left: 12, right: 4),
        child: Row(
          children: [
            Checkbox(
              value: item.done,
              activeColor: _doneColor,
              onChanged: canEdit ? (_) => _toggle() : null,
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
            if (canEdit)
              IconButton(
                tooltip: 'Убрать пункт',
                icon: const Icon(Icons.close, size: 18),
                color: theme.colorScheme.onSurfaceVariant,
                onPressed: _remove,
              ),
          ],
        ),
      ),
    );
  }
}
