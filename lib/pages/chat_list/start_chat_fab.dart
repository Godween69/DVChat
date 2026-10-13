// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

/// DVChat: кнопка «+» открывает экран «Друзья» (чаты создаются из списка друзей).
/// Оригинал: git show baseline-fluffychat-2.10.0:lib/pages/chat_list/start_chat_fab.dart
class StartChatFab extends StatelessWidget {
  final bool extended;
  const StartChatFab({this.extended = false, super.key});

  @override
  Widget build(BuildContext context) {
    void open() => context.go('/rooms/friends');
    if (extended) {
      return FloatingActionButton.extended(
        heroTag: null,
        onPressed: open,
        icon: const Icon(Icons.add),
        label: const Text('Друзья'),
      );
    }
    return FloatingActionButton(
      heroTag: null,
      onPressed: open,
      tooltip: 'Друзья',
      child: const Icon(Icons.add),
    );
  }
}
