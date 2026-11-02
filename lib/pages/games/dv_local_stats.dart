// SPDX-License-Identifier: AGPL-3.0-or-later

// DVChat: статистика игр против компьютера. Игра, открытая на экране, сообщает сюда свой номер;
// конец партии ловится по звуку победы или поражения (его играют все игры). Только офлайн-партии.

import 'dart:async';
import 'dart:convert';

import 'package:dvchat/pages/games/dv_game_sound.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DvLocalStats {
  static const String _key = 'dv_local_stats';
  static const String _extKey = 'dv_local_stats_ext';
  static String? _game;
  static bool _offline = false;
  static DateTime? _last;

  /// Вызывается после записи партии: отправка итогов в аккаунт (подключает DvStatsSync)
  static void Function()? onChanged;

  /// Вызывается при открытии страницы игры
  static void open(String game, {required bool offline}) {
    _game = game;
    _offline = offline;
    _last = null;
  }

  /// Вызывается при закрытии страницы игры
  static void close(String game) {
    if (_game == game) {
      _game = null;
      _offline = false;
    }
  }

  /// Вызывается из DvGameSound.play: победа или поражение в партии с компьютером
  static void noteSound(DvSound s) {
    final game = _game;
    if (game == null || !_offline) return;
    if (s != DvSound.win && s != DvSound.lose) return;
    final now = DateTime.now();
    final last = _last;
    // один и тот же финал не должен считаться дважды
    if (last != null && now.difference(last) < const Duration(seconds: 4)) {
      return;
    }
    _last = now;
    unawaited(_add(game, s == DvSound.win));
  }

  static Map<String, List<int>> _decode(String? raw) {
    final out = <String, List<int>>{};
    if (raw == null) return out;
    try {
      final m = jsonDecode(raw);
      if (m is Map) {
        m.forEach((k, v) {
          if (v is List && v.length >= 2) {
            out['$k'] = [(v[0] as num).toInt(), (v[1] as num).toInt()];
          }
        });
      }
    } catch (_) {
      // повреждённые данные просто игнорируем
    }
    return out;
  }

  static Future<void> _add(String game, bool win) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final all = _decode(prefs.getString(_key));
      final cur = all[game] ?? [0, 0];
      if (win) {
        cur[0]++;
      } else {
        cur[1]++;
      }
      all[game] = cur;
      await prefs.setString(_key, jsonEncode(all));
      // дата и число партий по дням (нужны для статистики в аккаунте)
      final ext = _decodeExt(prefs.getString(_extKey));
      final g = ext[game] ?? DvLocalExt();
      final now = DateTime.now();
      final day =
          '${now.year.toString().padLeft(4, '0')}-'
          '${now.month.toString().padLeft(2, '0')}-'
          '${now.day.toString().padLeft(2, '0')}';
      g.days[day] = (g.days[day] ?? 0) + 1;
      g.last = now.millisecondsSinceEpoch;
      ext[game] = g;
      await prefs.setString(
        _extKey,
        jsonEncode({
          for (final e in ext.entries) e.key: {'last': e.value.last, 'days': e.value.days},
        }),
      );
      onChanged?.call();
    } catch (_) {
      // статистика необязательна
    }
  }

  static Map<String, DvLocalExt> _decodeExt(String? raw) {
    final out = <String, DvLocalExt>{};
    if (raw == null) return out;
    try {
      final m = jsonDecode(raw);
      if (m is Map) {
        m.forEach((k, v) {
          if (v is Map) {
            final g = DvLocalExt();
            final last = v['last'];
            if (last is num) g.last = last.toInt();
            final days = v['days'];
            if (days is Map) {
              days.forEach((d, n) {
                if (n is num) g.days['$d'] = n.toInt();
              });
            }
            out['$k'] = g;
          }
        });
      }
    } catch (_) {
      // повреждённые данные игнорируем
    }
    return out;
  }

  /// Игра -> дата последней партии и число партий по дням
  static Future<Map<String, DvLocalExt>> loadExt() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return _decodeExt(prefs.getString(_extKey));
    } catch (_) {
      return {};
    }
  }

  /// Возвращает счётчики из аккаунта на чистом устройстве (после нового входа)
  static Future<void> restore(String game, int wins, int losses) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final all = _decode(prefs.getString(_key));
      all[game] = [wins, losses];
      await prefs.setString(_key, jsonEncode(all));
    } catch (_) {
      // статистика необязательна
    }
  }

  /// Игра -> [победы, поражения]
  static Future<Map<String, List<int>>> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return _decode(prefs.getString(_key));
    } catch (_) {
      return {};
    }
  }
}

/// Дата последней партии с компьютером и число партий по дням
class DvLocalExt {
  int last = 0;
  final Map<String, int> days = {};
}
