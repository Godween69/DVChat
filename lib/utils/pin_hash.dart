// SPDX-License-Identifier: AGPL-3.0-or-later

// DVChat: хранение PIN-кода блокировки приложения в виде хеша PBKDF2-HMAC-SHA256 с солью.
// Формат: v2:<число итераций>:<соль base64url>:<хеш base64url>.
// Прежний формат (просто цифры открытым текстом) принимается и после первого входа заменяется.

import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

/// Тяжёлый расчёт выполняется в отдельном потоке, чтобы интерфейс не замирал
Uint8List _pbkdf2Entry(List<Object> args) =>
    PinHash.pbkdf2(args[0] as List<int>, args[1] as List<int>, args[2] as int);

abstract class PinHash {
  static const int iterations = 50000;
  static const String _prefix = 'v2:';

  static bool isHashed(String? stored) =>
      stored != null && stored.startsWith(_prefix);

  /// Прежний формат: 4 и более цифр открытым текстом
  static bool isLegacy(String? stored) =>
      stored != null && stored.length >= 4 && int.tryParse(stored) != null;

  static bool isValidStored(String? stored) =>
      isHashed(stored) || isLegacy(stored);

  /// PBKDF2-HMAC-SHA256, один блок (32 байта)
  static Uint8List pbkdf2(List<int> password, List<int> salt, int iterations) {
    final hmac = Hmac(sha256, password);
    final input = Uint8List(salt.length + 4)..setAll(0, salt);
    ByteData.sublistView(input).setUint32(salt.length, 1);
    var u = hmac.convert(input).bytes;
    final t = Uint8List.fromList(u);
    for (var i = 1; i < iterations; i++) {
      u = hmac.convert(u).bytes;
      for (var j = 0; j < t.length; j++) {
        t[j] ^= u[j];
      }
    }
    return t;
  }

  static Future<String> hash(String pin) async {
    final random = Random.secure();
    final salt = Uint8List.fromList(
      List<int>.generate(16, (_) => random.nextInt(256)),
    );
    final digest = await compute(_pbkdf2Entry, <Object>[
      utf8.encode(pin),
      salt,
      iterations,
    ]);
    return '$_prefix$iterations:${base64Url.encode(salt)}:${base64Url.encode(digest)}';
  }

  static Future<bool> verify(String pin, String? stored) async {
    if (stored == null) return false;
    if (isLegacy(stored)) {
      return _equal(utf8.encode(pin), utf8.encode(stored));
    }
    if (!isHashed(stored)) return false;
    final parts = stored.substring(_prefix.length).split(':');
    if (parts.length != 3) return false;
    final rounds = int.tryParse(parts[0]);
    final salt = _decode(parts[1]);
    final expected = _decode(parts[2]);
    if (rounds == null || rounds < 1 || salt == null || expected == null) {
      return false;
    }
    final actual = await compute(_pbkdf2Entry, <Object>[
      utf8.encode(pin),
      salt,
      rounds,
    ]);
    return _equal(actual, expected);
  }

  static Uint8List? _decode(String value) {
    try {
      return base64Url.decode(value);
    } catch (_) {
      return null;
    }
  }

  static bool _equal(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}
