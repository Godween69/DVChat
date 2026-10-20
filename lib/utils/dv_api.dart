// DVChat: запросы к модулю dv_social на сервере (ID, друзья, заявки)

import 'dart:convert';

import 'package:dvchat/config/app_config.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';

/// Ошибка ответа модуля: код (например DV_NOT_FOUND) и текст для человека
class DvApiException implements Exception {
  final int status;
  final String errcode;
  final String message;
  const DvApiException(this.status, this.errcode, this.message);

  @override
  String toString() => message;
}

class DvApi {
  final Client client;

  /// Какой модуль сервера: dv (друзья, профили) или dvs (сторис)
  final String prefix;
  const DvApi(this.client, {this.prefix = 'dv'});

  /// ID не меняется, поэтому хранится в памяти после первого запроса
  static final Map<String, String> _idCache = {};

  Uri _uri(String path) =>
      Uri.https(AppConfig.defaultHomeserver, '/_synapse/client/$prefix/$path');

  Map<String, String> get _headers => {
    'Authorization': 'Bearer ${client.accessToken}',
    'Content-Type': 'application/json',
  };

  /// При холодном старте токен появляется не сразу: ждём его до 15 секунд
  Future<void> _ready() async {
    for (var i = 0; i < 75 && client.accessToken == null; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
  }

  /// Отправка с ожиданием токена и одним повтором, если сервер ответил 401
  Future<http.Response> _send(Future<http.Response> Function() request) async {
    await _ready();
    var response = await request();
    if (response.statusCode == 401) {
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      await _ready();
      response = await request();
    }
    return response;
  }

  Map<String, Object?> _check(http.Response response) {
    var json = <String, Object?>{};
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map<String, Object?>) json = decoded;
    } catch (_) {}
    if (response.statusCode >= 400) {
      throw DvApiException(
        response.statusCode,
        json['errcode']?.toString() ?? '',
        json['error']?.toString() ?? 'Ошибка ${response.statusCode}',
      );
    }
    return json;
  }

  Future<Map<String, Object?>> get(String path) async {
    final response = await _send(
      () => http
          .get(_uri(path), headers: _headers)
          .timeout(const Duration(seconds: 20)),
    );
    return _check(response);
  }

  Future<Map<String, Object?>> post(
    String path,
    Map<String, Object?> body,
  ) async {
    final response = await _send(
      () => http
          .post(_uri(path), headers: _headers, body: jsonEncode(body))
          .timeout(const Duration(seconds: 20)),
    );
    return _check(response);
  }

  /// Сохранённый ID без запроса (null, если ещё не загружали)
  static String? cachedId(Client client) => _idCache[client.userID ?? ''];

  /// Мой ID (10 цифр)
  Future<String> myId() async {
    final userId = client.userID ?? '';
    final cached = _idCache[userId];
    if (cached != null) return cached;
    final json = await get('me');
    final id = json['dv_id'];
    if (id is! String) {
      throw const DvApiException(500, '', 'Сервер не вернул ID');
    }
    _idCache[userId] = id;
    return id;
  }
}

/// Содержимое QR-кода «Мой код»
String dvAddLink(String dvId) => '${AppConfig.loginLinkScheme}://add/$dvId';
