// SPDX-License-Identifier: AGPL-3.0-or-later

// DVChat: анимация «записывает голосовое…»: красный пульсирующий микрофон и бегущие столбики.

import 'dart:math';

import 'package:material_ui/material_ui.dart';

class RecordingAnimation extends StatefulWidget {
  const RecordingAnimation({super.key});

  @override
  State<RecordingAnimation> createState() => _RecordingAnimationState();
}

class _RecordingAnimationState extends State<RecordingAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = _c.value * 2 * pi;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Transform.scale(
              scale: 1 + 0.18 * sin(t),
              child: Icon(Icons.mic, size: 18, color: theme.colorScheme.error),
            ),
            const SizedBox(width: 6),
            for (var i = 0; i < 4; i++)
              Container(
                width: 3,
                height: 6 + 8 * (0.5 + 0.5 * sin(t + i * 1.2)),
                margin: const EdgeInsets.symmetric(horizontal: 1),
                decoration: BoxDecoration(
                  color: theme.colorScheme.error.withAlpha(200),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            const SizedBox(width: 8),
            Text(
              'записывает голосовое…',
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        );
      },
    );
  }
}
