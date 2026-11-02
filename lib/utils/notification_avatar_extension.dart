// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// DVChat: Подготовка аватара отправителя для показа в уведомлении.

import 'dart:typed_data';

import 'package:dvchat/utils/client_download_content_extension.dart';
import 'package:matrix/matrix.dart';

const notificationAvatarDimension = 128;

extension NotificationAvatarExtension on Client {
  Future<Uint8List?> tryDownloadNotificationAvatar(Uri? avatar) async {
    if (avatar == null) return null;
    try {
      return await downloadMxcCached(
        avatar,
        thumbnailMethod: ThumbnailMethod.crop,
        width: notificationAvatarDimension,
        height: notificationAvatarDimension,
        animated: false,
        isThumbnail: true,
        rounded: true,
      ).timeout(const Duration(seconds: 3));
    } catch (e, s) {
      Logs().e('Unable to get avatar picture', e, s);
      return null;
    }
  }
}
