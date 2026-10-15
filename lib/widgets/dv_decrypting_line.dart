// SPDX-License-Identifier: AGPL-3.0-or-later

// DVChat: подпись чата, пока сообщение ещё расшифровывается: крутилка и текст

import 'package:material_ui/material_ui.dart';

class DvDecryptingLine extends StatelessWidget {
  const DvDecryptingLine({super.key});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(
      children: [
        SizedBox(
          width: 12,
          height: 12,
          child: CircularProgressIndicator(strokeWidth: 2, color: color),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            'Расшифровка…',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: color),
          ),
        ),
      ],
    );
  }
}
