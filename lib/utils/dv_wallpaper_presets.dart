// SPDX-License-Identifier: AGPL-3.0-or-later

// DVChat: готовые обои чата. Это градиенты, нарисованные кодом: файлов нет, весят ноль,
// работают без сети и не тормозят ленту. Цвета полупрозрачные, чтобы сообщения читались.

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Вид рисунка на обоях
enum DvPattern { mix, swirls, sprigs, flowers }

class DvWallpaperPreset {
  const DvWallpaperPreset(
    this.id,
    this.name,
    this.colors, [
    this.pattern = DvPattern.mix,
  ]);

  final String id;
  final String name;
  final List<Color> colors;
  final DvPattern pattern;

  /// Цвет «карандаша» для рисунка: в тёмной теме светлый и бледный, в светлой тёмный
  /// оттенок самих обоев. Рисунок тонкий, чтобы текст оставался читаемым.
  Color ink({required bool dark}) {
    if (dark) return const Color(0xFFFFFFFF).withAlpha(0x22);
    final hsl = HSLColor.fromColor(colors.last);
    return hsl.withLightness(0.22).withSaturation(0.5).toColor().withAlpha(0x34);
  }

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
    DvWallpaperPreset('dusk', 'Сумерки', [Color(0xFF355C7D), Color(0xFF6C5B7B), Color(0xFFC06C84)], DvPattern.swirls),
    DvWallpaperPreset('sea', 'Море', [Color(0xFF00B4DB), Color(0xFF0083B0)], DvPattern.swirls),
    DvWallpaperPreset('forest', 'Лес', [Color(0xFF134E5E), Color(0xFF71B280)], DvPattern.sprigs),
    DvWallpaperPreset('peach', 'Персик', [Color(0xFFFFB88C), Color(0xFFDE6262)], DvPattern.flowers),
    DvWallpaperPreset('ice', 'Лёд', [Color(0xFF9CECFB), Color(0xFF65C7F7), Color(0xFF0052D4)], DvPattern.sprigs),
    DvWallpaperPreset('lavender', 'Лаванда', [Color(0xFFC9B6E4), Color(0xFF8E7CC3)], DvPattern.flowers),
    DvWallpaperPreset('sunrise', 'Рассвет', [Color(0xFFFFE259), Color(0xFFFFA751)], DvPattern.mix),
    DvWallpaperPreset('berry', 'Ягода', [Color(0xFF8E2DE2), Color(0xFF4A00E0)], DvPattern.flowers),
    DvWallpaperPreset('graphite', 'Графит', [Color(0xFF485563), Color(0xFF29323C)], DvPattern.swirls),
    DvWallpaperPreset('rose', 'Роза', [Color(0xFFF7CAC9), Color(0xFF92A8D1)], DvPattern.mix),
  ];

  static DvWallpaperPreset? byId(String id) {
    for (final p in all) {
      if (p.id == id) return p;
    }
    return null;
  }
}

/// Обои целиком: градиент и поверх него тонкий рисунок. Один и тот же слой
/// рисует ленту чата и превью в настройках, поэтому они выглядят одинаково.
class DvWallpaperLayer extends StatelessWidget {
  const DvWallpaperLayer({super.key, required this.preset, required this.dark});

  final DvWallpaperPreset preset;
  final bool dark;

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      DecoratedBox(decoration: BoxDecoration(gradient: preset.gradient(dark: dark))),
      RepaintBoundary(
        child: CustomPaint(
          size: Size.infinite,
          painter: DvPatternPainter(preset.pattern, preset.ink(dark: dark)),
        ),
      ),
    ],
  );
}

/// Рисунок «как на бумажных обоях»: завитки, веточки с листьями, цветочки. Нарисован
/// линиями с круглыми концами, как карандашом. Плитки по 150 пикселей, в каждой свои
/// мотивы со сдвигом и поворотом; случайность посчитана заранее по номеру плитки,
/// поэтому рисунок не мерцает и не меняется между перерисовками.
class DvPatternPainter extends CustomPainter {
  DvPatternPainter(this.kind, this.ink);

  final DvPattern kind;
  final Color ink;

  static const double _tile = 150;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final cols = (size.width / _tile).ceil() + 1;
    final rows = (size.height / _tile).ceil() + 1;
    for (var y = 0; y < rows; y++) {
      for (var x = 0; x < cols; x++) {
        final rnd = math.Random(x * 7919 + y * 104729 + kind.index * 31);
        // Каждая вторая строка сдвинута, чтобы не было видно решётки
        final shift = y.isOdd ? _tile / 2 : 0.0;
        for (var k = 0; k < 2; k++) {
          final cx = x * _tile + shift + _tile * (0.25 + 0.5 * k) + rnd.nextDouble() * 24 - 12;
          final cy = y * _tile + _tile * (0.28 + 0.44 * k) + rnd.nextDouble() * 24 - 12;
          final angle = (rnd.nextDouble() - 0.5) * math.pi * 0.9;
          final pick = switch (kind) {
            DvPattern.swirls => 0,
            DvPattern.sprigs => 1,
            DvPattern.flowers => 2,
            DvPattern.mix => rnd.nextInt(3),
          };
          canvas.save();
          canvas.translate(cx, cy);
          canvas.rotate(angle);
          switch (pick) {
            case 0:
              _swirl(canvas, paint, 20 + rnd.nextDouble() * 8);
            case 1:
              _sprig(canvas, paint, 46 + rnd.nextDouble() * 12);
            default:
              _flower(canvas, paint, 14 + rnd.nextDouble() * 5);
          }
          canvas.restore();
        }
        // Мелкие точки-ягодки между мотивами
        for (var d = 0; d < 3; d++) {
          canvas.drawCircle(
            Offset(x * _tile + rnd.nextDouble() * _tile, y * _tile + rnd.nextDouble() * _tile),
            1.1,
            paint,
          );
        }
      }
    }
  }

  /// Завиток-спираль с хвостиком
  void _swirl(Canvas c, Paint p, double r) {
    final path = Path()..moveTo(-r * 1.6, r * 0.9);
    path.quadraticBezierTo(-r * 0.9, r * 0.2, -r * 0.2, r * 0.7);
    for (var a = 0.0; a <= math.pi * 2.6; a += 0.2) {
      final rad = r * (1 - a / (math.pi * 3.0));
      path.lineTo(math.cos(a + math.pi / 2) * rad, math.sin(a + math.pi / 2) * rad - r * 0.1);
    }
    c.drawPath(path, p);
  }

  /// Веточка с парами листиков
  void _sprig(Canvas c, Paint p, double len) {
    final stem = Path()
      ..moveTo(0, len / 2)
      ..quadraticBezierTo(len * 0.22, 0, 0, -len / 2);
    c.drawPath(stem, p);
    for (final t in const [0.2, 0.45, 0.7]) {
      final y = len / 2 - len * t;
      for (final side in const [-1.0, 1.0]) {
        c.save();
        c.translate(len * 0.07 * (1 - (t - 0.5).abs() * 2), y);
        c.rotate(side * 0.9);
        _leaf(c, p, len * 0.26);
        c.restore();
      }
    }
    c.save();
    c.translate(0, -len / 2);
    _leaf(c, p, len * 0.24);
    c.restore();
  }

  /// Листик: два изогнутых края, сходящихся в острый кончик
  void _leaf(Canvas c, Paint p, double l) {
    final path = Path()
      ..moveTo(0, 0)
      ..quadraticBezierTo(l * 0.42, -l * 0.35, 0, -l)
      ..quadraticBezierTo(-l * 0.42, -l * 0.35, 0, 0);
    c.drawPath(path, p);
  }

  /// Цветок: пять лепестков и серединка, снизу короткий стебелёк
  void _flower(Canvas c, Paint p, double r) {
    for (var i = 0; i < 5; i++) {
      c.save();
      c.rotate(i * math.pi * 2 / 5);
      c.drawOval(Rect.fromCenter(center: Offset(0, -r * 0.62), width: r * 0.62, height: r * 0.95), p);
      c.restore();
    }
    c.drawCircle(Offset.zero, r * 0.2, p);
    final stem = Path()
      ..moveTo(0, r * 0.9)
      ..quadraticBezierTo(r * 0.4, r * 1.6, 0, r * 2.2);
    c.drawPath(stem, p);
  }

  @override
  bool shouldRepaint(DvPatternPainter old) => old.kind != kind || old.ink != ink;
}
