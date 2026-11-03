// SPDX-FileCopyrightText: 2026-Present DVB Studio
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// DVChat: подтверждение входа в другие сервисы через DV Auth (github.com/Godween69/DVAuth).
// Сервис показывает на экране QR-код dvchat://auth#<base64url(JSON {"c":"код запроса"})> и число.
// Здесь: прочитать код, показать человеку, куда он входит, спросить число с экрана
// и подтвердить от имени своего аккаунта Matrix (одноразовый токен OpenID).
//
// Безопасность: адрес DV Auth берётся ТОЛЬКО из настроек сборки (DVCHAT_AUTH_URL), а не из QR-кода.
// Иначе чужой QR отправил бы токен OpenID на посторонний сервер.

import 'dart:async';
import 'dart:convert';

import 'package:dvchat/config/app_config.dart';
import 'package:dvchat/pages/new_private_chat/qr_scanner_modal.dart';
import 'package:dvchat/widgets/dv_glass.dart';
import 'package:dvchat/widgets/matrix.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:material_ui/material_ui.dart';

/// Ошибка с понятным человеку текстом.
class DvAuthException implements Exception {
  final String message;
  const DvAuthException(this.message);
  @override
  String toString() => message;
}

/// Разбирает ссылку dvchat://auth#...; возвращает код запроса или null.
String? parseAuthLink(String text) {
  final uri = Uri.tryParse(text.trim());
  if (uri == null ||
      uri.scheme != AppConfig.loginLinkScheme ||
      uri.host != AppConfig.authLinkHost ||
      uri.fragment.isEmpty) {
    return null;
  }
  try {
    final json = jsonDecode(
      utf8.decode(base64Url.decode(base64Url.normalize(uri.fragment))),
    );
    final c = json is Map ? json['c'] : null;
    if (c is String && RegExp(r'^[A-Za-z0-9_-]{8,64}$').hasMatch(c)) return c;
  } catch (_) {}
  return null;
}

/// Что сервис показывает человеку: куда входят, с какого адреса и устройства.
class AuthRequestInfo {
  final String title;
  final String purpose;
  final String ip;
  final String agent;
  const AuthRequestInfo({
    required this.title,
    required this.purpose,
    required this.ip,
    required this.agent,
  });
}

class DvAuth {
  static final Uri? _base = AppConfig.authUrl.isEmpty
      ? null
      : Uri.tryParse(AppConfig.authUrl.replaceAll(RegExp(r'/+$'), ''));

  static bool get configured => _base != null;

  static Uri _url(String path, [Map<String, String>? query]) {
    final b = _base!;
    return b.replace(path: '${b.path}$path', queryParameters: query);
  }

  static Map<String, dynamic> _decode(http.Response r) {
    try {
      final v = jsonDecode(utf8.decode(r.bodyBytes));
      if (v is Map<String, dynamic>) return v;
    } catch (_) {}
    return const {};
  }

  static String _error(http.Response r) {
    final m = _decode(r)['message'];
    if (m is String && m.isNotEmpty) return m;
    return switch (r.statusCode) {
      429 => 'Слишком много попыток. Подождите 15 минут.',
      >= 500 => 'Сервис подтверждения сейчас недоступен',
      _ => 'Не удалось подтвердить вход',
    };
  }

  static Future<AuthRequestInfo> info(String challenge) async {
    final http.Response r;
    try {
      r = await http
          .get(_url('/v1/chat/info', {'challenge': challenge}))
          .timeout(const Duration(seconds: 10));
    } catch (_) {
      throw const DvAuthException('Нет связи с сервисом подтверждения');
    }
    if (r.statusCode != 200) throw DvAuthException(_error(r));
    final j = _decode(r);
    return AuthRequestInfo(
      title: '${j['title'] ?? ''}',
      purpose: '${j['purpose'] ?? ''}',
      ip: '${j['ip'] ?? ''}',
      agent: '${j['agent'] ?? ''}',
    );
  }

  /// Одноразовый токен OpenID от своего сервера Matrix: подтверждает, кто мы.
  static Future<String> _openIdToken(BuildContext context) async {
    final client = Matrix.of(context).client;
    final home = client.homeserver;
    final userId = client.userID;
    final token = client.accessToken;
    if (home == null || userId == null || token == null) {
      throw const DvAuthException('Сначала войдите в аккаунт DVChat');
    }
    final http.Response r;
    try {
      r = await http
          .post(
            home.replace(
              path:
                  '/_matrix/client/v3/user/${Uri.encodeComponent(userId)}/openid/request_token',
            ),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
            body: '{}',
          )
          .timeout(const Duration(seconds: 10));
    } catch (_) {
      throw const DvAuthException('Нет связи с сервером чата');
    }
    final t = _decode(r)['access_token'];
    if (r.statusCode != 200 || t is! String || t.isEmpty) {
      throw const DvAuthException('Сервер чата не выдал подтверждение');
    }
    return t;
  }

  static Future<void> confirm(
    BuildContext context,
    String challenge,
    String number,
  ) async {
    final openid = await _openIdToken(context);
    final http.Response r;
    try {
      r = await http
          .post(
            _url('/v1/chat/confirm'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'challenge': challenge,
              'number': number,
              'openid': openid,
            }),
          )
          .timeout(const Duration(seconds: 10));
    } catch (_) {
      throw const DvAuthException('Нет связи с сервисом подтверждения');
    }
    if (r.statusCode != 200) throw DvAuthException(_error(r));
  }
}

/// Окно ввода числа с экрана входа: фиксированная вёрстка, крупные цифры, ничего не прыгает.
class _NumberDialog extends StatefulWidget {
  const _NumberDialog({required this.title, required this.where});

  final String title;
  final String where;

  @override
  State<_NumberDialog> createState() => _NumberDialogState();
}

class _NumberDialogState extends State<_NumberDialog> {
  final TextEditingController _c = TextEditingController();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _submit() {
    if (_c.text.length == 3) Navigator.of(context).pop(_c.text);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DvGlassDialog(
      title: widget.title,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.where.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: theme.colorScheme.onSurface.withAlpha(18),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                widget.where,
                style: TextStyle(
                  fontSize: 13,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          const SizedBox(height: 14),
          const Text(
            'Если это не вы, нажмите «Отмена». Иначе введите число с экрана входа.',
            style: TextStyle(fontSize: 14),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _c,
            autofocus: true,
            autocorrect: false,
            enableSuggestions: false,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            maxLength: 3,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: const TextStyle(
              fontSize: 34,
              fontWeight: FontWeight.w600,
              letterSpacing: 10,
            ),
            decoration: const InputDecoration(
              counterText: '',
              hintText: '000',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: _c.text.length == 3 ? _submit : null,
          child: const Text('Подтвердить'),
        ),
      ],
    );
  }
}

/// Полный путь: ссылка → «куда входите?» → число с экрана → подтверждение.
Future<void> confirmAuthLink(BuildContext context, String link) async {
  final messenger = ScaffoldMessenger.of(context);
  void say(String text) =>
      messenger.showSnackBar(SnackBar(content: Text(text)));

  if (!DvAuth.configured) {
    say('В этой сборке подтверждение входа не настроено (DVCHAT_AUTH_URL)');
    return;
  }
  final challenge = parseAuthLink(link);
  if (challenge == null) {
    say('Это не код подтверждения входа');
    return;
  }
  try {
    final info = await DvAuth.info(challenge);
    if (!context.mounted) return;
    final what = info.purpose == 'link'
        ? 'Привязать этот аккаунт чата к «${info.title}»?'
        : 'Вход в «${info.title}»';
    final where = [
      if (info.ip.isNotEmpty) 'Адрес: ${info.ip}',
      if (info.agent.isNotEmpty) info.agent,
    ].join('\n');
    final number = await showDialog<String>(
      context: context,
      builder: (_) => _NumberDialog(title: what, where: where),
    );
    if (number == null || number.trim().isEmpty) return;
    if (!context.mounted) return;
    await DvAuth.confirm(context, challenge, number.trim());
    say('Готово, вход подтверждён');
  } on DvAuthException catch (e) {
    say(e.message);
  } catch (e) {
    // Подробности не показываем и не пишем: в них может быть адрес запроса
    debugPrint('DV Auth: непредвиденная ошибка');
    say('Не удалось подтвердить вход');
  }
}

/// Открывает сканер QR и подтверждает вход по прочитанному коду.
Future<void> scanAndConfirmAuth(BuildContext context) async {
  await Navigator.of(context).push(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => QrScannerModal(
        onScan: (code) {
          // Сканер закрывается сам до вызова onScan
          if (!context.mounted) return;
          unawaited(confirmAuthLink(context, code));
        },
      ),
    ),
  );
}

/// Ссылка dvchat://auth#..., пришедшая от системы, ждёт, пока её заберёт список чатов.
class PendingAuthLink {
  static final ValueNotifier<({String link, DateTime at})?> notifier =
      ValueNotifier(null);

  static void set(String link) =>
      notifier.value = (link: link, at: DateTime.now());

  /// Отдаёт ссылку один раз; старше минуты считается устаревшей.
  static String? take() {
    final v = notifier.value;
    if (v == null) return null;
    notifier.value = null;
    if (DateTime.now().difference(v.at) > const Duration(minutes: 1)) {
      return null;
    }
    return v.link;
  }
}
