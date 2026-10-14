// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// DVChat: Экран блокировки: ввод PIN-кода.

import 'dart:async';

import 'package:dvchat/l10n/l10n.dart';
import 'package:dvchat/widgets/app_lock.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:material_ui/material_ui.dart';

class LockScreen extends StatefulWidget {
  const LockScreen({super.key});

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  String? _errorText;
  bool _inputBlocked = false;
  final TextEditingController _textEditingController = TextEditingController();
  bool _checking = false;
  Timer? _blockTimer;

  @override
  void initState() {
    super.initState();
    unawaited(_syncLockout());
  }

  /// Пауза после ошибок хранится на диске, поэтому действует и после перезапуска приложения
  Future<void> _syncLockout() async {
    final wait = await AppLock.of(context).lockoutRemaining();
    if (!mounted || wait == Duration.zero) return;
    _blockFor(wait);
  }

  void _blockFor(Duration wait) {
    _blockTimer?.cancel();
    setState(() => _inputBlocked = true);
    _blockTimer = Timer(wait, () {
      if (!mounted) return;
      setState(() {
        _inputBlocked = false;
        _errorText = null;
      });
    });
  }

  static String _waitText(Duration wait) {
    final seconds = wait.inSeconds;
    if (seconds < 90) return '$seconds с';
    return '${(seconds / 60).ceil()} мин';
  }

  Future<void> tryUnlockWithBiometrics() async {
    setState(() {
      _errorText = null;
    });

    final success = await AppLock.of(context).unlockWithBiometrics();

    if (success) {
      setState(() {
        _inputBlocked = false;
        _errorText = null;
      });
      return;
    }
  }

  Future<void> tryUnlock(String text) async {
    if (_checking || _inputBlocked) return;
    final pin = text.trim();
    setState(() => _errorText = null);

    if (!RegExp(r'^\d{4,6}$').hasMatch(pin)) {
      setState(() => _errorText = L10n.of(context).invalidInput);
      _textEditingController.clear();
      return;
    }

    _checking = true;
    final result = await AppLock.of(context).tryPin(pin);
    _checking = false;
    if (!mounted) return;
    _textEditingController.clear();
    if (result.ok) {
      setState(() {
        _inputBlocked = false;
        _errorText = null;
      });
      return;
    }
    if (result.wiped) return;
    final waitText = result.wait > Duration.zero
        ? ' Подождите ${_waitText(result.wait)}.'
        : '';
    setState(() {
      _errorText =
          'Неверный PIN.$waitText Осталось попыток до выхода из аккаунта: ${result.attemptsLeft}';
    });
    if (result.wait > Duration.zero) _blockFor(result.wait);
  }

  @override
  Widget build(BuildContext context) {
    return Overlay(
      initialEntries: [
        OverlayEntry(
          builder: (context) => Scaffold(
            appBar: AppBar(
              title: Text(L10n.of(context).pleaseEnterYourPin),
              centerTitle: true,
            ),
            body: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.all(16.0),
              children: [
                Center(
                  child: Image.asset(
                    'assets/logo/mini/logo_mono_mini.png',
                    width: 128,
                    color: Theme.of(context).colorScheme.surfaceContainerHigh,
                  ),
                ),
                const SizedBox(height: 16),
                Center(
                  child: TextField(
                    controller: _textEditingController,
                    textInputAction: TextInputAction.go,
                    keyboardType: TextInputType.number,
                    obscureText: true,
                    autofocus: true,
                    textAlign: TextAlign.center,
                    readOnly: _inputBlocked,
                    onSubmitted: tryUnlock,
                    style: const TextStyle(fontSize: 40),
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(6),
                    ],
                    decoration: InputDecoration(
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(40),
                      ),
                      errorText: _errorText,
                      hintText: '✱✱✱✱',
                      hintStyle: TextStyle(
                        color: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHighest,
                      ),
                      prefix: AppLock.of(context).useBiometrics
                          ? IconButton(
                              tooltip: L10n.of(context).unlockWithBiometrics,
                              icon: FutureBuilder(
                                future: LocalAuthentication()
                                    .getAvailableBiometrics(),
                                builder: (context, snapshot) {
                                  final availableBiometrics =
                                      snapshot.data ?? [];
                                  if (availableBiometrics.contains(
                                    BiometricType.face,
                                  )) {
                                    return Icon(Icons.face_unlock_outlined);
                                  }
                                  return Icon(Icons.fingerprint_outlined);
                                },
                              ),
                              onPressed: _inputBlocked
                                  ? null
                                  : tryUnlockWithBiometrics,
                            )
                          : IconButton(
                              tooltip: L10n.of(context).reset,
                              icon: Icon(Icons.cancel_outlined),
                              onPressed: _inputBlocked
                                  ? null
                                  : _textEditingController.clear,
                            ),
                      suffix: IconButton(
                        tooltip: L10n.of(context).unlock,
                        icon: Icon(Icons.send_outlined),
                        onPressed: _inputBlocked
                            ? null
                            : () => tryUnlock(_textEditingController.text),
                      ),
                    ),
                  ),
                ),
                if (_inputBlocked)
                  const Padding(
                    padding: EdgeInsets.all(16.0),
                    child: CircularProgressIndicator.adaptive(),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _blockTimer?.cancel();
    _textEditingController.dispose();
    super.dispose();
  }
}
