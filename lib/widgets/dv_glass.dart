// SPDX-License-Identifier: AGPL-3.0-or-later

// DVChat: полупрозрачные панели и меню в одном стиле: прозрачность 40%, БЕЗ размытия
// (размытие нагружало видеоядро и давало тормоза). Меню открывается у кнопки.

import 'package:material_ui/material_ui.dart';

/// Прозрачность панелей: 40% прозрачности = 60% непрозрачности (alpha 153 из 255). Один стиль на всё приложение.
const int kDvGlassAlpha = 153;

/// Полупрозрачная панель (без размытия): заливка цвета страницы, лёгкая светлая кромка.
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

  /// Не используется: размытия больше нет. Параметр оставлен, чтобы не менять вызовы.
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
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          color: base.withAlpha(opaque ? (dark ? 238 : 244) : kDvGlassAlpha),
          border: Border.all(
            color: Colors.white.withAlpha(dark ? 38 : 140),
            width: 1,
          ),
        ),
        child: Padding(padding: padding, child: child),
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
                    child: _GlassMenuBody<T>(items: items),
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

/// Панель меню
class _GlassMenuBody<T> extends StatelessWidget {
  const _GlassMenuBody({required this.items});

  final List<DvGlassMenuItem<T>> items;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DvGlass(
      radius: 24,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: SizedBox(
        width: _menuWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0 && items[i].dividerBefore)
                Divider(
                  height: 9,
                  indent: 62,
                  endIndent: 16,
                  color: scheme.outlineVariant.withAlpha(110),
                ),
              _GlassMenuRow<T>(item: items[i]),
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

/// Окно (диалог) в том же стиле: полупрозрачная панель без размытия, заголовок, содержимое, кнопки.
/// Клавиатура поднимает окно сама (его сдвигает Dialog), содержимое прокручивается.
class DvGlassDialog extends StatelessWidget {
  const DvGlassDialog({
    required this.title,
    required this.child,
    required this.actions,
    super.key,
  });

  final String title;
  final Widget child;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: DvGlass(
          radius: 24,
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              Flexible(child: SingleChildScrollView(child: child)),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  for (var i = 0; i < actions.length; i++) ...[
                    if (i > 0) const SizedBox(width: 8),
                    actions[i],
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
