// SPDX-License-Identifier: AGPL-3.0-or-later

// DVChat: экран нард (короткие нарды). Два режима:
//  - с компьютером, без интернета (компьютер играет в полную силу);
//  - с другом (room + gameId + hostId), ходы идут через личный чат.
// Доска деревянная, шашки и кости нарисованы, шашки плавно ездят, кости кувыркаются.
// Кости общие для двоих: считаются из номера партии, поэтому обоим телефонам выпадает одно и то же.

import 'package:dvchat/pages/games/dv_local_stats.dart';
import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:dvchat/pages/games/dv_game_net.dart';
import 'package:dvchat/pages/games/dv_game_sound.dart';
import 'package:dvchat/pages/games/nardy_logic.dart';
import 'package:dvchat/utils/dv_nicknames.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

class _Move {
  const _Move(this.cell, this.sender);

  final int cell;
  final String sender;
}

class NardyPage extends StatefulWidget {
  // level оставлен для совместимости со списком игр: компьютер всегда играет в полную силу
  const NardyPage({
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
  State<NardyPage> createState() => _NardyPageState();
}

class _Slide {
  const _Slide(this.pl, this.from, this.fromCount, this.dest, this.toIdx);

  final int pl;
  final int from; // 0..23 или 24 бар
  final int fromCount; // сколько шашек было в пункте до хода
  final int dest; // 0..23 или -1 выброс
  final int toIdx; // номер места шашки в пункте назначения после хода
}

class _BgCache {
  ui.Picture? pic;
  Size? size;
}

class _NardyPageState extends State<NardyPage> with TickerProviderStateMixin {
  late String _seed;
  late NardyGame _game;
  final Map<int, _Move> _moves = {};
  int? _sel;
  _Slide? _slide;
  bool _humanFirst = true;
  bool _busy = false;

  // Сетевая игра
  StreamSubscription<Event>? _sub;
  String? _lastSender;
  bool _endSent = false;
  bool _loading = false;
  String? _surrenderBy;
  int _passShown = -1;

  final _BgCache _bg = _BgCache();

  late final AnimationController _slideC = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 340),
  );
  late final AnimationController _rollC = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  )..value = 1;
  late final AnimationController _pulseC = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  bool get _online => widget.room != null;
  String get _me => widget.room?.client.userID ?? '';
  int get _myPl => _online ? (widget.hostId == _me ? 0 : 1) : (_humanFirst ? 0 : 1);
  int get _aiPl => 1 - _myPl;
  String get _whiteSender => _online ? (widget.hostId ?? '') : (_humanFirst ? 'me' : 'ai');
  bool get _finished => _surrenderBy != null || _game.winner >= 0;

  @override
  void initState() {
    super.initState();
    DvLocalStats.open('nardy', offline: widget.room == null);
    _pulseC.repeat();
    _seed = _online ? widget.gameId! : DateTime.now().microsecondsSinceEpoch.toString();
    _game = NardyGame(_seed);
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
    _slideC.dispose();
    _rollC.dispose();
    _pulseC.dispose();
    DvLocalStats.close('nardy');
    super.dispose();
  }

  // ---------------- сетевая часть ----------------

  bool _ingest(Event e) {
    if (e.type != DvGameNet.eventType || e.roomId != widget.room?.id) {
      return false;
    }
    final c = e.content;
    if (c['game'] != 'nardy' || '${c['id']}' != widget.gameId) return false;
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
    if (n is! int || cell is! int || cell < 0 || cell > 24 * 7 + 6) {
      return false;
    }
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
    final g = NardyGame(_seed);
    var n = 0;
    String? last;
    while (_moves.containsKey(n)) {
      final m = _moves[n]!;
      final d = NMove.decode(m.cell);
      if (d == null) break;
      final fromWhite = m.sender == _whiteSender;
      if (fromWhite != (g.pl == 0)) break;
      if (!g.apply(d.from, d.die)) break;
      last = m.sender;
      n++;
    }
    _lastSender = last;
    if (!mounted) return;
    final wasFinished = _finished;
    setState(() {
      _game = g;
      _sel = null;
    });
    if (!silent) {
      if (g.moveCount == old.moveCount + 1 && g.lastMove != null) {
        _startSlide(old, g);
      }
      if (g.turn != old.turn && g.winner < 0) _rollC.forward(from: 0);
      _sound(old, g, wasFinished);
      _notePasses(g);
    }
    _maybeSendEnd();
    _maybeAi();
  }

  void _startSlide(NardyGame old, NardyGame g) {
    final m = g.lastMove!;
    final pl = g.lastMovePl;
    final before = m.from == 24 ? old.board.bar[pl] : old.board.own(m.from, pl);
    final toIdx = m.dest == -1 ? g.board.off[pl] - 1 : g.board.own(m.dest, pl) - 1;
    _slide = _Slide(pl, m.from, before, m.dest, toIdx);
    _slideC.forward(from: 0).whenComplete(() {
      if (mounted) setState(() => _slide = null);
    });
  }

  void _sound(NardyGame old, NardyGame g, bool wasFinished) {
    if (!wasFinished && _finished) {
      final sound = _surrenderBy != null
          ? (_surrenderBy == _me ? DvSound.lose : DvSound.win)
          : (g.winner == _myPl ? DvSound.win : DvSound.lose);
      unawaited(DvGameSound.play(sound));
    } else if (g.moveCount > old.moveCount) {
      if (g.lastHit) {
        unawaited(DvGameSound.play(DvSound.hit));
      } else {
        unawaited(
          DvGameSound.play(g.lastMovePl == _myPl ? DvSound.place : DvSound.enemy),
        );
      }
    }
  }

  void _notePasses(NardyGame g) {
    if (g.lastPasses.isEmpty) return;
    final p = g.lastPasses.last;
    if (p.turn == _passShown) return;
    _passShown = p.turn;
    final who = p.pl == _myPl ? 'У вас' : (_online ? 'У соперника' : 'У компьютера');
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('$who нет хода (${p.rolled[0]} и ${p.rolled[1]}), ход переходит'),
          duration: const Duration(seconds: 2),
        ),
      );
  }

  void _maybeSendEnd() {
    if (!_online || _endSent || _game.winner < 0 || _surrenderBy != null) return;
    if (_lastSender != _me) return;
    _endSent = true;
    unawaited(
      DvGameNet.sendEnd(
        widget.room!,
        game: 'nardy',
        id: widget.gameId!,
        winner: _me,
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
    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;
    final g = _game;
    final seq = NardyAi.bestTurn(g.board, _aiPl, List<int>.of(g.dice));
    for (final m in seq) {
      if (!mounted) return;
      if (_game.pl != _aiPl || _game.winner >= 0) break;
      _moves[_moves.length] = _Move(m.cell, 'ai');
      _replay();
      await Future<void>.delayed(const Duration(milliseconds: 560));
    }
    if (!mounted) return;
    setState(() => _busy = false);
    _maybeAi();
  }

  // ---------------- ходы игрока ----------------

  bool get _myTurn =>
      !_loading && !_busy && !_finished && _game.pl == _myPl;

  Future<void> _doMove(int from, int die) async {
    final n = _game.moveCount;
    _moves[n] = _Move(from * 7 + die, _online ? _me : 'me');
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
        game: 'nardy',
        id: widget.gameId!,
        n: n,
        cell: from * 7 + die,
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

  void _onTap(int target) {
    if (!_myTurn) return;
    final legal = _game.legalMoves();
    final sel = _sel;
    if (sel != null) {
      NMove? pick;
      for (final m in legal) {
        if (m.from != sel || m.dest != target) continue;
        // при выбросе с перебросом берём меньшую кость, большая остаётся про запас
        if (pick == null || m.die < pick.die) pick = m;
      }
      if (pick != null) {
        unawaited(_doMove(pick.from, pick.die));
        return;
      }
    }
    final isSource = legal.any((m) => m.from == target);
    setState(() => _sel = (isSource && sel != target) ? target : null);
  }

  Future<void> _again() async {
    if (_online) {
      try {
        final id = await DvGameNet.sendInvite(
          widget.room!,
          game: 'nardy',
          gameTitle: 'нарды',
          announce: false,
        );
        if (!mounted) return;
        await Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => NardyPage(room: widget.room, gameId: id, hostId: _me),
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
      _game = NardyGame(_seed);
      _sel = null;
      _slide = null;
      _passShown = -1;
    });
    _rollC.forward(from: 0);
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
      final mars = g.gammon ? ' (марс)' : '';
      return g.winner == _myPl ? 'Вы победили!$mars 🎉' : 'Вы проиграли$mars';
    }
    if (g.pl == _myPl) {
      return g.dice.length > 1 ? 'Ваш ход' : 'Ваш ход, осталась одна кость';
    }
    return _online ? 'Ход соперника…' : 'Компьютер думает…';
  }

  Widget _chip(ThemeData theme, String name, int pl, bool active) {
    final white = pl == 0;
    final g = _game;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: active ? const Color(0xFFB98652).withValues(alpha: 0.22) : null,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: active ? const Color(0xFF8A5A2B) : theme.colorScheme.outlineVariant,
          width: active ? 2 : 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                center: const Alignment(-0.3, -0.3),
                colors: white
                    ? const [Color(0xFFFFFDF2), Color(0xFFD9C9A0)]
                    : const [Color(0xFF5A4B45), Color(0xFF140E0C)],
              ),
              border: Border.all(
                color: white ? const Color(0xFF9C8A5E) : Colors.black,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(
                  'до дома ${g.pips(pl)} · вынесено ${g.board.off[pl]}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = _online
        ? 'Нарды · ${widget.room!.dvDisplayname()}'
        : 'Нарды · с компьютером';
    final me = _myPl;
    final g = _game;
    final playing = !_loading && !_finished;
    final oppName = _online ? widget.room!.dvDisplayname() : 'Компьютер';
    final legal = _myTurn ? g.legalMoves() : const <NMove>[];
    final sources = <int>{for (final m in legal) m.from};
    final dests = <int>{
      if (_sel != null)
        for (final m in legal)
          if (m.from == _sel) m.dest,
    };
    return Scaffold(
      appBar: AppBar(title: Text(title), actions: const [DvSoundButton()]),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(10),
            child: Column(
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Row(
                    children: [
                      Expanded(
                        child: _chip(theme, 'Вы', me, playing && g.pl == me),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _chip(
                          theme,
                          oppName,
                          1 - me,
                          playing && g.pl == 1 - me,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Text(_status, style: theme.textTheme.titleLarge),
                const SizedBox(height: 10),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: LayoutBuilder(
                    builder: (context, c) {
                      final w = c.maxWidth;
                      final size = Size(w, w * 0.8);
                      final geo = _NG(size, me == 1);
                      return GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTapUp: (d) {
                          final t = geo.hit(d.localPosition);
                          if (t != null) _onTap(t);
                        },
                        child: AnimatedBuilder(
                          animation: Listenable.merge([_slideC, _rollC, _pulseC]),
                          builder: (context, _) => CustomPaint(
                            size: size,
                            painter: _NardyPainter(
                              geo: geo,
                              game: g,
                              cache: _bg,
                              myPl: me,
                              sel: _sel,
                              sources: sources,
                              dests: dests,
                              slide: _slide,
                              slideT: Curves.easeInOutCubic.transform(_slideC.value),
                              rollT: _rollC.value,
                              pulse: _pulseC.value,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Нажмите свою шашку, потом подсвеченное место. Шашки выносят в лоток справа.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 14),
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

// ---------------- геометрия доски ----------------

/// Раскладка: слева 6 пунктов, посередине бар, справа 6 пунктов и лоток для выброшенных.
/// Дом игрока всегда внизу справа: чёрным доска зеркалится по вертикали (flip).
class _NG {
  _NG(this.size, this.flip) : c = size.width / 14.65 {
    h = size.height;
    pad = h * 0.035;
    gap = h * 0.15;
    depth = (h - 2 * pad - gap) / 2;
    r = c * 0.44;
    lx0 = c * 0.25;
    barX = lx0 + 6 * c;
    rx0 = barX + c;
    trayX = rx0 + 6 * c;
    trayW = c * 1.15;
  }

  final Size size;
  final bool flip;
  final double c;
  late final double h, pad, gap, depth, r, lx0, barX, rx0, trayX, trayW;

  /// (половина 0 слева/1 справа, колонка 0..5 слева направо, верхний ряд)
  (int, int, bool) _place(int idx) {
    int half, k;
    bool top;
    if (idx <= 5) {
      half = 1;
      k = 5 - idx;
      top = false;
    } else if (idx <= 11) {
      half = 0;
      k = 11 - idx;
      top = false;
    } else if (idx <= 17) {
      half = 0;
      k = idx - 12;
      top = true;
    } else {
      half = 1;
      k = idx - 18;
      top = true;
    }
    return (half, k, top != flip);
  }

  Rect pointRect(int idx) {
    final (half, k, top) = _place(idx);
    final x = (half == 0 ? lx0 : rx0) + k * c;
    return top
        ? Rect.fromLTWH(x, pad, c, depth)
        : Rect.fromLTWH(x, h - pad - depth, c, depth);
  }

  Offset slot(int idx, int i, int count) {
    final (half, k, top) = _place(idx);
    final xc = (half == 0 ? lx0 : rx0) + k * c + c / 2;
    final step = count <= 1 ? 2 * r : min(2 * r, (depth - 2 * r) / (count - 1));
    final y = top ? pad + r + i * step : h - pad - r - i * step;
    return Offset(xc, y);
  }

  Offset barSlot(int pl, int i, int count) {
    final down = (pl == 0) != flip;
    final room = h / 2 - pad - r * 1.4;
    final step = count <= 1 ? 2 * r : min(2 * r, (room - r) / (count - 1));
    final off = r * 0.35 + r + i * step;
    return Offset(barX + c / 2, h / 2 + (down ? off : -off));
  }

  double get pillH => c * 0.30;

  Offset traySlot(int pl, int i) {
    final bottom = (pl == 0) != flip;
    final y = bottom ? h - pad - pillH * (i + 0.5) - c * 0.05 : pad + pillH * (i + 0.5) + c * 0.05;
    return Offset(trayX + trayW / 2, y);
  }

  Rect trayRect(int pl) {
    final bottom = (pl == 0) != flip;
    return bottom
        ? Rect.fromLTRB(trayX + c * 0.06, h / 2 + gap * 0.1, trayX + trayW - c * 0.06, h - pad)
        : Rect.fromLTRB(trayX + c * 0.06, pad, trayX + trayW - c * 0.06, h / 2 - gap * 0.1);
  }

  /// Что под пальцем: пункт 0..23, бар 24 или лоток -1
  int? hit(Offset p) {
    if (p.dx >= trayX) {
      return p.dx <= trayX + trayW + c * 0.25 ? -1 : null;
    }
    if (p.dx >= barX && p.dx < barX + c) return 24;
    int half, k;
    if (p.dx >= lx0 && p.dx < lx0 + 6 * c) {
      half = 0;
      k = ((p.dx - lx0) / c).floor().clamp(0, 5);
    } else if (p.dx >= rx0 && p.dx < rx0 + 6 * c) {
      half = 1;
      k = ((p.dx - rx0) / c).floor().clamp(0, 5);
    } else {
      return null;
    }
    final top = (p.dy < h / 2) != flip; // настоящий верхний ряд (без зеркала)
    if (!top) return half == 1 ? 5 - k : 11 - k;
    return half == 0 ? 12 + k : 18 + k;
  }
}

// ---------------- рисование ----------------

const Color _walnut = Color(0xFF4A2B15);
const Color _walnutLight = Color(0xFF7A4B26);
const Color _oak = Color(0xFFB98652);
const Color _pointDark = Color(0xFF4F2C14);
const Color _pointLight = Color(0xFFF4E4BC);
const Color _brass = Color(0xFFD0A74C);

class _NardyPainter extends CustomPainter {
  _NardyPainter({
    required this.geo,
    required this.game,
    required this.cache,
    required this.myPl,
    required this.sel,
    required this.sources,
    required this.dests,
    required this.slide,
    required this.slideT,
    required this.rollT,
    required this.pulse,
  });

  final _NG geo;
  final NardyGame game;
  final _BgCache cache;
  final int myPl;
  final int? sel;
  final Set<int> sources;
  final Set<int> dests;
  final _Slide? slide;
  final double slideT;
  final double rollT;
  final double pulse;

  // ----- фон: дерево, пункты, бар, лоток (рисуется один раз и кэшируется) -----

  void _grain(
    Canvas cv,
    Rect rect,
    int seed,
    Color dark,
    Color light,
    int lines, {
    bool vertical = false,
  }) {
    cv.save();
    cv.clipRect(rect);
    final rnd = Random(seed);
    for (var k = 0; k < lines; k++) {
      final along = vertical ? rect.height : rect.width;
      final across = vertical ? rect.width : rect.height;
      final pos = rnd.nextDouble() * across;
      final amp = 0.6 + rnd.nextDouble() * across * 0.02;
      final freq = (0.01 + rnd.nextDouble() * 0.03) * (400 / max(along, 100));
      final phase = rnd.nextDouble() * 6.28;
      final path = Path();
      const steps = 28;
      for (var s = 0; s <= steps; s++) {
        final t = along * s / steps;
        final off = pos + sin(t * freq + phase) * amp;
        final pt = vertical
            ? Offset(rect.left + off, rect.top + t)
            : Offset(rect.left + t, rect.top + off);
        if (s == 0) {
          path.moveTo(pt.dx, pt.dy);
        } else {
          path.lineTo(pt.dx, pt.dy);
        }
      }
      final isDark = rnd.nextDouble() < 0.65;
      cv.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.5 + rnd.nextDouble() * 1.4
          ..color = (isDark ? dark : light).withValues(
            alpha: 0.05 + rnd.nextDouble() * 0.11,
          ),
      );
    }
    cv.restore();
  }

  void _paintBackground(Canvas cv) {
    final g = geo;
    final full = Offset.zero & g.size;
    // внешняя рама
    final frame = RRect.fromRectAndRadius(full, Radius.circular(g.c * 0.5));
    cv.drawRRect(
      frame,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_walnutLight, _walnut, Color(0xFF3A200F)],
        ).createShader(full),
    );
    cv.save();
    cv.clipRRect(frame);
    _grain(cv, full, 11, const Color(0xFF241307), const Color(0xFF9B6A3E), 90);
    cv.restore();
    // фаска рамы
    cv.drawRRect(
      frame.deflate(1),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = const Color(0x33FFFFFF),
    );

    // игровое поле: две половины из светлого дуба
    final left = Rect.fromLTRB(g.lx0, g.pad, g.lx0 + 6 * g.c, g.h - g.pad);
    final right = Rect.fromLTRB(g.rx0, g.pad, g.rx0 + 6 * g.c, g.h - g.pad);
    for (final (i, rect) in [left, right].indexed) {
      cv.drawRect(
        rect,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFC99660), _oak, Color(0xFFA9763F)],
          ).createShader(rect),
      );
      _grain(cv, rect, 21 + i, const Color(0xFF6B4423), const Color(0xFFE3BB86), 55);
      // вдавленная окантовка
      cv.drawRect(
        rect.inflate(1),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = const Color(0xFF2A1809).withValues(alpha: 0.7),
      );
    }

    // пункты (треугольники) попеременно тёмные и светлые
    for (var idx = 0; idx < 24; idx++) {
      final rect = g.pointRect(idx);
      final (_, k, top) = g._place(idx);
      final dark = (k + (top ? 1 : 0)) % 2 == 0;
      final base = top ? rect.top : rect.bottom;
      final apex = top ? rect.top + rect.height * 0.9 : rect.bottom - rect.height * 0.9;
      final path = Path()
        ..moveTo(rect.left + g.c * 0.05, base)
        ..lineTo(rect.center.dx, apex)
        ..lineTo(rect.right - g.c * 0.05, base)
        ..close();
      final c1 = dark ? _pointDark : _pointLight;
      final c2 = dark ? const Color(0xFF7A4B26) : const Color(0xFFE0C58E);
      cv.drawPath(
        path,
        Paint()
          ..shader = LinearGradient(
            begin: top ? Alignment.topCenter : Alignment.bottomCenter,
            end: top ? Alignment.bottomCenter : Alignment.topCenter,
            colors: [c1, c2],
          ).createShader(rect),
      );
      cv.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8
          ..color = const Color(0xFF2A1809).withValues(alpha: 0.55),
      );
    }

    // бар посередине
    final bar = Rect.fromLTRB(g.barX, g.pad * 0.5, g.barX + g.c, g.h - g.pad * 0.5);
    cv.drawRect(
      bar,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFF3A200F), _walnutLight, Color(0xFF3A200F)],
        ).createShader(bar),
    );
    _grain(cv, bar, 31, const Color(0xFF1E1006), const Color(0xFF9B6A3E), 12, vertical: true);
    for (final f in [0.2, 0.8]) {
      final hinge = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(bar.center.dx, g.h * f),
          width: g.c * 0.55,
          height: g.c * 1.3,
        ),
        Radius.circular(g.c * 0.1),
      );
      cv.drawRRect(
        hinge,
        Paint()
          ..shader = const LinearGradient(
            colors: [Color(0xFF8E6A22), _brass, Color(0xFF8E6A22)],
          ).createShader(hinge.outerRect),
      );
      cv.drawCircle(hinge.center + Offset(0, -g.c * 0.35), g.c * 0.07, Paint()..color = const Color(0xFF5E4310));
      cv.drawCircle(hinge.center + Offset(0, g.c * 0.35), g.c * 0.07, Paint()..color = const Color(0xFF5E4310));
    }

    // лоток для выброшенных шашек
    for (final pl in [0, 1]) {
      final rect = g.trayRect(pl);
      final well = RRect.fromRectAndRadius(rect, Radius.circular(g.c * 0.12));
      cv.drawRRect(
        well,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [Color(0xFF1C1007), Color(0xFF3A2312)],
          ).createShader(rect),
      );
      cv.drawRRect(
        well,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = const Color(0x55000000),
      );
    }
  }

  // ----- шашка -----

  void _checker(Canvas cv, Offset c, double r, int pl, {double alpha = 1, double lift = 0}) {
    final white = pl == 0;
    cv.drawCircle(
      c + Offset(r * 0.12, r * (0.2 + lift)),
      r,
      Paint()..color = Colors.black.withValues(alpha: 0.3 * alpha),
    );
    final p = c + Offset(0, -r * lift * 0.6);
    cv.drawCircle(
      p,
      r,
      Paint()
        ..shader = ui.Gradient.radial(
          p + Offset(-r * 0.3, -r * 0.35),
          r * 1.4,
          white
              ? const [Color(0xFFFFFDF2), Color(0xFFE9DCB8), Color(0xFFBBA777)]
              : const [Color(0xFF6A5A53), Color(0xFF2B211E), Color(0xFF0E0908)],
          const [0.0, 0.6, 1.0],
        ),
    );
    cv.drawCircle(
      p,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = max(1.0, r * 0.1)
        ..color = (white ? const Color(0xFF8E7B4E) : Colors.black).withValues(alpha: alpha),
    );
    cv.drawCircle(
      p,
      r * 0.66,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = max(0.8, r * 0.07)
        ..color = (white ? const Color(0xFF8E7B4E) : const Color(0xFF8A766C)).withValues(alpha: 0.5 * alpha),
    );
  }

  void _pill(Canvas cv, Offset c, int pl) {
    final g = geo;
    final white = pl == 0;
    final rr = RRect.fromRectAndRadius(
      Rect.fromCenter(center: c, width: g.c * 0.92, height: g.pillH * 0.9),
      Radius.circular(g.pillH * 0.4),
    );
    cv.drawRRect(
      rr,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: white
              ? const [Color(0xFFFFFDF2), Color(0xFFBBA777)]
              : const [Color(0xFF6A5A53), Color(0xFF0E0908)],
        ).createShader(rr.outerRect),
    );
    cv.drawRRect(
      rr,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8
        ..color = white ? const Color(0xFF8E7B4E) : Colors.black,
    );
  }

  void _label(Canvas cv, Offset c, String text, Color color, double size) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: size,
          fontWeight: FontWeight.w800,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(cv, c - Offset(tp.width / 2, tp.height / 2));
  }

  // ----- кость -----

  static const Map<int, List<int>> _pips = {
    1: [4],
    2: [0, 8],
    3: [0, 4, 8],
    4: [0, 2, 6, 8],
    5: [0, 2, 4, 6, 8],
    6: [0, 2, 3, 5, 6, 8],
  };

  void _die(Canvas cv, Offset c, double s, int v, double angle, double alpha, bool dark) {
    cv.save();
    cv.translate(c.dx, c.dy);
    cv.rotate(angle);
    final rr = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset.zero, width: s, height: s),
      Radius.circular(s * 0.2),
    );
    cv.drawRRect(
      rr.shift(Offset(s * 0.05, s * 0.09)),
      Paint()..color = Colors.black.withValues(alpha: 0.32 * alpha),
    );
    cv.drawRRect(
      rr,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: dark
              ? [const Color(0xFF4A3B35).withValues(alpha: alpha), const Color(0xFF16100E).withValues(alpha: alpha)]
              : [const Color(0xFFFFFEF6).withValues(alpha: alpha), const Color(0xFFDDCFA6).withValues(alpha: alpha)],
        ).createShader(rr.outerRect),
    );
    cv.drawRRect(
      rr,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = max(1.0, s * 0.04)
        ..color = (dark ? Colors.black : const Color(0xFF9C8A5E)).withValues(alpha: alpha),
    );
    final pipColor = (dark ? const Color(0xFFF1E6C8) : const Color(0xFF1B1210)).withValues(alpha: alpha);
    for (final cell in _pips[v] ?? const <int>[]) {
      final dx = (cell % 3 - 1) * s * 0.27;
      final dy = (cell ~/ 3 - 1) * s * 0.27;
      cv.drawCircle(Offset(dx, dy), s * 0.075, Paint()..color = pipColor);
    }
    cv.restore();
  }

  void _dice(Canvas cv) {
    final g = geo;
    final gm = game;
    if (gm.winner >= 0) return;
    final size = min(g.gap * 0.78, g.c * 1.6);
    // кости ложатся в ту половину, где играет тот, чей ход (своя справа)
    final mineTurn = gm.pl == myPl;
    final cx = (mineTurn ? g.rx0 : g.lx0) + 3 * g.c;
    final y = g.h / 2;
    final remaining = List<int>.of(gm.dice);
    final isDouble = gm.rolled[0] == gm.rolled[1];
    for (var i = 0; i < 2; i++) {
      final v = gm.rolled[i];
      var alpha = 1.0;
      if (isDouble) {
        // дубль: две кости, пока осталось больше двух ходов — обе яркие
        alpha = remaining.length > i * 2 ? 1.0 : 0.35;
      } else {
        final idx = remaining.indexOf(v);
        if (idx >= 0) {
          remaining.removeAt(idx);
        } else {
          alpha = 0.35;
        }
      }
      final base = Offset(cx + (i == 0 ? -1 : 1) * size * 0.62, y);
      final t = rollT;
      var shown = v;
      var angle = 0.0;
      var pos = base;
      var sz = size;
      if (t < 1) {
        final spin = (1 - Curves.easeOut.transform(t)) * (i == 0 ? 1 : -1) * pi * 3;
        angle = spin;
        sz = size * (0.7 + 0.3 * Curves.easeOutBack.transform(t.clamp(0.0, 1.0)));
        pos = base + Offset(0, -(1 - t) * g.c * 1.2 * sin(t * pi * 2).abs());
        if (t < 0.75) {
          shown = Random(((t * 14).floor() + 1) * 31 + i * 7 + gm.turn).nextInt(6) + 1;
        }
      }
      _die(cv, pos, sz, shown, angle, alpha, gm.pl == 1);
    }
    if (isDouble && gm.dice.isNotEmpty && rollT >= 1) {
      _label(
        cv,
        Offset(cx + size * 1.5, y),
        '×${gm.dice.length}',
        const Color(0xFF3A200F),
        g.c * 0.62,
      );
    }
  }

  // ----- основной рисунок -----

  @override
  void paint(Canvas canvas, Size s) {
    final g = geo;
    if (cache.pic == null || cache.size != s) {
      final rec = ui.PictureRecorder();
      _paintBackground(Canvas(rec));
      cache.pic = rec.endRecording();
      cache.size = s;
    }
    canvas.drawPicture(cache.pic!);

    final b = game.board;
    final pulseA = 0.5 + 0.5 * sin(pulse * 2 * pi);

    // подсветка выбранного пункта и пунктов назначения
    if (sel != null && sel! < 24) {
      canvas.drawRect(
        g.pointRect(sel!),
        Paint()..color = const Color(0xFFFFD54F).withValues(alpha: 0.2),
      );
    }
    for (final d in dests) {
      if (d >= 0 && d < 24) {
        canvas.drawRect(
          g.pointRect(d),
          Paint()..color = const Color(0xFF7CE08A).withValues(alpha: 0.16 + 0.1 * pulseA),
        );
      } else if (d == -1) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(g.trayRect(myPl), Radius.circular(g.c * 0.12)),
          Paint()..color = const Color(0xFF7CE08A).withValues(alpha: 0.2 + 0.15 * pulseA),
        );
      }
    }

    // шашки на пунктах
    for (var idx = 0; idx < 24; idx++) {
      final v = b.p[idx];
      if (v == 0) continue;
      final pl = v > 0 ? 0 : 1;
      final cnt = v.abs();
      for (var i = 0; i < cnt; i++) {
        if (slide != null && slide!.dest == idx && slide!.toIdx == i && slide!.pl == pl) {
          continue; // эта шашка сейчас в полёте
        }
        final pos = g.slot(idx, i, cnt);
        _checker(canvas, pos, g.r, pl);
        if (i == cnt - 1 && cnt > 5) {
          _label(
            canvas,
            pos,
            '$cnt',
            pl == 0 ? const Color(0xFF3A2A10) : const Color(0xFFF1E6C8),
            g.r * 1.1,
          );
        }
      }
    }
    // бар
    for (final pl in [0, 1]) {
      final cnt = b.bar[pl];
      for (var i = 0; i < cnt; i++) {
        _checker(canvas, g.barSlot(pl, i, cnt), g.r, pl);
      }
    }
    // выброшенные
    for (final pl in [0, 1]) {
      for (var i = 0; i < b.off[pl]; i++) {
        if (slide != null && slide!.dest == -1 && slide!.toIdx == i && slide!.pl == pl) {
          continue;
        }
        _pill(canvas, g.traySlot(pl, i), pl);
      }
    }

    // шашки, которыми можно ходить, и их выбор
    for (final src in sources) {
      final Offset pos;
      if (src == 24) {
        final n = b.bar[myPl];
        pos = g.barSlot(myPl, n - 1, n);
      } else {
        final n = b.own(src, myPl);
        pos = g.slot(src, n - 1, n);
      }
      final chosen = src == sel;
      canvas.drawCircle(
        pos,
        g.r * (chosen ? 1.18 : 1.1 + 0.06 * pulseA),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = chosen ? g.r * 0.22 : g.r * 0.14
          ..color = const Color(0xFFFFC83D).withValues(alpha: chosen ? 0.95 : 0.45 + 0.4 * pulseA),
      );
    }
    // куда можно поставить
    for (final d in dests) {
      if (d < 0 || d > 23) continue;
      final cnt = b.own(d, myPl);
      final pos = g.slot(d, cnt, cnt + 1);
      canvas.drawCircle(
        pos,
        g.r * (0.7 + 0.12 * pulseA),
        Paint()..color = const Color(0xFF5CD66E).withValues(alpha: 0.35 + 0.25 * pulseA),
      );
      canvas.drawCircle(
        pos,
        g.r * 0.7,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = const Color(0xFF2E9E4F),
      );
    }

    // летящая шашка
    final sl = slide;
    if (sl != null) {
      final from = sl.from == 24
          ? g.barSlot(sl.pl, sl.fromCount - 1, sl.fromCount)
          : g.slot(sl.from, sl.fromCount - 1, sl.fromCount);
      final to = sl.dest == -1
          ? g.traySlot(sl.pl, sl.toIdx)
          : g.slot(sl.dest, sl.toIdx, b.own(sl.dest, sl.pl));
      final p = Offset.lerp(from, to, slideT)!;
      _checker(canvas, p, g.r, sl.pl, lift: sin(slideT * pi) * 0.8);
    }

    _dice(canvas);
  }

  @override
  bool shouldRepaint(_NardyPainter old) => true;
}
