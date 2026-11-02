// SPDX-License-Identifier: AGPL-3.0-or-later

// DVChat: плашка над полем ввода в личном чате: просьба об очистке переписки (мою или друга) и отказ.

import 'package:dvchat/utils/dv_clear.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

class DvClearBanner extends StatefulWidget {
  final Room room;
  const DvClearBanner(this.room, {super.key});

  @override
  State<DvClearBanner> createState() => _DvClearBannerState();
}

class _DvClearBannerState extends State<DvClearBanner> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action, {String? done}) async {
    if (_busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
      if (done != null) messenger.showSnackBar(SnackBar(content: Text(done)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final room = widget.room;
    return StreamBuilder<SyncUpdate>(
      stream: room.client.onSync.stream,
      builder: (context, _) {
        final state = DvClear.stateOf(room);
        if (state == DvClearState.none) return const SizedBox.shrink();
        final theme = Theme.of(context);
        final name = DvClear.peerName(room);
        final String text;
        final List<Widget> buttons;
        switch (state) {
          case DvClearState.incoming:
            text = '$name просит очистить вашу переписку. '
                'Если согласиться, все сообщения в этом чате сотрутся у вас обоих без возврата.';
            buttons = [
              TextButton(
                onPressed: _busy
                    ? null
                    : () => _run(() => DvClear.answer(room, accept: false)),
                child: const Text('Отказать'),
              ),
              FilledButton(
                onPressed: _busy
                    ? null
                    : () => _run(() => DvClear.answer(room, accept: true)),
                child: const Text('Стереть всё'),
              ),
            ];
          case DvClearState.waiting:
            text = 'Вы просили очистить чат. Ждём ответа: $name.';
            buttons = [
              TextButton(
                onPressed: _busy ? null : () => _run(() => DvClear.cancel(room)),
                child: const Text('Отменить просьбу'),
              ),
            ];
          case DvClearState.declined:
            text = '$name не согласился очистить чат.';
            buttons = [
              TextButton(
                onPressed: () async {
                  await DvClear.dismissDeclined(room);
                  if (mounted) setState(() {});
                },
                child: const Text('Понятно'),
              ),
            ];
          case DvClearState.none:
            return const SizedBox.shrink();
        }
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.cleaning_services_outlined,
                      size: 20, color: theme.colorScheme.primary),
                  const SizedBox(width: 10),
                  Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
                ],
              ),
              Align(
                alignment: Alignment.centerRight,
                child: Wrap(spacing: 8, children: buttons),
              ),
            ],
          ),
        );
      },
    );
  }
}
