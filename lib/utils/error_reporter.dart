// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

/// DVChat: ошибки только пишутся в лог. Окон «отправить разработчикам»,
/// запросов к GitHub и отправки отчётов на чужие серверы нет.
class ErrorReporter {
  final BuildContext? context;
  final String? message;

  const ErrorReporter(this.context, [this.message]);

  static const Set<String> ingoredTypes = {
    'IOException',
    'ClientException',
    'SocketException',
    'TlsException',
    'HandshakeException',
  };

  static void onFlutterError(Object error, [StackTrace? stackTrace]) {
    Logs().e('Flutter error', error, stackTrace);
  }

  Future<void> onErrorCallback(Object error, [StackTrace? stackTrace]) async {
    if (ingoredTypes.contains(error.runtimeType.toString())) return;
    Logs().e(message ?? 'Error caught', error, stackTrace);
  }
}
