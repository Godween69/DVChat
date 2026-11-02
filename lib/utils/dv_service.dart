// SPDX-License-Identifier: AGPL-3.0-or-later

// DVChat: служебный аккаунт «DVChat» (от него приходят уведомления и пуши из админки).
// Это не человек: у него своя иконка, имя менять нельзя, дня рождения нет.

/// Служебный пользователь сервера (см. server/dv_social.py, NOTICE_LOCALPART)
const String dvServiceLocalpart = 'dvnotice';

/// Имя, под которым служебный аккаунт показывается людям
const String dvServiceName = 'DVChat';

/// Это служебный аккаунт «DVChat»? (по идентификатору вида @dvnotice:сервер)
bool dvIsServiceUser(String? userId) {
  if (userId == null || !userId.startsWith('@')) return false;
  final end = userId.indexOf(':');
  final local = end < 0 ? userId.substring(1) : userId.substring(1, end);
  return local == dvServiceLocalpart;
}
