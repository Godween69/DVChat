// SPDX-License-Identifier: AGPL-3.0-or-later

// DVChat: экран морского боя. Два режима:
//  - с компьютером (level 0..2), без интернета;
//  - с другом (room + gameId + hostId): ходы идут через личный чат, расстановка каждого
//    хранится только на его телефоне, соперник получает её отпечаток, а в конце партии
//    расстановка раскрывается и проверяется.

import 'dart:async';
import 'dart:math';

import 'package:dvchat/pages/games/bs_logic.dart';
import 'package:dvchat/pages/games/dv_game_net.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Shot {
  const _Shot(this.cell, this.sender);

  final int cell;
  final String sender;
}

class _Res {
  const _Res(this.sender, this.res, this.ship);

  final String sender;
  final String res;
  final List<int> ship;
}

class _Reveal {
  const _Reveal(this.fleet, this.salt);

  final List<List<int>> fleet;
  final String salt;
}

class BsPage extends StatefulWidget {
  const BsPage({this.level, this.room, this.gameId, this.hostId, super.key});

  /// Для игры с компьютером: 0 лёгкий, 1 средний, 2 сильный
  final int? level;

  /// Для игры с другом
  final Room? room;
  final String? gameId;
  final String? hostId;

  @override
  State<BsPage> createState() => _BsPageState();
}

class _BsPageState extends State<BsPage> {
  static const List<String> _levelNames = ['Лёгкий', 'Средний', 'Сильный'];

  final Random _rnd = Random();

  // Общее состояние
  List<List<int>> _fleet = [];
  bool _placed = false;
  Map<int, int> _marks = {};
  List<List<int>> _sunk = [];
  Set<int> _incoming = {};
  bool _myTurn = false;
  bool _won = false;
  bool _lost = false;
  bool _busy = false;
  bool _loading = false;

  // Компьютер
  List<List<int>> _aiFleet = [];
  BsAi? _ai;

  // Сеть
  String _salt = '';
  final Map<String, String> _ready = {};
  final Map<int, _Shot> _shots = {};
  final Map<int, _Res> _results = {};
  final Map<String, _Reveal> _reveals = {};
  final Set<int> _answered = {};
  List<(int, String)> _log = [];
  int _nextN = 0;
  bool _waitResult = false;
  bool _bothReady = false;
  String _oppId = '';
  bool _revealSent = false;
  StreamSubscription<Event>? _sub;

  bool get _online => widget.room != null;
  String get _me => widget.room?.client.userID ?? '';
  bool get _finished => _won || _lost;
  String get _prefKey => 'dv_bs_${widget.gameId}';

  @override
  void initState() {
    super.initState();
    _fleet = BsLogic.randomFleet(_rnd);
    if (_online) {
      _loading = true;
      _sub = widget.room!.client.onTimelineEvent.stream.listen((e) {
        if (_ingest(e)) _rebuild();
      });
      unawaited(_load());
    } else {
      _aiFleet = BsLogic.randomFleet(_rnd);
      _ai = BsAi(widget.level ?? 1, _rnd);
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  // ---------------- сеть ----------------

  static List<int> _ints(Object? v) => v is List
      ? [
          for (final x in v)
            if (x is int) x,
        ]
      : <int>[];

  bool _ingest(Event e) {
    if (e.type != DvGameNet.eventType || e.roomId != widget.room?.id) {
      return false;
    }
    final c = e.content;
    if (c['game'] != 'bs' || '${c['id']}' != widget.gameId) return false;
    switch (c['kind']) {
      case 'ready':
        final h = c['commit'];
        if (h is String && !_ready.containsKey(e.senderId)) {
          _ready[e.senderId] = h;
          return true;
        }
      case 'shot':
        final n = c['n'];
        final cell = c['cell'];
        if (n is int &&
            cell is int &&
            cell >= 0 &&
            cell < 100 &&
            !_shots.containsKey(n)) {
          _shots[n] = _Shot(cell, e.senderId);
          return true;
        }
      case 'result':
        final n = c['n'];
        final res = c['res'];
        if (n is int &&
            (res == 'm' || res == 'h' || res == 's') &&
            !_results.containsKey(n)) {
          _results[n] = _Res(e.senderId, '$res', _ints(c['ship']));
          return true;
        }
      case 'reveal':
        final ships = c['ships'];
        final salt = c['salt'];
        if (ships is List &&
            salt is String &&
            !_reveals.containsKey(e.senderId)) {
          _reveals[e.senderId] = _Reveal([
            for (final s in ships) _ints(s),
          ], salt);
          return true;
        }
    }
    return false;
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_prefKey);
      if (saved != null && saved.contains('|')) {
        final i = saved.indexOf('|');
        _salt = saved.substring(0, i);
        _fleet = BsLogic.parse(saved.substring(i + 1));
      }
      final tl = await widget.room!.getTimeline(limit: 300);
      for (final e in tl.events) {
        _ingest(e);
      }
      tl.cancelSubscriptions();
    } catch (_) {
      // Не удалось прочитать историю: продолжим по новым событиям
    }
    _loading = false;
    _rebuild();
  }

  /// Пересчитывает состояние партии по всем полученным событиям
  void _rebuild() {
    final host = widget.hostId ?? '';
    final me = _me;
    final marks = <int, int>{};
    final sunk = <List<int>>[];
    final incoming = <int>{};
    final log = <(int, String)>[];
    final others = _ready.keys.where((k) => k != me).toList();
    final opp = me == host ? (others.isEmpty ? '' : others.first) : host;
    final bothReady = _ready.containsKey(me) && _ready.containsKey(opp);
    var turn = host;
    var n = 0;
    var pendingN = -1;
    _Shot? pending;
    if (bothReady) {
      while (_shots.containsKey(n)) {
        final s = _shots[n]!;
        if (s.sender != turn) break;
        final r = _results[n];
        if (r == null || r.sender == s.sender) {
          pending = s;
          pendingN = n;
          break;
        }
        if (s.sender == me) {
          marks[s.cell] = r.res == 'm' ? 0 : 1;
          log.add((s.cell, r.res));
          if (r.res == 's') {
            sunk.add(r.ship);
            for (final h in BsLogic.halo(r.ship)) {
              marks.putIfAbsent(h, () => 0);
            }
          }
        } else {
          incoming.add(s.cell);
        }
        if (r.res == 'm') turn = turn == me ? opp : me;
        n++;
      }
    }
    final won = sunk.length == BsLogic.shipSizes.length;
    final lost =
        bothReady &&
        _fleet.isNotEmpty &&
        incoming.isNotEmpty &&
        _fleet.expand((s) => s).every(incoming.contains);
    final incomingBefore = Set<int>.of(incoming);
    if (!mounted) return;
    setState(() {
      _marks = marks;
      _sunk = sunk;
      _incoming = incoming;
      _log = log;
      _oppId = opp;
      _bothReady = bothReady;
      _placed = _ready.containsKey(me);
      _won = won;
      _lost = lost;
      _nextN = n;
      _waitResult = pending != null && pending.sender == me;
      _myTurn = bothReady && !won && !lost && turn == me && pending == null;
    });
    if (pending != null &&
        pending.sender != me &&
        _placed &&
        _fleet.isNotEmpty &&
        !_answered.contains(pendingN)) {
      unawaited(_respond(pendingN, pending.cell, incomingBefore));
    }
    if ((won || lost) && !_revealSent) {
      _revealSent = true;
      unawaited(_sendReveal(won));
    }
  }

  Future<void> _respond(int n, int cell, Set<int> before) async {
    _answered.add(n);
    final r = BsLogic.resultOf(_fleet, before, cell);
    _results[n] = _Res(_me, r.res, r.ship);
    _rebuild();
    try {
      await widget.room!.sendEvent({
        'game': 'bs',
        'id': widget.gameId,
        'kind': 'result',
        'n': n,
        'res': r.res,
        'ship': r.ship,
      }, type: DvGameNet.eventType);
    } catch (_) {
      _results.remove(n);
      _answered.remove(n);
    }
  }

  Future<void> _sendReveal(bool winner) async {
    try {
      _reveals[_me] = _Reveal(_fleet, _salt);
      await widget.room!.sendEvent({
        'game': 'bs',
        'id': widget.gameId,
        'kind': 'reveal',
        'ships': _fleet,
        'salt': _salt,
      }, type: DvGameNet.eventType);
      if (winner) {
        await DvGameNet.sendEnd(widget.room!, game: 'bs', id: widget.gameId!);
      }
    } catch (_) {
      _revealSent = false;
    }
  }

  /// Случайная соль отпечатка: 128 бит
  static String _newSalt() {
    final r = Random.secure();
    return [
      for (var i = 0; i < 4; i++) r.nextInt(1 << 32).toRadixString(16),
    ].join();
  }

  Future<void> _confirmOnline() async {
    _salt = _newSalt();
    final commit = BsLogic.commit(_fleet, _salt);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKey, '$_salt|${BsLogic.serialize(_fleet)}');
      _ready[_me] = commit;
      _rebuild();
      await widget.room!.sendEvent({
        'game': 'bs',
        'id': widget.gameId,
        'kind': 'ready',
        'commit': commit,
      }, type: DvGameNet.eventType);
    } catch (_) {
      _ready.remove(_me);
      _rebuild();
      _snack('Не удалось отправить расстановку');
    }
  }

  Future<void> _shootOnline(int c) async {
    if (!_myTurn || _marks.containsKey(c)) return;
    final n = _nextN;
    _shots[n] = _Shot(c, _me);
    _rebuild();
    try {
      await widget.room!.sendEvent({
        'game': 'bs',
        'id': widget.gameId,
        'kind': 'shot',
        'n': n,
        'cell': c,
      }, type: DvGameNet.eventType);
    } catch (_) {
      _shots.remove(n);
      _rebuild();
      _snack('Не удалось отправить выстрел');
    }
  }

  /// true — расстановка соперника честная, false — нет, null — ещё не раскрыта
  bool? _opponentHonest() {
    final rv = _reveals[_oppId];
    final commit = _ready[_oppId];
    if (rv == null || commit == null) return null;
    if (BsLogic.commit(rv.fleet, rv.salt) != commit) return false;
    final sizes = [for (final s in rv.fleet) s.length]..sort();
    final need = List<int>.of(BsLogic.shipSizes)..sort();
    if (sizes.join(',') != need.join(',')) return false;
    final before = <int>{};
    for (final (cell, res) in _log) {
      if (BsLogic.resultOf(rv.fleet, before, cell).res != res) return false;
      before.add(cell);
    }
    return true;
  }

  // ---------------- игра с компьютером ----------------

  void _startPc() {
    setState(() {
      _placed = true;
      _myTurn = true;
    });
  }

  Future<void> _shootPc(int c) async {
    if (_busy || _finished || !_myTurn || _marks.containsKey(c)) return;
    final r = BsLogic.resultOf(_aiFleet, _marks.keys.toSet(), c);
    final marks = Map<int, int>.of(_marks)..[c] = r.res == 'm' ? 0 : 1;
    final sunk = List<List<int>>.of(_sunk);
    if (r.res == 's') {
      sunk.add(r.ship);
      for (final h in BsLogic.halo(r.ship)) {
        marks.putIfAbsent(h, () => 0);
      }
    }
    final won = sunk.length == BsLogic.shipSizes.length;
    setState(() {
      _marks = marks;
      _sunk = sunk;
      _won = won;
      if (r.res == 'm') _myTurn = false;
    });
    if (r.res == 'm' && !won) await _pcTurn();
  }

  Future<void> _pcTurn() async {
    setState(() => _busy = true);
    while (mounted) {
      await Future<void>.delayed(const Duration(milliseconds: 550));
      if (!mounted) return;
      final cell = _ai!.pick();
      final r = BsLogic.resultOf(_fleet, _ai!.shots, cell);
      _ai!.report(cell, r.res, r.ship);
      final incoming = Set<int>.of(_incoming)..add(cell);
      final lost = _fleet.expand((s) => s).every(incoming.contains);
      setState(() {
        _incoming = incoming;
        _lost = lost;
      });
      if (lost || r.res == 'm') break;
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (!_lost) _myTurn = true;
    });
  }

  // ---------------- общее ----------------

  void _snack(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  Future<void> _again() async {
    if (_online) {
      try {
        final id = await DvGameNet.sendInvite(
          widget.room!,
          game: 'bs',
          gameTitle: 'морской бой',
        );
        if (!mounted) return;
        await Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => BsPage(room: widget.room, gameId: id, hostId: _me),
          ),
        );
      } catch (_) {
        _snack('Не удалось отправить приглашение');
      }
      return;
    }
    setState(() {
      _fleet = BsLogic.randomFleet(_rnd);
      _aiFleet = BsLogic.randomFleet(_rnd);
      _ai = BsAi(widget.level ?? 1, _rnd);
      _marks = {};
      _sunk = [];
      _incoming = {};
      _won = false;
      _lost = false;
      _busy = false;
      _myTurn = false;
      _placed = false;
    });
  }

  String get _status {
    if (_loading) return 'Загрузка…';
    if (!_placed) return 'Расставьте корабли';
    if (_online && !_bothReady) return 'Ждём, пока соперник расставит корабли…';
    if (_won) return 'Вы победили! 🎉';
    if (_lost) return 'Вы проиграли';
    if (_online && _waitResult) return 'Ждём ответ соперника…';
    if (_myTurn) return 'Ваш выстрел';
    return _online ? 'Ход соперника…' : 'Компьютер стреляет…';
  }

  String? get _verdict {
    if (!_online || !_finished) return null;
    final h = _opponentHonest();
    if (h == null) return null;
    return h
        ? 'Расстановка соперника проверена: всё честно ✓'
        : '⚠ Расстановка соперника не совпала с обещанной';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = _online
        ? 'Морской бой · ${widget.room!.getLocalizedDisplayname()}'
        : 'Морской бой · ${_levelNames[(widget.level ?? 1).clamp(0, 2)]}';
    final showPlacement = !_loading && !_placed;
    final sunkCells = {for (final s in _sunk) ...s};
    final myCells = {for (final s in _fleet) ...s};
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Text(
                  _status,
                  style: theme.textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                if (_verdict != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(_verdict!, textAlign: TextAlign.center),
                  ),
                const SizedBox(height: 16),
                if (showPlacement) ...[
                  _BsGrid(
                    maxWidth: 340,
                    cell: (i) => _tile(
                      theme,
                      color: myCells.contains(i)
                          ? theme.colorScheme.primary
                          : theme.colorScheme.surfaceContainerHighest,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    alignment: WrapAlignment.center,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () =>
                            setState(() => _fleet = BsLogic.randomFleet(_rnd)),
                        icon: const Icon(Icons.shuffle),
                        label: const Text('Перемешать'),
                      ),
                      FilledButton.icon(
                        onPressed: _online ? _confirmOnline : _startPc,
                        icon: const Icon(Icons.check),
                        label: Text(_online ? 'Готов' : 'Играть'),
                      ),
                    ],
                  ),
                ] else if (_placed) ...[
                  if (_bothReady || !_online) ...[
                    Text('Поле соперника', style: theme.textTheme.labelLarge),
                    const SizedBox(height: 6),
                    _BsGrid(
                      maxWidth: 340,
                      onTap: _online ? _shootOnline : _shootPc,
                      cell: (i) {
                        final m = _marks[i];
                        if (m == null) {
                          return _tile(
                            theme,
                            color: theme.colorScheme.surfaceContainerHighest,
                          );
                        }
                        if (m == 0) {
                          return _tile(
                            theme,
                            color: theme.colorScheme.surfaceContainerHighest,
                            glyph: '•',
                            glyphColor: theme.colorScheme.outline,
                          );
                        }
                        return _tile(
                          theme,
                          color: sunkCells.contains(i)
                              ? theme.colorScheme.error
                              : theme.colorScheme.errorContainer,
                          glyph: '✕',
                          glyphColor: sunkCells.contains(i)
                              ? theme.colorScheme.onError
                              : theme.colorScheme.onErrorContainer,
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                  ],
                  Text('Ваше поле', style: theme.textTheme.labelLarge),
                  const SizedBox(height: 6),
                  _BsGrid(
                    maxWidth: 220,
                    small: true,
                    cell: (i) {
                      final ship = myCells.contains(i);
                      final shot = _incoming.contains(i);
                      return _tile(
                        theme,
                        small: true,
                        color: ship
                            ? (shot
                                  ? theme.colorScheme.error
                                  : theme.colorScheme.primary)
                            : theme.colorScheme.surfaceContainerHighest,
                        glyph: shot ? (ship ? '✕' : '•') : '',
                        glyphColor: ship
                            ? theme.colorScheme.onError
                            : theme.colorScheme.outline,
                      );
                    },
                  ),
                  if (_finished) ...[
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: _again,
                      icon: const Icon(Icons.replay),
                      label: Text(_online ? 'Сыграть ещё раз' : 'Новая партия'),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _tile(
    ThemeData theme, {
    required Color color,
    String glyph = '',
    Color? glyphColor,
    bool small = false,
  }) => Container(
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(small ? 2 : 4),
    ),
    alignment: Alignment.center,
    child: Text(
      glyph,
      style: TextStyle(
        fontSize: small ? 9 : 16,
        fontWeight: FontWeight.bold,
        color: glyphColor,
      ),
    ),
  );
}

class _BsGrid extends StatelessWidget {
  const _BsGrid({
    required this.cell,
    required this.maxWidth,
    this.onTap,
    this.small = false,
  });

  final Widget Function(int) cell;
  final double maxWidth;
  final void Function(int)? onTap;
  final bool small;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: BoxConstraints(maxWidth: maxWidth),
    child: AspectRatio(
      aspectRatio: 1,
      child: GridView.count(
        crossAxisCount: 10,
        mainAxisSpacing: small ? 1 : 2,
        crossAxisSpacing: small ? 1 : 2,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          for (var i = 0; i < 100; i++)
            GestureDetector(
              onTap: onTap == null ? null : () => onTap!(i),
              child: cell(i),
            ),
        ],
      ),
    ),
  );
}
