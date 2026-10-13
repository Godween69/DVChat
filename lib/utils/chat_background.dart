// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:ui';

import 'package:dvchat/config/setting_keys.dart';

/// DVChat: выбранный пользователем цвет фона чата (null — по умолчанию).
Color? get dvChatBackground {
  final value = AppSettings.chatBackgroundColorInt.value;
  return value == 0 ? null : Color(value);
}
