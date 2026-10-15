// SPDX-License-Identifier: AGPL-3.0-or-later

// DVChat: последнее видимое событие чата для списка чатов. Скрытые служебные события
// (ходы игр dv.game, «прочитал» dv.read) не должны попадать в подпись строки:
// иначе вместо текста там «User отправил(а) событие типа dv.game».

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart';

class DvLastEvent {
  DvLastEvent._();

  /// Меняется, когда нашлось настоящее сообщение вместо скрытого: список перерисуется
  static final ValueNotifier<int> tick = ValueNotifier<int>(0);

  static final Map<String, ({String id, Event? event})> _cache = {};
  static final Set<String> _busy = {};

  static bool _hidden(Event e) => e.type.startsWith('dv.');

  /// Событие для подписи строки: обычное последнее или, если оно скрытое,
  /// последнее настоящее сообщение до него
  static Event? of(Room room) {
    final last = room.lastEvent;
    if (last == null || !_hidden(last)) return last;
    final cached = _cache[room.id];
    if (cached != null && cached.id == last.eventId) return cached.event;
    _resolve(room, last.eventId);
    // Пока ищем, показываем прежний результат, если он был
    return cached?.event;
  }

  static Future<void> _resolve(Room room, String lastId) async {
    final key = '${room.id}|$lastId';
    if (!_busy.add(key)) return;
    try {
      final timeline = await room.getTimeline(limit: 40);
      final found = timeline.events.firstWhereOrNull(
        (e) =>
            room.client.roomPreviewLastEvents.contains(e.type) &&
            !_hidden(e) &&
            e.relationshipType != RelationshipTypes.edit,
      );
      timeline.cancelSubscriptions();
      _cache[room.id] = (id: lastId, event: found);
      tick.value++;
    } catch (_) {
      // Не вышло: строка останется без подписи, при следующем событии попробуем снова
    } finally {
      _busy.remove(key);
    }
  }
}
