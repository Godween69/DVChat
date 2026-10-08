// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/l10n/l10n.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'chat_list.dart';

/// DVChat: шестерёнка справа вверху с меню из трёх пунктов.
class ClientChooserButton extends StatelessWidget {
  final ChatListController controller;

  const ClientChooserButton(this.controller, {super.key});

  PopupMenuItem<SettingsAction> _item(
    SettingsAction action,
    IconData icon,
    String title,
  ) => PopupMenuItem(
    value: action,
    child: Row(children: [Icon(icon), const SizedBox(width: 18), Text(title)]),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return PopupMenuButton<SettingsAction>(
      key: const Key('accounts_and_settings_buttons'),
      tooltip: l10n.settings,
      icon: const Icon(Icons.settings_outlined),
      onSelected: (action) => _selected(action, context),
      itemBuilder: (context) => [
        _item(SettingsAction.setStatus, Icons.edit_outlined, l10n.setStatus),
        _item(SettingsAction.archive, Icons.archive_outlined, l10n.archive),
        _item(SettingsAction.settings, Icons.settings_outlined, l10n.settings),
      ],
    );
  }

  void _selected(SettingsAction action, BuildContext context) {
    switch (action) {
      case SettingsAction.setStatus:
        controller.setStatus();
        break;
      case SettingsAction.archive:
        context.go('/rooms/archive');
        break;
      case SettingsAction.settings:
        context.go('/rooms/settings');
        break;
    }
  }
}

enum SettingsAction { setStatus, archive, settings }
