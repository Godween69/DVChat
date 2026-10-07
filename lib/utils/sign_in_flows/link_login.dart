// DVChat: вход по ссылке dvchat://login#<base64url(JSON {"u":..,"p":..})>
// Источники ссылки: буфер обмена, QR-код (системный intent добавим позже)

import 'dart:async';
import 'dart:convert';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/pages/new_private_chat/qr_scanner_modal.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

class LoginLinkData {
  final String username;
  final String password;
  const LoginLinkData({required this.username, required this.password});
}

/// Разбирает строку-ссылку. Возвращает null, если формат неверный.
LoginLinkData? parseLoginLink(String raw) {
  final uri = Uri.tryParse(raw.trim());
  if (uri == null) return null;
  if (uri.scheme != AppConfig.loginLinkScheme ||
      uri.host != AppConfig.loginLinkHost) {
    return null;
  }
  if (uri.fragment.isEmpty) return null;
  try {
    // normalize дописывает недостающие "=" в конце base64
    final bytes = base64Url.decode(base64Url.normalize(uri.fragment));
    final json = jsonDecode(utf8.decode(bytes));
    if (json is! Map) return null;
    final u = json['u'];
    final p = json['p'];
    if (u is! String || p is! String || u.isEmpty || p.isEmpty) return null;
    return LoginLinkData(username: u, password: p);
  } catch (_) {
    return null;
  }
}

/// Логинится на наш сервер по данным из ссылки и открывает чаты.
Future<void> loginByLink(BuildContext context, String raw) async {
  final data = parseLoginLink(raw);
  if (data == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Некорректная ссылка для входа')),
    );
    return;
  }
  final matrix = Matrix.of(context);
  final result = await showFutureLoadingDialog(
    context: context,
    future: () async {
      final client = await matrix.getLoginClient();
      // Сервер всегда наш, чужие адреса игнорируются
      await client.checkHomeserver(Uri.https(AppConfig.defaultHomeserver, ''));
      await client.login(
        LoginType.mLoginPassword,
        identifier: AuthenticationUserIdentifier(user: data.username),
        password: data.password,
        initialDeviceDisplayName: PlatformInfos.appDisplayName,
      );
    },
  );
  // Ошибку (неверный пароль, нет сети) диалог показывает сам
  if (result.error == null && context.mounted) context.go('/backup');
}

/// Читает ссылку из буфера обмена и логинится.
Future<void> pasteAndLogin(BuildContext context) async {
  final data = await Clipboard.getData(Clipboard.kTextPlain);
  if (!context.mounted) return;
  final text = data?.text ?? '';
  await loginByLink(context, text);
  // Пароль не должен оставаться в буфере обмена после входа
  if (parseLoginLink(text) != null) {
    await Clipboard.setData(const ClipboardData(text: ''));
  }
}

/// Открывает сканер QR, строку из кода отдаёт в loginByLink.
Future<void> scanAndLogin(BuildContext context) async {
  await Navigator.of(context).push(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => QrScannerModal(
        onScan: (code) {
          // Сканер закрывается сам до вызова onScan, контекст страницы жив
          if (!context.mounted) return;
          unawaited(loginByLink(context, code));
        },
      ),
    ),
  );
}
