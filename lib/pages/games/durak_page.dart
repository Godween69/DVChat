// SPDX-License-Identifier: AGPL-3.0-or-later

// DVChat: экран «Дурак» на двоих, подкидной или переводной. Два режима:
//  - с компьютером (без интернета);
//  - с другом (room + gameId + hostId): колода в обоих телефонах раздаётся одинаково по номеру
//    партии, а через личный чат уходят только действия (выложил, побил, беру, бито, перевёл).
// Карты нарисованы кодом. Внизу ваша рука, на сукне стол, сверху колода с козырем и бито.

import 'package:dvchat/pages/games/dv_local_stats.dart';
import 'dart:async';
import 'dart:math';

import 'package:dvchat/pages/games/dv_game_net.dart';
import 'package:dvchat/pages/games/dv_game_sound.dart';
import 'package:dvchat/pages/games/durak_logic.dart';
import 'package:dvchat/utils/dv_nicknames.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

class _Move {
  const _Move(this.code, this.sender);

  final int code;
  final String sender;
}

class DurakPage extends StatefulWidget {
  const DurakPage({
    this.mode,
    this.level,
    this.room,
    this.gameId,
    this.hostId,
    super.key,
  });

  /// 'podkid' (подкидной) или 'perevod' (переводной); в сетевой партии берётся из приглашения
  final String? mode;

  /// Не используется: уровней сложности нет (параметр оставлен для общего вида игр)
  final int? level;

  /// Для игры с другом
  final Room? room;
  final String? gameId;
  final String? hostId;

  @override
  State<DurakPage> createState() => _DurakPageState();
}

class _DurakPageState extends State<DurakPage> {
  late String _mode;
  late int _seed;
  late DkState _s;
  int _plies = 0;
  int _lastMover = -1;
  int _lastOp = 0;
  int? _sel;
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
  int get _myIdx => _online && widget.hostId != _me ? 1 : 0;
  int get _oppIdx => 1 - _myIdx;

  bool get _finished => _surrenderBy != null || _s.result >= 0;

  bool get _myTurn => !_loading && !_busy && !_finished && _s.turn == _myIdx;

  @override
  void initState() {
    super.initState();
    DvLocalStats.open('durak', offline: widget.room == null);
    _mode = widget.mode ?? 'podkid';
    _seed = _online
        ? Dk.seedOf(widget.gameId!)
        : (DateTime.now().microsecondsSinceEpoch % 2147483646) + 1;
    _s = DkState.start(_seed, _mode);
    if (_online) {
      _loading = true;
      _sub = widget.room!.client.onTimelineEvent.stream.listen((e) {
        if (_ingest(e)) _rebuild();
      });
      DvGameNet.activeGameId = widget.gameId;
      unawaited(_load());
    } else {
      // Первый ход компьютера (если он нападает первым) запускаем после построения экрана
      unawaited(Future.microtask(_aiLoop));
    }
  }

  @override
  void dispose() {
    if (DvGameNet.activeGameId == widget.gameId) {
      DvGameNet.activeGameId = null;
    }
    _sub?.cancel();
    DvLocalStats.close('durak');
    super.dispose();
  }

  // ---------------- звук ----------------

  void _sound(int oldPlies, bool wasFinished) {
    if (!wasFinished && _finished) {
      final r = _s.result;
      final sound = _surrenderBy != null
          ? (_surrenderBy == _me ? DvSound.lose : DvSound.win)
          : (r == 2
                ? DvSound.miss
                : (r == _myIdx ? DvSound.win : DvSound.lose));
      unawaited(DvGameSound.play(sound));
    } else if (_plies > oldPlies) {
      final sound = _lastOp == Dk.opTake
          ? DvSound.hit
          : (_lastMover == _myIdx ? DvSound.place : DvSound.enemy);
      unawaited(DvGameSound.play(sound));
    }
  }

  // ---------------- сетевая часть ----------------

  bool _ingest(Event e) {
    if (e.type != DvGameNet.eventType || e.roomId != widget.room?.id) {
      return false;
    }
    final c = e.content;
    if (c['game'] != 'durak' || '${c['id']}' != widget.gameId) return false;
    if (c['kind'] == 'invite') {
      final m = c['mode'];
      if (m is String && (m == 'podkid' || m == 'perevod')) _mode = m;
      return false;
    }
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
      final tl = await widget.room!.getTimeline(limit: 500);
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

  /// Заново проигрывает партию по полученным действиям
  void _rebuild({bool silent = false}) {
    var s = DkState.start(_seed, _mode);
    var n = 0;
    String? last;
    var mover = -1;
    var op = 0;
    while (_moves.containsKey(n)) {
      final mv = _moves[n]!;
      final idx = mv.sender == widget.hostId ? 0 : 1;
      if (idx != s.turn) break;
      if (!s.legalMoves().contains(mv.code)) break;
      mover = idx;
      op = Dk.opOf(mv.code);
      s = s.apply(mv.code);
      last = mv.sender;
      n++;
      if (s.result >= 0) break;
    }
    _lastSender = last;
    if (!mounted) return;
    final oldPlies = _plies;
    final wasFinished = _finished;
    setState(() {
      _s = s;
      _plies = n;
      _lastMover = mover;
      _lastOp = op;
      _sel = null;
    });
    if (!silent) _sound(oldPlies, wasFinished);
    _maybeSendEnd();
  }

  void _maybeSendEnd() {
    if (!_online || _endSent || !_finished || _surrenderBy != null) return;
    if (_lastSender != _me) return;
    _endSent = true;
    final r = _s.result;
    final guestId = widget.hostId == _me
        ? (widget.room!.directChatMatrixID ?? '')
        : _me;
    final winner = r == 2 ? '' : (r == 0 ? (widget.hostId ?? '') : guestId);
    unawaited(
      DvGameNet.sendEnd(
        widget.room!,
        game: 'durak',
        id: widget.gameId!,
        winner: winner,
      ).catchError((_) => null),
    );
  }

  // ---------------- действия ----------------

  Future<void> _do(int code) async {
    if (!_myTurn) return;
    if (_online) {
      final n = _plies;
      _moves[n] = _Move(code, _me);
      _rebuild();
      try {
        await DvGameNet.sendMove(
          widget.room!,
          game: 'durak',
          id: widget.gameId!,
          n: n,
          cell: code,
          fin: _s.result >= 0,
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
    _applyLocal(code);
    unawaited(_aiLoop());
  }

  void _applyLocal(int code) {
    final oldPlies = _plies;
    final wasFinished = _finished;
    final mover = _s.turn;
    setState(() {
      _s = _s.apply(code);
      _plies++;
      _lastMover = mover;
      _lastOp = Dk.opOf(code);
      _sel = null;
    });
    _sound(oldPlies, wasFinished);
  }

  Future<void> _aiLoop() async {
    if (_busy) return;
    while (mounted && !_finished && _s.turn == 1) {
      setState(() => _busy = true);
      await Future<void>.delayed(const Duration(milliseconds: 800));
      if (!mounted) return;
      final m = DkAi.move(_s, 1);
      setState(() => _busy = false);
      _applyLocal(m);
    }
    if (mounted && _busy) setState(() => _busy = false);
  }

  Future<void> _again() async {
    if (_online) {
      try {
        final id = await DvGameNet.sendInvite(
          widget.room!,
          game: 'durak',
          gameTitle: 'дурак',
          announce: false,
          extra: {'mode': _mode},
        );
        if (!mounted) return;
        await Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => DurakPage(
              mode: _mode,
              room: widget.room,
              gameId: id,
              hostId: _me,
            ),
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
      _seed = (DateTime.now().microsecondsSinceEpoch % 2147483646) + 1;
      _s = DkState.start(_seed, _mode);
      _plies = 0;
      _lastMover = -1;
      _sel = null;
    });
    unawaited(_aiLoop());
  }

  // ---------------- нажатия ----------------

  Set<int> _movableCards(List<int> moves) => {
    for (final m in moves)
      if (Dk.opOf(m) != Dk.opTake && Dk.opOf(m) != Dk.opPass) Dk.cardOf(m),
  };

  void _tapCard(int card) {
    if (!_myTurn) return;
    final moves = _s.legalMoves();
    if (_s.phase != 1) {
      final m = Dk.mk(Dk.opAdd, card);
      if (moves.contains(m)) unawaited(_do(m));
      return;
    }
    final slots = [
      for (var i = 0; i < _s.atk.length; i++)
        if (moves.contains(Dk.mk(Dk.opBeat, card, i))) i,
    ];
    final canTrans = moves.contains(Dk.mk(Dk.opTrans, card));
    if (slots.length == 1 && !canTrans) {
      unawaited(_do(Dk.mk(Dk.opBeat, card, slots.first)));
    } else if (slots.isEmpty && canTrans) {
      unawaited(_do(Dk.mk(Dk.opTrans, card)));
    } else if (slots.isNotEmpty || canTrans) {
      setState(() => _sel = _sel == card ? null : card);
    }
  }

  void _tapTable(int i) {
    final sel = _sel;
    if (sel == null || !_myTurn) return;
    final m = Dk.mk(Dk.opBeat, sel, i);
    if (_s.legalMoves().contains(m)) unawaited(_do(m));
  }

  // ---------------- вид ----------------

  String get _status {
    if (_loading) return 'Загрузка…';
    if (_surrenderBy != null) {
      return _surrenderBy == _me
          ? 'Вы сдались'
          : 'Соперник сдался. Вы победили! 🎉';
    }
    final r = _s.result;
    if (r == 2) return 'Ничья';
    if (r >= 0) {
      return r == _myIdx ? 'Вы победили! 🎉' : 'Вы остались в дураках 🃏';
    }
    if (_s.turn != _myIdx) {
      return _online ? 'Ход соперника…' : 'Компьютер думает…';
    }
    if (_s.phase == 1) {
      return _mode == 'perevod'
          ? 'Отбейте, переведите или возьмите'
          : 'Отбейте карту или возьмите';
    }
    if (_s.atk.isEmpty) return 'Ваш ход: атакуйте';
    return _s.phase == 2
        ? 'Подкиньте ещё или нажмите «Готово»'
        : 'Подкиньте ещё или нажмите «Бито»';
  }

  Widget _chip(ThemeData theme, String name, int count, bool active) {
    final color = theme.colorScheme.primary;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
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
          Flexible(
            child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(width: 8),
          Icon(Icons.style, size: 16, color: color),
          const SizedBox(width: 3),
          Text(
            '$count',
            style: TextStyle(color: color, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _opponentFan(double cw) {
    final n = _s.hands[_oppIdx].length;
    final w = cw * 0.55;
    final step = n <= 1 ? 0.0 : min(w * 0.45, (cw * 4.2 - w) / (n - 1));
    return SizedBox(
      width: w + step * max(0, n - 1),
      height: w * 1.4,
      child: Stack(
        children: [
          for (var i = 0; i < n; i++)
            Positioned(left: i * step, child: DkBack(w)),
        ],
      ),
    );
  }

  Widget _deckArea(double cw) {
    final left = _s.stock.length;
    final trumpSuit = _s.trumpSuit;
    final red = trumpSuit == 1 || trumpSuit == 2;
    return SizedBox(
      width: cw * 1.9,
      height: cw * 1.4,
      child: Stack(
        children: [
          if (left > 0)
            Positioned(
              left: cw * 0.45,
              top: cw * 0.1,
              child: Transform.rotate(
                angle: pi / 2,
                child: DkCard(_s.trumpCard, cw * 0.78),
              ),
            ),
          if (left > 0) Positioned(left: 0, top: 0, child: DkBack(cw * 0.9)),
          if (left > 0)
            Positioned(
              left: 0,
              top: 0,
              width: cw * 0.9,
              height: cw * 0.9 * 1.4,
              child: Center(
                child: Text(
                  '$left',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    shadows: [Shadow(blurRadius: 4)],
                  ),
                ),
              ),
            ),
          if (left == 0)
            Positioned(
              left: 0,
              top: cw * 0.35,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Козырь ',
                      style: TextStyle(
                        color: Colors.black87,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: CustomPaint(
                        painter: DkSuitPainter(
                          trumpSuit,
                          red
                              ? const Color(0xFFD32F2F)
                              : const Color(0xFF1A1A1A),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _discardArea(double cw) {
    final n = _s.discard.length;
    if (n == 0) return SizedBox(width: cw * 0.9, height: cw * 1.26);
    return SizedBox(
      width: cw * 0.9,
      height: cw * 1.26,
      child: Stack(
        children: [
          DkBack(cw * 0.9),
          Positioned.fill(
            child: Center(
              child: Text(
                '$n',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  shadows: [Shadow(blurRadius: 4)],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _pop(Object key, Widget child) => TweenAnimationBuilder<double>(
    key: ValueKey(key),
    tween: Tween(begin: 0, end: 1),
    duration: const Duration(milliseconds: 240),
    curve: Curves.easeOutBack,
    builder: (context, t, child) => Opacity(
      opacity: t.clamp(0.0, 1.0),
      child: Transform.scale(scale: 0.7 + 0.3 * t, child: child),
    ),
    child: child,
  );

  Widget _tableArea(double cw, List<int> moves) {
    final ch = cw * 1.4;
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: cw * 0.15,
      runSpacing: cw * 0.15,
      children: [
        for (var i = 0; i < _s.atk.length; i++)
          SizedBox(
            width: cw * 1.25,
            height: ch + cw * 0.2,
            child: Stack(
              children: [
                Positioned(
                  left: 0,
                  top: 0,
                  child: GestureDetector(
                    onTap: () => _tapTable(i),
                    child: _pop(
                      'a${_s.atk[i]}',
                      DkCard(
                        _s.atk[i],
                        cw,
                        hot:
                            _sel != null &&
                            _myTurn &&
                            moves.contains(Dk.mk(Dk.opBeat, _sel!, i)),
                      ),
                    ),
                  ),
                ),
                if (_s.def[i] >= 0)
                  Positioned(
                    left: cw * 0.25,
                    top: cw * 0.2,
                    child: _pop('d${_s.def[i]}', DkCard(_s.def[i], cw)),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _handArea(double cw, double aw, List<int> moves) {
    final trump = _s.trumpSuit;
    final hand = List<int>.of(_s.hands[_myIdx])
      ..sort((a, b) {
        int key(int c) =>
            (Dk.suitOf(c) == trump ? 100 : 0) +
            Dk.suitOf(c) * 10 +
            Dk.rankOf(c);
        return key(a).compareTo(key(b));
      });
    final ch = cw * 1.4;
    final n = hand.length;
    final movable = _myTurn ? _movableCards(moves) : <int>{};
    final step = n <= 1
        ? 0.0
        : ((aw - cw) / (n - 1)).clamp(cw * 0.3, cw * 0.95);
    final total = cw + step * max(0, n - 1);
    final stack = SizedBox(
      width: total,
      height: ch + 18,
      child: Stack(
        children: [
          for (var i = 0; i < n; i++)
            Positioned(
              left: i * step,
              top: hand[i] == _sel ? 0 : (movable.contains(hand[i]) ? 8 : 16),
              child: GestureDetector(
                onTap: () => _tapCard(hand[i]),
                child: DkCard(
                  hand[i],
                  cw,
                  dim: _myTurn && !movable.contains(hand[i]),
                  hot: hand[i] == _sel,
                ),
              ),
            ),
        ],
      ),
    );
    if (total > aw) {
      return SizedBox(
        height: ch + 18,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: stack,
        ),
      );
    }
    return Center(child: stack);
  }

  Widget _buttons(List<int> moves) {
    if (!_myTurn) return const SizedBox(height: 44);
    final children = <Widget>[];
    if (_s.phase == 1) {
      children.add(
        FilledButton.tonal(
          onPressed: () => _do(Dk.mk(Dk.opTake)),
          child: const Text('Беру'),
        ),
      );
      final sel = _sel;
      if (sel != null && moves.contains(Dk.mk(Dk.opTrans, sel))) {
        children.add(
          FilledButton(
            onPressed: () => _do(Dk.mk(Dk.opTrans, sel)),
            child: const Text('Перевести'),
          ),
        );
      }
    } else if (_s.atk.isNotEmpty) {
      children.add(
        FilledButton(
          onPressed: () => _do(Dk.mk(Dk.opPass)),
          child: Text(_s.phase == 2 ? 'Готово' : 'Бито'),
        ),
      );
    }
    return SizedBox(
      height: 44,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(width: 12),
            children[i],
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = _online
        ? 'Дурак · ${widget.room!.dvDisplayname()}'
        : (_mode == 'perevod' ? 'Дурак переводной' : 'Дурак подкидной');
    final oppName = _online ? widget.room!.dvDisplayname() : 'Компьютер';
    final moves = _myTurn ? _s.legalMoves() : const <int>[];
    return Scaffold(
      appBar: AppBar(title: Text(title), actions: const [DvSoundButton()]),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, c) {
            final cw = ((c.maxWidth - 32) / 6.4).clamp(44.0, 68.0);
            return Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _chip(
                          theme,
                          oppName,
                          _s.hands[_oppIdx].length,
                          !_finished && !_loading && _s.turn == _oppIdx,
                        ),
                      ),
                      const SizedBox(width: 10),
                      _opponentFan(cw),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(22),
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFF6E4625), Color(0xFF45290F)],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withAlpha(80),
                            blurRadius: 12,
                            offset: const Offset(0, 5),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: DecoratedBox(
                          decoration: const BoxDecoration(
                            gradient: RadialGradient(
                              radius: 0.95,
                              colors: [Color(0xFF2D8F5B), Color(0xFF0F4D31)],
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(10),
                            child: Column(
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [_deckArea(cw), _discardArea(cw)],
                                ),
                                Expanded(
                                  child: Center(
                                    child: SingleChildScrollView(
                                      child: _tableArea(cw, moves),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _status,
                    style: theme.textTheme.titleMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 6),
                  if (_finished)
                    SizedBox(
                      height: 44,
                      child: FilledButton.icon(
                        onPressed: _again,
                        icon: const Icon(Icons.replay),
                        label: Text(
                          _online ? 'Сыграть ещё раз' : 'Новая партия',
                        ),
                      ),
                    )
                  else
                    _buttons(moves),
                  _handArea(cw, c.maxWidth - 24, moves),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

// ---------------- карты ----------------

const List<String> _suitShapes = [
  'M 50 8 C 90 38 95 62 75 76 C 62 85 52 78 50 68 C 48 78 38 85 25 76 C 5 62 10 38 50 8 Z M 44 64 L 56 64 L 62 94 L 38 94 Z',
  'M 50 92 C 8 60 4 30 25 17 C 38 10 50 20 50 32 C 50 20 62 10 75 17 C 96 30 92 60 50 92 Z',
  'M 50 6 L 84 50 L 50 94 L 16 50 Z',
  'M 50 6 C 66 6 74 20 68 34 C 90 30 100 52 84 64 C 74 72 62 68 56 60 L 62 94 L 38 94 L 44 60 C 38 68 26 72 16 64 C 0 52 10 30 32 34 C 26 20 34 6 50 6 Z',
];

class DkSuitPainter extends CustomPainter {
  DkSuitPainter(this.suit, [this.color]);

  /// 0 пики, 1 червы, 2 бубны, 3 трефы
  final int suit;
  final Color? color;

  static final Map<int, Path> _cache = {};

  static Path _shape(int s) => _cache[s] ??= _build(s);

  static Path _build(int s) {
    final tok = _suitShapes[s].split(' ');
    final p = Path();
    var i = 0;
    double next() => double.parse(tok[i++]);
    while (i < tok.length) {
      final cmd = tok[i++];
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
    return p;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.shortestSide / 100;
    canvas.save();
    canvas.translate((size.width - 100 * k) / 2, (size.height - 100 * k) / 2);
    canvas.scale(k);
    final red = suit == 1 || suit == 2;
    canvas.drawPath(
      _shape(suit),
      Paint()
        ..color =
            color ?? (red ? const Color(0xFFD32F2F) : const Color(0xFF1A1A1A)),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(DkSuitPainter old) =>
      old.suit != suit || old.color != color;
}

/// Лицо карты: достоинство в углах, масть в центре
class DkCard extends StatelessWidget {
  const DkCard(
    this.card,
    this.w, {
    this.dim = false,
    this.hot = false,
    super.key,
  });

  final int card;
  final double w;
  final bool dim;
  final bool hot;

  Widget _corner(Color col, int suit) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        Dk.rankNames[Dk.rankOf(card)],
        style: TextStyle(
          fontSize: w * 0.27,
          fontWeight: FontWeight.bold,
          height: 1.0,
          color: col,
        ),
      ),
      SizedBox(
        width: w * 0.2,
        height: w * 0.2,
        child: CustomPaint(painter: DkSuitPainter(suit)),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final suit = Dk.suitOf(card);
    final col = (suit == 1 || suit == 2)
        ? const Color(0xFFD32F2F)
        : const Color(0xFF1A1A1A);
    return Opacity(
      opacity: dim ? 0.55 : 1,
      child: Container(
        width: w,
        height: w * 1.4,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(w * 0.12),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFFFFFFF), Color(0xFFEDE7D8)],
          ),
          border: Border.all(
            color: hot ? const Color(0xFFFFB300) : const Color(0xFFB9AE95),
            width: hot ? 3 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(70),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Stack(
          children: [
            Positioned(
              left: w * 0.07,
              top: w * 0.04,
              child: _corner(col, suit),
            ),
            Center(
              child: SizedBox(
                width: w * 0.46,
                height: w * 0.46,
                child: CustomPaint(painter: DkSuitPainter(suit)),
              ),
            ),
            Positioned(
              right: w * 0.07,
              bottom: w * 0.04,
              child: Transform.rotate(angle: pi, child: _corner(col, suit)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Рубашка карты
class DkBack extends StatelessWidget {
  const DkBack(this.w, {super.key});

  final double w;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: w,
      height: w * 1.4,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(w * 0.12),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF9B2342), Color(0xFF4B0F20)],
        ),
        border: Border.all(color: Colors.white, width: w * 0.04),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(70),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.all(w * 0.07),
        child: CustomPaint(painter: _LatticePainter(), size: Size.infinite),
      ),
    );
  }
}

class _LatticePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = Colors.white.withAlpha(70)
      ..strokeWidth = 1;
    canvas.clipRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(4)),
    );
    final step = size.width / 4;
    for (var x = -size.height; x < size.width + size.height; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x + size.height, size.height), p);
      canvas.drawLine(Offset(x, size.height), Offset(x + size.height, 0), p);
    }
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(4)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = Colors.white.withAlpha(150),
    );
  }

  @override
  bool shouldRepaint(_LatticePainter old) => false;
}
