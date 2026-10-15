// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// DVChat: Строка чата в списке: аватар, имя, последнее сообщение, счётчик непрочитанных.

import 'package:dvchat/config/app_config.dart';
import 'package:dvchat/l10n/l10n.dart';
import 'package:dvchat/pages/chat_list/unread_bubble.dart';
import 'package:dvchat/pages/profile/dv_profile_page.dart';
import 'package:dvchat/utils/dv_last_event.dart';
import 'package:dvchat/utils/dv_list_style.dart';
import 'package:dvchat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:dvchat/utils/room_status_extension.dart';
import 'package:dvchat/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import 'package:dvchat/widgets/future_loading_dialog.dart';
import 'package:dvchat/widgets/hover_builder.dart';
import 'package:dvchat/widgets/typing_animation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

import '../../config/themes.dart';
import '../../utils/date_time_extension.dart';
import '../../widgets/avatar.dart';

class _ChatListItemBody extends StatelessWidget {
  final Room room;
  final bool activeChat;
  final void Function(BuildContext context)? onLongPress;
  final void Function()? onForget;
  final void Function() onTap;
  final String? filter;

  const _ChatListItemBody(
    this.room, {
    this.activeChat = false,
    required this.onTap,
    this.onLongPress,
    this.onForget,
    this.filter,
  });

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([DvLastEvent.tick, DvListStyle.revision]),
    builder: (context, _) => _buildItem(context),
  );

  Widget _buildItem(BuildContext context) {
    final theme = Theme.of(context);

    final isMuted = room.pushRuleState != PushRuleState.notify;
    final typingText = room.getLocalizedTypingText(context);
    final lastEvent = DvLastEvent.of(room);
    final ownMessage = lastEvent?.senderId == room.client.userID;
    final directChatMatrixId = room.directChatMatrixID;
    final isDirectChat = directChatMatrixId != null;
    final hasNotifications = room.notificationCount > 0;
    final backgroundColor = activeChat
        ? theme.colorScheme.secondaryContainer
        : DvListStyle.fill(context);
    final displayname = room.getLocalizedDisplayname(
      MatrixLocals(L10n.of(context)),
    );
    final filter = this.filter;
    if (filter != null && !displayname.toLowerCase().contains(filter)) {
      return const SizedBox.shrink();
    }

    final needLastEventSender =
        lastEvent != null &&
        room.getState(EventTypes.RoomMember, lastEvent.senderId) == null;

    return Padding(
      padding: DvListStyle.outerPadding,
      child: Material(
        shape: DvListStyle.shape(context),
        clipBehavior: Clip.hardEdge,
        color: backgroundColor,
        elevation: DvListStyle.elevation,
        shadowColor: Colors.black,
        surfaceTintColor: Colors.transparent,
        child: FutureBuilder(
          future: room.name.isEmpty ? room.loadHeroUsers() : null,
          builder: (context, _) => HoverBuilder(
            builder: (context, listTileHovered) => ListTile(
              minVerticalPadding: 16,
              contentPadding: const EdgeInsets.symmetric(horizontal: 8),
              onLongPress: () => onLongPress?.call(context),
              leading: HoverBuilder(
                builder: (context, hovered) => AnimatedScale(
                  duration: DvThemes.animationDuration,
                  curve: DvThemes.animationCurve,
                  scale: hovered ? 1.1 : 1.0,
                  child: SizedBox(
                    width: Avatar.defaultSize,
                    height: Avatar.defaultSize,
                    child: Stack(
                      children: [
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: Avatar(
                            mxContent: room.avatar,
                            size: Avatar.defaultSize,
                            name: displayname,
                            presenceUserId: directChatMatrixId,
                            presenceBackgroundColor: backgroundColor,
                            onTap: directChatMatrixId == null
                                ? () => onLongPress?.call(context)
                                : () => DvProfilePage.open(
                                    context,
                                    directChatMatrixId,
                                  ),
                          ),
                        ),
                        Positioned(
                          top: 0,
                          right: 0,
                          child: GestureDetector(
                            onTap: () => onLongPress?.call(context),
                            child: AnimatedScale(
                              duration: DvThemes.animationDuration,
                              curve: DvThemes.animationCurve,
                              scale: listTileHovered ? 1.0 : 0.0,
                              child: Material(
                                color: backgroundColor,
                                borderRadius: BorderRadius.circular(16),
                                child: const Icon(
                                  Icons.arrow_drop_down_circle_outlined,
                                  size: 18,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              title: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      displayname,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      softWrap: false,
                    ),
                  ),
                  if (isMuted)
                    const Padding(
                      padding: EdgeInsets.only(left: 4.0),
                      child: Icon(Icons.notifications_off_outlined, size: 16),
                    ),
                  if (room.isLowPriority)
                    Padding(
                      padding: EdgeInsets.only(
                        right: hasNotifications ? 4.0 : 0.0,
                      ),
                      child: Icon(
                        Icons.low_priority,
                        size: 16,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  if (room.isFavourite)
                    Padding(
                      padding: EdgeInsets.only(
                        right: hasNotifications ? 4.0 : 0.0,
                      ),
                      child: Icon(
                        Icons.push_pin,
                        size: 16,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  if (room.membership != Membership.invite)
                    Padding(
                      padding: const EdgeInsets.only(left: 4.0),
                      child: Text(
                        room.latestEventReceivedTime.localizedTimeShort(
                          context,
                        ),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: room.hasNewMessages
                              ? FontWeight.bold
                              : null,
                          color: room.highlightCount >= 1
                              ? theme.colorScheme.error
                              : room.hasNewMessages
                              ? theme.colorScheme.primary
                              : null,
                        ),
                      ),
                    ),
                ],
              ),
              subtitle: Row(
                children: [
                  if (typingText.isEmpty &&
                      ownMessage &&
                      lastEvent?.status.isSending == true) ...[
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator.adaptive(strokeWidth: 2),
                    ),
                    const SizedBox(width: 4),
                  ],
                  AnimatedSize(
                    clipBehavior: Clip.hardEdge,
                    duration: DvThemes.animationDuration,
                    curve: DvThemes.animationCurve,
                    child: typingText.isNotEmpty
                        ? Padding(
                            padding: const EdgeInsets.only(right: 4.0),
                            child: TypingAnimation(size: 4.0),
                          )
                        : lastEvent?.relationshipType ==
                              RelationshipTypes.thread
                        ? Container(
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: theme.colorScheme.outline,
                              ),
                              borderRadius: BorderRadius.circular(
                                AppConfig.borderRadius,
                              ),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8.0,
                            ),
                            margin: const EdgeInsets.only(right: 4.0),
                            child: Row(
                              mainAxisSize: .min,
                              children: [
                                Icon(
                                  Icons.message_outlined,
                                  size: 12,
                                  color: theme.colorScheme.outline,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  L10n.of(context).thread,
                                  style: TextStyle(fontSize: 11),
                                ),
                              ],
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                  Expanded(
                    child: typingText.isNotEmpty
                        ? Text(
                            typingText,
                            style: TextStyle(color: theme.colorScheme.primary),
                            maxLines: 1,
                            softWrap: false,
                          )
                        : FutureBuilder(
                            key: ValueKey(
                              '${lastEvent?.eventId}_${lastEvent?.type}_${lastEvent?.redacted}',
                            ),
                            future: needLastEventSender
                                ? lastEvent.calcLocalizedBody(
                                    MatrixLocals(L10n.of(context)),
                                    hideReply: true,
                                    hideEdit: true,
                                    plaintextBody: true,
                                    removeMarkdown: true,
                                    withSenderNamePrefix:
                                        // DVChat: служебное приветствие («X теперь в DVChat») показываем без имени автора
                                        !(lastEvent.content.containsKey(
                                          'online.dvbstudio.dvchat.newcomer',
                                        )) &&
                                        (!isDirectChat ||
                                            directChatMatrixId !=
                                                lastEvent.senderId),
                                  )
                                : null,
                            initialData: lastEvent?.calcLocalizedBodyFallback(
                              MatrixLocals(L10n.of(context)),
                              hideReply: true,
                              hideEdit: true,
                              plaintextBody: true,
                              removeMarkdown: true,
                              withSenderNamePrefix:
                                  // DVChat: служебное приветствие («X теперь в DVChat») показываем без имени автора
                                  !(lastEvent.content.containsKey(
                                    'online.dvbstudio.dvchat.newcomer',
                                  )) &&
                                  (!isDirectChat ||
                                      directChatMatrixId != lastEvent.senderId),
                            ),
                            builder: (context, snapshot) => Text(
                              room.membership == Membership.invite
                                  ? room
                                            .getState(
                                              EventTypes.RoomMember,
                                              room.client.userID!,
                                            )
                                            ?.content
                                            .tryGet<String>('reason') ??
                                        (isDirectChat
                                            ? L10n.of(context).newChatRequest
                                            : L10n.of(context).inviteGroupChat)
                                  : snapshot.data?.trim().replaceAll(
                                          '\n',
                                          ' ',
                                        ) ??
                                        L10n.of(context).noMessagesYet,
                              softWrap: false,
                              maxLines: room.notificationCount >= 1 ? 2 : 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                decoration: lastEvent?.redacted == true
                                    ? TextDecoration.lineThrough
                                    : null,
                              ),
                            ),
                          ),
                  ),
                  const SizedBox(width: 8),
                  UnreadBubble(room: room),
                ],
              ),
              onTap: onTap,
              trailing: onForget == null
                  ? room.membership == Membership.invite
                        ? IconButton(
                            tooltip: L10n.of(context).declineInvitation,
                            icon: const Icon(Icons.delete_forever_outlined),
                            color: theme.colorScheme.error,
                            onPressed: () async {
                              final consent = await showOkCancelAlertDialog(
                                context: context,
                                title: L10n.of(context).declineInvitation,
                                message: L10n.of(context).areYouSure,
                                okLabel: L10n.of(context).yes,
                                isDestructive: true,
                              );
                              if (consent != OkCancelResult.ok) return;
                              if (!context.mounted) return;
                              await showFutureLoadingDialog(
                                context: context,
                                future: room.leave,
                              );
                            },
                          )
                        : null
                  : IconButton(
                      icon: const Icon(Icons.delete_outlined),
                      onPressed: onForget,
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// DVChat: обёртка, которая догружает участников личного чата и ПОСЛЕ этого
/// заново строит всю строку списка. Раньше имя считалось до загрузки и оставалось
/// логином («dima»), пока чат не откроют.
class ChatListItem extends StatelessWidget {
  final Room room;
  final bool activeChat;
  final void Function(BuildContext context)? onLongPress;
  final void Function()? onForget;
  final void Function() onTap;
  final String? filter;

  const ChatListItem(
    this.room, {
    this.activeChat = false,
    required this.onTap,
    this.onLongPress,
    this.onForget,
    this.filter,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Object?>(
      future: room.name.isEmpty ? room.loadHeroUsers() : null,
      builder: (context, _) => _ChatListItemBody(
        room,
        activeChat: activeChat,
        onTap: onTap,
        onLongPress: onLongPress,
        onForget: onForget,
        filter: filter,
      ),
    );
  }
}
