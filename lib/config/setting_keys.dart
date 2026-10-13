// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:async/async.dart';
import 'package:dvchat/utils/legacy_migration.dart';
import 'package:dvchat/utils/platform_infos.dart';
import 'package:matrix/matrix_api_lite/utils/logs.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppSettings<T> {
  textMessageMaxLength<int>('textMessageMaxLength', 16384),

  /// Max lines for unselected HTML/text bubbles; 0 = unlimited (no fade).
  messagePreviewMaxLines<int>('dvchat.message_preview_max_lines', 50),
  audioRecordingNumChannels<int>('audioRecordingNumChannels', 1),
  audioRecordingAutoGain<bool>('audioRecordingAutoGain', true),
  audioRecordingEchoCancel<bool>('audioRecordingEchoCancel', false),
  audioRecordingNoiseSuppress<bool>('audioRecordingNoiseSuppress', true),
  audioRecordingBitRate<int>('audioRecordingBitRate', 64000),
  audioRecordingSamplingRate<int>('audioRecordingSamplingRate', 48000),
  showNoGoogle<bool>('dvchat.show_no_google', false),
  unifiedPushRegistered<bool>('dvchat.unifiedpush.registered', false),
  unifiedPushEndpoint<String>('dvchat.unifiedpush.endpoint', ''),
  pushNotificationsGatewayUrl<String>(
    'pushNotificationsGatewayUrl',
    'http://172.30.50.2:8080/_matrix/push/v1/notify',
  ),
  pushNotificationsPusherFormat<String>(
    'pushNotificationsPusherFormat',
    'event_id_only',
  ),
  renderHtml<bool>('dvchat.renderHtml', true),
  fontSizeFactor<double>('dvchat.font_size_factor', 1.0),
  hideRedactedEvents<bool>('dvchat.hideRedactedEvents', false),
  hideUnknownEvents<bool>('dvchat.hideUnknownEvents', true),
  autoplayImages<bool>('dvchat.autoplay_images', true),
  voiceMessageSpeedPercent<int>('dvchat.voice_message_speed', 100),
  archiveDeleteConfirm<bool>('dvchat.archive_delete_confirm', true),
  notifyAboutReactions<bool>('dvchat.notify_about_reactions', true),
  sendTypingNotifications<bool>('dvchat.send_typing_notifications', true),
  sendPublicReadReceipts<bool>('dvchat.send_public_read_receipts', true),
  swipeRightToLeftToReply<bool>('dvchat.swipeRightToLeftToReply', true),
  sendOnEnter<bool>('dvchat.send_on_enter', false),
  shareKeysWith<String>('dvchat.share_keys_with_2', 'all'),
  noEncryptionWarningShown<bool>('dvchat.no_encryption_warning_shown', false),
  displayChatDetailsColumn('dvchat.display_chat_details_column', false),
  // AppConfig-mirrored settings
  applicationName<String>('dvchat.application_name', 'DVChat'),
  defaultHomeserver<String>(
    'dvchat.default_homeserver',
    'chat.dvbstudio.online',
  ),
  // colorSchemeSeed stored as ARGB int
  colorSchemeSeedInt<int>('dvchat.color_scheme_seed', 0xFF5625BA),
  emojiSuggestionLocale<String>('emoji_suggestion_locale', ''),
  enableSoftLogout<bool>('dvchat.enable_soft_logout', true),
  sendTimelineEventTimeout<int>('dvchat.send_timeline_event_timeout', 15),
  webNotificationSound<bool>('dvchat.web_notification_sound', true),
  chatFilter<String>('dvchat.chat_filter', 'allChats'),
  showThumbnailsInTimeline<bool>('dvchat.showThumbnailsInTimeline', true),
  doubleTapToReact<bool>('dvchat.double_tap_to_react', false),
  // DVChat: цвет фона чата (ARGB, 0 = по умолчанию)
  chatBackgroundColorInt<int>('dvchat.chat_background_color', 0),
  doubleTapReaction<String>('dvchat.double_tap_reaction', '❤️'),
  benchmarksInLogs<bool>('dvchat.benchmarks_in_logs', false),
  autoSendErrorReports<bool?>('dvchat.auto_send_eror_reports', null),
  knownErrorHashes<List<String>>('dvchat.known_crash_hashes', []),
  checkForUpdates<bool>('dvchat.check_for_updates', true),
  lastUpdateCheckDate<String>('dvchat.last_update_check_date', '');

  final String key;
  final T _defaultValue;

  const AppSettings(this.key, this._defaultValue);

  static SharedPreferences get store => _store!;
  static SharedPreferences? _store;

  T get defaultValue => _defaultValue;

  static Future<void> reset() async {
    await AppSettings._store!.clear();
    await init();
  }

  static Future<SharedPreferences> init() async {
    if (AppSettings._store != null) return AppSettings.store;

    final store = AppSettings._store = await SharedPreferences.getInstance();

    // DVChat: перенос ключей со старых имён (одноразово, потом цикл пустой)
    await migrateLegacySettings(store);

    // Migrate wrong datatype for fontSizeFactor
    final fontSizeFactorString = Result(
      () => store.getString(AppSettings.fontSizeFactor.key),
    ).asValue?.value;
    if (fontSizeFactorString != null) {
      Logs().i('Migrate wrong datatype for fontSizeFactor!');
      await store.remove(AppSettings.fontSizeFactor.key);
      final fontSizeFactor = double.tryParse(fontSizeFactorString);
      if (fontSizeFactor != null) {
        await store.setDouble(AppSettings.fontSizeFactor.key, fontSizeFactor);
      }
    }

    if (store.getBool(AppSettings.sendOnEnter.key) == null) {
      await store.setBool(AppSettings.sendOnEnter.key, !PlatformInfos.isMobile);
    }
    if (store.getBool(AppSettings.doubleTapToReact.key) == null) {
      await store.setBool(
        AppSettings.doubleTapToReact.key,
        PlatformInfos.isMobile,
      );
    }

    return store;
  }
}

extension AppSettingsBoolNExtension on AppSettings<bool?> {
  bool? get value {
    final value = Result(() => AppSettings.store.getBool(key));
    final error = value.asError;
    if (error != null) {
      Logs().e(
        'Unable to fetch $key from storage. Removing entry...',
        error.error,
        error.stackTrace,
      );
    }
    return value.asValue?.value;
  }

  Future<void> setItem(bool value) => AppSettings.store.setBool(key, value);
}

extension AppSettingsBoolExtension on AppSettings<bool> {
  bool get value {
    final value = Result(() => AppSettings.store.getBool(key));
    final error = value.asError;
    if (error != null) {
      Logs().e(
        'Unable to fetch $key from storage. Removing entry...',
        error.error,
        error.stackTrace,
      );
    }
    return value.asValue?.value ?? defaultValue;
  }

  Future<void> setItem(bool value) => AppSettings.store.setBool(key, value);
}

extension AppSettingsStringExtension on AppSettings<String> {
  String get value {
    final value = Result(() => AppSettings.store.getString(key));
    final error = value.asError;
    if (error != null) {
      Logs().e(
        'Unable to fetch $key from storage. Removing entry...',
        error.error,
        error.stackTrace,
      );
    }
    return value.asValue?.value ?? defaultValue;
  }

  Future<void> setItem(String value) => AppSettings.store.setString(key, value);
}

extension AppSettingsIntExtension on AppSettings<int> {
  int get value {
    final value = Result(() => AppSettings.store.getInt(key));
    final error = value.asError;
    if (error != null) {
      Logs().e(
        'Unable to fetch $key from storage. Removing entry...',
        error.error,
        error.stackTrace,
      );
    }
    return value.asValue?.value ?? defaultValue;
  }

  Future<void> setItem(int value) => AppSettings.store.setInt(key, value);
}

extension AppSettingsDoubleExtension on AppSettings<double> {
  double get value {
    final value = Result(() => AppSettings.store.getDouble(key));
    final error = value.asError;
    if (error != null) {
      Logs().e(
        'Unable to fetch $key from storage. Removing entry...',
        error.error,
        error.stackTrace,
      );
    }
    return value.asValue?.value ?? defaultValue;
  }

  Future<void> setItem(double value) => AppSettings.store.setDouble(key, value);
}

extension AppSettingsStringListExtension on AppSettings<List<String>> {
  List<String> get value {
    final value = Result(() => AppSettings.store.getStringList(key));
    final error = value.asError;
    if (error != null) {
      Logs().e(
        'Unable to fetch $key from storage. Removing entry...',
        error.error,
        error.stackTrace,
      );
    }
    return value.asValue?.value ?? defaultValue;
  }

  Future<void> setItem(List<String> value) =>
      AppSettings.store.setStringList(key, value);
}
