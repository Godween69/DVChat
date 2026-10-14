// SPDX-License-Identifier: AGPL-3.0-or-later

// DVChat: нижняя панель вкладок на телефоне: «Чаты», «Друзья», «Игры».
// Панель видна только на этих трёх экранах и прячется внутри чата, настроек и игр.
// На широком экране (планшет, веб) ничего не меняется: там боковая панель.

import 'package:dvchat/config/themes.dart';
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
          : NavigationBar(
              selectedIndex: index,
              onDestinationSelected: (i) {
                if (i != index) context.go(_paths[i]);
              },
              destinations: const [
                NavigationDestination(
                  icon: _ChatsIcon(selected: false),
                  selectedIcon: _ChatsIcon(selected: true),
                  label: 'Чаты',
                ),
                NavigationDestination(
                  icon: Icon(Icons.people_outline),
                  selectedIcon: Icon(Icons.people),
                  label: 'Друзья',
                ),
                NavigationDestination(
                  icon: Icon(Icons.sports_esports_outlined),
                  selectedIcon: Icon(Icons.sports_esports),
                  label: 'Игры',
                ),
              ],
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
