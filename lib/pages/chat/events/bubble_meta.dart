// SPDX-License-Identifier: AGPL-3.0-or-later

// DVChat: время, «изменено», галочки и статус отправки внутри пузыря, справа внизу.

import 'package:dvchat/l10n/l10n.dart';
import 'package:dvchat/pages/chat/events/message_ticks.dart';
import 'package:dvchat/utils/date_time_extension.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

class BubbleMeta extends StatelessWidget {
  const BubbleMeta({
    required this.event,
    required this.timeline,
    required this.ownMessage,
    required this.edited,
    required this.color,
    this.onMedia = false,
    super.key,
  });

  final Event event;
  final Timeline timeline;
  final bool ownMessage;
  final bool edited;
  final Color color;

  /// Поверх картинки или видео: светлый текст на тёмной подложке
  final bool onMedia;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    final fg = onMedia ? Colors.white : color;
    final style = TextStyle(color: fg, fontSize: 11, height: 1.1);
    final status = event.status;
    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (edited) ...[
          Text(l10n.edited, style: style),
          const SizedBox(width: 4),
        ],
        if (status.isSent)
          Text(event.originServerTs.localizedTimeOfDay(context), style: style),
        if (ownMessage && status.isSent) ...[
          const SizedBox(width: 3),
          MessageTicks(event: event, timeline: timeline, color: fg),
        ],
        if (status == EventStatus.error) ...[
          Text(
            l10n.couldNotBeSent,
            style: style.copyWith(color: theme.colorScheme.error),
          ),
          const SizedBox(width: 3),
          Icon(Icons.error_outlined, size: 13, color: theme.colorScheme.error),
        ],
        if (status == EventStatus.sending) ...[
          Text(switch (event.fileSendingStatus) {
            null => l10n.sending,
            FileSendingStatus.generatingThumbnail => l10n.generatingThumbnail,
            FileSendingStatus.encrypting => l10n.encrypting,
            FileSendingStatus.uploading => l10n.uploading,
          }, style: style),
          const SizedBox(width: 4),
          SizedBox.square(
            dimension: 10,
            child: CircularProgressIndicator(strokeWidth: 1, color: fg),
          ),
        ],
      ],
    );
    if (!onMedia) return row;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(110),
        borderRadius: BorderRadius.circular(10),
      ),
      child: row,
    );
  }
}
