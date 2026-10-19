// SPDX-License-Identifier: AGPL-3.0-or-later

// DVChat: экран крестиков-ноликов на тетрадном листе, 5 в ряд на поле 15x15.
// Два режима:
//  - с компьютером, без интернета;
//  - с другом (room + gameId + hostId), ходы идут через личный чат.
// Крестики (синяя ручка) и нолики (красная) рисуются от руки с лёгкой неровностью,
// победная цепочка зачёркивается маркером. Поле можно приближать двумя пальцами.

import 'dart:async';
import 'dart:math';

import 'package:dvchat/pages/games/dv_game_net.dart';
import 'package:dvchat/pages/games/dv_game_sound.dart';
import 'package:dvchat/pages/games/ttt_logic.dart';
import 'package:dvchat/utils/dv_nicknames.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

class _Move {
  const _Move(this.cell, this.sender);

  final int cell;
  final String sender;
}

class TttPage extends StatefulWidget {
  // level оставлен для совместимости со списком игр, на поле 15x15 он не нужен
  const TttPage({
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
  State<TttPage> createState() => _TttPageState();
}

class _TttPageState extends State<TttPage> {
  List<String> _board = List.filled(TttLogic.cells, '');
  final List<int> _order = [];
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
    if (n is! int || cell is! int || cell < 0 || cell >= TttLogic.cells) {
      return false;
    }
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
    final b = List<String>.filled(TttLogic.cells, '');
    final order = <int>[];
    var n = 0;
    String? last;
    while (_moves.containsKey(n)) {
      final m = _moves[n]!;
      final hostMove = n.isEven;
      final fromHost = m.sender == widget.hostId;
      if (hostMove != fromHost || b[m.cell] != '') break;
      b[m.cell] = hostMove ? 'X' : 'O';
      order.add(m.cell);
      last = m.sender;
      n++;
      if (TttLogic.winner(b) != null) break;
    }
    _lastSender = last;
    if (!mounted) return;
    final oldCount = _count(_board);
    final wasFinished = _finished;
    setState(() {
      _board = b;
      _order
        ..clear()
        ..addAll(order);
    });
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
    setState(() {
      _board = List.of(_board)..[i] = turn;
      _order.add(i);
    });
    _soundFor(old, false);
    await _aiTurn();
  }

  Future<void> _aiTurn() async {
    if (_finished) return;
    final ai = _humanLetter == 'X' ? 'O' : 'X';
    if (TttLogic.turnOf(_board) != ai) return;
    setState(() => _busy = true);
    await Future<void>.delayed(const Duration(milliseconds: 550));
    if (!mounted) return;
    final move = TttLogic.aiMove(_board, ai);
    final old = _count(_board);
    setState(() {
      _board = List.of(_board)..[move] = ai;
      _order.add(move);
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
      _board = List.filled(TttLogic.cells, '');
      _order.clear();
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
    final color = letter == 'X' ? _inkBlue : _inkRed;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: active ? color.withValues(alpha: 0.14) : null,
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
        ? 'Крестики-нолики · ${widget.room!.dvDisplayname()}'
        : 'Крестики-нолики · 5 в ряд';
    final mine = _mine;
    final other = mine == 'X' ? 'O' : 'X';
    final turn = TttLogic.turnOf(_board);
    final playing = !_loading && !_finished;
    final oppName = _online ? widget.room!.dvDisplayname() : 'Компьютер';
    return Scaffold(
      appBar: AppBar(title: Text(title), actions: const [DvSoundButton()]),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
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
                const SizedBox(height: 12),
                Text(_status, style: theme.textTheme.titleLarge),
                const SizedBox(height: 12),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: _TttBoard(
                    board: _board,
                    last: _order.isEmpty ? -1 : _order.last,
                    winLine: line,
                    onTap: _tap,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Нужно собрать 5 подряд. Поле можно приблизить двумя пальцами.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
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

// ---------------- тетрадный лист ----------------

const Color _paper = Color(0xFFFBF7EA);
const Color _gridBlue = Color(0xFFB7C9E4);
const Color _inkBlue = Color(0xFF1C3F9E);
const Color _inkRed = Color(0xFFC62828);
const Color _marker = Color(0xFF2E9E4F);

/// Размеры листа: сетка N x N с полями слева (красная линия) и небольшими отступами
class _Geo {
  _Geo(double width) {
    cs = width / (TttLogic.n + 1.6);
    lm = cs * 1.1;
    tp = cs * 0.5;
    w = width;
    h = (TttLogic.n + 1) * cs;
  }

  late final double cs, lm, tp, w, h;

  Offset center(int i) => Offset(
    lm + (i % TttLogic.n + 0.5) * cs,
    tp + (i ~/ TttLogic.n + 0.5) * cs,
  );

  int? cellAt(Offset p) {
    final x = ((p.dx - lm) / cs).floor();
    final y = ((p.dy - tp) / cs).floor();
    if (x < 0 || y < 0 || x >= TttLogic.n || y >= TttLogic.n) return null;
    return y * TttLogic.n + x;
  }
}

class _TttBoard extends StatefulWidget {
  const _TttBoard({
    required this.board,
    required this.last,
    required this.winLine,
    required this.onTap,
  });

  final List<String> board;
  final int last;
  final List<int>? winLine;
  final void Function(int) onTap;

  @override
  State<_TttBoard> createState() => _TttBoardState();
}

class _TttBoardState extends State<_TttBoard> with TickerProviderStateMixin {
  late final AnimationController _pen = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  )..value = 1;
  late final AnimationController _win = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 650),
  );

  @override
  void didUpdateWidget(_TttBoard old) {
    super.didUpdateWidget(old);
    if (widget.last != old.last || _cnt(widget.board) != _cnt(old.board)) {
      if (widget.last >= 0 && widget.board[widget.last] != '') {
        _pen.forward(from: 0);
      } else {
        _pen.value = 1;
      }
    }
    if (widget.winLine != null && old.winLine == null) {
      _win.forward(from: 0);
    } else if (widget.winLine == null) {
      _win.value = 0;
    }
  }

  int _cnt(List<String> b) => b.where((c) => c != '').length;

  @override
  void dispose() {
    _pen.dispose();
    _win.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final g = _Geo(c.maxWidth);
        return InteractiveViewer(
          minScale: 1,
          maxScale: 3.5,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (d) {
              final i = g.cellAt(d.localPosition);
              if (i != null) widget.onTap(i);
            },
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x40000000),
                    blurRadius: 10,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: AnimatedBuilder(
                  animation: Listenable.merge([_pen, _win]),
                  builder: (context, _) => CustomPaint(
                    size: Size(g.w, g.h),
                    painter: _SheetPainter(
                      g: g,
                      board: widget.board,
                      last: widget.last,
                      pen: Curves.easeOut.transform(_pen.value),
                      win: widget.winLine,
                      winT: Curves.easeInOut.transform(_win.value),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SheetPainter extends CustomPainter {
  _SheetPainter({
    required this.g,
    required this.board,
    required this.last,
    required this.pen,
    required this.win,
    required this.winT,
  });

  final _Geo g;
  final List<String> board;
  final int last;
  final double pen;
  final List<int>? win;
  final double winT;

  @override
  void paint(Canvas canvas, Size s) {
    // бумага
    canvas.drawRect(Offset.zero & s, Paint()..color = _paper);

    // клетки на всём листе, выровненные по игровому полю
    final grid = Paint()
      ..color = _gridBlue
      ..strokeWidth = 1;
    for (var x = g.lm - g.cs; x <= s.width; x += g.cs) {
      if (x < 0) continue;
      canvas.drawLine(Offset(x, 0), Offset(x, s.height), grid);
    }
    for (var y = g.tp - g.cs; y <= s.height; y += g.cs) {
      if (y < 0) continue;
      canvas.drawLine(Offset(0, y), Offset(s.width, y), grid);
    }
    // игровое поле слегка обведено
    canvas.drawRect(
      Rect.fromLTWH(g.lm, g.tp, g.cs * TttLogic.n, g.cs * TttLogic.n),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = _gridBlue.withValues(alpha: 0.95),
    );

    // красная линия полей и дырки от переплёта
    canvas.drawLine(
      Offset(g.cs * 0.72, 0),
      Offset(g.cs * 0.72, s.height),
      Paint()
        ..color = const Color(0xFFE57373)
        ..strokeWidth = 1.4,
    );
    for (final f in [0.2, 0.5, 0.8]) {
      final c = Offset(g.cs * 0.3, s.height * f);
      canvas.drawCircle(
        c,
        g.cs * 0.17,
        Paint()..color = const Color(0x22000000),
      );
      canvas.drawCircle(c, g.cs * 0.14, Paint()..color = const Color(0xFFD9D3C0));
    }

    // подсветка последнего хода — жёлтый маркер
    if (last >= 0 && board[last] != '') {
      final c = g.center(last);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: c, width: g.cs * 0.94, height: g.cs * 0.94),
          Radius.circular(g.cs * 0.2),
        ),
        Paint()..color = const Color(0x55FFE14D),
      );
    }

    // фишки
    for (var i = 0; i < board.length; i++) {
      final v = board[i];
      if (v == '') continue;
      final t = i == last ? pen : 1.0;
      _drawMark(canvas, g.center(i), g.cs, v, i, t);
    }

    // зачёркивание победной цепочки
    final w = win;
    if (w != null && winT > 0) _drawWin(canvas, w);
  }

  void _stroke(Canvas canvas, Path path, Color color, double width, double t) {
    final metrics = path.computeMetrics().toList();
    for (final m in metrics) {
      final part = m.extractPath(0, m.length * t);
      // основной след и чуть сдвинутый бледный — как нажим шариковой ручки
      canvas.drawPath(
        part,
        Paint()
          ..color = color.withValues(alpha: 0.9)
          ..style = PaintingStyle.stroke
          ..strokeWidth = width
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
      canvas.drawPath(
        part.shift(Offset(width * 0.25, width * 0.2)),
        Paint()
          ..color = color.withValues(alpha: 0.28)
          ..style = PaintingStyle.stroke
          ..strokeWidth = width * 0.7
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  void _drawMark(Canvas canvas, Offset c, double cs, String v, int i, double t) {
    final rnd = Random(i * 7919 + (v == 'X' ? 13 : 71));
    double j(double a) => (rnd.nextDouble() - 0.5) * 2 * a;
    final r = cs * 0.30;
    final width = max(1.6, cs * 0.095);
    if (v == 'X') {
      final a1 = Offset(c.dx - r + j(cs * 0.06), c.dy - r + j(cs * 0.06));
      final b1 = Offset(c.dx + r + j(cs * 0.08), c.dy + r + j(cs * 0.08));
      final a2 = Offset(c.dx + r + j(cs * 0.06), c.dy - r + j(cs * 0.06));
      final b2 = Offset(c.dx - r + j(cs * 0.08), c.dy + r + j(cs * 0.08));
      final p1 = Path()
        ..moveTo(a1.dx, a1.dy)
        ..quadraticBezierTo(
          (a1.dx + b1.dx) / 2 + j(cs * 0.07),
          (a1.dy + b1.dy) / 2 + j(cs * 0.07),
          b1.dx,
          b1.dy,
        );
      final p2 = Path()
        ..moveTo(a2.dx, a2.dy)
        ..quadraticBezierTo(
          (a2.dx + b2.dx) / 2 + j(cs * 0.07),
          (a2.dy + b2.dy) / 2 + j(cs * 0.07),
          b2.dx,
          b2.dy,
        );
      _stroke(canvas, p1, _inkBlue, width, (t * 2).clamp(0.0, 1.0));
      if (t > 0.5) {
        _stroke(canvas, p2, _inkBlue, width, ((t - 0.5) * 2).clamp(0.0, 1.0));
      }
    } else {
      // нолик: чуть больше оборота по спирали, конец заходит за начало
      final start = rnd.nextDouble() * 2 * pi;
      final turns = 1.12 + rnd.nextDouble() * 0.1;
      final rx = r * (1.0 + j(0.06));
      final ry = r * (1.0 + j(0.06));
      final steps = 36;
      final path = Path();
      for (var k = 0; k <= steps; k++) {
        final f = k / steps;
        final ang = start + f * turns * 2 * pi;
        final wob = 1 + 0.05 * sin(f * 9 + start) + f * 0.07;
        final p = Offset(
          c.dx + cos(ang) * rx * wob,
          c.dy + sin(ang) * ry * wob,
        );
        if (k == 0) {
          path.moveTo(p.dx, p.dy);
        } else {
          path.lineTo(p.dx, p.dy);
        }
      }
      _stroke(canvas, path, _inkRed, width, t);
    }
  }

  void _drawWin(Canvas canvas, List<int> line) {
    final a0 = g.center(line.first);
    final b0 = g.center(line.last);
    final dir = (b0 - a0) / (b0 - a0).distance;
    final a = a0 - dir * g.cs * 0.45;
    final b = b0 + dir * g.cs * 0.45;
    final nrm = Offset(-dir.dy, dir.dx);
    final len = (b - a).distance;
    final path = Path()..moveTo(a.dx, a.dy);
    const steps = 24;
    for (var k = 1; k <= steps; k++) {
      final f = k / steps;
      final wob = sin(f * pi * 3) * g.cs * 0.05;
      final p = a + (b - a) * f + nrm * wob;
      path.lineTo(p.dx, p.dy);
    }
    final m = path.computeMetrics().first;
    final part = m.extractPath(0, len * winT);
    canvas.drawPath(
      part,
      Paint()
        ..color = _marker.withValues(alpha: 0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = g.cs * 0.34
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_SheetPainter old) =>
      old.board != board ||
      old.last != last ||
      old.pen != pen ||
      old.win != win ||
      old.winT != winT ||
      old.g.w != g.w;
}
