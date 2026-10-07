import 'package:flutter/material.dart';

/// Кастомизация DVChat: Кнопка создания чата скрыта.
/// Управление комнатами только через десктопного админа.
class StartChatFab extends StatelessWidget {
  const StartChatFab({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}
