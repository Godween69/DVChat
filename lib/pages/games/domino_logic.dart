// SPDX-License-Identifier: AGPL-3.0-or-later

// DVChat: домино на двоих (28 фишек, по 7 в руку, остальные в базаре).
// Раздача общая для обоих телефонов: фишки тасуются по номеру партии.
// Ход кодируется числом: 0..55 это фишка*2+край (0 слева, 1 справа), 100 взять из базара, 101 пропуск.

class DTile {
  const DTile(this.a, this.b);

  final int a;
  final int b;

  int get pips => a + b;
  bool get isDouble => a == b;
}

class Domino {
  static final List<DTile> all = [
    for (var a = 0; a <= 6; a++)
      for (var b = a; b <= 6; b++) DTile(a, b),
  ];

  static const int drawCell = 100;
  static const int passCell = 101;

  /// Порядок фишек после тасования по номеру партии
  static List<int> shuffled(String seed) {
    var h = 11;
    for (final c in seed.codeUnits) {
      h = (h * 31 + c) % 2147483647;
    }
    var x = h % 2147483646 + 1;
    int next() {
      x = (x * 16807) % 2147483647;
      return x;
    }

    next();
    next();
    final list = List<int>.generate(28, (i) => i);
    for (var i = 27; i > 0; i--) {
      final j = (next() ~/ 7) % (i + 1);
      final t = list[i];
      list[i] = list[j];
      list[j] = t;
    }
    return list;
  }
}

class DOpt {
  const DOpt(this.tile, this.end);

  final int tile;
  final int end; // 0 слева, 1 справа

  int get cell => tile * 2 + end;
}

class DominoGame {
  DominoGame(this.seed) {
    final order = Domino.shuffled(seed);
    hands = [order.sublist(0, 7), order.sublist(7, 14)];
    stock = order.sublist(14);
    pl = _starter();
  }

  final String seed;
  late List<List<int>> hands;
  late List<int> stock;

  /// Цепочка: фишки в порядке слева направо, каждая в ориентации (левое число, правое число)
  final List<(int, int)> chain = [];
  final List<int> chainTiles = [];
  late int pl; // чей ход: 0 хозяин партии, 1 гость
  int winner = -1; // 0, 1 или 2 (ничья)
  bool blocked = false;
  int passes = 0;
  int moveCount = 0;
  int lastTile = -1;
  int lastEnd = 0;
  int lastDrawPl = -1; // кто брал из базара последним действием
  final List<(int, int, int)> drawLog = []; // кто брал, левый и правый концы цепочки

  int? get left => chain.isEmpty ? null : chain.first.$1;
  int? get right => chain.isEmpty ? null : chain.last.$2;

  int _starter() {
    int best(int p) {
      var d = -1;
      for (final t in hands[p]) {
        final tile = Domino.all[t];
        if (tile.isDouble && tile.a > d) d = tile.a;
      }
      return d;
    }

    final d0 = best(0), d1 = best(1);
    if (d0 >= 0 || d1 >= 0) return d0 > d1 ? 0 : 1;
    int top(int p) {
      var m = -1;
      for (final t in hands[p]) {
        final s = Domino.all[t].pips * 10 + Domino.all[t].a;
        if (s > m) m = s;
      }
      return m;
    }

    return top(0) > top(1) ? 0 : 1;
  }

  List<DOpt> options(int p) {
    final res = <DOpt>[];
    for (final t in hands[p]) {
      final tile = Domino.all[t];
      if (chain.isEmpty) {
        res.add(DOpt(t, 0));
        continue;
      }
      final l = left!, r = right!;
      if (tile.a == l || tile.b == l) res.add(DOpt(t, 0));
      if (tile.a == r || tile.b == r) res.add(DOpt(t, 1));
    }
    return res;
  }

  bool get mustDraw => winner < 0 && options(pl).isEmpty && stock.isNotEmpty;
  bool get mustPass => winner < 0 && options(pl).isEmpty && stock.isEmpty;

  int handPips(int p) => hands[p].fold(0, (s, t) => s + Domino.all[t].pips);

  /// Выполнить действие текущего игрока. false, если оно недопустимо.
  bool apply(int cell) {
    if (winner >= 0) return false;
    if (cell == Domino.drawCell) {
      if (!mustDraw) return false;
      hands[pl].add(stock.removeAt(0));
      drawLog.add((pl, left ?? -1, right ?? -1));
      lastDrawPl = pl;
      lastTile = -1;
      moveCount++;
      return true;
    }
    if (cell == Domino.passCell) {
      if (!mustPass) return false;
      passes++;
      lastDrawPl = -1;
      lastTile = -1;
      moveCount++;
      if (passes >= 2) {
        blocked = true;
        final a = handPips(0), b = handPips(1);
        winner = a == b ? 2 : (a < b ? 0 : 1);
      } else {
        pl = 1 - pl;
      }
      return true;
    }
    if (cell < 0 || cell > 55) return false;
    final t = cell ~/ 2, e = cell % 2;
    final okOpt = options(pl).any((o) => o.tile == t && o.end == e);
    if (!okOpt) return false;
    final tile = Domino.all[t];
    if (chain.isEmpty) {
      chain.add((tile.a, tile.b));
      chainTiles.add(t);
    } else if (e == 0) {
      final l = left!;
      chain.insert(0, tile.b == l ? (tile.a, tile.b) : (tile.b, tile.a));
      chainTiles.insert(0, t);
    } else {
      final r = right!;
      chain.add(tile.a == r ? (tile.a, tile.b) : (tile.b, tile.a));
      chainTiles.add(t);
    }
    hands[pl].remove(t);
    passes = 0;
    lastTile = t;
    lastEnd = chain.length == 1 ? 0 : e;
    lastDrawPl = -1;
    moveCount++;
    if (hands[pl].isEmpty) {
      winner = pl;
    } else {
      pl = 1 - pl;
    }
    return true;
  }
}

/// Компьютерный соперник. Видит только свою руку и то, что лежит на столе.
class DominoAi {
  static int choose(DominoGame g, int p) {
    final opts = g.options(p);
    if (opts.isEmpty) {
      return g.stock.isNotEmpty ? Domino.drawCell : Domino.passCell;
    }
    // чего нет у соперника: он брал из базара, когда на концах были эти числа
    final lacks = <int>{};
    for (final d in g.drawLog) {
      if (d.$1 != p) {
        if (d.$2 >= 0) lacks.add(d.$2);
        if (d.$3 >= 0) lacks.add(d.$3);
      }
    }
    var best = opts.first;
    var bestScore = -1e9;
    for (final o in opts) {
      final tile = Domino.all[o.tile];
      int nl, nr;
      if (g.chain.isEmpty) {
        nl = tile.a;
        nr = tile.b;
      } else if (o.end == 0) {
        nl = tile.a == g.left! ? tile.b : tile.a;
        nr = g.right!;
      } else {
        nl = g.left!;
        nr = tile.b == g.right! ? tile.a : tile.b;
      }
      var score = tile.pips.toDouble();
      if (tile.isDouble) score += 3;
      // оставшиеся в руке фишки, которые смогут ходить на новые концы
      for (final t in g.hands[p]) {
        if (t == o.tile) continue;
        final x = Domino.all[t];
        for (final end in [nl, nr]) {
          if (x.a == end || x.b == end) score += 1.2;
        }
      }
      if (lacks.contains(nl)) score += 4;
      if (lacks.contains(nr)) score += 4;
      if (g.hands[p].length == 1) score += 100;
      if (score > bestScore) {
        bestScore = score;
        best = o;
      }
    }
    return best.cell;
  }
}
