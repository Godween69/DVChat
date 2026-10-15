// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// DVChat: Закреплённые сообщения вверху чата: список с датой закрепления и снятием закрепа.

import 'package:dvchat/l10n/l10n.dart';
import 'package:dvchat/pages/chat/chat.dart';
import 'package:dvchat/pages/chat/chat_app_bar_list_tile.dart';
import 'package:dvchat/utils/dv_confirm.dart';
import 'package:dvchat/utils/dv_pins.dart';
import 'package:dvchat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:dvchat/widgets/future_loading_dialog.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

class PinnedEvents extends StatelessWidget {
  final ChatController controller;

  const PinnedEvents(this.controller, {super.key});

  Future<void> _displayPinnedEventsDialog(BuildContext context) async {
    final eventsResult = await showFutureLoadingDialog(
      context: context,
      future: () => Future.wait(
        controller.room.pinnedEventIds.map(
          (eventId) => controller.room.getEventById(eventId),
        ),
      ),
    );
    final events = eventsResult.result;
    if (events == null) return;
    if (!context.mounted) return;

    final loaded = events.whereType<Event>().toList();
    if (loaded.isEmpty) return;
    if (loaded.length == 1) {
      controller.scrollToEventId(loaded.single.eventId);
      return;
    }
    final eventId = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (context) =>
          _PinnedSheet(controller: controller, events: loaded),
    );
    if (eventId != null) controller.scrollToEventId(eventId);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final pinnedEventIds = controller.room.pinnedEventIds;

    if (pinnedEventIds.isEmpty || controller.activeThreadId != null) {
      return const SizedBox.shrink();
    }

    return FutureBuilder<Event?>(
      future: controller.room.getEventById(pinnedEventIds.last),
      builder: (context, snapshot) {
        final event = snapshot.data;
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          child: ChatAppBarListTile(
            key: ValueKey(pinnedEventIds.last),
            title:
                event
                    ?.calcLocalizedBodyFallback(
                      MatrixLocals(L10n.of(context)),
                      withSenderNamePrefix: true,
                      hideReply: true,
                    )
                    .replaceAll('\n', ' ') ??
                L10n.of(context).loadingPleaseWait,
            leading: IconButton(
              splashRadius: 18,
              iconSize: 18,
              color: theme.colorScheme.onSurfaceVariant,
              icon: const Icon(Icons.push_pin),
              tooltip: L10n.of(context).unpin,
              onPressed:
                  controller.room.canSendEvent(EventTypes.RoomPinnedEvents)
                  ? () => controller.unpinEvent(pinnedEventIds.last)
                  : null,
            ),
            onTap: () => _displayPinnedEventsDialog(context),
          ),
        );
      },
    );
  }
}

/// Список закреплённых: под каждым сообщением дата закрепления, справа корзина
class _PinnedSheet extends StatefulWidget {
  const _PinnedSheet({required this.controller, required this.events});

  final ChatController controller;
  final List<Event> events;

  @override
  State<_PinnedSheet> createState() => _PinnedSheetState();
}

class _PinnedSheetState extends State<_PinnedSheet> {
  late final List<Event> _events = [...widget.events];

  Future<void> _unpin(Event event) async {
    final l10n = L10n.of(context);
    final room = widget.controller.room;
    final ok = await DvConfirm.ask(
      context,
      key: 'dv_confirm_unpin',
      title: l10n.unpin,
      message: l10n.confirmEventUnpin,
      okLabel: l10n.unpin,
    );
    if (!ok || !mounted) return;
    final ids = room.pinnedEventIds..removeWhere((id) => id == event.eventId);
    final done = await showFutureLoadingDialog(
      context: context,
      future: () => DvPins.save(room, ids),
    );
    if (done.error != null || !mounted) return;
    setState(() => _events.removeWhere((e) => e.eventId == event.eventId));
    if (_events.isEmpty) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);
    final room = widget.controller.room;
    final canUnpin = room.canChangeStateEvent(EventTypes.RoomPinnedEvents);
    final stamps = DvPins.stamps(room);
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'Закреплённые сообщения',
              style: theme.textTheme.titleMedium,
            ),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final event in _events)
                  ListTile(
                    leading: Icon(
                      event.messageType == MessageTypes.Image
                          ? Icons.photo_outlined
                          : Icons.push_pin_outlined,
                    ),
                    title: Text(
                      event
                          .calcLocalizedBodyFallback(
                            MatrixLocals(l10n),
                            withSenderNamePrefix: true,
                            hideReply: true,
                          )
                          .trim()
                          .replaceAll('\n', ' '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: stamps[event.eventId] == null
                        ? null
                        : Text(
                            'Закреплено: ${DvPins.when(stamps[event.eventId]!)}',
                            style: TextStyle(
                              fontSize: 11,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                    trailing: canUnpin
                        ? IconButton(
                            icon: const Icon(Icons.delete_outlined),
                            tooltip: l10n.unpin,
                            onPressed: () => _unpin(event),
                          )
                        : null,
                    onTap: () => Navigator.of(context).pop(event.eventId),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
