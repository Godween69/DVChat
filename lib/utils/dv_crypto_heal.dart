// SPDX-License-Identifier: AGPL-3.0-or-later

// DVChat: самолечение шифрования. Если после выхода и повторного входа ключи не открылись
// (фоновая настройка оборвалась), при каждом запуске берём кодовую фразу у сервера
// и открываем ключи заново. Человек ничего не видит, причины пишутся в журнал.

import 'dart:async';

import 'package:dvchat/utils/dv_api.dart';
import 'package:dvchat/utils/sign_in_flows/crypto_autosetup.dart';
import 'package:matrix/encryption.dart';
import 'package:matrix/matrix.dart';

abstract class DvCryptoHeal {
  static final Set<String> _running = {};

  static Future<void> run(Client client) async {
    final userId = client.userID;
    if (userId == null || !_running.add(userId)) return;
    try {
      for (var attempt = 0; attempt < 4; attempt++) {
        if (!client.isLogged()) return;
        if (client.prevBatch == null) {
          try {
            await client.onSync.stream.first.timeout(
              const Duration(seconds: 60),
            );
          } on TimeoutException {
            // Сеть медленная: ждём ещё, а не бросаем лечение до следующего запуска
            continue;
          }
        }
        final state = await client.getCryptoIdentityState();
        // Идентичности ещё нет (первый вход) или всё уже открыто: лечить нечего
        if (!state.initialized || state.connected) return;
        try {
          final json = await DvApi(client).post('keys/phrase', {});
          final phrase = json['phrase'];
          if (phrase is String && phrase.isNotEmpty) {
            Logs().i(
              'DVChat: ключи шифрования не открыты, открываю фразой с сервера',
            );
            if (await setupCryptoSilently(client, phrase, quiet: true)) return;
          } else {
            Logs().w('DVChat: сервер не вернул кодовую фразу');
          }
        } on DvApiException catch (e) {
          Logs().w(
            'DVChat: кодовая фраза недоступна (${e.status} ${e.errcode})',
          );
        }
        await Future<void>.delayed(Duration(seconds: 30 * (attempt + 1)));
      }
    } catch (e, s) {
      Logs().w('DVChat: самолечение шифрования не удалось', e, s);
    } finally {
      _running.remove(userId);
    }
  }
}
