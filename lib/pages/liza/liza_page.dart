// SPDX-License-Identifier: AGPL-3.0-or-later

// DVChat: вкладка «Лиза». Пока это анонс искусственного интеллекта, который скоро
// поселится в приложении. Сам помощник подключается позже, ключи доступа к нему
// будут храниться только на сервере DVChat, не в приложении.

import 'package:material_ui/material_ui.dart';

class LizaPage extends StatelessWidget {
  const LizaPage({super.key});

  Widget _feature(
    ThemeData theme,
    IconData icon,
    String title,
    String subtitle,
  ) => ListTile(
    leading: CircleAvatar(
      backgroundColor: theme.colorScheme.primaryContainer,
      foregroundColor: theme.colorScheme.onPrimaryContainer,
      child: Icon(icon),
    ),
    title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
    subtitle: Text(subtitle),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        centerTitle: true,
        title: const Text('Лиза'),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          const SizedBox(height: 28),
          Center(
            child: Container(
              width: 104,
              height: 104,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: theme.colorScheme.primaryContainer,
              ),
              child: Icon(
                Icons.auto_awesome,
                size: 52,
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
          ),
          const SizedBox(height: 18),
          Center(
            child: Text(
              'Лиза',
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Center(
            child: Text(
              'Искусственный интеллект DVChat',
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: theme.colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                'Скоро в приложении',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSecondaryContainer,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 22, 24, 10),
            child: Text(
              'Скоро Лиза поселится прямо здесь. Её можно будет спросить о чём угодно, '
              'не выходя из DVChat.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge,
            ),
          ),
          _feature(
            theme,
            Icons.chat_bubble_outline,
            'Отвечает на вопросы',
            'Простыми словами и по-русски',
          ),
          _feature(
            theme,
            Icons.edit_note,
            'Помогает с текстами',
            'Письма, поздравления, краткий пересказ',
          ),
          _feature(
            theme,
            Icons.translate,
            'Переводит',
            'С других языков и на другие языки',
          ),
          _feature(
            theme,
            Icons.lightbulb_outline,
            'Подсказывает идеи',
            'Что приготовить, куда поехать, как решить задачу',
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
            child: Text(
              'Пока это анонс: мы подключаем модель и настраиваем лимиты. '
              'Как только всё будет готово, Лиза появится на этой вкладке.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
