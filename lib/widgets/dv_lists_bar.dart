// SPDX-License-Identifier: AGPL-3.0-or-later

// DVChat: общие списки в личном чате (покупки, дела). Над полем ввода торчат «папочки»: слева всегда
// плюс (создать список), дальше по одной вкладке на список: цветная, полупрозрачная, с названием и счётчиком
// («3/8»). У выполненного списка рядом с названием зелёная галочка, название блекнет, счётчика нет. Нажатие открывает
// панель со списком, долгое нажатие на выполненный список убирает его у себя.
// Логика, правила и хранение: utils/dv_lists.dart.

import 'package:dvchat/utils/adaptive_bottom_sheet.dart';
import 'package:dvchat/utils/dv_lists.dart';
import 'package:dvchat/widgets/dv_glass.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

const Color _doneColor = Color(0xFF34B27B);

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
  final title = await showDialog<String>(
    context: context,
    builder: (_) => const _NameDialog(
      title: 'Новый список',
      hint: 'Например, Покупки или Дела',
      okLabel: 'Создать',
    ),
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

/// Закрывает клавиатуру и ждёт, пока она уйдёт (до ~0,6 с). Без этого лист появлялся над
/// ещё открытой клавиатурой, а потом «уезжал» за верх экрана, когда клавиатура пряталась.
Future<void> _dvHideKeyboard(BuildContext context) async {
  final view = WidgetsBinding.instance.platformDispatcher.views.first;
  if (view.viewInsets.bottom <= 0) return;
  FocusManager.instance.primaryFocus?.unfocus();
  for (var i = 0; i < 12 && view.viewInsets.bottom > 0; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

Future<void> dvOpenList(
  BuildContext context,
  Room room,
  String listId, {
  bool focusNew = false,
}) async {
  // Если сразу ставим курсор в поле листа, клавиатура и так понадобится: ждать не нужно
  if (!focusNew) await _dvHideKeyboard(context);
  if (!context.mounted) return;
  await showAdaptiveBottomSheet<void>(
    context: context,
    builder: (_) => DvListSheet(room: room, listId: listId, focusNew: focusNew),
  );
}

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

/// Окно с одним полем (название списка): в общем полупрозрачном стиле, кнопка активна, когда поле не пустое.
class _NameDialog extends StatefulWidget {
  const _NameDialog({
    required this.title,
    required this.okLabel,
    this.hint,
    this.initial = '',
  });

  final String title;
  final String okLabel;
  final String? hint;
  final String initial;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final TextEditingController _c = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _submit() {
    final t = _c.text.trim();
    if (t.isNotEmpty) Navigator.of(context).pop(t);
  }

  @override
  Widget build(BuildContext context) => DvGlassDialog(
    title: widget.title,
    child: TextField(
      controller: _c,
      autofocus: true,
      maxLength: DvLists.maxTitle,
      textCapitalization: TextCapitalization.sentences,
      decoration: InputDecoration(
        hintText: widget.hint,
        counterText: '',
        border: const OutlineInputBorder(),
      ),
      onChanged: (_) => setState(() {}),
      onSubmitted: (_) => _submit(),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Отмена'),
      ),
      FilledButton(
        onPressed: _c.text.trim().isEmpty ? null : _submit,
        child: Text(widget.okLabel),
      ),
    ],
  );
}

// =============================================================== лента «папочек»

// Вкладки низкие, вплотную друг к другу и нижним краем заходят за панель ввода: будто воткнуты за неё.
const double _tabHeight = 30; // было 22 -> 25 -> 30 (ещё выше на 20%)
const double _tabTuck = 6; // насколько вкладка уходит за панель ввода
const BorderRadius _tabShape = BorderRadius.vertical(top: Radius.circular(11));

/// Заливка вкладки: цвет панели ввода при 50% прозрачности
Color _tabFill(BuildContext context) =>
    Theme.of(context).colorScheme.surfaceContainer.withAlpha(128);

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
          // Место под тень сверху; лента сдвинута вниз на _tabTuck, чтобы вкладки уходили за панель
          return Transform.translate(
            offset: const Offset(0, _tabTuck),
            child: SizedBox(
              height: _tabHeight + 8,
              child: ListView(
                scrollDirection: Axis.horizontal,
                clipBehavior: Clip.none,
                padding: const EdgeInsets.fromLTRB(22, 8, 14, 0),
                children: [
                  _AddTab(room),
                  if (lists.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(left: 12),
                      child: Align(
                        alignment: Alignment.topLeft,
                        child: Text(
                          'Создай список дел или покупок',
                          style: TextStyle(
                            fontSize: 12.5,
                            height: 1.2,
                            color: theme.colorScheme.onSurface.withAlpha(105),
                          ),
                        ),
                      ),
                    ),
                  for (final list in lists) _ListTab(room: room, list: list),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Общая «плашка» вкладки: полупрозрачная, без окантовки, с мягкой тенью
class _TabShell extends StatelessWidget {
  const _TabShell({required this.child, this.onTap, this.onLongPress});

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topLeft,
    child: Material(
      color: _tabFill(context),
      elevation: 3,
      shadowColor: Colors.black,
      shape: const RoundedRectangleBorder(borderRadius: _tabShape),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: SizedBox(
          height: _tabHeight,
          // Нижние _tabTuck пикселей прячутся за панель, поэтому текст стоит выше середины
          child: Padding(
            padding: const EdgeInsets.fromLTRB(11, 0, 11, _tabTuck),
            child: child,
          ),
        ),
      ),
    ),
  );
}

class _ListTab extends StatelessWidget {
  const _ListTab({required this.room, required this.list});

  final Room room;
  final DvList list;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final done = list.complete;
    final base = theme.colorScheme.onSurface;
    // Выполненный список: рядом с названием зелёная галочка, название блеклое, счётчика нет
    return _TabShell(
      onTap: () => dvOpenList(context, room, list.id),
      onLongPress: () => dvHideList(context, room, list),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (done) ...[
            const Icon(Icons.check, size: 13, color: _doneColor),
            const SizedBox(width: 4),
          ],
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 110),
            child: Text(
              list.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                height: 1.1,
                fontWeight: FontWeight.w600,
                color: done ? base.withAlpha(110) : base,
              ),
            ),
          ),
          if (!done) ...[
            const SizedBox(width: 6),
            Text(
              list.total == 0 ? 'пусто' : '${list.doneCount}/${list.total}',
              style: TextStyle(
                fontSize: 11,
                height: 1.1,
                color: base.withAlpha(140),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _AddTab extends StatelessWidget {
  const _AddTab(this.room);

  final Room room;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: 'Новый список',
    child: _TabShell(
      onTap: () => dvCreateList(context, room),
      child: Icon(
        Icons.add,
        size: 16,
        color: Theme.of(context).colorScheme.primary,
      ),
    ),
  );
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
    final title = await showDialog<String>(
      context: context,
      builder: (_) => _NameDialog(
        title: 'Название списка',
        initial: list.title,
        okLabel: 'Сохранить',
      ),
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
                'Когда всё отмечено, у вкладки появляется зелёная галочка, а название блекнет. '
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
                                  style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
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
                                ? 'Всё отмечено'
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
                      padding: const EdgeInsets.only(top: 10, bottom: 6),
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
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(26),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(left: 18),
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
                      ),
                      IconButton(
                        tooltip: 'Добавить',
                        icon: const Icon(Icons.arrow_upward_rounded),
                        style: IconButton.styleFrom(
                          backgroundColor: theme.colorScheme.primary,
                          foregroundColor: theme.colorScheme.onPrimary,
                        ),
                        onPressed: _add,
                      ),
                      const SizedBox(width: 4),
                    ],
                  ),
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
    // Снять чужую отметку нельзя: пункт остаётся отмеченным и не реагирует на нажатие
    final canToggle = canEdit && item.canUntick(me);
    final canRemove = canEdit && item.canRemove(me);
    final faded = theme.colorScheme.onSurface.withAlpha(115);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
      child: Material(
        color: theme.colorScheme.surfaceContainerHigh.withAlpha(
          item.done ? 110 : 255,
        ),
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: canToggle ? _toggle : null,
          child: Padding(
            padding: const EdgeInsets.only(left: 14, right: 4),
            child: Row(
              children: [
                // Круглая отметка
                AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: item.done ? _doneColor : Colors.transparent,
                    border: Border.all(
                      color: item.done
                          ? _doneColor
                          : theme.colorScheme.onSurface.withAlpha(110),
                      width: 2,
                    ),
                  ),
                  child: item.done
                      ? const Icon(Icons.check, size: 16, color: Colors.white)
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    child: Text(
                      item.text,
                      style: TextStyle(
                        fontSize: 15.5,
                        decoration: item.done
                            ? TextDecoration.lineThrough
                            : null,
                        color: item.done ? faded : null,
                      ),
                    ),
                  ),
                ),
                if (canRemove)
                  IconButton(
                    tooltip: 'Убрать пункт',
                    icon: const Icon(Icons.close, size: 18),
                    color: faded,
                    onPressed: _remove,
                  )
                else
                  const SizedBox(width: 12),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
