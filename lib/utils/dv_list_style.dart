// SPDX-License-Identifier: AGPL-3.0-or-later

// DVChat: оформление списков (чаты, друзья, архив): обычный вид, «плашки» или «рамки».
// Плашки: фон чуть отличается от фона страницы и лёгкая тень. Рамки: тонкая бледная обводка.
// Ползунок «Контраст» (0..1) задаёт, насколько плашки и рамки заметны на фоне:
// слева они почти сливаются со страницей, справа выделяются сильнее.

import 'package:dvchat/config/app_config.dart';
import 'package:dvchat/config/setting_keys.dart';
import 'package:material_ui/material_ui.dart';

abstract class DvListStyle {
  static const String plain = 'plain';
  static const String plates = 'plates';
  static const String frames = 'frames';

  /// Растёт при любой смене стиля или контраста: экраны со списками подписаны на него
  /// и перерисовываются сразу, не дожидаясь, пока их снова откроют.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static void changed() => revision.value++;

  static String get mode {
    final value = AppSettings.listStyle.value;
    return value == plates || value == frames ? value : plain;
  }

  static bool get isPlain => mode == plain;

  /// Значение ползунка во время перетаскивания (до сохранения), иначе null
  static double? previewContrast;

  /// Контраст плашек и рамок с фоном, 0..1
  static double get contrast =>
      (previewContrast ?? AppSettings.listContrast.value).clamp(0.0, 1.0);

  /// Цвет тонкого кольца вокруг аватарки с фото (цвет рамки из персонализации).
  /// Не слабее половины силы, чтобы тёмное фото не сливалось с тёмным фоном.
  static Color avatarRing(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final k = contrast < 0.5 ? 0.5 : contrast;
    return theme.colorScheme.onSurface.withValues(
      alpha: (dark ? 0.34 : 0.28) * k,
    );
  }

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
      theme.colorScheme.onSurface.withValues(
        alpha: (dark ? 0.14 : 0.09) * contrast,
      ),
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
          alpha: (dark ? 0.34 : 0.28) * contrast,
        ),
      ),
    );
  }

  static double get elevation => mode == plates ? 0.9 * contrast : 0;
}
