// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// DVChat: Ключ шифрования локальной базы: создаётся один раз и хранится в защищённом хранилище.
// ВНИМАНИЕ: потеря ключа = потеря локальной истории; не менять без миграции.

import 'dart:convert';
import 'dart:math';

import 'package:dvchat/config/setting_keys.dart';
import 'package:dvchat/l10n/l10n.dart';
import 'package:dvchat/utils/app_locale.dart';
import 'package:dvchat/utils/client_manager.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:matrix/matrix.dart';

const _passwordStorageKey = 'database_password';

Future<String?> getDatabaseCipher() async {
  String? password;

  const storage = FlutterSecureStorage();

  try {
    password = await storage.read(key: _passwordStorageKey);
    if (password != null) return password;

    final rng = Random.secure();
    final list = Uint8List(32);
    list.setAll(0, Iterable.generate(list.length, (i) => rng.nextInt(256)));
    final newPassword = base64UrlEncode(list);
    await storage.write(key: _passwordStorageKey, value: newPassword);
    // workaround for if we just wrote to the key and it still doesn't exist
    password = await storage.read(key: _passwordStorageKey);
    if (password == null) throw MissingPluginException();
    return password;
  } on MissingPluginException catch (e) {
    storage.delete(key: _passwordStorageKey).catchError((_) {});
    Logs().w('Database encryption is not supported on this platform', e);
    _sendNoEncryptionWarning(e);
  } catch (e, s) {
    storage.delete(key: _passwordStorageKey).catchError((_) {});
    Logs().w('Unable to init database encryption', e, s);
    _sendNoEncryptionWarning(e);
  }
  return null;
}

Future<void> _sendNoEncryptionWarning(Object exception) async {
  final isStored = AppSettings.noEncryptionWarningShown.value;

  if (isStored == true) return;

  final l10n = await lookupL10n(appLocale);
  ClientManager.sendInitNotification(
    l10n.noDatabaseEncryption,
    exception.toString(),
  );

  await AppSettings.noEncryptionWarningShown.setItem(true);
}
