// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:dvchat/l10n/l10n.dart';
import 'package:dvchat/pages/archive/archive.dart';
import 'package:dvchat/pages/chat_list/chat_list_item.dart';
import 'package:dvchat/utils/stream_extension.dart';
import 'package:dvchat/widgets/layouts/max_width_body.dart';
import 'package:dvchat/widgets/matrix.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

class ArchiveView extends StatelessWidget {
  final ArchiveController controller;

  const ArchiveView(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    final client = Matrix.of(context).client;
    return StreamBuilder(
      stream: client.onSync.stream.rateLimit(const Duration(seconds: 1)),
      builder: (context, _) => FutureBuilder<List<ArchivedRoom>>(
        future: controller.getLeftRooms(context),
        builder: (context, snapshot) {
          final archived = controller.archivedRooms;
          final left = snapshot.data ?? controller.leftRooms;
          final isEmpty = archived.isEmpty && left.isEmpty;
          return Scaffold(
            appBar: AppBar(
              leading: const Center(child: BackButton()),
              title: Text(L10n.of(context).archive),
              actions: [
                if (!isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: TextButton.icon(
                      onPressed: controller.forgetAllAction,
                      label: Text(L10n.of(context).clearArchive),
                      icon: const Icon(Icons.cleaning_services_outlined),
                    ),
                  ),
              ],
            ),
            body: MaxWidthBody(
              withScrolling: false,
              child: snapshot.hasError
                  ? Center(
                      child: Text(
                        L10n.of(context).oopsSomethingWentWrong,
                        textAlign: TextAlign.center,
                      ),
                    )
                  : isEmpty
                  ? (snapshot.hasData
                        ? const Center(
                            child: Icon(Icons.archive_outlined, size: 80),
                          )
                        : const Center(
                            child: CircularProgressIndicator.adaptive(
                              strokeWidth: 2,
                            ),
                          ))
                  : ListView(
                      children: [
                        for (final room in archived)
                          ChatListItem(
                            room,
                            key: ValueKey('archived_${room.id}'),
                            onForget: () => controller.deleteArchivedRoom(room),
                            onTap: () => context.go('/rooms/${room.id}'),
                          ),
                        for (final entry in left)
                          ChatListItem(
                            entry.room,
                            key: ValueKey('left_${entry.room.id}'),
                            onForget: () => controller.forgetLeftRoom(entry),
                            onTap: () => context.go(
                              '/rooms/archive/${entry.room.id}',
                              extra: entry.timeline,
                            ),
                          ),
                      ],
                    ),
            ),
          );
        },
      ),
    );
  }
}
