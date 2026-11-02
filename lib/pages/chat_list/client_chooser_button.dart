// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// DVChat: Кнопка переключения между аккаунтами.

import 'package:dvchat/l10n/l10n.dart';
import 'package:dvchat/widgets/dv_glass.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'chat_list.dart';

/// DVChat: шестерёнка справа вверху с меню из трёх пунктов.
class ClientChooserButton extends StatelessWidget {
  final ChatListController controller;

  const ClientChooserButton(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    // DVChat: стеклянное меню с цветными значками
    return Builder(
      builder: (anchor) => IconButton(
        key: const Key('accounts_and_settings_buttons'),
        tooltip: l10n.settings,
        icon: const Icon(Icons.settings_outlined),
        onPressed: () async {
          final action = await showDvGlassMenu<SettingsAction>(
            anchor,
            items: [
              DvGlassMenuItem(
                value: SettingsAction.archive,
                icon: Icons.archive_rounded,
                title: l10n.archive,
                color: DvMenuColors.orange,
              ),
              DvGlassMenuItem(
                value: SettingsAction.settings,
                icon: Icons.settings_rounded,
                title: l10n.settings,
                color: DvMenuColors.blue,
              ),
            ],
          );
          if (action == null || !anchor.mounted) return;
          _selected(action, anchor);
        },
      ),
    );
  }

  void _selected(SettingsAction action, BuildContext context) {
    switch (action) {
      case SettingsAction.archive:
        context.go('/rooms/archive');
        break;
      case SettingsAction.settings:
        context.go('/rooms/settings');
        break;
    }
  }
}

enum SettingsAction { archive, settings }
