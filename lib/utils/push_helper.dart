// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// DVChat: Разбор пуша в фоне, когда приложение закрыто: по event_id запрашивает событие,
// расшифровывает и показывает локальное уведомление.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:dvchat/config/app_config.dart';
import 'package:dvchat/config/setting_keys.dart';
import 'package:dvchat/l10n/l10n.dart';
import 'package:dvchat/utils/app_locale.dart';
import 'package:dvchat/utils/client_manager.dart';
import 'package:dvchat/utils/dv_read_notice.dart';
import 'package:dvchat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:dvchat/utils/notification_avatar_extension.dart';
import 'package:dvchat/utils/notification_background_handler.dart';
import 'package:dvchat/utils/platform_infos.dart';
import 'package:dvchat/utils/start_push_foreground_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_new_badger/flutter_new_badger.dart';
import 'package:flutter_shortcuts_new/flutter_shortcuts_new.dart';
import 'package:http/http.dart' as http;
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart' hide Result;
import 'package:shared_preferences/shared_preferences.dart';

final Map<String, DateTime> lastReceivedPushNotification = {};

Future<void> pushHelper(
  PushNotification notification, {
  List<Client>? clients,
  L10n? l10n,
  String? activeRoomId,
  required FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin,
}) async {
  l10n ??= await lookupL10n(appLocale);

  try {
    await _tryPushHelper(
      notification,
      clients: clients,
      l10n: l10n,
      activeRoomId: activeRoomId,
      flutterLocalNotificationsPlugin: flutterLocalNotificationsPlugin,
    ).timeout(const Duration(seconds: 30));
  } catch (e, s) {
    if (PlatformInfos.isAndroid &&
        e is! TimeoutException &&
        e is! IOException &&
        e is! http.ClientException) {
      Logs().e('Push Helper has crashed! Writing into temporary file...', e, s);
      final store = await SharedPreferences.getInstance();
      await store.setStringList(AppConfig.pushHelperCrashReportKey, [
        e.toString(),
        s.toString(),
      ]);
    }

    if (notification.roomId != null) {
      await flutterLocalNotificationsPlugin.show(
        id: notification.notificationId,
        title: 'Новое сообщение',
        body: l10n.openAppToReadMessages,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            AppConfig.pushNotificationsChannelId,
            l10n.incomingMessages,
            number: notification.counts?.unread,
            ticker: l10n.unreadChatsInApp(
              AppSettings.applicationName.value,
              (notification.counts?.unread ?? 0).toString(),
            ),
            importance: Importance.high,
            priority: Priority.max,
            shortcutId: notification.roomId,
            category: AndroidNotificationCategory.message,
            groupKey: notification.clientName,
          ),
        ),
      );
    }
    rethrow;
  } finally {
    ForegroundServices.stopService('background_push');
  }
}

Future<void> _tryPushHelper(
  PushNotification notification, {
  List<Client>? clients,
  L10n? l10n,
  String? activeRoomId,
  required FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin,
}) async {
  final isBackgroundMessage = clients == null;
  Logs().v(
    'Push helper has been started (background=$isBackgroundMessage).',
    notification.toJson(),
  );

  final clientName = notification.clientName;
  final store = await AppSettings.init();

  final client = clientName == null
      ? (clients?.first ??
            (await ClientManager.getClients(
              initialize: false,
              store: store,
            )).first)
      : (clients?.firstWhereOrNull(
              (client) => client.clientName == clientName,
            ) ??
            await ClientManager.createClient(clientName, store));

  lastReceivedPushNotification[client.clientName] = DateTime.now();

  l10n ??= await L10n.delegate.load(appLocale);

  Logs().v('Load event...');
  final event = await client.getEventByPushNotification(
    notification,
    storeInDatabase: false,
  );

  updateAppBadge(notification.counts?.unread ?? 0);

  if (event == null) {
    Logs().v('Notification is a clearing indicator.');
    if (clients?.length == 1 && (notification.counts?.unread == 0)) {
      await flutterLocalNotificationsPlugin.cancelAll();
    } else {
      // Make sure client is fully loaded and synced before dismiss notifications:
      await client.roomsLoading;
      await client
          .oneShotSync()
          .timeout(const Duration(seconds: 8))
          .catchError((_) => null);

      final activeNotifications = await flutterLocalNotificationsPlugin
          .getActiveNotifications();
      activeNotifications.removeWhere(
        (notification) => notification.groupKey != client.clientName,
      );
      var needsUpdateForSummaryNotification = false;
      for (final activeNotification in activeNotifications) {
        final room = client.rooms.singleWhereOrNull(
          (room) =>
              '${client.clientName}_${room.id}'.hashCode ==
              activeNotification.id,
        );
        if (room != null && !room.isUnreadOrInvited) {
          flutterLocalNotificationsPlugin.cancel(id: activeNotification.id!);
          if (PlatformInfos.isAndroid) needsUpdateForSummaryNotification = true;
        }
      }
      if (needsUpdateForSummaryNotification) {
        await updateSummaryNotification(
          clientName: client.clientName,
          l10n: l10n,
          flutterLocalNotificationsPlugin: flutterLocalNotificationsPlugin,
        );
      }
    }
    return;
  }

  Logs().v('Push helper got notification event of type ${event.type}.');

  // DVChat: расшифрованная реакция не подходит ни под одно правило (правила знают только
  // сообщения и «зашифрованное событие»), поэтому для реакций правила не применяются,
  // решение принимается ниже
  if (event.type != EventTypes.Reaction &&
      event.type != dvReadEventType &&
      !client.pushruleEvaluator.match(event).notify) {
    Logs().i('Push helper: filtered by client-side push rules.');
    return;
  }

  // DVChat: уведомления о реакциях отключаются в настройках (в зашифрованных чатах
  // сервер не отличает реакцию от сообщения, поэтому решаем здесь, после расшифровки)
  if (event.type == EventTypes.Reaction) {
    if (!AppSettings.notifyAboutReactions.value) {
      Logs().i('Push helper: reaction notifications are turned off.');
      return;
    }
    // Уведомляем только о реакциях других людей на МОИ сообщения
    if (event.senderId == client.userID) return;
    final targetId = event.relationshipEventId;
    final target = targetId == null
        ? null
        : await event.room.getEventById(targetId);
    if (target == null || target.senderId != client.userID) {
      Logs().i('Push helper: reaction is not on my message.');
      return;
    }
  }

  // DVChat: «собеседник прочитал ваше сообщение» (скрытое событие dv.read)
  if (event.type == dvReadEventType) {
    if (!AppSettings.notifyAboutReadReceipts.value) {
      Logs().i('Push helper: read notifications are turned off.');
      return;
    }
    if (event.senderId == client.userID) return;
    final readId = event.content['event_id'];
    final readTarget = readId is String
        ? await event.room.getEventById(readId)
        : null;
    if (readTarget == null || readTarget.senderId != client.userID) {
      Logs().i('Push helper: read notice is not about my message.');
      return;
    }
  }

  if (notification.roomId != null &&
      activeRoomId == notification.roomId &&
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
    Logs().v('Room is in foreground. Stop push helper here.');
    return;
  }

  final matrixLocals = MatrixLocals(l10n);

  // Calculate the body
  final body = event.type == dvReadEventType
      ? 'Прочитал(а) ваше сообщение'
      : event.type == EventTypes.Encrypted
      ? 'Новое сообщение'
      : await event.calcLocalizedBody(
          matrixLocals,
          plaintextBody: true,
          withSenderNamePrefix: false,
          hideReply: true,
          hideEdit: true,
          removeMarkdown: true,
        );

  // The person object for the android message style notification
  final avatar = event.room.avatar;
  final senderAvatar = event.room.isDirectChat
      ? avatar
      : event.senderFromMemoryOrFallback.avatarUrl;

  final ownUser = event.room.unsafeGetUserFromMemoryOrFallback(client.userID!);

  final userAvatarFile = await client.tryDownloadNotificationAvatar(
    ownUser.avatarUrl,
  );
  final roomAvatarFile = await client.tryDownloadNotificationAvatar(avatar);
  final senderAvatarFile = await client.tryDownloadNotificationAvatar(
    senderAvatar,
  );

  final id = '${client.clientName}_${notification.roomId}'.hashCode;

  // DVChat: служебное приветствие («X теперь в DVChat») приходит без имени администратора
  final isServiceNotice = event.content.containsKey(
    'online.dvbstudio.dvchat.newcomer',
  );
  final senderName = isServiceNotice
      ? 'DVChat'
      : event.senderFromMemoryOrFallback.calcDisplayname();
  // Show notification

  final newMessage = Message(
    body,
    event.originServerTs,
    Person(
      bot: event.messageType == MessageTypes.Notice,
      key: event.senderId,
      name: senderName,
      icon: senderAvatarFile == null
          ? null
          : ByteArrayAndroidIcon(senderAvatarFile),
    ),
  );

  final messagingStyleInformation = PlatformInfos.isAndroid
      ? await AndroidFlutterLocalNotificationsPlugin()
            .getActiveNotificationMessagingStyle(id: id)
      : null;
  messagingStyleInformation?.messages?.add(newMessage);

  final roomName = event.room.getLocalizedDisplayname(MatrixLocals(l10n));

  final notificationGroupId = event.room.isDirectChat
      ? 'directChats'
      : 'groupChats';
  final groupName = event.room.isDirectChat ? l10n.directChats : l10n.groups;

  final messageRooms = AndroidNotificationChannelGroup(
    notificationGroupId,
    groupName,
  );
  final roomsChannel = AndroidNotificationChannel(
    event.room.id,
    roomName,
    groupId: notificationGroupId,
  );

  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >()
      ?.createNotificationChannelGroup(messageRooms);
  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >()
      ?.createNotificationChannel(roomsChannel);

  final androidPlatformChannelSpecifics = AndroidNotificationDetails(
    AppConfig.pushNotificationsChannelId,
    l10n.incomingMessages,
    number: notification.counts?.unread,
    category: AndroidNotificationCategory.message,
    shortcutId: event.room.id,
    styleInformation:
        messagingStyleInformation ??
        MessagingStyleInformation(
          Person(
            name: ownUser.calcDisplayname(),
            icon: userAvatarFile == null
                ? null
                : ByteArrayAndroidIcon(userAvatarFile),
            key: event.room.client.userID,
          ),
          conversationTitle: event.room.isDirectChat ? null : roomName,
          groupConversation: !event.room.isDirectChat,
          messages: [newMessage],
        ),
    ticker: event.calcLocalizedBodyFallback(
      matrixLocals,
      plaintextBody: true,
      withSenderNamePrefix: !event.room.isDirectChat,
      hideReply: true,
      hideEdit: true,
      removeMarkdown: true,
    ),
    importance: Importance.high,
    priority: Priority.max,
    groupKey: client.clientName,
    actions: switch (event.type) {
      EventTypes.Message ||
      EventTypes.Encrypted ||
      EventTypes.Sticker => <AndroidNotificationAction>[
        AndroidNotificationAction(
          DvChatNotificationActions.reply.name,
          l10n.reply,
          inputs: [AndroidNotificationActionInput(label: l10n.writeAMessage)],
          allowGeneratedReplies: true,
          semanticAction: SemanticAction.reply,
        ),
        AndroidNotificationAction(
          DvChatNotificationActions.markAsRead.name,
          l10n.markAsRead,
          semanticAction: SemanticAction.markAsRead,
        ),
        AndroidNotificationAction(
          DvChatNotificationActions.mute.name,
          l10n.mute,
          semanticAction: SemanticAction.mute,
        ),
      ],
      _ => null,
    },
  );
  final platformChannelSpecifics = NotificationDetails(
    android: androidPlatformChannelSpecifics,
  );

  final title = event.room.getLocalizedDisplayname(MatrixLocals(l10n));

  if (PlatformInfos.isAndroid && messagingStyleInformation == null) {
    await _setShortcut(event, l10n, title, roomAvatarFile);
  }

  final needsTitleAndBody = !PlatformInfos.isAndroid;

  await flutterLocalNotificationsPlugin.show(
    id: notification.notificationId,
    title: needsTitleAndBody ? title : null,
    body: needsTitleAndBody ? body : null,
    notificationDetails: platformChannelSpecifics,
    payload: DvChatPushPayload(
      client.clientName,
      event.room.id,
      event.eventId,
    ).toString(),
  );

  // Send summary notification on Android
  if (PlatformInfos.isAndroid) {
    await updateSummaryNotification(
      clientName: client.clientName,
      l10n: l10n,
      flutterLocalNotificationsPlugin: flutterLocalNotificationsPlugin,
    );
  }
  Logs().v('Push helper has been completed!');
}

void updateAppBadge(int unreadCount) {
  if (PlatformInfos.isAndroid) {
    if (unreadCount == 0) {
      FlutterNewBadger.removeBadge();
    } else {
      FlutterNewBadger.setBadge(unreadCount);
    }
    return;
  }
}

Future<void> updateSummaryNotification({
  required FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin,
  required String clientName,
  required L10n l10n,
}) async {
  final activeNotifications =
      (await flutterLocalNotificationsPlugin.getActiveNotifications())
          .where((n) => n.groupKey == clientName && n.id != clientName.hashCode)
          .toList();

  if (activeNotifications.isEmpty) {
    await flutterLocalNotificationsPlugin.cancel(id: clientName.hashCode);
    return;
  }

  if (activeNotifications.any(
    (notification) => notification.id == clientName.hashCode,
  )) {
    // Already have a visible summary notification!
    return;
  }

  await flutterLocalNotificationsPlugin.show(
    id: clientName.hashCode,
    notificationDetails: NotificationDetails(
      android: AndroidNotificationDetails(
        AppConfig.pushNotificationsChannelId,
        l10n.incomingMessages,
        groupKey: clientName,
        setAsGroupSummary: true,
        styleInformation: InboxStyleInformation(
          activeNotifications.map((n) => n.body ?? '').toList(),
        ),
        autoCancel: false,
        silent: true,
      ),
    ),
  );
}

class DvChatPushPayload {
  final String? clientName, roomId, eventId;

  DvChatPushPayload(this.clientName, this.roomId, this.eventId);

  factory DvChatPushPayload.fromString(String payload) {
    final parts = payload.split('|');
    if (parts.length != 3) {
      return DvChatPushPayload(null, null, null);
    }
    return DvChatPushPayload(parts.first, parts[1], parts[2]);
  }

  @override
  String toString() => '$clientName|$roomId|$eventId';
}

/// Creates a shortcut for Android platform but does not block displaying the
/// notification. This is optional but provides a nicer view of the
/// notification popup.
Future<void> _setShortcut(
  Event event,
  L10n l10n,
  String title,
  Uint8List? avatarFile,
) async {
  final flutterShortcuts = FlutterShortcuts();
  await flutterShortcuts.initialize(debug: !kReleaseMode);
  await flutterShortcuts.pushShortcutItem(
    shortcut: ShortcutItem(
      id: event.room.id,
      action: AppConfig.inviteLinkPrefix + event.room.id,
      shortLabel: title,
      conversationShortcut: true,
      icon: avatarFile == null ? null : base64Encode(avatarFile),
      shortcutIconAsset: avatarFile == null
          ? ShortcutIconAsset.androidAsset
          : ShortcutIconAsset.memoryAsset,
      isImportant: event.room.isFavourite,
    ),
  );
}

extension on PushNotification {
  String? get clientName =>
      devices?.firstOrNull?.data?.tryGet<String>('client_name');
  int get notificationId {
    final roomId = this.roomId;
    if (roomId == null) return 0;
    final clientName = this.clientName;
    if (clientName == null) return roomId.hashCode;
    return '${clientName}_$roomId'.hashCode;
  }
}
