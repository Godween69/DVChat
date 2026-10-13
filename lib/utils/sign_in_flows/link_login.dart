// DVChat: вход по ссылке dvchat://login#<base64url(JSON {"u":..,"p":..,"k":..})>
// Источники ссылки: буфер обмена, QR-код, системная ссылка (intent)

import 'dart:async';
import 'dart:convert';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/pages/new_private_chat/qr_scanner_modal.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/utils/sign_in_flows/crypto_autosetup.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_text_input_dialog.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

class LoginLinkData {
  final String username;
  final String password;
  // Кодовая фраза шифрования из поля k (может отсутствовать)
  final String? cryptoPassphrase;
  // Одноразовый код (новый формат ссылки): данные для входа выдаёт сервер
  final String? code;
  const LoginLinkData({
    this.username = '',
    this.password = '',
    this.cryptoPassphrase,
    this.code,
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
    // Новый формат: в ссылке только одноразовый код, остальное выдаёт сервер
    final c = json['c'];
    if (c is String && c.isNotEmpty) return LoginLinkData(code: c);
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

/// Логинится на наш сервер по данным из ссылки, открывает чаты,
/// шифрование настраивает в фоне.
Future<void> loginByLink(BuildContext context, String raw) async {
  final parsed = parseLoginLink(raw);
  if (parsed == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Некорректная ссылка для входа')),
    );
    return;
  }
  // Ссылка с кодом: данные для входа получаем у сервера (код одноразовый)
  final code = parsed.code;
  final data = code == null ? parsed : await _redeemLoginCode(context, code);
  if (data == null || !context.mounted) return;
  final matrix = Matrix.of(context);
  // Пароль нужен серверу при первой настройке шифрования (запрос UIA)
  matrix.cachedPassword = data.password;
  Client? loggedClient;
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
      loggedClient = client;
    },
  );
  // Ошибку (неверный пароль, нет сети) диалог показывает сам
  if (result.error != null) {
    matrix.cachedPassword = null;
    return;
  }
  final client = loggedClient;
  final phrase = data.cryptoPassphrase;
  if (client != null && phrase != null) {
    // Шифрование настраивается в фоне, пароль забываем по завершении
    unawaited(
      setupCryptoSilently(
        client,
        phrase,
      ).whenComplete(() => matrix.cachedPassword = null),
    );
  } else {
    matrix.cachedPassword = null;
  }
  if (context.mounted) context.go('/rooms');
}

void _showLoginError(BuildContext context, String text) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
}

/// Меняет одноразовый код из ссылки на данные входа. Если человек уже входил раньше,
/// сервер просит ID: спрашиваем его в диалоге (до 6 попыток). Пока ID не введён верно,
/// код не расходуется.
Future<LoginLinkData?> _redeemLoginCode(
  BuildContext context,
  String code,
) async {
  String? dvId;
  for (var attempt = 0; attempt < 6; attempt++) {
    final body = <String, String>{'code': code};
    if (dvId != null) body['dv_id'] = dvId;
    final http.Response response;
    try {
      response = await http
          .post(
            Uri.https(AppConfig.defaultHomeserver, '/_synapse/client/dv/login'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 20));
    } catch (_) {
      if (context.mounted) _showLoginError(context, 'Нет связи с сервером');
      return null;
    }
    var json = <String, Object?>{};
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map<String, Object?>) json = decoded;
    } catch (_) {}

    if (response.statusCode == 200) {
      final u = json['u'];
      final p = json['p'];
      final k = json['k'];
      if (u is String && p is String && u.isNotEmpty && p.isNotEmpty) {
        return LoginLinkData(
          username: u,
          password: p,
          cryptoPassphrase: k is String && k.isNotEmpty ? k : null,
        );
      }
      if (context.mounted) {
        _showLoginError(context, 'Сервер вернул неполные данные для входа');
      }
      return null;
    }

    final err = json['errcode'];
    if (err == 'DV_NEED_ID' || err == 'DV_BAD_ID') {
      if (!context.mounted) return null;
      final input = await showTextInputDialog(
        context: context,
        title: 'Введите ваш ID',
        message: err == 'DV_BAD_ID'
            ? 'ID неверный, попробуйте ещё раз'
            : 'Для входа с нового устройства нужен ваш ID из профиля',
        okLabel: 'Войти',
        cancelLabel: 'Отмена',
        keyboardType: TextInputType.number,
        maxLength: 10,
        validator: (value) => RegExp(r'^\d{10}$').hasMatch(value.trim())
            ? null
            : 'ID состоит из 10 цифр',
      );
      if (input == null) return null;
      dvId = input.trim();
      continue;
    }
    if (context.mounted) {
      _showLoginError(
        context,
        err == 'M_LIMIT_EXCEEDED'
            ? 'Слишком часто, подождите минуту'
            : 'Ссылка недействительна или уже использована',
      );
    }
    return null;
  }
  if (context.mounted) _showLoginError(context, 'Слишком много попыток');
  return null;
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

/// Остаток прежней схемы (страница /backup): удалим вместе со страницей.
class PendingCryptoPassphrase {
  static String? take() => null;
}
