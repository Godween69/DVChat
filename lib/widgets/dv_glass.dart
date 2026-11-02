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
    super.key,
  });

  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;

  /// Сила размытия (сигма гауссова размытия, в точках)
  final double blur;

  /// Цвет подкраски (по умолчанию цвет страницы)
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final base = tint ?? theme.colorScheme.surface;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                base.withAlpha(dark ? 160 : 200),
                base.withAlpha(dark ? 115 : 150),
              ],
            ),
            border: Border.all(
              color: Colors.white.withAlpha(dark ? 38 : 140),
              width: 1,
            ),
          ),
          child: child,
        ),
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
  });

  final T value;
  final IconData icon;
  final String title;

  /// Опасное действие (красным цветом)
  final bool destructive;
}

/// Стеклянное меню у кнопки [anchor] (например, «три точки» в шапке). Возвращает выбранное
/// значение или null, если меню закрыли.
Future<T?> showDvGlassMenu<T>(
  BuildContext anchor, {
  required List<DvGlassMenuItem<T>> items,
}) {
  final screen = MediaQuery.sizeOf(anchor);
  var top = MediaQuery.paddingOf(anchor).top + 56.0;
  var right = 8.0;
  final box = anchor.findRenderObject();
  if (box is RenderBox && box.hasSize) {
    final p = box.localToGlobal(Offset.zero);
    top = p.dy + box.size.height;
    right = (screen.width - (p.dx + box.size.width)).clamp(8.0, screen.width);
  }
  return showGeneralDialog<T>(
    context: anchor,
    useRootNavigator: true,
    barrierDismissible: true,
    barrierLabel: 'Закрыть меню',
    barrierColor: Colors.black.withAlpha(70),
    transitionDuration: const Duration(milliseconds: 200),
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
            right: right,
            child: FadeTransition(
              opacity: curved,
              child: ScaleTransition(
                alignment: Alignment.topRight,
                scale: Tween<double>(begin: 0.85, end: 1).animate(curved),
                child: Material(
                  type: MaterialType.transparency,
                  child: DvGlass(
                    radius: 22,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: SizedBox(
                      width: 252,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (var i = 0; i < items.length; i++) ...[
                            if (i > 0)
                              Divider(
                                height: 1,
                                indent: 56,
                                endIndent: 16,
                                color: Theme.of(
                                  context,
                                ).colorScheme.outlineVariant.withAlpha(90),
                              ),
                            _GlassMenuRow<T>(item: items[i]),
                          ],
                        ],
                      ),
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

class _GlassMenuRow<T> extends StatelessWidget {
  const _GlassMenuRow({required this.item});

  final DvGlassMenuItem<T> item;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = item.destructive ? scheme.error : scheme.onSurface;
    return InkWell(
      onTap: () => Navigator.of(context, rootNavigator: true).pop(item.value),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
        child: Row(
          children: [
            Icon(item.icon, size: 22, color: color),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                item.title,
                style: TextStyle(fontSize: 16, color: color),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
