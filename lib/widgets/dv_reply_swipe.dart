// SPDX-License-Identifier: AGPL-3.0-or-later

// DVChat: свайп сообщения для ответа. Свой виджет вместо swipe_to_action:
// сообщение едет за пальцем без перестроения, у порога лёгкий отклик,
// после отпускания возвращается пружиной. Принимает жест только в одну сторону,
// поэтому вертикальная прокрутка ленты не страдает.

import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

class DvReplySwipe extends StatefulWidget {
  const DvReplySwipe({
    required this.onReply,
    required this.leftwards,
    required this.child,
    this.enabled = true,
    super.key,
  });

  final VoidCallback onReply;

  /// true: тянуть справа налево, false: слева направо
  final bool leftwards;
  final bool enabled;
  final Widget child;

  @override
  State<DvReplySwipe> createState() => _DvReplySwipeState();
}

class _DvReplySwipeState extends State<DvReplySwipe>
    with SingleTickerProviderStateMixin {
  static const double _threshold = 64;
  static const double _maxPull = 96;

  late final AnimationController _spring = AnimationController.unbounded(
    vsync: this,
  );
  final ValueNotifier<double> _dx = ValueNotifier(0);
  double _raw = 0;
  bool _armed = false;

  @override
  void initState() {
    super.initState();
    _spring.addListener(() => _dx.value = _spring.value);
  }

  @override
  void dispose() {
    _spring.dispose();
    _dx.dispose();
    super.dispose();
  }

  void _start(DragStartDetails d) {
    _spring.stop();
    _raw = _dx.value;
    _armed = _raw >= _threshold;
  }

  void _update(DragUpdateDetails d) {
    final delta = widget.leftwards ? -d.delta.dx : d.delta.dx;
    _raw = (_raw + delta).clamp(0.0, 1000.0);
    // За порогом палец тянет втрое тяжелее: упругое сопротивление
    final shown = _raw <= _threshold
        ? _raw
        : (_threshold + (_raw - _threshold) * 0.3).clamp(0.0, _maxPull);
    _dx.value = shown;
    final armed = _raw >= _threshold;
    if (armed != _armed) {
      _armed = armed;
      if (armed) unawaited(HapticFeedback.selectionClick());
    }
  }

  void _end(DragEndDetails d) {
    final reply = _raw >= _threshold;
    _raw = 0;
    _armed = false;
    if (reply) widget.onReply();
    final v = widget.leftwards
        ? -d.velocity.pixelsPerSecond.dx
        : d.velocity.pixelsPerSecond.dx;
    _spring.value = _dx.value;
    _spring.animateWith(
      SpringSimulation(
        const SpringDescription(mass: 1, stiffness: 420, damping: 32),
        _dx.value,
        0,
        v.clamp(-2000.0, 2000.0),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    final theme = Theme.of(context);
    return RawGestureDetector(
      behavior: HitTestBehavior.translucent,
      gestures: {
        _SideDragRecognizer:
            GestureRecognizerFactoryWithHandlers<_SideDragRecognizer>(
              () => _SideDragRecognizer(leftwards: widget.leftwards),
              (r) => r
                ..leftwards = widget.leftwards
                ..onStart = _start
                ..onUpdate = _update
                ..onEnd = _end
                ..onCancel = () => _end(DragEndDetails()),
            ),
      },
      child: Stack(
        children: [
          // Значок «ответить» проявляется и растёт по мере движения
          Positioned.fill(
            child: ValueListenableBuilder<double>(
              valueListenable: _dx,
              builder: (context, dx, _) {
                final p = (dx / _threshold).clamp(0.0, 1.0);
                if (p <= 0) return const SizedBox.shrink();
                return Align(
                  alignment: widget.leftwards
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Opacity(
                      opacity: p,
                      child: Transform.scale(
                        scale: 0.55 + 0.45 * p,
                        child: Material(
                          color: theme.colorScheme.primaryContainer,
                          elevation: 1 + 2 * p,
                          shadowColor: Colors.black,
                          shape: const CircleBorder(),
                          child: Padding(
                            padding: const EdgeInsets.all(8),
                            child: Icon(
                              Icons.reply_outlined,
                              size: 20,
                              color: theme.colorScheme.onPrimaryContainer,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          // Само сообщение: двигается матрицей, содержимое не перестраивается
          ValueListenableBuilder<double>(
            valueListenable: _dx,
            child: widget.child,
            builder: (context, dx, child) => Transform.translate(
              offset: Offset(widget.leftwards ? -dx : dx, 0),
              child: child,
            ),
          ),
        ],
      ),
    );
  }
}

/// Принимает горизонтальный жест только в нужную сторону
class _SideDragRecognizer extends HorizontalDragGestureRecognizer {
  _SideDragRecognizer({required this.leftwards});

  bool leftwards;
  double _sum = 0;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    _sum = 0;
    super.addAllowedPointer(event);
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerMoveEvent) _sum += event.delta.dx;
    super.handleEvent(event);
  }

  @override
  bool hasSufficientGlobalDistanceToAccept(
    PointerDeviceKind pointerDeviceKind,
    double? deviceTouchSlop,
  ) =>
      (leftwards ? _sum < 0 : _sum > 0) &&
      super.hasSufficientGlobalDistanceToAccept(
        pointerDeviceKind,
        deviceTouchSlop,
      );
}
