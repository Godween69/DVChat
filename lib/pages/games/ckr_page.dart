// SPDX-License-Identifier: AGPL-3.0-or-later

// DVChat: экран русских шашек. Два режима:
//  - с компьютером (level 0..2), без интернета;
//  - с другом (room + gameId + hostId): ходы идут через личный чат.
// Управление под большой палец: касаешься своей шашки, подсвечиваются клетки, куда она
// может пойти, ведёшь палец и отпускаешь на нужной клетке. Бить обязательно.

import 'dart:async';
import 'dart:math';

import 'package:dvchat/config/themes.dart';
import 'package:dvchat/pages/games/ckr_logic.dart';
import 'package:dvchat/pages/games/dv_game_net.dart';
import 'package:dvchat/pages/games/dv_game_sound.dart';
import 'package:dvchat/utils/dv_nicknames.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

class _NetMove {
  const _NetMove(this.path, this.sender);

  final List<int> path;
  final String sender;
}

class CkrPage extends StatefulWidget {
  const CkrPage({this.level, this.room, this.gameId, this.hostId, super.key});

  /// Для игры с компьютером: 0 лёгкий, 1 средний, 2 сильный
  final int? level;

  /// Для игры с другом
  final Room? room;
  final String? gameId;
  final String? hostId;

  @override
  State<CkrPage> createState() => _CkrPageState();
}

class _CkrPageState extends State<CkrPage> {
  static const List<String> _levelNames = ['Лёгкий', 'Средний', 'Сильный'];

  /// Ничья, если 30 ходов подряд ходят только дамки и никто никого не бьёт
  static const int _drawPlies = 30;

  final Random _rnd = Random();

  List<int> _board = CkrLogic.initial();
  List<CkrMove> _legal = const [];
  int _toMove = 1;
  int _quiet = 0;
  int _count = 0;
  CkrMove? _last;
  String? _lastSender;

  // С компьютером
  bool _humanFirst = true;
  bool _busy = false;

  // Сеть
  final Map<int, _NetMove> _netMoves = {};
  StreamSubscription<Event>? _sub;
  bool _endSent = false;
  bool _loading = false;
  String? _surrenderBy;

  // Управление пальцем
  int? _selected;
  int? _hover;
  int? _pointer;
  Offset? _finger;

  bool get _online => widget.room != null;
  String get _me => widget.room?.client.userID ?? '';

  /// Моя сторона: 1 белые (внизу, ходят первыми), -1 чёрные
  int get _mine =>
      _online ? (widget.hostId == _me ? 1 : -1) : (_humanFirst ? 1 : -1);

  /// Чёрным доску поворачиваем, чтобы свои шашки были снизу
  bool get _flip => _mine < 0;

  int get _winnerSide {
    if (_surrenderBy != null) return _surrenderBy == _me ? -_mine : _mine;
    if (_legal.isEmpty) return -_toMove;
    return 0;
  }

  bool get _finished =>
      _surrenderBy != null || _legal.isEmpty || _quiet >= _drawPlies;

  bool get _myTurn => !_loading && !_busy && !_finished && _toMove == _mine;

  @override
  void initState() {
    super.initState();
    _legal = CkrLogic.moves(_board, _toMove);
    if (_online) {
      _loading = true;
      _sub = widget.room!.client.onTimelineEvent.stream.listen((e) {
        if (_ingest(e)) _rebuild();
      });
      DvGameNet.activeGameId = widget.gameId;
      unawaited(_load());
    }
  }

  @override
  void dispose() {
    if (DvGameNet.activeGameId == widget.gameId) {
      DvGameNet.activeGameId = null;
    }
    _sub?.cancel();
    super.dispose();
  }

  // ---------------- сеть ----------------

  bool _ingest(Event e) {
    if (e.type != DvGameNet.eventType || e.roomId != widget.room?.id) {
      return false;
    }
    final c = e.content;
    if (c['game'] != 'ckr' || '${c['id']}' != widget.gameId) return false;
    if (c['kind'] == 'end' && c['reason'] == 'surrender') {
      final by = c['by'];
      if (by is String && _surrenderBy == null) {
        _surrenderBy = by;
        return true;
      }
      return false;
    }
    if (c['kind'] != 'move') return false;
    final n = c['n'];
    final path = c['path'];
    if (n is! int || path is! List || path.length < 2) return false;
    final cells = <int>[];
    for (final x in path) {
      if (x is! int || x < 0 || x > 63) return false;
      cells.add(x);
    }
    if (_netMoves.containsKey(n)) return false;
    _netMoves[n] = _NetMove(cells, e.senderId);
    return true;
  }

  Future<void> _load() async {
    try {
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

  /// Собирает партию с начала из всех полученных ходов, проверяя очерёдность и правила
  void _rebuild({bool silent = false}) {
    var b = CkrLogic.initial();
    var turn = 1;
    var n = 0;
    var quiet = 0;
    CkrMove? last;
    String? lastSender;
    while (_netMoves.containsKey(n)) {
      final nm = _netMoves[n]!;
      final fromHost = nm.sender == widget.hostId;
      if ((turn == 1) != fromHost) break;
      final m = CkrLogic.find(b, turn, nm.path);
      if (m == null) break;
      quiet = CkrLogic.isQuiet(b, m) ? quiet + 1 : 0;
      b = CkrLogic.apply(b, m);
      turn = -turn;
      last = m;
      lastSender = nm.sender;
      n++;
      if (quiet >= _drawPlies || CkrLogic.moves(b, turn).isEmpty) break;
    }
    if (!mounted) return;
    final oldCount = _count;
    final wasFinished = _finished;
    setState(() {
      _board = b;
      _toMove = turn;
      _quiet = quiet;
      _count = n;
      _last = last;
      _lastSender = lastSender;
      _legal = CkrLogic.moves(b, turn);
      _selected = null;
      _hover = null;
    });
    if (!silent) _soundFor(oldCount, wasFinished, last);
    _maybeSendEnd();
  }

  void _maybeSendEnd() {
    if (!_online || _endSent || !_finished || _surrenderBy != null) return;
    if (_lastSender != _me) return;
    _endSent = true;
    final w = _winnerSide;
    unawaited(
      DvGameNet.sendEnd(
        widget.room!,
        game: 'ckr',
        id: widget.gameId!,
        winner: w == 0 ? '' : _me,
      ).catchError((_) => null),
    );
  }

  // ---------------- звук ----------------

  void _soundFor(int oldCount, bool wasFinished, CkrMove? last) {
    if (!wasFinished && _finished) {
      final w = _winnerSide;
      final sound = w == 0
          ? DvSound.miss
          : (w == _mine ? DvSound.win : DvSound.lose);
      unawaited(DvGameSound.play(sound));
    } else if (_count > oldCount && last != null) {
      final mineMove = _lastSender == _me;
      unawaited(
        DvGameSound.play(
          last.captured.isNotEmpty
              ? DvSound.hit
              : (mineMove ? DvSound.place : DvSound.enemy),
        ),
      );
    }
  }

  // ---------------- ходы ----------------

  /// Выбирает ход из выбранной клетки в клетку to (если путей несколько, берём с большим боем)
  CkrMove? _moveTo(int from, int to) {
    CkrMove? best;
    for (final m in _legal) {
      if (m.from == from && m.to == to) {
        if (best == null || m.captured.length > best.captured.length) best = m;
      }
    }
    return best;
  }

  Set<int> _targets(int from) => {
    for (final m in _legal)
      if (m.from == from) m.to,
  };

  Future<void> _play(CkrMove m) async {
    if (!_myTurn) return;
    if (_online) {
      final n = _count;
      _netMoves[n] = _NetMove(m.path, _me);
      _rebuild();
      try {
        await widget.room!.sendEvent({
          'game': 'ckr',
          'id': widget.gameId,
          'kind': 'move',
          'n': n,
          'path': m.path,
          if (_finished) 'fin': true,
        }, type: DvGameNet.eventType);
      } catch (_) {
        _netMoves.remove(n);
        _rebuild(silent: true);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Не удалось отправить ход')),
          );
        }
      }
      return;
    }
    _commitLocal(m, mine: true);
    await _aiTurn();
  }

  void _commitLocal(CkrMove m, {required bool mine}) {
    final quiet = CkrLogic.isQuiet(_board, m) ? _quiet + 1 : 0;
    final b = CkrLogic.apply(_board, m);
    final turn = -_toMove;
    final wasFinished = _finished;
    final old = _count;
    setState(() {
      _board = b;
      _toMove = turn;
      _quiet = quiet;
      _count++;
      _last = m;
      _lastSender = mine ? _me : 'ai';
      _legal = CkrLogic.moves(b, turn);
      _selected = null;
      _hover = null;
    });
    if (mine) {
      unawaited(
        DvGameSound.play(m.captured.isNotEmpty ? DvSound.hit : DvSound.place),
      );
    }
    if (!wasFinished && _finished) {
      final w = _winnerSide;
      unawaited(
        Future<void>.delayed(
          const Duration(milliseconds: 500),
          () => DvGameSound.play(
            w == 0 ? DvSound.miss : (w == _mine ? DvSound.win : DvSound.lose),
          ),
        ),
      );
    } else if (!mine && _count > old) {
      unawaited(
        DvGameSound.play(m.captured.isNotEmpty ? DvSound.hit : DvSound.enemy),
      );
    }
  }

  Future<void> _aiTurn() async {
    if (_finished || _toMove == _mine) return;
    setState(() => _busy = true);
    await Future<void>.delayed(const Duration(milliseconds: 550));
    if (!mounted) return;
    final m = CkrLogic.aiMove(_board, _toMove, widget.level ?? 1, _rnd);
    setState(() => _busy = false);
    if (m == null) return;
    _commitLocal(m, mine: false);
  }

  Future<void> _again() async {
    if (_online) {
      try {
        final id = await DvGameNet.sendInvite(
          widget.room!,
          game: 'ckr',
          gameTitle: 'шашки',
          announce: false,
        );
        if (!mounted) return;
        await Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => CkrPage(room: widget.room, gameId: id, hostId: _me),
          ),
        );
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Не удалось отправить приглашение')),
          );
        }
      }
      return;
    }
    setState(() {
      _humanFirst = !_humanFirst;
      _board = CkrLogic.initial();
      _toMove = 1;
      _quiet = 0;
      _count = 0;
      _last = null;
      _lastSender = null;
      _legal = CkrLogic.moves(_board, 1);
      _selected = null;
      _hover = null;
    });
    await _aiTurn();
  }

  // ---------------- палец ----------------

  int _boardIndex(int display) => _flip ? 63 - display : display;

  int? _cellAt(Offset p, double side) {
    if (p.dx < 0 || p.dy < 0 || p.dx >= side || p.dy >= side) return null;
    final cs = side / 8;
    final col = (p.dx ~/ cs).clamp(0, 7);
    final row = (p.dy ~/ cs).clamp(0, 7);
    return _boardIndex(row * 8 + col);
  }

  void _down(PointerDownEvent e, double side) {
    if (_pointer != null || !_myTurn) return;
    final cell = _cellAt(e.localPosition, side);
    if (cell == null) return;
    _pointer = e.pointer;
    setState(() {
      _finger = e.localPosition;
      final sel = _selected;
      if (sel != null && _targets(sel).contains(cell)) {
        // Вторым касанием можно просто нажать на подсвеченную клетку
        _hover = cell;
      } else if (_legal.any((m) => m.from == cell)) {
        _selected = cell;
        _hover = cell;
      } else {
        _selected = null;
        _hover = null;
      }
    });
  }

  void _move(PointerMoveEvent e, double side) {
    if (e.pointer != _pointer) return;
    setState(() {
      _finger = e.localPosition;
      _hover = _cellAt(e.localPosition, side);
    });
  }

  void _up(PointerUpEvent e, double side) {
    if (e.pointer != _pointer) return;
    final cell = _cellAt(e.localPosition, side);
    final sel = _selected;
    _pointer = null;
    CkrMove? move;
    if (sel != null && cell != null && cell != sel) {
      move = _moveTo(sel, cell);
    }
    setState(() {
      _finger = null;
      _hover = null;
      // Палец поднят на самой шашке: выбор остаётся. Мимо клеток хода: выбор снимается.
      if (move != null || (cell != sel && sel != null)) _selected = null;
    });
    if (move != null) unawaited(_play(move));
  }

  void _cancel(PointerCancelEvent e) {
    if (e.pointer != _pointer) return;
    _pointer = null;
    setState(() {
      _finger = null;
      _hover = null;
    });
  }

  // ---------------- оформление ----------------

  String get _status {
    if (_loading) return 'Загрузка…';
    if (_surrenderBy != null) {
      return _surrenderBy == _me
          ? 'Вы сдались'
          : 'Соперник сдался. Вы победили! 🎉';
    }
    if (_legal.isEmpty) {
      return -_toMove == _mine ? 'Вы победили! 🎉' : 'Вы проиграли';
    }
    if (_quiet >= _drawPlies) return 'Ничья';
    if (_toMove == _mine) {
      final mustTake = _legal.first.captured.isNotEmpty;
      return mustTake ? 'Ваш ход. Бить обязательно' : 'Ваш ход';
    }
    return _online ? 'Ход соперника…' : 'Компьютер думает…';
  }

  int _count0(int side) =>
      _board.where((v) => v != 0 && CkrLogic.sideOf(v) == side).length;

  Widget _piece(int v, double size, {double opacity = 1}) {
    final white = v > 0;
    final king = v.abs() == 2;
    final base = white ? const Color(0xFFF1EEE8) : const Color(0xFF26262B);
    final edge = white ? const Color(0xFFB9B3A8) : const Color(0xFF8D8D96);
    return Opacity(
      opacity: opacity,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: base,
          border: Border.all(color: edge, width: max(1.5, size * 0.05)),
        ),
        alignment: Alignment.center,
        child: king
            ? Container(
                width: size * 0.5,
                height: size * 0.5,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: white
                        ? const Color(0xFFC59B2E)
                        : const Color(0xFFE2B84A),
                    width: max(2.0, size * 0.09),
                  ),
                ),
              )
            : Container(
                width: size * 0.56,
                height: size * 0.56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: edge.withAlpha(120), width: 1),
                ),
              ),
      ),
    );
  }

  Widget _boardView(ThemeData theme, double side) {
    final cs = side / 8;
    final dark = Color.alphaBlend(
      theme.bubbleColor.withAlpha(230),
      theme.colorScheme.surface,
    );
    final light = Color.alphaBlend(
      theme.bubbleColor.withAlpha(34),
      theme.colorScheme.surfaceContainerHighest,
    );
    final sel = _selected;
    final targets = sel == null ? const <int>{} : _targets(sel);
    final lastCells = <int>{...?_last?.path};
    final hover = _hover;
    final accent = theme.colorScheme.primary;
    final children = <Widget>[];
    for (var d = 0; d < 64; d++) {
      final i = _boardIndex(d);
      final r = d ~/ 8;
      final c = d % 8;
      final isDark = (r + c).isOdd;
      final v = _board[i];
      final isTarget = targets.contains(i);
      final dragging = sel == i && _finger != null;
      var fill = isDark ? dark : light;
      if (isDark && lastCells.contains(i)) {
        fill = Color.alphaBlend(Colors.white.withAlpha(46), fill);
      }
      children.add(
        Positioned(
          left: c * cs,
          top: r * cs,
          width: cs,
          height: cs,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: fill,
              border: sel == i
                  ? Border.all(color: accent, width: 3)
                  : (isTarget && hover == i
                        ? Border.all(color: Colors.white, width: 3)
                        : null),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (v != 0) _piece(v, cs * 0.78, opacity: dragging ? 0.35 : 1),
                if (isTarget)
                  Container(
                    width: cs * (hover == i ? 0.62 : 0.34),
                    height: cs * (hover == i ? 0.62 : 0.34),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withAlpha(hover == i ? 190 : 150),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    }
    final finger = _finger;
    final selV = sel == null ? 0 : _board[sel];
    if (finger != null && selV != 0) {
      children.add(
        Positioned(
          left: finger.dx - cs * 0.46,
          top: finger.dy - cs * 0.46,
          child: IgnorePointer(child: _piece(selV, cs * 0.92, opacity: 0.9)),
        ),
      );
    }
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (e) => _down(e, side),
      onPointerMove: (e) => _move(e, side),
      onPointerUp: (e) => _up(e, side),
      onPointerCancel: _cancel,
      child: SizedBox.square(
        dimension: side,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Stack(children: children),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = _online
        ? 'Шашки · ${widget.room!.dvDisplayname()}'
        : 'Шашки · ${_levelNames[(widget.level ?? 1).clamp(0, 2)]}';
    final mineLeft = _count0(_mine);
    final oppLeft = _count0(-_mine);
    return Scaffold(
      appBar: AppBar(title: Text(title), actions: const [DvSoundButton()]),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, box) {
            const pad = 12.0;
            final reserve = 120.0 + (_finished ? 64 : 0);
            final side = min(
              box.maxWidth - pad * 2,
              box.maxHeight - pad * 2 - reserve,
            ).clamp(160.0, 700.0);
            return SingleChildScrollView(
              physics: _finished ? null : const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.all(pad),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: box.maxHeight - pad * 2,
                  minWidth: box.maxWidth - pad * 2,
                ),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _status,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: _myTurn
                              ? theme.colorScheme.primary
                              : theme.colorScheme.onSurface,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      _boardView(theme, side),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: side,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Ваших шашек: $mineLeft',
                              style: theme.textTheme.labelLarge,
                            ),
                            Text(
                              'У соперника: $oppLeft',
                              style: theme.textTheme.labelLarge,
                            ),
                          ],
                        ),
                      ),
                      if (_finished) ...[
                        const SizedBox(height: 14),
                        FilledButton.icon(
                          onPressed: _again,
                          icon: const Icon(Icons.replay),
                          label: Text(
                            _online ? 'Сыграть ещё раз' : 'Новая партия',
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
