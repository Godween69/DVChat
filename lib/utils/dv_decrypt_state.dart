// SPDX-License-Identifier: AGPL-3.0-or-later

// DVChat: идёт ли сейчас открытие ключей шифрования (после входа по ссылке).
// Пока идёт, список чатов вместо «Не удалось расшифровать сообщение» показывает
// крутилку «Расшифровка…», чтобы человек понимал, что надо чуть подождать.

import 'dart:async';

import 'package:flutter/foundation.dart';

abstract class DvDecryptState {
  static final ValueNotifier<bool> busy = ValueNotifier<bool>(false);

  static int _jobs = 0;
  static Timer? _timer;

  /// Началась настройка шифрования. Страховка: через 2 минуты индикатор гаснет сам
  static void begin() {
    _jobs++;
    _timer?.cancel();
    _timer = Timer(const Duration(minutes: 2), () {
      _jobs = 0;
      busy.value = false;
    });
    busy.value = true;
  }

  /// Настройка закончилась. Ещё несколько секунд держим индикатор: пока сообщения
  /// перечитываются новыми ключами, подпись в списке не должна мигать ошибкой
  static void end() {
    if (_jobs > 0) _jobs--;
    if (_jobs > 0) return;
    _timer?.cancel();
    _timer = Timer(const Duration(seconds: 6), () => busy.value = false);
  }
}
