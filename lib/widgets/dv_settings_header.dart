// SPDX-License-Identifier: AGPL-3.0-or-later

// DVChat: верх экрана настроек как в WhatsApp: аватарка, имя и «ID номер» (нажатие копирует),
// справа значок QR («Мой код»). Нажатие на аватарку открывает профиль.

import 'dart:async';

import 'package:dvchat/l10n/l10n.dart';
import 'package:dvchat/utils/dv_api.dart';
import 'package:dvchat/widgets/avatar.dart';
import 'package:dvchat/widgets/dv_my_id.dart';
import 'package:dvchat/widgets/matrix.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

class DvSettingsHeader extends StatelessWidget {
  const DvSettingsHeader({
    required this.profileFuture,
    required this.avatarKey,
    required this.onOpenProfile,
    super.key,
  });

  final Future<Profile>? profileFuture;

  /// По этому ключу находим место аватарки на экране (откуда «вылетает» профиль)
  final GlobalKey avatarKey;
  final void Function(String mxid) onOpenProfile;

  static const double avatarSize = 64;

  /// Последний загруженный профиль: пока грузится свежий, показываем прошлый,
  /// а не пустую аватарку с буквами (иначе она «моргает»)
  static final Map<String, Profile> _profileCache = {};

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final client = Matrix.of(context).client;
    final mxid = client.userID ?? L10n.of(context).user;
    return FutureBuilder<Profile>(
      initialData: _profileCache[client.userID ?? ''],
      future: profileFuture,
      builder: (context, profileSnapshot) {
        final profile = profileSnapshot.data;
        if (profile != null) _profileCache[client.userID ?? ''] = profile;
        final displayname = profile?.displayName ?? mxid.localpart ?? mxid;
        return FutureBuilder<String>(
          initialData: DvApi.cachedId(client),
          future: DvApi(client).myId(),
          builder: (context, idSnapshot) {
            final id = idSnapshot.data;
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => onOpenProfile(mxid),
                    child: KeyedSubtree(
                      key: avatarKey,
                      child: Avatar(
                        mxContent: profile?.avatarUrl,
                        name: displayname,
                        size: avatarSize,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          displayname,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        InkWell(
                          onTap: id == null
                              ? null
                              : () {
                                  unawaited(
                                    Clipboard.setData(ClipboardData(text: id)),
                                  );
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('ID скопирован'),
                                    ),
                                  );
                                },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Text(
                              id == null
                                  ? (idSnapshot.hasError
                                        ? 'ID не получен'
                                        : 'ID …')
                                  : 'ID $id',
                              style: theme.textTheme.bodyLarge?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.qr_code_2_outlined),
                    tooltip: 'Мой код',
                    onPressed: id == null
                        ? null
                        : () => unawaited(DvMyIdTile.showCode(context, id)),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
