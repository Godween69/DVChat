// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/widgets/layouts/max_width_body.dart';
import 'package:fluffychat/widgets/settings_switch_list_tile.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

import '../../widgets/matrix.dart';
import 'settings_notifications.dart';

class SettingsNotificationsView extends StatelessWidget {
  final SettingsNotificationsController controller;

  const SettingsNotificationsView(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !FluffyThemes.isColumnMode(context),
        centerTitle: FluffyThemes.isColumnMode(context),
        title: Text(L10n.of(context).notifications),
      ),
      body: MaxWidthBody(
        child: StreamBuilder(
          stream: Matrix.of(context).client.onSync.stream.where(
            (syncUpdate) =>
                syncUpdate.accountData?.any(
                  (accountData) => accountData.type == 'm.push_rules',
                ) ??
                false,
          ),
          builder: (context, _) {
            final client = Matrix.of(context).client;
            // Правило master при включении ОТКЛЮЧАЕТ все уведомления
            final master =
                (client.globalPushRules?.override ?? const <PushRule>[])
                    .where((rule) => rule.ruleId == '.m.rule.master')
                    .firstOrNull;
            final muted = master?.enabled ?? false;
            return Column(
              children: [
                ListTile(
                  title: const Text('Уведомления'),
                  subtitle: const Text(
                    'Выключатель перекрывает все остальные правила',
                  ),
                  trailing: Switch.adaptive(
                    value: !muted,
                    onChanged: controller.isLoading || master == null
                        ? null
                        : (_) => controller.togglePushRule(
                            PushRuleKind.override,
                            master,
                          ),
                  ),
                ),
                SettingsSwitchListTile.adaptive(
                  title: 'Уведомления о реакциях',
                  setting: AppSettings.notifyAboutReactions,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
