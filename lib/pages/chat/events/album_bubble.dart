// SPDX-License-Identifier: AGPL-3.0-or-later

// DVChat: альбом фото в чате: одна сетка из фото, листание внутри альбома,
// кнопка «Сохранить все».

import 'package:dvchat/pages/image_viewer/image_viewer.dart';
import 'package:dvchat/utils/dv_album.dart';
import 'package:dvchat/utils/file_description.dart';
import 'package:dvchat/utils/matrix_sdk_extensions/matrix_file_extension.dart';
import 'package:dvchat/widgets/mxc_image.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

class AlbumBubble extends StatelessWidget {
  const AlbumBubble({
    required this.head,
    required this.timeline,
    required this.textColor,
    required this.borderRadius,
    super.key,
  });

  /// Первое фото альбома: именно оно рисует всю сетку
  final Event head;
  final Timeline timeline;
  final Color textColor;
  final BorderRadius borderRadius;

  static const double _side = 256;
  static const double _gap = 2;

  /// Сколько клеток видно в сетке; остальные прячутся за «+N»
  static const int _maxCells = 9;

  void _open(BuildContext context, Event e) {
    showDialog(
      context: context,
      builder: (_) => ImageViewer(e, timeline: timeline, outerContext: context),
    );
  }

  Future<void> _saveAll(BuildContext context, List<Event> items) async {
    final messenger = ScaffoldMessenger.of(context);
    final android = !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
    var ok = 0;
    for (var k = 0; k < items.length; k++) {
      messenger
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text('Сохраняю ${k + 1} из ${items.length}…'),
            duration: const Duration(minutes: 5),
          ),
        );
      try {
        final file = await items[k].downloadAndDecryptAttachment();
        if (android) {
          if (await file.saveToGalleryQuiet()) ok++;
        } else {
          if (!context.mounted) break;
          await file.save(context);
          ok++;
        }
      } catch (e, s) {
        Logs().w('Альбом: не удалось сохранить фото', e, s);
      }
    }
    messenger
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(
            ok == items.length
                ? 'Сохранено фото: $ok'
                : 'Сохранено $ok из ${items.length}',
          ),
          showCloseIcon: true,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final items = dvAlbumMembers(head, timeline);
    final album = dvAlbumOf(head);
    final expected = album?.count ?? items.length;
    final shown = items.take(_maxCells).toList();
    final cols = shown.length == 1
        ? 1
        : (shown.length == 2 || shown.length == 4)
        ? 2
        : 3;
    final cell = (_side - _gap * (cols - 1)) / cols;
    final hidden = items.length - shown.length;
    final caption = head.fileDescription;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: borderRadius,
          child: SizedBox(
            width: _side,
            child: Wrap(
              spacing: _gap,
              runSpacing: _gap,
              children: [
                for (var k = 0; k < shown.length; k++)
                  SizedBox(
                    width: cols == 1 ? _side : cell,
                    height: cols == 1 ? _side : cell,
                    child: InkWell(
                      onTap: () => _open(context, shown[k]),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          MxcImage(
                            cacheKey:
                                shown[k].transactionId ?? shown[k].eventId,
                            cacheName: shown[k].room.id,
                            event: shown[k],
                            width: cols == 1 ? _side : cell,
                            height: cols == 1 ? _side : cell,
                            fit: BoxFit.cover,
                            isThumbnail: true,
                          ),
                          if (hidden > 0 && k == shown.length - 1)
                            ColoredBox(
                              color: Colors.black54,
                              child: Center(
                                child: Text(
                                  '+${hidden + 1}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (items.length < expected)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Загружается: ${items.length} из $expected',
              style: TextStyle(color: textColor, fontSize: 12),
            ),
          ),
        if (caption != null && caption.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(caption, style: TextStyle(color: textColor)),
          ),
        if (items.length > 1)
          TextButton.icon(
            onPressed: () => _saveAll(context, items),
            icon: const Icon(Icons.download, size: 18),
            label: Text('Сохранить все (${items.length})'),
            style: TextButton.styleFrom(foregroundColor: textColor),
          ),
      ],
    );
  }
}
