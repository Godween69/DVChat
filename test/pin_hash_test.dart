// SPDX-License-Identifier: AGPL-3.0-or-later

// DVChat: проверка хеширования PIN-кода блокировки.

import 'dart:convert';

import 'package:dvchat/utils/pin_hash.dart';
import 'package:flutter_test/flutter_test.dart';

String _hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

void main() {
  test('PBKDF2-HMAC-SHA256 совпадает с контрольными значениями', () {
    final password = utf8.encode('password');
    final salt = utf8.encode('salt');
    expect(
      _hex(PinHash.pbkdf2(password, salt, 1)),
      '120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b',
    );
    expect(
      _hex(PinHash.pbkdf2(password, salt, 2)),
      'ae4d0c95af6b46d32d0adff928f06dd02a303f8ef3c251dfd6e2d85a95474c43',
    );
    expect(
      _hex(PinHash.pbkdf2(password, salt, 4096)),
      'c5e478d59288c841aa530db6845c4c8d962893a001ce4e11a4963873aa98134a',
    );
  });

  test('хеш создаётся и проверяется', () async {
    final stored = await PinHash.hash('123456');
    expect(PinHash.isHashed(stored), isTrue);
    expect(PinHash.isLegacy(stored), isFalse);
    expect(await PinHash.verify('123456', stored), isTrue);
    expect(await PinHash.verify('123457', stored), isFalse);
  });

  test('прежний PIN открытым текстом ещё принимается', () async {
    expect(PinHash.isLegacy('123456'), isTrue);
    expect(await PinHash.verify('123456', '123456'), isTrue);
    expect(await PinHash.verify('654321', '123456'), isFalse);
    expect(PinHash.isValidStored('abc'), isFalse);
    expect(PinHash.isValidStored(null), isFalse);
  });
}
