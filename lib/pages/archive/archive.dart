// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// DVChat: Экран «Архив»: скрытые личные чаты (логика). Внешний вид — archive_view.dart,
// способ архивации — utils/room_archive_extension.dart.

import 'package:dvchat/config/setting_keys.dart';
import 'package:dvchat/l10n/l10n.dart';
import 'package:dvchat/pages/archive/archive_view.dart';
import 'package:dvchat/pages/chat_list/chat_list_item.dart';
import 'package:dvchat/utils/room_archive_extension.dart';
import 'package:dvchat/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import 'package:dvchat/widgets/future_loading_dialog.dart';
import 'package:dvchat/widgets/matrix.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

class Archive extends StatefulWidget {
  const Archive({super.key});

  @override
  ArchiveController createState() => ArchiveController();
}

class ArchiveController extends State<Archive> {
  /// Покинутые группы (выход из комнаты, восстановить нельзя)
  List<ArchivedRoom> leftRooms = [];
  Future<List<ArchivedRoom>>? _leftRoomsFuture;

  /// Чаты, отправленные в архив тегом (их можно вернуть)
  List<Room> get archivedRooms => Matrix.of(context).client.rooms
      .where(
        (room) =>
            room.isInArchive ||
            (room.isAbandonedDMRoom == true && !room.isHiddenByUser),
      )
      .toList();

  Future<List<ArchivedRoom>> getLeftRooms(BuildContext context) =>
      _leftRoomsFuture ??= Matrix.of(
        context,
      ).client.loadArchiveWithTimeline().then((rooms) => leftRooms = rooms);

  /// Подтверждение удаления одного чата, с галочкой «Больше не спрашивать»
  Future<bool> _confirmDelete(String message) async {
    if (!AppSettings.archiveDeleteConfirm.value) return true;
    var dontAskAgain = false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Удалить чат из архива?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(message),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: dontAskAgain,
                onChanged: (value) =>
                    setDialogState(() => dontAskAgain = value ?? false),
                title: const Text('Больше не спрашивать'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(L10n.of(context).cancel),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(L10n.of(context).delete),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return false;
    if (dontAskAgain) await AppSettings.archiveDeleteConfirm.setItem(false);
    return true;
  }

  Future<void> deleteArchivedRoom(Room room) async {
    if (!await _confirmDelete(
      'Чат пропадёт из списка. Он вернётся, если в нём появится новое сообщение.',
    )) {
      return;
    }
    if (!mounted) return;
    // Закрытый чат удаляем по-настоящему (выход и забывание), иначе он остаётся в аккаунте
    await showFutureLoadingDialog(
      context: context,
      future: () => room.isAbandonedDMRoom == true
          ? room.deleteForMe()
          : room.hideForever(),
    );
    if (mounted) setState(() {});
  }

  Future<void> forgetLeftRoom(ArchivedRoom archived) async {
    if (!await _confirmDelete('Чат будет удалён из архива навсегда.')) return;
    if (!mounted) return;
    await showFutureLoadingDialog(
      context: context,
      future: () async {
        await archived.room.forget();
        leftRooms.remove(archived);
      },
    );
    if (mounted) setState(() {});
  }

  /// «Очистить архив»: подтверждение всегда
  Future<void> forgetAllAction() async {
    final archived = archivedRooms;
    final left = List.of(leftRooms);
    if (archived.isEmpty && left.isEmpty) return;
    final confirmed = await showOkCancelAlertDialog(
      useRootNavigator: false,
      context: context,
      title: L10n.of(context).areYouSure,
      okLabel: L10n.of(context).yes,
      cancelLabel: L10n.of(context).cancel,
      message: 'Это удалит все сообщения из архива.',
    );
    if (confirmed != OkCancelResult.ok) return;
    if (!mounted) return;
    await showFutureLoadingDialog(
      context: context,
      futureWithProgress: (onProgress) async {
        final total = archived.length + left.length;
        var done = 0;
        for (final room in archived) {
          if (room.isAbandonedDMRoom == true) {
            await room.deleteForMe();
          } else {
            await room.hideForever();
          }
          onProgress(++done / total);
        }
        for (final entry in left) {
          await entry.room.forget();
          leftRooms.remove(entry);
          onProgress(++done / total);
        }
      },
    );
    if (mounted) setState(() {});
  }

  static const _months = [
    'января',
    'февраля',
    'марта',
    'апреля',
    'мая',
    'июня',
    'июля',
    'августа',
    'сентября',
    'октября',
    'ноября',
    'декабря',
  ];

  /// Строки архива одним списком: новые сверху, разделители по дням.
  /// Закрытый чат (собеседник вышел) датируется последним событием в нём,
  /// чат «В архив» — последним сообщением.
  List<Widget> buildItems(
    BuildContext context,
    List<Room> archived,
    List<ArchivedRoom> left,
  ) {
    final epoch = DateTime.fromMillisecondsSinceEpoch(0);
    final entries = <_ArchiveEntry>[
      for (final room in archived)
        _ArchiveEntry(
          date: room.lastEvent?.originServerTs ?? epoch,
          closed: room.isAbandonedDMRoom == true,
          item: ChatListItem(
            room,
            key: ValueKey('archived_${room.id}'),
            onForget: () => deleteArchivedRoom(room),
            onTap: () => context.go('/rooms/${room.id}'),
          ),
        ),
      for (final entry in left)
        _ArchiveEntry(
          date:
              entry.timeline.events.firstOrNull?.originServerTs ??
              entry.room.lastEvent?.originServerTs ??
              epoch,
          closed: true,
          item: ChatListItem(
            entry.room,
            key: ValueKey('left_${entry.room.id}'),
            onForget: () => forgetLeftRoom(entry),
            onTap: () => context.go(
              '/rooms/archive/${entry.room.id}',
              extra: entry.timeline,
            ),
          ),
        ),
    ]..sort((a, b) => b.date.compareTo(a.date));

    final theme = Theme.of(context);
    final result = <Widget>[];
    DateTime? lastDay;
    for (final e in entries) {
      final day = DateTime(e.date.year, e.date.month, e.date.day);
      if (lastDay != day) {
        lastDay = day;
        result.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(
              '${day.day} ${_months[day.month - 1]} ${day.year}',
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          ),
        );
      }
      result.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 2, 16, 0),
          child: Text(
            e.closed ? 'Закрыт · только чтение' : 'В архиве · можно вернуть',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
      result.add(e.item);
    }
    return result;
  }

  @override
  Widget build(BuildContext context) => ArchiveView(this);
}

class _ArchiveEntry {
  final DateTime date;
  final bool closed;
  final Widget item;

  const _ArchiveEntry({
    required this.date,
    required this.closed,
    required this.item,
  });
}
