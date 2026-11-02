// SPDX-License-Identifier: AGPL-3.0-or-later

// DVChat: подготовка фото для обоев чата: масштабируем и обрезаем ровно под экран и сохраняем
// как JPEG. Такая картинка маленькая, быстро грузится и почти ничего не стоит при отрисовке.

import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:matrix/matrix.dart';
import 'package:native_imaging/native_imaging.dart' as native;

abstract class DvWallpaper {
  /// Возвращает JPEG ровно [width] x [height] точек (середина фото) или null, если фото меньше
  /// экрана или что-то пошло не так (тогда берём обычное сжатие).
  static Future<Uint8List?> fitToScreen(
    Uint8List bytes, {
    required int width,
    required int height,
  }) async {
    try {
      await native.init();

      // 1) Пропорции фото: картинка декодируется сразу в крошечном размере, это быстро
      final probeCodec = await ui.instantiateImageCodec(bytes, targetWidth: 64);
      final probeImage = (await probeCodec.getNextFrame()).image;
      final aspect = probeImage.width / probeImage.height;
      probeImage.dispose();
      probeCodec.dispose();

      // 2) Размер, при котором фото целиком закрывает экран (как BoxFit.cover)
      final targetHeight = max(height.toDouble(), width / aspect).ceil();
      final targetWidth = (targetHeight * aspect).ceil();

      // 3) Декодируем сразу в нужном размере: большое фото целиком в памяти не держим
      final codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: targetWidth,
        targetHeight: targetHeight,
        allowUpscaling: false,
      );
      final image = (await codec.getNextFrame()).image;
      codec.dispose();
      if (image.width < width || image.height < height) {
        // Фото меньше экрана: растягивать нечего, оставляем как есть
        image.dispose();
        return null;
      }

      // 4) Вырезаем середину ровно под экран
      final recorder = ui.PictureRecorder();
      ui.Canvas(recorder).drawImageRect(
        image,
        ui.Rect.fromLTWH(
          (image.width - width) / 2,
          (image.height - height) / 2,
          width.toDouble(),
          height.toDouble(),
        ),
        ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
        ui.Paint()..filterQuality = ui.FilterQuality.high,
      );
      final picture = recorder.endRecording();
      final fitted = await picture.toImage(width, height);
      final data = await fitted.toByteData();
      image.dispose();
      picture.dispose();
      fitted.dispose();
      if (data == null) return null;

      // 5) Сохраняем как JPEG
      final rgba = Uint8List.view(
        data.buffer,
        data.offsetInBytes,
        data.lengthInBytes,
      );
      final nativeImage = native.Image.fromRGBA(width, height, rgba);
      final jpeg = await nativeImage.toJpeg(85);
      nativeImage.free();
      return jpeg;
    } catch (e, s) {
      Logs().w('Не удалось подогнать обои под экран', e, s);
      return null;
    }
  }
}
