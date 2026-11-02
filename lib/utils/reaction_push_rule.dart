// SPDX-License-Identifier: AGPL-3.0-or-later

// DVChat: пуши о реакциях. Сервер по умолчанию их не присылает (стандартное правило
// .m.rule.reaction гасит их, а подходящего правила «уведомлять» нет). Поэтому при включённой
// настройке добавляется своё правило dvchat.reaction (только личные чаты, где двое), а
// стандартное отключается. При выключенной настройке всё возвращается обратно.

import 'package:matrix/matrix.dart';

const String _ruleId = 'dvchat.reaction';
const String _stockRuleId = '.m.rule.reaction';

Future<void> syncReactionPushRule(Client client, {required bool on}) async {
  final rules = client.globalPushRules?.override;
  // Правила с сервера ещё не загружены: ничего не трогаем, чтобы не создать дубль
  if (rules == null) return;
  final custom = rules.where((r) => r.ruleId == _ruleId).firstOrNull;
  final stock = rules.where((r) => r.ruleId == _stockRuleId).firstOrNull;
  if (on) {
    if (custom == null) {
      await client.setPushRule(
        PushRuleKind.override,
        _ruleId,
        ['notify'],
        conditions: [
          PushCondition(
            kind: 'event_match',
            key: 'type',
            pattern: 'm.reaction',
          ),
          PushCondition(kind: 'room_member_count', is$: '2'),
        ],
      );
    } else if (!custom.enabled) {
      await client.setPushRuleEnabled(PushRuleKind.override, _ruleId, true);
    }
    if (stock != null && stock.enabled) {
      await client.setPushRuleEnabled(
        PushRuleKind.override,
        _stockRuleId,
        false,
      );
    }
  } else {
    if (custom != null && custom.enabled) {
      await client.setPushRuleEnabled(PushRuleKind.override, _ruleId, false);
    }
    if (stock != null && !stock.enabled) {
      await client.setPushRuleEnabled(
        PushRuleKind.override,
        _stockRuleId,
        true,
      );
    }
  }
}
