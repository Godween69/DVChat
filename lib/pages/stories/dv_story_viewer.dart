// DVChat: полноэкранный просмотр сторис: полоски времени, касание вправо/влево,
// удержание ставит на паузу, свайп вниз закрывает. Свои: кто смотрел и удаление.
// Чужие: реакции.

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dvchat/utils/dv_stories.dart';
import 'package:dvchat/widgets/avatar.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

class DvStoryViewer extends StatefulWidget {
  final Client client;
  final List<DvStoryGroup> groups;
  final int startGroup;

  const DvStoryViewer({
    required this.client,
    required this.groups,
    this.startGroup = 0,
    super.key,
  });

  @override
  State<DvStoryViewer> createState() => _DvStoryViewerState();
}

class _DvStoryViewerState extends State<DvStoryViewer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _progress;
  late int _group;
  late int _item;
  int _token = 0;
  Uint8List? _photo;
  VideoPlayerController? _video;
  bool _loading = true;
  bool _fetching = false;
  Timer? _spinner;
  bool _failed = false;
  bool _holding = false;
  bool _sheetOpen = false;
  bool _panel = false;
  String? _burst;

  DvStoryGroup get _g => widget.groups[_group];
  DvStory get _s => _g.items[_item];
  bool get _isMine => _g.userId == widget.client.userID;
  bool get _paused => _holding || _sheetOpen || _panel;

  @override
  void initState() {
    super.initState();
    _group = widget.startGroup.clamp(0, widget.groups.length - 1);
    _item = _g.startIndex;
    _progress = AnimationController(vsync: this)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) _next();
      });
    WidgetsBinding.instance.addPostFrameCallback((_) => _show());
  }

  @override
  void dispose() {
    _spinner?.cancel();
    _progress.dispose();
    _video?.dispose();
    // Кольца в списке обновляем один раз после выхода, а не после каждой сторис
    WidgetsBinding.instance.addPostFrameCallback((_) => DvStories.touch());
    super.dispose();
  }

  /// Картинка под размер экрана: не держим в памяти лишние мегапиксели
  ImageProvider _provider(Uint8List bytes) {
    final w =
        (MediaQuery.sizeOf(context).width *
                MediaQuery.devicePixelRatioOf(context))
            .round();
    return ResizeImage.resizeIfNeeded(w, null, MemoryImage(bytes));
  }

  /// Пока смотрят эту сторис, тихо скачиваем и готовим следующую
  Future<void> _prefetch() async {
    DvStory? next;
    if (_item + 1 < _g.items.length) {
      next = _g.items[_item + 1];
    } else if (!_isMine && _group + 1 < widget.groups.length) {
      final g = widget.groups[_group + 1];
      next = g.items[g.startIndex];
    }
    if (next == null) return;
    try {
      final bytes = await DvStories.bytes(widget.client, next.mxc);
      if (!next.isVideo && mounted) {
        await precacheImage(_provider(bytes), context);
      }
    } catch (_) {}
  }

  Future<void> _show() async {
    final token = ++_token;
    _progress.stop();
    _progress.value = 0;
    _video?.pause();
    _fetching = true;
    _failed = false;
    // Предыдущая картинка остаётся на экране; крутилку показываем,
    // только если загрузка затянулась
    _spinner?.cancel();
    _spinner = Timer(const Duration(milliseconds: 450), () {
      if (mounted && token == _token && _fetching) {
        setState(() => _loading = true);
      }
    });
    setState(() {});
    final story = _s;
    try {
      final bytes = await DvStories.bytes(widget.client, story.mxc);
      if (!mounted || token != _token) return;
      Duration length = const Duration(seconds: 5);
      VideoPlayerController? controller;
      if (story.isVideo) {
        if (kIsWeb) {
          controller = VideoPlayerController.networkUrl(
            Uri.dataFromBytes(bytes, mimeType: 'video/mp4'),
          );
        } else {
          final dir = await getTemporaryDirectory();
          final file = File('${dir.path}/story_${story.id}.mp4');
          if (!await file.exists()) await file.writeAsBytes(bytes);
          controller = VideoPlayerController.file(file);
        }
        await controller.initialize();
        if (!mounted || token != _token) {
          unawaited(controller.dispose());
          return;
        }
        final d = controller.value.duration;
        if (d > Duration.zero) {
          length = d > const Duration(seconds: 10)
              ? const Duration(seconds: 10)
              : d;
        }
        await controller.setLooping(false);
      } else {
        // Картинку декодируем заранее, чтобы смена была без паузы
        await precacheImage(_provider(bytes), context);
        if (!mounted || token != _token) return;
      }
      _spinner?.cancel();
      final old = _video;
      setState(() {
        _video = controller;
        _photo = story.isVideo ? null : bytes;
        _loading = false;
        _fetching = false;
      });
      unawaited(old?.dispose());
      if (controller != null && !_paused) unawaited(controller.play());
      _progress.duration = length;
      if (!_paused) unawaited(_progress.forward(from: 0));
      if (!_isMine && !story.seen) {
        unawaited(DvStories.markSeen(widget.client, story));
      }
      unawaited(_prefetch());
    } catch (e, s) {
      Logs().w('DVChat: не удалось показать сторис', e, s);
      if (!mounted || token != _token) return;
      _spinner?.cancel();
      setState(() {
        _loading = false;
        _fetching = false;
        _failed = true;
      });
    }
  }

  void _next() {
    if (_item + 1 < _g.items.length) {
      _item++;
      unawaited(_show());
    } else if (_group + 1 < widget.groups.length && !_isMine) {
      _group++;
      _item = _g.startIndex;
      unawaited(_show());
    } else {
      Navigator.of(context).maybePop();
    }
  }

  void _prev() {
    // Если уже посмотрели больше мгновения или это самая первая сторис, начинаем эту заново
    if (_progress.value > 0.15 || (_item == 0 && _group == 0)) {
      unawaited(_show());
      return;
    }
    if (_item > 0) {
      _item--;
    } else {
      _group--;
      _item = 0;
    }
    unawaited(_show());
  }

  void _pause() {
    _progress.stop();
    _video?.pause();
  }

  void _resume() {
    if (_paused || _loading || _fetching || _failed) return;
    _video?.play();
    if (_progress.duration != null) unawaited(_progress.forward());
  }

  Future<void> _delete() async {
    _sheetOpen = true;
    _pause();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить сторис?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    _sheetOpen = false;
    if (ok != true || !mounted) {
      _resume();
      return;
    }
    try {
      await DvStories.delete(widget.client, _s);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Не удалось удалить: $e')));
      }
      _resume();
      return;
    }
    if (mounted) Navigator.of(context).maybePop();
  }

  Future<void> _showViewers() async {
    _sheetOpen = true;
    _pause();
    final story = _s;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.55,
        child: FutureBuilder<List<DvStoryWatcher>>(
          future: DvStories.viewers(widget.client, story),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(
                child: Text('Не удалось загрузить: ${snapshot.error}'),
              );
            }
            final list = snapshot.data;
            if (list == null) {
              return const Center(child: CircularProgressIndicator());
            }
            if (list.isEmpty) {
              return const Center(child: Text('Пока никто не посмотрел'));
            }
            return ListView.builder(
              itemCount: list.length,
              itemBuilder: (context, i) {
                final v = list[i];
                return FutureBuilder<Profile>(
                  initialData: DvStories.profileData[v.userId],
                  future: DvStories.profile(widget.client, v.userId),
                  builder: (context, snap) {
                    final name = DvStories.nameOf(
                      widget.client,
                      v.userId,
                      snap.data,
                    );
                    return ListTile(
                      leading: Avatar(
                        mxContent: snap.data?.avatarUrl,
                        name: name,
                        client: widget.client,
                      ),
                      title: Text(name),
                      subtitle: Text(DvStories.ago(v.ts)),
                      trailing: v.reaction == null
                          ? null
                          : Text(
                              v.reaction!,
                              style: const TextStyle(fontSize: 24),
                            ),
                    );
                  },
                );
              },
            );
          },
        ),
      ),
    );
    _sheetOpen = false;
    _resume();
  }

  Future<void> _react(String emoji) async {
    final story = _s;
    final next = story.myReaction == emoji ? null : emoji;
    try {
      await DvStories.react(widget.client, story, next);
      if (mounted) setState(() {});
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось отправить реакцию: $e')),
      );
    }
  }

  Widget _content() {
    if (_failed) {
      return const Center(
        child: Text(
          'Не удалось загрузить сторис',
          style: TextStyle(color: Colors.white70),
        ),
      );
    }
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final video = _video;
    if (video != null) {
      return Center(
        child: AspectRatio(
          aspectRatio: video.value.aspectRatio,
          child: VideoPlayer(video),
        ),
      );
    }
    final photo = _photo;
    if (photo == null) return const SizedBox.shrink();
    return Image(
      image: _provider(photo),
      fit: BoxFit.contain,
      width: double.infinity,
      height: double.infinity,
      filterQuality: FilterQuality.medium,
      gaplessPlayback: true,
    );
  }

  Widget _bars() {
    return Row(
      children: [
        for (var i = 0; i < _g.items.length; i++)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: i == _item
                    ? AnimatedBuilder(
                        animation: _progress,
                        builder: (context, _) => LinearProgressIndicator(
                          value: _loading ? 0 : _progress.value,
                          minHeight: 3,
                          backgroundColor: Colors.white24,
                          color: Colors.white,
                        ),
                      )
                    : LinearProgressIndicator(
                        value: i < _item ? 1 : 0,
                        minHeight: 3,
                        backgroundColor: Colors.white24,
                        color: Colors.white,
                      ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _header() {
    return FutureBuilder<Profile>(
      initialData: DvStories.profileData[_g.userId],
      future: DvStories.profile(widget.client, _g.userId),
      builder: (context, snapshot) {
        final name = _isMine
            ? 'Моя сторис'
            : DvStories.nameOf(widget.client, _g.userId, snapshot.data);
        return Row(
          children: [
            Avatar(
              mxContent: snapshot.data?.avatarUrl,
              name: name,
              client: widget.client,
              size: 36,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    DvStories.ago(_s.createdTs),
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
            ),
            if (_isMine)
              IconButton(
                tooltip: 'Удалить',
                color: Colors.white,
                icon: const Icon(Icons.delete_outline),
                onPressed: _delete,
              ),
            IconButton(
              tooltip: 'Закрыть',
              color: Colors.white,
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          ],
        );
      },
    );
  }

  Widget _bottom() {
    if (_isMine) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          TextButton.icon(
            style: TextButton.styleFrom(foregroundColor: Colors.white),
            onPressed: _showViewers,
            icon: const Icon(Icons.visibility_outlined),
            label: Text('Просмотры: ${_s.views}   Реакции: ${_s.reactions}'),
          ),
        ],
      );
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        for (final e in DvStories.emojis)
          GestureDetector(
            onTap: () => _react(e),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _s.myReaction == e ? Colors.white24 : Colors.transparent,
              ),
              child: Text(e, style: const TextStyle(fontSize: 26)),
            ),
          ),
      ],
    );
  }

  void _openPanel() {
    setState(() => _panel = true);
    _pause();
  }

  void _closePanel() {
    setState(() => _panel = false);
    _resume();
  }

  /// Выбор реакции из панели долгого нажатия: эмодзи «выпрыгивает» на экран
  void _pick(String emoji) {
    final removing = _s.myReaction == emoji;
    setState(() {
      _panel = false;
      _burst = removing ? null : emoji;
    });
    unawaited(_react(emoji));
    Future<void>.delayed(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => _burst = null);
    });
    _resume();
  }

  Widget _panelView() {
    final theme = Theme.of(context);
    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _closePanel,
        child: Container(
          color: Colors.black54,
          alignment: Alignment.center,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.6, end: 1),
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutBack,
            builder: (context, v, child) => Transform.scale(
              scale: v,
              child: Opacity(opacity: v.clamp(0.0, 1.0), child: child),
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(32),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final e in DvStories.emojis)
                    GestureDetector(
                      onTap: () => _pick(e),
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Text(e, style: const TextStyle(fontSize: 34)),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _burstView(String emoji) {
    return Positioned.fill(
      child: IgnorePointer(
        child: Center(
          child: TweenAnimationBuilder<double>(
            key: ValueKey(emoji),
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 900),
            builder: (context, v, _) => Opacity(
              opacity: (1 - v * v).clamp(0.0, 1.0),
              child: Transform.scale(
                scale: 0.5 + 1.3 * v,
                child: Text(emoji, style: const TextStyle(fontSize: 80)),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Системные панели не прячем (иначе список под просмотром перестраивается и
    // моргает при выходе), только делаем значки светлыми на чёрном
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        // Stack на весь экран: без этого он сжимался до высоты шапки, фото и
        // область нажатий становились крошечными
        body: Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(
              child: LayoutBuilder(
                builder: (context, box) => GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: (d) =>
                      d.localPosition.dx < box.maxWidth / 3 ? _prev() : _next(),
                  onLongPressStart: (_) {
                    if (_isMine) {
                      _holding = true;
                      _pause();
                    } else {
                      _openPanel();
                    }
                  },
                  onLongPressEnd: (_) {
                    if (_holding) {
                      _holding = false;
                      _resume();
                    }
                  },
                  onVerticalDragEnd: (d) {
                    if ((d.primaryVelocity ?? 0) > 300) {
                      Navigator.of(context).maybePop();
                    }
                  },
                  child: _content(),
                ),
              ),
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [_bars(), const SizedBox(height: 8), _header()],
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  child: _bottom(),
                ),
              ),
            ),
            if (_burst != null) _burstView(_burst!),
            if (_panel) _panelView(),
          ],
        ),
      ),
    );
  }
}
