// SPDX-License-Identifier: AGPL-3.0-or-later

// DVChat: блокировка собеседника с памятью о периодах. Сервер, разблокируя человека, сразу
// показывает всё, что он писал, пока был заблокирован. Поэтому время блокировки и разблокировки
// записывается в данные аккаунта (account data), а сообщения этого человека, отправленные
// внутри периода блокировки, в чате не показываются никогда.

import 'package:matrix/matrix.dart';

/// Тип данных аккаунта: {"periods": {"@user:server": [[начало_мс, конец_мс], ...]}}.
/// Конец 0 означает «блокировка действует сейчас».
const String _blockedPeriodsType = 'online.dvbstudio.dvchat.blocked_periods';

extension BlockedPeriodsExtension on Client {
  Future<void> blockUser(String userId) async {
    await _markPeriod(userId, blocked: true);
    await ignoreUser(userId, leaveRooms: false);
  }

  Future<void> unblockUser(String userId) async {
    await _markPeriod(userId, blocked: false);
    await unignoreUser(userId);
  }

  /// Отправлено ли событие в то время, пока его автор был заблокирован
  bool isHiddenByBlock(Event event) {
    final raw = accountData[_blockedPeriodsType]?.content['periods'];
    if (raw is! Map) return false;
    final list = raw[event.senderId];
    if (list is! List) return false;
    final ts = event.originServerTs.millisecondsSinceEpoch;
    for (final p in list) {
      if (p is List && p.length == 2 && p[0] is int && p[1] is int) {
        final from = p[0] as int;
        final to = p[1] as int;
        if (ts >= from && (to == 0 || ts <= to)) return true;
      }
    }
    return false;
  }

  Future<void> _markPeriod(String userId, {required bool blocked}) async {
    final periods = <String, List<List<int>>>{};
    final raw = accountData[_blockedPeriodsType]?.content['periods'];
    if (raw is Map) {
      raw.forEach((key, value) {
        if (key is! String || value is! List) return;
        periods[key] = [
          for (final p in value)
            if (p is List && p.length == 2 && p[0] is int && p[1] is int)
              [p[0] as int, p[1] as int],
        ];
      });
    }
    final list = periods.putIfAbsent(userId, () => []);
    final now = DateTime.now().millisecondsSinceEpoch;
    if (blocked) {
      if (list.isEmpty || list.last[1] != 0) list.add([now, 0]);
    } else if (list.isNotEmpty && list.last[1] == 0) {
      list.last[1] = now;
    }
    await setAccountData(userID!, _blockedPeriodsType, {'periods': periods});
  }
}
