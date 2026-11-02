// SPDX-License-Identifier: AGPL-3.0-or-later

// DVChat: живая волна при записи голоса. Полосы толще и реже, новая полоса
// плавно выезжает справа, соседние значения сглажены: никакой дёрганости.

import 'package:material_ui/material_ui.dart';

class DvLiveWave extends StatefulWidget {
  const DvLiveWave({required this.samples, required this.color, super.key});

  /// Громкость 1..100, список растёт на месте раз в 100 мс
  final List<double> samples;
  final Color color;

  @override
  State<DvLiveWave> createState() => _DvLiveWaveState();
}

class _DvLiveWaveState extends State<DvLiveWave>
    with SingleTickerProviderStateMixin {
  static const Duration _sampleEvery = Duration(milliseconds: 100);

  late final AnimationController _frames = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 1),
  )..repeat();

  int _len = 0;
  DateTime _stamp = DateTime.now();

  @override
  void dispose() {
    _frames.dispose();
    super.dispose();
  }

  /// 0..1: сколько прошло с появления последнего значения
  double _progress() {
    final n = widget.samples.length;
    if (n != _len) {
      _len = n;
      _stamp = DateTime.now();
    }
    final t =
        DateTime.now().difference(_stamp).inMilliseconds /
        _sampleEvery.inMilliseconds;
    return Curves.easeOut.transform(t.clamp(0.0, 1.0));
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 36,
    width: double.infinity,
    child: CustomPaint(
      painter: _WavePainter(
        repaint: _frames,
        samples: widget.samples,
        color: widget.color,
        progress: _progress,
      ),
    ),
  );
}

class _WavePainter extends CustomPainter {
  _WavePainter({
    required Listenable repaint,
    required this.samples,
    required this.color,
    required this.progress,
  }) : super(repaint: repaint);

  final List<double> samples;
  final Color color;
  final double Function() progress;

  static const double _barW = 5;
  static const double _step = 12;

  double _smooth(int i) {
    final n = samples.length;
    final prev = samples[i > 0 ? i - 1 : i];
    final next = samples[i < n - 1 ? i + 1 : i];
    return prev * 0.25 + samples[i] * 0.5 + next * 0.25;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final n = samples.length;
    if (n == 0) return;
    final p = progress();
    canvas.clipRect(Offset.zero & size);
    final cy = size.height / 2;
    final count = (size.width / _step).ceil() + 2;
    final paint = Paint();
    for (var j = 0; j < count; j++) {
      final idx = n - 1 - j;
      if (idx < 0) break;
      var v = _smooth(idx) / 100;
      if (j == 0) v *= p;
      final h = (size.height * 0.92 * v).clamp(4.0, size.height);
      final x = size.width - _barW + (1 - p) * _step - j * _step;
      final t = (x / size.width).clamp(0.0, 1.0);
      paint.color = color.withValues(alpha: 0.3 + 0.7 * t);
      canvas.drawRRect(
        RRect.fromLTRBR(
          x,
          cy - h / 2,
          x + _barW,
          cy + h / 2,
          const Radius.circular(_barW / 2),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_WavePainter old) =>
      old.samples != samples || old.color != color;
}
