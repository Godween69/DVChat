// SPDX-License-Identifier: AGPL-3.0-or-later

// DVChat: разговоры с Лизой хранятся только на этом телефоне, отдельно для каждого пользователя.
// Сервер переписку не сохраняет.

import 'dart:convert';

import 'package:dvchat/pages/liza/liza_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Один разговор: название берётся из первого вопроса
class LizaConversation {
  LizaConversation({
    required this.id,
    this.title = '',
    int? updated,
    List<LizaMessage>? messages,
  }) : updated = updated ?? DateTime.now().millisecondsSinceEpoch,
       messages = messages ?? [];

  /// Новый пустой разговор (в историю попадает после первого вопроса)
  factory LizaConversation.fresh() =>
      LizaConversation(id: DateTime.now().microsecondsSinceEpoch.toString());

  final String id;
  String title;
  int updated;
  List<LizaMessage> messages;

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'updated': updated,
    'messages': [for (final m in messages) m.toJson()],
  };

  static LizaConversation? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    if (id is! String) return null;
    final raw = json['messages'];
    final messages = raw is List
        ? raw.map(LizaMessage.fromJson).whereType<LizaMessage>().toList()
        : <LizaMessage>[];
    return LizaConversation(
      id: id,
      title: json['title'] is String ? json['title'] as String : '',
      updated: (json['updated'] as num?)?.toInt(),
      messages: messages,
    );
  }
}

class LizaStore {
  static const int maxChats = 40;
  static const int maxMessages = 60;

  static String _key(String userId) => 'dv_liza_chats_$userId';

  /// Прежний ключ: до истории хранился один-единственный разговор
  static String _oldKey(String userId) => 'dv_liza_history_$userId';

  /// Название разговора: первый вопрос, одной строкой и не длиннее 48 знаков
  static String titleOf(List<LizaMessage> messages) {
    final first = messages.where((m) => m.isUser).firstOrNull;
    final text = (first?.text ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
    if (text.isEmpty) return 'Без названия';
    return text.length <= 48 ? text : '${text.substring(0, 47)}…';
  }

  /// Все разговоры, свежие первыми. Старую единственную переписку переносим в первый разговор.
  static Future<List<LizaConversation>> loadAll(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key(userId));
      if (raw != null) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          final list = decoded
              .map(LizaConversation.fromJson)
              .whereType<LizaConversation>()
              .toList();
          list.sort((a, b) => b.updated.compareTo(a.updated));
          return list;
        }
      }
      final old = prefs.getString(_oldKey(userId));
      if (old != null) {
        final decoded = jsonDecode(old);
        if (decoded is List) {
          final messages = decoded
              .map(LizaMessage.fromJson)
              .whereType<LizaMessage>()
              .toList();
          if (messages.isNotEmpty) {
            final chat = LizaConversation.fresh();
            chat.messages = messages;
            chat.title = titleOf(messages);
            await saveAll(userId, [chat]);
            await prefs.remove(_oldKey(userId));
            return [chat];
          }
        }
      }
    } catch (_) {}
    return [];
  }

  static Future<void> saveAll(
    String userId,
    List<LizaConversation> chats,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final sorted = List.of(chats)
        ..sort((a, b) => b.updated.compareTo(a.updated));
      final kept = sorted.length > maxChats
          ? sorted.sublist(0, maxChats)
          : sorted;
      await prefs.setString(
        _key(userId),
        jsonEncode([for (final c in kept) c.toJson()]),
      );
    } catch (_) {}
  }

  static Future<void> clear(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key(userId));
      await prefs.remove(_oldKey(userId));
    } catch (_) {}
  }
}
