// SPDX-License-Identifier: AGPL-3.0-or-later

// DVChat: альбом фото в чате: квадратная панель с коллажем (1, 2, 3 или 4 клетки;
// если фото больше четырёх, на четвёртой «+N»), листание внутри альбома,
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

  /// Первое фото альбома: именно оно рисует всю панель
  final Event head;
  final Timeline timeline;
  final Color textColor;
  final BorderRadius borderRadius;

  static const double _side = 256;
  static const double _gap = 2;
  static const double _half = (_side - _gap) / 2;

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

  /// Одна клетка коллажа
  Widget _cell(
    BuildContext context,
    Event e,
    double w,
    double h, {
    Widget? cover,
  }) {
    return SizedBox(
      width: w,
      height: h,
      child: InkWell(
        onTap: () => _open(context, e),
        child: Stack(
          fit: StackFit.expand,
          children: [
            MxcImage(
              cacheKey: e.transactionId ?? e.eventId,
              cacheName: e.room.id,
              event: e,
              width: w,
              height: h,
              fit: BoxFit.cover,
              isThumbnail: true,
            ),
            ?cover,
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = dvAlbumMembers(head, timeline);
    final album = dvAlbumOf(head);
    final expected = album?.count ?? items.length;
    final sending = items.any((e) => e.status == EventStatus.sending);
    // Пока фото ещё отправляются или доходят (не дольше 5 минут), показываем крутилку
    final waiting =
        items.length < expected &&
        (sending ||
            DateTime.now().difference(head.originServerTs) <
                const Duration(minutes: 5));
    final shown = items.take(4).toList();
    final more = items.length > 4;
    final caption = head.fileDescription;

    Widget grid;
    if (shown.length <= 1) {
      grid = _cell(context, shown.first, _side, _side);
    } else if (shown.length == 2) {
      grid = Row(
        children: [
          _cell(context, shown[0], _half, _side),
          const SizedBox(width: _gap),
          _cell(context, shown[1], _half, _side),
        ],
      );
    } else if (shown.length == 3) {
      grid = Row(
        children: [
          _cell(context, shown[0], _half, _side),
          const SizedBox(width: _gap),
          Column(
            children: [
              _cell(context, shown[1], _half, _half),
              const SizedBox(height: _gap),
              _cell(context, shown[2], _half, _half),
            ],
          ),
        ],
      );
    } else {
      grid = Column(
        children: [
          Row(
            children: [
              _cell(context, shown[0], _half, _half),
              const SizedBox(width: _gap),
              _cell(context, shown[1], _half, _half),
            ],
          ),
          const SizedBox(height: _gap),
          Row(
            children: [
              _cell(context, shown[2], _half, _half),
              const SizedBox(width: _gap),
              _cell(
                context,
                shown[3],
                _half,
                _half,
                cover: more
                    ? ColoredBox(
                        color: Colors.black54,
                        child: Center(
                          child: Text(
                            '+${items.length - 3}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      )
                    : null,
              ),
            ],
          ),
        ],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: borderRadius,
          child: SizedBox(
            width: _side,
            height: _side,
            child: Stack(
              fit: StackFit.expand,
              children: [
                grid,
                if (waiting)
                  IgnorePointer(
                    child: ColoredBox(
                      color: Colors.black38,
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const CircularProgressIndicator.adaptive(),
                            const SizedBox(height: 8),
                            Text(
                              '${items.length} из $expected',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (caption != null && caption.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(caption, style: TextStyle(color: textColor)),
          ),
        if (items.length > 1)
          TextButton.icon(
            onPressed: waiting ? null : () => _saveAll(context, items),
            icon: const Icon(Icons.download, size: 18),
            label: Text('Сохранить все (${items.length})'),
            style: TextButton.styleFrom(foregroundColor: textColor),
          ),
      ],
    );
  }
}
