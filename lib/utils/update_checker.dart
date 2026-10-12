// DVChat: проверка и установка обновлений. Приложение сверяется с version.json на нашем
// сервере (автоматически не чаще раза в час, по кнопке в настройках сразу), скачивает
// новую версию само (с проверкой размера и контрольной суммы) и открывает окно установки.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' show sha256;
import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:open_filex/open_filex.dart' show OpenFilex, ResultType;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

class _UpdateCancelled implements Exception {}

abstract class DvUpdateChecker {
  static const String _lastCheckKey =
      'online.dvbstudio.dvchat.update_checked_at';
  static const Duration _interval = Duration(hours: 1);
  static const String _apkName = 'dvchat-update.apk';
  static bool _checking = false;
  static bool _installing = false;

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
        _cleanup();
        if (manual && context.mounted) {
          _say(
            context,
            'У вас последняя версия (${info.version}, сборка ${info.buildNumber})',
          );
        }
        return;
      }
      final notes = data['notes'];
      final sha = data['sha256'];
      final size = data['size'];
      if (!context.mounted) return;
      await _showDialog(
        context,
        forced: forced,
        notes: notes is String ? notes : '',
        sha256Hex: sha is String ? sha.toLowerCase() : null,
        size: size is int ? size : null,
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
    required String? sha256Hex,
    required int? size,
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
                ? 'Вышла новая версия DVChat. Нажмите «Обновить»: приложение скачает её и предложит установить.'
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
    if (agree == true && context.mounted) {
      await _downloadAndInstall(context, sha256Hex: sha256Hex, size: size);
    }
  }

  /// Скачивает файл обновления с полосой загрузки, проверяет его и открывает окно установки.
  /// При любой неудаче открывает скачивание в браузере (прежний способ).
  static Future<void> _downloadAndInstall(
    BuildContext context, {
    required String? sha256Hex,
    required int? size,
  }) async {
    if (_installing) return;
    _installing = true;
    final navigator = Navigator.of(context, rootNavigator: true);
    final messenger = ScaffoldMessenger.of(context);
    final progress = ValueNotifier<double?>(null);
    var cancelled = false;
    var dialogOpen = true;
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => PopScope(
          canPop: false,
          child: AlertDialog(
            title: const Text('Загрузка обновления'),
            content: ValueListenableBuilder<double?>(
              valueListenable: progress,
              builder: (context, value, _) => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  LinearProgressIndicator(value: value),
                  const SizedBox(height: 12),
                  Text(
                    value == null
                        ? 'Подключение…'
                        : '${(value * 100).round()}%',
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => cancelled = true,
                child: const Text('Отмена'),
              ),
            ],
          ),
        ),
      ),
    );
    void closeDialog() {
      if (!dialogOpen) return;
      dialogOpen = false;
      navigator.pop();
    }

    Future<void> openInBrowser() => launchUrl(
      Uri.parse('${AppConfig.updateBaseUrl}dvchat.apk'),
      mode: LaunchMode.externalApplication,
    );

    try {
      final dir = await getTemporaryDirectory();
      final target = File('${dir.path}/$_apkName');
      // Уже скачанный и проверенный файл используем повторно
      if (!await _isValid(target, sha256Hex, size)) {
        await _download(
          target: target,
          size: size,
          sha256Hex: sha256Hex,
          progress: progress,
          cancelled: () => cancelled,
        );
      }
      closeDialog();
      final result = await OpenFilex.open(
        target.path,
        type: 'application/vnd.android.package-archive',
      );
      if (result.type != ResultType.done) {
        Logs().w('DVChat: не удалось открыть установку: ${result.message}');
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              'Не удалось открыть установку, открываю загрузку в браузере',
            ),
          ),
        );
        await openInBrowser();
      }
    } on _UpdateCancelled {
      closeDialog();
    } catch (e, s) {
      Logs().w('DVChat: не удалось скачать обновление', e, s);
      closeDialog();
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Не удалось скачать обновление в приложении, открываю загрузку в браузере',
          ),
        ),
      );
      await openInBrowser();
    } finally {
      _installing = false;
    }
  }

  static Future<bool> _isValid(File file, String? sha256Hex, int? size) async {
    if (!file.existsSync()) return false;
    if (size != null && file.lengthSync() != size) return false;
    if (sha256Hex != null) {
      final digest = await sha256.bind(file.openRead()).first;
      return digest.toString() == sha256Hex;
    }
    return true;
  }

  static Future<void> _download({
    required File target,
    required int? size,
    required String? sha256Hex,
    required ValueNotifier<double?> progress,
    required bool Function() cancelled,
  }) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    final part = File('${target.path}.part');
    IOSink? sink;
    try {
      final request = await client.getUrl(
        Uri.parse('${AppConfig.updateBaseUrl}dvchat.apk'),
      );
      final response = await request.close().timeout(
        const Duration(seconds: 30),
      );
      if (response.statusCode != 200) {
        throw HttpException('Сервер ответил ${response.statusCode}');
      }
      final total = response.contentLength > 0 ? response.contentLength : size;
      var received = 0;
      sink = part.openWrite();
      await for (final chunk in response.timeout(const Duration(seconds: 30))) {
        if (cancelled()) throw _UpdateCancelled();
        sink.add(chunk);
        received += chunk.length;
        if (total != null && total > 0) {
          progress.value = (received / total).clamp(0.0, 1.0);
        }
      }
      await sink.close();
      sink = null;
      if (size != null && received != size) {
        throw const HttpException('Размер файла не совпал');
      }
      if (sha256Hex != null) {
        final digest = await sha256.bind(part.openRead()).first;
        if (digest.toString() != sha256Hex) {
          throw const HttpException('Контрольная сумма не совпала');
        }
      }
      if (target.existsSync()) target.deleteSync();
      await part.rename(target.path);
    } finally {
      await sink?.close();
      client.close();
      if (part.existsSync()) part.deleteSync();
    }
  }

  /// Убирает скачанные файлы обновления, когда приложение уже последней версии.
  static Future<void> _cleanup() async {
    try {
      final dir = await getTemporaryDirectory();
      for (final name in [_apkName, '$_apkName.part']) {
        final file = File('${dir.path}/$name');
        if (file.existsSync()) file.deleteSync();
      }
    } catch (e) {
      Logs().v('DVChat: не удалось убрать файл обновления', e);
    }
  }
}
