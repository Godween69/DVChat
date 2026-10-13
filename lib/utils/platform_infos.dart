// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// DVChat: Сведения о платформе (Android/web), версии приложения и ссылки на «О приложении».

import 'dart:io';

import 'package:dvchat/config/setting_keys.dart';
import 'package:dvchat/l10n/l10n.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher_string.dart';

import '../config/app_config.dart';

abstract class PlatformInfos {
  static bool get isWeb => kIsWeb;
  static bool get isAndroid => !kIsWeb && Platform.isAndroid;

  /// Приложение для телефона — только Android (iPhone работает через web-версию)
  static bool get isMobile => isAndroid;

  static bool get usesTouchscreen => !isMobile;

  static bool get supportsCustomImageResizer =>
      PlatformInfos.isWeb || PlatformInfos.isMobile;

  /// Web could also record in theory but currently creates broken opus
  static bool get platformCanRecord => isMobile;

  static bool get supportsAppLock => isMobile;

  static String get appDisplayName =>
      '${AppSettings.applicationName.value} ${isWeb ? 'web' : Platform.operatingSystem}${kReleaseMode ? '' : 'Debug'}';

  static Future<String> getVersion() async {
    var version = kIsWeb ? 'Web' : 'Unknown';
    try {
      version = (await PackageInfo.fromPlatform()).version;
    } catch (_) {}
    return version;
  }

  static Future<void> showDialog(BuildContext context) async {
    final l10n = L10n.of(context);
    final version = await PlatformInfos.getVersion();
    if (!context.mounted) return;
    showAboutDialog(
      context: context,
      children: [
        Text(l10n.versionWithNumber(version)),
        TextButton.icon(
          onPressed: () => launchUrlString(AppConfig.sourceCodeUrl),
          icon: const Icon(Icons.source_outlined),
          label: Text(l10n.sourceCode),
        ),
      ],
      applicationIcon: ClipRRect(
        borderRadius: BorderRadius.circular(64),
        child: Image.asset(
          './assets/logo/mini/logo_mini.png',
          width: 64,
          height: 64,
        ),
      ),
      applicationName: AppSettings.applicationName.value,
    );
  }
}
