// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// DVChat: Поведение прокрутки: перетаскивание списков мышью и пальцем одинаково (нужно вебу).

import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';

class CustomScrollBehavior extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => {
    PointerDeviceKind.touch,
    PointerDeviceKind.trackpad,
  };
}
