// SPDX-License-Identifier: AGPL-3.0-or-later

// DVChat: готовые обои чата. Это градиенты, нарисованные кодом: файлов нет, весят ноль,
// работают без сети и не тормозят ленту. Цвета полупрозрачные, чтобы сообщения читались.

import 'package:flutter/painting.dart';

class DvWallpaperPreset {
  const DvWallpaperPreset(this.id, this.name, this.colors);

  final String id;
  final String name;
  final List<Color> colors;

  /// Градиент для ленты чата: в тёмной теме приглушён сильнее
  LinearGradient gradient({required bool dark}) => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [for (final c in colors) c.withAlpha(dark ? 0x66 : 0x88)],
  );

  /// Яркий градиент для значка в настройках
  LinearGradient get swatch => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: colors,
  );
}

class DvWallpapers {
  static const List<DvWallpaperPreset> all = [
    DvWallpaperPreset('dusk', 'Сумерки', [Color(0xFF355C7D), Color(0xFF6C5B7B), Color(0xFFC06C84)]),
    DvWallpaperPreset('sea', 'Море', [Color(0xFF00B4DB), Color(0xFF0083B0)]),
    DvWallpaperPreset('forest', 'Лес', [Color(0xFF134E5E), Color(0xFF71B280)]),
    DvWallpaperPreset('peach', 'Персик', [Color(0xFFFFB88C), Color(0xFFDE6262)]),
    DvWallpaperPreset('ice', 'Лёд', [Color(0xFF9CECFB), Color(0xFF65C7F7), Color(0xFF0052D4)]),
    DvWallpaperPreset('lavender', 'Лаванда', [Color(0xFFC9B6E4), Color(0xFF8E7CC3)]),
    DvWallpaperPreset('sunrise', 'Рассвет', [Color(0xFFFFE259), Color(0xFFFFA751)]),
    DvWallpaperPreset('berry', 'Ягода', [Color(0xFF8E2DE2), Color(0xFF4A00E0)]),
    DvWallpaperPreset('graphite', 'Графит', [Color(0xFF485563), Color(0xFF29323C)]),
    DvWallpaperPreset('rose', 'Роза', [Color(0xFFF7CAC9), Color(0xFF92A8D1)]),
  ];

  static DvWallpaperPreset? byId(String id) {
    for (final p in all) {
      if (p.id == id) return p;
    }
    return null;
  }
}
