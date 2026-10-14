// SPDX-License-Identifier: AGPL-3.0-or-later

// DVChat: вкладка «Игры». Игры с друзьями (через личный чат) и с компьютером (без интернета).

import 'dart:async';

import 'package:dvchat/pages/games/dv_game_net.dart';
import 'package:dvchat/pages/games/ttt_page.dart';
import 'package:dvchat/widgets/matrix.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

class GamesPage extends StatefulWidget {
  const GamesPage({super.key});

  @override
  State<GamesPage> createState() => _GamesPageState();
}

class _GamesPageState extends State<GamesPage> {
  List<DvGameInvite> _invites = const [];
  StreamSubscription<Event>? _sub;
  bool _scanning = false;

  Client get _client => Matrix.of(context).client;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_sub == null) {
      _sub = _client.onTimelineEvent.stream
          .where((e) => e.type == DvGameNet.eventType)
          .listen((_) => _reload());
      unawaited(_reload());
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
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

  Future<void> _tttStart() async {
    final mode = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              title: Text(
                'Крестики-нолики',
                style: TextStyle(fontWeight: FontWeight.bold),
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
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, 0),
              child: const Text('Лёгкий'),
            ),
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, 1),
              child: const Text('Средний'),
            ),
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, 2),
              child: const Text('Непобедимый'),
            ),
          ],
        ),
      );
      if (level == null || !mounted) return;
      _open(TttPage(level: level));
      return;
    }
    final rooms = DvGameNet.directRooms(_client);
    if (rooms.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Сначала добавьте друзей')));
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
        game: 'ttt',
        gameTitle: 'крестики-нолики',
      );
      if (!mounted) return;
      _open(TttPage(room: room, gameId: id, hostId: _client.userID));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось отправить приглашение')),
        );
      }
    }
  }

  void _soon() => ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('Эта игра появится в следующем обновлении')),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final me = _client.userID;
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
            if (_invites.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
                child: Text(
                  'Партии с друзьями',
                  style: theme.textTheme.titleSmall,
                ),
              ),
              for (final inv in _invites)
                Card(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  child: ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.grid_3x3)),
                    title: Text(
                      'Крестики-нолики · ${inv.room.getLocalizedDisplayname()}',
                    ),
                    subtitle: Text(
                      inv.hostId == me ? 'Вы пригласили' : 'Приглашает вас',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _open(
                      TttPage(
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
              'Крестики-нолики',
              'С другом или с компьютером',
              Icons.grid_3x3,
              _tttStart,
              ready: true,
            ),
            _gameCard(
              theme,
              'Морской бой',
              'С другом или с компьютером',
              Icons.sailing_outlined,
              _soon,
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
