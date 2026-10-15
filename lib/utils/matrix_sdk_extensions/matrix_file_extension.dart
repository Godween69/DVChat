// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// DVChat: Расширение MatrixFile: сохранение и отправка файла другим приложениям.
// Фото и видео на Android сохраняются сразу в галерею (альбом DVChat), без диалога и
// без ввода имени. Остальные файлы (документы, архивы) сохраняются через выбор места.

import 'dart:io';

import 'package:dvchat/l10n/l10n.dart';
import 'package:dvchat/utils/size_string.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:gal/gal.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

extension MatrixFileExtension on MatrixFile {
  static const String _galleryAlbum = 'DVChat';

  bool get _isVideo =>
      this is MatrixVideoFile || mimeType.toLowerCase().startsWith('video/');

  bool get _isImage =>
      this is MatrixImageFile || mimeType.toLowerCase().startsWith('image/');

  /// Автоматическое имя вида DVChat_20261014_215630.mp4
  String get _galleryName {
    String two(int v) => v.toString().padLeft(2, '0');
    final n = DateTime.now();
    final dot = name.lastIndexOf('.');
    final ext = dot > 0 && dot < name.length - 1
        ? name.substring(dot)
        : (_isVideo ? '.mp4' : '.jpg');
    return 'DVChat_${n.year}${two(n.month)}${two(n.day)}_'
        '${two(n.hour)}${two(n.minute)}${two(n.second)}$ext';
  }

  /// Кладёт фото или видео в галерею. Возвращает false, если не вышло (тогда
  /// показывается обычный выбор места сохранения).
  Future<bool> _saveToGallery() async {
    try {
      if (_isVideo) {
        final dir = await getTemporaryDirectory();
        final file = File('${dir.path}/$_galleryName');
        await file.writeAsBytes(bytes);
        await Gal.putVideo(file.path, album: _galleryAlbum);
        await file.delete();
      } else {
        await Gal.putImageBytes(bytes, album: _galleryAlbum);
      }
      return true;
    } catch (e, s) {
      Logs().w('Не удалось сохранить в галерею', e, s);
      return false;
    }
  }

  Future<void> save(BuildContext context) async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final l10n = L10n.of(context);

    if (!kIsWeb &&
        defaultTargetPlatform == TargetPlatform.android &&
        (_isImage || _isVideo)) {
      if (await _saveToGallery()) {
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text(
              _isVideo
                  ? 'Видео сохранено в галерею (альбом $_galleryAlbum)'
                  : 'Фото сохранено в галерею (альбом $_galleryAlbum)',
            ),
            showCloseIcon: true,
          ),
        );
        return;
      }
    }

    final downloadPath = await FilePicker.saveFile(
      dialogTitle: l10n.saveFile,
      fileName: name,
      type: filePickerFileType,
      bytes: bytes,
    );
    if (downloadPath == null) return;

    scaffoldMessenger.showSnackBar(
      SnackBar(
        content: Text(l10n.fileHasBeenSavedAt(downloadPath.toString())),
        showCloseIcon: true,
      ),
    );
  }

  FileType get filePickerFileType {
    if (this is MatrixImageFile) return FileType.image;
    if (this is MatrixAudioFile) return FileType.audio;
    if (this is MatrixVideoFile) return FileType.video;
    return FileType.any;
  }

  Future<void> share(BuildContext context) async {
    // Workaround for iPad from
    // https://github.com/fluttercommunity/plus_plugins/tree/main/packages/share_plus/share_plus#ipad
    final box = context.findRenderObject() as RenderBox?;

    await SharePlus.instance.share(
      ShareParams(
        files: [XFile.fromData(bytes, name: name, mimeType: mimeType)],
        sharePositionOrigin: box == null
            ? null
            : box.localToGlobal(Offset.zero) & box.size,
      ),
    );
    return;
  }

  MatrixFile get detectFileType {
    if (msgType == MessageTypes.Image) {
      return MatrixImageFile(bytes: bytes, name: name);
    }
    if (msgType == MessageTypes.Video) {
      return MatrixVideoFile(bytes: bytes, name: name);
    }
    if (msgType == MessageTypes.Audio) {
      return MatrixAudioFile(bytes: bytes, name: name);
    }
    return this;
  }

  String get sizeString => size.sizeString;
}
