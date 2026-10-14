// SPDX-License-Identifier: AGPL-3.0-or-later

// DVChat: логика крестиков-ноликов и компьютерный соперник. Работает без интернета.
// Поле: 9 клеток, значения '' (пусто), 'X', 'O'. Первым всегда ходит X.

import 'dart:math';

class TttLogic {
  static const List<List<int>> lines = [
    [0, 1, 2],
    [3, 4, 5],
    [6, 7, 8],
    [0, 3, 6],
    [1, 4, 7],
    [2, 5, 8],
    [0, 4, 8],
    [2, 4, 6],
  ];

  /// Выигравшая линия или null
  static List<int>? winLine(List<String> b) {
    for (final l in lines) {
      if (b[l[0]] != '' && b[l[0]] == b[l[1]] && b[l[1]] == b[l[2]]) {
        return l;
      }
    }
    return null;
  }

  static String? winner(List<String> b) {
    final l = winLine(b);
    return l == null ? null : b[l[0]];
  }

  static bool isFull(List<String> b) => !b.contains('');

  static String turnOf(List<String> b) =>
      b.where((c) => c != '').length.isEven ? 'X' : 'O';

  static final Random _rnd = Random();

  /// Ход компьютера. level: 0 лёгкий, 1 средний, 2 непобедимый.
  static int aiMove(List<String> board, String ai, int level) {
    final b = List<String>.of(board);
    final hu = ai == 'X' ? 'O' : 'X';
    final free = [
      for (var i = 0; i < 9; i++)
        if (b[i] == '') i,
    ];
    if (level <= 0) return free[_rnd.nextInt(free.length)];

    if (level == 1) {
      // Сначала выигрыш, потом защита, потом центр или случайная клетка
      for (final who in [ai, hu]) {
        for (final i in free) {
          b[i] = who;
          final w = winner(b);
          b[i] = '';
          if (w == who) return i;
        }
      }
      if (b[4] == '' && _rnd.nextBool()) return 4;
      return free[_rnd.nextInt(free.length)];
    }

    // Непобедимый: полный перебор (поле маленькое)
    var best = -2;
    final bestMoves = <int>[];
    for (final i in free) {
      b[i] = ai;
      final s = _minimax(b, hu, ai, hu);
      b[i] = '';
      if (s > best) {
        best = s;
        bestMoves
          ..clear()
          ..add(i);
      } else if (s == best) {
        bestMoves.add(i);
      }
    }
    return bestMoves[_rnd.nextInt(bestMoves.length)];
  }

  static int _minimax(List<String> b, String turn, String ai, String hu) {
    final w = winner(b);
    if (w == ai) return 1;
    if (w == hu) return -1;
    if (isFull(b)) return 0;
    var best = turn == ai ? -2 : 2;
    for (var i = 0; i < 9; i++) {
      if (b[i] != '') continue;
      b[i] = turn;
      final s = _minimax(b, turn == ai ? hu : ai, ai, hu);
      b[i] = '';
      if (turn == ai) {
        if (s > best) best = s;
      } else {
        if (s < best) best = s;
      }
    }
    return best;
  }
}
