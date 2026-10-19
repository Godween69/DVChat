// DVChat: сторис над списком чатов, как в Telegram. Свёрнуто: маленькие кружки
// стопкой в углу перед заголовком. Тянешь список вниз: ряд вытягивается за пальцем,
// отпустил далеко: остаётся раскрытым, близко: прячется. Смахнул вверх или прокрутил
// список: сворачивается.

import 'dart:async';

import 'package:dvchat/pages/stories/dv_story_audience.dart';
import 'package:dvchat/pages/stories/dv_story_viewer.dart';
import 'package:dvchat/utils/dv_stories.dart';
import 'package:dvchat/utils/platform_infos.dart';
import 'package:dvchat/widgets/avatar.dart';
import 'package:dvchat/widgets/future_loading_dialog.dart';
import 'package:flutter/rendering.dart';
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
            maxWidth: 1280,
            maxHeight: 1920,
            imageQuality: 85,
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

/// Раскрытый ряд под заголовком
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

  /// Где сейчас стопка кружков в заголовке, в координатах этой полосы
  Offset? _compactPos() {
    try {
      final c = DvStoriesCompact.lastContext;
      if (c == null || !c.mounted) return null;
      final cb = c.findRenderObject() as RenderBox?;
      final sb = context.findRenderObject() as RenderBox?;
      if (cb == null || sb == null || !cb.attached || !sb.attached) {
        return null;
      }
      if (!cb.hasSize) return null;
      return sb.globalToLocal(cb.localToGlobal(Offset.zero));
    } catch (_) {
      return null;
    }
  }

  /// Один кружок ряда: едет из своего места в стопке в своё место в ряду,
  /// одновременно увеличиваясь, подпись проявляется ближе к концу
  Widget _fly(int i, int count, double v, Offset? from, Widget bubble) {
    const stagger = 0.045;
    final k = stagger * (i > 6 ? 6 : i);
    final p = ((v - k) / (1 - k)).clamp(0.0, 1.0);
    // Линейно: кружок едет ровно за пальцем, без «быстрого старта»
    final e = p;
    final ci = i < DvStoriesCompact.maxCircles
        ? i
        : DvStoriesCompact.maxCircles - 1;
    final cx = (from?.dx ?? 0) + DvStoriesCompact.step * ci;
    final cy = from?.dy ?? -56.0;
    final rowX = 10.0 + 64.0 * i;
    final x = cx + (rowX + 5 - cx) * e;
    final y = cy + (4 - cy) * e;
    final scale =
        DvStoriesCompact.dia / 54 + (1 - DvStoriesCompact.dia / 54) * e;
    final dim = i < DvStoriesCompact.maxCircles ? 1.0 : p;
    return Transform.translate(
      offset: Offset(x - rowX - 5 * scale, y - 4),
      child: Transform.scale(
        scale: scale,
        alignment: Alignment.topLeft,
        child: Opacity(opacity: (v * 300).clamp(0.0, 1.0) * dim, child: bubble),
      ),
    );
  }

  Widget _row(DvStoriesFeed? feed, double v) {
    // Стопка в заголовке: слева 16 px (отступ заголовка), по высоте на 47 px выше ряда
    // (заголовок 64 px, стопка 30 px по центру, плюс 4 px отступа ряда)
    const from = Offset(16, -47);
    final me = widget.client.userID ?? '';
    final mine = feed?.mine ?? const <DvStory>[];
    final groups = feed?.groups ?? const <DvStoryGroup>[];
    final mineGroup = DvStoryGroup(me, mine);
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onVerticalDragEnd: (d) {
        if ((d.primaryVelocity ?? 0) < -150) DvStories.expanded.value = false;
      },
      child: SizedBox(
        height: 84,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          clipBehavior: Clip.none,
          physics: v < 0.999 ? const NeverScrollableScrollPhysics() : null,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _fly(
                0,
                groups.length + 1,
                v,
                from,
                _Bubble(
                  client: widget.client,
                  userId: me,
                  label: 'Моя',
                  labelOpacity: v * v,
                  ring: mine.isEmpty ? _Ring.none : _Ring.mine,
                  showPlus: true,
                  onTap: mine.isEmpty
                      ? () => _addStory(context, widget.client)
                      : () =>
                            _openViewer(context, widget.client, [mineGroup], 0),
                  onPlus: () => _addStory(context, widget.client),
                ),
              ),
              for (var i = 0; i < groups.length; i++)
                _fly(
                  i + 1,
                  groups.length + 1,
                  v,
                  from,
                  _Bubble(
                    client: widget.client,
                    userId: groups[i].userId,
                    labelOpacity: v * v,
                    ring: groups[i].hasUnseen ? _Ring.unseen : _Ring.seen,
                    onTap: () => _openViewer(context, widget.client, groups, i),
                  ),
                ),
            ],
          ),
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
        // Высота растёт вместе с пальцем, а кружки едут из угла в свои места
        // (без обрезки и без затухания)
        return Align(
          alignment: Alignment.topCenter,
          heightFactor: v,
          child: ValueListenableBuilder<DvStoriesFeed?>(
            valueListenable: DvStories.feed,
            builder: (context, feed, _) => _row(feed, v),
          ),
        );
      },
    );
  }
}

/// Свёрнутый вид: маленькие кружки стопкой рядом с заголовком
class DvStoriesCompact extends StatelessWidget {
  final Client client;
  const DvStoriesCompact({required this.client, super.key});

  static const double dia = 30;
  static const double step = 20;
  static const int maxCircles = 4;
  static const double _d = dia;
  static const double _step = step;

  /// Контекст стопки в заголовке: по нему раскрывающийся ряд находит, откуда ехать
  static BuildContext? lastContext;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ValueListenableBuilder<double>(
      valueListenable: DvStories.reveal,
      builder: (context, reveal, _) {
        return Opacity(
          // Как только ряд пошёл, стопка в углу гаснет сразу: её заменяют те же кружки, но уже летящие
          opacity: reveal > 0.003 ? 0.0 : 1.0,
          child: IgnorePointer(
            ignoring: reveal > 0.3,
            child: ValueListenableBuilder<DvStoriesFeed?>(
              valueListenable: DvStories.feed,
              builder: (context, feed, _) {
                final me = client.userID ?? '';
                final mine = feed?.mine ?? const <DvStory>[];
                final groups = (feed?.groups ?? const <DvStoryGroup>[])
                    .take(3)
                    .toList();
                final ids = <String>[me, ...groups.map((g) => g.userId)];
                Color ringOf(int i) {
                  if (i == 0) {
                    return mine.isEmpty
                        ? Colors.transparent
                        : theme.colorScheme.tertiary;
                  }
                  return groups[i - 1].hasUnseen
                      ? theme.colorScheme.primary
                      : theme.colorScheme.outlineVariant;
                }

                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => DvStories.expanded.value = true,
                  child: SizedBox(
                    width: _d + _step * (ids.length - 1),
                    height: _d,
                    child: Builder(
                      builder: (ctx) {
                        lastContext = ctx;
                        return Stack(
                          clipBehavior: Clip.none,
                          children: [
                            // Первый (мой) сверху: рисуем с конца
                            for (var i = ids.length - 1; i >= 0; i--)
                              Positioned(
                                left: _step * i,
                                child: Container(
                                  width: _d,
                                  height: _d,
                                  padding: const EdgeInsets.all(2),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: theme.colorScheme.surface,
                                    border: Border.all(
                                      color: ringOf(i),
                                      width: 2,
                                    ),
                                  ),
                                  child: FutureBuilder<Profile>(
                                    initialData: DvStories.profileData[ids[i]],
                                    future: DvStories.profile(client, ids[i]),
                                    builder: (context, snapshot) => Avatar(
                                      mxContent: snapshot.data?.avatarUrl,
                                      name: DvStories.nameOf(
                                        client,
                                        ids[i],
                                        snapshot.data,
                                      ),
                                      client: client,
                                      size: _d - 8,
                                      borderRadius: BorderRadius.circular(_d),
                                    ),
                                  ),
                                ),
                              ),
                            if (mine.isEmpty)
                              Positioned(
                                left: _d - 12,
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
                      },
                    ),
                  ),
                );
              },
            ),
          ),
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
      width: 64,
      child: Column(
        children: [
          GestureDetector(
            onTap: onTap,
            child: SizedBox(
              width: 54,
              height: 54,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 54,
                    height: 54,
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: ringColor,
                        width: ring == _Ring.none ? 0 : 2.5,
                      ),
                    ),
                    child: FutureBuilder<Profile>(
                      initialData: DvStories.profileData[userId],
                      future: DvStories.profile(client, userId),
                      builder: (context, snapshot) => Avatar(
                        mxContent: snapshot.data?.avatarUrl,
                        name: DvStories.nameOf(client, userId, snapshot.data),
                        client: client,
                        size: 44,
                        borderRadius: BorderRadius.circular(22),
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
