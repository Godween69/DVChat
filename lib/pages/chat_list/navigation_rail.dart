// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// DVChat: узкая боковая панель списка чатов на широком экране.
//
// Раньше здесь были ещё спейсы (группы чатов), теперь остаётся кнопка «Чаты»
// и кнопка создания нового чата.

import 'package:dvchat/config/themes.dart';
import 'package:dvchat/l10n/l10n.dart';
import 'package:dvchat/pages/chat_list/navi_rail_item.dart';
import 'package:dvchat/pages/chat_list/start_chat_fab.dart';
import 'package:material_ui/material_ui.dart';

class ChatsNavigationRail extends StatelessWidget {
  const ChatsNavigationRail({super.key});

  @override
  Widget build(BuildContext context) {
    return Material(
      child: SafeArea(
        child: SizedBox(
          width: DvThemes.navRailWidth,
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  children: [
                    NaviRailItem(
                      isSelected: true,
                      onTap: () {},
                      icon: const Padding(
                        padding: EdgeInsets.all(12.0),
                        child: Icon(Icons.forum_outlined),
                      ),
                      selectedIcon: const Padding(
                        padding: EdgeInsets.all(12.0),
                        child: Icon(Icons.forum),
                      ),
                      toolTip: L10n.of(context).chats,
                      unreadBadgeFilter: (room) => true,
                    ),
                  ],
                ),
              ),
              const Padding(
                padding: EdgeInsets.all(12.0),
                child: StartChatFab(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
