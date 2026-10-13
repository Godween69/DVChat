// DVChat: Логотип DVChat как виджет.

import 'package:material_ui/material_ui.dart';

/// DVChat: логотип приложения (иконка с монограммой DV и чат-пузырём).
/// Берётся из assets/logo/mini/logo_mini.png, углы скруглены в самой картинке.
class DvLogo extends StatelessWidget {
  final double size;

  const DvLogo({this.size = 128, super.key});

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/logo/mini/logo_mini.png',
      width: size,
      height: size,
      filterQuality: FilterQuality.medium,
    );
  }
}
