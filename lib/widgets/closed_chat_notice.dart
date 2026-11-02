// SPDX-License-Identifier: AGPL-3.0-or-later

// DVChat: внутреннее окно «Собеседник закрыл чат». Показывается один раз на каждый закрытый
// чат (запоминается на телефоне) и одним окном на все новые чаты сразу, поэтому хватает
// одного нажатия «Понятно». Текст зависит от того, остались ли они друзьями.

import 'package:dvchat/utils/dv_api.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Ключ в памяти телефона: номера комнат, о которых окно уже показывали
const String _shownKey = 'dvchat.closed_notice_shown';

/// Пока окно готовится или открыто, повторные вызовы (список чатов перерисовывается
/// часто) ничего не делают: иначе окно вылезало бы дважды
bool _noticeBusy = false;

Future<void> showClosedChatNotice(
  BuildContext context,
  List<Room> rooms,
) async {
  if (_noticeBusy) return;
  _noticeBusy = true;
  try {
    await _showClosedChatNotice(context, rooms);
  } finally {
    _noticeBusy = false;
  }
}

Future<void> _showClosedChatNotice(
  BuildContext context,
  List<Room> rooms,
) async {
  // Какие чаты уже объясняли человеку: их не показываем никогда больше
  SharedPreferences? prefs;
  var shown = <String>{};
  try {
    prefs = await SharedPreferences.getInstance();
    shown = (prefs.getStringList(_shownKey) ?? const <String>[]).toSet();
  } catch (_) {}
  final fresh = rooms.where((r) => !shown.contains(r.id)).toList();
  if (fresh.isEmpty) return;
  // Запоминаем сразу, не дожидаясь нажатия: окно не вылезет снова, пока открыто это
  try {
    await prefs?.setStringList(_shownKey, {
      ...shown,
      ...fresh.map((r) => r.id),
    }.toList());
  } catch (_) {}

  // true / false: друзья или нет; null: узнать не удалось (нет сети)
  final client = fresh.first.client;
  Set<String>? friendIds;
  try {
    final answer = await DvApi(client).get('friends');
    final list = answer['friends'];
    if (list is List) {
      friendIds = list
          .whereType<Map<String, Object?>>()
          .map((m) => '${m['user_id']}')
          .toSet();
    }
  } catch (_) {}

  final lines = <String>[];
  for (final room in fresh) {
    final partnerId = room.directChatMatrixID;
    if (partnerId == null) continue;
    var name = partnerId.localpart ?? partnerId;
    try {
      name = (await client.getProfileFromUserId(partnerId)).displayName ?? name;
    } catch (_) {}
    final stillFriends = friendIds?.contains(partnerId);
    lines.add(switch (stillFriends) {
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
    });
  }
  if (lines.isEmpty) return;

  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      title: Text(lines.length == 1 ? 'Чат закрыт' : 'Чаты закрыты'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < lines.length; i++) ...[
              if (i > 0) const SizedBox(height: 12),
              Text(lines[i]),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Понятно'),
        ),
      ],
    ),
  );
}
