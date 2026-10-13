// SPDX-License-Identifier: AGPL-3.0-or-later

// DVChat: Определение администратора сервера: только он видит служебные сведения о сообщениях.

import 'package:matrix/matrix.dart';

/// DVChat: администратор сервера (служебные сведения о сообщениях видит только он).
bool isDvAdmin(Client? client) => client?.userID?.localpart == 'dima';
