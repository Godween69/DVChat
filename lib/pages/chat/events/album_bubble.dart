// SPDX-License-Identifier: AGPL-3.0-or-later

// DVChat: альбом фото в чате: квадратная панель с коллажем (1, 2, 3 или 4 клетки;
// если фото больше четырёх, на четвёртой «+N»), листание внутри альбома,
// «Сохранить все» живёт в просмотре альбома. Пока фото отправляются, панель сразу занимает
// своё место (по числу фото), на ней крутится индикатор и «k из n».

import 'package:dvchat/pages/image_viewer/image_viewer.dart';
import 'package:dvchat/utils/dv_album.dart';
import 'package:dvchat/utils/file_description.dart';
import 'package:dvchat/widgets/mxc_image.dart';
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

  /// Одна клетка коллажа
  Widget _cell(
    BuildContext context,
    Event? e,
    double w,
    double h, {
    Widget? cover,
  }) {
    if (e == null) {
      // Фото ещё не отправлено: пустое место, чтобы панель не менялась в размере
      return SizedBox(
        width: w,
        height: h,
        child: ColoredBox(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: cover,
        ),
      );
    }
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
    // Готово = уже отправлено; в ожидании пока хоть одно фото идёт или ещё не появилось
    // (не дольше 5 минут), ошибка отправки крутилку выключает
    final done = items
        .where(
          (e) =>
              e.status == EventStatus.sent || e.status == EventStatus.synced,
        )
        .length;
    final sending = items.any((e) => e.status == EventStatus.sending);
    final failed = items.any((e) => e.status == EventStatus.error);
    final waiting =
        !failed &&
        (sending ||
            (items.length < expected &&
                DateTime.now().difference(head.originServerTs) <
                    const Duration(minutes: 5)));
    // Клетки по ожидаемому числу фото: недостающие пустые (null)
    final cells = <Event?>[
      for (var k = 0; k < (expected > 4 ? 4 : expected); k++)
        k < items.length ? items[k] : null,
    ];
    final more = expected > 4;
    final caption = head.fileDescription;

    Widget grid;
    if (cells.length <= 1) {
      grid = _cell(context, cells.first, _side, _side);
    } else if (cells.length == 2) {
      grid = Row(
        children: [
          _cell(context, cells[0], _half, _side),
          const SizedBox(width: _gap),
          _cell(context, cells[1], _half, _side),
        ],
      );
    } else if (cells.length == 3) {
      grid = Row(
        children: [
          _cell(context, cells[0], _half, _side),
          const SizedBox(width: _gap),
          Column(
            children: [
              _cell(context, cells[1], _half, _half),
              const SizedBox(height: _gap),
              _cell(context, cells[2], _half, _half),
            ],
          ),
        ],
      );
    } else {
      grid = Column(
        children: [
          Row(
            children: [
              _cell(context, cells[0], _half, _half),
              const SizedBox(width: _gap),
              _cell(context, cells[1], _half, _half),
            ],
          ),
          const SizedBox(height: _gap),
          Row(
            children: [
              _cell(context, cells[2], _half, _half),
              const SizedBox(width: _gap),
              _cell(
                context,
                cells[3],
                _half,
                _half,
                cover: more
                    ? ColoredBox(
                        color: Colors.black54,
                        child: Center(
                          child: Text(
                            '+${expected - 3}',
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
                              '$done из $expected',
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
        // Пока идёт отправка: под альбомом что-то улетает
        if (waiting && head.senderId == head.room.client.userID)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: _FlyingSend(color: textColor),
          ),
      ],
    );
  }
}

/// Маленькая анимация «отправляется»: бумажный самолётик улетает вправо и вверх и тает
class _FlyingSend extends StatefulWidget {
  const _FlyingSend({required this.color});

  final Color color;

  @override
  State<_FlyingSend> createState() => _FlyingSendState();
}

class _FlyingSendState extends State<_FlyingSend>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      SizedBox(
        width: 34,
        height: 20,
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, child) => Opacity(
            opacity: 1 - _c.value,
            child: Transform.translate(
              offset: Offset(_c.value * 18, -_c.value * 8),
              child: child,
            ),
          ),
          child: Icon(Icons.send_rounded, size: 16, color: widget.color),
        ),
      ),
      Text(
        'Отправляется…',
        style: TextStyle(color: widget.color, fontSize: 12),
      ),
    ],
  );
}
