// SPDX-License-Identifier: AGPL-3.0-or-later

// DVChat: экран шахмат. Два режима:
//  - с компьютером (без интернета, всегда в полную силу, думает в отдельном потоке);
//  - с другом (room + gameId + hostId), ходы идут через личный чат; пригласивший играет белыми.
// Касаешься своей фигуры, подсвечиваются доступные клетки, касаешься клетки, и фигура плавно идёт.
// Доска деревянная, фигуры нарисованы кодом. Мат, пат, ничья по правилам и повторению ходов.

import 'dart:async';

import 'package:dvchat/pages/games/chess_logic.dart';
import 'package:dvchat/pages/games/dv_game_net.dart';
import 'package:dvchat/pages/games/dv_game_sound.dart';
import 'package:dvchat/utils/dv_nicknames.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

class _Move {
  const _Move(this.move, this.sender);

  final int move;
  final String sender;
}

class ChessPage extends StatefulWidget {
  const ChessPage({this.level, this.room, this.gameId, this.hostId, super.key});

  /// Не используется: уровней сложности нет (параметр оставлен для общего вида игр)
  final int? level;

  /// Для игры с другом
  final Room? room;
  final String? gameId;
  final String? hostId;

  @override
  State<ChessPage> createState() => _ChessPageState();
}

class _ChessPageState extends State<ChessPage> {
  ChessState _s = ChessState.start();
  List<String> _keys = [ChessState.start().key];
  List<int> _legal = Chess.legalMoves(ChessState.start());
  int _plies = 0;
  int _lastMove = 0;
  ChessEnd _end = ChessEnd.none;
  int? _selected;
  int _animId = 0;
  int? _animFrom;
  int? _animTo;
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

  /// 1 белые, 2 чёрные
  int get _mine =>
      _online ? (widget.hostId == _me ? 1 : 2) : (_humanFirst ? 1 : 2);

  bool get _finished => _surrenderBy != null || _end != ChessEnd.none;

  bool get _myTurn => _s.white == (_mine == 1);

  /// Победившая сторона: 1 белые, 2 чёрные, 0 ничья
  int get _winnerSide {
    if (_surrenderBy != null) return _surrenderBy == _me ? 3 - _mine : _mine;
    if (_end == ChessEnd.mate) return _s.white ? 2 : 1;
    return 0;
  }

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

  static ChessEnd _endOf(ChessState s, List<String> keys) {
    final e = Chess.end(s);
    if (e != ChessEnd.none) return e;
    final k = keys.last;
    return keys.where((x) => x == k).length >= 3 ? ChessEnd.repeat : e;
  }

  int _pieceCount() => _s.b.where((v) => v != 0).length;

  void _soundFor(int oldPlies, bool wasFinished, int oldPieces) {
    if (!wasFinished && _finished) {
      final w = _winnerSide;
      final sound = w == 0
          ? DvSound.miss
          : (w == _mine ? DvSound.win : DvSound.lose);
      unawaited(DvGameSound.play(sound));
    } else if (_plies > oldPlies) {
      final mineMove = _plies.isOdd == (_mine == 1);
      final sound = _pieceCount() < oldPieces
          ? DvSound.hit
          : (mineMove ? DvSound.place : DvSound.enemy);
      unawaited(DvGameSound.play(sound));
    }
  }

  /// Локально выполняет ход (игра с компьютером)
  void _play(int m) {
    final oldPlies = _plies;
    final wasFinished = _finished;
    final oldPieces = _pieceCount();
    final n = Chess.apply(_s, m);
    final keys = [..._keys, n.key];
    setState(() {
      _s = n;
      _keys = keys;
      _plies++;
      _lastMove = m;
      _animId++;
      _animFrom = m & 63;
      _animTo = (m >> 6) & 63;
      _selected = null;
      _end = _endOf(n, keys);
      _legal = _end == ChessEnd.none ? Chess.legalMoves(n) : const [];
    });
    _soundFor(oldPlies, wasFinished, oldPieces);
  }

  // ---------------- сетевая часть ----------------

  bool _ingest(Event e) {
    if (e.type != DvGameNet.eventType || e.roomId != widget.room?.id) {
      return false;
    }
    final c = e.content;
    if (c['game'] != 'chess' || '${c['id']}' != widget.gameId) return false;
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
    final m = c['cell'];
    if (n is! int || m is! int || m < 0 || m > 32767) return false;
    if (_moves.containsKey(n)) return false;
    _moves[n] = _Move(m, e.senderId);
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
    _rebuild(silent: true);
  }

  /// Заново проигрывает партию по полученным ходам, проверяя очерёдность и правила
  void _rebuild({bool silent = false}) {
    var s = ChessState.start();
    final keys = [s.key];
    var n = 0;
    var lm = 0;
    String? last;
    var end = ChessEnd.none;
    while (_moves.containsKey(n)) {
      final mv = _moves[n]!;
      final fromHost = mv.sender == widget.hostId;
      if (n.isEven != fromHost) break;
      if (!Chess.legalMoves(s).contains(mv.move)) break;
      s = Chess.apply(s, mv.move);
      keys.add(s.key);
      lm = mv.move;
      last = mv.sender;
      n++;
      end = _endOf(s, keys);
      if (end != ChessEnd.none) break;
    }
    _lastSender = last;
    if (!mounted) return;
    final oldPlies = _plies;
    final wasFinished = _finished;
    final oldPieces = _pieceCount();
    setState(() {
      if (n == oldPlies + 1 && !silent) {
        _animId++;
        _animFrom = lm & 63;
        _animTo = (lm >> 6) & 63;
      } else if (n != oldPlies) {
        _animFrom = null;
        _animTo = null;
      }
      _s = s;
      _keys = keys;
      _plies = n;
      _lastMove = lm;
      _end = end;
      _selected = null;
      _legal = end == ChessEnd.none ? Chess.legalMoves(s) : const [];
    });
    if (!silent) _soundFor(oldPlies, wasFinished, oldPieces);
    _maybeSendEnd();
  }

  void _maybeSendEnd() {
    if (!_online || _endSent || !_finished || _surrenderBy != null) return;
    if (_lastSender != _me) return;
    _endSent = true;
    unawaited(
      DvGameNet.sendEnd(
        widget.room!,
        game: 'chess',
        id: widget.gameId!,
        winner: _end == ChessEnd.mate ? _me : '',
      ).catchError((_) => null),
    );
  }

  // ---------------- ходы ----------------

  Future<int?> _askPromo() => showModalBottomSheet<int>(
    context: context,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Превратить пешку в…',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                for (final t in const [5, 4, 3, 2])
                  InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => Navigator.pop(context, t),
                    child: Container(
                      width: 64,
                      height: 64,
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFFF2E0B9), Color(0xFFB98A55)],
                        ),
                      ),
                      child: CustomPaint(
                        painter: ChessPiecePainter(t, _mine == 1),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    ),
  );

  Future<void> _tapSquare(int sq) async {
    if (_loading || _busy || _finished || !_myTurn) return;
    final sel = _selected;
    if (sel != null) {
      final cands = [
        for (final m in _legal)
          if ((m & 63) == sel && ((m >> 6) & 63) == sq) m,
      ];
      if (cands.isNotEmpty) {
        var m = cands.first;
        if (cands.length > 1) {
          final p = await _askPromo();
          if (p == null || !mounted) return;
          m = cands.firstWhere((x) => ((x >> 12) & 7) == p);
        }
        await _commit(m);
        return;
      }
    }
    final v = _s.b[sq];
    final own = v != 0 && (v > 0) == (_mine == 1);
    setState(() => _selected = own && sq != sel ? sq : null);
  }

  Future<void> _commit(int m) async {
    if (_online) {
      final n = _plies;
      _moves[n] = _Move(m, _me);
      _rebuild();
      try {
        await DvGameNet.sendMove(
          widget.room!,
          game: 'chess',
          id: widget.gameId!,
          n: n,
          cell: m,
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
    _play(m);
    await _aiTurn();
  }

  Future<void> _aiTurn() async {
    if (_finished || _busy) return;
    final aiWhite = !_humanFirst;
    if (_s.white != aiWhite) return;
    setState(() => _busy = true);
    final data = [
      ..._s.toList(),
      1500,
      DateTime.now().microsecondsSinceEpoch & 0xFFFFFF,
    ];
    var m = 0;
    try {
      m = await compute(chessAiEntry, data);
    } catch (_) {
      m = 0;
    }
    if (!mounted) return;
    if (m == 0 || !_legal.contains(m)) {
      // На случай сбоя в потоке: первый допустимый ход
      m = _legal.isEmpty ? 0 : _legal.first;
    }
    setState(() => _busy = false);
    if (m != 0) _play(m);
  }

  Future<void> _again() async {
    if (_online) {
      try {
        final id = await DvGameNet.sendInvite(
          widget.room!,
          game: 'chess',
          gameTitle: 'шахматы',
          announce: false,
        );
        if (!mounted) return;
        await Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) =>
                ChessPage(room: widget.room, gameId: id, hostId: _me),
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
    final s = ChessState.start();
    setState(() {
      _humanFirst = !_humanFirst;
      _s = s;
      _keys = [s.key];
      _legal = Chess.legalMoves(s);
      _plies = 0;
      _lastMove = 0;
      _end = ChessEnd.none;
      _selected = null;
      _animFrom = null;
      _animTo = null;
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
    switch (_end) {
      case ChessEnd.mate:
        return _winnerSide == _mine
            ? 'Мат! Вы победили 🎉'
            : 'Мат. Вы проиграли';
      case ChessEnd.stalemate:
        return 'Пат. Ничья';
      case ChessEnd.fifty:
        return 'Ничья: 50 ходов без взятий';
      case ChessEnd.material:
        return 'Ничья: не хватает фигур для мата';
      case ChessEnd.repeat:
        return 'Ничья: тройное повторение';
      case ChessEnd.none:
        break;
    }
    final check = Chess.inCheck(_s);
    if (_myTurn) return check ? 'Шах! Ваш ход' : 'Ваш ход';
    return _online ? 'Ход соперника…' : 'Компьютер думает…';
  }

  /// Съеденные фигуры цвета white, дорогие первыми
  List<int> _captured(bool white) {
    const full = {5: 1, 4: 2, 3: 2, 2: 2, 1: 8};
    final have = <int, int>{};
    for (final v in _s.b) {
      if (v != 0 && (v > 0) == white) {
        have[v.abs()] = (have[v.abs()] ?? 0) + 1;
      }
    }
    return [
      for (final e in full.entries)
        for (var i = 0; i < e.value - (have[e.key] ?? 0); i++) e.key,
    ];
  }

  Widget _chip(ThemeData theme, String name, bool white, bool active) {
    final color = theme.colorScheme.primary;
    final lost = _captured(white);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: active ? color.withValues(alpha: 0.16) : null,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: active ? color : theme.colorScheme.outlineVariant,
          width: active ? 2 : 1,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 24,
                height: 24,
                child: CustomPaint(painter: ChessPiecePainter(6, white)),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          SizedBox(
            height: 16,
            child: Row(
              children: [
                for (final t in lost)
                  SizedBox(
                    width: 11,
                    height: 16,
                    child: CustomPaint(painter: ChessPiecePainter(t, white)),
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
        ? 'Шахматы · ${widget.room!.dvDisplayname()}'
        : 'Шахматы';
    final mineWhite = _mine == 1;
    final playing = !_loading && !_finished;
    final oppName = _online ? widget.room!.dvDisplayname() : 'Компьютер';
    final sel = _selected;
    return Scaffold(
      appBar: AppBar(title: Text(title), actions: const [DvSoundButton()]),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Row(
                    children: [
                      Expanded(
                        child: _chip(
                          theme,
                          'Вы',
                          mineWhite,
                          playing && _s.white == mineWhite,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _chip(
                          theme,
                          oppName,
                          !mineWhite,
                          playing && _s.white != mineWhite,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Text(_status, style: theme.textTheme.titleLarge),
                const SizedBox(height: 16),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: _ChessBoard(
                    b: _s.b,
                    flip: !mineWhite,
                    selected: sel,
                    targets: [
                      if (sel != null)
                        for (final m in _legal)
                          if ((m & 63) == sel) (m >> 6) & 63,
                    ],
                    lastFrom: _lastMove == 0 ? null : _lastMove & 63,
                    lastTo: _lastMove == 0 ? null : (_lastMove >> 6) & 63,
                    checkSq: Chess.inCheck(_s)
                        ? Chess.kingSq(_s.b, _s.white)
                        : null,
                    animId: _animId,
                    animFrom: _animFrom,
                    animTo: _animTo,
                    onTap: _tapSquare,
                  ),
                ),
                const SizedBox(height: 22),
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

class _ChessBoard extends StatelessWidget {
  const _ChessBoard({
    required this.b,
    required this.flip,
    required this.selected,
    required this.targets,
    required this.lastFrom,
    required this.lastTo,
    required this.checkSq,
    required this.animId,
    required this.animFrom,
    required this.animTo,
    required this.onTap,
  });

  final List<int> b;
  final bool flip;
  final int? selected;
  final List<int> targets;
  final int? lastFrom;
  final int? lastTo;
  final int? checkSq;
  final int animId;
  final int? animFrom;
  final int? animTo;
  final void Function(int) onTap;

  /// Где клетка sq на экране: (ряд, столбец) с учётом переворота доски
  (int, int) _view(int sq) {
    final r = sq >> 3;
    final c = sq & 7;
    return flip ? (7 - r, 7 - c) : (r, c);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(7),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF6E4625), Color(0xFF45290F)],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(80),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, c) {
          final cs = c.maxWidth / 8;
          final cells = <Widget>[];
          final pieces = <Widget>[];
          Widget? moving;
          for (var vr = 0; vr < 8; vr++) {
            for (var vc = 0; vc < 8; vc++) {
              final r = flip ? 7 - vr : vr;
              final col = flip ? 7 - vc : vc;
              final sq = r * 8 + col;
              final dark = (r + col).isOdd;
              var wood = dark
                  ? const [Color(0xFF9C6C3C), Color(0xFF774B25)]
                  : const [Color(0xFFF2E0B9), Color(0xFFE1C795)];
              if (sq == lastFrom || sq == lastTo) {
                wood = [
                  for (final x in wood)
                    Color.alphaBlend(const Color(0x66FFD54F), x),
                ];
              }
              if (sq == selected) {
                wood = [
                  for (final x in wood)
                    Color.alphaBlend(const Color(0x9958D26B), x),
                ];
              }
              final label = dark
                  ? const Color(0xFFF2E0B9)
                  : const Color(0xFF9C6C3C);
              cells.add(
                Positioned(
                  left: vc * cs,
                  top: vr * cs,
                  width: cs,
                  height: cs,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: wood,
                      ),
                    ),
                    child: Stack(
                      children: [
                        if (sq == checkSq)
                          Positioned.fill(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: RadialGradient(
                                  colors: [
                                    const Color(0xFFFF3B30).withAlpha(230),
                                    const Color(0xFFFF3B30).withAlpha(0),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        if (vc == 0)
                          Positioned(
                            left: cs * 0.06,
                            top: cs * 0.03,
                            child: Text(
                              '${8 - r}',
                              style: TextStyle(
                                fontSize: cs * 0.19,
                                fontWeight: FontWeight.bold,
                                color: label,
                              ),
                            ),
                          ),
                        if (vr == 7)
                          Positioned(
                            right: cs * 0.06,
                            bottom: cs * 0.03,
                            child: Text(
                              'abcdefgh'[col],
                              style: TextStyle(
                                fontSize: cs * 0.19,
                                fontWeight: FontWeight.bold,
                                color: label,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              );
              final v = b[sq];
              if (v == 0) continue;
              final piece = Padding(
                padding: EdgeInsets.all(cs * 0.05),
                child: CustomPaint(painter: ChessPiecePainter(v.abs(), v > 0)),
              );
              if (sq == animTo && animFrom != null) {
                final (fr, fc) = _view(animFrom!);
                moving = Positioned(
                  left: vc * cs,
                  top: vr * cs,
                  width: cs,
                  height: cs,
                  child: TweenAnimationBuilder<double>(
                    key: ValueKey('mv$animId'),
                    tween: Tween(begin: 0, end: 1),
                    duration: const Duration(milliseconds: 260),
                    curve: Curves.easeOutCubic,
                    builder: (context, t, child) => Transform.translate(
                      offset: Offset(
                        (fc - vc) * cs * (1 - t),
                        (fr - vr) * cs * (1 - t),
                      ),
                      child: child,
                    ),
                    child: piece,
                  ),
                );
              } else {
                pieces.add(
                  Positioned(
                    left: vc * cs,
                    top: vr * cs,
                    width: cs,
                    height: cs,
                    child: piece,
                  ),
                );
              }
            }
          }
          final marks = <Widget>[];
          for (final sq in targets) {
            final (vr, vc) = _view(sq);
            final capture =
                b[sq] != 0 ||
                (b[selected ?? 0].abs() == 1 && (selected! & 7) != (sq & 7));
            marks.add(
              Positioned(
                left: vc * cs,
                top: vr * cs,
                width: cs,
                height: cs,
                child: Center(
                  child: capture
                      ? Container(
                          width: cs * 0.92,
                          height: cs * 0.92,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.black.withAlpha(95),
                              width: cs * 0.07,
                            ),
                          ),
                        )
                      : Container(
                          width: cs * 0.3,
                          height: cs * 0.3,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.black.withAlpha(70),
                          ),
                        ),
                ),
              ),
            );
          }
          return ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (d) {
                final vc = (d.localPosition.dx / cs).floor().clamp(0, 7);
                final vr = (d.localPosition.dy / cs).floor().clamp(0, 7);
                final r = flip ? 7 - vr : vr;
                final col = flip ? 7 - vc : vc;
                onTap(r * 8 + col);
              },
              child: SizedBox(
                width: c.maxWidth,
                height: c.maxWidth,
                child: Stack(
                  children: [...cells, ...pieces, ?moving, ...marks],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Фигуры рисуются кодом: каждая собрана из простых частей в клетке 100 на 100
/// (r: скруглённый прямоугольник x y ширина высота радиус; c: круг x y радиус; p: контур M L C Z)
const Map<int, List<String>> _shapeData = {
  1: [
    'c 50 31 12.5',
    'r 38 43 24 7 3.5',
    'p M 41 49 L 59 49 C 60 60 66 68 69 76 L 31 76 C 34 68 40 60 41 49 Z',
    'r 24 82 52 9 4.5',
    'r 30 74 40 10 4',
  ],
  2: [
    'p M 29 76 C 29 62 38 56 43 47 C 37 47 33 49 29 52 L 21 47 C 21 40 29 31 35 26 L 35 17 L 42 22 C 44 20 46 18 49 15 L 51 24 C 65 28 73 42 71 58 L 69 76 Z',
    'r 24 82 52 9 4.5',
    'r 30 74 40 10 4',
  ],
  3: [
    'p M 50 12 C 63 24 67 38 59 50 L 41 50 C 33 38 37 24 50 12 Z',
    'c 50 11 5',
    'r 36 48 28 7 3.5',
    'p M 41 54 L 59 54 C 60 62 66 68 69 76 L 31 76 C 34 68 40 62 41 54 Z',
    'r 24 82 52 9 4.5',
    'r 30 74 40 10 4',
  ],
  4: [
    'p M 31 20 L 40 20 L 40 26 L 46 26 L 46 20 L 54 20 L 54 26 L 60 26 L 60 20 L 69 20 L 69 38 L 31 38 Z',
    'r 34 36 32 7 3',
    'p M 37 42 L 63 42 L 67 76 L 33 76 Z',
    'r 24 82 52 9 4.5',
    'r 30 74 40 10 4',
  ],
  5: [
    'p M 34 64 L 23 27 L 33 41 L 37 19 L 44 38 L 50 14 L 56 38 L 63 19 L 67 41 L 77 27 L 66 64 Z',
    'c 23 25 4.2',
    'c 37 17 4.2',
    'c 50 12 4.2',
    'c 63 17 4.2',
    'c 77 25 4.2',
    'r 31 60 38 8 4',
    'p M 36 66 L 64 66 L 68 76 L 32 76 Z',
    'r 24 82 52 9 4.5',
    'r 30 74 40 10 4',
  ],
  6: [
    'r 46 5 8 27 2.5',
    'r 39 12 22 8 2.5',
    'p M 35 74 L 36 46 C 34 36 43 31 50 38 C 57 31 66 36 64 46 L 65 74 Z',
    'r 33 58 34 8 4',
    'r 24 82 52 9 4.5',
    'r 30 74 40 10 4',
  ],
};

class ChessPiecePainter extends CustomPainter {
  ChessPiecePainter(this.type, this.white);

  /// 1 пешка, 2 конь, 3 слон, 4 ладья, 5 ферзь, 6 король
  final int type;
  final bool white;

  static final Map<int, Path> _cache = {};

  static Path _shape(int t) => _cache[t] ??= _build(t);

  static Path _build(int t) {
    Path? all;
    for (final part in _shapeData[t]!) {
      final tok = part.split(' ');
      final n = <double>[
        for (final x in tok.skip(1))
          if (double.tryParse(x) != null) double.parse(x),
      ];
      final Path p = Path();
      switch (tok.first) {
        case 'r':
          p.addRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(n[0], n[1], n[2], n[3]),
              Radius.circular(n[4]),
            ),
          );
        case 'c':
          p.addOval(Rect.fromCircle(center: Offset(n[0], n[1]), radius: n[2]));
        default:
          var i = 1;
          while (i < tok.length) {
            final cmd = tok[i++];
            double next() => double.parse(tok[i++]);
            switch (cmd) {
              case 'M':
                p.moveTo(next(), next());
              case 'L':
                p.lineTo(next(), next());
              case 'C':
                p.cubicTo(next(), next(), next(), next(), next(), next());
              case 'Z':
                p.close();
            }
          }
      }
      all = all == null ? p : Path.combine(PathOperation.union, all, p);
    }
    return all!;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.shortestSide / 100;
    canvas.save();
    canvas.translate((size.width - 100 * k) / 2, (size.height - 100 * k) / 2);
    canvas.scale(k);
    final path = _shape(type);
    final box = const Rect.fromLTWH(0, 0, 100, 100);
    // Тень под фигурой
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(50, 90), width: 64, height: 9),
      Paint()
        ..color = Colors.black.withAlpha(75)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    canvas.drawPath(
      path,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: white
              ? const [Color(0xFFFFFCF3), Color(0xFFCFC29F)]
              : const [Color(0xFF6A6A76), Color(0xFF121216)],
        ).createShader(box),
    );
    // Блик слева
    canvas.save();
    canvas.clipPath(path);
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, 56, 100),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            Colors.white.withAlpha(white ? 110 : 55),
            Colors.white.withAlpha(0),
          ],
        ).createShader(const Rect.fromLTWH(0, 0, 56, 100)),
    );
    canvas.restore();
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeJoin = StrokeJoin.round
        ..color = white ? const Color(0xFF5B4426) : const Color(0xFF000000),
    );
    // Глаз коня
    if (type == 2) {
      canvas.drawCircle(
        const Offset(41, 31),
        2.3,
        Paint()..color = white ? const Color(0xFF5B4426) : Colors.white70,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(ChessPiecePainter old) =>
      old.type != type || old.white != white;
}
