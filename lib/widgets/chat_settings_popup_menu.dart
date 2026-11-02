// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// DVChat: Меню «три точки» в шапке чата (поиск, сведения, архив, уведомления).

import 'package:dvchat/l10n/l10n.dart';
import 'package:dvchat/utils/blocked_periods.dart';
import 'package:dvchat/utils/room_archive_extension.dart';
import 'package:dvchat/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import 'package:dvchat/widgets/dv_glass.dart';
import 'package:dvchat/widgets/future_loading_dialog.dart';
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

  /// DVChat: пункты стеклянного меню (то же, что раньше было в выпадающем списке)
  List<DvGlassMenuItem<ChatPopupMenuActions>> _items(BuildContext context) {
    final l10n = L10n.of(context);
    return [
      if (displayChatDetails)
        DvGlassMenuItem(
          value: ChatPopupMenuActions.details,
          icon: Icons.info_outline_rounded,
          title: l10n.chatDetails,
        ),
      DvGlassMenuItem(
        value: ChatPopupMenuActions.search,
        icon: Icons.search_outlined,
        title: l10n.search,
      ),
      // Личный чат нельзя покинуть, его отправляют в архив
      if (room.isDirectChat)
        if (room.isInArchive && !room.isClosedChat)
          const DvGlassMenuItem(
            value: ChatPopupMenuActions.restore,
            icon: Icons.unarchive_outlined,
            title: 'Вернуть из архива',
          )
        else
          const DvGlassMenuItem(
            value: ChatPopupMenuActions.archive,
            icon: Icons.archive_outlined,
            title: 'В архив',
          )
      else
        DvGlassMenuItem(
          value: ChatPopupMenuActions.leave,
          icon: Icons.delete_outlined,
          title: l10n.leave,
          destructive: true,
        ),
      // DVChat: блокировка собеседника в личном чате (администратора заблокировать нельзя)
      if (_partnerId != null && _partnerId!.localpart != 'dima')
        if (room.client.ignoredUsers.contains(_partnerId))
          const DvGlassMenuItem(
            value: ChatPopupMenuActions.unblock,
            icon: Icons.lock_open_outlined,
            title: 'Разблокировать',
          )
        else
          const DvGlassMenuItem(
            value: ChatPopupMenuActions.block,
            icon: Icons.block_outlined,
            title: 'Заблокировать',
            destructive: true,
          ),
    ];
  }

  /// DVChat: «три точки» открывают стеклянное меню под кнопкой (вместо серого выпадающего списка)
  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (anchor) => IconButton(
        tooltip: 'Меню',
        icon: const Icon(Icons.more_vert),
        onPressed: () async {
          final choice = await showDvGlassMenu<ChatPopupMenuActions>(
            anchor,
            items: _items(anchor),
          );
          if (choice == null || !anchor.mounted) return;
          await _onSelected(anchor, choice);
        },
      ),
    );
  }

  Future<void> _onSelected(
    BuildContext context,
    ChatPopupMenuActions choice,
  ) async {
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
            future: () => room.client.blockUser(partnerId),
          );
          break;
        }
      case ChatPopupMenuActions.unblock:
        {
          final partnerId = room.directChatMatrixID;
          if (partnerId == null) return;
          await showFutureLoadingDialog(
            context: context,
            future: () => room.client.unblockUser(partnerId),
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
  }

  void _showChatDetails(BuildContext context) {
    if (GoRouterState.of(context).uri.path.endsWith('/details')) {
      context.go('/rooms/${room.id}');
    } else {
      context.go('/rooms/${room.id}/details');
    }
  }
}
