// Данные о людях без чтения переписки: друзья, заявки, уведомления (устройства и правила) и активность по заходам.
// Всё берётся от имени самого человека временным входом (токен живёт минуты и сразу гасится), как в очистке комнат.

const idOf = (v) => (typeof v === 'string' ? v : (v && (v.user_id || v.mxid || v.from_user || v.from || v.id)) || '');
const bool = (v) => v === true || v === 1 || v === '1';

// Друзья человека и входящие заявки. Формат ответа модуля dv_social не навязываем: берём то, что распознали.
export async function friendsOf(syn, userId, names) {
  return syn.asUser(userId, async (as) => {
    const f = await as.req('GET', '/_synapse/client/dv/friends').catch((e) => ({ error: e.message }));
    if (f.error) return { error: f.error, friends: [], requests: [], all_users: false };
    const q = await as.req('GET', '/_synapse/client/dv/requests').catch(() => ({ requests: [] }));
    const label = (id) => names.get(id)?.name || id.slice(1).split(':')[0];
    const friends = (Array.isArray(f.friends) ? f.friends : []).map((x) => ({
      user_id: idOf(x), label: label(idOf(x)), dv_id: (x && (x.dv_id || x.dvid)) || '',
      best: bool(x?.best) || bool(x?.is_best) || bool(x?.favorite),
    })).filter((x) => x.user_id);
    const requests = (Array.isArray(q.requests) ? q.requests : []).map((x) => ({ user_id: idOf(x), label: label(idOf(x)), dv_id: (x && (x.dv_id || x.dvid)) || '' })).filter((x) => x.user_id);
    return { friends, requests, all_users: Boolean(f.all_users) };
  });
}

// Правила уведомлений Matrix, которые имеет смысл показывать. mode: notify = правило включает уведомления,
// suppress = правило их подавляет (тогда «уведомлять» = правило выключено).
export const PUSH_RULES = [
  { kind: 'override', id: '.m.rule.master', mode: 'suppress', label: 'Не беспокоить: все уведомления выключены' },
  { kind: 'underride', id: '.m.rule.room.one_to_one', mode: 'notify', label: 'Личные сообщения' },
  { kind: 'underride', id: '.m.rule.encrypted_room_one_to_one', mode: 'notify', label: 'Личные сообщения в зашифрованных чатах' },
  { kind: 'underride', id: '.m.rule.message', mode: 'notify', label: 'Сообщения в группах' },
  { kind: 'underride', id: '.m.rule.encrypted', mode: 'notify', label: 'Сообщения в зашифрованных группах' },
  { kind: 'override', id: '.m.rule.invite_for_me', mode: 'notify', label: 'Приглашения в комнаты' },
  { kind: 'override', id: '.m.rule.roomnotif', mode: 'notify', label: 'Упоминание всех (@room)' },
  { kind: 'override', id: '.m.rule.member_event', mode: 'suppress', label: 'Вход и выход участников (выключено = не уведомлять)' },
  { kind: 'override', id: '.m.rule.reaction', mode: 'suppress', label: 'Реакции в открытых комнатах (выключено = уведомлять)' },
];
const RULE_BY_ID = new Map(PUSH_RULES.map((r) => [r.id, r]));
export const isPushRule = (id) => RULE_BY_ID.has(id);

const host = (u) => { try { return new URL(u).host; } catch { return ''; } };

export async function notifyOf(syn, userId) {
  return syn.asUser(userId, async (as) => {
    const [pu, ru] = await Promise.all([
      as.req('GET', '/_matrix/client/v3/pushers').catch(() => ({ pushers: [] })),
      as.req('GET', '/_matrix/client/v3/pushrules/').catch(() => ({ global: {} })),
    ]);
    const pushers = (pu.pushers || []).map((p) => ({
      app: p.app_display_name || p.app_id || '', device: p.device_display_name || '', kind: p.kind || '',
      gateway: host(p.data?.url), format: p.data?.format || '',
    }));
    const have = new Map();
    for (const k of ['override', 'underride']) for (const r of ru.global?.[k] || []) have.set(r.rule_id, r);
    const rules = PUSH_RULES.filter((d) => have.has(d.id)).map((d) => {
      const enabled = have.get(d.id).enabled !== false;
      return { id: d.id, label: d.label, notifies: d.mode === 'notify' ? enabled : !enabled };
    });
    return { pushers, rules };
  });
}

// Включить или выключить уведомления этой категории у человека
export async function setNotify(syn, userId, ruleId, notifies) {
  const d = RULE_BY_ID.get(ruleId);
  if (!d) throw Object.assign(new Error('Неизвестное правило уведомлений'), { status: 400 });
  const enabled = d.mode === 'notify' ? Boolean(notifies) : !notifies;
  return syn.asUser(userId, (as) => as.req('PUT', `/_matrix/client/v3/pushrules/global/${d.kind}/${encodeURIComponent(d.id)}/enabled`, { enabled }));
}

// Заходы: последнее появление каждого человека по его устройствам. Переписку не читает.
export async function activityOf(syn, users) {
  const out = [];
  const queue = users.filter((u) => !u.deactivated).slice(0, 80);
  async function worker() {
    for (let u = queue.shift(); u; u = queue.shift()) {
      const r = await syn.devices(u.user_id).catch(() => ({ devices: [] }));
      const seen = Math.max(0, ...(r.devices || []).map((d) => d.last_seen_ts || 0));
      out.push({ user_id: u.user_id, label: u.label, last_seen: seen || null, devices: (r.devices || []).length });
    }
  }
  await Promise.all([worker(), worker(), worker(), worker()]);
  return out.sort((a, b) => (b.last_seen || 0) - (a.last_seen || 0));
}

export function activitySummary(list, now = Date.now()) {
  const within = (ms) => list.filter((x) => x.last_seen && now - x.last_seen < ms).length;
  const dayKey = (ms) => new Date(ms + 3 * 3600e3).toISOString().slice(0, 10);   // сутки по Москве
  const byDay = new Map();
  for (const x of list) if (x.last_seen && now - x.last_seen < 14 * 86400e3) byDay.set(dayKey(x.last_seen), (byDay.get(dayKey(x.last_seen)) || 0) + 1);
  const series = [];
  for (let i = 13; i >= 0; i--) { const k = dayKey(now - i * 86400e3); series.push({ day: k, n: byDay.get(k) || 0 }); }
  return {
    total: list.length, d1: within(86400e3), d7: within(7 * 86400e3), d30: within(30 * 86400e3),
    never: list.filter((x) => !x.last_seen).length, series, recent: list.slice(0, 8),
    all: list.map((x) => ({ user_id: x.user_id, label: x.label, last_seen: x.last_seen })),
  };
}
