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

  group('правила списков', () {
    const a = DvListItem(id: 'a', text: 'Молоко', by: '@x:s');
    test('удалять можно только свои пункты', () {
      expect(a.canRemove('@x:s'), isTrue);
      expect(a.canRemove('@y:s'), isFalse);
      expect(const DvListItem(id: 'o', text: 'старый').canRemove('@y:s'), isTrue);
    });

    test('снять отметку может только тот, кто её поставил', () {
      final ticked = a.copyWith(done: true, doneBy: '@y:s');
      expect(ticked.canUntick('@y:s'), isTrue);
      expect(ticked.canUntick('@x:s'), isFalse);
      expect(a.canUntick('@x:s'), isTrue);
    });

    test('убрать у себя можно выполненный или пустой список', () {
      expect(_list().canHide, isTrue);
      expect(_list(items: const [a]).canHide, isFalse);
      expect(_list(items: [a.copyWith(done: true)]).canHide, isTrue);
    });

    test('переименовывает создатель, у старых списков любой', () {
      expect(_list().canRename('@z:s'), isTrue);
      final mine = _list().copyWith();
      expect(mine.canRename('@z:s'), isTrue);
    });

    test('вехи: половина, остался один, готово, без повторов', () {
      DvList build(int total, int done, [List<String> notified = const []]) =>
          _list(
            items: [
              for (var i = 0; i < total; i++)
                DvListItem(id: 'i$i', text: 'п$i', done: i < done),
            ],
          ).copyWith(notified: notified);
      expect(DvLists.nextMilestone(build(4, 1)), isNull);
      expect(DvLists.nextMilestone(build(4, 2))?.kind, 'half');
      expect(DvLists.nextMilestone(build(4, 3))?.kind, 'one_left');
      expect(DvLists.nextMilestone(build(4, 4))?.kind, 'done');
      expect(DvLists.nextMilestone(build(4, 2, ['half'])), isNull);
      expect(DvLists.nextMilestone(build(1, 1))?.kind, 'done');
    });

    test('тексты уведомлений', () {
      expect(
        DvLists.pingText({'kind': 'done', 'title': 'Покупки'}),
        'Выполнил(а) список «Покупки»',
      );
      expect(
        DvLists.pingText({'kind': 'one_left', 'title': 'Покупки'}),
        'В списке «Покупки» остался один пункт',
      );
      expect(
        DvLists.pingText({'kind': 'half', 'title': 'Покупки', 'done': 2, 'total': 4}),
        'Список «Покупки»: отмечено 2 из 4',
      );
      expect(DvLists.pingText({'kind': 'half', 'title': ' '}), isNull);
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
