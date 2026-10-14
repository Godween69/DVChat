// SPDX-License-Identifier: AGPL-3.0-or-later

// DVChat: уведомления «собеседник прочитал ваше сообщение».
// Отметка о прочтении в Matrix это не событие, и сервер пуш по ней не шлёт. Поэтому
// читающий (в личном чате) отправляет скрытое событие dv.read, а тот, чьё сообщение
// прочитали, получает его пушем (как реакции) и показывает уведомление, если включил.

import 'dart:async';

import 'package:matrix/matrix.dart';

const String dvReadEventType = 'dv.read';

final Map<String, String> _lastNotified = {};

/// Сообщает автору, что я прочитал его сообщение (только личные чаты)
Future<void> sendReadNotice(Room room, Event event) async {
  final me = room.client.userID;
  if (me == null || event.senderId == me) return;
  if (!room.isDirectChat || room.membership != Membership.join) return;
  if (event.type != EventTypes.Message) return;
  if (_lastNotified[room.id] == event.eventId) return;
  _lastNotified[room.id] = event.eventId;
  try {
    await room.sendEvent({'event_id': event.eventId}, type: dvReadEventType);
  } catch (_) {
    _lastNotified.remove(room.id);
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
