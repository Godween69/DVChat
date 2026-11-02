// DVChat: Галочки доставки и прочтения.

import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

/// DVChat: галочки статуса своего сообщения, как в Telegram.
/// ✓ серая — сообщение отправлено на сервер.
/// ✓✓ зелёная — прочитано: в личном чате собеседник, в группе — все участники.
/// «Прочитано» считаем так: у кого-то (кроме меня) есть отметка о прочтении
/// на этом сообщении или на любом более новом.
class MessageTicks extends StatelessWidget {
  final Event event;
  final Timeline timeline;
  final Color? color;

  const MessageTicks({
    required this.event,
    required this.timeline,
    this.color,
    super.key,
  });

  static const Color readColor = Color(0xFF4CD964);

  bool get _isRead {
    final myId = event.room.client.userID;
    final readers = <String>{};
    // timeline.events идёт от новых к старым: собираем отметки до нашего сообщения
    for (final e in timeline.events) {
      readers.addAll(
        e.receipts.map((r) => r.user.id).where((id) => id != myId),
      );
      if (e.eventId == event.eventId) break;
    }
    if (event.room.isDirectChat) return readers.isNotEmpty;
    final others = (event.room.summary.mJoinedMemberCount ?? 1) - 1;
    return others > 0 && readers.length >= others;
  }

  @override
  Widget build(BuildContext context) {
    // Перерисовываем, когда приходит новая отметка о прочтении в этой комнате
    return StreamBuilder(
      stream: event.room.client.onSync.stream.where(
        (syncUpdate) =>
            syncUpdate.rooms?.join?[event.room.id]?.ephemeral?.any(
              (ephemeral) => ephemeral.type == 'm.receipt',
            ) ??
            false,
      ),
      builder: (context, _) {
        final read = _isRead;
        return Icon(
          read ? Icons.done_all : Icons.done,
          size: 15,
          color: read ? readColor : color,
        );
      },
    );
  }
}
