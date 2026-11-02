// SPDX-License-Identifier: AGPL-3.0-or-later

// DVChat: «Лучшие друзья»: личный список избранных людей. Хранится в данных аккаунта
// (account data) на сервере, поэтому переживает смену телефона. Собеседник об этом не узнаёт.

import 'package:matrix/matrix.dart';

const String _bestFriendsType = 'online.dvbstudio.dvchat.best_friends';

extension BestFriendsExtension on Client {
  /// Идентификаторы людей из списка «Лучшие»
  Set<String> get bestFriends {
    final raw = accountData[_bestFriendsType]?.content['ids'];
    return raw is List ? raw.whereType<String>().toSet() : <String>{};
  }

  Future<void> setBestFriend(String userId, {required bool best}) async {
    final ids = bestFriends;
    if (best) {
      ids.add(userId);
    } else {
      ids.remove(userId);
    }
    await setAccountData(userID!, _bestFriendsType, {'ids': ids.toList()});
  }
}
