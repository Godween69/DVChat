// SPDX-License-Identifier: AGPL-3.0-or-later

// DVChat: единая отрисовка QR-кода: виджет для экрана (DvQr) и PNG-картинка для сохранения
// (DvQr.toPng). Используется в «Мой код», окне QR-приглашения и новом личном чате.

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';
import 'package:qr_flutter/qr_flutter.dart';

class DvQr extends StatelessWidget {
  final String data;
  final Color color;

  /// Сторона квадрата. Если не задана — занимает всю доступную ширину.
  final double? size;

  const DvQr({required this.data, required this.color, this.size, super.key});

  static QrEyeStyle _eyeStyle(Color color) =>
      QrEyeStyle(eyeShape: QrEyeShape.square, color: color);

  static QrDataModuleStyle _moduleStyle(Color color) => QrDataModuleStyle(
    dataModuleShape: QrDataModuleShape.square,
    color: color,
  );

  @override
  Widget build(BuildContext context) => QrImageView(
    data: data,
    size: size,
    eyeStyle: _eyeStyle(color),
    dataModuleStyle: _moduleStyle(color),
  );

  /// PNG: чёрный код на белом фоне — читается любым сканером.
  static Future<Uint8List> toPng(String data, {double size = 256}) async {
    final painter = QrPainter(
      data: data,
      version: QrVersions.auto,
      eyeStyle: _eyeStyle(const Color(0xFF000000)),
      dataModuleStyle: _moduleStyle(const Color(0xFF000000)),
    );
    final area = Size(size, size);
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawRect(
      Offset.zero & area,
      ui.Paint()..color = const Color(0xFFFFFFFF),
    );
    painter.paint(canvas, area);
    final image = await recorder.endRecording().toImage(
      size.toInt(),
      size.toInt(),
    );
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null) throw Exception('QR: не удалось получить PNG');
    return bytes.buffer.asUint8List();
  }
}
