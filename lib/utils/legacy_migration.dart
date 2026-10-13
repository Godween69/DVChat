// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// DVChat: одноразовый перенос данных со старых имён на новые.
//
// Приложение унаследовало от FluffyChat имена ключей, под которыми хранит настройки,
// пин-код и список аккаунтов. Чтобы после переименования ничего не потерялось, при
// запуске значения копируются на новые имена, а старые удаляются.
// Все старые имена собраны ЗДЕСЬ. Когда все установки обновятся, файл можно удалить
// вместе с двумя вызовами (AppSettings.init и startGui).

import 'dart:io';

import 'package:dvchat/utils/platform_infos.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:matrix/matrix_api_lite/utils/logs.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Старые префиксы ключей SharedPreferences -> новый префикс.
/// 'chat.fluffy.*' это настройки, 'im.fluffychat.*' это список аккаунтов.
const Map<String, String> _legacyPrefixes = {
  'chat.fluffy.': 'dvchat.',
  'im.fluffychat.': 'dvchat.',
};

/// Переносит ключи настроек. Дёшево и безопасно запускать при каждом старте:
/// когда старых ключей нет, цикл ничего не делает.
Future<void> migrateLegacySettings(SharedPreferences store) async {
  for (final oldKey in store.getKeys().toList()) {
    for (final entry in _legacyPrefixes.entries) {
      if (!oldKey.startsWith(entry.key)) continue;
      final newKey = entry.value + oldKey.substring(entry.key.length);
      try {
        final value = store.get(oldKey);
        if (value != null && !store.containsKey(newKey)) {
          if (value is bool) {
            await store.setBool(newKey, value);
          } else if (value is int) {
            await store.setInt(newKey, value);
          } else if (value is double) {
            await store.setDouble(newKey, value);
          } else if (value is String) {
            await store.setString(newKey, value);
          } else if (value is List) {
            await store.setStringList(newKey, value.cast<String>());
          }
        }
        await store.remove(oldKey);
      } catch (e, s) {
        Logs().w('Не удалось перенести ключ $oldKey', e, s);
      }
      break;
    }
  }
}

const String _platformMigrationDoneKey = 'dvchat.legacy_platform_migrated';

/// Пин-код приложения, старые каналы уведомлений и кэш скачанных файлов.
/// Выполняется один раз и только когда приложение открыто на экране
/// (удаление канала останавливает работающую фоновую службу).
Future<void> migrateLegacyPlatformData(SharedPreferences store) async {
  if (store.getBool(_platformMigrationDoneKey) == true) return;
  try {
    const secure = FlutterSecureStorage();
    const secureKeys = {
      'chat.fluffy.app_lock': 'dvchat.app_lock',
      'chat.fluffy.use_biometrics': 'dvchat.use_biometrics',
    };
    for (final entry in secureKeys.entries) {
      final value = await secure.read(key: entry.key);
      if (value == null) continue;
      if (await secure.read(key: entry.value) == null) {
        await secure.write(key: entry.value, value: value);
      }
      await secure.delete(key: entry.key);
    }

    if (PlatformInfos.isAndroid) {
      final android = FlutterLocalNotificationsPlugin()
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      await android?.deleteNotificationChannel(channelId: 'fluffychat_push');
      await android?.deleteNotificationChannel(channelId: 'fluffychat_sync');

      final temporary = await getTemporaryDirectory();
      final oldCache = Directory(
        join(temporary.path, 'fluffychat_download_cache'),
      );
      if (await oldCache.exists()) await oldCache.delete(recursive: true);
    }
    await store.setBool(_platformMigrationDoneKey, true);
  } catch (e, s) {
    Logs().w(
      'Не удалось перенести данные платформы, повторим при запуске',
      e,
      s,
    );
  }
}
