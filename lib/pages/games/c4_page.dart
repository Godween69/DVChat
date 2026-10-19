// SPDX-License-Identifier: AGPL-3.0-or-later

// DVChat: экран «Четыре в ряд». Два режима:
//  - с компьютером (без интернета, всегда в полную силу);
//  - с другом (room + gameId + hostId), ходы идут через личный чат.
// Касаешься нужного столбца, фишка падает вниз и подпрыгивает. Фишки лежат за синей доской
// и видны через отверстия, выигрышная четвёрка подсвечивается кольцами.

import 'dart:async';
import 'dart:math';

import 'package:dvchat/pages/games/c4_logic.dart';
import 'package:dvchat/pages/games/dv_game_net.dart';
import 'package:dvchat/pages/games/dv_game_sound.dart';
import 'package:dvchat/utils/dv_nicknames.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

class _Move {
  const _Move(this.col, this.sender);

  final int col;
  final String sender;
}

class C4Page extends StatefulWidget {
  const C4Page({this.level, this.room, this.gameId, this.hostId, super.key});

  /// Не используется: уровней сложности нет (параметр оставлен для общего вида игр)
  final int? level;

  /// Для игры с другом
  final Room? room;
  final String? gameId;
  final String? hostId;

  @override
  State<C4Page> createState() => _C4PageState();
}

class _C4PageState extends State<C4Page> {
  List<int> _board = List.filled(C4Logic.cols * C4Logic.rows, 0);
  int? _fresh;
  bool _humanFirst = true;
  bool _busy = false;
  final Random _rnd = Random();

  // Сетевая игра
  final Map<int, _Move> _moves = {};
  StreamSubscription<Event>? _sub;
  String? _lastSender;
  bool _endSent = false;
  bool _loading = false;
  String? _surrenderBy;

  bool get _online => widget.room != null;
  String get _me => widget.room?.client.userID ?? '';
  int get _mine =>
      _online ? (widget.hostId == _me ? 1 : 2) : (_humanFirst ? 1 : 2);

  @override
  void initState() {
    super.initState();
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

  // ---------------- общее ----------------

  bool get _finished =>
      _surrenderBy != null ||
      C4Logic.winner(_board) != null ||
      C4Logic.isFull(_board);

  /// Меняет поле; если добавилась ровно одна фишка, она «падает» с анимацией
  void _applyBoard(List<int> b) {
    int? fresh;
    if (C4Logic.count(b) == C4Logic.count(_board) + 1) {
      for (var i = 0; i < b.length; i++) {
        if (_board[i] == 0 && b[i] != 0) fresh = i;
      }
    }
    _fresh = fresh;
    _board = b;
  }

  void _soundFor(int oldCount, bool wasFinished) {
    final count = C4Logic.count(_board);
    if (!wasFinished && _finished) {
      final w = C4Logic.winner(_board);
      final sound = _surrenderBy != null
          ? (_surrenderBy == _me ? DvSound.lose : DvSound.win)
          : (w == null
                ? DvSound.miss
                : (w == _mine ? DvSound.win : DvSound.lose));
      unawaited(DvGameSound.play(sound));
    } else if (count > oldCount) {
      final last = count.isOdd ? 1 : 2;
      unawaited(
        DvGameSound.play(last == _mine ? DvSound.place : DvSound.enemy),
      );
    }
  }

  // ---------------- сетевая часть ----------------

  bool _ingest(Event e) {
    if (e.type != DvGameNet.eventType || e.roomId != widget.room?.id) {
      return false;
    }
    final c = e.content;
    if (c['game'] != 'c4' || '${c['id']}' != widget.gameId) return false;
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
    final col = c['cell'];
    if (n is! int || col is! int || col < 0 || col >= C4Logic.cols) {
      return false;
    }
    if (_moves.containsKey(n)) return false;
    _moves[n] = _Move(col, e.senderId);
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

  /// Собирает поле из полученных ходов, проверяя очерёдность
  void _rebuild({bool silent = false}) {
    final b = List<int>.filled(C4Logic.cols * C4Logic.rows, 0);
    var n = 0;
    String? last;
    while (_moves.containsKey(n)) {
      final m = _moves[n]!;
      final hostMove = n.isEven;
      final fromHost = m.sender == widget.hostId;
      if (hostMove != fromHost) break;
      final r = C4Logic.dropRow(b, m.col);
      if (r < 0) break;
      b[r * C4Logic.cols + m.col] = hostMove ? 1 : 2;
      last = m.sender;
      n++;
      if (C4Logic.winner(b) != null) break;
    }
    _lastSender = last;
    if (!mounted) return;
    final oldCount = C4Logic.count(_board);
    final wasFinished = _finished;
    setState(() => _applyBoard(b));
    if (!silent) _soundFor(oldCount, wasFinished);
    _maybeSendEnd();
  }

  void _maybeSendEnd() {
    if (!_online || _endSent || !_finished || _surrenderBy != null) return;
    if (_lastSender != _me) return;
    _endSent = true;
    final won = C4Logic.winner(_board) != null;
    unawaited(
      DvGameNet.sendEnd(
        widget.room!,
        game: 'c4',
        id: widget.gameId!,
        winner: won ? _me : '',
      ).catchError((_) => null),
    );
  }

  // ---------------- ходы ----------------

  Future<void> _tap(int col) async {
    if (_loading || _busy || _finished) return;
    final turn = C4Logic.turnOf(_board);
    if (turn != _mine) return;
    final row = C4Logic.dropRow(_board, col);
    if (row < 0) return;
    if (_online) {
      final n = C4Logic.count(_board);
      _moves[n] = _Move(col, _me);
      _rebuild();
      try {
        await DvGameNet.sendMove(
          widget.room!,
          game: 'c4',
          id: widget.gameId!,
          n: n,
          cell: col,
          fin: _finished,
        );
      } catch (_) {
        _moves.remove(n);
        _rebuild(silent: true);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Не удалось отправить ход')),
          );
        }
      }
      return;
    }
    // С компьютером
    final old = C4Logic.count(_board);
    setState(() {
      _applyBoard(List.of(_board)..[row * C4Logic.cols + col] = turn);
    });
    _soundFor(old, false);
    await _aiTurn();
  }

  Future<void> _aiTurn() async {
    if (_finished) return;
    final ai = _humanFirst ? 2 : 1;
    if (C4Logic.turnOf(_board) != ai) return;
    setState(() => _busy = true);
    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;
    final col = C4Logic.aiMove(_board, ai, _rnd);
    final row = C4Logic.dropRow(_board, col);
    final old = C4Logic.count(_board);
    setState(() {
      _applyBoard(List.of(_board)..[row * C4Logic.cols + col] = ai);
      _busy = false;
    });
    _soundFor(old, false);
  }

  Future<void> _again() async {
    if (_online) {
      try {
        final id = await DvGameNet.sendInvite(
          widget.room!,
          game: 'c4',
          gameTitle: 'четыре в ряд',
          announce: false,
        );
        if (!mounted) return;
        await Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => C4Page(room: widget.room, gameId: id, hostId: _me),
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
      _fresh = null;
      _board = List.filled(C4Logic.cols * C4Logic.rows, 0);
    });
    if (!_humanFirst) await _aiTurn();
  }

  String get _status {
    if (_loading) return 'Загрузка…';
    if (_surrenderBy != null) {
      return _surrenderBy == _me
          ? 'Вы сдались'
          : 'Соперник сдался. Вы победили! 🎉';
    }
    final w = C4Logic.winner(_board);
    if (w != null) return w == _mine ? 'Вы победили! 🎉' : 'Вы проиграли';
    if (C4Logic.isFull(_board)) return 'Ничья';
    if (C4Logic.turnOf(_board) == _mine) return 'Ваш ход';
    return _online ? 'Ход соперника…' : 'Компьютер думает…';
  }

  Widget _chip(ThemeData theme, String name, int player, bool active) {
    final color = player == 1
        ? const Color(0xFFE5383B)
        : const Color(0xFFF2B705);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: active ? color.withValues(alpha: 0.16) : null,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: active ? color : theme.colorScheme.outlineVariant,
          width: active ? 2 : 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CustomPaint(size: const Size(22, 22), painter: _DiscPainter(player)),
          const SizedBox(width: 8),
          Flexible(
            child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = _online
        ? 'Четыре в ряд · ${widget.room!.dvDisplayname()}'
        : 'Четыре в ряд';
    final mine = _mine;
    final other = 3 - mine;
    final turn = C4Logic.turnOf(_board);
    final playing = !_loading && !_finished;
    final oppName = _online ? widget.room!.dvDisplayname() : 'Компьютер';
    return Scaffold(
      appBar: AppBar(title: Text(title), actions: const [DvSoundButton()]),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Row(
                    children: [
                      Expanded(
                        child: _chip(
                          theme,
                          'Вы',
                          mine,
                          playing && turn == mine,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _chip(
                          theme,
                          oppName,
                          other,
                          playing && turn == other,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                Text(_status, style: theme.textTheme.titleLarge),
                const SizedBox(height: 18),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: _C4Board(
                    board: _board,
                    fresh: _fresh,
                    winLine: C4Logic.winLine(_board),
                    onColumn: _tap,
                  ),
                ),
                const SizedBox(height: 24),
                if (_finished)
                  FilledButton.icon(
                    onPressed: _again,
                    icon: const Icon(Icons.replay),
                    label: Text(_online ? 'Сыграть ещё раз' : 'Новая партия'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _C4Board extends StatelessWidget {
  const _C4Board({
    required this.board,
    required this.fresh,
    required this.winLine,
    required this.onColumn,
  });

  final List<int> board;
  final int? fresh;
  final List<int>? winLine;
  final void Function(int) onColumn;

  @override
  Widget build(BuildContext context) {
    const pad = 9.0;
    return Container(
      padding: const EdgeInsets.all(pad),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1C3F9E), Color(0xFF0E2260)],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(90),
            blurRadius: 16,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, c) {
          final cs = c.maxWidth / C4Logic.cols;
          final h = cs * C4Logic.rows;
          final line = winLine;
          return ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (d) => onColumn(
                (d.localPosition.dx / cs).floor().clamp(0, C4Logic.cols - 1),
              ),
              child: SizedBox(
                width: c.maxWidth,
                height: h,
                child: Stack(
                  children: [
                    // Тёмная подложка: через пустые отверстия виден фон
                    Positioned.fill(
                      child: ColoredBox(color: const Color(0xFF08142F)),
                    ),
                    // Фишки лежат за доской
                    for (var i = 0; i < board.length; i++)
                      if (board[i] != 0)
                        Positioned(
                          left: (i % C4Logic.cols) * cs,
                          top: (i ~/ C4Logic.cols) * cs,
                          width: cs,
                          height: cs,
                          child: _FallingDisc(
                            key: ValueKey('$i-${board[i]}'),
                            player: board[i],
                            row: i ~/ C4Logic.cols,
                            cellSize: cs,
                            animate: i == fresh,
                          ),
                        ),
                    // Доска с отверстиями поверх фишек
                    Positioned.fill(
                      child: IgnorePointer(
                        child: CustomPaint(painter: _FrontPainter(cs)),
                      ),
                    ),
                    if (line != null)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: TweenAnimationBuilder<double>(
                            key: ValueKey(line.join(',')),
                            tween: Tween(begin: 0, end: 1),
                            duration: const Duration(milliseconds: 700),
                            curve: Curves.easeOut,
                            builder: (context, t, child) => CustomPaint(
                              painter: _WinRingPainter(line, t, cs),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Фишка: падает сверху до своей клетки и подпрыгивает
class _FallingDisc extends StatelessWidget {
  const _FallingDisc({
    required this.player,
    required this.row,
    required this.cellSize,
    required this.animate,
    super.key,
  });

  final int player;
  final int row;
  final double cellSize;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: animate ? 0 : 1, end: 1),
      duration: animate
          ? Duration(milliseconds: 380 + row * 70)
          : Duration.zero,
      curve: Curves.bounceOut,
      builder: (context, t, child) => Transform.translate(
        offset: Offset(0, -(row + 1) * cellSize * (1 - t)),
        child: child,
      ),
      child: CustomPaint(painter: _DiscPainter(player)),
    );
  }
}

/// Глянцевая фишка: красная у первого игрока, жёлтая у второго
class _DiscPainter extends CustomPainter {
  _DiscPainter(this.player);

  final int player;

  @override
  void paint(Canvas canvas, Size s) {
    final c = Offset(s.width / 2, s.height / 2);
    final r = s.shortestSide * 0.43;
    final colors = player == 1
        ? const [Color(0xFFFF7A7A), Color(0xFFB80F1B)]
        : const [Color(0xFFFFEA7A), Color(0xFFDB9400)];
    final rect = Rect.fromCircle(center: c, radius: r);
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.3, -0.35),
          radius: 0.95,
          colors: colors,
        ).createShader(rect),
    );
    // Выточенное кольцо
    canvas.drawCircle(
      c,
      r * 0.68,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.14
        ..color = Colors.black.withAlpha(36),
    );
    canvas.drawCircle(
      c,
      r * 0.6,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.05
        ..color = Colors.white.withAlpha(46),
    );
    // Блик
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(c.dx - r * 0.3, c.dy - r * 0.45),
        width: r * 0.8,
        height: r * 0.36,
      ),
      Paint()..color = Colors.white.withAlpha(110),
    );
  }

  @override
  bool shouldRepaint(_DiscPainter old) => old.player != player;
}

/// Синяя доска с круглыми отверстиями
class _FrontPainter extends CustomPainter {
  _FrontPainter(this.cs);

  final double cs;

  @override
  void paint(Canvas canvas, Size s) {
    final holeR = cs * 0.42;
    final path = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & s);
    for (var r = 0; r < C4Logic.rows; r++) {
      for (var c = 0; c < C4Logic.cols; c++) {
        path.addOval(
          Rect.fromCircle(
            center: Offset((c + 0.5) * cs, (r + 0.5) * cs),
            radius: holeR,
          ),
        );
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF3A7BFF), Color(0xFF1B4BBE)],
        ).createShader(Offset.zero & s),
    );
    // Края отверстий: тёмная кромка и светлый ободок снизу
    final dark = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = cs * 0.05
      ..color = const Color(0xFF0B2A78).withAlpha(200);
    final light = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = cs * 0.025
      ..color = Colors.white.withAlpha(60);
    for (var r = 0; r < C4Logic.rows; r++) {
      for (var c = 0; c < C4Logic.cols; c++) {
        final center = Offset((c + 0.5) * cs, (r + 0.5) * cs);
        canvas.drawCircle(center, holeR, dark);
        canvas.drawCircle(center, holeR + cs * 0.05, light);
      }
    }
  }

  @override
  bool shouldRepaint(_FrontPainter old) => old.cs != cs;
}

/// Белые кольца вокруг выигрышной четвёрки
class _WinRingPainter extends CustomPainter {
  _WinRingPainter(this.line, this.t, this.cs);

  final List<int> line;
  final double t;
  final double cs;

  @override
  void paint(Canvas canvas, Size s) {
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = cs * 0.08
      ..color = Colors.white.withAlpha((235 * t).round());
    for (final i in line) {
      final center = Offset(
        (i % C4Logic.cols + 0.5) * cs,
        (i ~/ C4Logic.cols + 0.5) * cs,
      );
      canvas.drawCircle(center, cs * (0.5 - 0.06 * t), p);
    }
  }

  @override
  bool shouldRepaint(_WinRingPainter old) => old.t != t || old.line != line;
}
