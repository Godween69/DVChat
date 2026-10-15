// SPDX-License-Identifier: AGPL-3.0-or-later

// DVChat: строка списка со смахиванием влево. Строка уезжает в сторону и открывает
// плашку действия (в архив, удалить, прочитано и т.д.). Нажатие на плашку выполняет
// действие, нажатие на строку закрывает плашку. Одновременно открыта одна строка.
//
// Жест реагирует только на движение влево (или вправо, когда плашка уже открыта).
// Движение вправо и жесты по пустому месту достаются листанию вкладок.

import 'dart:async';

import 'package:dvchat/utils/dv_list_style.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

class DvSwipeAction {
  const DvSwipeAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onColor,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final Color onColor;
  final VoidCallback onTap;
}

class DvSwipeRow extends StatefulWidget {
  const DvSwipeRow({
    required this.rowId,
    required this.actionBuilder,
    required this.child,
    super.key,
  });

  final String rowId;

  /// Действие считается заново при каждой отрисовке, чтобы настройка действовала сразу
  final DvSwipeAction? Function() actionBuilder;
  final Widget child;

  /// Идентификатор открытой сейчас строки (остальные закрываются)
  static final ValueNotifier<String?> _open = ValueNotifier<String?>(null);

  @override
  State<DvSwipeRow> createState() => _DvSwipeRowState();
}

class _DvSwipeRowState extends State<DvSwipeRow>
    with SingleTickerProviderStateMixin {
  static const double _panelWidth = 84;

  late final AnimationController _c = AnimationController(vsync: this);

  @override
  void initState() {
    super.initState();
    DvSwipeRow._open.addListener(_onOpenChanged);
  }

  @override
  void dispose() {
    DvSwipeRow._open.removeListener(_onOpenChanged);
    _c.dispose();
    super.dispose();
  }

  void _onOpenChanged() {
    if (DvSwipeRow._open.value != widget.rowId && _c.value > 0) _animate(0);
  }

  void _animate(double to) {
    unawaited(
      _c.animateTo(
        to,
        duration: const Duration(milliseconds: 190),
        curve: Curves.easeOutCubic,
      ),
    );
  }

  bool get _isOpen => _c.value > 0.02;

  void _dragUpdate(DragUpdateDetails d) {
    _c.stop();
    _c.value = (_c.value - d.delta.dx / _panelWidth).clamp(0.0, 1.0);
  }

  void _dragEnd(DragEndDetails d) {
    final v = d.primaryVelocity ?? 0;
    _settle(v < -450 || (v <= 450 && _c.value > 0.5));
  }

  void _settle(bool open) {
    if (open) {
      if (DvSwipeRow._open.value != widget.rowId) {
        HapticFeedback.selectionClick();
        DvSwipeRow._open.value = widget.rowId;
      }
    } else if (DvSwipeRow._open.value == widget.rowId) {
      DvSwipeRow._open.value = null;
    }
    _animate(open ? 1 : 0);
  }

  Widget _panel(BuildContext context) {
    final action = widget.actionBuilder();
    if (action == null) return const SizedBox.shrink();
    final pad = DvListStyle.isPlain
        ? EdgeInsets.zero
        : DvListStyle.outerPadding.copyWith(left: 4);
    return Align(
      alignment: Alignment.centerRight,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, child) =>
            Opacity(opacity: _c.value.clamp(0.0, 1.0), child: child),
        child: SizedBox(
          width: _panelWidth,
          child: Padding(
            padding: pad,
            child: Material(
              color: action.color,
              shape: DvListStyle.shape(context),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () {
                  _settle(false);
                  action.onTap();
                },
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(action.icon, color: action.onColor, size: 24),
                      const SizedBox(height: 4),
                      Text(
                        action.label,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        style: TextStyle(
                          color: action.onColor,
                          fontSize: 11,
                          height: 1.1,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return RawGestureDetector(
      gestures: {
        _LeftDragRecognizer:
            GestureRecognizerFactoryWithHandlers<_LeftDragRecognizer>(
              () => _LeftDragRecognizer(
                enabled: () => widget.actionBuilder() != null,
                allowRight: () => _isOpen,
              ),
              (r) {
                r
                  ..onUpdate = _dragUpdate
                  ..onEnd = _dragEnd
                  ..onCancel = () => _settle(_c.value > 0.5);
              },
            ),
      },
      child: Stack(
        children: [
          Positioned.fill(child: _panel(context)),
          AnimatedBuilder(
            animation: _c,
            builder: (context, child) => Transform.translate(
              offset: Offset(-_c.value * _panelWidth, 0),
              child: Stack(
                children: [
                  child!,
                  // Пока плашка открыта, нажатие на строку только закрывает её
                  if (_c.value > 0.05)
                    Positioned.fill(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => _settle(false),
                      ),
                    ),
                ],
              ),
            ),
            child: widget.child,
          ),
        ],
      ),
    );
  }
}

/// Горизонтальное перетаскивание, которое принимает жест только при движении влево
/// (или вправо, если плашка уже открыта). Иначе жест достаётся листанию вкладок.
class _LeftDragRecognizer extends HorizontalDragGestureRecognizer {
  _LeftDragRecognizer({required this.enabled, required this.allowRight});

  final bool Function() enabled;
  final bool Function() allowRight;
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
      enabled() &&
      (_sum < 0 || allowRight()) &&
      super.hasSufficientGlobalDistanceToAccept(
        pointerDeviceKind,
        deviceTouchSlop,
      );
}
