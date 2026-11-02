// SPDX-License-Identifier: AGPL-3.0-or-later

// DVChat: подтверждение действия с галочкой «Больше не спрашивать».

import 'package:dvchat/l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

abstract class DvConfirm {
  /// Спрашивает подтверждение. Если человек когда-то поставил галочку «Больше не спрашивать»
  /// для этого ключа, сразу возвращает true. Ключ хранится на самом устройстве.
  static Future<bool> ask(
    BuildContext context, {
    required String key,
    required String title,
    required String message,
    required String okLabel,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(key) ?? false) return true;
    if (!context.mounted) return false;
    var dontAsk = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(message),
              const SizedBox(height: 8),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: dontAsk,
                onChanged: (value) => setLocal(() => dontAsk = value ?? false),
                title: const Text('Больше не спрашивать'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(L10n.of(context).cancel),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(okLabel),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return false;
    if (dontAsk) await prefs.setBool(key, true);
    return true;
  }
}
