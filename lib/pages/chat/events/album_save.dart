// SPDX-License-Identifier: AGPL-3.0-or-later

// DVChat: «Сохранить все» для альбома. Кнопка живёт в просмотре альбома (не под альбомом в чате).

import 'package:dvchat/utils/matrix_sdk_extensions/matrix_file_extension.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

/// Сохраняет все фото альбома в галерею (на Android в папку DVChat, без лишних вопросов),
/// показывает ход («Сохраняю 3 из 15…») и итог.
Future<void> dvSaveAlbum(BuildContext context, List<Event> items) async {
  final messenger = ScaffoldMessenger.of(context);
  final android = !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  var ok = 0;
  for (var k = 0; k < items.length; k++) {
    messenger
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text('Сохраняю все фото: ${k + 1} из ${items.length}…'),
          duration: const Duration(minutes: 5),
        ),
      );
    try {
      final file = await items[k].downloadAndDecryptAttachment();
      if (android) {
        if (await file.saveToGalleryQuiet()) ok++;
      } else {
        if (!context.mounted) break;
        await file.save(context);
        ok++;
      }
    } catch (e, s) {
      Logs().w('Альбом: не удалось сохранить фото', e, s);
    }
  }
  messenger
    ..clearSnackBars()
    ..showSnackBar(
      SnackBar(
        content: Text(
          ok == items.length
              ? 'Сохранено фото: $ok'
              : 'Сохранено $ok из ${items.length}',
        ),
        showCloseIcon: true,
      ),
    );
}
