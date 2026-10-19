// DVChat: сторис на 24 часа: запросы к модулю dv_stories на сервере и общий список.

import 'dart:async';
import 'dart:typed_data';

import 'package:dvchat/utils/dv_api.dart';
import 'package:dvchat/utils/dv_nicknames.dart';
import 'package:dvchat/utils/resize_video.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show decodeImageFromList;
import 'package:flutter/widgets.dart'
    show
        OverscrollNotification,
        ScrollEndNotification,
        ScrollNotification,
        ScrollUpdateNotification;
import 'package:image_picker/image_picker.dart';
import 'package:matrix/matrix.dart';

/// Одна сторис
class DvStory {
  final String id;
  final String kind; // photo или video
  final Uri mxc;
  final int? width;
  final int? height;
  final int? durationMs;
  final String caption;
  final int createdTs;
  final int expiresTs;
  bool seen;
  String? myReaction;
  int views;
  int reactions;

  DvStory({
    required this.id,
    required this.kind,
    required this.mxc,
    required this.caption,
    required this.createdTs,
    required this.expiresTs,
    this.width,
    this.height,
    this.durationMs,
    this.seen = false,
    this.myReaction,
    this.views = 0,
    this.reactions = 0,
  });

  bool get isVideo => kind == 'video';

  static int? _int(Object? v) => v is num ? v.toInt() : null;

  factory DvStory.fromJson(Map<String, Object?> j) => DvStory(
    id: j['id']?.toString() ?? '',
    kind: j['kind']?.toString() ?? 'photo',
    mxc: Uri.parse(j['mxc']?.toString() ?? ''),
    width: _int(j['width']),
    height: _int(j['height']),
    durationMs: _int(j['duration_ms']),
    caption: j['caption']?.toString() ?? '',
    createdTs: _int(j['created_ts']) ?? 0,
    expiresTs: _int(j['expires_ts']) ?? 0,
    seen: j['seen'] == true,
    myReaction: j['my_reaction']?.toString(),
    views: _int(j['views']) ?? 0,
    reactions: _int(j['reactions']) ?? 0,
  );
}

/// Сторис одного человека (по порядку публикации)
class DvStoryGroup {
  final String userId;
  final List<DvStory> items;
  const DvStoryGroup(this.userId, this.items);

  bool get hasUnseen => items.any((s) => !s.seen);

  /// С какой сторис начинать просмотр: с первой непросмотренной
  int get startIndex {
    final i = items.indexWhere((s) => !s.seen);
    return i < 0 ? 0 : i;
  }

  int get lastTs => items.isEmpty ? 0 : items.last.createdTs;
}

class DvStoriesFeed {
  final List<DvStory> mine;
  final List<DvStoryGroup> groups;
  const DvStoriesFeed(this.mine, this.groups);
}

/// Кому показать сторис: всем друзьям или выбранным
class DvAudience {
  final bool all;
  final List<String> users;
  const DvAudience.all() : all = true, users = const [];
  const DvAudience.some(this.users) : all = false;
}

/// Запись о том, кто посмотрел мою сторис
class DvStoryWatcher {
  final String userId;
  final int ts;
  final String? reaction;
  const DvStoryWatcher(this.userId, this.ts, this.reaction);
}

class DvStories {
  static const String prefix = 'dvs';
  static const List<String> emojis = ['❤️', '🔥', '😂', '😮', '😢', '👍'];

  /// Последний полученный список; null, пока не загружали
  static final ValueNotifier<DvStoriesFeed?> feed = ValueNotifier(null);
  static bool _loading = false;

  /// Раскрыта ли полоса сторис над списком чатов (потянули вниз)
  static final ValueNotifier<bool> expanded = ValueNotifier(false);
  static double _pull = 0;

  /// Слушатель прокрутки списка чатов: потянул вниз у самого верха: раскрыть,
  /// прокрутил список вверх: свернуть
  static bool onListScroll(ScrollNotification n) {
    if (n.depth != 0) return false;
    if (n is OverscrollNotification) {
      if (n.overscroll < 0 && n.metrics.pixels <= 0) {
        _pull += -n.overscroll;
        if (_pull > 36 && !expanded.value) expanded.value = true;
      }
    } else if (n is ScrollEndNotification) {
      _pull = 0;
    } else if (n is ScrollUpdateNotification) {
      if (n.metrics.pixels > 24 && expanded.value) expanded.value = false;
    }
    return false;
  }

  static DvApi _api(Client client) => DvApi(client, prefix: prefix);

  static Future<void> refresh(Client client) async {
    if (_loading || client.accessToken == null) return;
    _loading = true;
    try {
      final json = await _api(client).get('feed');
      final mine = <DvStory>[];
      final rawMine = json['mine'];
      if (rawMine is List) {
        for (final m in rawMine.whereType<Map<String, Object?>>()) {
          mine.add(DvStory.fromJson(m));
        }
      }
      final groups = <DvStoryGroup>[];
      final rawGroups = json['friends'];
      if (rawGroups is List) {
        for (final g in rawGroups.whereType<Map<String, Object?>>()) {
          final items = <DvStory>[];
          final rawItems = g['items'];
          if (rawItems is List) {
            for (final m in rawItems.whereType<Map<String, Object?>>()) {
              items.add(DvStory.fromJson(m));
            }
          }
          if (items.isNotEmpty) {
            groups.add(DvStoryGroup(g['user_id']?.toString() ?? '', items));
          }
        }
      }
      // Сначала те, у кого есть непросмотренное, потом по времени последней сторис
      groups.sort((a, b) {
        if (a.hasUnseen != b.hasUnseen) return a.hasUnseen ? -1 : 1;
        return b.lastTs.compareTo(a.lastTs);
      });
      feed.value = DvStoriesFeed(mine, groups);
    } catch (e, s) {
      Logs().w('DVChat: не удалось загрузить сторис', e, s);
    } finally {
      _loading = false;
    }
  }

  /// Сообщить окнам, что что-то изменилось в уже загруженном списке
  static void touch() {
    final f = feed.value;
    if (f != null) feed.value = DvStoriesFeed(f.mine, f.groups);
  }

  static Future<void> markSeen(Client client, DvStory story) async {
    story.seen = true;
    touch();
    try {
      await _api(client).post('view', {'id': story.id});
    } catch (e) {
      Logs().w('DVChat: не удалось отметить просмотр сторис', e);
    }
  }

  /// Реакция; emoji = null снимает реакцию
  static Future<void> react(Client client, DvStory story, String? emoji) async {
    await _api(client).post('react', {'id': story.id, 'emoji': emoji});
    story.myReaction = emoji;
    story.seen = true;
    touch();
  }

  static Future<void> delete(Client client, DvStory story) async {
    await _api(client).post('delete', {'id': story.id});
    await refresh(client);
  }

  static Future<List<DvStoryWatcher>> viewers(
    Client client,
    DvStory story,
  ) async {
    final json = await _api(client).post('viewers', {'id': story.id});
    final raw = json['viewers'];
    if (raw is! List) return [];
    return raw
        .whereType<Map<String, Object?>>()
        .map(
          (m) => DvStoryWatcher(
            m['user_id']?.toString() ?? '',
            (m['ts'] as num?)?.toInt() ?? 0,
            m['reaction']?.toString(),
          ),
        )
        .toList();
  }

  /// Публикация: сжатие, загрузка в медиа-хранилище и запись в модуль
  static Future<void> publish(
    Client client,
    XFile picked, {
    required bool video,
    DvAudience audience = const DvAudience.all(),
  }) async {
    late final Uint8List bytes;
    late final String name;
    late final String mime;
    int? width;
    int? height;
    int? duration;
    if (video) {
      final info = await picked.getVideoInfo();
      duration = info.duration;
      if (duration != null && duration > 10500) {
        throw const DvApiException(
          400,
          'DVS_TOO_LONG',
          'Видео длиннее 10 секунд',
        );
      }
      bytes = info.bytes;
      name = 'story.mp4';
      mime = info.mimeType ?? 'video/mp4';
      width = info.width;
      height = info.height;
      duration ??= 10000;
    } else {
      bytes = await picked.readAsBytes();
      name = 'story.jpg';
      mime = 'image/jpeg';
      try {
        final image = await decodeImageFromList(bytes);
        width = image.width;
        height = image.height;
        image.dispose();
      } catch (_) {}
    }
    final uri = await client.uploadContent(
      bytes,
      filename: name,
      contentType: mime,
    );
    await _api(client).post('publish', {
      'kind': video ? 'video' : 'photo',
      'mxc': uri.toString(),
      'width': width,
      'height': height,
      'duration_ms': duration,
      'caption': '',
      'audience': audience.all
          ? {'mode': 'all'}
          : {'mode': 'some', 'users': audience.users},
    });
    await refresh(client);
  }

  // ---------- файлы и имена ----------

  static final Map<String, Uint8List> _bytesCache = {};

  /// Байты файла сторис. Хранится в памяти не больше нескольких штук,
  /// на диск (в базу приложения) не пишется.
  static Future<Uint8List> bytes(Client client, Uri mxc) async {
    final key = mxc.toString();
    final cached = _bytesCache[key];
    if (cached != null) return cached;
    final uri = await mxc.getDownloadUri(client);
    final response = await client.httpClient.get(
      uri,
      headers: {'authorization': 'Bearer ${client.accessToken}'},
    );
    if (response.statusCode != 200) {
      throw Exception('Файл сторис недоступен (${response.statusCode})');
    }
    if (_bytesCache.length >= 8) _bytesCache.remove(_bytesCache.keys.first);
    _bytesCache[key] = response.bodyBytes;
    return response.bodyBytes;
  }

  static final Map<String, Future<Profile>> _profiles = {};
  static final Map<String, Profile> profileData = {};

  static Future<Profile> profile(Client client, String userId) =>
      _profiles.putIfAbsent(
        userId,
        () => client
            .getProfileFromUserId(userId)
            .then((p) => profileData[userId] = p),
      );

  /// Имя для показа: своё прозвище, имя профиля или логин
  static String nameOf(Client client, String userId, Profile? profile) =>
      DvNicknames.of(client, userId) ??
      profile?.displayName ??
      userId.localpart ??
      userId;

  /// «5 мин назад», «3 ч назад»
  static String ago(int ts) {
    final diff = DateTime.now().millisecondsSinceEpoch - ts;
    final min = diff ~/ 60000;
    if (min < 1) return 'только что';
    if (min < 60) return '$min мин назад';
    return '${min ~/ 60} ч назад';
  }
}
