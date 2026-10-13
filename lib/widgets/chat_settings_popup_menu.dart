// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/room_archive_extension.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

enum ChatPopupMenuActions {
  details,
  search,
  archive,
  restore,
  leave,
  block,
  unblock,
}

class ChatSettingsPopupMenu extends StatelessWidget {
  final Room room;
  final bool displayChatDetails;

  const ChatSettingsPopupMenu(this.room, this.displayChatDetails, {super.key});

  /// DVChat: собеседник в личном чате (null — не личный чат)
  String? get _partnerId => room.isDirectChat ? room.directChatMatrixID : null;

  PopupMenuItem<ChatPopupMenuActions> _item(
    ChatPopupMenuActions action,
    IconData icon,
    String title,
  ) => PopupMenuItem<ChatPopupMenuActions>(
    value: action,
    child: Row(children: [Icon(icon), const SizedBox(width: 12), Text(title)]),
  );

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<ChatPopupMenuActions>(
      useRootNavigator: true,
      onSelected: (choice) async {
        final router = GoRouter.of(context);
        switch (choice) {
          case ChatPopupMenuActions.leave:
            if (room.isSupportRoom) {
              // DVChat: чат с поддержкой не покидаем, только скрываем
              final hidden = await showFutureLoadingDialog(
                context: context,
                future: room.hideForever,
              );
              if (hidden.error == null) router.go('/rooms');
              break;
            }
            final l10n = L10n.of(context);
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
            if (result.error == null) router.go('/rooms');
            break;
          case ChatPopupMenuActions.archive:
            final result = await showFutureLoadingDialog(
              context: context,
              future: room.moveToArchive,
            );
            if (result.error == null) router.go('/rooms');
            break;
          case ChatPopupMenuActions.restore:
            await showFutureLoadingDialog(
              context: context,
              future: room.restoreFromArchive,
            );
            break;
          case ChatPopupMenuActions.block:
            {
              final partnerId = room.directChatMatrixID;
              if (partnerId == null) return;
              final ok = await showOkCancelAlertDialog(
                context: context,
                title: 'Заблокировать собеседника?',
                message:
                    'Его сообщения перестанут показываться вам. Он об этом не узнает. '
                    'Разблокировать можно в этом же меню.',
                okLabel: 'Заблокировать',
                cancelLabel: L10n.of(context).cancel,
                isDestructive: true,
              );
              if (ok != OkCancelResult.ok) return;
              if (!context.mounted) return;
              await showFutureLoadingDialog(
                context: context,
                future: () =>
                    room.client.ignoreUser(partnerId, leaveRooms: false),
              );
              break;
            }
          case ChatPopupMenuActions.unblock:
            {
              final partnerId = room.directChatMatrixID;
              if (partnerId == null) return;
              await showFutureLoadingDialog(
                context: context,
                future: () => room.client.unignoreUser(partnerId),
              );
              break;
            }
          case ChatPopupMenuActions.details:
            _showChatDetails(context);
            break;
          case ChatPopupMenuActions.search:
            router.go('/rooms/${room.id}/search');
            break;
        }
      },
      itemBuilder: (BuildContext context) {
        final l10n = L10n.of(context);
        return [
          if (displayChatDetails)
            _item(
              ChatPopupMenuActions.details,
              Icons.info_outline_rounded,
              l10n.chatDetails,
            ),
          _item(
            ChatPopupMenuActions.search,
            Icons.search_outlined,
            l10n.search,
          ),
          // Личный чат нельзя покинуть, его отправляют в архив
          if (room.isDirectChat)
            if (room.isInArchive)
              _item(
                ChatPopupMenuActions.restore,
                Icons.unarchive_outlined,
                'Вернуть из архива',
              )
            else
              _item(
                ChatPopupMenuActions.archive,
                Icons.archive_outlined,
                'В архив',
              )
          else
            _item(
              ChatPopupMenuActions.leave,
              Icons.delete_outlined,
              l10n.leave,
            ),
          // DVChat: блокировка собеседника в личном чате (администратора заблокировать нельзя)
          if (_partnerId != null && _partnerId!.localpart != 'dima')
            if (room.client.ignoredUsers.contains(_partnerId))
              _item(
                ChatPopupMenuActions.unblock,
                Icons.lock_open_outlined,
                'Разблокировать',
              )
            else
              _item(
                ChatPopupMenuActions.block,
                Icons.block_outlined,
                'Заблокировать',
              ),
        ];
      },
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
