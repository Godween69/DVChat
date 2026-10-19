// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// DVChat: Верхняя панель списка чатов: поиск и статус соединения.

import 'package:dvchat/config/setting_keys.dart';
import 'package:dvchat/config/themes.dart';
import 'package:dvchat/pages/chat_list/chat_list.dart';
import 'package:dvchat/pages/chat_list/client_chooser_button.dart';
import 'package:dvchat/utils/dv_dev_menu.dart';
import 'package:dvchat/utils/sync_status_localization.dart';
import 'package:dvchat/widgets/dv_stories_strip.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

import '../../widgets/matrix.dart';

/// DVChat: поиска нет. Заголовок (или статус синхронизации) и шестерёнка.
class ChatListHeader extends StatelessWidget implements PreferredSizeWidget {
  final ChatListController controller;
  final bool globalSearch;

  const ChatListHeader({
    super.key,
    required this.controller,
    this.globalSearch = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final client = Matrix.of(context).client;
    final isColumnMode = DvThemes.isColumnMode(context);

    return SliverAppBar(
      floating: true,
      toolbarHeight: 64,
      pinned: isColumnMode,
      scrolledUnderElevation: 0,
      clipBehavior: Clip.none,
      shape: isColumnMode
          ? Border(bottom: BorderSide(color: theme.dividerColor, width: 1))
          : null,
      backgroundColor: isColumnMode
          ? theme.colorScheme.surface.withAlpha(240)
          : Colors.transparent,
      automaticallyImplyLeading: false,
      title: StreamBuilder(
        stream: client.onSyncStatus.stream,
        builder: (context, snapshot) {
          final status =
              client.onSyncStatus.value ??
              const SyncStatusUpdate(SyncStatus.waitingForResponse);
          final synced =
              client.onSync.value != null &&
              status.status != SyncStatus.error &&
              client.prevBatch != null;
          return Row(
            children: [
              if (!synced) ...[
                SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator.adaptive(
                    strokeWidth: 2,
                    value: status.progress,
                  ),
                ),
                const SizedBox(width: 12),
              ],
              if (synced) ...[
                DvStoriesCompact(client: client),
                const SizedBox(width: 12),
              ],
              Flexible(
                // DVChat: 20 быстрых нажатий на заголовок открывают скрытое меню разработчика
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => DvDevMenu.tap(context),
                  child: Text(
                    synced
                        ? AppSettings.applicationName.value
                        : status.calcLocalizedString(context),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleLarge,
                  ),
                ),
              ),
              const Spacer(),
            ],
          );
        },
      ),
      actions: [ClientChooserButton(controller), const SizedBox(width: 4)],
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(56);
}
