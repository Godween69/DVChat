// SPDX-License-Identifier: AGPL-3.0-or-later

// DVChat: «стеклянные» панели. Полупрозрачная панель размывает то, что лежит под ней
// (современный «воздушный» вид), плюс стеклянное меню, которое открывается у кнопки.

import 'dart:ui' show ImageFilter;

import 'package:material_ui/material_ui.dart';

/// Стеклянная панель: размывает всё, что под ней, и слегка подкрашивает цветом страницы.
class DvGlass extends StatelessWidget {
  const DvGlass({
    required this.child,
    this.radius = 24,
    this.padding = EdgeInsets.zero,
    this.blur = 24,
    this.tint,
    this.opaque = false,
    super.key,
  });

  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;

  /// Сила размытия (сигма гауссова размытия, в точках)
  final double blur;

  /// Цвет подкраски (по умолчанию цвет страницы)
  final Color? tint;

  /// Почти непрозрачная панель (там, где под ней нет размытия, чтобы не просвечивал текст)
  final bool opaque;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final base = tint ?? theme.colorScheme.surface;
    final surface = AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            base.withAlpha(opaque ? (dark ? 238 : 244) : (dark ? 160 : 200)),
            base.withAlpha(opaque ? (dark ? 228 : 236) : (dark ? 115 : 150)),
          ],
        ),
        border: Border.all(
          color: Colors.white.withAlpha(dark ? 38 : 140),
          width: 1,
        ),
      ),
      child: child,
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      // blur <= 0: без размытия под панелью (нужно на время анимации, когда оно тормозит)
      child: blur <= 0
          ? surface
          : BackdropFilter(
              filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
              child: surface,
            ),
    );
  }
}

/// Мягкий цветной фон под стеклянными панелями (без него стеклу нечего размывать).
class DvGlassBackdrop extends StatelessWidget {
  const DvGlassBackdrop({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Stack(
      children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  scheme.primaryContainer.withAlpha(120),
                  scheme.surface,
                  scheme.tertiaryContainer.withAlpha(120),
                ],
              ),
            ),
          ),
        ),
        Positioned.fill(child: child),
      ],
    );
  }
}

/// Пункт стеклянного меню
class DvGlassMenuItem<T> {
  const DvGlassMenuItem({
    required this.value,
    required this.icon,
    required this.title,
    this.destructive = false,
    this.color,
    this.dividerBefore = false,
  });

  final T value;
  final IconData icon;
  final String title;

  /// Опасное действие (красным цветом)
  final bool destructive;

  /// Цвет значка (цветной кружок за значком); по умолчанию цвет темы
  final Color? color;

  /// Тонкая черта над пунктом (разделяет группы)
  final bool dividerBefore;
}

/// Где открывать стеклянное меню относительно кнопки
enum DvGlassMenuPlace {
  /// под кнопкой, у её правого края (три точки в шапке)
  belowEnd,

  /// над кнопкой, у её левого края (плюс в строке ввода)
  aboveStart,

  /// под или над виджетом по центру, где больше места (долгое нажатие на чат)
  auto,
}

/// Красивые цвета значков в меню (мягкие, хорошо видны на светлой и тёмной теме)
class DvMenuColors {
  const DvMenuColors._();

  static const Color blue = Color(0xFF4C8DF6);
  static const Color green = Color(0xFF34B27B);
  static const Color orange = Color(0xFFF59A3C);
  static const Color pink = Color(0xFFEA5C8B);
  static const Color purple = Color(0xFF8A6CF0);
  static const Color teal = Color(0xFF23B5C4);
  static const Color red = Color(0xFFE5534B);
  static const Color amber = Color(0xFFE9B028);
}

const double _menuWidth = 260;

/// Стеклянное меню у кнопки [anchor]. Возвращает выбранное значение или null, если меню закрыли.
/// Размытие включается, когда анимация закончилась: пока меню движется, размывать то, что под
/// ним (ленту чата), слишком дорого и меню тормозит.
Future<T?> showDvGlassMenu<T>(
  BuildContext anchor, {
  required List<DvGlassMenuItem<T>> items,
  DvGlassMenuPlace place = DvGlassMenuPlace.belowEnd,
}) {
  final screen = MediaQuery.sizeOf(anchor);
  final pad = MediaQuery.paddingOf(anchor);
  var rect = Rect.fromLTWH(screen.width - 56, pad.top, 48, 56);
  final box = anchor.findRenderObject();
  if (box is RenderBox && box.hasSize) {
    rect = box.localToGlobal(Offset.zero) & box.size;
  }
  final estHeight = items.length * 52.0 + 16;
  var up = place == DvGlassMenuPlace.aboveStart;
  if (place == DvGlassMenuPlace.auto) {
    up = rect.bottom + estHeight > screen.height - pad.bottom - 8;
  }
  double? left;
  double? right;
  switch (place) {
    case DvGlassMenuPlace.belowEnd:
      right = (screen.width - rect.right).clamp(8.0, screen.width);
    case DvGlassMenuPlace.aboveStart:
      left = rect.left.clamp(8.0, screen.width - _menuWidth - 8);
    case DvGlassMenuPlace.auto:
      left = (rect.center.dx - _menuWidth / 2).clamp(
        8.0,
        screen.width - _menuWidth - 8,
      );
  }
  final top = up ? null : rect.bottom + 4;
  final bottom = up ? screen.height - rect.top + 6 : null;
  final alignment = Alignment(
    right != null ? 1.0 : (place == DvGlassMenuPlace.auto ? 0.0 : -1.0),
    up ? 1.0 : -1.0,
  );
  return showGeneralDialog<T>(
    context: anchor,
    useRootNavigator: true,
    barrierDismissible: true,
    barrierLabel: 'Закрыть меню',
    barrierColor: Colors.black.withAlpha(60),
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (context, animation, secondaryAnimation) =>
        const SizedBox.shrink(),
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return Stack(
        children: [
          Positioned(
            top: top,
            bottom: bottom,
            left: left,
            right: right,
            child: FadeTransition(
              opacity: curved,
              child: ScaleTransition(
                alignment: alignment,
                scale: Tween<double>(begin: 0.9, end: 1).animate(curved),
                child: Material(
                  type: MaterialType.transparency,
                  child: RepaintBoundary(
                    child: _GlassMenuBody<T>(
                      items: items,
                      animation: animation,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    },
  );
}

/// Панель меню: на время движения без размытия, потом с размытием
class _GlassMenuBody<T> extends StatefulWidget {
  const _GlassMenuBody({required this.items, required this.animation});

  final List<DvGlassMenuItem<T>> items;
  final Animation<double> animation;

  @override
  State<_GlassMenuBody<T>> createState() => _GlassMenuBodyState<T>();
}

class _GlassMenuBodyState<T> extends State<_GlassMenuBody<T>> {
  bool _settled = false;

  @override
  void initState() {
    super.initState();
    widget.animation.addStatusListener(_onStatus);
  }

  @override
  void dispose() {
    widget.animation.removeStatusListener(_onStatus);
    super.dispose();
  }

  void _onStatus(AnimationStatus status) {
    final done = status == AnimationStatus.completed;
    if (done != _settled && mounted) setState(() => _settled = done);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DvGlass(
      radius: 24,
      blur: _settled ? 18 : 0,
      opaque: !_settled,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: SizedBox(
        width: _menuWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < widget.items.length; i++) ...[
              if (i > 0 && widget.items[i].dividerBefore)
                Divider(
                  height: 9,
                  indent: 62,
                  endIndent: 16,
                  color: scheme.outlineVariant.withAlpha(110),
                ),
              _GlassMenuRow<T>(item: widget.items[i]),
            ],
          ],
        ),
      ),
    );
  }
}

class _GlassMenuRow<T> extends StatelessWidget {
  const _GlassMenuRow({required this.item});

  final DvGlassMenuItem<T> item;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = item.destructive
        ? DvMenuColors.red
        : (item.color ?? scheme.primary);
    final textColor = item.destructive ? scheme.error : scheme.onSurface;
    return InkWell(
      onTap: () => Navigator.of(context, rootNavigator: true).pop(item.value),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: accent.withAlpha(42),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(item.icon, size: 21, color: accent),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                item.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 16, color: textColor),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
