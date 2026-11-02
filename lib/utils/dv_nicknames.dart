// SPDX-License-Identifier: AGPL-3.0-or-later

// DVChat: личные имена. Каждый может назвать друга по-своему (мама для меня «мама»,
// для сына «бабушка»). Имена хранятся в данных аккаунта (dv.nicknames) и видны только
// их владельцу, у других людей и на сервере в профиле человека ничего не меняется.

import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart';

class DvNicknames {
  static const String type = 'dv.nicknames';

  /// Растёт при каждом изменении: списки, показывающие имена, перерисовываются
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static Map<String, String> _all(Client client) {
    final raw = client.accountData[type]?.content;
    final out = <String, String>{};
    if (raw != null) {
      raw.forEach((key, value) {
        if (value is String && value.trim().isNotEmpty) {
          out[key] = value.trim();
        }
      });
    }
    return out;
  }

  /// Личное имя человека или null, если не задано (себя не переименовываем)
  static String? of(Client client, String userId) {
    if (userId == client.userID) return null;
    return _all(client)[userId];
  }

  /// Задаёт имя; пустое или null убирает его
  static Future<void> set(Client client, String userId, String? name) async {
    final all = <String, Object?>{..._all(client)};
    final value = name?.trim() ?? '';
    if (value.isEmpty) {
      all.remove(userId);
    } else {
      all[userId] = value;
    }
    await client.setAccountData(client.userID!, type, all);
    client.accountData[type] = BasicEvent(type: type, content: all);
    revision.value++;
  }
}

extension DvRoomNickname on Room {
  /// Название чата; в личном чате вместо имени человека показывается личное имя
  String dvDisplayname([
    MatrixLocalizations i18n = const MatrixDefaultLocalizations(),
  ]) {
    final id = directChatMatrixID;
    if (id != null) {
      final nick = DvNicknames.of(client, id);
      if (nick != null) return nick;
    }
    return getLocalizedDisplayname(i18n);
  }
}

extension DvUserNickname on User {
  /// Имя человека для показа: личное имя, если задано
  String dvName({
    bool? formatLocalpart,
    bool? mxidLocalPartFallback,
    MatrixLocalizations i18n = const MatrixDefaultLocalizations(),
  }) =>
      DvNicknames.of(room.client, id) ??
      calcDisplayname(
        formatLocalpart: formatLocalpart,
        mxidLocalPartFallback: mxidLocalPartFallback,
        i18n: i18n,
      );
}
