// SPDX-License-Identifier: AGPL-3.0-or-later

// DVChat: оформление списков (чаты, друзья, архив): обычный вид, «плашки» или «рамки».
// Плашки: фон чуть отличается от фона страницы и лёгкая тень. Рамки: тонкая бледная обводка.

import 'package:dvchat/config/app_config.dart';
import 'package:dvchat/config/setting_keys.dart';
import 'package:material_ui/material_ui.dart';

abstract class DvListStyle {
  static const String plain = 'plain';
  static const String plates = 'plates';
  static const String frames = 'frames';

  static String get mode {
    final value = AppSettings.listStyle.value;
    return value == plates || value == frames ? value : plain;
  }

  static bool get isPlain => mode == plain;

  static EdgeInsets get outerPadding => isPlain
      ? const EdgeInsets.symmetric(horizontal: 8)
      : const EdgeInsets.symmetric(horizontal: 10, vertical: 3);

  /// Заливка строки: у плашек чуть светлее (тёмная тема) или чуть серее (светлая) фона страницы
  static Color? fill(BuildContext context) {
    if (isPlain) return null;
    final theme = Theme.of(context);
    final base = theme.scaffoldBackgroundColor;
    if (mode == frames) return base;
    final dark = theme.brightness == Brightness.dark;
    return Color.alphaBlend(
      theme.colorScheme.onSurface.withValues(alpha: dark ? 0.07 : 0.045),
      base,
    );
  }

  static ShapeBorder shape(BuildContext context) {
    final radius = BorderRadius.circular(AppConfig.borderRadius);
    if (mode != frames) return RoundedRectangleBorder(borderRadius: radius);
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return RoundedRectangleBorder(
      borderRadius: radius,
      side: BorderSide(
        color: theme.colorScheme.onSurface.withValues(
          alpha: dark ? 0.18 : 0.14,
        ),
      ),
    );
  }

  static double get elevation => mode == plates ? 0.6 : 0;
}
