// SPDX-License-Identifier: AGPL-3.0-or-later

// DVChat: вкладка «Игры». Игры с друзьями (по сети) и с компьютером (без интернета).
// Пока заготовка: сами игры появляются в следующих обновлениях по одной.

import 'package:material_ui/material_ui.dart';

class _GameInfo {
  const _GameInfo(this.title, this.subtitle, this.icon);

  final String title;
  final String subtitle;
  final IconData icon;
}

class GamesPage extends StatelessWidget {
  const GamesPage({super.key});

  static const List<_GameInfo> _games = [
    _GameInfo('Крестики-нолики', 'С другом или с компьютером', Icons.grid_3x3),
    _GameInfo(
      'Морской бой',
      'С другом или с компьютером',
      Icons.sailing_outlined,
    ),
    _GameInfo('Шашки', 'С другом или с компьютером', Icons.circle_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        centerTitle: true,
        title: const Text('Игры'),
      ),
      body: ListView(
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
          for (final game in _games)
            Card(
              margin: const EdgeInsets.symmetric(vertical: 4),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 6,
                ),
                leading: CircleAvatar(
                  backgroundColor: theme.colorScheme.primaryContainer,
                  foregroundColor: theme.colorScheme.onPrimaryContainer,
                  child: Icon(game.icon),
                ),
                title: Text(game.title),
                subtitle: Text(game.subtitle),
                trailing: const Chip(label: Text('Скоро')),
                onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Эта игра появится в следующем обновлении'),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
