// SPDX-License-Identifier: AGPL-3.0-or-later

// DVChat: экран морского боя. Два режима:
//  - с компьютером (level 0..2), без интернета;
//  - с другом (room + gameId + hostId): ходы идут через личный чат, расстановка каждого
//    хранится только на его телефоне, соперник получает её отпечаток, а в конце партии
//    расстановка раскрывается и проверяется.

import 'package:dvchat/pages/games/dv_local_stats.dart';
import 'dart:async';
import 'dart:math';

import 'package:dvchat/config/themes.dart';
import 'package:dvchat/pages/games/bs_logic.dart';
import 'package:dvchat/pages/games/dv_game_net.dart';
import 'package:dvchat/pages/games/dv_game_sound.dart';
import 'package:dvchat/utils/dv_nicknames.dart';
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
  final Random _rnd = Random();

  // Общее состояние
  List<List<int>> _fleet = [];
  bool _placed = false;
  Map<int, int> _marks = {};
  List<List<int>> _sunk = [];
  Set<int> _incoming = {};
  int _lastMine = -1;
  int _lastIn = -1;
  bool _myTurn = false;
  bool _won = false;
  bool _lost = false;
  bool _busy = false;
  bool _loading = false;
  String? _surrenderBy;

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
    DvLocalStats.open('bs', offline: widget.room == null);
    _fleet = BsLogic.randomFleet(_rnd);
    if (_online) {
      _loading = true;
      _sub = widget.room!.client.onTimelineEvent.stream.listen((e) {
        if (_ingest(e)) _rebuild();
      });
      DvGameNet.activeGameId = widget.gameId;
      unawaited(_load());
    } else {
      _aiFleet = BsLogic.randomFleet(_rnd);
      _ai = BsAi(2, _rnd);
    }
  }

  @override
  void dispose() {
    if (DvGameNet.activeGameId == widget.gameId) {
      DvGameNet.activeGameId = null;
    }
    _sub?.cancel();
    DvLocalStats.close('bs');
    super.dispose();
  }

  // ---------------- звук ----------------

  void _playRes(String res) => unawaited(
    DvGameSound.play(
      res == 'm' ? DvSound.miss : (res == 's' ? DvSound.sunk : DvSound.hit),
    ),
  );

  void _finishSound(bool won) => unawaited(
    Future<void>.delayed(
      const Duration(milliseconds: 700),
      () => DvGameSound.play(won ? DvSound.win : DvSound.lose),
    ),
  );

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
      case 'end':
        final by = c['by'];
        if (c['reason'] == 'surrender' &&
            by is String &&
            _surrenderBy == null) {
          _surrenderBy = by;
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
    _rebuild(silent: true);
  }

  /// Пересчитывает состояние партии по всем полученным событиям
  void _rebuild({bool silent = false}) {
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
    var lastMine = -1;
    var lastIn = -1;
    String? lastMineRes;
    String? lastInRes;
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
          lastMine = s.cell;
          lastMineRes = r.res;
          if (r.res == 's') {
            sunk.add(r.ship);
            for (final h in BsLogic.halo(r.ship)) {
              marks.putIfAbsent(h, () => 0);
            }
          }
        } else {
          incoming.add(s.cell);
          lastIn = s.cell;
          lastInRes = r.res;
        }
        if (r.res == 'm') turn = turn == me ? opp : me;
        n++;
      }
    }
    final surr = _surrenderBy;
    final won =
        sunk.length == BsLogic.shipSizes.length || (surr != null && surr != me);
    final lost =
        (surr != null && surr == me) ||
        (bothReady &&
            _fleet.isNotEmpty &&
            incoming.isNotEmpty &&
            _fleet.expand((s) => s).every(incoming.contains));
    final incomingBefore = Set<int>.of(incoming);
    if (!mounted) return;
    final oldLog = _log.length;
    final oldIn = _incoming.length;
    final wasFinished = _finished;
    setState(() {
      _marks = marks;
      _sunk = sunk;
      _incoming = incoming;
      _log = log;
      _lastMine = lastMine;
      _lastIn = lastIn;
      _oppId = opp;
      _bothReady = bothReady;
      _placed = _ready.containsKey(me);
      _won = won;
      _lost = lost;
      _nextN = n;
      _waitResult = pending != null && pending.sender == me;
      _myTurn = bothReady && !won && !lost && turn == me && pending == null;
    });
    if (!silent) {
      if (log.length > oldLog && lastMineRes != null) {
        _playRes(lastMineRes);
      } else if (incoming.length > oldIn && lastInRes != null) {
        _playRes(lastInRes);
      }
      if (!wasFinished && (won || lost)) _finishSound(won);
    }
    if (pending != null &&
        pending.sender != me &&
        _placed &&
        _fleet.isNotEmpty &&
        !_answered.contains(pendingN)) {
      unawaited(_respond(pendingN, pending.cell, incomingBefore));
    }
    if ((won || lost) && !_revealSent && _surrenderBy == null) {
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
        await DvGameNet.sendEnd(
          widget.room!,
          game: 'bs',
          id: widget.gameId!,
          winner: _me,
        );
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
      _rebuild(silent: true);
      await widget.room!.sendEvent({
        'game': 'bs',
        'id': widget.gameId,
        'kind': 'ready',
        'commit': commit,
      }, type: DvGameNet.eventType);
    } catch (_) {
      _ready.remove(_me);
      _rebuild(silent: true);
      _snack('Не удалось отправить расстановку');
    }
  }

  Future<void> _shootOnline(int c) async {
    if (!_myTurn || _marks.containsKey(c)) return;
    final n = _nextN;
    _shots[n] = _Shot(c, _me);
    _rebuild(silent: true);
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
      _rebuild(silent: true);
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
      _lastMine = c;
      if (r.res == 'm') _myTurn = false;
    });
    _playRes(r.res);
    if (won) _finishSound(true);
    if (r.res == 'm' && !won) await _pcTurn();
  }

  Future<void> _pcTurn() async {
    setState(() => _busy = true);
    while (mounted) {
      await Future<void>.delayed(const Duration(milliseconds: 650));
      if (!mounted) return;
      final cell = _ai!.pick();
      final r = BsLogic.resultOf(_fleet, _ai!.shots, cell);
      _ai!.report(cell, r.res, r.ship);
      final incoming = Set<int>.of(_incoming)..add(cell);
      final lost = _fleet.expand((s) => s).every(incoming.contains);
      setState(() {
        _incoming = incoming;
        _lastIn = cell;
        _lost = lost;
      });
      _playRes(r.res);
      if (lost) _finishSound(false);
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
          announce: false,
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
      _ai = BsAi(2, _rnd);
      _marks = {};
      _sunk = [];
      _incoming = {};
      _lastMine = -1;
      _lastIn = -1;
      _won = false;
      _lost = false;
      _busy = false;
      _myTurn = false;
      _placed = false;
    });
  }

  String get _status {
    if (_loading) return 'Загрузка…';
    if (_surrenderBy != null) {
      return _surrenderBy == _me
          ? 'Вы сдались'
          : 'Соперник сдался. Вы победили! 🎉';
    }
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

  // ---------------- оформление ----------------

  bool _dark(ThemeData theme) => theme.brightness == Brightness.dark;

  /// Тёмно-красный для выстрелов: заметен и на светлой, и на тёмной воде
  Color _red(ThemeData theme) =>
      _dark(theme) ? const Color(0xFFE06060) : const Color(0xFF8B1A1A);

  /// Вода: слабый оттенок цвета сообщений
  Color _water(ThemeData theme) => Color.alphaBlend(
    theme.bubbleColor.withAlpha(_dark(theme) ? 64 : 50),
    theme.colorScheme.surfaceContainerHighest,
  );

  Widget _box(Color color, {Widget? child, Color? ring, bool small = false}) =>
      Container(
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(small ? 2 : 5),
          border: ring == null
              ? null
              : Border.all(color: ring, width: small ? 1.5 : 2),
        ),
        alignment: Alignment.center,
        child: child,
      );

  Widget _pop(String key, Color color, double size) =>
      TweenAnimationBuilder<double>(
        key: ValueKey(key),
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 380),
        curve: Curves.elasticOut,
        builder: (context, t, child) => Transform.scale(
          scale: t,
          child: Text(
            '✕',
            style: TextStyle(
              fontSize: size,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ),
      );

  Widget _miss(String key, Color color) => TweenAnimationBuilder<double>(
    key: ValueKey(key),
    tween: Tween(begin: 0, end: 1),
    duration: const Duration(milliseconds: 550),
    curve: Curves.easeOut,
    builder: (context, t, child) =>
        CustomPaint(painter: _RipplePainter(t, color), size: Size.infinite),
  );

  /// Число кораблей: крупная цифра и подпись под ней
  Widget _stat(ThemeData theme, String label, int count) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        '$count',
        style: theme.textTheme.headlineSmall?.copyWith(
          fontWeight: FontWeight.bold,
        ),
      ),
      Text(label, style: theme.textTheme.labelSmall),
    ],
  );

  Widget _enemyCell(ThemeData theme, int i, Color water, Set<int> sunkCells) {
    final red = _red(theme);
    final m = _marks[i];
    final ring = i == _lastMine
        ? theme.colorScheme.onSurface.withAlpha(150)
        : null;
    if (m == null) return _box(water, ring: ring);
    if (m == 0) {
      return _box(water, ring: ring, child: _miss('m$i', red));
    }
    if (sunkCells.contains(i)) {
      return _box(red, ring: ring, child: _pop('h$i', Colors.white, 16));
    }
    return _box(
      Color.alphaBlend(red.withAlpha(80), water),
      ring: ring,
      child: _pop('h$i', red, 16),
    );
  }

  Widget _ownCell(ThemeData theme, int i, Color water, Set<int> myCells) {
    final red = _red(theme);
    final ship = myCells.contains(i);
    final shot = _incoming.contains(i);
    final ring = i == _lastIn ? theme.colorScheme.tertiary : null;
    if (ship) {
      return _box(
        shot ? red : theme.bubbleColor,
        ring: ring,
        small: true,
        child: shot ? _pop('o$i', Colors.white, 9) : null,
      );
    }
    return _box(
      water,
      ring: ring,
      small: true,
      child: shot ? _miss('om$i', red) : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = _online
        ? 'Морской бой · ${widget.room!.dvDisplayname()}'
        : 'Морской бой';
    final showPlacement = !_loading && !_placed && !_finished;
    final playing = !showPlacement && (_placed || _finished);
    final showEnemy = playing && (_bothReady || !_online);
    final sunkCells = {for (final s in _sunk) ...s};
    final myCells = {for (final s in _fleet) ...s};
    final water = _water(theme);
    final enemyLeft = BsLogic.shipSizes.length - _sunk.length;
    final myLeft = _fleet.where((s) => !s.every(_incoming.contains)).length;
    final statusStyle = theme.textTheme.titleMedium?.copyWith(
      fontWeight: FontWeight.bold,
      color: _myTurn && !_finished
          ? theme.colorScheme.primary
          : theme.colorScheme.onSurface,
    );
    return Scaffold(
      appBar: AppBar(title: Text(title), actions: const [DvSoundButton()]),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, box) {
            const pad = 12.0;
            const smallSide = 150.0;
            final width = box.maxWidth - pad * 2;
            final Widget content;
            if (showPlacement) {
              content = Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _status,
                    style: theme.textTheme.titleLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 14),
                  _BsGrid(
                    maxWidth: 340,
                    cell: (i) =>
                        _box(myCells.contains(i) ? theme.bubbleColor : water),
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
                ],
              );
            } else if (showEnemy) {
              // Всё на одном экране: большое поле, под ним слева состояние хода,
              // в середине своё маленькое поле, справа число кораблей
              final reserve =
                  smallSide +
                  14 +
                  (_finished ? (_verdict != null ? 110 : 80) : 0);
              final big = (box.maxHeight - pad * 2 - reserve).clamp(
                120.0,
                width,
              );
              content = Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _AimGrid(
                    side: big,
                    enabled: _myTurn && !_busy && !_finished && !_waitResult,
                    aimColor: theme.colorScheme.primary,
                    onShoot: _online ? _shootOnline : _shootPc,
                    cell: (i) => _enemyCell(theme, i, water, sunkCells),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: width,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: Text(
                              _status,
                              style: statusStyle,
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                        SizedBox.square(
                          dimension: smallSide,
                          child: _BsGrid(
                            maxWidth: smallSide,
                            small: true,
                            cell: (i) => _ownCell(theme, i, water, myCells),
                          ),
                        ),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(left: 8),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _stat(theme, 'у соперника', enemyLeft),
                                const SizedBox(height: 8),
                                _stat(theme, 'у вас', myLeft),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_verdict != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(_verdict!, textAlign: TextAlign.center),
                    ),
                  if (_finished) ...[
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: _again,
                      icon: const Icon(Icons.replay),
                      label: Text(_online ? 'Сыграть ещё раз' : 'Новая партия'),
                    ),
                  ],
                ],
              );
            } else {
              // Ждём соперника или загрузку: статус и своё поле
              content = Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _status,
                    style: theme.textTheme.titleLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 14),
                  _BsGrid(
                    maxWidth: 260,
                    small: true,
                    cell: (i) => _ownCell(theme, i, water, myCells),
                  ),
                  if (_finished) ...[
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _again,
                      icon: const Icon(Icons.replay),
                      label: Text(_online ? 'Сыграть ещё раз' : 'Новая партия'),
                    ),
                  ],
                ],
              );
            }
            return SingleChildScrollView(
              // Пока идёт бой, экран не прокручивается: прицел ведётся пальцем
              physics: showEnemy && !_finished
                  ? const NeverScrollableScrollPhysics()
                  : null,
              padding: const EdgeInsets.all(pad),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: box.maxHeight - pad * 2,
                  minWidth: width,
                ),
                child: Center(child: content),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Круги на воде от промаха: точка остаётся, кольцо расходится и гаснет
class _RipplePainter extends CustomPainter {
  _RipplePainter(this.t, this.color);

  final double t;
  final Color color;

  @override
  void paint(Canvas canvas, Size s) {
    final c = Offset(s.width / 2, s.height / 2);
    final dot = Paint()..color = color;
    canvas.drawCircle(c, max(1.5, s.shortestSide * 0.09), dot);
    if (t < 1) {
      final ring = Paint()
        ..color = color.withValues(alpha: (1 - t) * 0.7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      canvas.drawCircle(c, s.shortestSide * (0.1 + 0.4 * t), ring);
    }
  }

  @override
  bool shouldRepaint(_RipplePainter old) => old.t != t || old.color != color;
}

/// Неинтерактивная сетка 10x10 (расстановка и своё поле)
class _BsGrid extends StatelessWidget {
  const _BsGrid({
    required this.cell,
    required this.maxWidth,
    this.small = false,
  });

  final Widget Function(int) cell;
  final double maxWidth;
  final bool small;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: BoxConstraints(maxWidth: maxWidth),
    child: AspectRatio(
      aspectRatio: 1,
      child: GridView.count(
        crossAxisCount: 10,
        padding: EdgeInsets.zero,
        mainAxisSpacing: small ? 1 : 2,
        crossAxisSpacing: small ? 1 : 2,
        physics: const NeverScrollableScrollPhysics(),
        children: [for (var i = 0; i < 100; i++) cell(i)],
      ),
    ),
  );
}

/// Поле соперника с прицелом: касание ставит квадрат, он идёт за пальцем,
/// выстрел делается, когда палец оторван над полем. Оторвал за пределами поля — выстрела нет.
class _AimGrid extends StatefulWidget {
  const _AimGrid({
    required this.side,
    required this.cell,
    required this.enabled,
    required this.onShoot,
    required this.aimColor,
  });

  final double side;
  final Widget Function(int) cell;
  final bool enabled;
  final void Function(int) onShoot;
  final Color aimColor;

  @override
  State<_AimGrid> createState() => _AimGridState();
}

class _AimGridState extends State<_AimGrid> {
  static const double _gap = 2;

  int? _pointer;
  int? _aim;

  double get _pitch => (widget.side + _gap) / 10;

  int? _cellAt(Offset p) {
    final side = widget.side;
    if (p.dx < 0 || p.dy < 0 || p.dx >= side || p.dy >= side) return null;
    final col = (p.dx ~/ _pitch).clamp(0, 9);
    final row = (p.dy ~/ _pitch).clamp(0, 9);
    return row * 10 + col;
  }

  void _down(PointerDownEvent e) {
    if (!widget.enabled || _pointer != null) return;
    _pointer = e.pointer;
    setState(() => _aim = _cellAt(e.localPosition));
  }

  void _move(PointerMoveEvent e) {
    if (e.pointer != _pointer) return;
    final c = _cellAt(e.localPosition);
    if (c != _aim) setState(() => _aim = c);
  }

  void _up(PointerUpEvent e) {
    if (e.pointer != _pointer) return;
    final c = _cellAt(e.localPosition);
    _pointer = null;
    setState(() => _aim = null);
    if (c != null) widget.onShoot(c);
  }

  void _cancel(PointerCancelEvent e) {
    if (e.pointer != _pointer) return;
    _pointer = null;
    setState(() => _aim = null);
  }

  @override
  Widget build(BuildContext context) {
    final side = widget.side;
    final pitch = _pitch;
    final tile = pitch - _gap;
    final aim = _aim;
    final color = widget.aimColor;
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _down,
      onPointerMove: _move,
      onPointerUp: _up,
      onPointerCancel: _cancel,
      child: SizedBox.square(
        dimension: side,
        child: Stack(
          children: [
            IgnorePointer(
              child: GridView.count(
                crossAxisCount: 10,
                padding: EdgeInsets.zero,
                mainAxisSpacing: _gap,
                crossAxisSpacing: _gap,
                physics: const NeverScrollableScrollPhysics(),
                children: [for (var i = 0; i < 100; i++) widget.cell(i)],
              ),
            ),
            if (aim != null) ...[
              Positioned(
                left: 0,
                top: (aim ~/ 10) * pitch,
                width: side,
                height: tile,
                child: IgnorePointer(
                  child: ColoredBox(color: color.withAlpha(30)),
                ),
              ),
              Positioned(
                left: (aim % 10) * pitch,
                top: 0,
                width: tile,
                height: side,
                child: IgnorePointer(
                  child: ColoredBox(color: color.withAlpha(30)),
                ),
              ),
              Positioned(
                left: (aim % 10) * pitch - 1,
                top: (aim ~/ 10) * pitch - 1,
                width: tile + 2,
                height: tile + 2,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: color.withAlpha(70),
                      border: Border.all(color: color, width: 3),
                      borderRadius: BorderRadius.circular(5),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
