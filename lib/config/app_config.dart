// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

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

  // DVChat: захардкоженный homeserver (без схемы https://)
  static const String defaultHomeserver = 'chat.dvbstudio.online';

  // DVChat: формат ссылки/QR для входа: dvchat://login#<base64url(JSON)>
  // JSON: {"u":"логин","p":"пароль"}. Фрагмент после # по сети не уходит.
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
  // Identifies the notification activation callback on Windows. Never change!
  static const String windowsNotificationGuid =
      '4894dfda-c70a-4ebc-b139-acae55f3988d';

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

  // DVChat: канал обновлений на московском сервере. Адрес (с секретом) подставляет сборка
  // через --dart-define=DVCHAT_UPDATE_URL=..., в репозитории его нет
  static const String updateBaseUrl = String.fromEnvironment(
    'DVCHAT_UPDATE_URL',
  );
}
