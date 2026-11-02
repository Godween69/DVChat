// SPDX-License-Identifier: AGPL-3.0-or-later

// DVChat: повторная отправка сообщений. Не ушедшее сообщение (в том числе голосовое)
// остаётся в чате с красной меткой, пока его не отправят или не удалят. Нажатие на метку
// открывает меню «Отправить снова / Удалить», а при появлении связи все такие сообщения
// уходят сами, по порядку.

import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

class DvResend {
  static bool _attached = false;
  static bool _running = false;
  static StreamSubscription<SyncStatusUpdate>? _sub;

  /// Сразу после запуска тоже проверяем зависшие сообщения
  static bool _needCheck = true;

  /// Следит за связью. Вызывается один раз за сеанс.
  static void attach(Client client) {
    if (_attached) return;
    _attached = true;
    _sub = client.onSyncStatus.stream.listen((update) {
      if (update.status == SyncStatus.error) {
        _needCheck = true;
      } else if (update.status == SyncStatus.finished && _needCheck) {
        _needCheck = false;
        unawaited(retryAll(client));
      }
    });
  }

  /// Перестаёт следить за связью (при выходе из аккаунта)
  static Future<void> detach() async {
    await _sub?.cancel();
    _sub = null;
    _attached = false;
  }

  /// Отправляет заново всё, что не ушло, от старых сообщений к новым
  static Future<void> retryAll(Client client) async {
    if (_running) return;
    _running = true;
    try {
      await Future<void>.delayed(const Duration(seconds: 2));
      for (final room in client.rooms) {
        if (room.membership != Membership.join) continue;
        if (room.lastEvent?.status.isError != true) continue;
        final timeline = await room.getTimeline(limit: 40);
        final failed = timeline.events
            .where((e) => e.status.isError && e.senderId == client.userID)
            .toList()
            .reversed
            .toList();
        timeline.cancelSubscriptions();
        for (final event in failed) {
          await retry(event);
        }
      }
    } catch (e) {
      Logs().v('DVChat: автоповтор отправки не удался', e);
    } finally {
      _running = false;
    }
  }

  /// Повторяет отправку одного сообщения. Если задан context, о неудаче скажет сообщением.
  static Future<bool> retry(Event event, {BuildContext? context}) async {
    var problem = 'Не удалось отправить. Проверьте связь и повторите.';
    try {
      await event.sendAgain();
      return true;
    } on FileNoLongerInCacheException {
      problem = 'Файл уже не хранится на телефоне. Отправьте его заново.';
    } catch (e) {
      Logs().v('DVChat: повтор отправки не удался', e);
    }
    if (context != null && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(problem)));
    }
    return false;
  }

  /// Меню у не ушедшего сообщения
  static Future<void> sheet(BuildContext context, Event event) async {
    final error = Theme.of(context).colorScheme.error;
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              title: Text(
                'Сообщение не отправлено',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text(
                'Оно останется здесь, пока вы его не отправите или не удалите.',
              ),
            ),
            ListTile(
              leading: const Icon(Icons.refresh),
              title: const Text('Отправить снова'),
              onTap: () => Navigator.pop(context, 'again'),
            ),
            ListTile(
              leading: Icon(Icons.delete_outline, color: error),
              title: Text('Удалить', style: TextStyle(color: error)),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (action == null || !context.mounted) return;
    if (action == 'again') {
      await retry(event, context: context);
    } else if (action == 'delete') {
      try {
        await event.cancelSend();
      } catch (e) {
        Logs().v('DVChat: не удалось удалить неотправленное', e);
      }
    }
  }
}
