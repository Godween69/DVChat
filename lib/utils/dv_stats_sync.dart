// SPDX-License-Identifier: AGPL-3.0-or-later

// DVChat: итоги игр человека кладутся в данные его аккаунта (dv.game_stats, формат v1), чтобы
// статистика переживала выход и новый вход, а панель администратора считала «Партий сыграно».
// Формат: {v:1, games:{<игра>:{played,won,lost,drawn,last(мс),days:{"ГГГГ-ММ-ДД":число}}}}.
// Сюда попадают партии с компьютером (локальные счётчики) и с друзьями (итоги из личных чатов).
// Без чужих данных: только числа и даты, имён и содержимого партий нет.

import 'dart:async';
import 'dart:convert';

import 'package:dvchat/pages/games/dv_game_net.dart';
import 'package:dvchat/pages/games/dv_local_stats.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

int _i(Object? v) => v is num ? v.toInt() : 0;

class _G {
  int w = 0, l = 0, d = 0, last = 0;
  final Map<String, int> days = {};

  Map<String, Object?> toJson() => {
    'w': w,
    'l': l,
    'd': d,
    'last': last,
    'days': days,
  };

  static _G fromJson(Object? j) {
    final g = _G();
    if (j is Map) {
      g.w = _i(j['w']);
      g.l = _i(j['l']);
      g.d = _i(j['d']);
      g.last = _i(j['last']);
      final dd = j['days'];
      if (dd is Map) dd.forEach((k, v) => g.days['$k'] = _i(v));
    }
    return g;
  }

  /// Запись в формате аккаунта (так её пишет и читает панель)
  static _G fromServer(Object? j) {
    final g = _G();
    if (j is Map) {
      g.w = _i(j['won']);
      g.l = _i(j['lost']);
      g.d = _i(j['drawn']);
      g.last = _i(j['last']);
      final dd = j['days'];
      if (dd is Map) dd.forEach((k, v) => g.days['$k'] = _i(v));
    }
    return g;
  }
}

class DvStatsSync {
  static const String accountType = 'dv.game_stats';
  static const List<String> games = [
    'ttt',
    'bs',
    'ckr',
    'c4',
    'chess',
    'durak',
    'nardy',
    'domino',
  ];
  static const String _scanKey = 'dv_stats_last_scan';
  static const String _sentKey = 'dv_stats_last_sent';
  static const String _cacheKey = 'dv_stats_friend_cache';
  static bool _busy = false;

  /// Подключает синхронизацию к клиенту: первая проверка через полминуты после старта
  /// (не чаще раза в 12 часов), затем после каждой партии с компьютером
  static void watch(Client client) {
    DvLocalStats.onChanged = () => unawaited(publishNow(client));
    var started = false;
    client.onSync.stream.listen((_) {
      if (started) return;
      started = true;
      unawaited(
        Future<void>.delayed(
          const Duration(seconds: 30),
          () => maybeScan(client),
        ),
      );
    });
  }

  static String _day(DateTime t) =>
      '${t.year.toString().padLeft(4, '0')}-'
      '${t.month.toString().padLeft(2, '0')}-'
      '${t.day.toString().padLeft(2, '0')}';

  /// Читает итоги партий с друзьями из личных чатов (каждая партия один раз)
  static Future<Map<String, _G>> _scanFriends(Client client) async {
    final out = <String, _G>{};
    final me = client.userID;
    for (final room in DvGameNet.directRooms(client)) {
      try {
        final tl = await room.getTimeline(limit: 1000);
        final byId = <String, Event>{};
        for (final e in tl.events) {
          if (e.type != DvGameNet.eventType || e.content['kind'] != 'end') {
            continue;
          }
          final id = '${e.content['game']}:${e.content['id']}';
          final old = byId[id];
          if (old == null ||
              (!old.content.containsKey('winner') &&
                  e.content.containsKey('winner'))) {
            byId[id] = e;
          }
        }
        tl.cancelSubscriptions();
        for (final e in byId.values) {
          final game = '${e.content['game']}';
          final w = e.content['winner'];
          if (!games.contains(game) || w is! String) continue;
          final g = out[game] ??= _G();
          if (w.isEmpty) {
            g.d++;
          } else if (w == me) {
            g.w++;
          } else {
            g.l++;
          }
          final ts = e.originServerTs;
          final day = _day(ts.toLocal());
          g.days[day] = (g.days[day] ?? 0) + 1;
          if (ts.millisecondsSinceEpoch > g.last) {
            g.last = ts.millisecondsSinceEpoch;
          }
        }
      } catch (_) {
        // чат без доступной истории пропускаем
      }
    }
    return out;
  }

  /// Полная проверка: не чаще раза в 12 часов, либо сразу при force
  static Future<void> maybeScan(Client client, {bool force = false}) async {
    if (_busy || client.userID == null) return;
    _busy = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.now().millisecondsSinceEpoch;
      final last = prefs.getInt(_scanKey) ?? 0;
      if (!force && now - last < const Duration(hours: 12).inMilliseconds) {
        return;
      }
      final friends = await _scanFriends(client);
      await prefs.setString(
        _cacheKey,
        jsonEncode({for (final e in friends.entries) e.key: e.value.toJson()}),
      );
      await prefs.setInt(_scanKey, now);
      await _publish(client, friends, restoreLocal: true);
    } catch (e) {
      Logs().w('DVChat: статистика игр не отправилась', e);
    } finally {
      _busy = false;
    }
  }

  /// После партии с компьютером: итоги с друзьями берутся из сохранённых при последней проверке
  static Future<void> publishNow(Client client) async {
    if (client.userID == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final friends = <String, _G>{};
      final raw = prefs.getString(_cacheKey);
      if (raw != null) {
        final m = jsonDecode(raw);
        if (m is Map) m.forEach((k, v) => friends['$k'] = _G.fromJson(v));
      }
      await _publish(client, friends);
    } catch (e) {
      Logs().w('DVChat: статистика игр не отправилась', e);
    }
  }

  static Map<String, _G> _serverStats(Client client) {
    final out = <String, _G>{};
    final content = client.accountData[accountType]?.content;
    final g = content?['games'];
    if (g is Map) g.forEach((k, v) => out['$k'] = _G.fromServer(v));
    return out;
  }

  static Future<void> _publish(
    Client client,
    Map<String, _G> friends, {
    bool restoreLocal = false,
  }) async {
    final uid = client.userID;
    if (uid == null) return;
    final server = _serverStats(client);
    var local = await DvLocalStats.load();
    // Новый вход на чистом устройстве: партии с компьютером возвращаются из аккаунта
    var restored = false;
    // (только после свежей проверки друзей, иначе чужие партии засчитались бы как свои)
    for (final game in restoreLocal ? games : const <String>[]) {
      final cur = local[game];
      final s = server[game];
      if ((cur == null || cur[0] + cur[1] == 0) && s != null) {
        final f = friends[game] ?? _G();
        final ow = _max(0, s.w - f.w);
        final ol = _max(0, s.l - f.l);
        if (ow + ol > 0) {
          await DvLocalStats.restore(game, ow, ol);
          restored = true;
        }
      }
    }
    if (restored) local = await DvLocalStats.load();
    final ext = await DvLocalStats.loadExt();
    final out = <String, Object?>{};
    for (final game in games) {
      final f = friends[game] ?? _G();
      final s = server[game] ?? _G();
      final lw = local[game]?[0] ?? 0;
      final ll = local[game]?[1] ?? 0;
      final won = _max(f.w + lw, s.w);
      final lost = _max(f.l + ll, s.l);
      final drawn = _max(f.d, s.d);
      final played = won + lost + drawn;
      if (played == 0) continue;
      final days = <String, int>{};
      for (final e in f.days.entries) {
        days[e.key] = e.value;
      }
      final x = ext[game];
      if (x != null) {
        x.days.forEach((k, v) => days[k] = (days[k] ?? 0) + v);
      }
      s.days.forEach((k, v) => days[k] = _max(days[k] ?? 0, v));
      out[game] = {
        'played': played,
        'won': won,
        'lost': lost,
        'drawn': drawn,
        'last': _max(_max(f.last, x?.last ?? 0), s.last),
        'days': days,
      };
    }
    final content = <String, Object?>{'v': 1, 'games': out};
    final encoded = jsonEncode(content);
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString(_sentKey) == encoded &&
        client.accountData[accountType] != null) {
      return;
    }
    await client.setAccountData(uid, accountType, content);
    await prefs.setString(_sentKey, encoded);
  }

  static int _max(int a, int b) => a > b ? a : b;
}
