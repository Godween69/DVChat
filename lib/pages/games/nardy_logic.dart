// SPDX-License-Identifier: AGPL-3.0-or-later

// DVChat: нарды (короткие, с ударами и баром). Логика, ходы по правилам и компьютерный соперник.
// Поле: 24 пункта p[0..23]; белые хранятся положительными числами, чёрные отрицательными.
// Белые ходят от 23 к 0 (дом 0..5), чёрные от 0 к 23 (дом 18..23).
// Бар имеет номер 24. Выброс шашки с поля обозначается как пункт назначения -1.
// Кости общие для двоих: бросок хода считается из номера партии и номера хода,
// поэтому оба телефона получают одинаковые кости без обмена сообщениями.

import 'dart:math';

class NMove {
  const NMove(this.from, this.die, this.dest);

  final int from; // 0..23 пункт или 24 бар
  final int die; // 1..6
  final int dest; // 0..23 пункт или -1 выброс с поля

  /// Число, которое уходит в событие игры
  int get cell => from * 7 + die;

  static NMove? decode(int cell) {
    if (cell < 0) return null;
    final from = cell ~/ 7;
    final die = cell % 7;
    if (from > 24 || die < 1 || die > 6) return null;
    return NMove(from, die, -2);
  }
}

class NBoard {
  NBoard(this.p, this.bar, this.off);

  factory NBoard.start() {
    final p = List<int>.filled(24, 0);
    p[23] = 2;
    p[12] = 5;
    p[7] = 3;
    p[5] = 5;
    p[0] = -2;
    p[11] = -5;
    p[16] = -3;
    p[18] = -5;
    return NBoard(p, [0, 0], [0, 0]);
  }

  final List<int> p;
  final List<int> bar;
  final List<int> off;

  static const int illegal = -2;
  static const int offDest = -1;

  NBoard copy() => NBoard(List.of(p), List.of(bar), List.of(off));

  int own(int i, int pl) => pl == 0 ? (p[i] > 0 ? p[i] : 0) : (p[i] < 0 ? -p[i] : 0);

  bool allHome(int pl) {
    if (bar[pl] > 0) return false;
    if (pl == 0) {
      for (var i = 6; i < 24; i++) {
        if (p[i] > 0) return false;
      }
    } else {
      for (var i = 0; i < 18; i++) {
        if (p[i] < 0) return false;
      }
    }
    return true;
  }

  /// Куда придёт шашка при ходе from на die, либо illegal
  int destOf(int pl, int from, int die) {
    int to;
    if (bar[pl] > 0) {
      if (from != 24) return illegal;
    }
    if (from == 24) {
      if (bar[pl] == 0) return illegal;
      to = pl == 0 ? 24 - die : die - 1;
    } else {
      if (from < 0 || from > 23 || own(from, pl) == 0) return illegal;
      to = pl == 0 ? from - die : from + die;
    }
    if (to >= 0 && to <= 23) {
      return own(to, 1 - pl) >= 2 ? illegal : to;
    }
    // выброс с поля
    if (from == 24 || !allHome(pl)) return illegal;
    final exact = pl == 0 ? to == -1 : to == 24;
    if (exact) return offDest;
    // с перебросом: позади (дальше от выхода) не должно быть своих шашек
    if (pl == 0) {
      for (var i = from + 1; i <= 5; i++) {
        if (own(i, 0) > 0) return illegal;
      }
    } else {
      for (var i = from - 1; i >= 18; i--) {
        if (own(i, 1) > 0) return illegal;
      }
    }
    return offDest;
  }

  /// Ход (предполагается допустимым). Возвращает новое поле.
  NBoard apply(int pl, int from, int die) {
    final to = destOf(pl, from, die);
    final b = copy();
    if (from == 24) {
      b.bar[pl]--;
    } else {
      b.p[from] += pl == 0 ? -1 : 1;
    }
    if (to == offDest) {
      b.off[pl]++;
    } else {
      final hit = pl == 0 ? b.p[to] == -1 : b.p[to] == 1;
      if (hit) {
        b.p[to] = 0;
        b.bar[1 - pl]++;
      }
      b.p[to] += pl == 0 ? 1 : -1;
    }
    return b;
  }

  int pips(int pl) {
    var s = bar[pl] * 25;
    for (var i = 0; i < 24; i++) {
      if (pl == 0 && p[i] > 0) s += p[i] * (i + 1);
      if (pl == 1 && p[i] < 0) s += -p[i] * (24 - i);
    }
    return s;
  }

  String key() => '${p.join(',')}|${bar.join(',')}|${off.join(',')}';
}

class NSeq {
  NSeq(this.moves, this.board);

  final List<NMove> moves;
  final NBoard board;
}

class NPass {
  const NPass(this.pl, this.rolled, this.turn);

  final int pl;
  final List<int> rolled;
  final int turn;
}

class Nardy {
  /// Кости хода: одинаковые у обоих игроков по номеру партии и номеру хода
  static List<int> roll(String seed, int turn) {
    var h = 7;
    for (final c in seed.codeUnits) {
      h = (h * 31 + c) % 2147483647;
    }
    var x = (h + turn * 104729 + 12345) % 2147483647;
    if (x == 0) x = 1;
    int next() {
      x = (x * 16807) % 2147483647;
      return x;
    }

    next();
    next();
    final a = (next() ~/ 7) % 6 + 1;
    final b = (next() ~/ 7) % 6 + 1;
    return [a, b];
  }

  static List<int> expand(List<int> rolled) =>
      rolled[0] == rolled[1] ? [rolled[0], rolled[0], rolled[0], rolled[0]] : [rolled[0], rolled[1]];

  static void _dfs(
    NBoard b,
    int pl,
    List<int> dice,
    List<NMove> acc,
    List<NSeq> out,
    Set<String> seen,
  ) {
    if (b.off[pl] == 15) {
      out.add(NSeq(List.of(acc), b));
      return;
    }
    final key = '${b.key()}#${dice.join()}';
    if (!seen.add(key)) return;
    var any = false;
    final tried = <int>{};
    for (var k = 0; k < dice.length; k++) {
      final die = dice[k];
      if (!tried.add(die)) continue;
      final rest = List<int>.of(dice)..removeAt(k);
      final froms = <int>[];
      if (b.bar[pl] > 0) {
        froms.add(24);
      } else {
        for (var i = 0; i < 24; i++) {
          if (b.own(i, pl) > 0) froms.add(i);
        }
      }
      for (final f in froms) {
        final to = b.destOf(pl, f, die);
        if (to == NBoard.illegal) continue;
        any = true;
        acc.add(NMove(f, die, to));
        _dfs(b.apply(pl, f, die), pl, rest, acc, out, seen);
        acc.removeLast();
      }
    }
    if (!any) out.add(NSeq(List.of(acc), b));
  }

  /// Все полные ходы игрока по правилам: максимальное число сыгранных костей,
  /// а если можно сыграть только одну из двух разных, то большую.
  static List<NSeq> fullTurns(NBoard b, int pl, List<int> dice) {
    final out = <NSeq>[];
    _dfs(b, pl, dice, [], out, <String>{});
    var maxLen = 0;
    for (final s in out) {
      if (s.moves.length > maxLen) maxLen = s.moves.length;
    }
    var res = [
      for (final s in out)
        if (s.moves.length == maxLen) s,
    ];
    if (maxLen == 1 && dice.length == 2 && dice[0] != dice[1]) {
      final big = max(dice[0], dice[1]);
      final bigOnly = [
        for (final s in res)
          if (s.moves.first.die == big) s,
      ];
      if (bigOnly.isNotEmpty) res = bigOnly;
    }
    // одинаковые итоговые позиции не нужны
    final uniq = <String, NSeq>{};
    for (final s in res) {
      uniq.putIfAbsent(s.board.key(), () => s);
    }
    return uniq.values.toList();
  }

  /// Допустимые первые ходы (для подсветки и проверки)
  static List<NMove> firstMoves(NBoard b, int pl, List<int> dice) {
    if (dice.isEmpty) return [];
    final seqs = fullTurns(b, pl, dice);
    final seen = <int>{};
    final res = <NMove>[];
    for (final s in seqs) {
      if (s.moves.isEmpty) continue;
      final m = s.moves.first;
      if (seen.add(m.from * 7 + m.die)) res.add(m);
    }
    return res;
  }
}

/// Партия: восстанавливается из номера партии и списка ходов (from*7+die)
class NardyGame {
  NardyGame(this.seed) {
    board = NBoard.start();
    rolled = Nardy.roll(seed, 0);
    dice = Nardy.expand(rolled);
    _settle();
  }

  final String seed;
  late NBoard board;
  int pl = 0; // чей ход: 0 белые (хозяин партии), 1 чёрные
  int turn = 0;
  late List<int> rolled; // выпавшие кости хода (две)
  late List<int> dice; // оставшиеся кости
  int used = 0; // сыграно костей в этом ходу
  int winner = -1;
  int moveCount = 0;
  NMove? lastMove;
  int lastMovePl = 0;
  bool lastHit = false;
  List<NPass> lastPasses = [];
  List<NMove>? _lm;

  List<NMove> legalMoves() => _lm ??= Nardy.firstMoves(board, pl, dice);

  /// Сыграть ход шашкой from (0..23 или 24 бар) на кость die
  bool apply(int from, int die) {
    if (winner >= 0) return false;
    final di = dice.indexOf(die);
    if (di < 0) return false;
    NMove? m;
    for (final l in legalMoves()) {
      if (l.from == from && l.die == die) m = l;
    }
    if (m == null) return false;
    final before = board.bar[1 - pl];
    board = board.apply(pl, from, die);
    lastHit = board.bar[1 - pl] > before;
    lastMove = m;
    lastMovePl = pl;
    dice.removeAt(di);
    used++;
    moveCount++;
    lastPasses = [];
    _lm = null;
    if (board.off[pl] == 15) {
      winner = pl;
      dice = [];
      return true;
    }
    _settle();
    return true;
  }

  /// Передаёт ход, когда кости кончились или ходить нечем
  void _settle() {
    for (var guard = 0; guard < 40 && winner < 0; guard++) {
      _lm = null;
      if (dice.isNotEmpty && legalMoves().isNotEmpty) return;
      if (dice.isNotEmpty && used == 0) {
        lastPasses = [...lastPasses, NPass(pl, List.of(rolled), turn)];
      }
      pl = 1 - pl;
      turn++;
      rolled = Nardy.roll(seed, turn);
      dice = Nardy.expand(rolled);
      used = 0;
    }
  }

  int pips(int who) => board.pips(who);

  /// Победа с «марсом»: проигравший не вынес ни одной шашки
  bool get gammon => winner >= 0 && board.off[1 - winner] == 0;
}

/// Компьютерный соперник: перебор всех полных ходов, оценка позиции и
/// просмотр ответа соперника на каждый из 21 броска для лучших кандидатов.
class NardyAi {
  static double _blotRisk(NBoard b, int side, int i) {
    var h6 = 0, h12 = 0;
    if (side == 0) {
      // хит чёрными, что стоят позади (с меньшим номером), бар чёрных как -1
      if (b.bar[1] > 0) {
        final d = i + 1;
        if (d <= 6) {
          h6++;
        } else if (d <= 12) {
          h12++;
        }
      }
      for (var j = 0; j < i; j++) {
        if (b.p[j] < 0) {
          final d = i - j;
          if (d <= 6) {
            h6++;
          } else if (d <= 12) {
            h12++;
          }
        }
      }
    } else {
      if (b.bar[0] > 0) {
        final d = 24 - i;
        if (d <= 6) {
          h6++;
        } else if (d <= 12) {
          h12++;
        }
      }
      for (var j = i + 1; j < 24; j++) {
        if (b.p[j] > 0) {
          final d = j - i;
          if (d <= 6) {
            h6++;
          } else if (d <= 12) {
            h12++;
          }
        }
      }
    }
    if (h6 > 0) return (h6 == 1 ? 0.31 : 0.45) + (h12 > 0 ? 0.05 : 0);
    return h12 > 0 ? 0.12 : 0.0;
  }

  static bool _contact(NBoard b) {
    if (b.bar[0] > 0 || b.bar[1] > 0) return true;
    // белые идут вниз, чёрные вверх: пока чёрная шашка стоит ниже белой, они ещё встретятся
    var maxWhite = -1, minBlack = 99;
    for (var i = 0; i < 24; i++) {
      if (b.p[i] > 0 && i > maxWhite) maxWhite = i;
      if (b.p[i] < 0 && i < minBlack) minBlack = i;
    }
    return minBlack < maxWhite;
  }

  static double _side(NBoard b, int side, bool contact) {
    var s = -b.pips(side).toDouble();
    if (!contact) return s;
    s -= b.bar[side] * 12;
    var run = 0;
    for (var k = 0; k < 24; k++) {
      // обход от своего конца дома к началу, чтобы считать подряд идущие пункты
      final i = side == 0 ? k : 23 - k;
      final c = b.own(i, side);
      if (c == 1) {
        final loss = side == 0 ? (24 - i) : (i + 1);
        s -= _blotRisk(b, side, i) * (loss + 8);
      }
      if (c >= 2) {
        s += 3;
        final home = side == 0 ? i <= 5 : i >= 18;
        if (home) s += 2;
        final enemyHome = side == 0 ? i >= 18 : i <= 5;
        if (enemyHome) s += 4; // передовой якорь
        run++;
        if (run >= 3) s += run * 1.2;
        if (c > 4) s -= (c - 4) * 1.5;
      } else {
        run = 0;
      }
    }
    return s;
  }

  static double evaluate(NBoard b, int pl) {
    final contact = _contact(b);
    return _side(b, pl, contact) - _side(b, 1 - pl, contact);
  }

  /// Лучший полный ход для игрока pl на кости dice. Пустой список, если ходить нечем.
  static List<NMove> bestTurn(NBoard b, int pl, List<int> dice, {int ms = 900}) {
    final seqs = Nardy.fullTurns(b, pl, dice);
    if (seqs.isEmpty || seqs.first.moves.isEmpty) return [];
    if (seqs.length == 1) return seqs.first.moves;
    final scored = [
      for (final s in seqs) (s, evaluate(s.board, pl)),
    ]..sort((x, y) => y.$2.compareTo(x.$2));
    final top = scored.take(10).toList();
    final sw = Stopwatch()..start();
    var best = top.first.$1;
    var bestVal = -1e18;
    for (var c = 0; c < top.length; c++) {
      if (c > 1 && sw.elapsedMilliseconds > ms) break;
      final cand = top[c].$1;
      var v = 0.0;
      for (var a = 1; a <= 6; a++) {
        for (var d = a; d <= 6; d++) {
          final w = a == d ? 1.0 : 2.0;
          final oppDice = a == d ? [a, a, a, a] : [a, d];
          final replies = Nardy.fullTurns(cand.board, 1 - pl, oppDice);
          var worst = 1e18;
          if (replies.isEmpty || replies.first.moves.isEmpty) {
            worst = evaluate(cand.board, pl);
          } else {
            for (final r in replies) {
              final e = evaluate(r.board, pl);
              if (e < worst) worst = e;
            }
          }
          v += w * worst;
        }
      }
      v /= 36;
      if (v > bestVal) {
        bestVal = v;
        best = cand;
      }
    }
    return best.moves;
  }
}
