// SPDX-License-Identifier: AGPL-3.0-or-later

// DVChat: проверка общих списков (разбор, счётчики, «убрать у себя») и ссылки подтверждения входа.

import 'package:dvchat/utils/dv_auth.dart';
import 'package:dvchat/utils/dv_lists.dart';
import 'package:flutter_test/flutter_test.dart';

DvList _list({List<DvListItem>? items, int updated = 100}) => DvList(
  id: 'abc12345',
  title: 'Покупки',
  items: items ?? const [],
  created: 50,
  updated: updated,
);

void main() {
  group('списки', () {
    test('счётчики и «выполнен»', () {
      expect(_list().complete, isFalse, reason: 'пустой список не бывает выполненным');
      final two = _list(
        items: const [
          DvListItem(id: 'a', text: 'Молоко'),
          DvListItem(id: 'b', text: 'Хлеб', done: true),
        ],
      );
      expect(two.total, 2);
      expect(two.doneCount, 1);
      expect(two.complete, isFalse);
      final all = two.copyWith(
        items: [for (final i in two.items) i.copyWith(done: true)],
      );
      expect(all.complete, isTrue);
    });

    test('содержимое туда и обратно без потерь', () {
      final list = _list(
        items: const [
          DvListItem(id: 'a', text: 'Молоко', by: '@x:s', at: 7),
          DvListItem(id: 'b', text: 'Хлеб', done: true, by: '@x:s', doneBy: '@y:s', at: 8),
        ],
      );
      final back = DvList.fromJson(list.id, list.toJson());
      expect(back, isNotNull);
      expect(back!.title, 'Покупки');
      expect(back.created, 50);
      expect(back.updated, 100);
      expect(back.items.length, 2);
      expect(back.items[1].done, isTrue);
      expect(back.items[1].doneBy, '@y:s');
      expect(back.items[0].by, '@x:s');
    });

    test('испорченные данные не ломают разбор', () {
      expect(DvList.fromJson('x', {'title': 'a'}), isNull);
      expect(DvList.fromJson('x', {'items': []}), isNull);
      final list = DvList.fromJson('x', {
        'title': 'Дела',
        'items': [
          {'id': 'a', 'text': 'Ок'},
          {'id': '', 'text': 'без номера'},
          {'id': 'b', 'text': '   '},
          'мусор',
          {'text': 'без id'},
        ],
      });
      expect(list, isNotNull);
      expect(list!.items.length, 1);
      expect(list.items.single.text, 'Ок');
      expect(list.created, 0);
    });

    test('убранный у себя список возвращается после правки', () {
      final list = _list(updated: 100);
      expect(DvLists.isHidden(list, const {}), isFalse);
      expect(DvLists.isHidden(list, {'abc12345': 100}), isTrue);
      expect(DvLists.isHidden(list, {'abc12345': 150}), isTrue);
      expect(DvLists.isHidden(list.copyWith(updated: 101), {'abc12345': 100}), isFalse);
      expect(DvLists.isHidden(list, {'other': 999}), isFalse);
    });
  });

  group('подтверждение входа', () {
    test('ссылка dvchat://auth# разбирается', () {
      expect(parseAuthLink('dvchat://auth#eyJjIjoiQWJDZDEyMzRfLXh5eiJ9'), 'AbCd1234_-xyz');
      expect(parseAuthLink('  dvchat://auth#eyJjIjoiQWJDZDEyMzRfLXh5eiJ9  '), 'AbCd1234_-xyz');
    });

    test('чужие и повреждённые ссылки отвергаются', () {
      expect(parseAuthLink('https://auth#eyJjIjoiQWJDZDEyMzRfLXh5eiJ9'), isNull);
      expect(parseAuthLink('dvchat://login#eyJjIjoiQWJDZDEyMzRfLXh5eiJ9'), isNull);
      expect(parseAuthLink('dvchat://auth'), isNull);
      expect(parseAuthLink('dvchat://auth#eyJjIjoieCJ9'), isNull, reason: 'код короче 8 знаков');
      expect(parseAuthLink('dvchat://auth#eyJkIjoiQWJDZDEyMzQifQ'), isNull, reason: 'нет поля c');
      expect(parseAuthLink('dvchat://auth#не-base64!!'), isNull);
      expect(parseAuthLink(''), isNull);
    });
  });
}
