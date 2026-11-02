// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// DVChat: Передача текста и ссылок (приглашение, ID) в другие приложения через системное меню.

import 'package:dvchat/l10n/l10n.dart';
import 'package:dvchat/utils/platform_infos.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:share_plus/share_plus.dart';

abstract class DvShare {
  static Future<void> share(
    String text,
    BuildContext context, {
    bool copyOnly = false,
  }) async {
    final l10n = L10n.of(context);
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    if (PlatformInfos.isMobile && !copyOnly) {
      final box = context.findRenderObject() as RenderBox;
      await SharePlus.instance.share(
        ShareParams(
          text: text,
          sharePositionOrigin: box.localToGlobal(Offset.zero) & box.size,
        ),
      );
      return;
    }
    await Clipboard.setData(ClipboardData(text: text));
    if (!PlatformInfos.isMobile) {
      scaffoldMessenger.showSnackBar(
        SnackBar(showCloseIcon: true, content: Text(l10n.copiedToClipboard)),
      );
    }
    return;
  }
}
