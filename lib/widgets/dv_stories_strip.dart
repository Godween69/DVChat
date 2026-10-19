// DVChat: сторис над списком чатов, как в Telegram. Свёрнуто: маленькие кружки
// стопкой в углу перед заголовком. Тянешь список вниз: кружки едут из стопки
// вниз-вправо в ряд под заголовком и растут, ровно за пальцем. Отпустил далеко:
// ряд остаётся, близко: кружки едут обратно в угол.

import 'dart:async';

import 'package:dvchat/pages/stories/dv_story_audience.dart';
import 'package:dvchat/pages/stories/dv_story_viewer.dart';
import 'package:dvchat/utils/dv_stories.dart';
import 'package:dvchat/utils/platform_infos.dart';
import 'package:dvchat/widgets/avatar.dart';
import 'package:dvchat/widgets/future_loading_dialog.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

void _openViewer(
  BuildContext context,
  Client client,
  List<DvStoryGroup> groups,
  int index,
) {
  Navigator.of(context, rootNavigator: true).push(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (context) =>
          DvStoryViewer(client: client, groups: groups, startGroup: index),
    ),
  );
}

/// Выбор файла, выбор аудитории и публикация
Future<void> _addStory(BuildContext context, Client client) async {
  void snack(String text) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  final action = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (PlatformInfos.isMobile)
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Снять фото'),
              onTap: () => Navigator.of(context).pop('camera_photo'),
            ),
          if (PlatformInfos.isMobile)
            ListTile(
              leading: const Icon(Icons.videocam_outlined),
              title: const Text('Снять видео (до 10 секунд)'),
              onTap: () => Navigator.of(context).pop('camera_video'),
            ),
          ListTile(
            leading: const Icon(Icons.photo_outlined),
            title: const Text('Фото из галереи'),
            onTap: () => Navigator.of(context).pop('gallery_photo'),
          ),
          ListTile(
            leading: const Icon(Icons.video_library_outlined),
            title: const Text('Видео из галереи (до 10 секунд)'),
            onTap: () => Navigator.of(context).pop('gallery_video'),
          ),
        ],
      ),
    ),
  );
  if (action == null || !context.mounted) return;
  final video = action.endsWith('video');
  final source = action.startsWith('camera')
      ? ImageSource.camera
      : ImageSource.gallery;
  final picker = ImagePicker();
  XFile? picked;
  try {
    picked = video
        ? await picker.pickVideo(
            source: source,
            maxDuration: const Duration(seconds: 10),
          )
        : await picker.pickImage(
            source: source,
            maxWidth: 1080,
            maxHeight: 1920,
            imageQuality: 78,
          );
  } catch (e) {
    snack('Не удалось выбрать файл: $e');
    return;
  }
  if (picked == null || !context.mounted) return;
  final file = picked;
  final audience = await pickStoryAudience(context, client);
  if (audience == null || !context.mounted) return;
  final result = await showFutureLoadingDialog(
    context: context,
    title: 'Публикую сторис…',
    future: () =>
        DvStories.publish(client, file, video: video, audience: audience),
  );
  if (result.error == null) {
    snack('Сторис опубликован на 24 часа');
  }
}

/// Геометрия: где стоят кружки в стопке и в ряду. Всё считается от места
/// самой стопки в заголовке (как аватарка в профиле: сдвиг от своего места),
/// поэтому начать движение не из угла кружок не может.
class _Geo {
  // Стопка в заголовке
  static const double stackD = 30;
  static const double stackStep = 20;
  static const int stackMax = 4;
  static const double stackAvatar = 22;
  static const double stackBorder = 2;

  // Ряд под заголовком
  static const double rowD = 54;
  static const double rowCell = 64;
  static const double rowPadX = 10;
  static const double rowPadY = 4;
  static const double rowHeight = 84;
  static const double rowAvatar = 44;
  static const double rowBorder = 2.5;

  // Где ряд относительно стопки: заголовок 64 px, стопка 30 px по его центру
  // (сверху 17 px), слева отступ заголовка 16 px
  static const double toolbar = 64;
  static const double stackLeft = 16;
  static double get stackTop => (toolbar - stackD) / 2;

  /// Сдвиг кружка i из стопки в ряд (в координатах стопки)
  static Offset shift(int i) {
    final ci = i < stackMax ? i : stackMax - 1;
    final rowX = rowPadX + rowCell * i + (rowCell - rowD) / 2;
    final dx = rowX - stackLeft - stackStep * ci;
    final dy = toolbar - stackTop + rowPadY;
    return Offset(dx, dy);
  }

  /// Ход кружка i по общему ходу v (0..1): следующие чуть отстают
  static double progress(int i, double v) {
    final k = 0.045 * (i > 6 ? 6 : i);
    return ((v - k) / (1 - k)).clamp(0.0, 1.0);
  }
}

/// Раскрытый ряд под заголовком: даёт место (растёт за пальцем) и показывает
/// подписи; сами кружки во время движения рисует стопка в заголовке
class DvStoriesStrip extends StatefulWidget {
  final Client client;
  const DvStoriesStrip({required this.client, super.key});

  @override
  State<DvStoriesStrip> createState() => _DvStoriesStripState();
}

class _DvStoriesStripState extends State<DvStoriesStrip>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  Timer? _timer;
  late final AnimationController _c;

  void _onPull() {
    final p = DvStories.pull.value;
    if (p != null) {
      _c.stop();
      _c.value = p;
    } else {
      _settle();
    }
  }

  void _settle() {
    unawaited(
      _c.animateTo(
        DvStories.expanded.value ? 1 : 0,
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeOutCubic,
      ),
    );
  }

  void _publish() => DvStories.reveal.value = _c.value;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _c = AnimationController(
      vsync: this,
      value: DvStories.expanded.value ? 1 : 0,
    );
    _c.addListener(_publish);
    DvStories.pull.addListener(_onPull);
    DvStories.expanded.addListener(_settle);
    WidgetsBinding.instance.addPostFrameCallback((_) => _publish());
    unawaited(DvStories.refresh(widget.client));
    _timer = Timer.periodic(
      const Duration(seconds: 60),
      (_) => DvStories.refresh(widget.client),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    DvStories.pull.removeListener(_onPull);
    DvStories.expanded.removeListener(_settle);
    _c.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(DvStories.refresh(widget.client));
    }
  }

  Widget _row(DvStoriesFeed? feed, double v) {
    final me = widget.client.userID ?? '';
    final mine = feed?.mine ?? const <DvStory>[];
    final groups = feed?.groups ?? const <DvStoryGroup>[];
    final mineGroup = DvStoryGroup(me, mine);
    // Пока кружки едут, их рисует стопка; здесь видны только подписи
    final open = v >= 0.999;
    final circle = open ? 1.0 : 0.0;
    final label = v * v * v;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onVerticalDragEnd: (d) {
        if ((d.primaryVelocity ?? 0) < -150) DvStories.expanded.value = false;
      },
      child: SizedBox(
        height: _Geo.rowHeight,
        child: ListView(
          scrollDirection: Axis.horizontal,
          physics: open ? null : const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(
            horizontal: _Geo.rowPadX,
            vertical: _Geo.rowPadY,
          ),
          children: [
            _Bubble(
              client: widget.client,
              userId: me,
              label: 'Моя',
              circleOpacity: circle,
              labelOpacity: label,
              ring: mine.isEmpty ? _Ring.none : _Ring.mine,
              showPlus: true,
              onTap: mine.isEmpty
                  ? () => _addStory(context, widget.client)
                  : () => _openViewer(context, widget.client, [mineGroup], 0),
              onPlus: () => _addStory(context, widget.client),
            ),
            for (var i = 0; i < groups.length; i++)
              _Bubble(
                client: widget.client,
                userId: groups[i].userId,
                circleOpacity: circle,
                labelOpacity: label,
                ring: groups[i].hasUnseen ? _Ring.unseen : _Ring.seen,
                onTap: () => _openViewer(context, widget.client, groups, i),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final v = _c.value.clamp(0.0, 1.0);
        if (v < 0.002) {
          return const SizedBox(width: double.infinity, height: 0);
        }
        // Место под ряд растёт вместе с пальцем
        return ClipRect(
          child: Align(
            alignment: Alignment.topCenter,
            heightFactor: v,
            child: ValueListenableBuilder<DvStoriesFeed?>(
              valueListenable: DvStories.feed,
              builder: (context, feed, _) => _row(feed, v),
            ),
          ),
        );
      },
    );
  }
}

/// Стопка кружков в углу перед заголовком. Пока ряд раскрывается, она же
/// рисует летящие кружки: каждый сдвигается от своего места в стопке
/// вниз-вправо к своему месту в ряду и растёт с 30 до 54 px.
class DvStoriesCompact extends StatelessWidget {
  final Client client;
  const DvStoriesCompact({required this.client, super.key});

  Widget _circle(ThemeData theme, String userId, Color ring, double t) {
    final d = _Geo.stackD + (_Geo.rowD - _Geo.stackD) * t;
    final avatar = _Geo.stackAvatar + (_Geo.rowAvatar - _Geo.stackAvatar) * t;
    final border = _Geo.stackBorder + (_Geo.rowBorder - _Geo.stackBorder) * t;
    return Container(
      width: d,
      height: d,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: t < 0.5 ? theme.colorScheme.surface : null,
        border: Border.all(color: ring, width: border),
      ),
      child: FutureBuilder<Profile>(
        initialData: DvStories.profileData[userId],
        future: DvStories.profile(client, userId),
        builder: (context, snapshot) => Avatar(
          mxContent: snapshot.data?.avatarUrl,
          name: DvStories.nameOf(client, userId, snapshot.data),
          client: client,
          size: avatar,
          borderRadius: BorderRadius.circular(avatar),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ValueListenableBuilder<DvStoriesFeed?>(
      valueListenable: DvStories.feed,
      builder: (context, feed, _) {
        final me = client.userID ?? '';
        final mine = feed?.mine ?? const <DvStory>[];
        final allGroups = feed?.groups ?? const <DvStoryGroup>[];
        final ids = <String>[me, ...allGroups.map((g) => g.userId)];
        final shown = ids.length < _Geo.stackMax ? ids.length : _Geo.stackMax;
        Color ringOf(int i) {
          if (i == 0) {
            return mine.isEmpty
                ? Colors.transparent
                : theme.colorScheme.tertiary;
          }
          return allGroups[i - 1].hasUnseen
              ? theme.colorScheme.primary
              : theme.colorScheme.outlineVariant;
        }

        // Ширина стопки постоянная, чтобы заголовок не дёргался
        final width = _Geo.stackD + _Geo.stackStep * (shown - 1);
        return ValueListenableBuilder<double>(
          valueListenable: DvStories.reveal,
          builder: (context, reveal, _) {
            final Widget body;
            if (reveal >= 0.999) {
              // Ряд раскрыт: кружки уже стоят в ряду
              body = const SizedBox.shrink();
            } else if (reveal <= 0.003) {
              body = Stack(
                clipBehavior: Clip.none,
                children: [
                  // Первый (мой) сверху: рисуем с конца
                  for (var i = shown - 1; i >= 0; i--)
                    Positioned(
                      left: _Geo.stackStep * i,
                      top: 0,
                      child: _circle(theme, ids[i], ringOf(i), 0),
                    ),
                  if (mine.isEmpty)
                    Positioned(
                      left: _Geo.stackD - 12,
                      bottom: -2,
                      child: Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.add,
                          size: 11,
                          color: theme.colorScheme.onPrimary,
                        ),
                      ),
                    ),
                ],
              );
            } else {
              // Полёт: каждый кружок сдвигается от своего места в стопке
              body = Stack(
                clipBehavior: Clip.none,
                children: [
                  for (var i = ids.length - 1; i >= 0; i--)
                    () {
                      final t = _Geo.progress(i, reveal);
                      final ci = i < _Geo.stackMax ? i : _Geo.stackMax - 1;
                      final s = _Geo.shift(i) * t;
                      return Positioned(
                        left: _Geo.stackStep * ci + s.dx,
                        top: s.dy,
                        child: Opacity(
                          opacity: i < _Geo.stackMax ? 1.0 : t,
                          child: _circle(theme, ids[i], ringOf(i), t),
                        ),
                      );
                    }(),
                ],
              );
            }
            return IgnorePointer(
              ignoring: reveal > 0.003,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => DvStories.expanded.value = true,
                child: SizedBox(width: width, height: _Geo.stackD, child: body),
              ),
            );
          },
        );
      },
    );
  }
}

enum _Ring { none, mine, unseen, seen }

class _Bubble extends StatelessWidget {
  final Client client;
  final String userId;
  final String? label;
  final _Ring ring;
  final bool showPlus;
  final double circleOpacity;
  final double labelOpacity;
  final VoidCallback onTap;
  final VoidCallback? onPlus;

  const _Bubble({
    required this.client,
    required this.userId,
    required this.ring,
    required this.onTap,
    this.label,
    this.showPlus = false,
    this.circleOpacity = 1,
    this.labelOpacity = 1,
    this.onPlus,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ringColor = switch (ring) {
      _Ring.unseen => theme.colorScheme.primary,
      _Ring.mine => theme.colorScheme.tertiary,
      _Ring.seen => theme.colorScheme.outlineVariant,
      _Ring.none => Colors.transparent,
    };
    return SizedBox(
      width: _Geo.rowCell,
      child: Column(
        children: [
          Opacity(
            opacity: circleOpacity,
            child: GestureDetector(
              onTap: onTap,
              child: SizedBox(
                width: _Geo.rowD,
                height: _Geo.rowD,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: _Geo.rowD,
                      height: _Geo.rowD,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: ringColor,
                          width: _Geo.rowBorder,
                        ),
                      ),
                      child: FutureBuilder<Profile>(
                        initialData: DvStories.profileData[userId],
                        future: DvStories.profile(client, userId),
                        builder: (context, snapshot) => Avatar(
                          mxContent: snapshot.data?.avatarUrl,
                          name: DvStories.nameOf(client, userId, snapshot.data),
                          client: client,
                          size: _Geo.rowAvatar,
                          borderRadius: BorderRadius.circular(_Geo.rowAvatar),
                        ),
                      ),
                    ),
                    if (showPlus)
                      Positioned(
                        right: -2,
                        bottom: -2,
                        child: GestureDetector(
                          onTap: onPlus,
                          child: Container(
                            width: 20,
                            height: 20,
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: theme.colorScheme.surface,
                                width: 2,
                              ),
                            ),
                            child: Icon(
                              Icons.add,
                              size: 13,
                              color: theme.colorScheme.onPrimary,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 2),
          FutureBuilder<Profile>(
            initialData: DvStories.profileData[userId],
            future: DvStories.profile(client, userId),
            builder: (context, snapshot) => Opacity(
              opacity: labelOpacity.clamp(0.0, 1.0),
              child: Text(
                label ?? DvStories.nameOf(client, userId, snapshot.data),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: theme.textTheme.labelSmall?.copyWith(fontSize: 11),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
