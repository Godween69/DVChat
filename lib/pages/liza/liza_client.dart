// SPDX-License-Identifier: AGPL-3.0-or-later

// DVChat: запросы вкладки «Лиза» к серверу DVChat (проверка доступа, ответ потоком).
// Ключ доступа к ИИ хранится только на сервере; приложение передаёт свой токен Matrix.

import 'dart:async';
import 'dart:convert';

import 'package:dvchat/config/app_config.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';

class LizaMessage {
  final String text;
  final bool isUser;
  const LizaMessage({required this.text, required this.isUser});

  Map<String, Object?> toJson() => {'t': text, 'u': isUser};

  static LizaMessage? fromJson(Object? json) {
    if (json is! Map) return null;
    final text = json['t'];
    final isUser = json['u'];
    if (text is! String || isUser is! bool) return null;
    return LizaMessage(text: text, isUser: isUser);
  }
}

enum LizaAccess { ok, closed, error }

class LizaStatus {
  final LizaAccess access;
  final int used;
  final int? limit;
  final bool admin;
  final int? tokens;
  const LizaStatus(
    this.access, {
    this.used = 0,
    this.limit,
    this.admin = false,
    this.tokens,
  });
}

/// Кусочек ответа: текст, конец ответа или ошибка
class LizaChunk {
  final String? delta;
  final bool done;
  final String? error;
  final int? used;
  final int? limit;
  final int? tokens;
  const LizaChunk._({
    this.delta,
    this.done = false,
    this.error,
    this.used,
    this.limit,
    this.tokens,
  });
  const LizaChunk.text(String text) : this._(delta: text);
  const LizaChunk.finished({int? used, int? limit, int? tokens})
    : this._(done: true, used: used, limit: limit, tokens: tokens);
  const LizaChunk.failed(String message) : this._(error: message);
}

class LizaClient {
  final Client client;
  const LizaClient(this.client);

  Uri _uri(String path) =>
      Uri.https(AppConfig.defaultHomeserver, '/lisa/v1/$path');

  Map<String, String> get _headers => {
    'Authorization': 'Bearer ${client.accessToken}',
    'Content-Type': 'application/json',
  };

  /// Спрашиваем сервер: можно ли мне пользоваться Лизой
  Future<LizaStatus> status() async {
    if (client.accessToken == null) return const LizaStatus(LizaAccess.error);
    try {
      final response = await http
          .get(_uri('status'), headers: _headers)
          .timeout(const Duration(seconds: 15));
      if (response.statusCode == 403) {
        return const LizaStatus(LizaAccess.closed);
      }
      if (response.statusCode != 200) {
        return const LizaStatus(LizaAccess.error);
      }
      final json = jsonDecode(utf8.decode(response.bodyBytes));
      if (json is! Map) return const LizaStatus(LizaAccess.error);
      return LizaStatus(
        LizaAccess.ok,
        used: (json['used'] as num?)?.toInt() ?? 0,
        limit: (json['limit'] as num?)?.toInt(),
        admin: json['admin'] == true,
        tokens: (json['tokens'] as num?)?.toInt(),
      );
    } catch (_) {
      return const LizaStatus(LizaAccess.error);
    }
  }

  /// Отправляет историю и отдаёт ответ по кусочкам
  Stream<LizaChunk> chat(List<LizaMessage> history) async* {
    final httpClient = http.Client();
    try {
      final request = http.Request('POST', _uri('chat'));
      request.headers.addAll(_headers);
      request.body = jsonEncode({
        'messages': [
          for (final m in history)
            {'role': m.isUser ? 'user' : 'assistant', 'content': m.text},
        ],
      });
      final response = await httpClient
          .send(request)
          .timeout(const Duration(seconds: 60));
      if (response.statusCode != 200) {
        final body = await response.stream.bytesToString();
        var message = 'Сеть сейчас перегружена. Попробуйте позже.';
        try {
          final json = jsonDecode(body);
          if (json is Map && json['message'] is String) {
            message = json['message'] as String;
          }
        } catch (_) {}
        yield LizaChunk.failed(message);
        return;
      }
      await for (final line
          in response.stream
              .transform(utf8.decoder)
              .transform(const LineSplitter())) {
        if (!line.startsWith('data:')) continue;
        Object? json;
        try {
          json = jsonDecode(line.substring(5).trim());
        } catch (_) {
          continue;
        }
        if (json is! Map) continue;
        if (json['d'] is String) {
          yield LizaChunk.text(json['d'] as String);
        } else if (json['done'] == true) {
          yield LizaChunk.finished(
            used: (json['used'] as num?)?.toInt(),
            limit: (json['limit'] as num?)?.toInt(),
            tokens: (json['tok'] as num?)?.toInt(),
          );
        } else if (json['error'] != null) {
          yield LizaChunk.failed(
            json['message']?.toString() ??
                'Сеть сейчас перегружена. Попробуйте позже.',
          );
        }
      }
    } on TimeoutException {
      yield const LizaChunk.failed(
        'Сеть сейчас перегружена. Попробуйте позже.',
      );
    } catch (_) {
      yield const LizaChunk.failed('Нет связи с Лизой');
    } finally {
      httpClient.close();
    }
  }
}
