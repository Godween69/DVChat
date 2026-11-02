// SPDX-License-Identifier: AGPL-3.0-or-later

// DVChat: красные точки на нижних вкладках. «Друзья»: есть заявки, которые вы ещё не
// приняли и не отклонили. «Игры»: в какой-то партии сейчас ваш ход (или вас пригласили).

import 'dart:async';

import 'package:dvchat/pages/games/dv_game_net.dart';
import 'package:dvchat/utils/dv_api.dart';
import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart';

class DvBadges {
  DvBadges._();

  /// Сколько входящих заявок в друзья ждёт ответа
  static final ValueNotifier<int> friendRequests = ValueNotifier(0);

  /// В скольких партиях ход за вами
  static final ValueNotifier<int> gameTurns = ValueNotifier(0);

  static StreamSubscription<Event>? _sub;
  static Timer? _debounce;
  static Client? _client;

  /// Запускает слежение (повторный вызов с тем же клиентом ничего не делает)
  static void attach(Client client) {
    if (identical(_client, client) && _sub != null) return;
    _sub?.cancel();
    _client = client;
    _sub = client.onTimelineEvent.stream
        .where(
          (e) =>
              e.senderId != client.userID &&
              (e.type == DvGameNet.eventType ||
                  e.senderId.startsWith('@dvnotice:')),
        )
        .listen((e) {
          _debounce?.cancel();
          _debounce = Timer(const Duration(milliseconds: 1500), refresh);
        });
    // Первое чтение после того, как клиент готов
    unawaited(client.onSync.stream.first.then((_) => refresh()));
    if (client.rooms.isNotEmpty) unawaited(refresh());
  }

  /// Перечитывает оба счётчика
  static Future<void> refresh() async {
    final client = _client;
    if (client == null || client.userID == null) return;
    try {
      final answer = await DvApi(client).get('requests');
      final list = answer['requests'];
      friendRequests.value = list is List ? list.length : 0;
    } catch (_) {}
    try {
      await DvGameNet.scan(client);
    } catch (_) {}
  }
}
