// DVChat: полоса сторис над списком чатов: «Моя» и друзья с кольцом (новое — яркое).

import 'dart:async';

import 'package:dvchat/pages/stories/dv_story_viewer.dart';
import 'package:dvchat/utils/dv_stories.dart';
import 'package:dvchat/utils/platform_infos.dart';
import 'package:dvchat/widgets/avatar.dart';
import 'package:dvchat/widgets/future_loading_dialog.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

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

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _add() async {
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
    if (action == null || !mounted) return;
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
      _snack('Не удалось выбрать файл: $e');
      return;
    }
    if (picked == null || !mounted) return;
    final file = picked;
    final result = await showFutureLoadingDialog(
      context: context,
      title: 'Публикую сторис…',
      future: () => DvStories.publish(widget.client, file, video: video),
    );
    if (result.error == null) {
      _snack('Сторис опубликован на 24 часа');
    }
  }

  void _open(List<DvStoryGroup> groups, int index) {
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (context) => DvStoryViewer(
          client: widget.client,
          groups: groups,
          startGroup: index,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<DvStoriesFeed?>(
      valueListenable: DvStories.feed,
      builder: (context, feed, _) {
        final me = widget.client.userID ?? '';
        final mine = feed?.mine ?? const <DvStory>[];
        final groups = feed?.groups ?? const <DvStoryGroup>[];
        final mineGroup = DvStoryGroup(me, mine);
        return SizedBox(
          height: 104,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            children: [
              _Bubble(
                client: widget.client,
                userId: me,
                label: 'Моя',
                ring: mine.isEmpty ? _Ring.none : _Ring.mine,
                showPlus: true,
                onTap: mine.isEmpty ? _add : () => _open([mineGroup], 0),
                onPlus: _add,
              ),
              for (var i = 0; i < groups.length; i++)
                _Bubble(
                  client: widget.client,
                  userId: groups[i].userId,
                  ring: groups[i].hasUnseen ? _Ring.unseen : _Ring.seen,
                  onTap: () => _open(groups, i),
                ),
            ],
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
      width: 74,
      child: Column(
        children: [
          GestureDetector(
            onTap: onTap,
            child: SizedBox(
              width: 62,
              height: 62,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 62,
                    height: 62,
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: ringColor,
                        width: ring == _Ring.none ? 0 : 3,
                      ),
                    ),
                    child: FutureBuilder<Profile>(
                      initialData: DvStories.profileData[userId],
                      future: DvStories.profile(client, userId),
                      builder: (context, snapshot) => Avatar(
                        mxContent: snapshot.data?.avatarUrl,
                        name: DvStories.nameOf(client, userId, snapshot.data),
                        client: client,
                        size: 50,
                        borderRadius: BorderRadius.circular(25),
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
                          width: 22,
                          height: 22,
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
                            size: 14,
                            color: theme.colorScheme.onPrimary,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 4),
          FutureBuilder<Profile>(
            initialData: DvStories.profileData[userId],
            future: DvStories.profile(client, userId),
            builder: (context, snapshot) => Text(
              label ?? DvStories.nameOf(client, userId, snapshot.data),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: theme.textTheme.labelSmall,
            ),
          ),
        ],
      ),
    );
  }
}
