// SPDX-License-Identifier: AGPL-3.0-or-later

// DVChat: красивый индикатор ожидания (кольца с хвостом, вращаются с разной скоростью,
// в центре пульсирующая точка) и затемнение на весь экран с подписью на время долгой работы.

import 'dart:math' as math;

import 'package:dvchat/widgets/dv_glass.dart';
import 'package:material_ui/material_ui.dart';

/// Индикатор ожидания. С подписью [label] рисуется колонкой «кольца + текст».
class DvLoader extends StatefulWidget {
  const DvLoader({this.size = 56, this.label, super.key});

  final double size;
  final String? label;

  @override
  State<DvLoader> createState() => _DvLoaderState();
}

class _DvLoaderState extends State<DvLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final ring = SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => CustomPaint(
          painter: _LoaderPainter(
            t: _controller.value,
            a: scheme.primary,
            b: scheme.tertiary,
          ),
        ),
      ),
    );
    final label = widget.label;
    if (label == null) return ring;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ring,
        const SizedBox(height: 16),
        Text(
          label,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _LoaderPainter extends CustomPainter {
  _LoaderPainter({required this.t, required this.a, required this.b});

  /// Время цикла от 0 до 1
  final double t;
  final Color a;
  final Color b;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final outer = size.shortestSide / 2;
    final stroke = size.shortestSide * 0.075;
    const sweep = math.pi * 1.25;
    for (var i = 0; i < 3; i++) {
      final radius = outer - stroke / 2 - i * stroke * 1.9;
      if (radius <= 0) continue;
      final dir = i.isEven ? 1.0 : -1.0;
      final start = dir * t * 2 * math.pi * (1 + i * 0.55) + i * 2.1;
      final color = Color.lerp(a, b, i / 2)!;
      final rect = Rect.fromCircle(center: center, radius: radius);
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..shader = SweepGradient(
          startAngle: 0,
          endAngle: sweep,
          colors: dir > 0
              ? [color.withAlpha(0), color]
              : [color, color.withAlpha(0)],
          transform: GradientRotation(start),
        ).createShader(rect);
      canvas.drawArc(rect, start, sweep, false, paint);
    }
    final pulse = 0.5 + 0.5 * math.sin(t * 2 * math.pi * 3);
    canvas.drawCircle(
      center,
      size.shortestSide * (0.05 + 0.035 * pulse),
      Paint()..color = Color.lerp(a, b, pulse)!,
    );
  }

  @override
  bool shouldRepaint(_LoaderPainter old) =>
      old.t != t || old.a != a || old.b != b;
}

/// Затемнение на весь экран со стеклянной карточкой («идёт сжатие, подождите немного»).
/// Показывается поверх всего приложения, убирается вызовом [close].
class DvBusyOverlay {
  DvBusyOverlay._(this._entry);

  final OverlayEntry _entry;
  bool _closed = false;

  /// Показывает затемнение. Возвращает null, если экрана уже нет.
  static DvBusyOverlay? show(BuildContext context, String text) {
    if (!context.mounted) return null;
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return null;
    final entry = OverlayEntry(
      builder: (context) => Positioned.fill(child: _BusyCard(text: text)),
    );
    overlay.insert(entry);
    return DvBusyOverlay._(entry);
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _entry.remove();
    _entry.dispose();
  }
}

class _BusyCard extends StatelessWidget {
  const _BusyCard({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const ModalBarrier(dismissible: false, color: Colors.black54),
        Center(
          child: Material(
            type: MaterialType.transparency,
            child: DvGlass(
              radius: 28,
              padding: const EdgeInsets.fromLTRB(32, 28, 32, 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 240),
                child: DvLoader(size: 76, label: text),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
