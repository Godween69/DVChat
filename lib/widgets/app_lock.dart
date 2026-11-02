// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// DVChat: Блокировка приложения: следит за сворачиванием и показывает экран ввода PIN, когда он включён.
// PIN хранится только хешем. Число неверных попыток и время паузы лежат на диске (перезапуск
// приложения их не сбрасывает). После 10 неверных PIN подряд выполняется выход из аккаунта.

import 'dart:async';

import 'package:dvchat/utils/pin_hash.dart';
import 'package:dvchat/widgets/lock_screen.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';

/// Итог проверки PIN-кода
class PinCheckResult {
  const PinCheckResult({
    this.ok = false,
    this.wiped = false,
    this.wait = Duration.zero,
    this.attemptsLeft = 0,
  });

  /// PIN верный
  final bool ok;

  /// Выполнен выход из аккаунта после слишком многих ошибок
  final bool wiped;

  /// Сколько ждать до следующей попытки
  final Duration wait;

  /// Сколько попыток осталось до выхода из аккаунта
  final int attemptsLeft;
}

class AppLockWidget extends StatefulWidget {
  const AppLockWidget({
    required this.child,
    required this.pincode,
    required this.useBiometrics,
    required this.isLoggedIn,
    this.onTooManyAttempts,
    super.key,
  });

  final bool isLoggedIn, useBiometrics;
  final String? pincode;
  final Widget child;

  /// Вызывается после 10 неверных PIN подряд: выход из аккаунтов и стирание локальных данных
  final Future<void> Function()? onTooManyAttempts;

  @override
  State<AppLockWidget> createState() => AppLock();
}

class AppLock extends State<AppLockWidget> with WidgetsBindingObserver {
  static const FlutterSecureStorage _storage = FlutterSecureStorage();
  static const String _pinKey = 'dvchat.app_lock';
  static const String _failsKey = 'dvchat.app_lock_fails';
  static const String _untilKey = 'dvchat.app_lock_until';

  /// Столько неверных PIN подряд приводят к выходу из аккаунта
  static const int maxFails = 10;

  String? _pincode;
  bool _isLocked = false;
  bool _useBiometrics = false;
  bool _triedAutoBiometrics = false;

  /// Системное окно отпечатка открыто (оно само сворачивает приложение)
  bool _authenticating = false;
  DateTime? _authEndedAt;

  /// Сразу после окна отпечатка приходят запоздалые события сворачивания: их не считаем
  bool get _recentlyAuthenticated =>
      _authEndedAt != null &&
      DateTime.now().difference(_authEndedAt!) < const Duration(seconds: 2);
  bool _paused = false;
  int _fails = 0;
  int _lockedUntilMs = 0;
  bool _countersLoaded = false;

  bool get isActive => PinHash.isValidStored(_pincode) && !_paused;
  bool get useBiometrics => _useBiometrics;

  @override
  void initState() {
    _useBiometrics = widget.useBiometrics;
    _pincode = widget.pincode;
    _isLocked = isActive;
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback(_checkLoggedIn);
    unawaited(_loadCounters());
    if (isActive && useBiometrics) unlockWithBiometrics();
  }

  Future<void> _checkLoggedIn(_) async {
    if (widget.isLoggedIn) return;

    await changePincode(null);
    setState(() {
      _isLocked = false;
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_authenticating || _recentlyAuthenticated) return;
    if (isActive && state == AppLifecycleState.hidden && !_isLocked) {
      showLockScreen();
    }
    if (_isLocked &&
        state == AppLifecycleState.resumed &&
        useBiometrics &&
        !_triedAutoBiometrics) {
      unlockWithBiometrics();
    }
  }

  bool get isLocked => _isLocked;

  Future<void> changeUseBiometrics(bool useBiometrics) async {
    await _storage.write(
      key: 'dvchat.use_biometrics',
      value: useBiometrics.toString(),
    );
    _useBiometrics = useBiometrics;
    return;
  }

  /// Сохраняет новый PIN (хешем) или отключает блокировку, если передан null
  Future<void> changePincode(String? pincode) async {
    final stored = pincode == null ? null : await PinHash.hash(pincode);
    await _storage.write(key: _pinKey, value: stored);
    _pincode = stored;
    await _resetCounters();
  }

  Future<void> _loadCounters() async {
    if (_countersLoaded) return;
    try {
      final fails = await _storage.read(key: _failsKey);
      final until = await _storage.read(key: _untilKey);
      _fails = int.tryParse(fails ?? '') ?? 0;
      _lockedUntilMs = int.tryParse(until ?? '') ?? 0;
    } catch (e, s) {
      Logs().w('DVChat: не удалось прочитать счётчик попыток PIN', e, s);
    }
    _countersLoaded = true;
  }

  Future<void> _resetCounters() async {
    _fails = 0;
    _lockedUntilMs = 0;
    await _storage.write(key: _failsKey, value: null);
    await _storage.write(key: _untilKey, value: null);
  }

  /// Сколько ещё действует пауза после ошибок (на диске, переживает перезапуск)
  Future<Duration> lockoutRemaining() async {
    await _loadCounters();
    final left = _lockedUntilMs - DateTime.now().millisecondsSinceEpoch;
    return left > 0 ? Duration(milliseconds: left) : Duration.zero;
  }

  static int _delaySeconds(int fails) {
    if (fails < 3) return 0;
    if (fails == 3) return 30;
    if (fails == 4) return 60;
    if (fails == 5) return 300;
    return 900;
  }

  /// Проверяет PIN. Считает попытки на диске и после 10 ошибок подряд выходит из аккаунта.
  Future<PinCheckResult> tryPin(String pin) async {
    await _loadCounters();
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now < _lockedUntilMs) {
      return PinCheckResult(
        wait: Duration(milliseconds: _lockedUntilMs - now),
        attemptsLeft: maxFails - _fails,
      );
    }
    // Попытку записываем до проверки: иначе её можно «не засчитать», убив приложение
    _fails++;
    await _storage.write(key: _failsKey, value: '$_fails');
    final stored = _pincode;
    if (await PinHash.verify(pin, stored)) {
      // Прежний PIN хранился открытым текстом: заменяем его хешем (счётчики сбросятся)
      if (PinHash.isLegacy(stored)) {
        await changePincode(pin);
      } else {
        await _resetCounters();
      }
      if (mounted) setState(() => _isLocked = false);
      return const PinCheckResult(ok: true);
    }
    if (_fails >= maxFails) {
      await _wipe();
      return const PinCheckResult(wiped: true);
    }
    final delay = _delaySeconds(_fails);
    _lockedUntilMs = delay == 0
        ? 0
        : DateTime.now().millisecondsSinceEpoch + delay * 1000;
    await _storage.write(key: _untilKey, value: '$_lockedUntilMs');
    return PinCheckResult(
      wait: Duration(seconds: delay),
      attemptsLeft: maxFails - _fails,
    );
  }

  /// Слишком много ошибок: выход из аккаунта, блокировка снимается (защищать уже нечего)
  Future<void> _wipe() async {
    try {
      await widget.onTooManyAttempts?.call();
    } catch (e, s) {
      Logs().w('DVChat: выход после ошибок PIN завершился с ошибкой', e, s);
    }
    await _storage.write(key: _pinKey, value: null);
    _pincode = null;
    await _resetCounters();
    if (mounted) setState(() => _isLocked = false);
  }

  Future<bool> unlockWithBiometrics() async {
    // Второй запрос, пока первый открыт, не делаем
    if (_authenticating) return false;
    _authenticating = true;
    _triedAutoBiometrics = true;
    var unlocked = false;
    try {
      unlocked = await LocalAuthentication().authenticate(
        localizedReason: 'Подтвердите вход в приложение',
        persistAcrossBackgrounding: true,
        biometricOnly: true,
      );
    } catch (e, s) {
      Logs().w('DVChat: отпечаток недоступен или отменён', e, s);
    } finally {
      _authenticating = false;
      _authEndedAt = DateTime.now();
    }
    if (unlocked && mounted) {
      setState(() {
        _isLocked = false;
        _triedAutoBiometrics = false;
      });
    }
    return unlocked;
  }

  void showLockScreen() => setState(() {
    _isLocked = true;
  });

  Future<T> pauseWhile<T>(Future<T> future) async {
    _paused = true;
    try {
      return await future;
    } finally {
      _paused = false;
    }
  }

  static AppLock of(BuildContext context) =>
      Provider.of<AppLock>(context, listen: false);

  @override
  Widget build(BuildContext context) => Provider<AppLock>(
    create: (_) => this,
    child: Stack(
      fit: StackFit.expand,
      children: [widget.child, if (isLocked) const LockScreen()],
    ),
  );
}
