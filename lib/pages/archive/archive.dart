// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/archive/archive_view.dart';
import 'package:fluffychat/utils/room_archive_extension.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';
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
  List<Room> get archivedRooms => Matrix.of(
    context,
  ).client.rooms.where((room) => room.isInArchive).toList();

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
    await showFutureLoadingDialog(context: context, future: room.hideForever);
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
          await room.hideForever();
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

  @override
  Widget build(BuildContext context) => ArchiveView(this);
}
