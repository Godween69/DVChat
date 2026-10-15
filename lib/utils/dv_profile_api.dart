// SPDX-License-Identifier: AGPL-3.0-or-later

// DVChat: день рождения и настройки профиля на сервере (модуль dv_social).

import 'package:dvchat/utils/dv_api.dart';
import 'package:matrix/matrix.dart';

class DvBirthday {
  const DvBirthday(this.day, this.month, [this.year]);

  final int day;
  final int month;
  final int? year;

  static const List<String> monthNames = [
    'Январь',
    'Февраль',
    'Март',
    'Апрель',
    'Май',
    'Июнь',
    'Июль',
    'Август',
    'Сентябрь',
    'Октябрь',
    'Ноябрь',
    'Декабрь',
  ];

  static const List<String> _genitive = [
    'января',
    'февраля',
    'марта',
    'апреля',
    'мая',
    'июня',
    'июля',
    'августа',
    'сентября',
    'октября',
    'ноября',
    'декабря',
  ];

  String get text {
    final base = '$day ${_genitive[month - 1]}';
    return year == null ? base : '$base $year';
  }
}

abstract class DvProfiles {
  static final Map<String, DvBirthday?> _birthdays = {};
  static bool? _notify;

  static DvBirthday? cachedBirthday(String userId) => _birthdays[userId];

  /// Уведомления о днях рождения друзей: по умолчанию включены
  static bool get notifyCached => _notify ?? true;

  /// Загружает профили (себя и друзей) и запоминает в памяти
  static Future<void> load(Client client, List<String> ids) async {
    final json = await DvApi(client).post('profile/get', {'user_ids': ids});
    final profiles = json['profiles'];
    if (profiles is! Map) return;
    for (final entry in profiles.entries) {
      final id = entry.key.toString();
      final value = entry.value;
      if (value is! Map) continue;
      final b = value['birthday'];
      if (b is Map && b['day'] is int && b['month'] is int) {
        _birthdays[id] = DvBirthday(
          b['day'] as int,
          b['month'] as int,
          b['year'] as int?,
        );
      } else {
        _birthdays[id] = null;
      }
      if (id == client.userID && value['notify_birthdays'] is bool) {
        _notify = value['notify_birthdays'] as bool;
      }
    }
  }

  static Future<void> saveBirthday(Client client, DvBirthday? birthday) async {
    await DvApi(client).post('profile/set', {
      'birthday': birthday == null
          ? null
          : {
              'day': birthday.day,
              'month': birthday.month,
              if (birthday.year != null) 'year': birthday.year,
            },
    });
    _birthdays[client.userID ?? ''] = birthday;
  }

  static Future<void> saveNotify(Client client, {required bool value}) async {
    await DvApi(client).post('profile/set', {'notify_birthdays': value});
    _notify = value;
  }
}
