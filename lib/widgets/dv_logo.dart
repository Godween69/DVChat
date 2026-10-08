// DVChat: логотип. D это кольцо, из которого по касательной вырастает левая
// ножка буквы V (кольцо переходит в V без излома).

import 'package:fluffychat/config/app_config.dart';
import 'package:material_ui/material_ui.dart';

class DvLogo extends StatelessWidget {
  final double size;
  const DvLogo({this.size = 128, super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: const CustomPaint(painter: _DvLogoPainter()),
    );
  }
}

class _DvLogoPainter extends CustomPainter {
  const _DvLogoPainter();

  @override
  void paint(Canvas canvas, Size size) {
    // Рисуем в сетке 100x100 и масштабируем под нужный размер
    final k = size.width / 100;
    Offset p(double x, double y) => Offset(x * k, y * k);

    // Фон: круг фирменного цвета
    canvas.drawCircle(
      p(50, 50),
      50 * k,
      Paint()..color = AppConfig.primaryColor,
    );

    // Знак чуть уменьшаем относительно центра, чтобы не касался края круга
    canvas.translate(50 * k, 50 * k);
    canvas.scale(0.82);
    canvas.translate(-50 * k, -50 * k);

    final stroke = Paint()
      ..color = const Color(0xFFFFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8 * k
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // D: кольцо
    canvas.drawCircle(p(34, 47), 22 * k, stroke);

    // V: левая ножка отходит от кольца по касательной, правая уходит вверх
    final v = Path()
      ..moveTo(54.7 * k, 39.5 * k)
      ..lineTo(68.3 * k, 77 * k)
      ..lineTo(87.8 * k, 23 * k);
    canvas.drawPath(v, stroke);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
