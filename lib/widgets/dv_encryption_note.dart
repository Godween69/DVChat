// SPDX-License-Identifier: AGPL-3.0-or-later

// DVChat: строка внизу списка чатов «Ваши личные сообщения защищены сквозным шифрованием»
// и полноэкранная страница с понятным объяснением.

import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';

class DvEncryptionNote extends StatefulWidget {
  const DvEncryptionNote({super.key});

  @override
  State<DvEncryptionNote> createState() => _DvEncryptionNoteState();
}

class _DvEncryptionNoteState extends State<DvEncryptionNote> {
  final TapGestureRecognizer _tap = TapGestureRecognizer();

  @override
  void initState() {
    super.initState();
    _tap.onTap = _open;
  }

  @override
  void dispose() {
    _tap.dispose();
    super.dispose();
  }

  void _open() {
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => const DvEncryptionPage(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.outline;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
      child: Center(
        child: Text.rich(
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(color: muted),
          TextSpan(
            children: [
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: Icon(Icons.lock_outline, size: 14, color: muted),
              ),
              const TextSpan(text: ' Ваши личные сообщения защищены '),
              TextSpan(
                text: 'сквозным шифрованием',
                recognizer: _tap,
                style: TextStyle(
                  color: theme.colorScheme.primary,
                  decoration: TextDecoration.underline,
                  decorationColor: theme.colorScheme.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class DvEncryptionPage extends StatelessWidget {
  const DvEncryptionPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final body = theme.textTheme.bodyLarge?.copyWith(height: 1.45);
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        centerTitle: true,
        title: const Text('Сквозное шифрование'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Center(
                          child: CircleAvatar(
                            radius: 40,
                            backgroundColor: theme.colorScheme.primaryContainer,
                            child: Icon(
                              Icons.lock_outline,
                              size: 40,
                              color: theme.colorScheme.onPrimaryContainer,
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'Ваши сообщения под защитой',
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Всё, что вы отправляете: текст, голосовые, фото, видео, документы '
                          'и место на карте, шифруется сквозным шифрованием прямо на вашем '
                          'телефоне. Это как письмо в запертом сейфе: ключ есть только у вас '
                          'и у того, кому вы пишете. Провайдер, хакеры и посторонние в '
                          'интернете увидят только «замок» и ничего прочитать не смогут. '
                          'На сервере сообщения лежат только в зашифрованном виде.',
                          style: body,
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'Важно знать!',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Тот, кому вы пишете, может переслать ваше сообщение или '
                          'сфотографировать экран, поэтому пишите то, чем готовы поделиться '
                          'с этим человеком.',
                          style: body,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Администрация имеет техническую возможность восстановить доступ '
                          'к ключам при необходимости (это нужно, чтобы вы не потеряли '
                          'переписку при смене или утрате телефона). Это компромисс между '
                          'полной приватностью и удобством.',
                          style: body,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Понятно'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
