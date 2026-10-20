// SPDX-License-Identifier: AGPL-3.0-or-later

// DVChat: экран домино. Два режима:
//  - с компьютером, без интернета;
//  - с другом (room + gameId + hostId), ходы идут через личный чат.
// Раздача общая: фишки тасуются по номеру партии, поэтому у обоих телефонов одинаковый расклад.

import 'package:dvchat/pages/games/dv_local_stats.dart';
import 'dart:async';
import 'dart:math';

import 'package:dvchat/pages/games/domino_logic.dart';
import 'package:dvchat/pages/games/dv_game_net.dart';
import 'package:dvchat/pages/games/dv_game_sound.dart';
import 'package:dvchat/utils/dv_nicknames.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

class _Move {
  const _Move(this.cell, this.sender);

  final int cell;
  final String sender;
}

class DominoPage extends StatefulWidget {
  // level оставлен для совместимости со списком игр
  const DominoPage({
    this.level,
    this.room,
    this.gameId,
    this.hostId,
    super.key,
  });

  final int? level;

  /// Для игры с другом
  final Room? room;
  final String? gameId;
  final String? hostId;

  @override
  State<DominoPage> createState() => _DominoPageState();
}

class _DominoPageState extends State<DominoPage> with TickerProviderStateMixin {
  late String _seed;
  late DominoGame _game;
  final Map<int, _Move> _moves = {};
  int? _selTile;
  bool _humanFirst = true;
  bool _busy = false;

  // Сетевая игра
  StreamSubscription<Event>? _sub;
  String? _lastSender;
  bool _endSent = false;
  bool _loading = false;
  String? _surrenderBy;

  final ScrollController _scroll = ScrollController();

  late final AnimationController _placeC = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  )..value = 1;
  late final AnimationController _pulseC = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  );

  bool get _online => widget.room != null;
  String get _me => widget.room?.client.userID ?? '';
  int get _myPl => _online ? (widget.hostId == _me ? 0 : 1) : (_humanFirst ? 0 : 1);
  int get _aiPl => 1 - _myPl;
  String get _hostSender => _online ? (widget.hostId ?? '') : (_humanFirst ? 'me' : 'ai');
  bool get _finished => _surrenderBy != null || _game.winner >= 0;
  bool get _myTurn => !_loading && !_busy && !_finished && _game.pl == _myPl;

  @override
  void initState() {
    super.initState();
    DvLocalStats.open('domino', offline: widget.room == null);
    _pulseC.repeat();
    _seed = _online ? widget.gameId! : DateTime.now().microsecondsSinceEpoch.toString();
    _game = DominoGame(_seed);
    if (_online) {
      _loading = true;
      _sub = widget.room!.client.onTimelineEvent.stream.listen((e) {
        if (_ingest(e)) _replay();
      });
      DvGameNet.activeGameId = widget.gameId;
      unawaited(_load());
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => _maybeAi());
    }
  }

  @override
  void dispose() {
    if (DvGameNet.activeGameId == widget.gameId) {
      DvGameNet.activeGameId = null;
    }
    _sub?.cancel();
    _scroll.dispose();
    _placeC.dispose();
    _pulseC.dispose();
    DvLocalStats.close('domino');
    super.dispose();
  }

  // ---------------- сетевая часть ----------------

  bool _ingest(Event e) {
    if (e.type != DvGameNet.eventType || e.roomId != widget.room?.id) {
      return false;
    }
    final c = e.content;
    if (c['game'] != 'domino' || '${c['id']}' != widget.gameId) return false;
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
    final cell = c['cell'];
    if (n is! int || cell is! int || cell < 0 || cell > 101) return false;
    if (_moves.containsKey(n)) return false;
    _moves[n] = _Move(cell, e.senderId);
    return true;
  }

  Future<void> _load() async {
    try {
      final tl = await widget.room!.getTimeline(limit: 400);
      for (final e in tl.events) {
        _ingest(e);
      }
      tl.cancelSubscriptions();
    } catch (_) {
      // Не удалось прочитать историю: продолжим по новым событиям
    }
    _loading = false;
    _replay(silent: true);
  }

  /// Собирает партию заново из списка ходов, проверяя очерёдность и правила
  void _replay({bool silent = false}) {
    final old = _game;
    final g = DominoGame(_seed);
    var n = 0;
    String? last;
    while (_moves.containsKey(n)) {
      final m = _moves[n]!;
      final fromHost = m.sender == _hostSender;
      if (fromHost != (g.pl == 0)) break;
      if (!g.apply(m.cell)) break;
      last = m.sender;
      n++;
    }
    _lastSender = last;
    if (!mounted) return;
    final wasFinished = _finished;
    setState(() {
      _game = g;
      _selTile = null;
    });
    if (!silent) {
      if (g.chainTiles.length > old.chainTiles.length) {
        _placeC.forward(from: 0);
        _scrollToEnd(g.lastEnd);
      }
      _sound(old, g, wasFinished);
    }
    _maybeSendEnd();
    _maybeAi();
  }

  void _scrollToEnd(int end) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final max = _scroll.position.maxScrollExtent;
      final target = end == 0 ? 0.0 : max;
      _scroll.animateTo(
        target,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOutCubic,
      );
    });
  }

  void _sound(DominoGame old, DominoGame g, bool wasFinished) {
    if (!wasFinished && _finished) {
      final sound = _surrenderBy != null
          ? (_surrenderBy == _me ? DvSound.lose : DvSound.win)
          : (g.winner == 2
                ? DvSound.miss
                : (g.winner == _myPl ? DvSound.win : DvSound.lose));
      unawaited(DvGameSound.play(sound));
    } else if (g.moveCount > old.moveCount) {
      if (g.lastTile >= 0) {
        // фишку положил тот, кто ходил до смены хода
        final mover = g.winner >= 0 ? g.winner : 1 - g.pl;
        unawaited(DvGameSound.play(mover == _myPl ? DvSound.place : DvSound.enemy));
      } else {
        unawaited(DvGameSound.play(DvSound.miss));
      }
    }
  }

  void _maybeSendEnd() {
    if (!_online || _endSent || _game.winner < 0 || _surrenderBy != null) return;
    if (_lastSender != _me) return;
    _endSent = true;
    final w = _game.winner;
    final other = widget.hostId == _me ? (widget.room!.directChatMatrixID ?? '') : (widget.hostId ?? '');
    unawaited(
      DvGameNet.sendEnd(
        widget.room!,
        game: 'domino',
        id: widget.gameId!,
        winner: w == 2 ? '' : (w == _myPl ? _me : other),
      ).catchError((_) => null),
    );
  }

  // ---------------- игра с компьютером ----------------

  void _maybeAi() {
    if (_online || _busy || !mounted) return;
    if (_game.winner >= 0 || _game.pl != _aiPl) return;
    unawaited(_aiTurn());
  }

  Future<void> _aiTurn() async {
    setState(() => _busy = true);
    while (mounted && _game.winner < 0 && _game.pl == _aiPl) {
      await Future<void>.delayed(const Duration(milliseconds: 850));
      if (!mounted) return;
      final cell = DominoAi.choose(_game, _aiPl);
      _moves[_moves.length] = _Move(cell, 'ai');
      _replay();
    }
    if (!mounted) return;
    setState(() => _busy = false);
    _maybeAi();
  }

  // ---------------- ходы игрока ----------------

  Future<void> _doMove(int cell) async {
    final n = _game.moveCount;
    _moves[n] = _Move(cell, _online ? _me : 'me');
    _replay();
    if (_game.moveCount != n + 1) {
      _moves.remove(n);
      _replay(silent: true);
      return;
    }
    if (!_online) return;
    try {
      await DvGameNet.sendMove(
        widget.room!,
        game: 'domino',
        id: widget.gameId!,
        n: n,
        cell: cell,
        fin: _game.winner >= 0,
      );
    } catch (_) {
      _moves.remove(n);
      _replay(silent: true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось отправить ход')),
        );
      }
    }
  }

  void _onTapTile(int t) {
    if (!_myTurn) return;
    final opts = _game.options(_myPl).where((o) => o.tile == t).toList();
    if (opts.isEmpty) {
      setState(() => _selTile = null);
      return;
    }
    if (opts.length == 1) {
      unawaited(_doMove(opts.first.cell));
      return;
    }
    setState(() => _selTile = _selTile == t ? null : t);
  }

  void _onTapEnd(int end) {
    final t = _selTile;
    if (t == null || !_myTurn) return;
    unawaited(_doMove(t * 2 + end));
  }

  Future<void> _again() async {
    if (_online) {
      try {
        final id = await DvGameNet.sendInvite(
          widget.room!,
          game: 'domino',
          gameTitle: 'домино',
          announce: false,
        );
        if (!mounted) return;
        await Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => DominoPage(room: widget.room, gameId: id, hostId: _me),
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
      _seed = DateTime.now().microsecondsSinceEpoch.toString();
      _moves.clear();
      _game = DominoGame(_seed);
      _selTile = null;
    });
    _placeC.value = 1;
    _maybeAi();
  }

  // ---------------- оформление ----------------

  String get _status {
    if (_loading) return 'Загрузка…';
    if (_surrenderBy != null) {
      return _surrenderBy == _me
          ? 'Вы сдались'
          : 'Соперник сдался. Вы победили! 🎉';
    }
    final g = _game;
    if (g.winner >= 0) {
      if (g.winner == 2) return 'Ничья';
      final mine = g.winner == _myPl;
      final pts = g.handPips(1 - g.winner);
      final fish = g.blocked ? ' (рыба)' : '';
      return mine
          ? 'Вы победили! 🎉 +$pts$fish'
          : 'Вы проиграли$fish';
    }
    if (g.pl != _myPl) return _online ? 'Ход соперника…' : 'Компьютер думает…';
    if (g.mustDraw) return 'Нет подходящей фишки: берите из базара';
    if (g.mustPass) return 'Ходить нечем, пропустите ход';
    return 'Ваш ход';
  }

  Widget _chip(ThemeData theme, String name, int pl, bool active) {
    final g = _game;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: active ? const Color(0xFF2C6B45).withValues(alpha: 0.2) : null,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: active ? const Color(0xFF2C6B45) : theme.colorScheme.outlineVariant,
          width: active ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
          Text(
            'фишек ${g.hands[pl].length} · очков ${g.handPips(pl)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final g = _game;
    final me = _myPl;
    final title = _online
        ? 'Домино · ${widget.room!.dvDisplayname()}'
        : 'Домино · с компьютером';
    final playing = !_loading && !_finished;
    final oppName = _online ? widget.room!.dvDisplayname() : 'Компьютер';
    final opts = _myTurn ? g.options(me) : const <DOpt>[];
    final playable = <int>{for (final o in opts) o.tile};
    final hand = g.hands[me];
    final selOpts = _selTile == null
        ? const <DOpt>[]
        : opts.where((o) => o.tile == _selTile).toList();
    return Scaffold(
      appBar: AppBar(title: Text(title), actions: const [DvSoundButton()]),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(10),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _chip(theme, 'Вы', me, playing && g.pl == me),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _chip(theme, oppName, 1 - me, playing && g.pl == 1 - me),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _status,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  // фишки соперника рубашкой вверх и базар
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Wrap(
                          spacing: 4,
                          runSpacing: 4,
                          children: [
                            for (var i = 0; i < g.hands[1 - me].length; i++)
                              CustomPaint(
                                size: const Size(20, 40),
                                painter: _BackPainter(),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Column(
                        children: [
                          CustomPaint(size: const Size(28, 56), painter: _BackPainter(stack: true)),
                          Text('базар ${g.stock.length}', style: theme.textTheme.bodySmall),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // стол с цепочкой
                  _table(selOpts),
                  const SizedBox(height: 10),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 6,
                    runSpacing: 8,
                    children: [
                      for (final t in hand)
                        GestureDetector(
                          onTap: () => _onTapTile(t),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 160),
                            transform: Matrix4.translationValues(
                              0,
                              (_myTurn && playable.contains(t)) ? -6 : 0,
                              0,
                            ),
                            child: CustomPaint(
                              size: const Size(34, 68),
                              painter: _HandTilePainter(
                                t,
                                dim: _myTurn && !playable.contains(t),
                                glow: _selTile == t,
                                hint: _myTurn && playable.contains(t),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_myTurn && g.mustDraw)
                    FilledButton.tonalIcon(
                      onPressed: () => _doMove(Domino.drawCell),
                      icon: const Icon(Icons.add_card),
                      label: Text('Взять из базара (${g.stock.length})'),
                    ),
                  if (_myTurn && g.mustPass)
                    FilledButton.tonalIcon(
                      onPressed: () => _doMove(Domino.passCell),
                      icon: const Icon(Icons.skip_next),
                      label: const Text('Пропустить ход'),
                    ),
                  if (_finished)
                    FilledButton.icon(
                      onPressed: _again,
                      icon: const Icon(Icons.replay),
                      label: Text(_online ? 'Сыграть ещё раз' : 'Новая партия'),
                    ),
                  const SizedBox(height: 8),
                  Text(
                    'Нажмите подходящую фишку. Если она подходит с обеих сторон, нажмите на нужный край цепочки.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _table(List<DOpt> selOpts) {
    final g = _game;
    const s = 30.0;
    return Container(
      height: s * 5,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF6B4423), Color(0xFF3A200F)],
        ),
        boxShadow: const [
          BoxShadow(color: Color(0x44000000), blurRadius: 8, offset: Offset(0, 3)),
        ],
      ),
      padding: const EdgeInsets.all(6),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(13),
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: RadialGradient(
              colors: [Color(0xFF2F7A4D), Color(0xFF1B4D31)],
              radius: 0.9,
            ),
          ),
          child: LayoutBuilder(
            builder: (context, c) {
              final lay = _ChainLayout(g, s, c.maxWidth);
              final ends = <int>{for (final o in selOpts) o.end};
              return SingleChildScrollView(
                controller: _scroll,
                scrollDirection: Axis.horizontal,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: (d) {
                    final p = d.localPosition;
                    if (ends.contains(0) && lay.leftSlot.inflate(10).contains(p)) {
                      _onTapEnd(0);
                    } else if (ends.contains(1) && lay.rightSlot.inflate(10).contains(p)) {
                      _onTapEnd(1);
                    }
                  },
                  child: AnimatedBuilder(
                    animation: Listenable.merge([_placeC, _pulseC]),
                    builder: (context, _) => CustomPaint(
                      size: Size(lay.width, c.maxHeight),
                      painter: _ChainPainter(
                        lay: lay,
                        game: g,
                        s: s,
                        ends: ends,
                        placeT: Curves.easeOutBack.transform(_placeC.value.clamp(0.0, 1.0)),
                        pulse: _pulseC.value,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

// ---------------- рисование фишек ----------------

const Map<int, List<int>> _pipCells = {
  0: [],
  1: [4],
  2: [0, 8],
  3: [0, 4, 8],
  4: [0, 2, 6, 8],
  5: [0, 2, 4, 6, 8],
  6: [0, 2, 3, 5, 6, 8],
};

/// Рисует фишку: центр c, меньшая сторона s. vertical: стоит вертикально (a сверху, b снизу)
void _paintTile(
  Canvas cv,
  Offset c,
  double s,
  int a,
  int b, {
  required bool vertical,
  double alpha = 1,
  double scale = 1,
}) {
  cv.save();
  cv.translate(c.dx, c.dy);
  cv.scale(scale);
  final w = vertical ? s : 2 * s;
  final h = vertical ? 2 * s : s;
  final rr = RRect.fromRectAndRadius(
    Rect.fromCenter(center: Offset.zero, width: w, height: h),
    Radius.circular(s * 0.16),
  );
  cv.drawRRect(
    rr.shift(Offset(s * 0.05, s * 0.09)),
    Paint()..color = Colors.black.withValues(alpha: 0.35 * alpha),
  );
  cv.drawRRect(
    rr,
    Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          const Color(0xFFFFFDF2).withValues(alpha: alpha),
          const Color(0xFFE6D9B2).withValues(alpha: alpha),
        ],
      ).createShader(rr.outerRect),
  );
  cv.drawRRect(
    rr,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = max(0.8, s * 0.035)
      ..color = const Color(0xFF8E7B4E).withValues(alpha: alpha),
  );
  // разделитель и латунная кнопка посередине
  final p = Paint()
    ..color = const Color(0xFF6B5A33).withValues(alpha: alpha)
    ..strokeWidth = max(1.0, s * 0.045)
    ..strokeCap = StrokeCap.round;
  if (vertical) {
    cv.drawLine(Offset(-w * 0.4, 0), Offset(w * 0.4, 0), p);
  } else {
    cv.drawLine(Offset(0, -h * 0.4), Offset(0, h * 0.4), p);
  }
  cv.drawCircle(Offset.zero, s * 0.06, Paint()..color = const Color(0xFFC9A24A).withValues(alpha: alpha));
  // очки в двух половинах
  final pip = Paint()..color = const Color(0xFF1B1210).withValues(alpha: alpha);
  void half(int v, Offset center) {
    for (final cell in _pipCells[v] ?? const <int>[]) {
      final dx = (cell % 3 - 1) * s * 0.26;
      final dy = (cell ~/ 3 - 1) * s * 0.26;
      cv.drawCircle(center + Offset(dx, dy), s * 0.085, pip);
    }
  }

  if (vertical) {
    half(a, Offset(0, -s / 2));
    half(b, Offset(0, s / 2));
  } else {
    half(a, Offset(-s / 2, 0));
    half(b, Offset(s / 2, 0));
  }
  cv.restore();
}

class _HandTilePainter extends CustomPainter {
  _HandTilePainter(this.t, {required this.dim, required this.glow, required this.hint});

  final int t;
  final bool dim;
  final bool glow;
  final bool hint;

  @override
  void paint(Canvas canvas, Size size) {
    final tile = Domino.all[t];
    final c = Offset(size.width / 2, size.height / 2);
    final s = size.width;
    if (glow || hint) {
      final rr = RRect.fromRectAndRadius(
        Rect.fromCenter(center: c, width: s + 4, height: 2 * s + 4),
        Radius.circular(s * 0.2),
      );
      canvas.drawRRect(
        rr,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = glow ? 3 : 1.6
          ..color = const Color(0xFFFFC83D).withValues(alpha: glow ? 1 : 0.7),
      );
    }
    _paintTile(canvas, c, s - 2, tile.a, tile.b, vertical: true, alpha: dim ? 0.5 : 1);
  }

  @override
  bool shouldRepaint(_HandTilePainter old) =>
      old.t != t || old.dim != dim || old.glow != glow || old.hint != hint;
}

class _BackPainter extends CustomPainter {
  _BackPainter({this.stack = false});

  final bool stack;

  @override
  void paint(Canvas canvas, Size size) {
    void back(Offset shift) {
      final rr = RRect.fromRectAndRadius(
        (Offset.zero & size).shift(shift).deflate(1),
        Radius.circular(size.width * 0.18),
      );
      canvas.drawRRect(
        rr.shift(const Offset(1, 2)),
        Paint()..color = Colors.black.withValues(alpha: 0.3),
      );
      canvas.drawRRect(
        rr,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF7A4B26), Color(0xFF3A200F)],
          ).createShader(rr.outerRect),
      );
      canvas.drawRRect(
        rr,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8
          ..color = const Color(0xFF241307),
      );
      canvas.drawCircle(rr.center, size.width * 0.1, Paint()..color = const Color(0xFFD0A74C));
    }

    if (stack) {
      back(const Offset(-2, -2));
      back(const Offset(2, 2));
    } else {
      back(Offset.zero);
    }
  }

  @override
  bool shouldRepaint(_BackPainter old) => old.stack != stack;
}

/// Положение фишек цепочки на столе
class _ChainLayout {
  _ChainLayout(DominoGame g, this.s, double viewport) {
    var x = 0.0;
    final spans = <(double, double, bool)>[];
    for (final t in g.chain) {
      final dbl = t.$1 == t.$2;
      final w = dbl ? s : 2 * s;
      spans.add((x, w, dbl));
      x += w;
    }
    final chainW = x;
    width = max(viewport, chainW + 8 * s);
    final startX = (width - chainW) / 2;
    final cy = 2.5 * s;
    for (var i = 0; i < spans.length; i++) {
      final sp = spans[i];
      centers.add(Offset(startX + sp.$1 + sp.$2 / 2, cy));
      vertical.add(sp.$3);
    }
    leftSlot = Rect.fromCenter(
      center: Offset(startX - 1.4 * s, cy),
      width: 2 * s,
      height: s,
    );
    rightSlot = Rect.fromCenter(
      center: Offset(startX + chainW + 1.4 * s, cy),
      width: 2 * s,
      height: s,
    );
  }

  final double s;
  late final double width;
  final List<Offset> centers = [];
  final List<bool> vertical = [];
  late final Rect leftSlot;
  late final Rect rightSlot;
}

class _ChainPainter extends CustomPainter {
  _ChainPainter({
    required this.lay,
    required this.game,
    required this.s,
    required this.ends,
    required this.placeT,
    required this.pulse,
  });

  final _ChainLayout lay;
  final DominoGame game;
  final double s;
  final Set<int> ends;
  final double placeT;
  final double pulse;

  void _slot(Canvas canvas, Rect r) {
    final a = 0.5 + 0.5 * sin(pulse * 2 * pi);
    final rr = RRect.fromRectAndRadius(r, Radius.circular(s * 0.2));
    canvas.drawRRect(
      rr,
      Paint()..color = const Color(0xFFFFC83D).withValues(alpha: 0.12 + 0.12 * a),
    );
    canvas.drawRRect(
      rr,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = const Color(0xFFFFC83D).withValues(alpha: 0.6 + 0.4 * a),
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (game.chain.isEmpty) {
      // стол пуст: подсказка по центру
      final tp = TextPainter(
        text: const TextSpan(
          text: 'Первая фишка ложится сюда',
          style: TextStyle(color: Color(0x88FFFFFF), fontSize: 14),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset((lay.width - tp.width) / 2, size.height / 2 - tp.height / 2));
      return;
    }
    // индекс, который сейчас «влетает»
    var animIdx = -1;
    if (game.lastTile >= 0) {
      animIdx = game.chainTiles.indexOf(game.lastTile);
    }
    for (var i = 0; i < game.chain.length; i++) {
      final t = game.chain[i];
      final anim = i == animIdx && placeT < 1;
      _paintTile(
        canvas,
        lay.centers[i] + (anim ? Offset(0, -(1 - placeT) * s * 0.8) : Offset.zero),
        s,
        t.$1,
        t.$2,
        vertical: lay.vertical[i],
        alpha: anim ? placeT.clamp(0.0, 1.0) : 1,
        scale: anim ? 0.6 + 0.4 * placeT : 1,
      );
    }
    if (ends.contains(0)) _slot(canvas, lay.leftSlot);
    if (ends.contains(1)) _slot(canvas, lay.rightSlot);
  }

  @override
  bool shouldRepaint(_ChainPainter old) => true;
}
