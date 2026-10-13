// SPDX-License-Identifier: AGPL-3.0-or-later

// DVChat: внутреннее окно «Собеседник закрыл чат». Показывается один раз, когда у человека
// появляется личный чат, из которого вышел собеседник (чат при этом уходит в Архив).
// Текст зависит от того, остались ли они друзьями. Окно закрывается кнопкой «Понятно».

import 'package:dvchat/utils/dv_api.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

Future<void> showClosedChatNotice(
  BuildContext context,
  List<Room> rooms,
) async {
  for (final room in rooms) {
    final partnerId = room.directChatMatrixID;
    if (partnerId == null) continue;
    final client = room.client;

    var name = partnerId.localpart ?? partnerId;
    try {
      name = (await client.getProfileFromUserId(partnerId)).displayName ?? name;
    } catch (_) {}

    // true / false — друзья или нет; null — узнать не удалось (нет сети)
    bool? stillFriends;
    try {
      final answer = await DvApi(client).get('friends');
      final list = answer['friends'];
      stillFriends =
          list is List &&
          list.whereType<Map<String, Object?>>().any(
            (m) => m['user_id'] == partnerId,
          );
    } catch (_) {}

    final text = switch (stillFriends) {
      true =>
        '$name удалил(а) чат. Переписка перенесена в Архив: её можно хранить, '
            'читать или удалить. Вы по-прежнему друзья, можно начать новый чат.',
      false =>
        '$name удалил(а) вас из друзей. Переписка перенесена в Архив: её можно '
            'хранить, читать или удалить. Чтобы общаться снова, добавьтесь друг '
            'к другу заново через QR-код или ID.',
      null =>
        '$name закрыл(а) чат. Переписка перенесена в Архив: её можно хранить, '
            'читать или удалить.',
    };

    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Чат закрыт'),
        content: Text(text),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Понятно'),
          ),
        ],
      ),
    );
  }
}
