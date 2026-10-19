// SPDX-License-Identifier: AGPL-3.0-or-later

// DVChat: история разговора с Лизой хранится только на этом телефоне, отдельно для каждого пользователя.

import 'dart:convert';

import 'package:dvchat/pages/liza/liza_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LizaStore {
  static const int _maxMessages = 60;

  static String _key(String userId) => 'dv_liza_history_$userId';

  static Future<List<LizaMessage>> load(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key(userId));
      if (raw == null) return [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .map(LizaMessage.fromJson)
          .whereType<LizaMessage>()
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> save(String userId, List<LizaMessage> messages) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final tail = messages.length > _maxMessages
          ? messages.sublist(messages.length - _maxMessages)
          : messages;
      await prefs.setString(
        _key(userId),
        jsonEncode([for (final m in tail) m.toJson()]),
      );
    } catch (_) {}
  }

  static Future<void> clear(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key(userId));
    } catch (_) {}
  }
}
