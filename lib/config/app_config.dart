// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// DVChat: Константы приложения: идентификатор, ссылки (код, обращения), цвета, имена каналов уведомлений.

import 'dart:ui';

abstract class AppConfig {
  static const Color primaryColor = Color(0xFF261386);

  static const Color chatColor = primaryColor;
  static const double messageFontSize = 16.0;

  // DVChat: единственный разрешённый сервер, выбор другого запрещён
  static const bool allowOtherHomeservers = false;
  // DVChat: регистрацию отключаем, аккаунты выдаёт админ
  static const bool enableRegistration = false;
  static const bool hideTypingUsernames = false;

  // DVChat: сервер, к которому привязано приложение (без схемы https://).
  // Задаётся при сборке из файла dvchat.env (DVCHAT_HOMESERVER), см. docs/DEPLOY.md
  static const String defaultHomeserver = String.fromEnvironment(
    'DVCHAT_HOMESERVER',
    defaultValue: 'chat.example.org',
  );

  // DVChat: адрес шлюза уведомлений Matrix (его получает Synapse при регистрации push).
  // Задаётся при сборке из файла dvchat.env (DVCHAT_PUSH_GATEWAY)
  static const String pushGatewayUrl = String.fromEnvironment(
    'DVCHAT_PUSH_GATEWAY',
    defaultValue: 'https://push.example.org/_matrix/push/v1/notify',
  );

  // DVChat: формат ссылки/QR для входа: dvchat://login#<base64url(JSON)>
  // JSON: {"c":"одноразовый код"}; данные для входа по коду выдаёт сервер.
  // Фрагмент после # по сети не уходит.
  static const String loginLinkScheme = 'dvchat';
  static const String loginLinkHost = 'login';

  static const String inviteLinkPrefix = 'https://matrix.to/#/';
  static const String deepLinkPrefix = 'dvchat://chat/';
  static const String schemePrefix = 'matrix:';
  static const String pushNotificationsChannelId = 'dvchat_push';
  static const String pushNotificationsAppId = 'online.dvbstudio.dvchat';
  static const double borderRadius = 18.0;
  static const double columnWidth = 360.0;

  static const String appId = 'online.dvbstudio.dvchat';

  static const String sourceCodeUrl = 'https://github.com/Godween69/DVChat';

  static const Set<String> defaultReactions = {'👍', '❤️', '😂', '😮', '😢'};

  static final Uri newIssueUrl = Uri(
    scheme: 'https',
    host: 'github.com',
    path: '/Godween69/DVChat/issues/new',
  );

  static const String mainIsolatePortName = 'main_isolate';
  static const String pushIsolatePortName = 'push_isolate';
  static const String pushHelperCrashReportKey = 'push_helper_crash_report';

  static const String vodozemacVersion = '0.8.1';

  // DVChat: пометки комнат для архива (из чата никто не выходит)
  static const String archiveTag = 'u.dvchat.archive';
  static const String hiddenTag = 'u.dvchat.hidden';

  // DVChat: канал обновлений (веб-сервер с version.json и dvchat.apk).
  // Адрес (с секретом) подставляет сборка
  // из файла dvchat.env (DVCHAT_UPDATE_URL), в репозитории его нет
  static const String updateBaseUrl = String.fromEnvironment(
    'DVCHAT_UPDATE_URL',
  );
}
