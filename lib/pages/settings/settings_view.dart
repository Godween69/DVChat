// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// DVChat: Экран «Настройки» (внешний вид): главная страница настроек.

import 'package:dvchat/l10n/l10n.dart';
import 'package:dvchat/pages/profile/dv_profile_page.dart';
import 'package:dvchat/utils/platform_infos.dart';
import 'package:dvchat/utils/update_checker.dart';
import 'package:dvchat/widgets/avatar.dart';
import 'package:dvchat/widgets/dv_my_id.dart';
import 'package:dvchat/widgets/matrix.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'settings.dart';

/// DVChat: настройки пользователя: профиль, персонализация, уведомления, чат, выход.
class SettingsView extends StatefulWidget {
  final SettingsController controller;

  const SettingsView(this.controller, {super.key});

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  SettingsController get controller => widget.controller;

  /// Размер маленькой аватарки вверху (от неё профиль «вылетает» к центру)
  static const double _avatarSize = 48;

  /// По этому ключу находим место аватарки на экране (откуда «вылетает» профиль).
  /// Ключ свой у каждой копии экрана, чтобы две копии не конфликтовали.
  final GlobalKey _avatarKey = GlobalKey();

  /// Открывает свой профиль: большая аватарка плавно «вылетает» от маленькой
  Future<void> _openProfile(BuildContext context, String mxid) async {
    Rect? from;
    final box = _avatarKey.currentContext?.findRenderObject();
    if (box is RenderBox && box.hasSize) {
      from = box.localToGlobal(Offset.zero) & box.size;
    }
    await DvProfilePage.open(context, mxid, from: from);
    if (!mounted || !controller.mounted) return;
    controller.updateProfile();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final activeRoute = GoRouter.of(
      context,
    ).routeInformationProvider.value.uri.path;

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 84,
        title: Text(L10n.of(context).settings),
        leading: Center(
          child: BackButton(onPressed: () => context.go('/rooms')),
        ),
        actions: [
          FutureBuilder<Profile>(
            future: controller.profileFuture,
            builder: (context, snapshot) {
              final profile = snapshot.data;
              final mxid =
                  Matrix.of(context).client.userID ?? L10n.of(context).user;
              final displayname =
                  profile?.displayName ?? mxid.localpart ?? mxid;
              return InkWell(
                splashColor: Colors.transparent,
                highlightColor: Colors.transparent,
                onTap: () => _openProfile(context, mxid),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      KeyedSubtree(
                        key: _avatarKey,
                        child: Avatar(
                          mxContent: profile?.avatarUrl,
                          name: displayname,
                          size: _avatarSize,
                        ),
                      ),
                      const SizedBox(height: 3),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 90),
                        child: Text(
                          displayname,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 11,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: ListTileTheme(
        iconColor: theme.colorScheme.onSurface,
        child: ListView(
          key: const Key('SettingsListViewContent'),
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.person_outline),
              title: const Text('Профиль'),
              onTap: () =>
                  _openProfile(context, Matrix.of(context).client.userID ?? ''),
            ),
            const DvMyIdTile(),
            ListTile(
              leading: const Icon(Icons.format_paint_outlined),
              title: Text(L10n.of(context).changeTheme),
              tileColor: activeRoute.startsWith('/rooms/settings/style')
                  ? theme.colorScheme.surfaceContainerHigh
                  : null,
              onTap: () => context.go('/rooms/settings/style'),
            ),
            ListTile(
              leading: const Icon(Icons.lock_outline),
              title: Text(L10n.of(context).security),
              tileColor: activeRoute.startsWith('/rooms/settings/security')
                  ? theme.colorScheme.surfaceContainerHigh
                  : null,
              onTap: () => context.go('/rooms/settings/security'),
            ),
            ListTile(
              leading: const Icon(Icons.notifications_outlined),
              title: Text(L10n.of(context).notifications),
              tileColor: activeRoute.startsWith('/rooms/settings/notifications')
                  ? theme.colorScheme.surfaceContainerHigh
                  : null,
              onTap: () => context.go('/rooms/settings/notifications'),
            ),
            ListTile(
              leading: const Icon(Icons.forum_outlined),
              title: Text(L10n.of(context).chat),
              onTap: () => context.go('/rooms/settings/chat'),
              tileColor: activeRoute.startsWith('/rooms/settings/chat')
                  ? theme.colorScheme.surfaceContainerHigh
                  : null,
            ),
            ListTile(
              leading: const Icon(Icons.feedback_outlined),
              title: const Text('Обратная связь'),
              onTap: () => context.go('/rooms/settings/feedback'),
              tileColor: activeRoute.startsWith('/rooms/settings/feedback')
                  ? theme.colorScheme.surfaceContainerHigh
                  : null,
            ),
            if (PlatformInfos.isAndroid)
              FutureBuilder<PackageInfo>(
                future: PackageInfo.fromPlatform(),
                builder: (context, snapshot) {
                  final info = snapshot.data;
                  return ListTile(
                    leading: const Icon(Icons.system_update_outlined),
                    title: const Text('Проверить обновление'),
                    subtitle: info == null
                        ? null
                        : Text('Версия ${info.version} (${info.buildNumber})'),
                    onTap: () => DvUpdateChecker.check(context, manual: true),
                  );
                },
              ),
            Divider(color: theme.dividerColor),
            ListTile(
              leading: const Icon(Icons.logout_outlined),
              title: const Text('Выйти из аккаунта'),
              onTap: controller.logoutAction,
            ),
          ],
        ),
      ),
    );
  }
}
