// SPDX-License-Identifier: AGPL-3.0-or-later

// DVChat: уведомления «собеседник прочитал ваше сообщение».
// Отметка о прочтении в Matrix это не событие, и сервер пуш по ней не шлёт. Поэтому
// читающий (в личном чате) отправляет скрытое событие dv.read, а тот, чьё сообщение
// прочитали, получает его пушем (как реакции) и показывает уведомление, если включил.

import 'dart:async';

import 'package:collection/collection.dart';
import 'package:dvchat/utils/dv_last_event.dart';
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

bool _isHiddenType(String type) =>
    type == dvReadEventType || type == 'dv.game' || type == 'dv.story';

/// Скрытые события (dv.read, dv.story и ходы игр) сервер считает новыми уведомлениями и поднимает
/// счётчик непрочитанных, хотя в чате ничего нового нет. Если настоящих непрочитанных сообщений
/// нет, счётчик сбрасывается личной отметкой на этом событии. То же делается после синхронизации
/// (не чаще раза в 20 секунд): события могли прийти, пока приложение было закрыто.
StreamSubscription<Event> attachHiddenEventCleaner(Client client) {
  var lastSweep = DateTime.fromMillisecondsSinceEpoch(0);
  // подписка живёт столько же, сколько клиент
  client.onSync.stream.listen((_) {
    final now = DateTime.now();
    if (now.difference(lastSweep) < const Duration(seconds: 20)) return;
    lastSweep = now;
    unawaited(_sweepHiddenUnread(client));
  });
  return client.onTimelineEvent.stream
      .where((e) => _isHiddenType(e.type) && e.senderId != client.userID)
      .listen((e) async {
        // Счётчик комнаты обновляется чуть позже самого события
        await Future<void>.delayed(const Duration(seconds: 1));
        final room = client.getRoomById(e.roomId ?? '');
        if (room == null) return;
        await _clearIfOnlyHidden(client, room);
      });
}

Future<void> _sweepHiddenUnread(Client client) async {
  for (final room in client.rooms) {
    await _clearIfOnlyHidden(client, room);
  }
}

/// Сбрасывает счётчик комнаты, если последнее событие служебное, а настоящих непрочитанных нет
Future<void> _clearIfOnlyHidden(Client client, Room room) async {
  if (room.membership != Membership.join || room.notificationCount == 0) {
    return;
  }
  final last = room.lastEvent;
  if (last == null || !last.type.startsWith('dv.')) return;
  // Поиск настоящего последнего сообщения запускается здесь же; если он ещё идёт,
  // комната будет проверена при следующей синхронизации
  final real = DvLastEvent.of(room);
  if (!DvLastEvent.resolved(room)) return;
  if (real != null &&
      real.senderId != client.userID &&
      real.eventId != room.fullyRead) {
    return;
  }
  try {
    await client.postReceipt(room.id, ReceiptType.mReadPrivate, last.eventId);
  } catch (_) {
    // Не получилось: счётчик сбросится при открытии чата
  }
}
