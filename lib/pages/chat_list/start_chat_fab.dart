// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:material_ui/material_ui.dart';

/// DVChat: кнопка создания чата скрыта, комнатами управляет только администратор.
/// Оригинал: git show baseline-fluffychat-2.10.0:lib/pages/chat_list/start_chat_fab.dart
class StartChatFab extends StatelessWidget {
  final bool extended;
  const StartChatFab({this.extended = false, super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
