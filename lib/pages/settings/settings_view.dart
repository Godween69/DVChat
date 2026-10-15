// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// DVChat: Экран «Настройки» (внешний вид): главная страница настроек.

import 'package:dvchat/l10n/l10n.dart';
import 'package:dvchat/pages/profile/dv_profile_page.dart';
import 'package:dvchat/utils/platform_infos.dart';
import 'package:dvchat/utils/update_checker.dart';
import 'package:dvchat/widgets/dv_settings_header.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
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
        title: Text(L10n.of(context).settings),
        leading: Center(
          child: BackButton(onPressed: () => context.go('/rooms')),
        ),
      ),
      body: ListTileTheme(
        iconColor: theme.colorScheme.onSurface,
        child: ListView(
          key: const Key('SettingsListViewContent'),
          children: <Widget>[
            DvSettingsHeader(
              profileFuture: controller.profileFuture,
              avatarKey: _avatarKey,
              onOpenProfile: (mxid) => _openProfile(context, mxid),
            ),
            Divider(height: 1, color: theme.dividerColor),
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
