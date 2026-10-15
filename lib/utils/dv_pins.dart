// SPDX-License-Identifier: AGPL-3.0-or-later

// DVChat: закреплённые сообщения с датой закрепления. Дата хранится рядом со списком
// закреплённых в том же событии комнаты (поле dv.pinned_at: id сообщения -> время в мс).
// У старых закрепов даты нет, она не показывается.

import 'package:matrix/matrix.dart';

abstract class DvPins {
  static const String stampsKey = 'dv.pinned_at';

  static const List<String> _months = [
    'января',
    'февраля',
    'марта',
    'апреля',
    'мая',
    'июня',
    'июля',
    'августа',
    'сентября',
    'октября',
    'ноября',
    'декабря',
  ];

  /// Когда что закреплено: id сообщения -> время в миллисекундах
  static Map<String, int> stamps(Room room) {
    final raw = room.getState(EventTypes.RoomPinnedEvents)?.content[stampsKey];
    if (raw is! Map) return {};
    return {
      for (final entry in raw.entries)
        if (entry.value is int) entry.key.toString(): entry.value as int,
    };
  }

  /// Записывает новый список закреплённых. Новым закрепам ставит текущее время,
  /// у прежних сохраняет прежнюю дату.
  static Future<void> save(Room room, List<String> ids) async {
    final old = stamps(room);
    final existing = room.pinnedEventIds.toSet();
    final now = DateTime.now().millisecondsSinceEpoch;
    final next = <String, int>{};
    for (final id in ids) {
      final time = old[id] ?? (existing.contains(id) ? null : now);
      if (time != null) next[id] = time;
    }
    await room.client.setRoomStateWithKey(
      room.id,
      EventTypes.RoomPinnedEvents,
      '',
      {'pinned': ids, stampsKey: next},
    );
  }

  /// «15 октября, 11:30» (с годом, если не текущий)
  static String when(int millis) {
    final d = DateTime.fromMillisecondsSinceEpoch(millis);
    final year = d.year == DateTime.now().year ? '' : ' ${d.year}';
    final hh = d.hour.toString().padLeft(2, '0');
    final mm = d.minute.toString().padLeft(2, '0');
    return '${d.day} ${_months[d.month - 1]}$year, $hh:$mm';
  }
}
