// SPDX-License-Identifier: AGPL-3.0-or-later

// DVChat: профили друзей заранее, чтобы при открытии профиля не мигала буква вместо фото.

import 'dart:async';

import 'package:dvchat/widgets/avatar.dart';
import 'package:dvchat/widgets/mxc_image.dart';
import 'package:matrix/matrix.dart';

class DvProfileCache {
  static final Map<String, Profile> data = {};

  /// Размеры аватара, которые показываются в списке и на странице профиля
  static const List<double> _sizes = [Avatar.defaultSize, Avatar.defaultSize * 3.8];

  /// Запоминает профиль и в фоне скачивает фото в нужных размерах
  static void remember(
    Client client,
    String userId,
    Profile profile,
    double devicePixelRatio,
  ) {
    data[userId] = profile;
    final uri = profile.avatarUrl;
    if (uri == null || uri.toString().isEmpty) return;
    for (final size in _sizes) {
      unawaited(MxcImage.prefetch(client, uri, size, devicePixelRatio));
    }
  }
}
