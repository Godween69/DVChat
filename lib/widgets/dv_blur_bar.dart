// SPDX-License-Identifier: AGPL-3.0-or-later

// DVChat: фон шапки экрана. Шапка прозрачная, а всё, что прокручивается под ней,
// размывается и чуть затемняется цветом страницы, чтобы заголовок читался.

import 'dart:ui' show ImageFilter;

import 'package:material_ui/material_ui.dart';

class DvBlurBar extends StatelessWidget {
  const DvBlurBar({this.enabled = true, super.key});

  /// false: шапка рисуется своим сплошным цветом (например, при выборе сообщений)
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return const SizedBox.shrink();
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: ColoredBox(
          color: Theme.of(context).colorScheme.surface.withAlpha(150),
        ),
      ),
    );
  }
}
