// SPDX-License-Identifier: AGPL-3.0-or-later

// DVChat: Экран обрезки аватара перед загрузкой.

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crop_image/crop_image.dart';
import 'package:material_ui/material_ui.dart';

/// DVChat: экран обрезки аватара. Возвращает PNG 512×512 или null (отмена).
Future<Uint8List?> cropAvatar(BuildContext context, Uint8List bytes) {
  return Navigator.of(context).push<Uint8List>(
    MaterialPageRoute(builder: (_) => _AvatarCropPage(bytes: bytes)),
  );
}

class _AvatarCropPage extends StatefulWidget {
  const _AvatarCropPage({required this.bytes});

  final Uint8List bytes;

  @override
  State<_AvatarCropPage> createState() => _AvatarCropPageState();
}

class _AvatarCropPageState extends State<_AvatarCropPage> {
  // Квадратная рамка 1:1, по умолчанию почти на всё изображение
  final CropController _controller = CropController(
    aspectRatio: 1,
    defaultCrop: const Rect.fromLTRB(0.05, 0.05, 0.95, 0.95),
  );
  bool _saving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final navigator = Navigator.of(context);
    try {
      final bitmap = await _controller.croppedBitmap(maxSize: 512);
      final data = await bitmap.toByteData(format: ui.ImageByteFormat.png);
      bitmap.dispose();
      navigator.pop(data?.buffer.asUint8List());
    } catch (_) {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Обрезка аватара'),
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            TextButton(
              onPressed: _save,
              child: Text(
                'Готово',
                style: TextStyle(
                  color: theme.colorScheme.primaryContainer,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: CropImage(
                controller: _controller,
                image: Image.memory(widget.bytes),
              ),
            ),
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                'Двигайте и растягивайте рамку. В чате аватар будет круглым.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
