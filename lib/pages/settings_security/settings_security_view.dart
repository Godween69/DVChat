// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// DVChat: Экран «Безопасность» (внешний вид): только PIN-код и вход по биометрии.
// Остальные настройки (набор текста, отметки о прочтении, отчёты о сбоях, заблокированные,
// ключи, учётная запись) скрыты: в семейном чате они заданы раз и навсегда.

import 'package:dvchat/config/themes.dart';
import 'package:dvchat/l10n/l10n.dart';
import 'package:dvchat/utils/platform_infos.dart';
import 'package:dvchat/widgets/app_lock.dart';
import 'package:dvchat/widgets/layouts/max_width_body.dart';
import 'package:local_auth/local_auth.dart';
import 'package:material_ui/material_ui.dart';

import 'settings_security.dart';

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
                    'Приложение просит 6-значный PIN при запуске и после сворачивания. '
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
            ],
          ),
        ),
      ),
    );
  }
}
