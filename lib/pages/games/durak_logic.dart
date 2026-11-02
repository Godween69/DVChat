// SPDX-License-Identifier: AGPL-3.0-or-later

// DVChat: правила дурака на двоих (колода 36 карт), подкидной и переводной, и компьютерный игрок.
// Карта это число 0..35: масть = карта ~/ 9 (0 пики, 1 червы, 2 бубны, 3 трефы), достоинство = карта % 9
// (0 это шестёрка, 8 это туз). Игрок 0 это пригласивший, игрок 1 это его соперник.
// Раздача зависит только от номера партии, поэтому на обоих телефонах колода одинаковая, а по сети
// ходят только действия, закодированные числом: op | карта << 4 | стол << 10.

class Dk {
  static const List<String> rankNames = [
    '6',
    '7',
    '8',
    '9',
    '10',
    'В',
    'Д',
    'К',
    'Т',
  ];
  static const List<String> suitNames = ['пики', 'червы', 'бубны', 'трефы'];

  static int suitOf(int c) => c ~/ 9;
  static int rankOf(int c) => c % 9;

  static const int opAdd = 1; // выложить (подкинуть) карту
  static const int opBeat = 2; // побить карту на столе
  static const int opTake = 3; // беру
  static const int opPass = 4; // бито или «готово»
  static const int opTrans = 5; // перевести

  static int mk(int op, [int card = 0, int slot = 0]) =>
      op | (card << 4) | (slot << 10);
  static int opOf(int m) => m & 15;
  static int cardOf(int m) => (m >> 4) & 63;
  static int slotOf(int m) => (m >> 10) & 7;

  /// Число из номера партии: одинаковое на всех устройствах
  static int seedOf(String id) {
    var h = 7;
    for (final u in id.codeUnits) {
      h = (h * 31 + u) % 2147483647;
    }
    return h == 0 ? 1 : h;
  }
}

/// Простой детерминированный генератор (одинаковый везде, без зависимости от платформы)
class DkRng {
  DkRng(int seed) : _s = seed % 2147483647 == 0 ? 1 : seed % 2147483647;

  int _s;

  int nextInt(int n) {
    _s = (_s * 48271) % 2147483647;
    return _s % n;
  }
}

class DkState {
  DkState({
    required this.mode,
    required this.hands,
    required this.stock,
    required this.trumpSuit,
    required this.trumpCard,
    required this.atk,
    required this.def,
    required this.attacker,
    required this.phase,
    required this.limit,
    required this.discard,
    required this.result,
  });

  /// Новая партия по номеру; mode: 'podkid' или 'perevod'
  factory DkState.start(int seed, String mode) {
    final rng = DkRng(seed);
    final deck = List<int>.generate(36, (i) => i);
    for (var i = deck.length - 1; i > 0; i--) {
      final j = rng.nextInt(i + 1);
      final t = deck[i];
      deck[i] = deck[j];
      deck[j] = t;
    }
    final stock = deck.sublist(12);
    final hands = [deck.sublist(0, 6), deck.sublist(6, 12)];
    final trumpCard = stock.last;
    final trump = Dk.suitOf(trumpCard);
    // Ходит первым тот, у кого младший козырь; если козырей на руках нет, решает жребий
    var first = -1;
    var low = 99;
    for (var p = 0; p < 2; p++) {
      for (final c in hands[p]) {
        if (Dk.suitOf(c) == trump && Dk.rankOf(c) < low) {
          low = Dk.rankOf(c);
          first = p;
        }
      }
    }
    if (first < 0) first = rng.nextInt(2);
    final s = DkState(
      mode: mode,
      hands: hands,
      stock: stock,
      trumpSuit: trump,
      trumpCard: trumpCard,
      atk: [],
      def: [],
      attacker: first,
      phase: 0,
      limit: 6,
      discard: [],
      result: -1,
    );
    s.limit = s._calcLimit();
    return s;
  }

  final String mode;
  final List<List<int>> hands;
  final List<int> stock;
  final int trumpSuit;
  final int trumpCard;

  /// Карты нападения на столе и чем они побиты (-1 если не побита)
  final List<int> atk;
  final List<int> def;
  int attacker;

  /// 0: ход нападающего, 1: защита, 2: нападающий добавляет после «беру»
  int phase;

  /// Сколько карт всего можно выложить в этом круге
  int limit;
  final List<int> discard;

  /// -1 идёт игра, 0 или 1 победил этот игрок (второй в дураках), 2 ничья
  int result;

  int get defender => 1 - attacker;

  /// Чей сейчас ход
  int get turn => phase == 1 ? defender : attacker;

  bool isTrump(int c) => Dk.suitOf(c) == trumpSuit;

  /// Бьёт ли карта d карту a
  bool beats(int d, int a) {
    if (Dk.suitOf(d) == Dk.suitOf(a)) return Dk.rankOf(d) > Dk.rankOf(a);
    return isTrump(d) && !isTrump(a);
  }

  DkState copy() => DkState(
    mode: mode,
    hands: [List.of(hands[0]), List.of(hands[1])],
    stock: List.of(stock),
    trumpSuit: trumpSuit,
    trumpCard: trumpCard,
    atk: List.of(atk),
    def: List.of(def),
    attacker: attacker,
    phase: phase,
    limit: limit,
    discard: List.of(discard),
    result: result,
  );

  int _calcLimit() {
    final n = hands[defender].length;
    return n < 6 ? n : 6;
  }

  int get _unbeaten => def.where((x) => x < 0).length;

  Set<int> get _tableRanks => {
    for (final c in atk) Dk.rankOf(c),
    for (final c in def)
      if (c >= 0) Dk.rankOf(c),
  };

  /// Карты, которые нападающий может сейчас подкинуть
  List<int> _addable() {
    if (atk.isEmpty) return List.of(hands[attacker]);
    if (atk.length >= limit) return const [];
    if (phase != 2 && _unbeaten + 1 > hands[defender].length) return const [];
    final ranks = _tableRanks;
    return [
      for (final c in hands[attacker])
        if (ranks.contains(Dk.rankOf(c))) c,
    ];
  }

  /// Можно ли перевести картой c (только в переводном, пока ничего не побито)
  bool _canTranslate(int c) {
    if (mode != 'perevod' || phase != 1) return false;
    if (def.any((x) => x >= 0) || atk.length >= 6) return false;
    final r = Dk.rankOf(atk.first);
    if (atk.any((x) => Dk.rankOf(x) != r)) return false;
    if (Dk.rankOf(c) != r) return false;
    return atk.length + 1 <= hands[attacker].length;
  }

  /// Допустимые действия того, чей сейчас ход
  List<int> legalMoves() {
    if (result >= 0) return const [];
    final out = <int>[];
    if (phase == 0 || phase == 2) {
      for (final c in _addable()) {
        out.add(Dk.mk(Dk.opAdd, c));
      }
      if (atk.isNotEmpty) out.add(Dk.mk(Dk.opPass));
    } else {
      for (var i = 0; i < atk.length; i++) {
        if (def[i] >= 0) continue;
        for (final c in hands[defender]) {
          if (beats(c, atk[i])) out.add(Dk.mk(Dk.opBeat, c, i));
        }
      }
      for (final c in hands[defender]) {
        if (_canTranslate(c)) out.add(Dk.mk(Dk.opTrans, c));
      }
      out.add(Dk.mk(Dk.opTake));
    }
    return out;
  }

  void _draw() {
    for (final p in [attacker, defender]) {
      while (hands[p].length < 6 && stock.isNotEmpty) {
        hands[p].add(stock.removeAt(0));
      }
    }
  }

  void _checkEnd() {
    if (stock.isNotEmpty) return;
    final e0 = hands[0].isEmpty;
    final e1 = hands[1].isEmpty;
    if (e0 && e1) {
      result = 2;
    } else if (e0) {
      result = 0;
    } else if (e1) {
      result = 1;
    }
  }

  void _endRound({required bool taken}) {
    if (taken) {
      hands[defender].addAll(atk);
      hands[defender].addAll(def.where((x) => x >= 0));
    } else {
      discard.addAll(atk);
      discard.addAll(def.where((x) => x >= 0));
    }
    atk.clear();
    def.clear();
    _draw();
    if (!taken) attacker = defender;
    phase = 0;
    _checkEnd();
    if (result < 0) limit = _calcLimit();
  }

  /// Если подкидывать больше нечего, круг заканчивается сам
  void _autoFinish() {
    if (result >= 0) return;
    if (phase == 0 && atk.isNotEmpty && _unbeaten == 0 && _addable().isEmpty) {
      _endRound(taken: false);
    } else if (phase == 2 && _addable().isEmpty) {
      _endRound(taken: true);
    }
  }

  /// Выполняет действие и возвращает новую позицию
  DkState apply(int m) {
    final s = copy();
    final op = Dk.opOf(m);
    final c = Dk.cardOf(m);
    switch (op) {
      case Dk.opAdd:
        s.hands[s.attacker].remove(c);
        s.atk.add(c);
        s.def.add(-1);
        if (s.phase == 0) s.phase = 1;
        s._autoFinish();
      case Dk.opBeat:
        s.hands[s.defender].remove(c);
        s.def[Dk.slotOf(m)] = c;
        if (s._unbeaten == 0) s.phase = 0;
        s._autoFinish();
      case Dk.opTake:
        s.phase = 2;
        s._autoFinish();
      case Dk.opPass:
        s._endRound(taken: s.phase == 2);
      case Dk.opTrans:
        s.hands[s.defender].remove(c);
        s.atk.add(c);
        s.def.add(-1);
        s.attacker = s.defender;
        s.phase = 1;
        s.limit = s._calcLimit();
    }
    return s;
  }

  /// Видимые игроку карты (его рука, стол, бито), нужны компьютеру для подсчёта карт
  List<int> seenBy(int p) => [
    ...hands[p],
    ...discard,
    ...atk,
    ...def.where((x) => x >= 0),
    trumpCard,
  ];
}

/// Компьютерный игрок: решает только по тому, что видит (своя рука, стол, бито, козырь)
class DkAi {
  static int _cost(DkState s, int c) => Dk.rankOf(c) + (s.isTrump(c) ? 20 : 0);

  static int move(DkState s, int p) {
    final moves = s.legalMoves();
    if (moves.length == 1) return moves.first;
    final hand = s.hands[p];
    if (s.phase == 1) return _defend(s, p, moves, hand);
    return _attack(s, p, moves, hand);
  }

  static int _attack(DkState s, int p, List<int> moves, List<int> hand) {
    final adds = [
      for (final m in moves)
        if (Dk.opOf(m) == Dk.opAdd) Dk.cardOf(m),
    ];
    if (adds.isEmpty) return Dk.mk(Dk.opPass);
    // Сколько карт каждого достоинства на руке: пары выгодно выкладывать вместе
    int same(int c) => hand.where((x) => Dk.rankOf(x) == Dk.rankOf(c)).length;
    adds.sort((a, b) {
      final d = _cost(s, a).compareTo(_cost(s, b));
      return d != 0 ? d : same(b).compareTo(same(a));
    });
    final best = adds.first;
    if (s.atk.isEmpty) return Dk.mk(Dk.opAdd, best);
    // Подкидываем только дешёвое: козыри и старшие карты придерживаем
    final endgame = s.stock.isEmpty;
    final cheap =
        !s.isTrump(best) && (Dk.rankOf(best) <= 5 || s.phase == 2 || endgame);
    if (cheap) return Dk.mk(Dk.opAdd, best);
    return Dk.mk(Dk.opPass);
  }

  static int _defend(DkState s, int p, List<int> moves, List<int> hand) {
    // Перевод: выгоден нетрёмовой картой
    final trans = [
      for (final m in moves)
        if (Dk.opOf(m) == Dk.opTrans && !s.isTrump(Dk.cardOf(m))) m,
    ];
    if (trans.isNotEmpty) {
      trans.sort(
        (a, b) => _cost(s, Dk.cardOf(a)).compareTo(_cost(s, Dk.cardOf(b))),
      );
      return trans.first;
    }
    // Побить всё самыми дешёвыми картами; если не выходит, берём
    final left = List.of(hand);
    final plan = <int>[];
    var trumpsUsed = 0;
    var spentOnLow = false;
    final open = [
      for (var i = 0; i < s.atk.length; i++)
        if (s.def[i] < 0) i,
    ]..sort((a, b) => Dk.rankOf(s.atk[b]).compareTo(Dk.rankOf(s.atk[a])));
    for (final i in open) {
      final cands = [
        for (final c in left)
          if (s.beats(c, s.atk[i])) c,
      ]..sort((a, b) => _cost(s, a).compareTo(_cost(s, b)));
      if (cands.isEmpty) return Dk.mk(Dk.opTake);
      final c = cands.first;
      if (s.isTrump(c)) {
        trumpsUsed++;
        if (!s.isTrump(s.atk[i]) && Dk.rankOf(s.atk[i]) <= 5) spentOnLow = true;
      }
      left.remove(c);
      plan.add(Dk.mk(Dk.opBeat, c, i));
    }
    final early = s.stock.length >= 4;
    if (early && (trumpsUsed >= 2 || (spentOnLow && hand.length <= 9))) {
      return Dk.mk(Dk.opTake);
    }
    // Первое действие плана; остальные карты будут побиты на следующих ходах
    final i0 = open.first;
    final first = plan.firstWhere((m) => Dk.slotOf(m) == i0);
    return first;
  }
}
