// SPDX-License-Identifier: AGPL-3.0-or-later

// DVChat: подсказка для iPhone. Вход, сделанный во вкладке Safari, не переходит в
// приложение с экрана «Домой»: у них разные хранилища, а во вкладке iOS ещё и стирает
// данные сайта после недели без заходов. Поэтому просим сначала добавить DVChat на
// экран «Домой» и входить уже оттуда.

import 'package:dvchat/utils/platform_infos.dart';
import 'package:material_ui/material_ui.dart';
import 'package:universal_html/universal_html.dart' as web;

class DvInstallHint extends StatelessWidget {
  const DvInstallHint({super.key});

  /// true: iPhone/iPad, и страница открыта во вкладке Safari, а не с иконки «Домой»
  static bool get needed {
    if (!PlatformInfos.isIosWeb) return false;
    try {
      return web.window.matchMedia('(display-mode: standalone)').matches !=
          true;
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSecondaryContainer;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.ios_share, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Чтобы вход не пропадал, сначала добавьте DVChat на экран «Домой»: '
              'нажмите «Поделиться» → «На экран Домой», откройте DVChat с иконки '
              'и войдите уже там.',
              style: TextStyle(color: color),
            ),
          ),
        ],
      ),
    );
  }
}
