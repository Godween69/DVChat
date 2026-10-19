// SPDX-License-Identifier: AGPL-3.0-or-later

// DVChat: вкладка «Игры». Сверху квадратные плитки игр («кубики»), ниже партии с друзьями
// списком, как чаты. У партии есть меню (три точки или долгое нажатие): информация и счёт,
// уведомления по этой партии, закрыть партию (засчитывается как сдача).

import 'dart:async';

import 'package:dvchat/pages/games/bs_page.dart';
import 'package:dvchat/pages/games/ckr_page.dart';
import 'package:dvchat/pages/games/dv_game_net.dart';
import 'package:dvchat/pages/games/ttt_page.dart';
import 'package:dvchat/utils/dv_list_style.dart';
import 'package:dvchat/utils/dv_nicknames.dart';
import 'package:dvchat/widgets/avatar.dart';
import 'package:dvchat/widgets/dv_list_card.dart';
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

const _ckr = _GameDef('ckr', 'Шашки', 'шашки', Icons.radio_button_checked, [
  'Лёгкий',
  'Средний',
  'Сильный',
]);

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

  _GameDef? _def(String id) => switch (id) {
    'ttt' => _ttt,
    'bs' => _bs,
    'ckr' => _ckr,
    _ => null,
  };

  void _styleChanged() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    DvListStyle.revision.addListener(_styleChanged);
  }

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
    DvListStyle.revision.removeListener(_styleChanged);
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
  }) => switch (game) {
    'bs' => BsPage(level: level, room: room, gameId: gameId, hostId: hostId),
    'ckr' => CkrPage(level: level, room: room, gameId: gameId, hostId: hostId),
    _ => TttPage(level: level, room: room, gameId: gameId, hostId: hostId),
  };

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
              child: Text(r.dvDisplayname()),
            ),
        ],
      ),
    );
    if (room == null || !mounted) return;
    // Партия с этим другом в эту игру уже идёт: открываем её, а не шлём новое приглашение
    final current = await DvGameNet.scan(_client);
    if (!mounted) return;
    for (final inv in current) {
      if (inv.room.id == room.id && inv.game == g.id) {
        _open(
          _pageFor(
            inv.game,
            room: inv.room,
            gameId: inv.gameId,
            hostId: inv.hostId,
          ),
        );
        return;
      }
    }
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

  // ---------------- меню партии ----------------

  String _dateTime(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    final l = t.toLocal();
    return '${two(l.day)}.${two(l.month)}.${l.year} ${two(l.hour)}:${two(l.minute)}';
  }

  Future<void> _partyMenu(DvGameInvite inv) async {
    final muted = DvGameNet.isMuted(inv.gameId);
    final error = Theme.of(context).colorScheme.error;
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('Информация'),
              onTap: () => Navigator.pop(context, 'info'),
            ),
            ListTile(
              leading: Icon(
                muted
                    ? Icons.notifications_outlined
                    : Icons.notifications_off_outlined,
              ),
              title: Text(
                muted ? 'Включить уведомления' : 'Отключить уведомления',
              ),
              onTap: () => Navigator.pop(context, 'mute'),
            ),
            ListTile(
              leading: Icon(Icons.flag_outlined, color: error),
              title: Text('Закрыть партию', style: TextStyle(color: error)),
              subtitle: const Text('Засчитается как сдача'),
              onTap: () => Navigator.pop(context, 'close'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'info':
        await _info(inv);
      case 'mute':
        await DvGameNet.setMuted(inv.gameId, !muted);
        if (mounted) setState(() {});
      case 'close':
        await _closeParty(inv);
    }
  }

  Future<void> _info(DvGameInvite inv) async {
    final def = _def(inv.game)!;
    final stats = await DvGameNet.stats(inv.room, inv.game);
    if (!mounted) return;
    final me = _client.userID;
    final theme = Theme.of(context);
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(def.title),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Соперник: ${inv.room.dvDisplayname()}'),
              const SizedBox(height: 6),
              Text(
                'Приглашение: ${_dateTime(inv.time)} '
                '(${inv.hostId == me ? 'вы пригласили' : 'приглашает вас'})',
              ),
              const SizedBox(height: 16),
              const Text(
                'Счёт в этой игре с другом',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              Text('Сыграно партий: ${stats.played}'),
              Text('Побед: ${stats.wins}'),
              Text('Поражений: ${stats.losses}'),
              Text('Ничьих: ${stats.draws}'),
              if (stats.quitByMe + stats.quitByOpp > 0)
                Text('Сдач: вы ${stats.quitByMe}, соперник ${stats.quitByOpp}'),
              const SizedBox(height: 12),
              Text(
                'История партий хранится в чате и очистке не подлежит.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ОК'),
          ),
        ],
      ),
    );
  }

  Future<void> _closeParty(DvGameInvite inv) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Закрыть партию?'),
        content: const Text(
          'Партия будет засчитана как сдача: победа достанется сопернику. '
          'Это отобразится в информации о партии.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Закрыть'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await DvGameNet.surrender(inv.room, game: inv.game, id: inv.gameId);
      _snack('Партия закрыта');
      unawaited(_reload());
    } catch (_) {
      _snack('Не удалось закрыть партию');
    }
  }

  // ---------------- оформление ----------------

  Widget _heading(ThemeData theme, String text) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
    child: Text(
      text,
      style: theme.textTheme.labelLarge?.copyWith(
        color: theme.colorScheme.primary,
      ),
    ),
  );

  /// Квадратная плитка игры («кубик»)
  Widget _tile(
    ThemeData theme, {
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    bool soon = false,
  }) {
    final plain = DvListStyle.isPlain;
    return Material(
      color: plain
          ? theme.colorScheme.surfaceContainerHighest
          : DvListStyle.fill(context),
      elevation: DvListStyle.elevation,
      shadowColor: Colors.black,
      surfaceTintColor: Colors.transparent,
      shape: DvListStyle.shape(context),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: theme.colorScheme.primaryContainer,
                foregroundColor: theme.colorScheme.onPrimaryContainer,
                child: Icon(icon, size: 24),
              ),
              const SizedBox(height: 8),
              Text(
                title,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  height: 1.15,
                  fontWeight: FontWeight.w600,
                  color: soon
                      ? theme.colorScheme.outline
                      : theme.colorScheme.onSurface,
                ),
              ),
              if (soon)
                Text(
                  'скоро',
                  style: TextStyle(
                    fontSize: 9,
                    color: theme.colorScheme.outline,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Партия с другом: строка, как в списке чатов; три строки, чтобы ничего не обрезалось
  Widget _party(ThemeData theme, DvGameInvite inv, String? me) {
    final def = _def(inv.game)!;
    final name = inv.room.dvDisplayname();
    final muted = DvGameNet.isMuted(inv.gameId);
    final small = theme.textTheme.bodySmall;
    return DvListCard(
      child: ListTile(
        isThreeLine: true,
        contentPadding: DvListStyle.isPlain
            ? const EdgeInsets.only(left: 16, right: 4)
            : const EdgeInsets.fromLTRB(18, 8, 4, 8),
        leading: Avatar(
          mxContent: inv.room.avatar,
          name: name,
          client: _client,
        ),
        title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(def.title, maxLines: 1, overflow: TextOverflow.ellipsis),
            Text(
              inv.hostId == me ? 'Вы пригласили' : 'Приглашает вас',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: small?.copyWith(color: theme.colorScheme.outline),
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (muted)
              Icon(
                Icons.notifications_off_outlined,
                size: 18,
                color: theme.colorScheme.outline,
              ),
            IconButton(
              tooltip: 'Меню',
              icon: const Icon(Icons.more_vert),
              onPressed: () => _partyMenu(inv),
            ),
          ],
        ),
        onTap: () => _open(
          _pageFor(
            inv.game,
            room: inv.room,
            gameId: inv.gameId,
            hostId: inv.hostId,
          ),
        ),
        onLongPress: () => _partyMenu(inv),
      ),
    );
  }

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
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(
                'Играйте с друзьями или с компьютером. С компьютером интернет не нужен.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            ),
            _heading(theme, 'Игры'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: GridView.count(
                crossAxisCount: 3,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _tile(
                    theme,
                    icon: _ttt.icon,
                    title: _ttt.title,
                    onTap: () => _start(_ttt),
                  ),
                  _tile(
                    theme,
                    icon: _bs.icon,
                    title: _bs.title,
                    onTap: () => _start(_bs),
                  ),
                  _tile(
                    theme,
                    icon: _ckr.icon,
                    title: _ckr.title,
                    onTap: () => _start(_ckr),
                  ),
                ],
              ),
            ),
            _heading(theme, 'Партии с друзьями'),
            if (invites.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'Пока нет партий. Выберите игру и пригласите друга.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              )
            else
              for (final inv in invites) _party(theme, inv, me),
          ],
        ),
      ),
    );
  }
}
