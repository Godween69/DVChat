// SPDX-License-Identifier: AGPL-3.0-or-later

// DVChat: альбом фото. Пачка фото уходит обычными сообщениями-картинками, у каждого есть
// метка с общим номером альбома, номером фото и общим числом. Чат собирает такие фото
// в одну сетку у первого фото, остальные отдельно не показывает, а уведомление
// приходит только о первом. Старые версии приложения видят просто несколько фото.

import 'package:matrix/matrix.dart';

/// Ключ метки альбома в содержимом сообщения
const String dvAlbumKey = 'online.dvbstudio.dvchat.album';

/// Больше фото в одном альбоме не бывает (лишние уходят следующим альбомом)
const int dvAlbumMax = 30;

/// Метка альбома у одного сообщения
class DvAlbum {
  const DvAlbum(this.id, this.index, this.count);

  /// Общий номер альбома
  final String id;

  /// Номер фото в альбоме с нуля
  final int index;

  /// Сколько всего фото в альбоме
  final int count;
}

/// Метка альбома у сообщения или null, если сообщение не из альбома
DvAlbum? dvAlbumOf(Event event) {
  final raw = event.content[dvAlbumKey];
  if (raw is! Map) return null;
  final id = raw['id'];
  final i = raw['i'];
  final n = raw['n'];
  if (id is! String || i is! int || n is! int) return null;
  if (n < 2 || n > dvAlbumMax || i < 0 || i >= n) return null;
  return DvAlbum(id, i, n);
}

/// Фото альбома, кроме первого: в ленте отдельно не показываются
bool dvIsAlbumTail(Event event) {
  final a = dvAlbumOf(event);
  return a != null && a.index > 0;
}

/// Все фото альбома по порядку (первое, второе...). Берутся только фото того же
/// отправителя с тем же номером альбома; удалённые пропускаются.
List<Event> dvAlbumMembers(Event head, Timeline timeline) {
  final a = dvAlbumOf(head);
  if (a == null) return [head];
  final byIndex = <int, Event>{};
  for (final e in timeline.events) {
    if (e.redacted || e.senderId != head.senderId) continue;
    final m = dvAlbumOf(e);
    if (m == null || m.id != a.id) continue;
    byIndex.putIfAbsent(m.index, () => e);
  }
  final keys = byIndex.keys.toList()..sort();
  return [for (final k in keys) byIndex[k]!];
}
