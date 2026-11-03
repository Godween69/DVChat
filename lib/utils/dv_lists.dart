// SPDX-License-Identifier: AGPL-3.0-or-later

// DVChat: общие списки в личном чате (покупки, дела). Список это не сообщение, а состояние комнаты
// online.dvbstudio.dvchat.list (ключ состояния = номер списка), поэтому оба участника видят
// одно и то же и сразу замечают изменения. Отметка «убрал список у себя» хранится в личных данных
// комнаты online.dvbstudio.dvchat.lists_hidden и собеседника не касается: список возвращается,
// если после того, как его убрали, в нём что-то изменили.
//
// Правила (проверяет приложение, сервер хранит список целиком):
//   пункт добавляет любой; удалить пункт может только тот, кто его добавил;
//   отметить пункт может любой; снять отметку может только тот, кто её поставил;
//   переименовать список может только его создатель;
//   убрать список у себя можно, когда все пункты отмечены (или список пуст).
//
// Уведомления: когда отмечено полсписка, остался один пункт или всё готово, собеседнику уходит
// скрытое событие dv.list (в ленте не видно, приходит пушем, как dv.read и dv.story). Чтобы не
// повторяться, достигнутые рубежи запоминаются в самом списке (поле notified).
//
// Содержимое списка (content состояния):
//   title     название
//   creator   кто создал (Matrix-идентификатор; у старых списков пусто)
//   items     пункты: id, text, done, by (кто добавил), done_by (кто отметил), at (время добавления)
//   notified  рубежи, о которых уже сообщили: half, one_left, done
//   created   время создания списка, мс
//   updated   время последней правки, мс (растёт при каждой правке)

import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart';

const String dvListType = 'online.dvbstudio.dvchat.list';
const String dvListsHiddenType = 'online.dvbstudio.dvchat.lists_hidden';

/// Скрытое событие для пуша о ходе выполнения списка
const String dvListPingType = 'dv.list';

/// Ошибка с понятным человеку текстом.
class DvListsException implements Exception {
  final String message;
  const DvListsException(this.message);
  @override
  String toString() => message;
}

class DvListItem {
  const DvListItem({
    required this.id,
    required this.text,
    this.done = false,
    this.by = '',
    this.doneBy = '',
    this.at = 0,
  });

  final String id;
  final String text;
  final bool done;

  /// Кто добавил пункт (Matrix-идентификатор)
  final String by;

  /// Кто отметил пункт выполненным
  final String doneBy;

  /// Когда добавлен, мс
  final int at;

  DvListItem copyWith({String? text, bool? done, String? doneBy}) => DvListItem(
    id: id,
    text: text ?? this.text,
    done: done ?? this.done,
    by: by,
    doneBy: doneBy ?? this.doneBy,
    at: at,
  );

  /// Удалить пункт может только тот, кто его добавил (у пункта без автора может любой)
  bool canRemove(String me) => by.isEmpty || by == me;

  /// Снять отметку может только тот, кто её поставил (без автора отметки может любой)
  bool canUntick(String me) => !done || doneBy.isEmpty || doneBy == me;

  Map<String, Object?> toJson() => {
    'id': id,
    'text': text,
    'done': done,
    'by': by,
    'done_by': doneBy,
    'at': at,
  };

  static DvListItem? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final text = raw['text'];
    if (id is! String || id.isEmpty || text is! String || text.trim().isEmpty) {
      return null;
    }
    final by = raw['by'];
    final doneBy = raw['done_by'];
    final at = raw['at'];
    return DvListItem(
      id: id,
      text: text,
      done: raw['done'] == true,
      by: by is String ? by : '',
      doneBy: doneBy is String ? doneBy : '',
      at: at is int ? at : 0,
    );
  }
}

class DvList {
  const DvList({
    required this.id,
    required this.title,
    required this.items,
    required this.created,
    required this.updated,
    this.creator = '',
    this.notified = const [],
  });

  final String id;
  final String title;
  final List<DvListItem> items;
  final int created;
  final int updated;

  /// Кто создал список (у списков из первых тестовых сборок пусто)
  final String creator;

  /// Рубежи, о которых собеседнику уже сообщили: half, one_left, done
  final List<String> notified;

  int get total => items.length;
  int get doneCount => items.where((i) => i.done).length;

  /// Все пункты отмечены (у пустого списка «выполнен» не бывает)
  bool get complete => items.isNotEmpty && doneCount == items.length;

  /// Убрать у себя можно выполненный или пустой список
  bool get canHide => complete || items.isEmpty;

  /// Переименовать может создатель (если создатель неизвестен, любой из двоих)
  bool canRename(String me) => creator.isEmpty || creator == me;

  DvList copyWith({
    String? title,
    List<DvListItem>? items,
    int? updated,
    List<String>? notified,
  }) => DvList(
    id: id,
    title: title ?? this.title,
    items: items ?? this.items,
    created: created,
    updated: updated ?? this.updated,
    creator: creator,
    notified: notified ?? this.notified,
  );

  Map<String, Object?> toJson() => {
    'title': title,
    'creator': creator,
    'items': [for (final i in items) i.toJson()],
    'notified': notified,
    'created': created,
    'updated': updated,
  };

  static DvList? fromJson(String id, Map<String, Object?> content) {
    final title = content['title'];
    final rawItems = content['items'];
    if (title is! String || rawItems is! List) return null;
    final items = <DvListItem>[
      for (final raw in rawItems)
        if (DvListItem.fromJson(raw) != null) DvListItem.fromJson(raw)!,
    ];
    final created = content['created'];
    final updated = content['updated'];
    final creator = content['creator'];
    final notified = content['notified'];
    return DvList(
      id: id,
      title: title,
      items: items,
      created: created is int ? created : 0,
      updated: updated is int ? updated : 0,
      creator: creator is String ? creator : '',
      notified: notified is List
          ? [for (final n in notified) if (n is String) n]
          : const [],
    );
  }
}

/// Рубеж выполнения списка, о котором стоит сообщить собеседнику
class DvListMilestone {
  const DvListMilestone(this.kind, this.notified);

  /// half, one_left или done
  final String kind;

  /// Новый набор запомненных рубежей (для записи в список)
  final List<String> notified;
}

abstract class DvLists {
  static const int maxLists = 20;
  static const int maxAll = 100;
  static const int maxItems = 100;
  static const int maxTitle = 40;
  static const int maxText = 200;

  /// Растёт при каждой правке на этом устройстве: по нему окна перерисовываются сразу,
  /// не дожидаясь ответа сервера.
  static final ValueNotifier<int> tick = ValueNotifier<int>(0);

  // Свежие правки, которые ещё не вернулись с сервера: ключ «комната|список».
  // Показываем их поверх состояния комнаты, пока сервер не догонит (но не дольше 15 секунд).
  static final Map<String, ({DvList list, int sentAt})> _local = {};

  // Недавно убранные у себя списки: комната -> номер списка -> время правки на момент «убрать»
  static final Map<String, Map<String, int>> _hiddenLocal = {};

  // Очередь отправки: правки уходят на сервер строго по порядку
  static Future<void> _tail = Future<void>.value();

  static Future<void> _serial(Future<void> Function() job) {
    final next = _tail.then((_) => job());
    _tail = next.then((_) {}, onError: (Object _) {});
    return next;
  }

  static int _now() => DateTime.now().millisecondsSinceEpoch;

  /// Время правки всегда больше предыдущего, даже если часы устройств немного расходятся
  static int _next(int previous) {
    final now = _now();
    return now > previous ? now : previous + 1;
  }

  static final Random _random = Random.secure();

  static String _newId() {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    return String.fromCharCodes(
      List<int>.generate(
        8,
        (_) => chars.codeUnitAt(_random.nextInt(chars.length)),
      ),
    );
  }

  static String _clip(String text, int max) {
    final t = text.trim();
    return t.length <= max ? t : t.substring(0, max);
  }

  // ---------------------------------------------------------------- рубежи и тексты пушей

  /// Какой рубеж достигнут после отметки и ещё не был объявлен. Если достигнуто сразу
  /// несколько, объявляется самый важный (готово, остался один, половина), а остальные
  /// запоминаются молча.
  static DvListMilestone? nextMilestone(DvList list) {
    final t = list.total;
    final d = list.doneCount;
    if (t == 0) return null;
    final reached = <String>[
      if (d == t) 'done',
      if (t >= 2 && d == t - 1) 'one_left',
      if (t >= 2 && d * 2 >= t && d < t) 'half',
    ];
    final fresh = reached.where((k) => !list.notified.contains(k)).toList();
    if (fresh.isEmpty) return null;
    const order = ['done', 'one_left', 'half'];
    final kind = order.firstWhere(fresh.contains);
    return DvListMilestone(kind, {...list.notified, ...reached}.toList());
  }

  /// Текст уведомления по скрытому событию dv.list (имя того, кто отметил, стоит в заголовке)
  static String? pingText(Map<String, Object?> content) {
    final title = content['title'];
    if (title is! String || title.trim().isEmpty) return null;
    final name = _clip(title, maxTitle);
    final done = content['done'];
    final total = content['total'];
    switch (content['kind']) {
      case 'done':
        return 'Выполнил(а) список «$name»';
      case 'one_left':
        return 'В списке «$name» остался один пункт';
      case 'half':
        if (done is int && total is int) {
          return 'Список «$name»: отмечено $done из $total';
        }
        return 'В списке «$name» отмечена половина';
    }
    return null;
  }

  // ---------------------------------------------------------------- чтение

  /// Списки из состояния комнаты (без свежих правок)
  static Map<String, DvList> fromState(Room room) {
    final out = <String, DvList>{};
    final states = room.states[dvListType];
    if (states == null) return out;
    for (final entry in states.entries) {
      final list = DvList.fromJson(entry.key, entry.value.content);
      if (list != null) out[entry.key] = list;
    }
    return out;
  }

  /// Все списки комнаты: состояние с сервера, поверх него правки, которые ещё не вернулись
  static Map<String, DvList> all(Room room) {
    final out = fromState(room);
    final now = _now();
    final prefix = '${room.id}|';
    for (final key in _local.keys.toList()) {
      if (!key.startsWith(prefix)) continue;
      final entry = _local[key]!;
      final id = key.substring(prefix.length);
      final server = out[id];
      final caught = server != null && server.updated >= entry.list.updated;
      if (caught || now - entry.sentAt > 15000) {
        _local.remove(key);
      } else {
        out[id] = entry.list;
      }
    }
    return out;
  }

  /// Какие списки я убрал у себя: номер списка -> время его правки на тот момент
  static Map<String, int> hiddenOf(Room room) {
    final out = <String, int>{};
    final raw = room.roomAccountData[dvListsHiddenType]?.content['lists'];
    if (raw is Map) {
      for (final e in raw.entries) {
        final v = e.value;
        if (v is int) out['${e.key}'] = v;
      }
    }
    final local = _hiddenLocal[room.id];
    if (local != null) {
      for (final e in local.entries) {
        if ((out[e.key] ?? 0) < e.value) out[e.key] = e.value;
      }
    }
    return out;
  }

  /// Убранный список возвращается, если после этого в нём что-то изменили
  static bool isHidden(DvList list, Map<String, int> hidden) {
    final at = hidden[list.id];
    return at != null && list.updated <= at;
  }

  /// Списки, которые этот человек должен видеть, по порядку создания
  static List<DvList> visible(Room room) {
    final hidden = hiddenOf(room);
    final lists = all(room).values.where((l) => !isHidden(l, hidden)).toList();
    lists.sort((a, b) => a.created.compareTo(b.created));
    return lists;
  }

  /// Можно ли менять списки: нужны права на это состояние (в личном чате их выравнивает DvDmRights)
  static bool canEdit(Room room) => room.canChangeStateEvent(dvListType);

  // ---------------------------------------------------------------- правки

  static Future<void> _commit(Room room, DvList list) {
    final key = '${room.id}|${list.id}';
    _local[key] = (list: list, sentAt: _now());
    tick.value++;
    return _serial(() async {
      try {
        await room.client.setRoomStateWithKey(
          room.id,
          dvListType,
          list.id,
          list.toJson(),
        );
      } catch (_) {
        _local.remove(key);
        tick.value++;
        rethrow;
      }
    });
  }

  static Future<void> _apply(
    Room room,
    String listId,
    DvList Function(DvList current) change,
  ) {
    final current = all(room)[listId];
    if (current == null) {
      return Future<void>.error(const DvListsException('Список не найден'));
    }
    final DvList next;
    try {
      next = change(current);
    } on DvListsException catch (e) {
      return Future<void>.error(e);
    }
    return _commit(room, next.copyWith(updated: _next(current.updated)));
  }

  /// Создаёт пустой список, возвращает его номер
  static Future<String> create(Room room, String title) async {
    if (!canEdit(room)) {
      throw const DvListsException(
        'Пока нельзя создавать списки в этом чате. Откройте DVChat у того, кто создал чат: права выровняются сами.',
      );
    }
    final lists = all(room).values;
    if (lists.length >= maxAll ||
        lists.where((l) => !l.complete).length >= maxLists) {
      throw const DvListsException('Слишком много списков в этом чате');
    }
    final name = _clip(title, maxTitle);
    if (name.isEmpty) throw const DvListsException('Нужно название списка');
    final id = _newId();
    final now = _now();
    await _commit(
      room,
      DvList(
        id: id,
        title: name,
        items: const [],
        created: now,
        updated: now,
        creator: room.client.userID ?? '',
      ),
    );
    return id;
  }

  /// Переименовать может создатель списка
  static Future<void> rename(Room room, String listId, String title) {
    final name = _clip(title, maxTitle);
    if (name.isEmpty) {
      return Future<void>.error(
        const DvListsException('Нужно название списка'),
      );
    }
    final me = room.client.userID ?? '';
    return _apply(room, listId, (l) {
      if (!l.canRename(me)) {
        throw const DvListsException(
          'Переименовать список может только тот, кто его создал',
        );
      }
      return l.copyWith(title: name);
    });
  }

  /// Добавляет пункт. Рубежи уведомлений сбрасываются: в списке стало больше дел
  static Future<void> addItem(Room room, String listId, String text) {
    final t = _clip(text, maxText);
    if (t.isEmpty) return Future<void>.value();
    final me = room.client.userID ?? '';
    return _apply(room, listId, (l) {
      if (l.items.length >= maxItems) {
        throw const DvListsException('В списке уже много пунктов');
      }
      return l.copyWith(
        items: [
          ...l.items,
          DvListItem(id: _newId(), text: t, by: me, at: _now()),
        ],
        notified: const [],
      );
    });
  }

  /// Ставит или снимает отметку. Снять отметку может только тот, кто её поставил.
  /// Если достигнут рубеж (половина, остался один, готово), собеседнику уходит пуш.
  static Future<void> toggle(Room room, String listId, String itemId) async {
    final me = room.client.userID ?? '';
    DvListMilestone? milestone;
    DvList? result;
    await _apply(room, listId, (l) {
      final item = l.items.where((i) => i.id == itemId).firstOrNull;
      if (item == null) throw const DvListsException('Пункт не найден');
      if (!item.canUntick(me)) {
        throw const DvListsException(
          'Снять отметку может только тот, кто её поставил',
        );
      }
      var next = l.copyWith(
        items: [
          for (final i in l.items)
            if (i.id == itemId)
              i.copyWith(done: !i.done, doneBy: i.done ? '' : me)
            else
              i,
        ],
      );
      if (!item.done) {
        milestone = nextMilestone(next);
        if (milestone != null) {
          next = next.copyWith(notified: milestone!.notified);
        }
      }
      result = next;
      return next;
    });
    final m = milestone;
    final r = result;
    if (m == null || r == null) return;
    try {
      await room.sendEvent({
        'kind': m.kind,
        'list': r.id,
        'title': r.title,
        'done': r.doneCount,
        'total': r.total,
      }, type: dvListPingType);
    } catch (_) {
      // Пуш не ушёл: список уже сохранён, повторять не нужно
    }
  }

  /// Удалить пункт может только тот, кто его добавил
  static Future<void> removeItem(Room room, String listId, String itemId) {
    final me = room.client.userID ?? '';
    return _apply(room, listId, (l) {
      final item = l.items.where((i) => i.id == itemId).firstOrNull;
      if (item == null) return l;
      if (!item.canRemove(me)) {
        throw const DvListsException(
          'Удалить пункт может только тот, кто его добавил',
        );
      }
      return l.copyWith(items: [
        for (final i in l.items)
          if (i.id != itemId) i,
      ]);
    });
  }

  /// Убрать список только у себя: собеседник его по-прежнему видит.
  /// Убрать можно выполненный или пустой список.
  static Future<void> hide(Room room, DvList list) async {
    if (!list.canHide) {
      throw const DvListsException(
        'Убрать список можно, когда все пункты отмечены',
      );
    }
    final map = Map<String, int>.from(hiddenOf(room));
    final known = all(room);
    map.removeWhere((id, _) => !known.containsKey(id));
    map[list.id] = list.updated;
    _hiddenLocal[room.id] = Map<String, int>.from(map);
    tick.value++;
    try {
      await room.client.setAccountDataPerRoom(
        room.client.userID!,
        room.id,
        dvListsHiddenType,
        {'lists': map},
      );
    } catch (_) {
      _hiddenLocal[room.id]?.remove(list.id);
      tick.value++;
      rethrow;
    }
  }
}
