// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// DVChat: Показ локальных уведомлений, пока приложение открыто или работает в фоне.

import 'package:dvchat/config/setting_keys.dart';
import 'package:dvchat/l10n/l10n.dart';
import 'package:dvchat/utils/client_download_content_extension.dart';
import 'package:dvchat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:dvchat/widgets/matrix.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:universal_html/html.dart' as html;

extension LocalNotificationsExtension on MatrixState {
  static final html.AudioElement _audioPlayer = html.AudioElement()
    ..src = 'assets/assets/sounds/notification.mp3'
    ..load();

  Future<void> showLocalNotification(Event event) async {
    final roomId = event.room.id;
    if (activeRoomId == roomId) {
      if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        return;
      }
    }

    final title = event.room.getLocalizedDisplayname(
      MatrixLocals(L10n.of(context)),
    );
    final body = await event.calcLocalizedBody(
      MatrixLocals(L10n.of(context)),
      withSenderNamePrefix:
          !event.room.isDirectChat ||
          event.room.lastEvent?.senderId == client.userID,
      plaintextBody: true,
      hideReply: true,
      hideEdit: true,
      removeMarkdown: true,
    );
    final avatarUrl = event.room.avatar;

    const size = 128;
    const thumbnailMethod = ThumbnailMethod.crop;

    if (avatarUrl != null) {
      // Pre-cache so that we can later just set the thumbnail uri as icon:
      try {
        await client.downloadMxcCached(
          avatarUrl,
          width: size,
          height: size,
          thumbnailMethod: thumbnailMethod,
          isThumbnail: true,
          rounded: true,
        );
      } catch (e, s) {
        Logs().d('Unable to pre-download avatar for web notification', e, s);
      }
    }

    if (kIsWeb) {
      final thumbnailUri = await avatarUrl?.getThumbnailUri(
        client,
        width: size,
        height: size,
        method: thumbnailMethod,
      );

      if (AppSettings.webNotificationSound.value) _audioPlayer.play();

      html.Notification(
        title,
        body: body,
        icon: thumbnailUri?.toString(),
        tag: event.room.id,
      );
      return;
    }
  }
}
