// SPDX-License-Identifier: AGPL-3.0-or-later

// DVChat: страница «Что нового». После обновления один раз показывается на весь экран:
// листается свайпом, у каждого нововведения своя картинка-схема, нарисованная кодом.
// Чтобы показать страницу снова после следующего обновления, меняется contentId,
// а новые страницы дописываются в список _slides.

import 'dart:async';

import 'package:dvchat/utils/dv_wallpaper_presets.dart';
import 'package:dvchat/widgets/recording_animation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DvWhatsNew {
  /// Номер набора новостей: поменялся, значит, страницу нужно показать ещё раз
  static const String contentId = 'stage2-1';
  static const String _key = 'dv_whats_new_seen';
  static bool _shown = false;

  /// Показывает страницу один раз за запуск и один раз на набор новостей
  static Future<void> maybeShow(BuildContext context) async {
    if (_shown) return;
    _shown = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getString(_key) == contentId) return;
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      if (!context.mounted) return;
      await open(context);
      await prefs.setString(_key, contentId);
    } catch (_) {
      // страница необязательна
    }
  }

  static Future<void> open(BuildContext context) =>
      Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute<void>(
          fullscreenDialog: true,
          builder: (_) => const DvWhatsNewPage(),
        ),
      );
}

class _Slide {
  const _Slide(this.icon, this.color, this.title, this.text, this.art);

  final IconData icon;
  final Color color;
  final String title;
  final String text;
  final Widget Function(BuildContext context) art;
}

Widget _pill(BuildContext context, Widget child) => Container(
  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
  decoration: BoxDecoration(
    color: Theme.of(context).colorScheme.surfaceContainerHigh,
    borderRadius: BorderRadius.circular(18),
  ),
  child: child,
);

final List<_Slide> _slides = [
  _Slide(
    Icons.auto_stories,
    const Color(0xFFE8590C),
    'Истории и игры без лишнего шума',
    'В чатах больше нет служебных сообщений про истории и приглашения в игры. '
        'Вместо них приходит уведомление с именем друга.',
    (context) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final c in const [
              Color(0xFFE8590C),
              Color(0xFFC2255C),
              Color(0xFF7048E8),
            ])
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 6),
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(colors: [c, c.withAlpha(120)]),
                ),
                child: CircleAvatar(
                  radius: 24,
                  backgroundColor: Theme.of(context).colorScheme.surface,
                  child: Icon(Icons.person, color: c),
                ),
              ),
          ],
        ),
        const SizedBox(height: 14),
        _pill(context, const Text('Аня опубликовала новую историю')),
      ],
    ),
  ),
  _Slide(
    Icons.history,
    const Color(0xFF1C7ED6),
    'Старые сообщения подгружаются сами',
    'Кнопки «Загрузить больше» нет: листайте вверх, и история подтянется, '
        'как в привычных мессенджерах.',
    (context) => const Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.keyboard_arrow_up, size: 52),
        SizedBox(
          width: 26,
          height: 26,
          child: CircularProgressIndicator(strokeWidth: 3),
        ),
      ],
    ),
  ),
  _Slide(
    Icons.palette,
    const Color(0xFF7048E8),
    'Обои и тема значками',
    'Настройки → Оформление: десять готовых обоев, а светлую, тёмную или '
        'автоматическую тему выбирают цветные значки.',
    (context) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: [
            for (final p in DvWallpapers.all.take(6))
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: p.swatch,
                ),
              ),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.light_mode, color: Colors.amber.shade700, size: 32),
            const SizedBox(width: 16),
            Icon(Icons.dark_mode, color: Colors.indigo.shade400, size: 32),
            const SizedBox(width: 16),
            const Icon(Icons.brightness_auto, color: Colors.teal, size: 32),
          ],
        ),
      ],
    ),
  ),
  _Slide(
    Icons.shopping_cart,
    const Color(0xFF0CA678),
    'Список покупок удобнее',
    'Купленное отмечает любой участник чата. Автор списка может убрать '
        'лишний пункт крестиком.',
    (context) => SizedBox(
      width: 230,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final row in const [
            ('Молоко', true),
            ('Хлеб', true),
            ('Яйца', false),
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: _pill(
                context,
                Row(
                  children: [
                    Icon(
                      row.$2 ? Icons.check_circle : Icons.radio_button_unchecked,
                      color: row.$2 ? Colors.green : null,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        row.$1,
                        style: TextStyle(
                          decoration: row.$2 ? TextDecoration.lineThrough : null,
                        ),
                      ),
                    ),
                    if (!row.$2) const Icon(Icons.close, size: 18),
                  ],
                ),
              ),
            ),
        ],
      ),
    ),
  ),
  _Slide(
    Icons.person_add,
    const Color(0xFF2F9E44),
    'Заявки в друзья',
    'Зелёная галочка принимает заявку, красный крестик отклоняет. '
        'Рядом появляется подтверждение.',
    (context) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton.filledTonal(
          iconSize: 32,
          color: Colors.green.shade700,
          onPressed: () {},
          icon: const Icon(Icons.check),
        ),
        const SizedBox(width: 24),
        IconButton.filledTonal(
          iconSize: 32,
          color: Theme.of(context).colorScheme.error,
          onPressed: () {},
          icon: const Icon(Icons.close),
        ),
      ],
    ),
  ),
  _Slide(
    Icons.mic,
    const Color(0xFFE03131),
    'Видно, что записывают голосовое',
    'Пока собеседник записывает голосовое сообщение, под чатом бегут '
        'столбики и стоит подпись.',
    (context) => _pill(context, const RecordingAnimation()),
  ),
  _Slide(
    Icons.emoji_events,
    const Color(0xFFF08C00),
    'Статистика игр не пропадает',
    'Итоги партий хранятся в вашем аккаунте: после выхода и нового входа '
        'они возвращаются.',
    (context) => const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.emoji_events, size: 48, color: Color(0xFFF08C00)),
        SizedBox(width: 12),
        Icon(Icons.arrow_forward, size: 28),
        SizedBox(width: 12),
        Icon(Icons.cloud_done_outlined, size: 48, color: Color(0xFF1C7ED6)),
      ],
    ),
  ),
];

class DvWhatsNewPage extends StatefulWidget {
  const DvWhatsNewPage({super.key});

  @override
  State<DvWhatsNewPage> createState() => _DvWhatsNewPageState();
}

class _DvWhatsNewPageState extends State<DvWhatsNewPage> {
  final PageController _controller = PageController();
  int _index = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _next() {
    if (_index >= _slides.length - 1) {
      Navigator.of(context).pop();
      return;
    }
    unawaited(
      _controller.nextPage(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final last = _index == _slides.length - 1;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(last ? '' : 'Пропустить'),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _slides.length,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (context, i) {
                  final s = _slides[i];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 28),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0.8, end: 1),
                          duration: const Duration(milliseconds: 500),
                          curve: Curves.easeOutBack,
                          builder: (context, v, child) => Transform.scale(
                            scale: v,
                            child: Opacity(
                              opacity: v > 1 ? 1.0 : (v < 0 ? 0.0 : v),
                              child: child,
                            ),
                          ),
                          child: Container(
                            width: 220,
                            height: 220,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: RadialGradient(
                                colors: [
                                  s.color.withAlpha(60),
                                  s.color.withAlpha(12),
                                ],
                              ),
                            ),
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                Positioned(
                                  top: 22,
                                  child: Icon(s.icon, size: 40, color: s.color),
                                ),
                                Padding(
                                  padding: const EdgeInsets.only(top: 40),
                                  child: s.art(context),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 28),
                        Text(
                          s.title,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          s.text,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyLarge,
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < _slides.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: i == _index ? 22 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
                      color: i == _index
                          ? theme.colorScheme.primary
                          : theme.colorScheme.outlineVariant,
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 18, 28, 24),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _next,
                  child: Text(last ? 'Готово' : 'Далее'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
