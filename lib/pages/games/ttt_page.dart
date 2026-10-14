// SPDX-License-Identifier: AGPL-3.0-or-later

// DVChat: экран крестиков-ноликов. Два режима:
//  - с компьютером (level 0..2), без интернета;
//  - с другом (room + gameId + hostId), ходы идут через личный чат.

import 'dart:async';

import 'package:dvchat/pages/games/dv_game_net.dart';
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

  bool get _online => widget.room != null;
  String get _me => widget.room?.client.userID ?? '';
  String get _myLetter => widget.hostId == _me ? 'X' : 'O';
  String get _humanLetter => _humanFirst ? 'X' : 'O';

  @override
  void initState() {
    super.initState();
    if (_online) {
      _loading = true;
      _sub = widget.room!.client.onTimelineEvent.stream.listen((e) {
        if (_ingest(e)) _rebuild();
      });
      unawaited(_load());
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  // ---------------- сетевая часть ----------------

  bool _ingest(Event e) {
    if (e.type != DvGameNet.eventType || e.roomId != widget.room?.id) {
      return false;
    }
    final c = e.content;
    if (c['game'] != 'ttt' || '${c['id']}' != widget.gameId) return false;
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
      final tl = await widget.room!.getTimeline();
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

  /// Собирает поле из полученных ходов, проверяя очерёдность
  void _rebuild() {
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
    setState(() => _board = b);
    _maybeSendEnd();
  }

  void _maybeSendEnd() {
    if (!_online || _endSent || !_finished) return;
    if (_lastSender != _me) return;
    _endSent = true;
    unawaited(
      DvGameNet.sendEnd(
        widget.room!,
        game: 'ttt',
        id: widget.gameId!,
      ).catchError((_) => null),
    );
  }

  // ---------------- общая часть ----------------

  bool get _finished =>
      TttLogic.winner(_board) != null || TttLogic.isFull(_board);

  Future<void> _tap(int i) async {
    if (_loading || _busy || _finished || _board[i] != '') return;
    final turn = TttLogic.turnOf(_board);
    if (_online) {
      if (turn != _myLetter) return;
      final n = _board.where((c) => c != '').length;
      _moves[n] = _Move(i, _me);
      _rebuild();
      try {
        await DvGameNet.sendMove(
          widget.room!,
          game: 'ttt',
          id: widget.gameId!,
          n: n,
          cell: i,
        );
      } catch (_) {
        _moves.remove(n);
        _rebuild();
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
    setState(() => _board = List.of(_board)..[i] = turn);
    await _aiTurn();
  }

  Future<void> _aiTurn() async {
    if (_finished) return;
    final ai = _humanLetter == 'X' ? 'O' : 'X';
    if (TttLogic.turnOf(_board) != ai) return;
    setState(() => _busy = true);
    await Future<void>.delayed(const Duration(milliseconds: 450));
    if (!mounted) return;
    final move = TttLogic.aiMove(_board, ai, widget.level ?? 1);
    setState(() {
      _board = List.of(_board)..[move] = ai;
      _busy = false;
    });
  }

  Future<void> _again() async {
    if (_online) {
      try {
        final id = await DvGameNet.sendInvite(
          widget.room!,
          game: 'ttt',
          gameTitle: 'крестики-нолики',
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
    final w = TttLogic.winner(_board);
    final mine = _online ? _myLetter : _humanLetter;
    if (w != null) return w == mine ? 'Вы победили! 🎉' : 'Вы проиграли';
    if (TttLogic.isFull(_board)) return 'Ничья';
    final turn = TttLogic.turnOf(_board);
    if (turn == mine) return 'Ваш ход ($mine)';
    return _online ? 'Ход соперника…' : 'Компьютер думает…';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final line = TttLogic.winLine(_board);
    final title = _online
        ? 'Крестики-нолики · ${widget.room!.getLocalizedDisplayname()}'
        : 'Крестики-нолики · ${_levelNames[(widget.level ?? 1).clamp(0, 2)]}';
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(_status, style: theme.textTheme.headlineSmall),
              const SizedBox(height: 24),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: AspectRatio(
                  aspectRatio: 1,
                  child: GridView.count(
                    crossAxisCount: 3,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    physics: const NeverScrollableScrollPhysics(),
                    children: [
                      for (var i = 0; i < 9; i++)
                        _cell(theme, i, line?.contains(i) ?? false),
                    ],
                  ),
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
    );
  }

  Widget _cell(ThemeData theme, int i, bool highlight) {
    final v = _board[i];
    final color = v == 'X'
        ? theme.colorScheme.primary
        : theme.colorScheme.error;
    return Material(
      color: highlight
          ? theme.colorScheme.primaryContainer
          : theme.colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _tap(i),
        child: Center(
          child: Text(
            v,
            style: TextStyle(
              fontSize: 56,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ),
      ),
    );
  }
}
