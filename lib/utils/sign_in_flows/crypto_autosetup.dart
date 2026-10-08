// DVChat: тихая настройка шифрования после входа по ссылке.
// Пользователь уже в списке чатов и ничего не видит.

import 'dart:async';

import 'package:fluffychat/widgets/fluffy_chat_app.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/encryption.dart';
import 'package:matrix/matrix.dart';

/// Создаёт или открывает крипто-идентичность кодовой фразой из ссылки.
/// Возвращает true при успехе.
Future<bool> setupCryptoSilently(Client client, String passphrase) async {
  try {
    // 1. Ждём первую синхронизацию: сразу после входа account data ещё не загружена
    if (client.prevBatch == null) {
      await client.onSync.stream.first.timeout(const Duration(seconds: 60));
    }

    // 2. Состояние смотрим уже после синхронизации
    final state = await client.getCryptoIdentityState();
    if (state.connected) return true;
    if (!state.initialized) {
      // Первый вход: создаём идентичность с нашей фразой (сервер попросит пароль,
      // его автоматически подставит cachedPassword)
      await client.initCryptoIdentity(passphrase: passphrase);
    } else {
      // Повторный вход: открываем существующую той же фразой
      await client.restoreCryptoIdentity(passphrase);
    }

    // 3. Подтягиваем ключи комнат из онлайн-копии
    try {
      await client.encryption?.keyManager.loadAllKeys();
    } catch (e, s) {
      Logs().w('DVChat: не удалось загрузить ключи комнат', e, s);
    }

    // 4. Просим ключи для уже полученных нечитаемых сообщений
    for (final room in client.rooms) {
      final lastEvent = room.lastEvent;
      if (lastEvent == null ||
          lastEvent.messageType != MessageTypes.BadEncrypted ||
          lastEvent.content['can_request_session'] != true) {
        continue;
      }
      final sessionId = lastEvent.content.tryGet<String>('session_id');
      final senderKey = lastEvent.content.tryGet<String>('sender_key');
      if (sessionId != null && senderKey != null) {
        client.encryption?.keyManager.maybeAutoRequest(
          room.id,
          sessionId,
          senderKey,
        );
      }
    }
    return true;
  } on InvalidPassphraseException catch (e) {
    Logs().w('DVChat: кодовая фраза не подошла к существующей идентичности', e);
    _showFailure('кодовая фраза не подошла');
    return false;
  } catch (e, s) {
    Logs().w('DVChat: тихая настройка шифрования не удалась', e, s);
    _showFailure('$e');
    return false;
  }
}

// Временно показываем причину сбоя (потом заменим на короткое сообщение)
void _showFailure(String reason) {
  final context =
      FluffyChatApp.router.routerDelegate.navigatorKey.currentContext;
  if (context == null || !context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text('Шифрование не настроено: $reason'),
      duration: const Duration(seconds: 20),
    ),
  );
}
