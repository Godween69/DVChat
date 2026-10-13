// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:dvchat/widgets/dv_logo.dart';
import 'package:material_ui/material_ui.dart';

/// DVChat: заставка при холодном запуске — крупный логотип, плавное появление
/// и плавное исчезновение. Показывается один раз за запуск приложения.
class DvSplash extends StatefulWidget {
  const DvSplash({required this.child, super.key});

  final Widget child;

  /// Заставка уже показана в этом запуске?
  static bool _done = false;

  @override
  State<DvSplash> createState() => _DvSplashState();
}

class _DvSplashState extends State<DvSplash>
    with SingleTickerProviderStateMixin {
  // Полная длительность: появление ~0.65 с, пауза ~1.15 с, исчезновение ~0.8 с
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  );
  bool _visible = !DvSplash._done;

  @override
  void initState() {
    super.initState();
    if (_visible) {
      _controller.forward().whenComplete(() {
        DvSplash._done = true;
        if (mounted) setState(() => _visible = false);
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible) return widget.child;
    // Цвет фона совпадает с системной заставкой (день — белый, ночь — тёмно-синий)
    final dark = MediaQuery.platformBrightnessOf(context) == Brightness.dark;
    final background = dark ? const Color(0xFF0D1522) : const Color(0xFFFFFFFF);
    final logoSize = (MediaQuery.sizeOf(context).shortestSide * 0.55).clamp(
      160.0,
      300.0,
    );
    return Stack(
      textDirection: TextDirection.ltr,
      children: [
        widget.child,
        Positioned.fill(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              final t = _controller.value;
              final appear = Curves.easeOut.transform(
                (t / 0.25).clamp(0.0, 1.0),
              );
              final vanish = Curves.easeIn.transform(
                ((t - 0.70) / 0.30).clamp(0.0, 1.0),
              );
              return IgnorePointer(
                ignoring: vanish > 0.6,
                child: Opacity(
                  opacity: 1 - vanish,
                  child: ColoredBox(
                    color: background,
                    child: Center(
                      child: Opacity(
                        opacity: appear,
                        child: Transform.scale(
                          scale: 0.9 + 0.1 * appear,
                          child: DvLogo(size: logoSize),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
