// SPDX-License-Identifier: AGPL-3.0-or-later

// DVChat: правила русских шашек. Поле 8x8 в виде списка из 64 клеток (строка * 8 + столбец).
// Значения клетки: 0 пусто, 1 белая шашка, 2 белая дамка, -1 чёрная шашка, -2 чёрная дамка.
// Белые стоят внизу (строки 5-7) и ходят первыми, чёрные вверху (строки 0-2).
// Правила: обычная шашка ходит вперёд на клетку, а бьёт и вперёд, и назад; дамка ходит
// и бьёт на любое расстояние; бить обязательно (любым способом на выбор, но серию
// надо довести до конца); шашка, дошедшая до последней линии в ходе боя, становится
// дамкой и продолжает бить как дамка; побитые шашки снимаются после хода и дважды не бьются.

import 'dart:math';

/// Один ход: клетки, по которым идёт фигура (начало, затем каждая остановка), и побитые клетки
class CkrMove {
  const CkrMove(this.path, this.captured);

  final List<int> path;
  final List<int> captured;

  int get from => path.first;
  int get to => path.last;
}

class CkrLogic {
  static const List<(int, int)> _dirs = [(-1, -1), (-1, 1), (1, -1), (1, 1)];

  static bool _in(int r, int c) => r >= 0 && r < 8 && c >= 0 && c < 8;

  static List<int> initial() {
    final b = List<int>.filled(64, 0);
    for (var r = 0; r < 8; r++) {
      for (var c = 0; c < 8; c++) {
        if ((r + c).isOdd) {
          if (r < 3) b[r * 8 + c] = -1;
          if (r > 4) b[r * 8 + c] = 1;
        }
      }
    }
    return b;
  }

  static int sideOf(int v) => v > 0 ? 1 : (v < 0 ? -1 : 0);

  static bool _enemy(int v, int side) => v != 0 && sideOf(v) != side;

  /// Последняя линия для стороны: белые идут к строке 0, чёрные к строке 7
  static int _lastRow(int side) => side > 0 ? 0 : 7;

  /// Есть ли у фигуры на pos хотя бы один бой (с учётом уже побитых captured)
  static bool _canCapture(
    List<int> b,
    int pos,
    int side,
    bool king,
    List<int> captured,
  ) {
    final r0 = pos ~/ 8;
    final c0 = pos % 8;
    for (final d in _dirs) {
      var r = r0 + d.$1;
      var c = c0 + d.$2;
      if (king) {
        while (_in(r, c) && b[r * 8 + c] == 0) {
          r += d.$1;
          c += d.$2;
        }
      }
      if (!_in(r, c)) continue;
      final mid = r * 8 + c;
      if (!_enemy(b[mid], side) || captured.contains(mid)) continue;
      final lr = r + d.$1;
      final lc = c + d.$2;
      if (_in(lr, lc) && b[lr * 8 + lc] == 0) return true;
    }
    return false;
  }

  /// Перебор серий боя от клетки pos (фигура с начальной клетки уже снята с доски)
  static void _dfs(
    List<int> b,
    int pos,
    int side,
    bool king,
    List<int> path,
    List<int> captured,
    List<CkrMove> out,
  ) {
    final r0 = pos ~/ 8;
    final c0 = pos % 8;
    for (final d in _dirs) {
      var r = r0 + d.$1;
      var c = c0 + d.$2;
      if (king) {
        while (_in(r, c) && b[r * 8 + c] == 0) {
          r += d.$1;
          c += d.$2;
        }
      }
      if (!_in(r, c)) continue;
      final mid = r * 8 + c;
      if (!_enemy(b[mid], side) || captured.contains(mid)) continue;
      final lands = <int>[];
      var lr = r + d.$1;
      var lc = c + d.$2;
      while (_in(lr, lc) && b[lr * 8 + lc] == 0) {
        lands.add(lr * 8 + lc);
        if (!king) break;
        lr += d.$1;
        lc += d.$2;
      }
      if (lands.isEmpty) continue;
      final nextCaptured = [...captured, mid];
      // Куда можно встать так, чтобы бой продолжался (если такие есть, обязаны выбрать их)
      final cont = <int>[];
      final becomesKing = <int, bool>{};
      for (final land in lands) {
        final k = king || (land ~/ 8 == _lastRow(side));
        becomesKing[land] = k;
        if (_canCapture(b, land, side, k, nextCaptured)) cont.add(land);
      }
      if (cont.isNotEmpty) {
        for (final land in cont) {
          _dfs(
            b,
            land,
            side,
            becomesKing[land]!,
            [...path, land],
            nextCaptured,
            out,
          );
        }
      } else {
        for (final land in lands) {
          out.add(CkrMove([...path, land], nextCaptured));
        }
      }
    }
  }

  /// Все допустимые ходы стороны side (1 белые, -1 чёрные); при возможности боя только бои
  static List<CkrMove> moves(List<int> board, int side) {
    final captures = <CkrMove>[];
    for (var i = 0; i < 64; i++) {
      final v = board[i];
      if (v == 0 || sideOf(v) != side) continue;
      final b = List<int>.of(board)..[i] = 0;
      _dfs(b, i, side, v.abs() == 2, [i], <int>[], captures);
    }
    if (captures.isNotEmpty) return captures;

    final simple = <CkrMove>[];
    for (var i = 0; i < 64; i++) {
      final v = board[i];
      if (v == 0 || sideOf(v) != side) continue;
      final king = v.abs() == 2;
      final r0 = i ~/ 8;
      final c0 = i % 8;
      for (final d in _dirs) {
        if (!king && d.$1 != -side) continue;
        var r = r0 + d.$1;
        var c = c0 + d.$2;
        while (_in(r, c) && board[r * 8 + c] == 0) {
          simple.add(CkrMove([i, r * 8 + c], const <int>[]));
          if (!king) break;
          r += d.$1;
          c += d.$2;
        }
      }
    }
    return simple;
  }

  /// Доска после хода (побитые снимаются, шашка у последней линии становится дамкой)
  static List<int> apply(List<int> board, CkrMove m) {
    final b = List<int>.of(board);
    final v = b[m.from];
    final side = sideOf(v);
    var king = v.abs() == 2;
    for (final p in m.path) {
      if (p ~/ 8 == _lastRow(side)) king = true;
    }
    b[m.from] = 0;
    for (final x in m.captured) {
      b[x] = 0;
    }
    b[m.to] = side * (king ? 2 : 1);
    return b;
  }

  /// Ход, который ничего не бил и не был ходом простой шашки (для правила ничьей)
  static bool isQuiet(List<int> before, CkrMove m) =>
      m.captured.isEmpty && before[m.from].abs() == 2;

  /// Находит допустимый ход по пути (для ходов, пришедших по сети)
  static CkrMove? find(List<int> board, int side, List<int> path) {
    for (final m in moves(board, side)) {
      if (m.path.length == path.length) {
        var same = true;
        for (var i = 0; i < path.length; i++) {
          if (m.path[i] != path[i]) {
            same = false;
            break;
          }
        }
        if (same) return m;
      }
    }
    return null;
  }

  // ---------------- компьютер ----------------

  static const int _man = 100;
  static const int _kingValue = 320;

  /// Оценка позиции с точки зрения стороны side
  static int evaluate(List<int> b, int side) {
    var score = 0;
    for (var i = 0; i < 64; i++) {
      final v = b[i];
      if (v == 0) continue;
      final s = sideOf(v);
      final r = i ~/ 8;
      var val = v.abs() == 2 ? _kingValue : _man + (s > 0 ? (7 - r) : r) * 4;
      // Шашки на краю и в тылу надёжнее
      final c = i % 8;
      if (v.abs() == 1 && (c == 0 || c == 7)) val += 3;
      if (v.abs() == 1 && (s > 0 ? r == 7 : r == 0)) val += 8;
      score += s == side ? val : -val;
    }
    return score;
  }

  static int _search(
    List<int> b,
    int toMove,
    int me,
    int depth,
    int alpha,
    int beta,
  ) {
    final list = moves(b, toMove);
    if (list.isEmpty) return toMove == me ? -100000 - depth : 100000 + depth;
    // На глубине предела досматриваем только бои, чтобы не оценивать позицию посреди размена
    if (depth <= 0 && list.first.captured.isEmpty) return evaluate(b, me);
    // Сначала бои: так отсечений больше
    list.sort((x, y) => y.captured.length.compareTo(x.captured.length));
    if (toMove == me) {
      var best = -1 << 30;
      for (final m in list) {
        final v = _search(apply(b, m), -toMove, me, depth - 1, alpha, beta);
        if (v > best) best = v;
        if (best > alpha) alpha = best;
        if (alpha >= beta) break;
      }
      return best;
    }
    var best = 1 << 30;
    for (final m in list) {
      final v = _search(apply(b, m), -toMove, me, depth - 1, alpha, beta);
      if (v < best) best = v;
      if (best < beta) beta = best;
      if (alpha >= beta) break;
    }
    return best;
  }

  /// Ход компьютера. level: 0 лёгкий (случайный), 1 средний (на 2 хода вперёд), 2 сильный (на 4-5)
  static CkrMove? aiMove(List<int> board, int side, int level, Random rnd) {
    final list = moves(board, side);
    if (list.isEmpty) return null;
    if (list.length == 1) return list.first;
    if (level <= 0) return list[rnd.nextInt(list.length)];
    var total = 0;
    for (final v in board) {
      if (v != 0) total++;
    }
    final depth = level == 1 ? 2 : (total <= 12 ? 5 : 4);
    CkrMove? best;
    var bestScore = -1 << 30;
    list.shuffle(rnd);
    for (final m in list) {
      final v = _search(
        apply(board, m),
        -side,
        side,
        depth - 1,
        -1 << 30,
        1 << 30,
      );
      if (v > bestScore) {
        bestScore = v;
        best = m;
      }
    }
    return best ?? list.first;
  }
}
