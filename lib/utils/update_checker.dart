// DVChat: проверка обновлений. Приложение не чаще раза в несколько часов читает
// version.json на нашем сервере и предлагает скачать новую версию.

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
  static const Duration _interval = Duration(hours: 6);
  static bool _checking = false;

  static Future<void> check(BuildContext context) async {
    if (!Platform.isAndroid) return;
    if (_checking) return;
    final store = Matrix.of(context).store;
    final now = DateTime.now().millisecondsSinceEpoch;
    final last = store.getInt(_lastCheckKey) ?? 0;
    if (now - last < _interval.inMilliseconds) return;
    _checking = true;
    final http = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await http.getUrl(
        Uri.parse('${AppConfig.updateBaseUrl}version.json'),
      );
      final response = await request.close().timeout(
        const Duration(seconds: 15),
      );
      if (response.statusCode != 200) return;
      final body = await response.transform(utf8.decoder).join();
      final data = jsonDecode(body);
      if (data is! Map) return;
      final remoteCode = data['versionCode'];
      if (remoteCode is! int) return;
      final info = await PackageInfo.fromPlatform();
      final localCode = int.tryParse(info.buildNumber) ?? 0;
      final minCode = data['minVersionCode'];
      final forced = minCode is int && localCode < minCode;
      // Для обязательного обновления не откладываем следующую проверку
      if (!forced) await store.setInt(_lastCheckKey, now);
      if (remoteCode <= localCode) return;
      final notes = data['notes'];
      if (!context.mounted) return;
      await _showDialog(
        context,
        forced: forced,
        notes: notes is String ? notes : '',
      );
    } catch (e, s) {
      Logs().w('DVChat: не удалось проверить обновления', e, s);
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
