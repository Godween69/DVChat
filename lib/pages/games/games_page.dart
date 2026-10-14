// SPDX-License-Identifier: AGPL-3.0-or-later

// DVChat: вкладка «Игры». Игры с друзьями (через личный чат) и с компьютером (без интернета).

import 'dart:async';

import 'package:dvchat/pages/games/bs_page.dart';
import 'package:dvchat/pages/games/dv_game_net.dart';
import 'package:dvchat/pages/games/ttt_page.dart';
import 'package:dvchat/widgets/matrix.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

class _GameDef {
  const _GameDef(this.id, this.title, this.inviteTitle, this.icon, this.levels);

  final String id;
  final String title;
  final String inviteTitle;
  final IconData icon;
  final List<String> levels;
}

const _ttt = _GameDef(
  'ttt',
  'Крестики-нолики',
  'крестики-нолики',
  Icons.grid_3x3,
  ['Лёгкий', 'Средний', 'Непобедимый'],
);
const _bs = _GameDef(
  'bs',
  'Морской бой',
  'морской бой',
  Icons.sailing_outlined,
  ['Лёгкий', 'Средний', 'Сильный'],
);

class GamesPage extends StatefulWidget {
  const GamesPage({super.key});

  @override
  State<GamesPage> createState() => _GamesPageState();
}

class _GamesPageState extends State<GamesPage> {
  List<DvGameInvite> _invites = const [];
  StreamSubscription<Event>? _sub;
  Timer? _debounce;
  bool _scanning = false;

  Client get _client => Matrix.of(context).client;

  _GameDef? _def(String id) => id == 'ttt' ? _ttt : (id == 'bs' ? _bs : null);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_sub == null) {
      _sub = _client.onTimelineEvent.stream
          .where((e) => e.type == DvGameNet.eventType)
          .listen((_) {
            _debounce?.cancel();
            _debounce = Timer(const Duration(milliseconds: 1500), _reload);
          });
      unawaited(_reload());
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _reload() async {
    if (_scanning) return;
    _scanning = true;
    final list = await DvGameNet.scan(_client);
    _scanning = false;
    if (mounted) setState(() => _invites = list);
  }

  void _open(Widget page) {
    Navigator.of(
      context,
      rootNavigator: true,
    ).push(MaterialPageRoute(builder: (_) => page)).then((_) => _reload());
  }

  Widget _pageFor(
    String game, {
    int? level,
    Room? room,
    String? gameId,
    String? hostId,
  }) => game == 'bs'
      ? BsPage(level: level, room: room, gameId: gameId, hostId: hostId)
      : TttPage(level: level, room: room, gameId: gameId, hostId: hostId);

  Future<void> _start(_GameDef g) async {
    final mode = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(
                g.title,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.smart_toy_outlined),
              title: const Text('С компьютером'),
              subtitle: const Text('Без интернета'),
              onTap: () => Navigator.pop(context, 'pc'),
            ),
            ListTile(
              leading: const Icon(Icons.people_outline),
              title: const Text('С другом'),
              onTap: () => Navigator.pop(context, 'friend'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || mode == null) return;
    if (mode == 'pc') {
      final level = await showDialog<int>(
        context: context,
        builder: (context) => SimpleDialog(
          title: const Text('Сложность'),
          children: [
            for (var i = 0; i < g.levels.length; i++)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, i),
                child: Text(g.levels[i]),
              ),
          ],
        ),
      );
      if (level == null || !mounted) return;
      _open(_pageFor(g.id, level: level));
      return;
    }
    final rooms = DvGameNet.directRooms(_client);
    if (rooms.isEmpty) {
      _snack('Сначала добавьте друзей');
      return;
    }
    final room = await showDialog<Room>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('С кем играем?'),
        children: [
          for (final r in rooms)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, r),
              child: Text(r.getLocalizedDisplayname()),
            ),
        ],
      ),
    );
    if (room == null || !mounted) return;
    try {
      final id = await DvGameNet.sendInvite(
        room,
        game: g.id,
        gameTitle: g.inviteTitle,
      );
      if (!mounted) return;
      _open(_pageFor(g.id, room: room, gameId: id, hostId: _client.userID));
    } catch (_) {
      _snack('Не удалось отправить приглашение');
    }
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  void _soon() => _snack('Эта игра появится в следующем обновлении');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final me = _client.userID;
    final invites = [
      for (final i in _invites)
        if (_def(i.game) != null) i,
    ];
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        centerTitle: true,
        title: const Text('Игры'),
      ),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
              child: Text(
                'Играйте с друзьями или с компьютером. С компьютером интернет не нужен.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            ),
            if (invites.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
                child: Text(
                  'Партии с друзьями',
                  style: theme.textTheme.titleSmall,
                ),
              ),
              for (final inv in invites)
                Card(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  child: ListTile(
                    leading: CircleAvatar(child: Icon(_def(inv.game)!.icon)),
                    title: Text(
                      '${_def(inv.game)!.title} · ${inv.room.getLocalizedDisplayname()}',
                    ),
                    subtitle: Text(
                      inv.hostId == me ? 'Вы пригласили' : 'Приглашает вас',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _open(
                      _pageFor(
                        inv.game,
                        room: inv.room,
                        gameId: inv.gameId,
                        hostId: inv.hostId,
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 12),
            ],
            _gameCard(
              theme,
              _ttt.title,
              'С другом или с компьютером',
              _ttt.icon,
              () => _start(_ttt),
              ready: true,
            ),
            _gameCard(
              theme,
              _bs.title,
              'С другом или с компьютером',
              _bs.icon,
              () => _start(_bs),
              ready: true,
            ),
            _gameCard(
              theme,
              'Шашки',
              'С другом или с компьютером',
              Icons.circle_outlined,
              _soon,
            ),
          ],
        ),
      ),
    );
  }

  Widget _gameCard(
    ThemeData theme,
    String title,
    String subtitle,
    IconData icon,
    VoidCallback onTap, {
    bool ready = false,
  }) => Card(
    margin: const EdgeInsets.symmetric(vertical: 4),
    child: ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: CircleAvatar(
        backgroundColor: theme.colorScheme.primaryContainer,
        foregroundColor: theme.colorScheme.onPrimaryContainer,
        child: Icon(icon),
      ),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: ready
          ? const Icon(Icons.chevron_right)
          : const Chip(label: Text('Скоро')),
      onTap: onTap,
    ),
  );
}
