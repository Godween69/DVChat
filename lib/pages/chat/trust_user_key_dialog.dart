// DVChat: все пользователи сервера доверенные. Никаких диалогов сверки ключей,
// эмодзи и «заверено / не заверено»: ключи пользователей заверяются молча.

import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

/// Молча заверяет ключи всех участников комнаты и разрешает отправку.
Future<bool> showTrustUserInRoomDialog(BuildContext context, Room room) async {
  if (!room.encrypted) return true;
  final users = await room.requestParticipants();
  for (final user in users) {
    if (user.id == room.client.userID) continue;
    final masterKey = room.client.userDeviceKeys[user.id]?.masterKey;
    if (masterKey == null ||
        masterKey.verified ||
        masterKey.trustOnFirstUseSince != null) {
      continue;
    }
    masterKey.trustOnFirstUse();
  }
  return true;
}
