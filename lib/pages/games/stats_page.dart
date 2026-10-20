// SPDX-License-Identifier: AGPL-3.0-or-later

// DVChat: общий экран статистики игр: против компьютера, против друзей, по каждому другу.

import 'package:dvchat/pages/games/dv_game_net.dart';
import 'package:dvchat/pages/games/dv_local_stats.dart';
import 'package:dvchat/utils/dv_nicknames.dart';
import 'package:dvchat/widgets/matrix.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

const _games = <String, (String, IconData, Color)>{
  'ttt': ('Крестики-нолики', Icons.grid_3x3, Color(0xFF4D96FF)),
  'bs': ('Морской бой', Icons.sailing_outlined, Color(0xFF00A8E8)),
  'ckr': ('Шашки', Icons.radio_button_checked, Color(0xFFE8590C)),
  'c4': ('Четыре в ряд', Icons.grid_view, Color(0xFFE03131)),
  'chess': ('Шахматы', Icons.castle, Color(0xFF7048E8)),
  'durak': ('Дурак', Icons.style, Color(0xFFC2255C)),
  'nardy': ('Нарды', Icons.casino, Color(0xFF0CA678)),
  'domino': ('Домино', Icons.splitscreen, Color(0xFF845EF7)),
};

class _Friends {
  /// игра -> [победы, поражения, ничьи]
  final Map<String, List<int>> byGame = {};

  /// друг -> [победы, поражения, ничьи]
  final Map<String, List<int>> byFriend = {};
}

class DvStatsPage extends StatefulWidget {
  const DvStatsPage({super.key});

  @override
  State<DvStatsPage> createState() => _DvStatsPageState();
}

class _DvStatsPageState extends State<DvStatsPage> {
  Map<String, List<int>>? _local;
  _Friends? _friends;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _load();
  }

  Future<void> _load() async {
    final client = Matrix.of(context).client;
    final local = await DvLocalStats.load();
    if (mounted) setState(() => _local = local);
    final friends = await _scan(client);
    if (mounted) setState(() => _friends = friends);
  }

  /// Читает итоги партий из чатов: каждая партия считается один раз
  Future<_Friends> _scan(Client client) async {
    final out = _Friends();
    final me = client.userID;
    for (final room in DvGameNet.directRooms(client)) {
      try {
        final tl = await room.getTimeline(limit: 1000);
        final byId = <String, Map<String, Object?>>{};
        for (final e in tl.events) {
          if (e.type != DvGameNet.eventType || e.content['kind'] != 'end') {
            continue;
          }
          final id = '${e.content['game']}:${e.content['id']}';
          final old = byId[id];
          if (old == null ||
              (!old.containsKey('winner') && e.content.containsKey('winner'))) {
            byId[id] = e.content;
          }
        }
        tl.cancelSubscriptions();
        final name = room.dvDisplayname();
        for (final c in byId.values) {
          final game = '${c['game']}';
          final w = c['winner'];
          if (!_games.containsKey(game) || w is! String) continue;
          final i = w.isEmpty ? 2 : (w == me ? 0 : 1);
          (out.byGame[game] ??= [0, 0, 0])[i]++;
          (out.byFriend[name] ??= [0, 0, 0])[i]++;
        }
      } catch (_) {
        // чат без доступной истории пропускаем
      }
    }
    return out;
  }

  static String _line(int w, int l, [int? d]) =>
      'побед $w · поражений $l${d == null ? '' : ' · ничьих $d'}';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final local = _local;
    final friends = _friends;
    var lw = 0, ll = 0, fw = 0, fl = 0, fd = 0;
    for (final v in (local ?? {}).values) {
      lw += v[0];
      ll += v[1];
    }
    for (final v in (friends?.byGame ?? {}).values) {
      fw += v[0];
      fl += v[1];
      fd += v[2];
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Статистика игр')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Card(
            elevation: 0,
            color: theme.colorScheme.primaryContainer.withAlpha(120),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Всего', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text('С компьютером: ${_line(lw, ll)}'),
                  const SizedBox(height: 4),
                  Text(
                    friends == null
                        ? 'С друзьями: считаю…'
                        : 'С друзьями: ${_line(fw, fl, fd)}',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
            child: Text(
              'По играм',
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          ),
          for (final e in _games.entries)
            _gameCard(theme, e.key, e.value, local, friends),
          if (friends != null && friends.byFriend.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 20, 4, 4),
              child: Text(
                'По друзьям',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
            for (final f in friends.byFriend.entries)
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                leading: const Icon(Icons.person_outline),
                title: Text(f.key),
                subtitle: Text(_line(f.value[0], f.value[1], f.value[2])),
                trailing: Text(
                  'партий ${f.value[0] + f.value[1] + f.value[2]}',
                  style: theme.textTheme.bodySmall,
                ),
              ),
          ],
          Padding(
            padding: const EdgeInsets.only(top: 20),
            child: Text(
              'Счёт с компьютером ведётся с момента этого обновления. Ничьи против компьютера не считаются.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _gameCard(
    ThemeData theme,
    String id,
    (String, IconData, Color) g,
    Map<String, List<int>>? local,
    _Friends? friends,
  ) {
    final l = local?[id] ?? const [0, 0];
    final f = friends?.byGame[id] ?? const [0, 0, 0];
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest.withAlpha(140),
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(g.$2, color: g.$3, size: 34),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    g.$1,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Компьютер: ${_line(l[0], l[1])}',
                    style: theme.textTheme.bodySmall,
                  ),
                  Text(
                    friends == null
                        ? 'Друзья: считаю…'
                        : 'Друзья: ${_line(f[0], f[1], f[2])}',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
