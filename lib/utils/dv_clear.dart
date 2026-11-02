// SPDX-License-Identifier: AGPL-3.0-or-later

// DVChat: очистка переписки. Сервер стирает историю молча, поэтому ставит в комнате метку
// (состояние online.dvbstudio.dvchat.cleared со временем очистки). Приложение видит метку и стирает
// свою копию сообщений, которые старше метки. Просьба об очистке личного чата хранится в состоянии
// online.dvbstudio.dvchat.clear_request: pending (ждёт ответа), declined (отказ), none.

import 'dart:async';

import 'package:dvchat/config/setting_keys.dart';
import 'package:dvchat/utils/dv_api.dart';
import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart';

/// Просьба об очистке, как её видит этот человек
enum DvClearState {
  /// Просьбы нет
  none,

  /// Я попросил, жду ответа друга
  waiting,

  /// Друг просит, нужен мой ответ
  incoming,

  /// Друг отказался (показывается тому, кто просил)
  declined,
}

class DvClear {
  DvClear._();

  static const clearedType = 'online.dvbstudio.dvchat.cleared';
  static const requestType = 'online.dvbstudio.dvchat.clear_request';

  /// «комната|время» последней стёртой у нас переписки: открытый чат по этому сигналу перечитывает ленту
  static final ValueNotifier<String> wiped = ValueNotifier('');

  static StreamSubscription<SyncUpdate>? _sub;
  static Client? _client;
  static bool _busy = false;
  static bool _again = false;

  /// Запускает слежение за метками очистки (повторный вызов с тем же клиентом ничего не делает)
  static void attach(Client client) {
    if (identical(_client, client) && _sub != null) return;
    _sub?.cancel();
    _client = client;
    _sub = client.onSync.stream.listen((_) => unawaited(_scan()));
    unawaited(_scan());
  }

  static String _key(String roomId) => 'dv_cleared_ts_$roomId';

  /// Проходит по комнатам: где метка новее той, что уже применена, стирает старые сообщения
  static Future<void> _scan() async {
    final client = _client;
    if (client == null) return;
    if (_busy) {
      _again = true;
      return;
    }
    _busy = true;
    try {
      do {
        _again = false;
        for (final room in client.rooms) {
          final marker = room.getState(clearedType);
          final ts = marker?.content['ts'];
          if (ts is! int) continue;
          final done = AppSettings.store.getInt(_key(room.id)) ?? 0;
          if (ts <= done) continue;
          try {
            await _wipe(room, ts, marker is Event ? marker.eventId : null);
            await AppSettings.store.setInt(_key(room.id), ts);
            wiped.value = '${room.id}|$ts';
          } catch (e, s) {
            Logs().w('DVChat: не удалось стереть копию очищенной переписки', e, s);
          }
        }
      } while (_again);
    } finally {
      _busy = false;
    }
  }

  /// Стирает из локальной базы сообщения не новее времени очистки (новые, пришедшие после очистки, остаются)
  static Future<void> _wipe(Room room, int ts, String? markerEventId) async {
    final db = room.client.database;
    final ids = <String>[];
    for (var start = 0; start < 5000; start += 200) {
      final page = await db.getEventList(room, start: start, limit: 200);
      for (final e in page) {
        if (e.stateKey == null &&
            e.status.isSynced &&
            e.originServerTs.millisecondsSinceEpoch <= ts) {
          ids.add(e.eventId);
        }
      }
      if (page.length < 200) break;
    }
    for (final id in ids) {
      await db.removeEvent(id, room.id);
    }
    final last = room.lastEvent;
    if (last != null && last.originServerTs.millisecondsSinceEpoch <= ts) {
      room.lastEvent = null;
    }
    // Счётчик непрочитанных относился к стёртым сообщениям
    if (room.notificationCount > 0 && markerEventId != null) {
      try {
        await room.setReadMarker(markerEventId, mRead: markerEventId);
      } catch (_) {}
    }
  }

  /// Состояние просьбы об очистке для личного чата
  static DvClearState stateOf(Room room) {
    final content = room.getState(requestType)?.content;
    if (content == null) return DvClearState.none;
    final me = room.client.userID;
    final by = content['by'];
    switch (content['status']) {
      case 'pending':
        return by == me ? DvClearState.waiting : DvClearState.incoming;
      case 'declined':
        // «by» здесь тот, кто отказал; показываем отказ только тому, кто просил
        return by != me && !_declineSeen(room, content)
            ? DvClearState.declined
            : DvClearState.none;
    }
    return DvClearState.none;
  }

  static String _seenKey(String roomId) => 'dv_clear_declined_seen_$roomId';

  static bool _declineSeen(Room room, Map<String, Object?> content) {
    final ts = content['ts'];
    return ts is int && (AppSettings.store.getInt(_seenKey(room.id)) ?? 0) >= ts;
  }

  /// «Понятно» на отказе: больше не показывать эту плашку
  static Future<void> dismissDeclined(Room room) async {
    final ts = room.getState(requestType)?.content['ts'];
    if (ts is int) await AppSettings.store.setInt(_seenKey(room.id), ts);
  }

  /// Имя друга для текстов плашки
  static String peerName(Room room) =>
      room.getLocalizedDisplayname().trim().isEmpty
      ? 'Собеседник'
      : room.getLocalizedDisplayname();

  /// Попросить очистить личный чат
  static Future<void> request(Room room) async {
    await DvApi(room.client).post('chat/clear/request', {'room_id': room.id});
  }

  /// Ответить на просьбу: согласиться (чат сразу стирается у обоих) или отказать
  static Future<void> answer(Room room, {required bool accept}) async {
    await DvApi(room.client).post('chat/clear/answer', {
      'room_id': room.id,
      'accept': accept,
    });
  }

  /// Забрать свою просьбу обратно
  static Future<void> cancel(Room room) async {
    await DvApi(room.client).post('chat/clear/cancel', {'room_id': room.id});
  }
}
