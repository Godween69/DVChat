// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// DVChat: Показ нижней панели/диалога, подстраивающегося под размер экрана.

import 'dart:math';

import 'package:dvchat/config/app_config.dart';
import 'package:dvchat/config/themes.dart';
import 'package:material_ui/material_ui.dart';

Future<T?> showAdaptiveBottomSheet<T>({
  required BuildContext context,
  required Widget Function(BuildContext) builder,
  bool isDismissible = true,
  bool isScrollControlled = true,
  bool useRootNavigator = true,
}) {
  if (DvThemes.isColumnMode(context)) {
    return showDialog<T>(
      context: context,
      useRootNavigator: useRootNavigator,
      barrierDismissible: isDismissible,
      useSafeArea: true,
      builder: (context) => Center(
        child: Container(
          margin: const EdgeInsets.all(16),
          constraints: const BoxConstraints(maxWidth: 480, maxHeight: 720),
          child: Material(
            elevation: Theme.of(context).dialogTheme.elevation ?? 4,
            shadowColor: Theme.of(context).dialogTheme.shadowColor,
            borderRadius: BorderRadius.circular(AppConfig.borderRadius),
            color: Theme.of(context).scaffoldBackgroundColor,
            clipBehavior: Clip.hardEdge,
            child: builder(context),
          ),
        ),
      ),
    );
  }

  return showModalBottomSheet<T>(
    context: context,
    builder: (context) => ConstrainedBox(
      constraints: BoxConstraints(
        // Не выше видимой области: над клавиатурой остаётся (высота - клавиатура - 32), не больше 600
        maxHeight: min(
          MediaQuery.sizeOf(context).height - 32,
          MediaQuery.viewInsetsOf(context).bottom + 600,
        ),
      ),
      child: builder(context),
    ),
    useSafeArea: true,
    useRootNavigator: useRootNavigator,
    isDismissible: isDismissible,
    isScrollControlled: isScrollControlled,
    clipBehavior: Clip.hardEdge,
  );
}
