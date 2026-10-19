// SPDX-License-Identifier: AGPL-3.0-or-later

// DVChat: правила и компьютерный соперник для «Четыре в ряд».
// Поле 7 столбцов на 6 рядов, клетка (ряд r сверху, столбец c) лежит в списке под номером r * 7 + c.
// Значения клеток: 0 пусто, 1 первый игрок (красные), 2 второй (жёлтые).
// Уровней сложности нет: компьютер всегда ищет ход перебором с отсечениями.

import 'dart:math';

class C4Logic {
  static const int cols = 7;
  static const int rows = 6;

  /// Порядок перебора столбцов: от центра к краям (так отсечений больше)
  static const List<int> _order = [3, 2, 4, 1, 5, 0, 6];

  /// Все линии по четыре клетки
  static final List<List<int>> _windows = _buildWindows();

  static List<List<int>> _buildWindows() {
    final out = <List<int>>[];
    const dirs = [
      [0, 1],
      [1, 0],
      [1, 1],
      [1, -1],
    ];
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        for (final d in dirs) {
          final er = r + 3 * d[0];
          final ec = c + 3 * d[1];
          if (er < 0 || er >= rows || ec < 0 || ec >= cols) continue;
          out.add([
            for (var k = 0; k < 4; k++) (r + k * d[0]) * cols + (c + k * d[1]),
          ]);
        }
      }
    }
    return out;
  }

  static int count(List<int> b) => b.where((v) => v != 0).length;

  /// Чей ход: первый ходит при чётном числе фишек
  static int turnOf(List<int> b) => count(b).isEven ? 1 : 2;

  static bool isFull(List<int> b) => !b.contains(0);

  /// Ряд, куда ляжет фишка в этом столбце, или -1, если столбец полон
  static int dropRow(List<int> b, int c) {
    if (c < 0 || c >= cols) return -1;
    for (var r = rows - 1; r >= 0; r--) {
      if (b[r * cols + c] == 0) return r;
    }
    return -1;
  }

  /// Выигрышная линия из четырёх клеток или null
  static List<int>? winLine(List<int> b) {
    for (final w in _windows) {
      final v = b[w[0]];
      if (v != 0 && b[w[1]] == v && b[w[2]] == v && b[w[3]] == v) return w;
    }
    return null;
  }

  static int? winner(List<int> b) {
    final l = winLine(b);
    return l == null ? null : b[l.first];
  }

  /// Выиграла ли только что положенная в (r, c) фишка игрока p
  static bool _wins(List<int> b, int r, int c, int p) {
    const dirs = [
      [0, 1],
      [1, 0],
      [1, 1],
      [1, -1],
    ];
    for (final d in dirs) {
      var n = 1;
      for (final s in const [1, -1]) {
        var rr = r + s * d[0];
        var cc = c + s * d[1];
        while (rr >= 0 &&
            rr < rows &&
            cc >= 0 &&
            cc < cols &&
            b[rr * cols + cc] == p) {
          n++;
          rr += s * d[0];
          cc += s * d[1];
        }
      }
      if (n >= 4) return true;
    }
    return false;
  }

  /// Оценка позиции для игрока p: сколько у него «почти линий» против соперника
  static int _eval(List<int> b, int p) {
    final q = 3 - p;
    var score = 0;
    for (final w in _windows) {
      var mine = 0;
      var theirs = 0;
      for (final i in w) {
        final v = b[i];
        if (v == p) {
          mine++;
        } else if (v == q) {
          theirs++;
        }
      }
      if (mine > 0 && theirs > 0) continue;
      if (mine == 3) {
        score += 50;
      } else if (mine == 2) {
        score += 10;
      } else if (theirs == 3) {
        score -= 60;
      } else if (theirs == 2) {
        score -= 10;
      }
    }
    // Центральный столбец ценнее
    for (var r = 0; r < rows; r++) {
      final v = b[r * cols + 3];
      if (v == p) score += 6;
      if (v == q) score -= 6;
    }
    return score;
  }

  /// Негамакс с альфа-бета отсечением; результат с точки зрения ходящего p
  static int _neg(List<int> b, int p, int depth, int alpha, int beta) {
    if (depth == 0) return _eval(b, p);
    var best = -1000000;
    var any = false;
    for (final c in _order) {
      final r = dropRow(b, c);
      if (r < 0) continue;
      any = true;
      b[r * cols + c] = p;
      final int score;
      if (_wins(b, r, c, p)) {
        score = 100000 + depth;
      } else {
        score = -_neg(b, 3 - p, depth - 1, -beta, -alpha);
      }
      b[r * cols + c] = 0;
      if (score > best) best = score;
      if (best > alpha) alpha = best;
      if (alpha >= beta) break;
    }
    return any ? best : 0;
  }

  /// Лучший ход компьютера (номер столбца) за игрока me
  static int aiMove(List<int> board, int me, Random rnd) {
    final b = List<int>.of(board);
    final filled = count(b);
    final depth = filled < 12 ? 7 : (filled < 24 ? 8 : 10);
    final moves = [
      for (final c in _order)
        if (dropRow(b, c) >= 0) c,
    ];
    var bestScore = -2000000;
    var bestMoves = <int>[];
    for (final c in moves) {
      final r = dropRow(b, c);
      b[r * cols + c] = me;
      final int score;
      if (_wins(b, r, c, me)) {
        score = 1000000;
      } else {
        score = -_neg(b, 3 - me, depth - 1, -1000000, 1000000);
      }
      b[r * cols + c] = 0;
      if (score > bestScore) {
        bestScore = score;
        bestMoves = [c];
      } else if (score == bestScore) {
        bestMoves.add(c);
      }
    }
    if (bestMoves.isEmpty) return moves.first;
    return bestMoves[rnd.nextInt(bestMoves.length)];
  }
}
