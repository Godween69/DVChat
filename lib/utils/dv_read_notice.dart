// SPDX-License-Identifier: AGPL-3.0-or-later

// DVChat: уведомления «собеседник прочитал ваше сообщение».
// Отметка о прочтении в Matrix это не событие, и сервер пуш по ней не шлёт. Поэтому
// читающий (в личном чате) отправляет скрытое событие dv.read, а тот, чьё сообщение
// прочитали, получает его пушем (как реакции) и показывает уведомление, если включил.

import 'dart:async';

import 'package:collection/collection.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String dvReadEventType = 'dv.read';

final Set<String> _inFlight = {};

/// Сообщает автору, что я прочитал его последнее сообщение (только личные чаты).
/// Вызывается, когда чат открыт на экране; одно уведомление на одно сообщение
/// (запоминается на диске, чтобы не повторяться после перезапуска).
Future<void> sendReadNotice(Room room, Timeline timeline) async {
  final me = room.client.userID;
  if (me == null || !room.isDirectChat || room.membership != Membership.join) {
    return;
  }
  // Берём последнее настоящее сообщение собеседника, а не служебное событие
  final msg = timeline.events.firstWhereOrNull(
    (e) =>
        e.type == EventTypes.Message && e.senderId != me && e.status.isSynced,
  );
  if (msg == null) return;
  if (!_inFlight.add(room.id)) return;
  final key = 'dv_read_notified_${room.id}';
  try {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString(key) == msg.eventId) return;
    await prefs.setString(key, msg.eventId);
    try {
      await room.sendEvent({'event_id': msg.eventId}, type: dvReadEventType);
    } catch (_) {
      await prefs.remove(key);
    }
  } finally {
    _inFlight.remove(room.id);
  }
}

/// Скрытые события (dv.read и ходы игр) сервер считает новыми уведомлениями и поднимает
/// счётчик непрочитанных, хотя в чате ничего нового нет. Если все видимые сообщения уже
/// прочитаны, счётчик сбрасывается личной отметкой на этом событии.
StreamSubscription<Event> attachHiddenEventCleaner(Client client) => client
    .onTimelineEvent
    .stream
    .where(
      (e) =>
          (e.type == dvReadEventType || e.type == 'dv.game') &&
          e.senderId != client.userID,
    )
    .listen((e) async {
      // Счётчик комнаты обновляется чуть позже самого события
      await Future<void>.delayed(const Duration(seconds: 1));
      final room = client.getRoomById(e.roomId ?? '');
      if (room == null) return;
      if (room.hasNewMessages || room.notificationCount == 0) return;
      try {
        await client.postReceipt(room.id, ReceiptType.mReadPrivate, e.eventId);
      } catch (_) {
        // Не получилось: счётчик сбросится при открытии чата
      }
    });
