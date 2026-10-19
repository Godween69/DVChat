// SPDX-License-Identifier: AGPL-3.0-or-later

// DVChat: каркас сетевых игр. Игра идёт в личном чате с другом: приглашение, ходы и итог
// это служебные события типа dv.game (в зашифрованной комнате они шифруются как обычные
// сообщения и в ленте чата не показываются). Вместе с приглашением уходит обычное
// сообщение, чтобы другу пришло уведомление. История партий хранится в самом чате
// и очистке не подлежит.

import 'package:dvchat/config/setting_keys.dart';
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

/// Итоги всех партий в одну игру с одним другом
class DvGameStats {
  int played = 0;
  int wins = 0;
  int losses = 0;
  int draws = 0;
  int quitByMe = 0;
  int quitByOpp = 0;
}

class DvGameNet {
  static const String eventType = 'dv.game';

  /// Приглашение живёт сутки, потом считается забытым
  static const Duration inviteLifetime = Duration(hours: 24);

  /// Партия, открытая на экране сейчас (для неё уведомления не показываются)
  static String? activeGameId;

  static String gameTitle(String game) => switch (game) {
    'bs' => 'Морской бой',
    'ckr' => 'Шашки',
    'c4' => 'Четыре в ряд',
    'chess' => 'Шахматы',
    'durak' => 'Дурак',
    'nardy' => 'Нарды',
    _ => 'Крестики-нолики',
  };

  /// Личные чаты, в которых можно играть
  static List<Room> directRooms(Client client) => client.rooms
      .where(
        (r) =>
            r.membership == Membership.join &&
            r.isDirectChat &&
            r.isAbandonedDMRoom != true,
      )
      .toList();

  // ---------- уведомления по отдельной партии ----------

  static bool isMuted(String gameId) =>
      AppSettings.mutedGames.value.contains(gameId);

  static Future<void> setMuted(String gameId, bool muted) async {
    final list = List<String>.of(AppSettings.mutedGames.value)..remove(gameId);
    if (muted) list.add(gameId);
    // Список не растёт бесконечно
    final trimmed = list.length > 200 ? list.sublist(list.length - 200) : list;
    await AppSettings.mutedGames.setItem(trimmed);
  }

  /// Текст уведомления о событии игры или null, если уведомлять не нужно
  static String? notificationText(Event e) {
    final c = e.content;
    final title = gameTitle('${c['game']}');
    switch (c['kind']) {
      case 'invite':
        // Обычное приглашение уже сопровождается сообщением в чате; уведомляем о реванше
        return c['silent'] == true
            ? '🎮 $title: предлагает сыграть ещё раз'
            : null;
      case 'move':
        return c['fin'] == true
            ? '🎮 $title: партия окончена'
            : '🎮 $title: ваш ход';
      case 'shot':
        return '🎮 $title: ваш ход';
      case 'ready':
        return '🎮 $title: соперник расставил корабли';
      case 'end':
        return c['reason'] == 'surrender'
            ? '🎮 $title: соперник сдался, вы победили'
            : null;
    }
    return null;
  }

  // ---------- отправка ----------

  /// Отправляет приглашение, возвращает идентификатор партии
  static Future<String> sendInvite(
    Room room, {
    required String game,
    required String gameTitle,
    bool announce = true,
    Map<String, Object?>? extra,
  }) async {
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    await room.sendEvent({
      'game': game,
      'id': id,
      'kind': 'invite',
      if (!announce) 'silent': true,
      ...?extra,
    }, type: eventType);
    // Видимое сообщение в чат только при первом приглашении, не при реванше
    if (announce) {
      await room.sendTextEvent(
        '🎮 Приглашение сыграть: $gameTitle. Откройте вкладку «Игры».',
      );
    }
    return id;
  }

  static Future<void> sendMove(
    Room room, {
    required String game,
    required String id,
    required int n,
    required int cell,
    bool fin = false,
  }) async {
    await room.sendEvent({
      'game': game,
      'id': id,
      'kind': 'move',
      'n': n,
      'cell': cell,
      if (fin) 'fin': true,
    }, type: eventType);
  }

  /// Конец партии. winner: идентификатор победителя, пустая строка при ничьей.
  static Future<void> sendEnd(
    Room room, {
    required String game,
    required String id,
    String? winner,
    String? reason,
    String? by,
  }) async {
    await room.sendEvent({
      'game': game,
      'id': id,
      'kind': 'end',
      'winner': ?winner,
      'reason': ?reason,
      'by': ?by,
    }, type: eventType);
  }

  /// Выйти из партии: засчитывается как сдача, победа достаётся сопернику
  static Future<void> surrender(
    Room room, {
    required String game,
    required String id,
  }) => sendEnd(
    room,
    game: game,
    id: id,
    winner: room.directChatMatrixID,
    reason: 'surrender',
    by: room.client.userID,
  );

  // ---------- чтение ----------

  /// Незавершённые партии во всех личных чатах
  static Future<List<DvGameInvite>> scan(Client client) async {
    final result = <DvGameInvite>[];
    final now = DateTime.now();
    for (final room in directRooms(client)) {
      try {
        final tl = await room.getTimeline(limit: 300);
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

  /// Итоги всех завершённых партий в эту игру с этим другом
  static Future<DvGameStats> stats(Room room, String game) async {
    final s = DvGameStats();
    final me = room.client.userID;
    try {
      final tl = await room.getTimeline(limit: 1000);
      final ends = tl.events
          .where(
            (e) =>
                e.type == eventType &&
                e.content['game'] == game &&
                e.content['kind'] == 'end',
          )
          .toList();
      tl.cancelSubscriptions();
      // Одна партия считается один раз; предпочитаем запись с известным итогом
      final byId = <String, Map<String, Object?>>{};
      for (final e in ends) {
        final id = '${e.content['id']}';
        final old = byId[id];
        if (old == null ||
            (!old.containsKey('winner') && e.content.containsKey('winner'))) {
          byId[id] = e.content;
        }
      }
      for (final c in byId.values) {
        s.played++;
        if (c['reason'] == 'surrender') {
          if (c['by'] == me) {
            s.quitByMe++;
          } else {
            s.quitByOpp++;
          }
        }
        final w = c['winner'];
        if (w is String) {
          if (w.isEmpty) {
            s.draws++;
          } else if (w == me) {
            s.wins++;
          } else {
            s.losses++;
          }
        }
      }
    } catch (_) {
      // Итоги необязательны
    }
    return s;
  }
}
