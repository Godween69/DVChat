// SPDX-License-Identifier: AGPL-3.0-or-later

// DVChat: экран «История» (все разговоры с Лизой на этом телефоне) и справка «О Лизе».

import 'dart:async';

import 'package:dvchat/pages/liza/liza_store.dart';
import 'package:material_ui/material_ui.dart';

String _two(int n) => n.toString().padLeft(2, '0');

String _when(int millis) {
  final d = DateTime.fromMillisecondsSinceEpoch(millis);
  return '${_two(d.day)}.${_two(d.month)}.${d.year} ${_two(d.hour)}:${_two(d.minute)}';
}

/// Число с неразрывными пробелами между тысячами: 12340 -> 12 340
String lizaSpaced(int n) {
  final s = n.toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(' ');
    b.write(s[i]);
  }
  return b.toString();
}

/// Список разговоров: нажать — открыть, корзина — удалить один, сверху — очистить всё
class LizaHistoryPage extends StatefulWidget {
  const LizaHistoryPage({
    required this.chats,
    required this.currentId,
    required this.onDelete,
    required this.onClear,
    super.key,
  });

  /// Тот же список, что у чата: удаление меняет его на месте
  final List<LizaConversation> chats;
  final String currentId;
  final Future<void> Function(String id) onDelete;
  final Future<void> Function() onClear;

  @override
  State<LizaHistoryPage> createState() => _LizaHistoryPageState();
}

class _LizaHistoryPageState extends State<LizaHistoryPage> {
  Future<void> _confirmClear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Очистить всю историю?'),
        content: const Text(
          'Все разговоры с Лизой на этом телефоне будут удалены. Вернуть их нельзя.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Очистить'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await widget.onClear();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chats = widget.chats;
    return Scaffold(
      appBar: AppBar(
        title: const Text('История'),
        actions: [
          IconButton(
            tooltip: 'Очистить всю историю',
            icon: const Icon(Icons.delete_sweep_outlined),
            onPressed: chats.isEmpty ? null : _confirmClear,
          ),
        ],
      ),
      body: chats.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Пока пусто. Задайте вопрос Лизе: разговор сохранится здесь, '
                  'на вашем телефоне.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView.separated(
              itemCount: chats.length,
              separatorBuilder: (context, i) =>
                  Divider(height: 1, color: theme.dividerColor),
              itemBuilder: (context, i) {
                final c = chats[i];
                final questions = c.messages.where((m) => m.isUser).length;
                final current = c.id == widget.currentId;
                return ListTile(
                  leading: Icon(
                    current ? Icons.chat_bubble : Icons.chat_bubble_outline,
                    color: current ? theme.colorScheme.primary : null,
                  ),
                  title: Text(
                    c.title.isEmpty ? 'Без названия' : c.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text('${_when(c.updated)} · вопросов: $questions'),
                  trailing: IconButton(
                    tooltip: 'Удалить разговор',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () async {
                      await widget.onDelete(c.id);
                      if (mounted) setState(() {});
                    },
                  ),
                  onTap: () => Navigator.of(context).pop(c.id),
                );
              },
            ),
    );
  }
}

/// Справка «О Лизе»: что умеет, сколько запросов и токенов потрачено, как хранится переписка
void showLizaInfo(
  BuildContext context, {
  required int used,
  required int? limit,
  required int? tokens,
}) {
  final theme = Theme.of(context);
  final small = theme.textTheme.bodyMedium?.copyWith(
    color: theme.colorScheme.onSurfaceVariant,
  );
  Widget block(String title, List<String> lines) => Padding(
    padding: const EdgeInsets.only(top: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.titleSmall?.copyWith(
            color: theme.colorScheme.primary,
          ),
        ),
        const SizedBox(height: 4),
        for (final line in lines)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(line, style: theme.textTheme.bodyMedium),
          ),
      ],
    ),
  );
  unawaited(
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('О Лизе', style: theme.textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(
                'Лиза — помощник семейного мессенджера DVChat. Отвечает на '
                'вопросы, пишет и правит тексты, переводит, подсказывает идеи, '
                'знает сегодняшнюю дату, может сказать погоду и найти свежие '
                'сведения в интернете.',
                style: theme.textTheme.bodyMedium,
              ),
              block('Сегодня', [
                limit == null
                    ? 'Запросов: $used (личного лимита нет)'
                    : 'Запросов: $used из $limit',
                tokens == null
                    ? 'Токенов: пока не посчитано'
                    : 'Токенов: ${lizaSpaced(tokens)}',
              ]),
              const SizedBox(height: 8),
              Text(
                'Токен — это кусочек слова. Один вопрос с ответом обычно '
                'занимает от 500 до 3 000 токенов. В длинном разговоре больше, '
                'потому что Лиза перечитывает прошлые реплики.',
                style: small,
              ),
              block('Лимиты', [
                'Счётчик обнуляется каждую ночь по московскому времени.',
                'Есть ещё общий дневной лимит на всю семью. Если его выбрали, '
                    'Лиза ответит завтра.',
              ]),
              block('Переписка', [
                'Разговоры хранятся только на этом телефоне, сервер их не '
                    'сохраняет. Открыть, удалить один или очистить всё можно в '
                    'разделе «История» (значок слева вверху).',
                'Кнопка «+» начинает новый разговор, прошлый останется в истории.',
              ]),
              block('Голос', [
                'Нажмите на микрофон слева от строки, говорите и нажмите на него '
                    'ещё раз. Текст появится в строке, его можно поправить и '
                    'отправить стрелкой.',
              ]),
            ],
          ),
        ),
      ),
    ),
  );
}
