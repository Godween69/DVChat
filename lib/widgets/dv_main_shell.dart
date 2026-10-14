// SPDX-License-Identifier: AGPL-3.0-or-later

// DVChat: нижняя панель вкладок на телефоне: «Чаты», «Друзья», «Игры».
// Панель видна только на этих трёх экранах и прячется внутри чата, настроек и игр.
// На широком экране (планшет, веб) ничего не меняется: там боковая панель.
// Вид панели следует оформлению списков: обычный (без заливки, в цвет страницы),
// плашки (парящая «таблетка» с лёгкой тенью) и рамки (то же с тонкой обводкой).

import 'package:dvchat/config/themes.dart';
import 'package:dvchat/utils/dv_list_style.dart';
import 'package:dvchat/utils/room_archive_extension.dart';
import 'package:dvchat/widgets/matrix.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

class DvMainShell extends StatelessWidget {
  const DvMainShell({required this.path, required this.child, super.key});

  /// Текущий адрес (например /rooms/friends)
  final String path;
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
  Widget build(BuildContext context) {
    if (DvThemes.isColumnMode(context)) return child;
    final index = indexFor(path);
    return Scaffold(
      // Клавиатуру обрабатывают сами экраны внутри
      resizeToAvoidBottomInset: false,
      body: child,
      bottomNavigationBar: index == null
          ? null
          : _DvTabBar(
              index: index,
              onSelect: (i) {
                if (i != index) context.go(_paths[i]);
              },
            ),
    );
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
  Widget build(BuildContext context) {
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
