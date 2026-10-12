// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

import '../mxc_image_viewer.dart';

/// DVChat: окно профиля пользователя. Показывает только аватар и имя.
/// Ссылка на профиль, статус присутствия и кнопки «Написать» / «Новый чат»
/// убраны намеренно: из этого окна нельзя выйти на других пользователей.
class UserDialog extends StatelessWidget {
  static Future<void> show({
    required BuildContext context,
    required Profile profile,
    bool noProfileWarning = false,
  }) => showAdaptiveDialog(
    context: context,
    barrierDismissible: true,
    builder: (context) =>
        UserDialog(profile, noProfileWarning: noProfileWarning),
  );

  final Profile profile;
  final bool noProfileWarning;

  const UserDialog(this.profile, {this.noProfileWarning = false, super.key});

  @override
  Widget build(BuildContext context) {
    final displayname =
        profile.displayName ??
        profile.userId.localpart ??
        L10n.of(context).user;
    final avatar = profile.avatarUrl;
    return AlertDialog.adaptive(
      content: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Avatar(
            mxContent: avatar,
            name: displayname,
            size: Avatar.defaultSize * 1.5,
            onTap: avatar != null
                ? () => showDialog(
                    context: context,
                    builder: (_) => MxcImageViewer(avatar),
                  )
                : null,
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              displayname,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 16),
            ),
          ),
        ],
      ),
    );
  }
}
