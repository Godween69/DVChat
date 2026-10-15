// SPDX-License-Identifier: AGPL-3.0-or-later

// DVChat: нижняя панель вкладок на телефоне: «Чаты», «Друзья», «Игры».
// Панель видна только на этих трёх экранах и прячется внутри чата, настроек и игр.
// На широком экране (планшет, веб) ничего не меняется: там боковая панель.
// Вид панели следует оформлению списков: обычный (без заливки, в цвет страницы),
// плашки (парящая «таблетка» с лёгкой тенью) и рамки (то же с тонкой обводкой).

import 'dart:async';

import 'package:dvchat/config/themes.dart';
import 'package:dvchat/pages/chat_list/chat_list.dart';
import 'package:dvchat/pages/friends/friends_page.dart';
import 'package:dvchat/pages/games/games_page.dart';
import 'package:dvchat/utils/dv_list_style.dart';
import 'package:dvchat/utils/room_archive_extension.dart';
import 'package:dvchat/widgets/matrix.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

/// Каркас телефона: три вкладки в общем PageView (листаются свайпом за пальцем)
/// и нижняя панель. Маршруты вкладок в роутере пустые, сами экраны живут здесь,
/// поэтому прокрутка и состояние вкладок сохраняются. Остальные экраны (чат,
/// настройки, архив) открываются поверх через [child].
class DvMainShell extends StatefulWidget {
  const DvMainShell({required this.path, required this.child, super.key});

  /// Текущий адрес (например /rooms/friends)
  final String path;

  /// Страница текущего маршрута (на вкладках пустая)
  final Widget child;

  static const List<String> _paths = [
    '/rooms',
    '/rooms/friends',
    '/rooms/games',
  ];

  static int? indexFor(String path) {
    final clean = path.length > 1 && path.endsWith('/')
        ? path.substring(0, path.length - 1)
        : path;
    final i = _paths.indexOf(clean);
    return i < 0 ? null : i;
  }

  @override
  State<DvMainShell> createState() => _DvMainShellState();
}

class _DvMainShellState extends State<DvMainShell> {
  late final PageController _controller;
  int _page = 0;

  /// Идёт прокрутка от нажатия на панель: промежуточные страницы адрес не меняют
  bool _animating = false;

  @override
  void initState() {
    super.initState();
    _page = DvMainShell.indexFor(widget.path) ?? 0;
    _controller = PageController(initialPage: _page);
  }

  @override
  void didUpdateWidget(DvMainShell old) {
    super.didUpdateWidget(old);
    final i = DvMainShell.indexFor(widget.path);
    if (i == null || i == _page) return;
    final cameFromTab = DvMainShell.indexFor(old.path) != null;
    _page = i;
    _showPage(i, animate: cameFromTab);
  }

  void _showPage(int i, {required bool animate}) {
    if (!_controller.hasClients) return;
    if (!animate) {
      _controller.jumpToPage(i);
      return;
    }
    _animating = true;
    unawaited(
      _controller
          .animateToPage(
            i,
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
          )
          .whenComplete(() => _animating = false),
    );
  }

  /// Страница сменилась свайпом: подтягиваем адрес
  void _onPageChanged(int i) {
    if (_animating || i == _page) return;
    setState(() => _page = i);
    context.go(DvMainShell._paths[i]);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (DvThemes.isColumnMode(context)) return widget.child;
    final onTab = DvMainShell.indexFor(widget.path) != null;
    // Пока открыта клавиатура, панель прячется (как в Telegram), иначе экран сжимается лишний раз
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    return Scaffold(
      // Клавиатуру обрабатывают сами экраны внутри
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          Positioned.fill(
            child: PageView(
              controller: _controller,
              onPageChanged: _onPageChanged,
              // Когда сверху открыт чат или настройки, листать вкладки нельзя
              physics: onTab ? null : const NeverScrollableScrollPhysics(),
              children: [
                _TabFx(
                  controller: _controller,
                  index: 0,
                  child: const _KeepAlive(child: ChatList(activeChat: null)),
                ),
                _TabFx(
                  controller: _controller,
                  index: 1,
                  child: const _KeepAlive(child: FriendsPage()),
                ),
                _TabFx(
                  controller: _controller,
                  index: 2,
                  child: const _KeepAlive(child: GamesPage()),
                ),
              ],
            ),
          ),
          // Слой роутера на вкладках пустой, но его Navigator (ModalBarrier) глотает
          // все касания и не пускает их к вкладкам под ним. Поэтому на вкладках он глухой
          Positioned.fill(
            child: IgnorePointer(ignoring: onTab, child: widget.child),
          ),
        ],
      ),
      bottomNavigationBar: !onTab || keyboardOpen
          ? null
          : _DvTabBar(
              index: _page,
              onSelect: (i) {
                if (i != _page) context.go(DvMainShell._paths[i]);
              },
            ),
    );
  }
}

/// Не даёт PageView выгружать вкладку, когда её не видно (сохраняет прокрутку)
class _KeepAlive extends StatefulWidget {
  const _KeepAlive({required this.child});

  final Widget child;

  @override
  State<_KeepAlive> createState() => _KeepAliveState();
}

class _KeepAliveState extends State<_KeepAlive>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

class _DvTabBar extends StatelessWidget {
  const _DvTabBar({required this.index, required this.onSelect});

  final int index;
  final ValueChanged<int> onSelect;

  static const double _height = 54;
  static const List<String> _labels = ['Чаты', 'Друзья', 'Игры'];

  Widget _icon(int i, bool selected) => switch (i) {
    0 => _ChatsIcon(selected: selected),
    1 => Icon(selected ? Icons.people : Icons.people_outline),
    _ => Icon(selected ? Icons.sports_esports : Icons.sports_esports_outlined),
  };

  Widget _tab(ThemeData theme, int i) {
    final selected = i == index;
    final color = selected
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurfaceVariant;
    return InkResponse(
      onTap: () => onSelect(i),
      radius: 36,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconTheme(
            data: IconThemeData(color: color, size: 22),
            child: _icon(i, selected),
          ),
          const SizedBox(height: 2),
          Text(
            _labels[i],
            style: TextStyle(
              fontSize: 11,
              height: 1.1,
              color: color,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
    valueListenable: DvListStyle.revision,
    builder: (context, _, _) => _bar(context),
  );

  Widget _bar(BuildContext context) {
    final theme = Theme.of(context);
    final row = SizedBox(
      height: _height,
      child: Row(
        children: [
          for (var i = 0; i < _labels.length; i++)
            Expanded(child: _tab(theme, i)),
        ],
      ),
    );

    // Обычный вид: без заливки, линии и тени, в цвет страницы
    if (DvListStyle.isPlain) {
      return Material(
        color: theme.scaffoldBackgroundColor,
        surfaceTintColor: Colors.transparent,
        child: SafeArea(top: false, child: row),
      );
    }

    // Плашки и рамки: отдельная «таблетка», висящая над нижним краем
    final base = DvListStyle.shape(context);
    final side = base is RoundedRectangleBorder ? base.side : BorderSide.none;
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Material(
        color: DvListStyle.fill(context),
        elevation: DvListStyle.mode == DvListStyle.plates
            ? 0.5 + 3 * DvListStyle.contrast
            : 0,
        shadowColor: Colors.black,
        surfaceTintColor: Colors.transparent,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_height / 2),
          side: side,
        ),
        child: row,
      ),
    );
  }
}

/// Значок «Чаты» с числом чатов, где есть непрочитанные
class _ChatsIcon extends StatelessWidget {
  const _ChatsIcon({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    final client = Matrix.of(context).client;
    final icon = Icon(selected ? Icons.chat_bubble : Icons.chat_bubble_outline);
    return StreamBuilder(
      stream: client.onSync.stream.where((s) => s.hasRoomUpdate),
      builder: (context, _) {
        final unread = client.rooms
            .where(
              (r) =>
                  r.membership == Membership.join &&
                  r.notificationCount > 0 &&
                  !r.isInArchive &&
                  !r.isHiddenByUser &&
                  r.isAbandonedDMRoom != true &&
                  !r.isNewcomerPlaceholder,
            )
            .length;
        if (unread == 0) return icon;
        return Badge(label: Text('$unread'), child: icon);
      },
    );
  }
}

/// Эффект листания вкладок как на рабочих столах Android: уходящая вкладка гаснет
/// и чуть уменьшается, приходящая проявляется. Содержимое при этом не перестраивается.
class _TabFx extends StatelessWidget {
  const _TabFx({
    required this.controller,
    required this.index,
    required this.child,
  });

  final PageController controller;
  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    child: child,
    builder: (context, child) {
      final page = controller.hasClients && controller.position.haveDimensions
          ? (controller.page ?? index)
          : controller.initialPage;
      final d = (page - index).abs().clamp(0.0, 1.0);
      return Opacity(
        opacity: (1 - d * 1.15).clamp(0.0, 1.0),
        child: Transform.scale(scale: 1 - 0.1 * d, child: child),
      );
    },
  );
}
