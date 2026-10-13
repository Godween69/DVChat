// SPDX-FileCopyrightText: 2026 DVB Studio
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:ui';

/// DVChat работает только на русском языке.
/// Фоновые части приложения (уведомления, пуши, база данных) раньше брали язык
/// телефона и падали, если он не русский. Теперь везде используется этот язык.
const Locale appLocale = Locale('ru');
