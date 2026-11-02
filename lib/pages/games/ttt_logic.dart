// SPDX-License-Identifier: AGPL-3.0-or-later

// DVChat: крестики-нолики на большом поле, побеждает тот, кто выстроил 5 в ряд.
// Поле: 15x15 = 225 клеток, значения '' (пусто), 'X', 'O'. Первым всегда ходит X.
// Компьютер оценивает каждую клетку по «окнам» из пяти клеток (как в гомоку).

import 'dart:math';

class TttLogic {
  // Режимы: classic — обычное 3x3, big — расширенный лист 12x12 (5 в ряд),
  // иное (старые партии без режима) — прежнее поле 15x15
  static int n = 15;
  static int need = 5;
  static int get cells => n * n;

  static void configure(String? mode) {
    if (mode == 'classic') {
      n = 3;
      need = 3;
    } else if (mode == 'big') {
      n = 12;
      need = 5;
    } else {
      n = 15;
      need = 5;
    }
  }

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
  static int _price(int mine) {
    if (mine >= need) return 1000000;
    final left = need - mine; // сколько ещё не хватает до победы
    return switch (left) {
      1 => 6000,
      2 => 400,
      3 => 40,
      _ => 4,
    };
  }

  // Полный перебор для поля 3x3: не проигрывает, но и не мухлюет
  static int _minimax(List<String> b, String turn, String ai, int depth) {
    final w = winner(b);
    if (w != null) return w == ai ? 10 - depth : depth - 10;
    if (isFull(b)) return 0;
    final other = turn == 'X' ? 'O' : 'X';
    var best = turn == ai ? -100 : 100;
    for (var i = 0; i < 9; i++) {
      if (b[i] != '') continue;
      b[i] = turn;
      final v = _minimax(b, other, ai, depth + 1);
      b[i] = '';
      best = turn == ai ? max(best, v) : min(best, v);
    }
    return best;
  }

  static int _classicMove(List<String> board, String ai) {
    final b = List<String>.of(board);
    final other = ai == 'X' ? 'O' : 'X';
    var best = -100;
    final opts = <int>[];
    for (var i = 0; i < 9; i++) {
      if (b[i] != '') continue;
      b[i] = ai;
      final v = _minimax(b, other, ai, 1);
      b[i] = '';
      if (v > best) {
        best = v;
        opts
          ..clear()
          ..add(i);
      } else if (v == best) {
        opts.add(i);
      }
    }
    return opts[_rnd.nextInt(opts.length)];
  }

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
        if (ok) total += _price(mine);
      }
    }
    return total;
  }

  /// Ход компьютера: сначала свой выигрыш, потом защита, иначе лучшая по оценке клетка
  static int aiMove(List<String> board, String ai) {
    final hu = ai == 'X' ? 'O' : 'X';
    if (n == 3) return _classicMove(board, ai);
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
      if (need > 3) {
        if (a >= 6000 + 400) s += 3000;
        if (d >= 6000 + 400) s += 2000;
      }
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
