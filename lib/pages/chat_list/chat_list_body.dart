// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// DVChat: Тело списка чатов: чаты, приглашения, пустое состояние.

import 'dart:async';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:dvchat/l10n/l10n.dart';
import 'package:dvchat/pages/chat_list/chat_list.dart';
import 'package:dvchat/pages/chat_list/chat_list_item.dart';
import 'package:dvchat/pages/chat_list/dummy_chat_list_item.dart';
import 'package:dvchat/utils/room_archive_extension.dart';
import 'package:dvchat/utils/stream_extension.dart';
import 'package:dvchat/widgets/closed_chat_notice.dart';
import 'package:dvchat/widgets/dv_encryption_note.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

import '../../widgets/matrix.dart';
import 'chat_list_header.dart';

/// DVChat: как в WhatsApp. Сверху группы, под ними личные чаты, всё в одном окне.
/// Комнаты, уже отправленные в архив автоматически (чтобы не делать это повторно)
final Set<String> _autoArchived = {};

class ChatListViewBody extends StatelessWidget {
  final ChatListController controller;

  const ChatListViewBody(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final client = Matrix.of(context).client;

    const dummyChatCount = 4;
    return StreamBuilder(
      key: ValueKey(client.userID.toString()),
      stream: client.onSync.stream
          .where((s) => s.hasRoomUpdate)
          .rateLimit(const Duration(seconds: 1)),
      builder: (context, _) {
        final allRooms = controller.filteredRooms;
        // DVChat: новое сообщение возвращает чат из архива в список
        final returning = allRooms
            .where(
              (room) =>
                  (room.isInArchive || room.isHiddenByUser) &&
                  room.hasNewMessages,
            )
            .toList();
        if (returning.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            for (final room in returning) {
              room.returnToList();
            }
          });
        }
        // DVChat: собеседник покинул чат — чат уходит в архив (читать можно, писать нельзя)
        final abandoned = allRooms
            .where(
              (room) =>
                  room.isAbandonedDMRoom == true &&
                  !room.isInArchive &&
                  !room.isHiddenByUser &&
                  !_autoArchived.contains(room.id),
            )
            .toList();
        if (abandoned.isNotEmpty) {
          _autoArchived.addAll(abandoned.map((room) => room.id));
          WidgetsBinding.instance.addPostFrameCallback((_) {
            for (final room in abandoned) {
              room.moveToArchive();
            }
            if (context.mounted) {
              unawaited(showClosedChatNotice(context, abandoned));
            }
          });
        }
        final rooms = allRooms
            .where((room) => !room.isNewcomerPlaceholder)
            // Закрытый чат живёт только в Архиве, метка для этого не нужна
            .where((room) => room.isAbandonedDMRoom != true)
            .where(
              (room) =>
                  !(room.isInArchive || room.isHiddenByUser) ||
                  room.hasNewMessages,
            )
            .toList();

        // Сначала группы, потом личные чаты; порядок внутри раздела прежний
        final groups = rooms.where((room) => !room.isDirectChat).toList();
        // DVChat: личные чаты с заблокированным собеседником уходят в отдельный раздел внизу
        final ignoredIds = client.ignoredUsers;
        bool isBlocked(Room room) =>
            room.isDirectChat && ignoredIds.contains(room.directChatMatrixID);
        final directs = rooms
            .where((room) => room.isDirectChat && !isBlocked(room))
            .toList();
        final blocked = rooms.where(isBlocked).toList();
        final entries = <Object>[
          if (groups.isNotEmpty) 'Группы',
          ...groups,
          if (directs.isNotEmpty) 'Личные чаты',
          ...directs,
          if (blocked.isNotEmpty) 'Заблокированные',
          ...blocked,
        ];

        return CustomScrollView(
          controller: controller.scrollController,
          slivers: [
            ChatListHeader(controller: controller),
            if (client.prevBatch != null && rooms.isEmpty)
              SliverToBoxAdapter(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        const Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            DummyChatListItem(opacity: 0.5, animate: false),
                            DummyChatListItem(opacity: 0.3, animate: false),
                          ],
                        ),
                        Icon(
                          CupertinoIcons.chat_bubble_text_fill,
                          size: 128,
                          color: theme.colorScheme.secondary,
                        ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Text(
                        client.rooms.isEmpty
                            ? 'Пока нет чатов'
                            : L10n.of(context).noMoreChatsFound,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 18,
                          color: theme.colorScheme.secondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            if (client.prevBatch == null)
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, i) => DummyChatListItem(
                    opacity: (dummyChatCount - i) / dummyChatCount,
                    animate: true,
                  ),
                  childCount: dummyChatCount,
                ),
              ),
            if (client.prevBatch != null)
              SliverSafeArea(
                top: false,
                sliver: SliverList.builder(
                  itemCount: entries.length,
                  itemBuilder: (BuildContext context, int i) {
                    final entry = entries[i];
                    if (entry is String) {
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                        child: Text(
                          entry,
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: entry == 'Заблокированные'
                                ? theme.colorScheme.outline
                                : theme.colorScheme.primary,
                          ),
                        ),
                      );
                    }
                    final room = entry as Room;
                    final item = ChatListItem(
                      room,
                      key: Key('chat_list_item_${room.id}'),
                      filter: '',
                      onTap: () => controller.onChatTap(room),
                      onLongPress: (context) =>
                          controller.chatContextAction(room, context),
                      activeChat: controller.activeChat == room.id,
                    );
                    return isBlocked(room)
                        ? Opacity(opacity: 0.45, child: item)
                        : item;
                  },
                ),
              ),
            if (client.prevBatch != null)
              const SliverToBoxAdapter(child: DvEncryptionNote()),
          ],
        );
      },
    );
  }
}
