// SPDX-License-Identifier: AGPL-3.0-or-later

// DVChat: логика морского боя (классические правила 10x10). Работает без интернета.
// Клетка поля = число 0..99 (строка * 10 + столбец).

import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

class BsLogic {
  static const int size = 10;
  static const List<int> shipSizes = [4, 3, 3, 2, 2, 2, 1, 1, 1, 1];

  /// Все соседние клетки, включая диагональные
  static List<int> neighbors8(int c) {
    final r = c ~/ size;
    final col = c % size;
    return [
      for (var dr = -1; dr <= 1; dr++)
        for (var dc = -1; dc <= 1; dc++)
          if ((dr != 0 || dc != 0) &&
              r + dr >= 0 &&
              r + dr < size &&
              col + dc >= 0 &&
              col + dc < size)
            (r + dr) * size + col + dc,
    ];
  }

  /// Соседние клетки по сторонам (вверх, вниз, влево, вправо)
  static List<int> neighbors4(int c) {
    final r = c ~/ size;
    final col = c % size;
    return [
      if (r > 0) c - size,
      if (r < size - 1) c + size,
      if (col > 0) c - 1,
      if (col < size - 1) c + 1,
    ];
  }

  /// Клетки вокруг корабля (где других кораблей быть не может)
  static Set<int> halo(List<int> ship) {
    final result = <int>{};
    for (final c in ship) {
      result.addAll(neighbors8(c));
    }
    result.removeAll(ship);
    return result;
  }

  /// Случайная расстановка: корабли не касаются друг друга
  static List<List<int>> randomFleet(Random rnd) {
    while (true) {
      final fleet = <List<int>>[];
      final occupied = <int>{};
      var ok = true;
      for (final len in shipSizes) {
        var placed = false;
        for (var t = 0; t < 200 && !placed; t++) {
          final horiz = rnd.nextBool();
          final r = rnd.nextInt(horiz ? size : size - len + 1);
          final c = rnd.nextInt(horiz ? size - len + 1 : size);
          final cells = [
            for (var k = 0; k < len; k++)
              horiz ? r * size + c + k : (r + k) * size + c,
          ];
          if (cells.any(occupied.contains)) continue;
          fleet.add(cells);
          for (final x in cells) {
            occupied.add(x);
            occupied.addAll(neighbors8(x));
          }
          placed = true;
        }
        if (!placed) {
          ok = false;
          break;
        }
      }
      if (ok) return fleet;
    }
  }

  /// Каноническая запись расстановки (для отпечатка и хранения)
  static String serialize(List<List<int>> fleet) {
    final ships = [for (final s in fleet) (List<int>.of(s)..sort())]
      ..sort((a, b) => a.first.compareTo(b.first));
    return ships.map((s) => s.join(',')).join(';');
  }

  static List<List<int>> parse(String s) {
    if (s.isEmpty) return [];
    return [
      for (final p in s.split(';'))
        [for (final x in p.split(',')) int.parse(x)],
    ];
  }

  /// Отпечаток расстановки: SHA-256 от соли и расстановки
  static String commit(List<List<int>> fleet, String salt) =>
      sha256.convert(utf8.encode('$salt|${serialize(fleet)}')).toString();

  /// Результат выстрела: m — мимо, h — ранил, s — потопил
  static ({String res, List<int> ship}) resultOf(
    List<List<int>> fleet,
    Set<int> before,
    int cell,
  ) {
    for (final s in fleet) {
      if (s.contains(cell)) {
        final all = s.every((x) => x == cell || before.contains(x));
        return (res: all ? 's' : 'h', ship: all ? s : const <int>[]);
      }
    }
    return (res: 'm', ship: const <int>[]);
  }
}

/// Компьютерный стрелок. level: 0 лёгкий, 1 средний, 2 сильный.
class BsAi {
  BsAi(this.level, this.rnd);

  final int level;
  final Random rnd;
  final Set<int> shots = {};
  final Set<int> blocked = {};
  final Set<int> openHits = {};

  bool _free(int c) =>
      c >= 0 &&
      c < 100 &&
      !shots.contains(c) &&
      (level == 0 || !blocked.contains(c));

  int pick() {
    if (level >= 1 && openHits.isNotEmpty) {
      final hits = openHits.toList()..sort();
      final cands = <int>{};
      if (hits.length >= 2) {
        final horiz = hits.every((h) => h ~/ 10 == hits.first ~/ 10);
        final vert = hits.every((h) => h % 10 == hits.first % 10);
        if (horiz || vert) {
          final step = horiz ? 1 : 10;
          for (final h in [hits.first - step, hits.last + step]) {
            final sameRow = !horiz || h ~/ 10 == hits.first ~/ 10;
            if (sameRow && _free(h)) cands.add(h);
          }
        }
      }
      if (cands.isEmpty) {
        for (final h in hits) {
          for (final n in BsLogic.neighbors4(h)) {
            if (_free(n)) cands.add(n);
          }
        }
      }
      if (cands.isNotEmpty) {
        final list = cands.toList();
        return list[rnd.nextInt(list.length)];
      }
    }
    var free = [
      for (var i = 0; i < 100; i++)
        if (_free(i)) i,
    ];
    if (free.isEmpty) {
      free = [
        for (var i = 0; i < 100; i++)
          if (!shots.contains(i)) i,
      ];
    }
    if (level >= 2) {
      final parity = free.where((i) => ((i ~/ 10) + (i % 10)).isEven).toList();
      if (parity.isNotEmpty) free = parity;
    }
    return free[rnd.nextInt(free.length)];
  }

  void report(int cell, String res, List<int> ship) {
    shots.add(cell);
    if (res == 'h' || res == 's') openHits.add(cell);
    if (res == 's') {
      openHits.removeAll(ship);
      blocked.addAll(BsLogic.halo(ship));
    }
  }
}
