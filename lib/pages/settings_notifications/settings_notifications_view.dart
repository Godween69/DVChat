// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// DVChat: Экран «Уведомления» (внешний вид): правила уведомлений.

import 'package:dvchat/config/setting_keys.dart';
import 'package:dvchat/config/themes.dart';
import 'package:dvchat/l10n/l10n.dart';
import 'package:dvchat/widgets/layouts/max_width_body.dart';
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
        automaticallyImplyLeading: !DvThemes.isColumnMode(context),
        centerTitle: DvThemes.isColumnMode(context),
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
            // Правило .m.rule.reaction включено = сервер не шлёт уведомления о реакциях
            final reactionRule =
                (client.globalPushRules?.override ?? const <PushRule>[])
                    .where((rule) => rule.ruleId == '.m.rule.reaction')
                    .firstOrNull;
            final reactionsOn =
                !(reactionRule?.enabled ?? false) &&
                AppSettings.notifyAboutReactions.value;
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
                ListTile(
                  title: const Text('Уведомления о реакциях'),
                  trailing: Switch.adaptive(
                    value: reactionsOn,
                    onChanged: controller.isLoading
                        ? null
                        : controller.setReactionNotifications,
                  ),
                ),
                ListTile(
                  title: const Text(
                    'Хочу получать уведомления о прочтении посланных сообщений',
                  ),
                  subtitle: const Text(
                    'Придёт уведомление, когда собеседник прочитал ваше сообщение (в личных чатах, если у него свежая версия приложения)',
                  ),
                  trailing: Switch.adaptive(
                    value: AppSettings.notifyAboutReadReceipts.value,
                    onChanged: controller.setReadReceiptNotifications,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
