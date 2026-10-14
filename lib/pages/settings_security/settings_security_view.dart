// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// DVChat: Экран «Безопасность» (внешний вид): PIN-код, вход по биометрии и список устройств
// с кнопкой «Выйти на всех устройствах, кроме этого». Остальные настройки скрыты.

import 'package:dvchat/config/themes.dart';
import 'package:dvchat/l10n/l10n.dart';
import 'package:dvchat/utils/platform_infos.dart';
import 'package:dvchat/widgets/app_lock.dart';
import 'package:dvchat/widgets/layouts/max_width_body.dart';
import 'package:dvchat/widgets/matrix.dart';
import 'package:local_auth/local_auth.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

import 'settings_security.dart';

String _two(int n) => n.toString().padLeft(2, '0');

String _lastSeen(int? ts) {
  if (ts == null || ts <= 0) return 'Давно не был(а) в сети';
  final d = DateTime.fromMillisecondsSinceEpoch(ts);
  return 'Был(а) в сети: ${_two(d.day)}.${_two(d.month)}.${d.year} ${_two(d.hour)}:${_two(d.minute)}';
}

class SettingsSecurityView extends StatelessWidget {
  final SettingsSecurityController controller;

  const SettingsSecurityView(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lock = PlatformInfos.supportsAppLock ? AppLock.of(context) : null;

    return Scaffold(
      appBar: AppBar(
        title: Text(L10n.of(context).security),
        automaticallyImplyLeading: !DvThemes.isColumnMode(context),
        centerTitle: DvThemes.isColumnMode(context),
      ),
      body: ListTileTheme(
        iconColor: theme.colorScheme.onSurface,
        child: MaxWidthBody(
          child: Column(
            children: [
              if (lock == null)
                const ListTile(
                  title: Text(
                    'На этом устройстве блокировка PIN-кодом недоступна',
                  ),
                )
              else ...[
                SwitchListTile.adaptive(
                  value: lock.isActive,
                  title: const Text('PIN-код при входе в приложение'),
                  subtitle: const Text(
                    'Приложение просит PIN (от 4 до 6 цифр) при запуске и после сворачивания. '
                    'После 10 неверных попыток подряд выполняется выход из аккаунта.',
                  ),
                  onChanged: (active) => active
                      ? controller.setAppLockAction()
                      : controller.disableAppLockAction(),
                ),
                if (lock.isActive) ...[
                  FutureBuilder(
                    future: LocalAuthentication().canCheckBiometrics,
                    builder: (context, snapshot) {
                      if (snapshot.data != true) return const SizedBox.shrink();
                      return SwitchListTile.adaptive(
                        value: lock.useBiometrics,
                        onChanged: (_) => controller.toggleBiometrics(),
                        title: const Text('Вход по отпечатку или лицу'),
                        subtitle: const Text('Вместо ввода PIN-кода'),
                      );
                    },
                  ),
                  ListTile(
                    trailing: const Icon(Icons.lock_reset_outlined),
                    title: const Text('Изменить PIN-код'),
                    onTap: controller.setAppLockAction,
                  ),
                ],
              ],
              Divider(color: theme.dividerColor),
              ListTile(
                title: Text(
                  'Устройства',
                  style: TextStyle(
                    color: theme.colorScheme.secondary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                subtitle: const Text(
                  'Войти можно с нескольких устройств сразу. Лишние можно отключить.',
                ),
              ),
              FutureBuilder<List<Device>?>(
                future: controller.devicesFuture,
                builder: (context, snapshot) {
                  final devices = snapshot.data;
                  if (devices == null) {
                    if (snapshot.hasError) {
                      return const ListTile(
                        title: Text('Не удалось загрузить список устройств'),
                      );
                    }
                    return const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(
                        child: CircularProgressIndicator.adaptive(
                          strokeWidth: 2,
                        ),
                      ),
                    );
                  }
                  final myId = Matrix.of(context).client.deviceID;
                  final sorted = [...devices]
                    ..sort((a, b) {
                      if (a.deviceId == myId) return -1;
                      if (b.deviceId == myId) return 1;
                      return (b.lastSeenTs ?? 0).compareTo(a.lastSeenTs ?? 0);
                    });
                  return Column(
                    children: [
                      for (final device in sorted)
                        ListTile(
                          leading: device.deviceId == myId
                              ? const Icon(
                                  Icons.check_circle,
                                  color: Colors.green,
                                )
                              : const Icon(Icons.smartphone_outlined),
                          title: Text(
                            (device.displayName ?? '').isNotEmpty
                                ? device.displayName!
                                : device.deviceId,
                          ),
                          subtitle: Text(
                            device.deviceId == myId
                                ? 'Это устройство'
                                : _lastSeen(device.lastSeenTs),
                          ),
                        ),
                      ListTile(
                        leading: const Icon(Icons.logout, color: Colors.red),
                        title: const Text(
                          'Выйти на всех устройствах, кроме этого',
                          style: TextStyle(color: Colors.red),
                        ),
                        subtitle: devices.length <= 1
                            ? const Text('Других устройств нет')
                            : null,
                        onTap: devices.length <= 1
                            ? null
                            : controller.logoutOthersAction,
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
