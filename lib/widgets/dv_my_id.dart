// DVChat: строка «Мой ID» в настройках и окно «Мой код» с QR

import 'dart:async';

import 'package:dvchat/l10n/l10n.dart';
import 'package:dvchat/utils/dv_api.dart';
import 'package:dvchat/widgets/dv_qr.dart';
import 'package:dvchat/widgets/matrix.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

class DvMyIdTile extends StatelessWidget {
  const DvMyIdTile({super.key});

  @override
  Widget build(BuildContext context) {
    final client = Matrix.of(context).client;
    return FutureBuilder<String>(
      future: DvApi(client).myId(),
      builder: (context, snapshot) {
        final id = snapshot.data;
        return ListTile(
          leading: const Icon(Icons.qr_code_2_outlined),
          title: const Text('Мой ID'),
          subtitle: Text(
            id ?? (snapshot.hasError ? 'Не удалось получить ID' : 'Загрузка…'),
          ),
          trailing: id == null
              ? null
              : IconButton(
                  icon: const Icon(Icons.copy_outlined),
                  tooltip: 'Скопировать',
                  onPressed: () {
                    unawaited(Clipboard.setData(ClipboardData(text: id)));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('ID скопирован')),
                    );
                  },
                ),
          onTap: id == null ? null : () => _showCode(context, id),
        );
      },
    );
  }

  Future<void> _showCode(BuildContext context, String id) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Мой код'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            color: Colors.white,
            padding: const EdgeInsets.all(12),
            child: DvQr(data: dvAddLink(id), size: 220, color: Colors.black),
          ),
          const SizedBox(height: 12),
          SelectableText(
            id,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Покажите код тому, кого хотите добавить в друзья: '
            'он отсканирует его или введёт ID вручную.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(L10n.of(context).close),
        ),
      ],
    ),
  );
}
