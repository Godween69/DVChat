// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// DVChat: Экран «Уведомления» (логика): правила уведомлений.

import 'package:dvchat/config/setting_keys.dart';
import 'package:dvchat/utils/localized_exception_extension.dart';
import 'package:dvchat/utils/reaction_push_rule.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

import '../../widgets/matrix.dart';
import 'settings_notifications_view.dart';

class SettingsNotifications extends StatefulWidget {
  const SettingsNotifications({super.key});

  @override
  SettingsNotificationsController createState() =>
      SettingsNotificationsController();
}

class SettingsNotificationsController extends State<SettingsNotifications> {
  bool isLoading = false;

  // DVChat: единственное действие экрана, включить или выключить одно правило уведомлений
  Future<void> togglePushRule(PushRuleKind kind, PushRule pushRule) async {
    setState(() {
      isLoading = true;
    });
    try {
      final updateFromSync = Matrix.of(context).client.onSync.stream
          .where(
            (syncUpdate) =>
                syncUpdate.accountData?.any(
                  (accountData) => accountData.type == 'm.push_rules',
                ) ??
                false,
          )
          .first;
      await Matrix.of(
        context,
      ).client.setPushRuleEnabled(kind, pushRule.ruleId, !pushRule.enabled);
      await updateFromSync;
    } catch (e, s) {
      Logs().w('Unable to toggle push rule', e, s);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toLocalizedString(context))));
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  // DVChat: уведомления о реакциях — локальная настройка плюс серверное правило.
  // При «вкл» добавляется своё серверное правило dvchat.reaction, стандартное .m.rule.reaction отключается.
  Future<void> setReactionNotifications(bool on) async {
    setState(() {
      isLoading = true;
    });
    try {
      final client = Matrix.of(context).client;
      await AppSettings.notifyAboutReactions.setItem(on);
      await syncReactionPushRule(client, on: on);
    } catch (e, s) {
      Logs().w('Unable to toggle reaction notifications', e, s);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toLocalizedString(context))));
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  // DVChat: уведомления о прочтении посланных мной сообщений (пока только сохраняет выбор)
  Future<void> setReadReceiptNotifications(bool on) async {
    await AppSettings.notifyAboutReadReceipts.setItem(on);
    if (!mounted) return;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) => SettingsNotificationsView(this);
}
