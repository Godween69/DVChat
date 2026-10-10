// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

enum ChatPopupMenuActions { details, leave, search }

class ChatSettingsPopupMenu extends StatelessWidget {
  final Room room;
  final bool displayChatDetails;

  const ChatSettingsPopupMenu(this.room, this.displayChatDetails, {super.key});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<ChatPopupMenuActions>(
      useRootNavigator: true,
      onSelected: (choice) async {
        switch (choice) {
          case ChatPopupMenuActions.leave:
            final l10n = L10n.of(context);
            final router = GoRouter.of(context);
            final confirmed = await showOkCancelAlertDialog(
              context: context,
              title: l10n.areYouSure,
              message: l10n.archiveRoomDescription,
              okLabel: l10n.leave,
              cancelLabel: l10n.cancel,
              isDestructive: true,
            );
            if (confirmed != OkCancelResult.ok) return;
            if (!context.mounted) return;
            final result = await showFutureLoadingDialog(
              context: context,
              future: room.leave,
            );
            if (result.error == null) {
              router.go('/rooms');
            }
            break;
          case ChatPopupMenuActions.details:
            _showChatDetails(context);
            break;
          case ChatPopupMenuActions.search:
            context.go('/rooms/${room.id}/search');
            break;
        }
      },
      itemBuilder: (BuildContext context) => [
        if (displayChatDetails)
          PopupMenuItem<ChatPopupMenuActions>(
            value: ChatPopupMenuActions.details,
            child: Row(
              children: [
                const Icon(Icons.info_outline_rounded),
                const SizedBox(width: 12),
                Text(L10n.of(context).chatDetails),
              ],
            ),
          ),
        PopupMenuItem<ChatPopupMenuActions>(
          value: ChatPopupMenuActions.search,
          child: Row(
            children: [
              const Icon(Icons.search_outlined),
              const SizedBox(width: 12),
              Text(L10n.of(context).search),
            ],
          ),
        ),
        PopupMenuItem<ChatPopupMenuActions>(
          value: ChatPopupMenuActions.leave,
          child: Row(
            children: [
              const Icon(Icons.delete_outlined),
              const SizedBox(width: 12),
              Text(L10n.of(context).leave),
            ],
          ),
        ),
      ],
    );
  }

  void _showChatDetails(BuildContext context) {
    if (GoRouterState.of(context).uri.path.endsWith('/details')) {
      context.go('/rooms/${room.id}');
    } else {
      context.go('/rooms/${room.id}/details');
    }
  }
}
