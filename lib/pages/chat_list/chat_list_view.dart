// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// DVChat: каркас экрана списка чатов.
//
// На широком экране слева узкая панель (navigation_rail.dart), справа сам
// список (chat_list_body.dart). На телефоне только список и кнопка нового чата.

import 'package:dvchat/config/themes.dart';
import 'package:dvchat/pages/chat_list/chat_list.dart';
import 'package:dvchat/pages/chat_list/navigation_rail.dart';
import 'package:material_ui/material_ui.dart';

import 'chat_list_body.dart';

class ChatListView extends StatelessWidget {
  final ChatListController controller;

  const ChatListView(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    final isColumnMode = DvThemes.isColumnMode(context);
    return Row(
      children: [
        Material(
          color: Theme.of(context).colorScheme.surface,
          child: AnimatedSize(
            duration: DvThemes.animationDuration,
            curve: DvThemes.animationCurve,
            child: isColumnMode
                ? const ChatsNavigationRail()
                : SizedBox(width: 0, height: MediaQuery.sizeOf(context).height),
          ),
        ),
        if (isColumnMode)
          Container(width: 1, color: Theme.of(context).dividerColor),
        Expanded(
          child: GestureDetector(
            onTap: FocusManager.instance.primaryFocus?.unfocus,
            excludeFromSemantics: true,
            behavior: HitTestBehavior.translucent,
            child: Scaffold(
              body: Material(child: ChatListViewBody(controller)),
            ),
          ),
        ),
      ],
    );
  }
}
