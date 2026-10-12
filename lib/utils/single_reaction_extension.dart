// DVChat: у пользователя на одном сообщении может быть только одна реакция.

import 'package:collection/collection.dart';
import 'package:matrix/matrix.dart';

extension SingleReactionExtension on Room {
  /// Ставит реакцию [key]: прежние реакции пользователя на этом сообщении снимаются,
  /// повторный выбор той же реакции просто снимает её.
  Future<void> setMyReaction(Event event, Timeline timeline, String key) async {
    final own = event
        .aggregatedEvents(timeline, RelationshipTypes.reaction)
        .where((e) => e.senderId == client.userID)
        .toList();
    final same = own.firstWhereOrNull(
      (e) =>
          e.content
              .tryGetMap<String, Object?>('m.relates_to')
              ?.tryGet<String>('key') ==
          key,
    );
    for (final e in own) {
      await e.redactEvent();
    }
    if (same == null) await sendReaction(event.eventId, key);
  }
}
