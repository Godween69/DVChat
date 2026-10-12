// DVChat: проверка обновлений. Приложение сверяется с version.json на нашем сервере
// (автоматически не чаще раза в час, по кнопке в настройках сразу) и предлагает
// скачать новую версию.

import 'dart:convert';
import 'dart:io';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

abstract class DvUpdateChecker {
  static const String _lastCheckKey =
      'online.dvbstudio.dvchat.update_checked_at';
  static const Duration _interval = Duration(hours: 1);
  static bool _checking = false;

  static void _say(BuildContext context, String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  /// [manual]: проверка по кнопке, без ограничения по времени и с сообщением о результате.
  static Future<void> check(BuildContext context, {bool manual = false}) async {
    if (!Platform.isAndroid) return;
    if (_checking) {
      if (manual) _say(context, 'Проверка уже идёт');
      return;
    }
    if (AppConfig.updateBaseUrl.isEmpty) {
      if (manual) _say(context, 'В этой сборке не задан адрес обновлений');
      return;
    }
    final store = Matrix.of(context).store;
    final now = DateTime.now().millisecondsSinceEpoch;
    final last = store.getInt(_lastCheckKey) ?? 0;
    if (!manual && now - last < _interval.inMilliseconds) return;
    _checking = true;
    final http = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await http.getUrl(
        Uri.parse('${AppConfig.updateBaseUrl}version.json'),
      );
      final response = await request.close().timeout(
        const Duration(seconds: 15),
      );
      if (response.statusCode != 200) {
        if (manual && context.mounted) {
          _say(
            context,
            'Сервер обновлений ответил ошибкой ${response.statusCode}',
          );
        }
        return;
      }
      final body = await response.transform(utf8.decoder).join();
      final data = jsonDecode(body);
      if (data is! Map) {
        if (manual && context.mounted) {
          _say(context, 'Сервер обновлений вернул непонятный ответ');
        }
        return;
      }
      final remoteCode = data['versionCode'];
      if (remoteCode is! int) {
        if (manual && context.mounted) {
          _say(context, 'Сервер обновлений вернул непонятный ответ');
        }
        return;
      }
      final info = await PackageInfo.fromPlatform();
      final localCode = int.tryParse(info.buildNumber) ?? 0;
      final minCode = data['minVersionCode'];
      final forced = minCode is int && localCode < minCode;
      // Для обязательного обновления не откладываем следующую проверку
      if (!forced) await store.setInt(_lastCheckKey, now);
      if (remoteCode <= localCode) {
        if (manual && context.mounted) {
          _say(
            context,
            'У вас последняя версия (${info.version}, сборка ${info.buildNumber})',
          );
        }
        return;
      }
      final notes = data['notes'];
      if (!context.mounted) return;
      await _showDialog(
        context,
        forced: forced,
        notes: notes is String ? notes : '',
      );
    } catch (e, s) {
      Logs().w('DVChat: не удалось проверить обновления', e, s);
      if (manual && context.mounted) {
        _say(context, 'Не удалось проверить обновление: нет связи с сервером');
      }
    } finally {
      http.close();
      _checking = false;
    }
  }

  static Future<void> _showDialog(
    BuildContext context, {
    required bool forced,
    required String notes,
  }) async {
    final agree = await showDialog<bool>(
      context: context,
      barrierDismissible: !forced,
      builder: (context) => PopScope(
        canPop: !forced,
        child: AlertDialog(
          title: const Text('Доступно обновление'),
          content: Text(
            notes.isEmpty
                ? 'Вышла новая версия DVChat. Нажмите «Обновить», скачайте файл и подтвердите установку.'
                : notes,
          ),
          actions: [
            if (!forced)
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Позже'),
              ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Обновить'),
            ),
          ],
        ),
      ),
    );
    if (agree == true) {
      await launchUrl(
        Uri.parse('${AppConfig.updateBaseUrl}dvchat.apk'),
        mode: LaunchMode.externalApplication,
      );
    }
  }
}
