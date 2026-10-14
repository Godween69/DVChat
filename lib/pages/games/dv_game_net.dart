// SPDX-License-Identifier: AGPL-3.0-or-later

// DVChat: каркас сетевых игр. Игра идёт в личном чате с другом: приглашение и ходы
// это служебные события типа dv.game (в зашифрованной комнате они шифруются как
// обычные сообщения и в ленте чата не показываются). Вместе с приглашением уходит
// обычное сообщение, чтобы другу пришло уведомление.

import 'package:matrix/matrix.dart';

class DvGameInvite {
  const DvGameInvite({
    required this.room,
    required this.gameId,
    required this.game,
    required this.hostId,
    required this.time,
  });

  final Room room;
  final String gameId;
  final String game;
  final String hostId;
  final DateTime time;
}

class DvGameNet {
  static const String eventType = 'dv.game';

  /// Приглашение живёт сутки, потом считается забытым
  static const Duration inviteLifetime = Duration(hours: 24);

  /// Личные чаты, в которых можно играть
  static List<Room> directRooms(Client client) => client.rooms
      .where(
        (r) =>
            r.membership == Membership.join &&
            r.isDirectChat &&
            r.isAbandonedDMRoom != true,
      )
      .toList();

  /// Отправляет приглашение, возвращает идентификатор партии
  static Future<String> sendInvite(
    Room room, {
    required String game,
    required String gameTitle,
  }) async {
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    await room.sendEvent({
      'game': game,
      'id': id,
      'kind': 'invite',
    }, type: eventType);
    await room.sendTextEvent(
      '🎮 Приглашение сыграть: $gameTitle. Откройте вкладку «Игры».',
    );
    return id;
  }

  static Future<void> sendMove(
    Room room, {
    required String game,
    required String id,
    required int n,
    required int cell,
  }) async {
    await room.sendEvent({
      'game': game,
      'id': id,
      'kind': 'move',
      'n': n,
      'cell': cell,
    }, type: eventType);
  }

  static Future<void> sendEnd(
    Room room, {
    required String game,
    required String id,
  }) async {
    await room.sendEvent({
      'game': game,
      'id': id,
      'kind': 'end',
    }, type: eventType);
  }

  /// Незавершённые партии во всех личных чатах
  static Future<List<DvGameInvite>> scan(Client client) async {
    final result = <DvGameInvite>[];
    final now = DateTime.now();
    for (final room in directRooms(client)) {
      try {
        final tl = await room.getTimeline();
        final events = tl.events.where((e) => e.type == eventType).toList();
        tl.cancelSubscriptions();
        final ended = <String>{};
        for (final e in events) {
          if (e.content['kind'] == 'end') {
            ended.add('${e.content['id']}');
          }
        }
        for (final e in events) {
          if (e.content['kind'] != 'invite') continue;
          final id = '${e.content['id']}';
          if (ended.contains(id)) continue;
          if (now.difference(e.originServerTs) > inviteLifetime) continue;
          result.add(
            DvGameInvite(
              room: room,
              gameId: id,
              game: '${e.content['game']}',
              hostId: e.senderId,
              time: e.originServerTs,
            ),
          );
        }
      } catch (_) {
        // Чат, который не удалось прочитать, пропускаем
      }
    }
    result.sort((a, b) => b.time.compareTo(a.time));
    return result;
  }
}
