// SPDX-License-Identifier: AGPL-3.0-or-later

// DVChat: сигнал «записывает голосовое». Это не событие в чате, а короткое сообщение
// «устройству напрямую» (to-device): оно ничего не оставляет в переписке и не вызывает
// уведомлений. Пока человек записывает, сигнал повторяется каждые 4 секунды; получатель
// считает запись идущей ещё 7 секунд после последнего сигнала.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart';

class DvRecordingSignal {
  static const String type = 'dv.recording';

  // ---------- получение ----------
  static final Map<String, DateTime> _until = {};

  /// Меняется, когда у кого-то началась или кончилась запись
  static final ValueNotifier<int> changes = ValueNotifier<int>(0);

  /// Начинает слушать сигналы клиента
  static void attach(Client client) {
    client.onToDeviceEvent.stream.listen((e) {
      if (e.type != type) return;
      final roomId = e.content['room_id'];
      if (roomId is! String) return;
      final key = '$roomId|${e.sender}';
      if (e.content['on'] == false) {
        _until.remove(key);
      } else {
        _until[key] = DateTime.now().add(const Duration(seconds: 7));
        // через 7 секунд без нового сигнала запись считается законченной
        Timer(const Duration(seconds: 7, milliseconds: 200), () => changes.value++);
      }
      changes.value++;
    });
  }

  /// Кто сейчас записывает голосовое в этой комнате
  static List<String> recorders(String roomId) {
    final now = DateTime.now();
    final out = <String>[];
    _until.removeWhere((_, t) => t.isBefore(now));
    for (final e in _until.entries) {
      if (e.key.startsWith('$roomId|')) out.add(e.key.substring(roomId.length + 1));
    }
    return out;
  }

  // ---------- отправка ----------
  static Timer? _beat;
  static Room? _room;

  static void start(Room room) {
    stop();
    _room = room;
    unawaited(_send(room, true));
    _beat = Timer.periodic(const Duration(seconds: 4), (_) => _send(room, true));
  }

  static void stop() {
    _beat?.cancel();
    _beat = null;
    final room = _room;
    _room = null;
    if (room != null) unawaited(_send(room, false));
  }

  static Future<void> _send(Room room, bool on) async {
    try {
      final me = room.client.userID;
      final targets = room
          .getParticipants()
          .where((u) => u.membership == Membership.join && u.id != me)
          .map((u) => u.id)
          .take(8)
          .toList();
      if (targets.isEmpty) return;
      await room.client.sendToDevice(
        type,
        room.client.generateUniqueTransactionId(),
        {
          for (final id in targets)
            id: {
              '*': {'room_id': room.id, 'on': on},
            },
        },
      );
    } catch (_) {
      // сигнал необязателен: нет сети, значит, и показывать нечего
    }
  }
}
