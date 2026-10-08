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
  // Кодовая фраза шифрования из поля k (может отсутствовать)
  final String? cryptoPassphrase;
  const LoginLinkData({
    required this.username,
    required this.password,
    this.cryptoPassphrase,
  });
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
    final k = json['k'];
    return LoginLinkData(
      username: u,
      password: p,
      cryptoPassphrase: k is String && k.isNotEmpty ? k : null,
    );
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
  // Фразу кладём в память ДО входа: после входа роутер сам откроет /backup
  final phrase = data.cryptoPassphrase;
  if (phrase != null) PendingCryptoPassphrase.set(phrase);
  // Пароль нужен серверу при первой настройке шифрования (запрос UIA)
  matrix.cachedPassword = data.password;
  Timer(const Duration(minutes: 2), () => matrix.cachedPassword = null);
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
  if (result.error != null) {
    PendingCryptoPassphrase.clear();
    matrix.cachedPassword = null;
  }
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

/// Ссылка, пришедшая от системы (dvchat://...), ждёт, пока стартовый экран её заберёт.
/// Хранится с временем получения: старше 30 секунд считается устаревшей.
class PendingLoginLink {
  static final ValueNotifier<({String link, DateTime at})?> notifier =
      ValueNotifier(null);

  static void set(String link) =>
      notifier.value = (link: link, at: DateTime.now());

  /// Отдаёт ссылку один раз и очищает хранилище.
  static String? take() {
    final value = notifier.value;
    if (value == null) return null;
    notifier.value = null;
    if (DateTime.now().difference(value.at) > const Duration(seconds: 30)) {
      return null;
    }
    return value.link;
  }
}

/// Кодовая фраза шифрования из ссылки входа. Живёт только в памяти и
/// отдаётся один раз экрану /backup, который сам настраивает шифрование.
class PendingCryptoPassphrase {
  static String? _value;
  static DateTime? _at;

  static void set(String value) {
    _value = value;
    _at = DateTime.now();
  }

  static void clear() {
    _value = null;
    _at = null;
  }

  /// Отдаёт фразу один раз и очищает хранилище. Старше 2 минут считается устаревшей.
  static String? take() {
    final value = _value;
    final at = _at;
    clear();
    if (value == null || at == null) return null;
    if (DateTime.now().difference(at) > const Duration(minutes: 2)) return null;
    return value;
  }
}
