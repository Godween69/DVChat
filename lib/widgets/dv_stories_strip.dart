// DVChat: сторис над списком чатов, как в Telegram. Свёрнуто: маленькие кружки
// стопкой рядом с заголовком. Потянул список вниз: кружки раскрываются в ряд.
// Смахнул вверх или прокрутил список: снова сворачиваются.

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
    with WidgetsBindingObserver {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(DvStories.refresh(widget.client));
    _timer = Timer.periodic(
      const Duration(seconds: 60),
      (_) => DvStories.refresh(widget.client),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(DvStories.refresh(widget.client));
    }
  }

  Widget _row(DvStoriesFeed? feed) {
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
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          children: [
            _Bubble(
              client: widget.client,
              userId: me,
              label: 'Моя',
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
    return ValueListenableBuilder<bool>(
      valueListenable: DvStories.expanded,
      builder: (context, open, _) => AnimatedSize(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        child: open
            ? ValueListenableBuilder<DvStoriesFeed?>(
                valueListenable: DvStories.feed,
                builder: (context, feed, _) => _row(feed),
              )
            : const SizedBox(width: double.infinity, height: 0),
      ),
    );
  }
}

/// Свёрнутый вид: маленькие кружки стопкой рядом с заголовком
class DvStoriesCompact extends StatelessWidget {
  final Client client;
  const DvStoriesCompact({required this.client, super.key});

  static const double _d = 30;
  static const double _step = 20;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ValueListenableBuilder<bool>(
      valueListenable: DvStories.expanded,
      builder: (context, open, _) {
        if (open) return const SizedBox.shrink();
        return ValueListenableBuilder<DvStoriesFeed?>(
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
                child: Stack(
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
                            border: Border.all(color: ringOf(i), width: 2),
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
                ),
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
  final VoidCallback onTap;
  final VoidCallback? onPlus;

  const _Bubble({
    required this.client,
    required this.userId,
    required this.ring,
    required this.onTap,
    this.label,
    this.showPlus = false,
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
            builder: (context, snapshot) => Text(
              label ?? DvStories.nameOf(client, userId, snapshot.data),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: theme.textTheme.labelSmall?.copyWith(fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }
}
