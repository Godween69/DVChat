// SPDX-License-Identifier: AGPL-3.0-or-later

// DVChat: равные права в личных чатах. В личном чате нет «владельца»: закреплять сообщения
// могут оба. Тот, кто создал чат (и потому может менять права), один раз выравнивает их.

import 'dart:async';

import 'package:matrix/matrix.dart';

abstract class DvDmRights {
  static final Set<String> _done = {};
  static StreamSubscription<SyncUpdate>? _sub;
  static Client? _watched;
  static bool _busy = false;

  static void watch(Client client) {
    if (identical(_watched, client)) return;
    _sub?.cancel();
    _watched = client;
    _done.clear();
    unawaited(ensure(client));
    _sub = client.onSync.stream
        .where((s) => s.hasRoomUpdate)
        .listen((_) => unawaited(ensure(client)));
  }

  static Future<void> ensure(Client client) async {
    if (_busy) return;
    _busy = true;
    try {
      for (final room in client.rooms) {
        if (_done.contains(room.id)) continue;
        if (room.membership != Membership.join || !room.isDirectChat) continue;
        final state = room.getState(EventTypes.RoomPowerLevels);
        if (state == null) continue;
        final content = Map<String, Object?>.from(state.content);
        final events = Map<String, Object?>.from(
          (content['events'] as Map?) ?? const <String, Object?>{},
        );
        if (events[EventTypes.RoomPinnedEvents] == 0) {
          _done.add(room.id);
          continue;
        }
        // Менять права может только тот, у кого они есть: остальные подождут создателя чата
        if (!room.canChangeStateEvent(EventTypes.RoomPowerLevels)) continue;
        events[EventTypes.RoomPinnedEvents] = 0;
        content['events'] = events;
        _done.add(room.id);
        try {
          await client.setRoomStateWithKey(
            room.id,
            EventTypes.RoomPowerLevels,
            '',
            content,
          );
        } catch (e) {
          Logs().v('DVChat: не удалось выровнять права в личном чате', e);
        }
      }
    } finally {
      _busy = false;
    }
  }
}
