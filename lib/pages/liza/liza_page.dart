// SPDX-License-Identifier: AGPL-3.0-or-later

// DVChat: вкладка «Лиза». Кому она открыта, решает сервер: допущенные видят чат,
// остальные пока видят анонс «Скоро в приложении».

import 'package:dvchat/pages/liza/liza_announce.dart';
import 'package:dvchat/pages/liza/liza_chat.dart';
import 'package:dvchat/pages/liza/liza_client.dart';
import 'package:dvchat/widgets/matrix.dart';
import 'package:material_ui/material_ui.dart';

class LizaPage extends StatefulWidget {
  const LizaPage({super.key});

  @override
  State<LizaPage> createState() => _LizaPageState();
}

class _LizaPageState extends State<LizaPage> {
  LizaStatus? _status;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _check();
  }

  Future<void> _check() async {
    final client = Matrix.of(context).client;
    final status = await LizaClient(client).status();
    if (!mounted) return;
    setState(() => _status = status);
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    if (status == null) {
      return Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          centerTitle: true,
          title: const Text('Лиза'),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    switch (status.access) {
      case LizaAccess.ok:
        final client = Matrix.of(context).client;
        return LizaChat(
          key: ValueKey(client.userID),
          client: client,
          status: status,
        );
      case LizaAccess.closed:
        return const LizaAnnounce();
      case LizaAccess.error:
        return Scaffold(
          appBar: AppBar(
            automaticallyImplyLeading: false,
            centerTitle: true,
            title: const Text('Лиза'),
          ),
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cloud_off, size: 48),
                const SizedBox(height: 12),
                const Text('Не удалось связаться с Лизой'),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () {
                    setState(() => _status = null);
                    _check();
                  },
                  child: const Text('Повторить'),
                ),
              ],
            ),
          ),
        );
    }
  }
}
