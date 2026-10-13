// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
// Copyright (C) 2020, 2021 Famedly GmbH
// Copyright (C) 2021 Fluffychat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// DVChat: Регистрация приложения на получение пушей: токен FCM отправляется на сервер Matrix
// (pusher), дальше сообщение идёт Synapse → шлюз dvchatgate → FCM → телефон.

import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:ui';

import 'package:dvchat/l10n/l10n.dart';
import 'package:dvchat/main.dart';
import 'package:dvchat/utils/app_locale.dart';
import 'package:dvchat/utils/notification_background_handler.dart';
import 'package:dvchat/utils/push_helper.dart';
import 'package:dvchat/utils/reaction_push_rule.dart';
import 'package:dvchat/widgets/dvchat_app.dart';
import 'package:fcm_shared_isolate/fcm_shared_isolate.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

import '../config/app_config.dart';
import '../config/setting_keys.dart';
import '../widgets/matrix.dart';
import 'platform_infos.dart';

class BackgroundPush {
  static BackgroundPush? _instance;
  final FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  List<Client> _clients;

  List<Client> get clients => matrix?.widget.clients ?? _clients;

  MatrixState? matrix;
  String? _fcmToken;

  String? get fcmToken => _fcmToken;
  void Function(String errorMsg, {Uri? link})? onFcmError;
  L10n? l10n;

  Future<void> loadLocale() async {
    final context = matrix?.context;
    // inspired by _lookupL10n in .dart_tool/flutter_gen/gen_l10n/l10n.dart
    l10n ??=
        (context != null && context.mounted ? L10n.of(context) : null) ??
        (await L10n.delegate.load(appLocale));
  }

  final pendingTests = <String, Completer<void>>{};
  bool firebaseEnabled = false;

  final firebase = FcmSharedIsolate();

  DateTime? lastReceivedPush;

  Future<void> _init() async {
    firebaseEnabled = true;
    try {
      mainIsolateReceivePort?.listen((message) async {
        try {
          await notificationTap(
            NotificationResponseJson.fromJsonString(message),
            clients: clients,
            router: DvChatApp.router,
            l10n: l10n,
          );
        } catch (e, s) {
          Logs().wtf('Main Notification Tap crashed', e, s);
        }
      });
      if (PlatformInfos.isAndroid) {
        final port = ReceivePort();
        IsolateNameServer.removePortNameMapping('background_tab_port');
        IsolateNameServer.registerPortWithName(
          port.sendPort,
          'background_tab_port',
        );
        port.listen((message) async {
          try {
            await notificationTap(
              NotificationResponseJson.fromJsonString(message),
              clients: clients,
              router: DvChatApp.router,
              l10n: l10n,
            );
          } catch (e, s) {
            Logs().wtf('Main Notification Tap crashed', e, s);
          }
        });
      }
      await _flutterLocalNotificationsPlugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('notifications_icon'),
        ),
        onDidReceiveNotificationResponse: (response) => notificationTap(
          response,
          clients: clients,
          router: DvChatApp.router,
          l10n: l10n,
        ),
        onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
      );
      Logs().v('Flutter Local Notifications initialized');
      firebase.setListeners(
        onMessage: (message) => pushHelper(
          PushNotification.fromJson(
            message.tryGetMap<String, Object>('data') ?? message,
          ),
          clients: clients,
          l10n: l10n,
          activeRoomId: matrix?.activeRoomId,
          flutterLocalNotificationsPlugin: _flutterLocalNotificationsPlugin,
        ),
      );
    } catch (e, s) {
      Logs().e('Unable to initialize Flutter local notifications', e, s);
    }
  }

  BackgroundPush._(this._clients) {
    _init();
  }

  factory BackgroundPush.clientOnly(List<Client> clients) {
    return _instance ??= BackgroundPush._(clients);
  }

  factory BackgroundPush(
    MatrixState matrix, {
    void Function(String errorMsg, {Uri? link})? onFcmError,
  }) {
    final instance = BackgroundPush.clientOnly(matrix.widget.clients);
    instance.matrix = matrix;
    // ignore: prefer_initializing_formals
    instance.onFcmError = onFcmError;
    return instance;
  }

  /// Makes sure that there is exactly ONE pusher with these settings for this
  /// client and deletes all other pushers if not.
  Future<void> setupPusher({
    required Client client,
    String? gatewayUrl,
    String? token,
  }) async {
    if (PlatformInfos.isAndroid) {
      _flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
    }
    final appDisplayName = PlatformInfos.appDisplayName;

    final pushers =
        await (client.getPushers().catchError((e) {
          Logs().w('[Push] Unable to request pushers', e);
          return <Pusher>[];
        })) ??
        [];

    // we need the deviceAppId to remove potential legacy pusher
    var deviceAppId = '${AppConfig.pushNotificationsAppId}.${client.deviceID}';
    // appId may only be up to 64 chars as per spec
    if (deviceAppId.length > 64) {
      deviceAppId = deviceAppId.substring(0, 64);
    }
    final thisAppId = deviceAppId;
    if (gatewayUrl == null || token == null) {
      Logs().w('[Push] Missing required push credentials');
      return;
    }

    if (pushers.any(
      (currentPusher) =>
          currentPusher.pushkey == token &&
          currentPusher.data.additionalProperties['client_name'] ==
              client.clientName &&
          currentPusher.kind == 'http' &&
          currentPusher.appId == thisAppId &&
          currentPusher.appDisplayName == appDisplayName &&
          currentPusher.deviceDisplayName == client.deviceName &&
          currentPusher.lang == 'en' &&
          currentPusher.data.url.toString() == gatewayUrl &&
          currentPusher.data.format ==
              AppSettings.pushNotificationsPusherFormat.value &&
          currentPusher.data.additionalProperties['data_message'] ==
              pusherDataMessageFormat,
    )) {
      Logs().i('[Push] Pusher already set for ${client.deviceID}');
      return;
    }

    if (!client.isLogged()) return;

    final legacyPushers = pushers.where((pusher) => pusher.appId == thisAppId);
    for (final pusher in legacyPushers) {
      try {
        await client.deletePusher(pusher);
        Logs().i('[Push] Removed legacy pusher for ${client.deviceID}');
      } catch (err) {
        Logs().w(
          '[Push] Failed to remove old pusher for ${client.deviceID}',
          err,
        );
      }
    }

    Logs().i('Need to set new pusher for ${client.clientName}');
    try {
      await client.postPusher(
        Pusher(
          pushkey: token,
          appId: thisAppId,
          appDisplayName: appDisplayName,
          deviceDisplayName: PlatformInfos.appDisplayName,
          lang: 'en',
          data: PusherData(
            url: Uri.parse(gatewayUrl),
            format: AppSettings.pushNotificationsPusherFormat.value,
            additionalProperties: {
              'client_name': client.clientName,
              'data_message': pusherDataMessageFormat,
            },
          ),
          kind: 'http',
        ),
        append: true,
      );
    } catch (e, s) {
      Logs().e('[Push] Unable to set pushers', e, s);
    }
  }

  final pusherDataMessageFormat = Platform.isAndroid;

  static bool _wentToRoomOnStartup = false;

  Future<void> setupPush(BuildContext context) async {
    for (final client in clients) {
      Logs().d('SetupPush for Client ${client.clientName}');
      if (client.onLoginStateChanged.value != LoginState.loggedIn ||
          !PlatformInfos.isMobile ||
          matrix == null) {
        return;
      }
      await setupFirebase(client);
      try {
        await syncReactionPushRule(
          client,
          on: AppSettings.notifyAboutReactions.value,
        );
      } catch (e, s) {
        Logs().w('[Push] Unable to sync reaction push rule', e, s);
      }
    }

    // ignore: unawaited_futures
    _flutterLocalNotificationsPlugin.getNotificationAppLaunchDetails().then((
      details,
    ) {
      if (details == null ||
          !details.didNotificationLaunchApp ||
          _wentToRoomOnStartup) {
        return;
      }
      _wentToRoomOnStartup = true;
      final response = details.notificationResponse;
      if (response != null) {
        notificationTap(
          response,
          clients: clients,
          router: DvChatApp.router,
          l10n: l10n,
        );
      }
    });
  }

  Future<void> _noFcmWarning() async {
    // DVChat: предупреждение об отсутствии Google-сервисов клиентам не показываем
  }

  Future<void> setupFirebase(Client client) async {
    Logs().v('Setup firebase');
    if (!firebaseEnabled) {
      await _noFcmWarning();
      return;
    }
    if (_fcmToken?.isEmpty ?? true) {
      const max = 5;
      for (var i = 0; i < max; i++) {
        try {
          await Future.delayed(const Duration(seconds: 1));
          _fcmToken = await firebase.getToken();
          if (_fcmToken != null) break;
        } catch (e, s) {
          Logs().w(
            '[Push] cannot get token - try ($i/$max)',
            e,
            e is String ? null : s,
          );
        }
      }
      if (_fcmToken == null) {
        await _noFcmWarning();
        return;
      }
    }
    await setupPusher(
      client: client,
      gatewayUrl: AppSettings.pushNotificationsGatewayUrl.value,
      token: _fcmToken,
    );
  }
}
