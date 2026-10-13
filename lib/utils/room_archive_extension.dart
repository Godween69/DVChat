// DVChat: архив личных чатов. Чат помечается тегом и скрывается из списка,
// из комнаты никто не выходит, поэтому собеседник ничего не видит.
// Возврат в список определяется по времени сообщений, а не по счётчику непрочитанных.

import 'package:dvchat/config/app_config.dart';
import 'package:matrix/matrix.dart';

/// Тип данных комнаты: время последнего сообщения в момент архивации (серверное)
const String _archiveStampType = 'online.dvbstudio.dvchat.archived_at';

/// Метка комнаты поддержки (ставится сервером): такой чат нельзя покинуть, только скрыть
const String _supportStateType = 'online.dvbstudio.dvchat.support';

/// Комнаты, которые прямо сейчас возвращаются в список (защита от повторных вызовов)
final Set<String> _returningRooms = {};

extension RoomArchiveExtension on Room {
  /// Чат лежит в архиве (виден только на экране «Архив»)
  bool get isInArchive => tags.containsKey(AppConfig.archiveTag);

  /// Закрытый чат: собеседник вышел, мы тоже не в комнате. Только чтение истории:
  /// без выбора, копирования, пересылки, ответов, реакций и сохранения файлов.
  bool get isHistoryOnly =>
      {Membership.leave, Membership.ban}.contains(membership);

  /// Чат удалён из архива: скрыт, вернётся при новом сообщении
  bool get isHiddenByUser => tags.containsKey(AppConfig.hiddenTag);

  /// Чат с администратором (серверная метка в состоянии комнаты)
  bool get isSupportRoom => getState(_supportStateType) != null;

  int? get _archivedAtMs {
    final value = roomAccountData[_archiveStampType]?.content['ts'];
    return value is int ? value : null;
  }

  /// Чат создан для меня как для новичка: в нём пока только приветствие «X теперь в DVChat»
  /// с моей пометкой. Такой чат скрыт, пока мне не напишут (последним станет другое сообщение).
  bool get isNewcomerPlaceholder {
    final marker = lastEvent?.content['online.dvbstudio.dvchat.newcomer'];
    return marker is String && marker == client.userID;
  }

  /// Пришло приглашение или чужое сообщение новее метки архивации
  bool get hasNewMessages {
    if (membership == Membership.invite) return true;
    final since = _archivedAtMs;
    final last = lastEvent;
    if (since == null || last == null) return false;
    return last.senderId != client.userID &&
        last.originServerTs.millisecondsSinceEpoch > since;
  }

  Future<void> _stamp() => client.setAccountDataPerRoom(
    client.userID!,
    id,
    _archiveStampType,
    {
      'ts':
          (lastEvent?.originServerTs ?? DateTime.now()).millisecondsSinceEpoch,
    },
  );

  Future<void> moveToArchive() async {
    await _stamp();
    await addTag(AppConfig.archiveTag);
  }

  Future<void> restoreFromArchive() => removeTag(AppConfig.archiveTag);

  /// Удалить из архива: ставим скрытый тег, тег архива снимаем
  Future<void> hideForever() async {
    await _stamp();
    await addTag(AppConfig.hiddenTag);
    if (isInArchive) await removeTag(AppConfig.archiveTag);
  }

  /// Новое сообщение вернуло чат в список: снимаем оба тега
  Future<void> returnToList() async {
    if (!_returningRooms.add(id)) return;
    try {
      if (isInArchive) await removeTag(AppConfig.archiveTag);
      if (isHiddenByUser) await removeTag(AppConfig.hiddenTag);
    } finally {
      _returningRooms.remove(id);
    }
  }
}
