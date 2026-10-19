// SPDX-License-Identifier: AGPL-3.0-or-later

// DVChat: шахматные правила и компьютерный соперник. Полные правила: рокировка, взятие на
// проходе, превращение пешки, шах, мат, пат, правило 50 ходов, нехватка материала.
// Клетка = номер от 0 до 63, считая по рядам сверху вниз: 0 это a8, 7 это h8, 56 это a1, 63 это h1.
// Фигуры: 1 пешка, 2 конь, 3 слон, 4 ладья, 5 ферзь, 6 король; белые положительные, чёрные отрицательные.
// Ход упакован в число: откуда | куда << 6 | превращение << 12.
// Уровней сложности нет: компьютер ищет ход перебором с отсечениями, пока не истечёт время.

import 'dart:math';

class ChessState {
  const ChessState(
    this.b,
    this.white,
    this.castle,
    this.ep,
    this.half,
    this.full,
  );

  factory ChessState.start() {
    final b = List<int>.filled(64, 0);
    const back = [4, 2, 3, 5, 6, 3, 2, 4];
    for (var c = 0; c < 8; c++) {
      b[c] = -back[c];
      b[8 + c] = -1;
      b[48 + c] = 1;
      b[56 + c] = back[c];
    }
    return ChessState(b, true, 15, -1, 0, 1);
  }

  factory ChessState.fromList(List<int> d) =>
      ChessState(d.sublist(0, 64), d[64] == 1, d[65], d[66], d[67], d[68]);

  final List<int> b;

  /// Чей ход
  final bool white;

  /// Права на рокировку: 1 белая короткая, 2 белая длинная, 4 чёрная короткая, 8 чёрная длинная
  final int castle;

  /// Клетка, которую можно взять на проходе, или -1
  final int ep;

  /// Полуходов без взятия и хода пешки
  final int half;

  /// Номер хода (с единицы)
  final int full;

  List<int> toList() => [...b, white ? 1 : 0, castle, ep, half, full];

  /// Ключ позиции для подсчёта повторений
  String get key => '${b.join(',')}|${white ? 1 : 0}|$castle|$ep';
}

enum ChessEnd { none, mate, stalemate, fifty, material, repeat }

class Chess {
  static const _knightD = [
    [-2, -1], [-2, 1], [-1, -2], [-1, 2], [1, -2], [1, 2], [2, -1], [2, 1], //
  ];
  static const _kingD = [
    [-1, -1], [-1, 0], [-1, 1], [0, -1], [0, 1], [1, -1], [1, 0], [1, 1], //
  ];
  static const _bishopD = [
    [-1, -1], [-1, 1], [1, -1], [1, 1], //
  ];
  static const _rookD = [
    [-1, 0], [1, 0], [0, -1], [0, 1], //
  ];

  /// Бьёт ли сторона byWhite клетку sq
  static bool attacked(List<int> b, int sq, bool byWhite) {
    final r = sq >> 3;
    final c = sq & 7;
    final s = byWhite ? 1 : -1;
    final pr = byWhite ? r + 1 : r - 1;
    if (pr >= 0 && pr < 8) {
      if (c > 0 && b[pr * 8 + c - 1] == s) return true;
      if (c < 7 && b[pr * 8 + c + 1] == s) return true;
    }
    for (final d in _knightD) {
      final rr = r + d[0];
      final cc = c + d[1];
      if (rr < 0 || rr > 7 || cc < 0 || cc > 7) continue;
      if (b[rr * 8 + cc] == 2 * s) return true;
    }
    for (final d in _kingD) {
      final rr = r + d[0];
      final cc = c + d[1];
      if (rr < 0 || rr > 7 || cc < 0 || cc > 7) continue;
      if (b[rr * 8 + cc] == 6 * s) return true;
    }
    for (final d in _bishopD) {
      var rr = r + d[0];
      var cc = c + d[1];
      while (rr >= 0 && rr < 8 && cc >= 0 && cc < 8) {
        final v = b[rr * 8 + cc];
        if (v != 0) {
          if (v == 3 * s || v == 5 * s) return true;
          break;
        }
        rr += d[0];
        cc += d[1];
      }
    }
    for (final d in _rookD) {
      var rr = r + d[0];
      var cc = c + d[1];
      while (rr >= 0 && rr < 8 && cc >= 0 && cc < 8) {
        final v = b[rr * 8 + cc];
        if (v != 0) {
          if (v == 4 * s || v == 5 * s) return true;
          break;
        }
        rr += d[0];
        cc += d[1];
      }
    }
    return false;
  }

  static int kingSq(List<int> b, bool white) {
    final k = white ? 6 : -6;
    for (var i = 0; i < 64; i++) {
      if (b[i] == k) return i;
    }
    return -1;
  }

  static bool inCheck(ChessState s) =>
      attacked(s.b, kingSq(s.b, s.white), !s.white);

  /// Ходы без проверки, не остался ли свой король под боем
  static List<int> pseudo(ChessState s) {
    final out = <int>[];
    final b = s.b;
    final w = s.white;
    final sg = w ? 1 : -1;
    for (var i = 0; i < 64; i++) {
      final v = b[i];
      if (v == 0 || (v > 0) != w) continue;
      final t = v.abs();
      final r = i >> 3;
      final c = i & 7;
      if (t == 1) {
        final dr = w ? -1 : 1;
        final startR = w ? 6 : 1;
        final lastR = w ? 1 : 6;
        final r1 = r + dr;
        if (r1 < 0 || r1 > 7) continue;
        void add(int to) {
          if (r == lastR) {
            for (final p in const [5, 4, 3, 2]) {
              out.add(i | (to << 6) | (p << 12));
            }
          } else {
            out.add(i | (to << 6));
          }
        }

        if (b[r1 * 8 + c] == 0) {
          add(r1 * 8 + c);
          if (r == startR && b[(r1 + dr) * 8 + c] == 0) {
            out.add(i | (((r1 + dr) * 8 + c) << 6));
          }
        }
        for (final dc in const [-1, 1]) {
          final cc = c + dc;
          if (cc < 0 || cc > 7) continue;
          final to = r1 * 8 + cc;
          final tv = b[to];
          if ((tv != 0 && (tv > 0) != w) || to == s.ep) add(to);
        }
      } else if (t == 2 || t == 6) {
        for (final d in t == 2 ? _knightD : _kingD) {
          final rr = r + d[0];
          final cc = c + d[1];
          if (rr < 0 || rr > 7 || cc < 0 || cc > 7) continue;
          final tv = b[rr * 8 + cc];
          if (tv == 0 || (tv > 0) != w) out.add(i | ((rr * 8 + cc) << 6));
        }
        if (t == 6 && i == (w ? 60 : 4)) {
          final base = w ? 56 : 0;
          final rk = w ? 1 : 4;
          final rq = w ? 2 : 8;
          if (s.castle & (rk | rq) != 0 && !attacked(b, i, !w)) {
            if (s.castle & rk != 0 &&
                b[base + 5] == 0 &&
                b[base + 6] == 0 &&
                b[base + 7] == 4 * sg &&
                !attacked(b, base + 5, !w) &&
                !attacked(b, base + 6, !w)) {
              out.add(i | ((base + 6) << 6));
            }
            if (s.castle & rq != 0 &&
                b[base + 1] == 0 &&
                b[base + 2] == 0 &&
                b[base + 3] == 0 &&
                b[base] == 4 * sg &&
                !attacked(b, base + 3, !w) &&
                !attacked(b, base + 2, !w)) {
              out.add(i | ((base + 2) << 6));
            }
          }
        }
      } else {
        final dirs = t == 3 ? _bishopD : (t == 4 ? _rookD : _kingD);
        for (final d in dirs) {
          var rr = r + d[0];
          var cc = c + d[1];
          while (rr >= 0 && rr < 8 && cc >= 0 && cc < 8) {
            final tv = b[rr * 8 + cc];
            if (tv == 0) {
              out.add(i | ((rr * 8 + cc) << 6));
            } else {
              if ((tv > 0) != w) out.add(i | ((rr * 8 + cc) << 6));
              break;
            }
            rr += d[0];
            cc += d[1];
          }
        }
      }
    }
    return out;
  }

  /// Выполняет ход и возвращает новую позицию
  static ChessState apply(ChessState s, int m) {
    final from = m & 63;
    final to = (m >> 6) & 63;
    final promo = (m >> 12) & 7;
    final b = List<int>.of(s.b);
    final piece = b[from];
    final captured = b[to];
    final type = piece.abs();
    b[to] = piece;
    b[from] = 0;
    if (type == 1 && to == s.ep && (from & 7) != (to & 7)) {
      b[s.white ? to + 8 : to - 8] = 0;
    }
    if (promo != 0) b[to] = s.white ? promo : -promo;
    if (type == 6 && (to - from).abs() == 2) {
      if (to > from) {
        b[to - 1] = b[to + 1];
        b[to + 1] = 0;
      } else {
        b[to + 1] = b[to - 2];
        b[to - 2] = 0;
      }
    }
    var castle = s.castle;
    if (type == 6) castle &= s.white ? ~3 : ~12;
    if (from == 63 || to == 63) castle &= ~1;
    if (from == 56 || to == 56) castle &= ~2;
    if (from == 7 || to == 7) castle &= ~4;
    if (from == 0 || to == 0) castle &= ~8;
    final ep = (type == 1 && (to - from).abs() == 16) ? (from + to) >> 1 : -1;
    final half = (type == 1 || captured != 0) ? 0 : s.half + 1;
    return ChessState(
      b,
      !s.white,
      castle,
      ep,
      half,
      s.white ? s.full : s.full + 1,
    );
  }

  static List<int> legalMoves(ChessState s) {
    final out = <int>[];
    for (final m in pseudo(s)) {
      final n = apply(s, m);
      if (!attacked(n.b, kingSq(n.b, s.white), !s.white)) out.add(m);
    }
    return out;
  }

  /// Как закончилась партия (без учёта троекратного повторения, его считает экран)
  static ChessEnd end(ChessState s) {
    if (legalMoves(s).isEmpty) {
      return inCheck(s) ? ChessEnd.mate : ChessEnd.stalemate;
    }
    if (s.half >= 100) return ChessEnd.fifty;
    var minors = 0;
    for (final v in s.b) {
      final t = v.abs();
      if (t == 0 || t == 6) continue;
      if (t == 2 || t == 3) {
        minors++;
      } else {
        return ChessEnd.none;
      }
    }
    return minors <= 1 ? ChessEnd.material : ChessEnd.none;
  }
}

class _Timeout implements Exception {}

/// Компьютерный игрок: перебор с отсечениями, углубление по времени, оценка по таблицам клеток
class ChessAi {
  static const List<int> _val = [0, 100, 320, 330, 500, 900, 0];
  static const int _inf = 1000000;

  static const List<List<int>> _pst = [
    [],
    [
      0, 0, 0, 0, 0, 0, 0, 0, //
      50, 50, 50, 50, 50, 50, 50, 50, //
      10, 10, 20, 30, 30, 20, 10, 10, //
      5, 5, 10, 25, 25, 10, 5, 5, //
      0, 0, 0, 20, 20, 0, 0, 0, //
      5, -5, -10, 0, 0, -10, -5, 5, //
      5, 10, 10, -20, -20, 10, 10, 5, //
      0, 0, 0, 0, 0, 0, 0, 0, //
    ],
    [
      -50, -40, -30, -30, -30, -30, -40, -50, //
      -40, -20, 0, 0, 0, 0, -20, -40, //
      -30, 0, 10, 15, 15, 10, 0, -30, //
      -30, 5, 15, 20, 20, 15, 5, -30, //
      -30, 0, 15, 20, 20, 15, 0, -30, //
      -30, 5, 10, 15, 15, 10, 5, -30, //
      -40, -20, 0, 5, 5, 0, -20, -40, //
      -50, -40, -30, -30, -30, -30, -40, -50, //
    ],
    [
      -20, -10, -10, -10, -10, -10, -10, -20, //
      -10, 0, 0, 0, 0, 0, 0, -10, //
      -10, 0, 5, 10, 10, 5, 0, -10, //
      -10, 5, 5, 10, 10, 5, 5, -10, //
      -10, 0, 10, 10, 10, 10, 0, -10, //
      -10, 10, 10, 10, 10, 10, 10, -10, //
      -10, 5, 0, 0, 0, 0, 5, -10, //
      -20, -10, -10, -10, -10, -10, -10, -20, //
    ],
    [
      0, 0, 0, 0, 0, 0, 0, 0, //
      5, 10, 10, 10, 10, 10, 10, 5, //
      -5, 0, 0, 0, 0, 0, 0, -5, //
      -5, 0, 0, 0, 0, 0, 0, -5, //
      -5, 0, 0, 0, 0, 0, 0, -5, //
      -5, 0, 0, 0, 0, 0, 0, -5, //
      -5, 0, 0, 0, 0, 0, 0, -5, //
      0, 0, 0, 5, 5, 0, 0, 0, //
    ],
    [
      -20, -10, -10, -5, -5, -10, -10, -20, //
      -10, 0, 0, 0, 0, 0, 0, -10, //
      -10, 0, 5, 5, 5, 5, 0, -10, //
      -5, 0, 5, 5, 5, 5, 0, -5, //
      0, 0, 5, 5, 5, 5, 0, -5, //
      -10, 5, 5, 5, 5, 5, 0, -10, //
      -10, 0, 5, 0, 0, 0, 0, -10, //
      -20, -10, -10, -5, -5, -10, -10, -20, //
    ],
    [
      -30, -40, -40, -50, -50, -40, -40, -30, //
      -30, -40, -40, -50, -50, -40, -40, -30, //
      -30, -40, -40, -50, -50, -40, -40, -30, //
      -30, -40, -40, -50, -50, -40, -40, -30, //
      -20, -30, -30, -40, -40, -30, -30, -20, //
      -10, -20, -20, -20, -20, -20, -20, -10, //
      20, 20, 0, 0, 0, 0, 20, 20, //
      20, 30, 10, 0, 0, 10, 30, 20, //
    ],
  ];

  final Stopwatch _sw = Stopwatch();
  int _nodes = 0;
  int _limit = 1500;

  /// Оценка с точки зрения того, чей ход
  static int evaluate(ChessState s) {
    var score = 0;
    var heavy = 0;
    for (final v in s.b) {
      final t = v.abs();
      if (t > 1 && t < 6) heavy += _val[t];
    }
    final endgame = heavy <= 2600;
    for (var i = 0; i < 64; i++) {
      final v = s.b[i];
      if (v == 0) continue;
      final t = v.abs();
      final white = v > 0;
      final idx = white ? i : i ^ 56;
      int p;
      if (t == 6 && endgame) {
        final r = idx >> 3;
        final c = idx & 7;
        p = -4 * ((2 * r - 7).abs() + (2 * c - 7).abs());
      } else {
        p = _pst[t][idx];
      }
      final val = _val[t] + p;
      score += white ? val : -val;
    }
    return s.white ? score : -score;
  }

  /// Хорошие ходы вперёд: сначала взятия (дорогую фигуру дешёвой), потом превращения
  static void _order(ChessState s, List<int> moves) {
    final keys = <int>[];
    for (final m in moves) {
      final from = m & 63;
      final to = (m >> 6) & 63;
      final promo = (m >> 12) & 7;
      var victim = s.b[to].abs();
      if (victim == 0 &&
          s.b[from].abs() == 1 &&
          to == s.ep &&
          (from & 7) != (to & 7)) {
        victim = 1;
      }
      var score = 0;
      if (victim != 0)
        score = 10000 + _val[victim] * 10 - _val[s.b[from].abs()];
      if (promo != 0) score += 9000 + _val[promo];
      keys.add((score << 16) | m);
    }
    keys.sort((a, b) => b.compareTo(a));
    for (var i = 0; i < keys.length; i++) {
      moves[i] = keys[i] & 0xFFFF;
    }
  }

  int _quiesce(ChessState s, int alpha, int beta, int qd) {
    if ((++_nodes & 2047) == 0 && _sw.elapsedMilliseconds > _limit) {
      throw _Timeout();
    }
    final stand = evaluate(s);
    if (stand >= beta) return stand;
    if (stand > alpha) alpha = stand;
    if (qd >= 6) return alpha;
    final moves = <int>[];
    for (final m in Chess.pseudo(s)) {
      final from = m & 63;
      final to = (m >> 6) & 63;
      if (s.b[to] != 0 ||
          ((m >> 12) & 7) != 0 ||
          (s.b[from].abs() == 1 && to == s.ep && (from & 7) != (to & 7))) {
        moves.add(m);
      }
    }
    _order(s, moves);
    for (final m in moves) {
      final n = Chess.apply(s, m);
      if (Chess.attacked(n.b, Chess.kingSq(n.b, s.white), !s.white)) continue;
      final sc = -_quiesce(n, -beta, -alpha, qd + 1);
      if (sc >= beta) return sc;
      if (sc > alpha) alpha = sc;
    }
    return alpha;
  }

  int _search(ChessState s, int depth, int alpha, int beta, int ply) {
    if ((++_nodes & 2047) == 0 && _sw.elapsedMilliseconds > _limit) {
      throw _Timeout();
    }
    if (s.half >= 100) return 0;
    final inChk = Chess.inCheck(s);
    if (inChk && ply < 10) depth++;
    if (depth <= 0) return _quiesce(s, alpha, beta, 0);
    final moves = Chess.pseudo(s);
    _order(s, moves);
    var legal = 0;
    var best = -_inf;
    for (final m in moves) {
      final n = Chess.apply(s, m);
      if (Chess.attacked(n.b, Chess.kingSq(n.b, s.white), !s.white)) continue;
      legal++;
      final sc = -_search(n, depth - 1, -beta, -alpha, ply + 1);
      if (sc > best) best = sc;
      if (best > alpha) alpha = best;
      if (alpha >= beta) break;
    }
    if (legal == 0) return inChk ? -30000 + ply : 0;
    return best;
  }

  /// Лучший ход за время millis (в миллисекундах) или 0, если ходов нет
  int best(ChessState s, int millis) {
    _limit = millis;
    _nodes = 0;
    _sw
      ..reset()
      ..start();
    final ordered = Chess.legalMoves(s);
    if (ordered.isEmpty) return 0;
    if (ordered.length == 1) return ordered.first;
    _order(s, ordered);
    var bestMove = ordered.first;
    for (var depth = 1; depth <= 8; depth++) {
      var alpha = -_inf;
      var iterBest = ordered.first;
      try {
        for (final m in ordered) {
          final n = Chess.apply(s, m);
          final sc = -_search(n, depth - 1, -_inf, -alpha, 1);
          if (sc > alpha) {
            alpha = sc;
            iterBest = m;
          }
        }
      } on _Timeout {
        break;
      }
      bestMove = iterBest;
      ordered
        ..remove(iterBest)
        ..insert(0, iterBest);
      if (alpha > 29000) break;
    }
    return bestMove;
  }
}

/// Точка входа для отдельного потока: данные это ChessState.toList() плюс время и зерно случайности
int chessAiEntry(List<int> d) {
  final s = ChessState.fromList(d);
  if (s.full == 1 && s.white) {
    // Первый ход белых: разные популярные дебюты, чтобы партии не были одинаковыми
    const openings = [
      52 | (36 << 6),
      51 | (35 << 6),
      62 | (45 << 6),
      50 | (34 << 6),
    ];
    return openings[Random(d[70]).nextInt(openings.length)];
  }
  return ChessAi().best(s, d[69]);
}
