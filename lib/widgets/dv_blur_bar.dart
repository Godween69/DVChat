// SPDX-License-Identifier: AGPL-3.0-or-later

// DVChat: фон шапки экрана. Шапка прозрачная, а всё, что прокручивается под ней,
// размывается и подкрашивается цветом страницы, чтобы заголовок читался.
// Насколько шапка плотная, человек выбирает в «Оформлении» (ползунок «Непрозрачность шапки»):
// слева стекло, справа сплошной цвет. Значение по умолчанию совпадает с прежним видом.

import 'dart:ui' show ImageFilter;

import 'package:dvchat/config/setting_keys.dart';
import 'package:material_ui/material_ui.dart';

class DvBlurBar extends StatelessWidget {
  const DvBlurBar({this.enabled = true, super.key});

  /// false: шапка рисуется своим сплошным цветом (например, при выборе сообщений)
  final bool enabled;

  /// Значение ползунка во время перетаскивания (до сохранения), иначе null
  static double? preview;

  /// Растёт при смене непрозрачности: все шапки перерисовываются сразу
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static void changed() => revision.value++;

  /// Непрозрачность шапки, 0..1
  static double get opacity =>
      (preview ?? AppSettings.headerOpacity.value).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    if (!enabled) return const SizedBox.shrink();
    return ValueListenableBuilder<int>(
      valueListenable: revision,
      builder: (context, value, child) {
        final surface = Theme.of(context).colorScheme.surface;
        final alpha = (255 * opacity).round();
        // Почти сплошная шапка: размытие под ней уже не видно, не тратим на него силы
        if (alpha >= 250) return ColoredBox(color: surface);
        return ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
            child: ColoredBox(color: surface.withAlpha(alpha)),
          ),
        );
      },
    );
  }
}
