// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// DVChat: Уменьшение картинок перед отправкой в чат (размер и качество), чтобы не слать оригиналы.

import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:matrix/matrix.dart';
import 'package:native_imaging/native_imaging.dart' as native;

(int, int) _scaleToBox(int width, int height, {required int boxSize}) {
  final fit = applyBoxFit(
    BoxFit.scaleDown,
    Size(width.toDouble(), height.toDouble()),
    Size(boxSize.toDouble(), boxSize.toDouble()),
  ).destination;
  return (fit.width.round(), fit.height.round());
}

Future<MatrixImageFileResizedResponse?> customImageResizer(
  MatrixImageFileResizeArguments arguments,
) async {
  await native.init();

  var imageBytes = arguments.bytes;
  String? blurhash;

  var originalWidth = 0;
  var originalHeight = 0;
  var width = 0;
  var height = 0;
  String? mimeType;

  try {
    // DVChat: размер узнаём, не раскрывая картинку, и раскрываем сразу в нужном размере.
    // Раньше оригинал (12 Мп) раскрывался целиком: около 48 МБ памяти и секунды работы
    // главного потока на каждое фото, из-за чего окно отправки висело, а приложение вылетало.
    final buffer = await ImmutableBuffer.fromUint8List(arguments.bytes);
    final descriptor = await ImageDescriptor.encoded(buffer);
    var srcW = descriptor.width;
    var srcH = descriptor.height;
    final longSide = srcW > srcH ? srcW : srcH;
    final limit = arguments.maxDimension;
    final scale = longSide > limit ? limit / longSide : 1.0;
    final dartCodec = await descriptor.instantiateCodec(
      targetWidth: (srcW * scale).round(),
      targetHeight: (srcH * scale).round(),
    );
    descriptor.dispose();
    buffer.dispose();
    final frameCount = dartCodec.frameCount;
    final dartFrame = await dartCodec.getNextFrame();
    final rgbaData = await dartFrame.image.toByteData();
    if (rgbaData == null) {
      return null;
    }
    final rgba = Uint8List.view(
      rgbaData.buffer,
      rgbaData.offsetInBytes,
      rgbaData.lengthInBytes,
    );

    width = dartFrame.image.width;
    height = dartFrame.image.height;
    // если сторона повернулась при раскрытии, размеры оригинала меняем местами
    if (srcW != srcH && (srcW > srcH) != (width > height)) {
      final t = srcW;
      srcW = srcH;
      srcH = t;
    }
    originalWidth = srcW;
    originalHeight = srcH;

    var nativeImg = native.Image.fromRGBA(width, height, rgba);

    dartFrame.image.dispose();
    dartCodec.dispose();

    if (arguments.calcBlurhash) {
      // scale down image for blurhashing to speed it up
      final (blurW, blurH) = _scaleToBox(width, height, boxSize: 100);
      final blurhashImg = nativeImg.resample(
        blurW,
        blurH,
        // nearest is unsupported...
        native.Transform.bilinear,
      );

      blurhash = blurhashImg.toBlurhash(3, 3);

      blurhashImg.free();
    }

    if (frameCount > 1) {
      // Don't scale down animated images, since those would lose frames.
      width = originalWidth;
      height = originalHeight;
      nativeImg.free();
    } else {
      final max = arguments.maxDimension;
      if (width > max || height > max) {
        (width, height) = _scaleToBox(width, height, boxSize: max);

        final scaledImg = nativeImg.resample(
          width,
          height,
          native.Transform.lanczos,
        );
        nativeImg.free();
        nativeImg = scaledImg;
      }

      imageBytes = await nativeImg.toJpeg(75);
      mimeType = 'image/jpeg';
      nativeImg.free();
    }
  } catch (e, s) {
    Logs().e('Could not generate preview', e, s);
    mimeType = null;
  }

  return MatrixImageFileResizedResponse(
    bytes: imageBytes,
    width: width,
    height: height,
    originalWidth: originalWidth,
    originalHeight: originalHeight,
    blurhash: blurhash,
    mimeType: mimeType,
  );
}
