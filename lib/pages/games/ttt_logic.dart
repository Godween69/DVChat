// SPDX-License-Identifier: AGPL-3.0-or-later

// DVChat: крестики-нолики на большом поле, побеждает тот, кто выстроил 5 в ряд.
// Поле: 15x15 = 225 клеток, значения '' (пусто), 'X', 'O'. Первым всегда ходит X.
// Компьютер оценивает каждую клетку по «окнам» из пяти клеток (как в гомоку).

import 'dart:math';

class TttLogic {
  static const int n = 15;
  static const int cells = n * n;
  static const int need = 5;

  static const List<List<int>> _dirs = [
    [1, 0],
    [0, 1],
    [1, 1],
    [1, -1],
  ];

  /// Выигравшая цепочка (клетки по порядку) или null
  static List<int>? winLine(List<String> b) {
    for (var y = 0; y < n; y++) {
      for (var x = 0; x < n; x++) {
        final v = b[y * n + x];
        if (v == '') continue;
        for (final d in _dirs) {
          // начинаем только с начала цепочки
          final px = x - d[0], py = y - d[1];
          if (px >= 0 && px < n && py >= 0 && py < n && b[py * n + px] == v) {
            continue;
          }
          final line = <int>[y * n + x];
          var cx = x + d[0], cy = y + d[1];
          while (cx >= 0 && cx < n && cy >= 0 && cy < n && b[cy * n + cx] == v) {
            line.add(cy * n + cx);
            cx += d[0];
            cy += d[1];
          }
          if (line.length >= need) return line;
        }
      }
    }
    return null;
  }

  static String? winner(List<String> b) {
    final l = winLine(b);
    return l == null ? null : b[l.first];
  }

  static bool isFull(List<String> b) => !b.contains('');

  static String turnOf(List<String> b) =>
      b.where((c) => c != '').length.isEven ? 'X' : 'O';

  static final Random _rnd = Random();

  // Цена окна из пяти клеток по числу своих камней (с учётом ставимого)
  static const List<int> _price = [0, 4, 40, 400, 6000, 1000000];

  /// Оценка клетки i для игрока who: сумма цен окон по четырём направлениям
  static int _score(List<String> b, int i, String who, String other) {
    final x = i % n, y = i ~/ n;
    var total = 0;
    for (final d in _dirs) {
      for (var off = -(need - 1); off <= 0; off++) {
        var mine = 1; // сама ставимая клетка
        var ok = true;
        for (var k = 0; k < need; k++) {
          final cx = x + d[0] * (off + k);
          final cy = y + d[1] * (off + k);
          if (cx < 0 || cx >= n || cy < 0 || cy >= n) {
            ok = false;
            break;
          }
          final v = b[cy * n + cx];
          if (cx == x && cy == y) continue;
          if (v == other) {
            ok = false;
            break;
          }
          if (v == who) mine++;
        }
        if (ok) total += _price[mine];
      }
    }
    return total;
  }

  /// Ход компьютера: сначала свой выигрыш, потом защита, иначе лучшая по оценке клетка
  static int aiMove(List<String> board, String ai) {
    final hu = ai == 'X' ? 'O' : 'X';
    final stones = [
      for (var i = 0; i < cells; i++)
        if (board[i] != '') i,
    ];
    if (stones.isEmpty) return (n ~/ 2) * n + n ~/ 2;

    // Кандидаты: пустые клетки не дальше двух от любого камня
    final cand = <int>{};
    for (final s in stones) {
      final sx = s % n, sy = s ~/ n;
      for (var dy = -2; dy <= 2; dy++) {
        for (var dx = -2; dx <= 2; dx++) {
          final cx = sx + dx, cy = sy + dy;
          if (cx < 0 || cx >= n || cy < 0 || cy >= n) continue;
          if (board[cy * n + cx] == '') cand.add(cy * n + cx);
        }
      }
    }
    if (cand.isEmpty) {
      final free = [
        for (var i = 0; i < cells; i++)
          if (board[i] == '') i,
      ];
      return free[_rnd.nextInt(free.length)];
    }

    var best = -1;
    final bestCells = <int>[];
    for (final i in cand) {
      final a = _score(board, i, ai, hu);
      final d = _score(board, i, hu, ai);
      // защита чуть слабее нападения, но блок явной угрозы перевешивает мелочи
      var s = a + (d * 0.95).round();
      if (a >= 1000000) {
        s = 1 << 40; // выигрываем сразу
      } else if (d >= 1000000) {
        s = 1 << 39; // иначе проигрываем
      }
      // двойная угроза (сразу две «тройки/четвёрки») — сильный ход
      if (a >= 6000 + 400) s += 3000;
      if (d >= 6000 + 400) s += 2000;
      // лёгкая тяга к центру
      final cx = (i % n - n ~/ 2).abs(), cy = (i ~/ n - n ~/ 2).abs();
      s += 7 - max(cx, cy).clamp(0, 7);
      if (s > best) {
        best = s;
        bestCells
          ..clear()
          ..add(i);
      } else if (s == best) {
        bestCells.add(i);
      }
    }
    return bestCells[_rnd.nextInt(bestCells.length)];
  }
}
