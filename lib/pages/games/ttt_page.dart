// SPDX-License-Identifier: AGPL-3.0-or-later

// DVChat: экран крестиков-ноликов. Два режима:
//  - с компьютером (level 0..2), без интернета;
//  - с другом (room + gameId + hostId), ходы идут через личный чат.
// Крестики и нолики рисуются анимацией, победная линия перечёркивает выигрышные клетки.

import 'dart:async';
import 'dart:math';

import 'package:dvchat/pages/games/dv_game_net.dart';
import 'package:dvchat/pages/games/dv_game_sound.dart';
import 'package:dvchat/pages/games/ttt_logic.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

class _Move {
  const _Move(this.cell, this.sender);

  final int cell;
  final String sender;
}

class TttPage extends StatefulWidget {
  const TttPage({this.level, this.room, this.gameId, this.hostId, super.key});

  /// Для игры с компьютером: 0 лёгкий, 1 средний, 2 непобедимый
  final int? level;

  /// Для игры с другом
  final Room? room;
  final String? gameId;
  final String? hostId;

  @override
  State<TttPage> createState() => _TttPageState();
}

class _TttPageState extends State<TttPage> {
  static const List<String> _levelNames = ['Лёгкий', 'Средний', 'Непобедимый'];

  List<String> _board = List.filled(9, '');
  bool _humanFirst = true;
  bool _busy = false;

  // Сетевая игра
  final Map<int, _Move> _moves = {};
  StreamSubscription<Event>? _sub;
  String? _lastSender;
  bool _endSent = false;
  bool _loading = false;
  String? _surrenderBy;

  bool get _online => widget.room != null;
  String get _me => widget.room?.client.userID ?? '';
  String get _myLetter => widget.hostId == _me ? 'X' : 'O';
  String get _humanLetter => _humanFirst ? 'X' : 'O';
  String get _mine => _online ? _myLetter : _humanLetter;

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

  // ---------------- звук ----------------

  int _count(List<String> b) => b.where((c) => c != '').length;

  /// Звук после изменения поля: свой ход, ход соперника или конец партии
  void _soundFor(int oldCount, bool wasFinished) {
    final count = _count(_board);
    if (!wasFinished && _finished) {
      final w = TttLogic.winner(_board);
      final sound = _surrenderBy != null
          ? (_surrenderBy == _me ? DvSound.lose : DvSound.win)
          : (w == null
                ? DvSound.miss
                : (w == _mine ? DvSound.win : DvSound.lose));
      unawaited(DvGameSound.play(sound));
    } else if (count > oldCount) {
      final lastLetter = count.isOdd ? 'X' : 'O';
      unawaited(
        DvGameSound.play(lastLetter == _mine ? DvSound.place : DvSound.enemy),
      );
    }
  }

  // ---------------- сетевая часть ----------------

  bool _ingest(Event e) {
    if (e.type != DvGameNet.eventType || e.roomId != widget.room?.id) {
      return false;
    }
    final c = e.content;
    if (c['game'] != 'ttt' || '${c['id']}' != widget.gameId) return false;
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
    if (n is! int || cell is! int || cell < 0 || cell > 8) return false;
    if (_moves.containsKey(n)) return false;
    _moves[n] = _Move(cell, e.senderId);
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
    final b = List<String>.filled(9, '');
    var n = 0;
    String? last;
    while (_moves.containsKey(n)) {
      final m = _moves[n]!;
      final hostMove = n.isEven;
      final fromHost = m.sender == widget.hostId;
      if (hostMove != fromHost || b[m.cell] != '') break;
      b[m.cell] = hostMove ? 'X' : 'O';
      last = m.sender;
      n++;
      if (TttLogic.winner(b) != null) break;
    }
    _lastSender = last;
    if (!mounted) return;
    final oldCount = _count(_board);
    final wasFinished = _finished;
    setState(() => _board = b);
    if (!silent) _soundFor(oldCount, wasFinished);
    _maybeSendEnd();
  }

  void _maybeSendEnd() {
    if (!_online || _endSent || !_finished || _surrenderBy != null) return;
    if (_lastSender != _me) return;
    _endSent = true;
    final won = TttLogic.winner(_board) != null;
    unawaited(
      DvGameNet.sendEnd(
        widget.room!,
        game: 'ttt',
        id: widget.gameId!,
        winner: won ? _me : '',
      ).catchError((_) => null),
    );
  }

  // ---------------- общая часть ----------------

  bool get _finished =>
      _surrenderBy != null ||
      TttLogic.winner(_board) != null ||
      TttLogic.isFull(_board);

  Future<void> _tap(int i) async {
    if (_loading || _busy || _finished || _board[i] != '') return;
    final turn = TttLogic.turnOf(_board);
    if (_online) {
      if (turn != _myLetter) return;
      final n = _count(_board);
      _moves[n] = _Move(i, _me);
      _rebuild();
      try {
        await DvGameNet.sendMove(
          widget.room!,
          game: 'ttt',
          id: widget.gameId!,
          n: n,
          cell: i,
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
    if (turn != _humanLetter) return;
    final old = _count(_board);
    setState(() => _board = List.of(_board)..[i] = turn);
    _soundFor(old, false);
    await _aiTurn();
  }

  Future<void> _aiTurn() async {
    if (_finished) return;
    final ai = _humanLetter == 'X' ? 'O' : 'X';
    if (TttLogic.turnOf(_board) != ai) return;
    setState(() => _busy = true);
    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;
    final move = TttLogic.aiMove(_board, ai, widget.level ?? 1);
    final old = _count(_board);
    setState(() {
      _board = List.of(_board)..[move] = ai;
      _busy = false;
    });
    _soundFor(old, false);
  }

  Future<void> _again() async {
    if (_online) {
      try {
        final id = await DvGameNet.sendInvite(
          widget.room!,
          game: 'ttt',
          gameTitle: 'крестики-нолики',
          announce: false,
        );
        if (!mounted) return;
        await Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => TttPage(room: widget.room, gameId: id, hostId: _me),
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
      _board = List.filled(9, '');
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
    final w = TttLogic.winner(_board);
    final mine = _mine;
    if (w != null) return w == mine ? 'Вы победили! 🎉' : 'Вы проиграли';
    if (TttLogic.isFull(_board)) return 'Ничья';
    final turn = TttLogic.turnOf(_board);
    if (turn == mine) return 'Ваш ход';
    return _online ? 'Ход соперника…' : 'Компьютер думает…';
  }

  Widget _chip(ThemeData theme, String name, String letter, bool active) {
    final color = letter == 'X'
        ? theme.colorScheme.primary
        : theme.colorScheme.tertiary;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
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
          Text(
            letter == 'X' ? '✕' : '◯',
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
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
    final line = TttLogic.winLine(_board);
    final title = _online
        ? 'Крестики-нолики · ${widget.room!.getLocalizedDisplayname()}'
        : 'Крестики-нолики · ${_levelNames[(widget.level ?? 1).clamp(0, 2)]}';
    final mine = _mine;
    final other = mine == 'X' ? 'O' : 'X';
    final turn = TttLogic.turnOf(_board);
    final playing = !_loading && !_finished;
    final oppName = _online
        ? widget.room!.getLocalizedDisplayname()
        : 'Компьютер';
    return Scaffold(
      appBar: AppBar(title: Text(title), actions: const [DvSoundButton()]),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 360),
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
                  constraints: const BoxConstraints(maxWidth: 360),
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: _TttBoard(board: _board, winLine: line, onTap: _tap),
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

class _TttBoard extends StatelessWidget {
  const _TttBoard({
    required this.board,
    required this.winLine,
    required this.onTap,
  });

  final List<String> board;
  final List<int>? winLine;
  final void Function(int) onTap;

  Widget _cell(ThemeData theme, int i) {
    final v = board[i];
    final win = winLine?.contains(i) ?? false;
    final color = v == 'X'
        ? theme.colorScheme.primary
        : theme.colorScheme.tertiary;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onTap(i),
      child: Container(
        margin: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: win
              ? theme.colorScheme.primaryContainer.withValues(alpha: 0.6)
              : null,
          borderRadius: BorderRadius.circular(16),
        ),
        child: v.isEmpty
            ? null
            : TweenAnimationBuilder<double>(
                key: ValueKey('$i$v'),
                tween: Tween(begin: 0, end: 1),
                duration: const Duration(milliseconds: 320),
                curve: Curves.easeOutCubic,
                builder: (context, t, child) => CustomPaint(
                  painter: _MarkPainter(v, t, color),
                  size: Size.infinite,
                ),
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final line = winLine;
    return LayoutBuilder(
      builder: (context, c) {
        final cs = c.maxWidth / 3;
        return Material(
          color: theme.colorScheme.surfaceContainerHigh,
          elevation: 1,
          shadowColor: Colors.black,
          surfaceTintColor: Colors.transparent,
          borderRadius: BorderRadius.circular(24),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _GridPainter(theme.colorScheme.outlineVariant),
                ),
              ),
              for (var i = 0; i < 9; i++)
                Positioned(
                  left: (i % 3) * cs,
                  top: (i ~/ 3) * cs,
                  width: cs,
                  height: cs,
                  child: _cell(theme, i),
                ),
              if (line != null)
                Positioned.fill(
                  child: IgnorePointer(
                    child: TweenAnimationBuilder<double>(
                      key: ValueKey(line.join(',')),
                      tween: Tween(begin: 0, end: 1),
                      duration: const Duration(milliseconds: 450),
                      curve: Curves.easeOut,
                      builder: (context, t, child) => CustomPaint(
                        painter: _WinPainter(
                          line,
                          t,
                          theme.colorScheme.primary,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _GridPainter extends CustomPainter {
  _GridPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size s) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    final a = s.width / 3;
    final inset = s.width * 0.06;
    for (var k = 1; k <= 2; k++) {
      canvas.drawLine(Offset(a * k, inset), Offset(a * k, s.height - inset), p);
      canvas.drawLine(Offset(inset, a * k), Offset(s.width - inset, a * k), p);
    }
  }

  @override
  bool shouldRepaint(_GridPainter old) => old.color != color;
}

class _MarkPainter extends CustomPainter {
  _MarkPainter(this.letter, this.t, this.color);

  final String letter;
  final double t;
  final Color color;

  @override
  void paint(Canvas canvas, Size s) {
    final c = Offset(s.width / 2, s.height / 2);
    final r = s.shortestSide * 0.3;
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = s.shortestSide * 0.11
      ..strokeCap = StrokeCap.round;
    if (letter == 'X') {
      final t1 = (t * 2).clamp(0.0, 1.0);
      final t2 = ((t - 0.5) * 2).clamp(0.0, 1.0);
      final a = Offset(c.dx - r, c.dy - r);
      final b = Offset(c.dx + r, c.dy + r);
      canvas.drawLine(a, Offset.lerp(a, b, t1)!, p);
      if (t2 > 0) {
        final a2 = Offset(c.dx + r, c.dy - r);
        final b2 = Offset(c.dx - r, c.dy + r);
        canvas.drawLine(a2, Offset.lerp(a2, b2, t2)!, p);
      }
    } else {
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: r * 1.05),
        -pi / 2,
        2 * pi * t,
        false,
        p,
      );
    }
  }

  @override
  bool shouldRepaint(_MarkPainter old) =>
      old.t != t || old.letter != letter || old.color != color;
}

class _WinPainter extends CustomPainter {
  _WinPainter(this.line, this.t, this.color);

  final List<int> line;
  final double t;
  final Color color;

  @override
  void paint(Canvas canvas, Size s) {
    final cs = s.width / 3;
    Offset center(int i) => Offset((i % 3 + 0.5) * cs, (i ~/ 3 + 0.5) * cs);
    final a0 = center(line.first);
    final b0 = center(line.last);
    final d = (b0 - a0) / (b0 - a0).distance;
    final a = a0 - d * (cs * 0.3);
    final b = b0 + d * (cs * 0.3);
    final p = Paint()
      ..color = color.withValues(alpha: 0.85)
      ..strokeWidth = cs * 0.09
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(a, Offset.lerp(a, b, t)!, p);
  }

  @override
  bool shouldRepaint(_WinPainter old) =>
      old.t != t || old.color != color || old.line != line;
}
