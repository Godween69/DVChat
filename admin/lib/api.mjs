// Маршруты админки. Каждая изменяющая операция пишется в журнал (без секретов).
import { writeFileSync, appendFileSync, mkdirSync, readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { generateSecret } from './auth.mjs';
import * as G from './groups.mjs';
import { clearRoom } from './clear.mjs';
import { readLisa, saveLisa, applyGlobal, applyUser, applyAllowBulk, lisaView, lisaConfigured, readPanel, applyModels, catalogView, purposeTags, summarizeGames, GAME_STATS_TYPE, explainError, recommend, summarize, readGuide, saveGuide, GUIDE_MAX } from './lisa.mjs';
import { friendsOf, notifyOf, setNotify, isPushRule, PUSH_RULES, activityOf, activitySummary } from './people.mjs';
import { renameSync, unlinkSync, existsSync, statSync } from 'node:fs';

export class HttpError extends Error {
  constructor(status, message, code = 'ERROR') { super(message); this.status = status; this.code = code; }
}
const bad = (m) => new HttpError(400, m, 'BAD_REQUEST');

const USERNAME = /^[a-z0-9][a-z0-9._=-]{1,31}$/;
const MXID = /^@[a-z0-9._=\/+-]+:[A-Za-z0-9.-]+(:\d+)?$/;
const ROOMID = /^![A-Za-z0-9._~\-+=\/]+(:[A-Za-z0-9.-]+)?$/;

export function makeLink(code) {
  return 'dvchat://login#' + Buffer.from(JSON.stringify({ c: code }), 'utf8').toString('base64url');
}

// Ответ модуля issue может называть поле по-разному: берём первое подходящее
const pickCode = (r) => r?.code || r?.c || r?.login_code || '';

// Список людей из dv_social: ищем массив объектов с mxid и dv_id, формат не навязываем
export function normalizeDvPeople(json) {
  const out = new Map();
  const walk = (v) => {
    if (Array.isArray(v)) return v.forEach(walk);
    if (v && typeof v === 'object') {
      const uid = v.user_id || v.mxid || v.id;
      const dv = v.dv_id || v.dvid;
      if (typeof uid === 'string' && uid.startsWith('@') && dv) out.set(uid, String(dv));
      Object.values(v).forEach((x) => typeof x === 'object' && walk(x));
    }
  };
  walk(json);
  return out;
}

// Файл dvchat.env: известные поля правятся, остальные строки (комментарии, другие ключи) сохраняются как есть.
export const MASK = '••••••••';
// Адреса шлюза и канала обновлений могут содержать секрет в пути: наружу (в браузер) он отдаётся только по кнопке «Показать»
export const maskUrl = (u) => { const m = /^(https:\/\/[^/]+)\/.+$/.exec(u || ''); return m ? m[1] + '/' + MASK : (u || ''); };
// Вид комнаты: одно определение для обзора и вкладок «Комнаты» и «Группы», чтобы числа везде совпадали
const SUPPORT_RE = /\s@[\w.\-]+\s\(\d{6,}\)\s*$/;
export function roomKind(x, service) {
  if (x.room_id === service) return 'service';
  if (x.joined_members === 0) return 'empty';
  if (x.joined_members > 2) return 'group';
  if (SUPPORT_RE.test(x.name || '')) return 'support';
  if (x.name && x.joined_members > 1) return 'group';   // группа с названием, где пока двое
  return 'direct';
}

export function parseEnv(text) {
  const kv = {};
  for (const l of String(text || '').split('\n')) { const m = /^([A-Z][A-Z0-9_]*)=(.*)$/.exec(l); if (m) kv[m[1]] = m[2]; }
  return kv;
}
const KEYS = { homeserver: 'DVCHAT_HOMESERVER', pushGateway: 'DVCHAT_PUSH_GATEWAY', updateUrl: 'DVCHAT_UPDATE_URL' };

export function envText(v, existing = '') {
  const clean = (x, name) => {
    const s = String(x ?? '').trim();
    if (/[\r\n"'\\\s]/.test(s)) throw bad(`Поле ${name}: пробелы, кавычки и переводы строк недопустимы`);
    return s;
  };
  const old = parseEnv(existing);
  const host = clean(v.homeserver, 'Адрес сервера');
  if (!/^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?(:\d+)?$/.test(host)) throw bad('Адрес сервера: укажите имя хоста без https://, например chat.example.org');
  const url = (x, name, prev) => {
    let s = clean(x, name);
    if (s && prev && s === maskUrl(prev)) return prev;      // маску не трогали: остаётся прежний адрес с секретом
    if (!s) return '';
    if (!/^https:\/\/[A-Za-z0-9.-]+(:\d+)?(\/[A-Za-z0-9._~\-\/]*)?$/.test(s)) throw bad(`Поле ${name}: нужен адрес вида https://…`);
    return s;
  };
  const next = { DVCHAT_HOMESERVER: host, DVCHAT_PUSH_GATEWAY: url(v.pushGateway, 'Шлюз уведомлений', old.DVCHAT_PUSH_GATEWAY), DVCHAT_UPDATE_URL: url(v.updateUrl, 'Канал обновлений', old.DVCHAT_UPDATE_URL) };
  const lines = [];
  const done = new Set();
  for (const l of String(existing || '').split('\n')) {
    const m = /^([A-Z][A-Z0-9_]*)=/.exec(l);
    if (m && m[1] in next) { done.add(m[1]); if (next[m[1]]) lines.push(`${m[1]}=${next[m[1]]}`); }
    else if (l !== '' || lines.length) lines.push(l);
  }
  while (lines.length && lines[lines.length - 1] === '') lines.pop();
  if (!lines.length) lines.push('# Настройки сборки DVChat. Создано мастером админки. В git не добавлять.');
  for (const k of Object.values(KEYS)) if (!done.has(k) && next[k]) lines.push(`${k}=${next[k]}`);
  return lines.join('\n') + '\n';
}

// Вид файла для показа: адреса с секретом и значения неизвестных ключей скрыты
export function maskedEnvText(text) {
  return String(text || '').split('\n').map((l) => {
    const m = /^([A-Z][A-Z0-9_]*)=(.*)$/.exec(l);
    if (!m) return l;
    if (m[1] === 'DVCHAT_HOMESERVER') return l;
    if (m[1] === 'DVCHAT_PUSH_GATEWAY' || m[1] === 'DVCHAT_UPDATE_URL') return `${m[1]}=${maskUrl(m[2])}`;
    return `${m[1]}=<скрыто>`;
  }).join('\n');
}

// Ошибка модуля dv_social: 404 без кода значит, что модуль на сервере старый
const dvFail = (e) => {
  if (e.status === 404 && e.errcode !== 'DV_NOT_FOUND') throw new HttpError(502, 'Модуль dv_social на сервере без этих действий: обновите серверный модуль (скрипт dvserver-deploy.sh)', 'DV_OLD');
  throw new HttpError(e.status === 403 ? 403 : e.status === 404 ? 404 : 502, e.message, e.errcode || 'ERROR');
};

export function createApi({ cfg, syn, audit }) {
  let adminId = '';
  const me = async () => (adminId ||= (await syn.whoami()).user_id);
  const serverName = async () => (await me()).split(':').slice(1).join(':');
  const fullId = async (u) => {
    const s = String(u || '').trim();
    if (MXID.test(s)) return s;
    if (USERNAME.test(s)) return `@${s}:${await serverName()}`;
    throw bad('Некорректное имя пользователя');
  };
  const roomId = (r) => { if (!ROOMID.test(r)) throw bad('Некорректный номер комнаты'); return r; };
  const confirmName = (given, expected) => {
    if (!given || String(given).trim() !== String(expected)) throw bad('Подтверждение не совпало: введите имя точно');
  };

  // Служебная комната: в ней состоит только администратор, она нужна для входа в группы без приглашения
  const svcFile = join(cfg.dataDir, 'service_room.json');
  let svc = '';
  const svcPeek = () => { if (svc) return svc; try { svc = JSON.parse(readFileSync(svcFile, 'utf8')).room_id || ''; } catch { svc = ''; } return svc; };
  async function serviceRoom() {
    const admin = await me();
    const known = svcPeek();
    if (known) {
      const m = await syn.roomMembers(known).catch(() => null);
      if (m && (m.members || []).includes(admin)) {
        if ((m.members || []).some((x) => x !== admin)) throw new HttpError(500, 'Служебная комната админки повреждена: в ней посторонние. Удалите её на вкладке «Комнаты» и повторите.');
        return known;
      }
    }
    const r = await syn.createRoom({ name: 'dvchat-admin-service', topic: 'Служебная комната админки DVChat. Не удалять, никого не приглашать.', preset: 'private_chat', visibility: 'private' });
    mkdirSync(dirname(svcFile), { recursive: true });
    writeFileSync(svcFile, JSON.stringify({ room_id: r.room_id }), { mode: 0o600 });
    svc = r.room_id;
    return svc;
  }
  const gctx = async () => ({ syn, adminId: await me(), serviceRoom });

  // Все люди (в том числе удалённые) для подписей комнат
  async function usersMap() {
    const m = new Map(); let from;
    for (let i = 0; i < 10; i++) {
      const r = await syn.users({ limit: 100, from, deactivated: 'true', guests: 'false' });
      for (const u of r.users || []) m.set(u.name, { name: u.displayname || u.name.slice(1).split(':')[0], deactivated: Boolean(u.deactivated) });
      if (!r.next_token) break; from = r.next_token;
    }
    return m;
  }
  const personLabel = (map, id) => { const u = map.get(id); const base = u?.name || id.slice(1).split(':')[0]; return u?.deactivated ? `${base} (удалён)` : base; };

  async function dvPeople() {
    try { return normalizeDvPeople(await syn.dvFriends()); } catch { return new Map(); }
  }

  async function issueLink(userId, { password, passphrase, ttl }) {
    const body = { user_id: userId, password, ttl_hours: Math.min(72, Math.max(1, Number(ttl) || 24)) };
    if (passphrase) body.passphrase = passphrase;
    const r = await syn.dvIssue(body);
    const code = pickCode(r);
    if (!code) throw new HttpError(502, 'Модуль выдачи кодов не вернул код. Проверьте модуль dv_social.');
    return { code, link: makeLink(code), ttl_hours: body.ttl_hours };
  }

  const activityCache = { at: 0, data: null };
  const gamesCache = { at: 0, data: null };

  const routes = {
    'GET /api/overview': async () => {
      const [ver, users, rooms] = await Promise.all([
        syn.version().catch(() => ({})), syn.users({ limit: 1, deactivated: 'true' }).catch(() => ({})),
        syn.rooms({ limit: 1 }).catch(() => ({})),
      ]);
      const all = await syn.users({ limit: 100, guests: 'false' });
      const grp = await syn.rooms({ limit: 500 }).catch(() => ({ rooms: [] }));
      const list = grp.rooms || [];
      const service = svcPeek();
      const real = list.filter((r) => r.room_id !== service);
      const kindOf = (r) => roomKind(r, service);
      const out = {
        server_name: await serverName(), synapse: ver.server_version || '',
        users_active: all.total ?? 0, users_with_deactivated: users.total ?? 0,
        rooms_total: rooms.total_rooms ?? 0,
        groups_list: real.filter((r) => kindOf(r) === 'group').map((r) => ({ name: r.name || 'без названия', members: r.joined_members, encrypted: Boolean(r.encryption) })),
        rooms_groups: real.filter((r) => kindOf(r) === 'group').length,
        rooms_orphans: real.filter((r) => kindOf(r) === 'empty').length,
        rooms_kinds: {
          groups: real.filter((r) => kindOf(r) === 'group').length,
          support: real.filter((r) => kindOf(r) === 'support').length,
          direct: real.filter((r) => kindOf(r) === 'direct').length,
          empty: real.filter((r) => kindOf(r) === 'empty').length,
          encrypted: real.filter((r) => r.encryption).length,
        },
      };
      // Заходы людей (по устройствам, переписку не читает); кэш на минуту, чтобы обзор открывался быстро
      if (!activityCache.data || Date.now() - activityCache.at > 60_000) {
        const people = (all.users || []).map((u) => ({ user_id: u.name, deactivated: Boolean(u.deactivated), label: u.displayname || u.name.slice(1).split(':')[0] }));
        activityCache.data = activitySummary(await activityOf(syn, people)); activityCache.at = Date.now();
      }
      out.activity = activityCache.data;
      // Лиза: жива ли, какая модель отвечает, расход за сегодня и за 7 дней
      if (cfg.lisaPanelDir) {
        const map = await usersMap();
        const st = readPanel(cfg.lisaPanelDir, 'state.json'), sts = readPanel(cfg.lisaPanelDir, 'stats.json');
        const sum = sts ? summarize(sts.data) : null;
        out.lisa = { connected: Boolean(st), alive: Boolean(st) && st.age < 180, age: st ? Math.round(st.age) : null, active: st?.data.active || null,
          models_up: st ? st.data.models.filter((m) => m.up).length : 0, models_total: st ? st.data.models.length : 0, key_ok: st?.data.key?.ok ?? null,
          today: sum?.totals.today || null, d7: sum?.totals.d7 || null, series: sum?.series || [],
          by_user: (sum?.users || []).map((u) => ({ label: personLabel(map, u.user), n: u.today.n, cost: u.today.cost, n7: u.d7.n, cost7: u.d7.cost })).filter((u) => u.n7 || u.n) };
      }
      return out;
    },

    'GET /api/users': async ({ query }) => {
      const r = await syn.users({ limit: 100, from: query.from, name: query.q, guests: 'false', deactivated: query.deactivated === '1' ? 'true' : 'false' });
      const dv = await dvPeople();
      const root = await me();
      return {
        total: r.total, next: r.next_token ?? null, root,
        users: (r.users || []).map((u) => ({
          user_id: u.name, displayname: u.displayname || '', admin: Boolean(u.admin),
          deactivated: Boolean(u.deactivated), created: u.creation_ts, dv_id: dv.get(u.name) || '', root: u.name === root,
        })),
      };
    },

    'POST /api/users': async ({ body }) => {
      const name = String(body.username || '').trim().toLowerCase();
      if (!USERNAME.test(name)) throw bad('Имя: 2–32 символа, латиница, цифры, точка, дефис, подчёркивание');
      const userId = await fullId(name);
      const exists = await syn.user(userId).then(() => true, (e) => (e.status === 404 ? false : Promise.reject(e)));
      if (exists) throw new HttpError(409, 'Такой пользователь уже есть', 'EXISTS');
      const password = generateSecret(24);
      const passphrase = generateSecret(24).replace(/(.{4})(?=.)/g, '$1-');
      await syn.putUser(userId, { password, admin: false, displayname: String(body.displayname || name).slice(0, 64), logout_devices: false });
      const issued = await issueLink(userId, { password, passphrase, ttl: body.ttl_hours });
      audit('user.create', { user: userId });
      return { user_id: userId, ...issued };
    },

    'POST /api/users/link': async ({ body }) => {
      const userId = await fullId(body.user_id);
      await syn.user(userId);
      const password = generateSecret(24);
      // Кодовая фраза человека уже хранится на сервере: берём её (от его имени), иначе создаём новую
      let passphrase = null;
      try { passphrase = (await syn.asUser(userId, (as) => as.dvKeysPhrase())).phrase || null; }
      catch (e) { if (e.status !== 404) throw e; }
      if (!passphrase) passphrase = generateSecret(24).replace(/(.{4})(?=.)/g, '$1-');
      await syn.putUser(userId, { password, logout_devices: false });
      const issued = await issueLink(userId, { password, passphrase, ttl: body.ttl_hours });
      audit('user.link', { user: userId });
      return { user_id: userId, ...issued };
    },

    'POST /api/users/logout-all': async ({ body }) => {
      const userId = await fullId(body.user_id);
      const d = await syn.devices(userId);
      const ids = (d.devices || []).map((x) => x.device_id);
      if (ids.length) await syn.deleteDevices(userId, ids);
      audit('user.logout_all', { user: userId, devices: ids.length });
      return { devices_removed: ids.length };
    },

    'POST /api/users/logout-others': async ({ body }) => {
      const userId = await fullId(body.user_id);
      const d = await syn.devices(userId);
      const all = (d.devices || []).map((x) => x.device_id);
      if (!all.includes(body.keep)) throw bad('Это устройство не найдено у человека');
      const ids = all.filter((x) => x !== body.keep);
      if (ids.length) await syn.deleteDevices(userId, ids);
      audit('user.logout_others', { user: userId, devices: ids.length });
      return { devices_removed: ids.length };
    },

    'POST /api/users/devices': async ({ body }) => {
      const d = await syn.devices(await fullId(body.user_id));
      return { devices: (d.devices || []).map((x) => ({ id: x.device_id, name: x.display_name || '', last_seen: x.last_seen_ts, ip: x.last_seen_ip || '' })) };
    },

    'POST /api/users/rename': async ({ body }) => {
      const userId = await fullId(body.user_id);
      await syn.putUser(userId, { displayname: String(body.displayname || '').slice(0, 64) });
      audit('user.rename', { user: userId });
      return { ok: true };
    },

    'POST /api/users/rooms': async ({ body }) => {
      const userId = await fullId(body.user_id);
      const jr = await syn.joinedRooms(userId);
      const out = [];
      for (const id of (jr.joined_rooms || []).slice(0, 100)) {
        const r = await syn.room(id).catch(() => null);
        if (r) out.push({ room_id: id, name: r.name || '', members: r.joined_members });
      }
      return { rooms: out };
    },

    'POST /api/users/deactivate': async ({ body }) => {
      const userId = await fullId(body.user_id);
      if (userId === (await me())) throw bad('Нельзя удалить учётную запись самой админки');
      const u = await syn.user(userId);
      // Корневой админ (учётная запись самой панели) неприкосновенен; обычного администратора удалить можно
      confirmName(body.confirm, userId.slice(1).split(':')[0]);
      // Сначала выводим человека из всех групп и чатов, чтобы в них не оставался удалённый аккаунт
      const plan = await G.userRoomsPlan(syn, userId);
      if (plan.blockers.length) throw bad('Человек единственный владелец в: ' + plan.blockers.join(', ') + '. Назначьте другого владельца и повторите.');
      const left = await G.leaveRooms(syn, userId, plan.leave);
      await syn.deactivate(userId, body.erase === true);
      audit('user.deactivate', { user: userId, erase: body.erase === true, left });
      return { ok: true, left };
    },

    'GET /api/rooms': async ({ query }) => {
      const r = await syn.rooms({ limit: 500, search_term: query.q, order_by: 'joined_members', dir: 'b' });
      const map = await usersMap();
      const service = svcPeek();
      const list = r.rooms || [];
      const rooms = [];
      for (let i = 0; i < list.length; i += 10) {
        rooms.push(...await Promise.all(list.slice(i, i + 10).map(async (x) => {
          const mem = x.joined_members > 0 ? ((await syn.roomMembers(x.room_id).catch(() => ({ members: [] }))).members || []) : [];
          const people = mem.map((id) => ({ id, label: personLabel(map, id), deleted: Boolean(map.get(id)?.deactivated) }));
          const names = people.map((p) => p.label);
          // Кто вышел и кого пригласили, но он ещё не зашёл (по состоянию комнаты; только для небольших комнат)
          let left = [], invited = [];
          if (x.joined_members > 0 && x.joined_members <= 2) {
            const st = await syn.roomState(x.room_id).catch(() => ({ state: [] }));
            for (const e of st.state || []) {
              if (e.type !== 'm.room.member') continue;
              const who = personLabel(map, e.state_key);
              if (e.content?.membership === 'leave' || e.content?.membership === 'ban') left.push(who);
              if (e.content?.membership === 'invite') invited.push(who);
            }
          }
          // Обращение в поддержку: комната с названием «Имя @логин (ID)», создаётся модулем при обращении человека
          const support = /\s@[\w.\-]+\s\(\d{6,}\)\s*$/.test(x.name || '');
          const kind = roomKind(x, service);
          let label = kind === 'service' ? 'Служебная комната админки' : (x.name || '');
          if (kind === 'support') label = 'Поддержка: ' + (x.name || '');
          else if (!label) {
            if (kind === 'empty') label = 'Пустая комната (никого внутри)';
            else if (kind === 'group') label = 'Группа без названия: ' + names.slice(0, 4).join(', ') + (names.length > 4 ? '…' : '');
            else if (names.length === 1) label = 'Личный чат: ' + names[0] + (left.length ? ' (собеседник вышел: ' + left.join(', ') + ')' : invited.length ? ' (собеседник приглашён, ещё не зашёл)' : ' (собеседника нет)');
            else label = 'Личный чат: ' + names.join(' и ');
          }
          const note = [left.length ? 'вышли: ' + left.join(', ') : '', invited.length ? 'приглашены, не зашли: ' + invited.join(', ') : ''].filter(Boolean).join('; ');
          return { room_id: x.room_id, name: x.name || '', label, kind, members: x.joined_members, local_members: x.joined_local_members,
            creator: x.creator, encrypted: Boolean(x.encryption), people, note, has_deleted: people.some((p) => p.deleted) };
        })));
      }
      let out = rooms;
      if (query.filter === 'empty' || query.filter === 'orphans') out = rooms.filter((x) => x.kind === 'empty');
      if (query.filter === 'groups') out = rooms.filter((x) => x.kind === 'group');
      if (query.filter === 'direct') out = rooms.filter((x) => x.kind === 'direct');
      if (query.filter === 'support') out = rooms.filter((x) => x.kind === 'support');
      if (query.filter === 'deleted') out = rooms.filter((x) => x.has_deleted);
      return { total: r.total_rooms, rooms: out, empty_count: rooms.filter((x) => x.kind === 'empty').length };
    },

    'POST /api/rooms/delete': async ({ body }) => {
      const id = roomId(body.room_id);
      if (id === svcPeek()) throw bad('Служебную комнату админки удалять нельзя: она нужна для работы с группами');
      const room = await syn.room(id);
      confirmName(body.confirm, room.name || 'удалить');
      const r = await syn.deleteRoom(id, true);
      audit('room.delete', { room: id });
      return { delete_id: r.delete_id || '' };
    },

    'POST /api/rooms/clear': async ({ body }) => {
      const id = roomId(body.room_id);
      if (id === svcPeek()) throw bad('Служебную комнату админки очищать не нужно: в ней нет переписки');
      if (String(body.confirm || '').trim() !== 'очистить') throw bad('Подтверждение не совпало: введите слово «очистить»');
      await syn.room(id);
      const r = await clearRoom(syn, id);
      audit('room.clear', { room: id, ...r });
      return { ok: true, ...r };
    },

    // Подружить двух людей сразу и создать их личный чат (для тех, кому трудно с интерфейсом)
    'POST /api/people/befriend': async ({ body }) => {
      const a = await fullId(body.a), b = await fullId(body.b);
      if (a === b) throw bad('Нужны два разных человека');
      const r = await syn.dvAdmin('befriend', { a, b, chat: body.chat !== false }).catch(dvFail);
      audit('people.befriend', { a, b, status: r.status, chat: Boolean(r.room_id), chat_existed: Boolean(r.chat_existed) });
      return r;
    },

    // Убрать двоих из друзей друг у друга (чат и история остаются)
    'POST /api/people/unfriend': async ({ body }) => {
      const a = await fullId(body.a), b = await fullId(body.b);
      if (a === b) throw bad('Нужны два разных человека');
      const r = await syn.dvAdmin('unfriend', { a, b }).catch(dvFail);
      audit('people.unfriend', { a, b, status: r.status });
      return r;
    },

    // Служебный пуш: сообщение от «DVChat» в личном чате получателя, приходит обычным уведомлением
    'POST /api/people/push': async ({ body }) => {
      const text = String(body.text || '').trim();
      if (!text || text.length > 500) throw bad('Текст от 1 до 500 знаков');
      if (!Array.isArray(body.user_ids) || !body.user_ids.length || body.user_ids.length > 50) throw bad('Выберите от 1 до 50 получателей');
      const ids = [];
      for (const u of body.user_ids) ids.push(await fullId(u));
      const r = await syn.dvAdmin('notify', { user_ids: ids, text }).catch(dvFail);
      audit('people.push', { sent: r.sent.length, failed: r.failed.length, length: text.length });
      return r;
    },

    'POST /api/rooms/delete-empty': async ({ body }) => {
      const service = svcPeek();
      const r = await syn.rooms({ limit: 500 });
      const empties = (r.rooms || []).filter((x) => x.joined_members === 0 && x.room_id !== service);
      if (String(body.confirm || '').trim() !== String(empties.length)) throw bad('Подтверждение не совпало: введите число пустых комнат');
      let n = 0;
      for (const x of empties) { try { await syn.deleteRoom(x.room_id, true); n++; } catch { /* пропускаем */ } }
      audit('room.delete_empty', { count: n });
      return { deleted: n };
    },

    'GET /api/groups': async () => {
      const r = await syn.rooms({ limit: 500, order_by: 'joined_members', dir: 'b' });
      const service = svcPeek();
      return { groups: (r.rooms || []).filter((x) => roomKind(x, service) === 'group')
        .map((x) => ({ room_id: x.room_id, name: x.name || '', members: x.joined_members, encrypted: Boolean(x.encryption) })), ladder: G.LADDER };
    },

    'POST /api/groups': async ({ body }) => {
      const name = String(body.name || '').trim();
      if (!name || name.length > 80) throw bad('Название группы: от 1 до 80 символов');
      const owner = await fullId(body.owner);
      await syn.user(owner);
      const members = [];
      for (const m of body.members || []) members.push(await fullId(m));
      const r = await G.createGroup(await gctx(), { name, topic: String(body.topic || '').slice(0, 200), owner, members, encrypted: body.encrypted !== false });
      audit('group.create', { room: r.room_id, owner, members: members.length });
      return r;
    },

    'POST /api/groups/details': async ({ body }) => G.groupDetails(syn, roomId(body.room_id)),

    'POST /api/groups/perms': async ({ body }) => {
      const userId = await fullId(body.user_id);
      const r = await G.setMemberPerms(await gctx(), roomId(body.room_id), userId, body.perms || {});
      audit('group.perms', { room: body.room_id, user: userId, level: r.level });
      return r;
    },

    'POST /api/groups/add': async ({ body }) => {
      const ids = []; for (const m of body.members || []) ids.push(await fullId(m));
      const r = await G.addMembers(await gctx(), roomId(body.room_id), ids);
      audit('group.add', { room: body.room_id, users: ids.length });
      return r;
    },

    'POST /api/groups/remove': async ({ body }) => {
      const userId = await fullId(body.user_id);
      await G.removeMember(await gctx(), roomId(body.room_id), userId);
      audit('group.remove', { room: body.room_id, user: userId });
      return { ok: true };
    },

    // Статистика игр: из профилей людей (account data dv.game_stats), читается админским запросом, без входа от имени человека
    'GET /api/games/stats': async () => {
      if (!gamesCache.data || Date.now() - gamesCache.at > 60_000) {
        const r = await syn.users({ limit: 100, guests: 'false', deactivated: 'false' });
        const people = (r.users || []).slice(0, 80).map((u) => ({ user_id: u.name, label: u.displayname || u.name.slice(1).split(':')[0] }));
        const rows = []; const queue = people.slice();
        const worker = async () => { for (let p = queue.shift(); p; p = queue.shift()) {
          const d = await syn.accountData(p.user_id).catch(() => null);
          rows.push({ ...p, data: d?.account_data?.global?.[GAME_STATS_TYPE] });
        } };
        await Promise.all([worker(), worker(), worker(), worker()]);
        gamesCache.data = { ...summarizeGames(rows), people_total: people.length }; gamesCache.at = Date.now();
      }
      return gamesCache.data;
    },

    'GET /api/lisa': async () => {
      if (!lisaConfigured(cfg.lisaConfigPath)) return { enabled: false };
      const r = await syn.users({ limit: 200, guests: 'false', deactivated: 'false' });
      const dv = await dvPeople();
      const people = (r.users || []).map((u) => ({ user_id: u.name, displayname: u.displayname || '', dv_id: dv.get(u.name) || '' }));
      return lisaView(readLisa(cfg.lisaConfigPath), people);
    },

    // Модели, ключ, деньги: файлы пишет сама Лиза (state.json, catalog.json, stats.json, requests.json)
    'GET /api/lisa/overview': async () => {
      if (!lisaConfigured(cfg.lisaConfigPath)) return { enabled: false };
      const c = readLisa(cfg.lisaConfigPath);
      const dir = cfg.lisaPanelDir;
      const st = dir ? readPanel(dir, 'state.json') : null;
      const sts = dir ? readPanel(dir, 'stats.json') : null;
      const cat = dir ? readPanel(dir, 'catalog.json') : null;
      const map = await usersMap();
      const label = (id) => personLabel(map, id);
      const sum = sts ? summarize(sts.data) : null;
      if (sum) sum.users = sum.users.map((u) => ({ ...u, label: label(u.user) }));
      const prices = new Map((st?.data.models || []).map((m) => [m.id, m]));
      const catById = new Map(catalogView(cat?.data.models || []).map((m) => [m.id, m]));
      return {
        enabled: true, panel: Boolean(dir),
        state: st ? { ...st.data, age: Math.round(st.age) } : null,
        models: (c.models || []).map((m) => ({ id: m.id, vision: Boolean(m.vision), up: prices.get(m.id)?.up ?? null, error: prices.get(m.id)?.error || null, error_info: prices.get(m.id)?.error ? explainError(prices.get(m.id).error) : null, pending: !prices.has(m.id), tags: catById.get(m.id)?.tags || purposeTags({ id: m.id, vision: Boolean(m.vision) }),
          price_in: prices.get(m.id)?.price_in ?? null, price_out: prices.get(m.id)?.price_out ?? null })),
        catalog: Boolean(cat), engines: (dir ? readPanel(dir, 'engines.json') : null)?.data.engines || null, stats: sum, stats_age: sts ? Math.round(sts.age) : null,
        settings: lisaView(c, []).settings, key_warn_usd: c.key_warn_usd ?? 2,
      };
    },

    // Каталог OpenRouter: поиск, фильтр «бесплатные / платные», «понимают картинки», сортировка по цене
    'GET /api/lisa/catalog': async ({ query }) => {
      const cat = cfg.lisaPanelDir ? readPanel(cfg.lisaPanelDir, 'catalog.json') : null;
      if (!cat) return { models: [], ready: false };
      const q = String(query.q || '').trim().toLowerCase();
      let list = catalogView(cat.data.models).filter((m) => !q || m.id.toLowerCase().includes(q) || String(m.name).toLowerCase().includes(q));
      if (query.kind === 'free') list = list.filter((m) => m.free);
      if (query.kind === 'paid') list = list.filter((m) => !m.free);
      if (query.vision === '1') list = list.filter((m) => m.vision);
      const byPrice = (a, b) => (a.price_out ?? 1e9) - (b.price_out ?? 1e9) || a.id.localeCompare(b.id);
      list.sort(query.sort === 'name' ? (a, b) => a.id.localeCompare(b.id) : byPrice);
      const offset = Math.max(0, Number(query.offset) || 0), limit = Math.min(100, Math.max(1, Number(query.limit) || 30));
      const rec = offset === 0 && !q && !query.kind && query.vision !== '1' ? recommend(catalogView(cat.data.models)) : undefined;
      return { models: list.slice(offset, offset + limit), recommend: rec, ready: true, total: cat.data.models.length, matched: list.length, free_total: catalogView(cat.data.models).filter((m) => m.free).length };
    },

    'GET /api/lisa/requests': async ({ query }) => {
      const r = cfg.lisaPanelDir ? readPanel(cfg.lisaPanelDir, 'requests.json') : null;
      if (!r) return { items: [], days: 0 };
      const map = await usersMap();
      let items = r.data.items.map((x) => ({ ...x, label: personLabel(map, x.user) }));
      if (query.user) items = items.filter((x) => x.user === query.user);
      return { items: items.slice(0, 200), days: r.data.days };
    },

    'GET /api/lisa/guide': async () => {
      if (!cfg.lisaGuidePath) return { enabled: false };
      return { enabled: true, text: readGuide(cfg.lisaGuidePath), max: GUIDE_MAX };
    },

    'POST /api/lisa/guide': async ({ body }) => {
      if (!cfg.lisaGuidePath) throw bad('Файл справочника не подключён');
      saveGuide(cfg.lisaGuidePath, body.text);
      audit('lisa.guide', { length: String(body.text).length });
      return { ok: true };
    },

    'POST /api/lisa/models': async ({ body }) => {
      if (!lisaConfigured(cfg.lisaConfigPath)) throw bad('Файл настроек Лизы не подключён');
      const cat = cfg.lisaPanelDir ? readPanel(cfg.lisaPanelDir, 'catalog.json') : null;
      const c = applyModels(readLisa(cfg.lisaConfigPath), body.models, cat?.data.models);
      saveLisa(cfg.lisaConfigPath, c);
      audit('lisa.models', { models: body.models });
      return { ok: true };
    },

    'POST /api/lisa/global': async ({ body }) => {
      if (!lisaConfigured(cfg.lisaConfigPath)) throw bad('Файл настроек Лизы не подключён');
      const c = applyGlobal(readLisa(cfg.lisaConfigPath), body);
      saveLisa(cfg.lisaConfigPath, c);
      audit('lisa.global', { keys: Object.keys(body) });
      return { ok: true };
    },

    'POST /api/lisa/user': async ({ body }) => {
      if (!lisaConfigured(cfg.lisaConfigPath)) throw bad('Файл настроек Лизы не подключён');
      const userId = await fullId(body.user_id);
      const dv = await dvPeople();
      const c = applyUser(readLisa(cfg.lisaConfigPath), { userId, dvId: dv.get(userId) || '' }, body);
      saveLisa(cfg.lisaConfigPath, c);
      audit('lisa.user', { user: userId, keys: Object.keys(body).filter((k) => k !== 'user_id') });
      return { ok: true };
    },

    // Массово разрешить или запретить Лизу выбранным людям (доступ по списку)
    'POST /api/lisa/allow-bulk': async ({ body }) => {
      if (!lisaConfigured(cfg.lisaConfigPath)) throw bad('Файл настроек Лизы не подключён');
      const dv = await dvPeople();
      const ids = Array.isArray(body.user_ids) ? body.user_ids : [];
      const items = []; for (const u of ids) { const userId = await fullId(u); items.push({ userId, dvId: dv.get(userId) || '' }); }
      const r = applyAllowBulk(readLisa(cfg.lisaConfigPath), items, body.allowed);
      saveLisa(cfg.lisaConfigPath, r.cfg);
      audit('lisa.allow_bulk', { count: items.length, allowed: body.allowed, skipped: r.skipped.length });
      return { ok: true, skipped: r.skipped };
    },

    // Смена ключа OpenRouter. Панель ключа не хранит и сама его не применяет: кладёт заявку в свой каталог,
    // а отдельная служба на сервере (под root) проверяет ключ у OpenRouter, записывает и перезапускает Лизу.
    'POST /api/lisa/key': async ({ body }) => {
      if (!lisaConfigured(cfg.lisaConfigPath)) throw bad('Файл настроек Лизы не подключён');
      const key = String(body.key || '').trim();
      if (!/^sk-or-[A-Za-z0-9_\-]{20,200}$/.test(key)) throw bad('Ключ OpenRouter начинается с sk-or- и не содержит пробелов');
      const dir = dirname(cfg.lisaConfigPath), req = join(dir, 'key-request.json');
      if (existsSync(req) && Date.now() - statSync(req).mtimeMs < 120_000) throw new HttpError(409, 'Прежняя заявка ещё обрабатывается, подождите минуту', 'BUSY');
      const id = Math.random().toString(16).slice(2, 10);
      try { unlinkSync(join(dir, 'key-result.json')); } catch { /* результата ещё не было */ }
      const tmp = join(dir, '.key-request.tmp');
      writeFileSync(tmp, JSON.stringify({ id, key, ts: Date.now() }), { mode: 0o600 });
      renameSync(tmp, req);
      audit('lisa.key_requested', { id });
      return { ok: true, id };
    },

    // Отмена заявки (служба на сервере не ответила): файл с ключом удаляется
    'POST /api/lisa/key-cancel': async () => {
      if (!lisaConfigured(cfg.lisaConfigPath)) throw bad('Файл настроек Лизы не подключён');
      try { unlinkSync(join(dirname(cfg.lisaConfigPath), 'key-request.json')); } catch { /* заявки уже нет */ }
      audit('lisa.key_cancelled', {});
      return { ok: true };
    },

    'GET /api/lisa/key-status': async () => {
      if (!lisaConfigured(cfg.lisaConfigPath)) return { enabled: false };
      const dir = dirname(cfg.lisaConfigPath);
      let result = null; try { result = JSON.parse(readFileSync(join(dir, 'key-result.json'), 'utf8')); } catch { /* ещё нет */ }
      return { enabled: true, pending: existsSync(join(dir, 'key-request.json')), result };
    },

    // Друзья и входящие заявки человека (без переписки)
    'POST /api/users/friends': async ({ body }) => {
      const userId = await fullId(body.user_id);
      const r = await friendsOf(syn, userId, await usersMap());
      audit('user.friends_view', { user: userId });
      return r;
    },

    // Уведомления человека: устройства с подключёнными уведомлениями и правила Matrix
    'POST /api/users/notify': async ({ body }) => {
      const userId = await fullId(body.user_id);
      return notifyOf(syn, userId);
    },

    'POST /api/users/notify-rule': async ({ body }) => {
      const userId = await fullId(body.user_id);
      if (!isPushRule(body.rule_id)) throw bad('Неизвестное правило уведомлений');
      await setNotify(syn, userId, body.rule_id, Boolean(body.notifies));
      audit('notify.rule', { user: userId, rule: body.rule_id, notifies: Boolean(body.notifies) });
      return { ok: true };
    },

    // Все активные люди с количеством устройств и уведомлений (по кнопке: каждому делается короткий временный вход)
    'POST /api/notify/overview': async () => {
      const r = await syn.users({ limit: 100, guests: 'false' });
      const rows = [];
      for (const u of (r.users || []).filter((x) => !x.deactivated && !x.admin)) {
        const n = await notifyOf(syn, u.name).catch(() => null);
        rows.push({ user_id: u.name, label: u.displayname || u.name.slice(1).split(':')[0], pushers: n ? n.pushers : null, rules: n ? n.rules : null });
      }
      return { people: rows, rules: PUSH_RULES.map((d) => ({ id: d.id, label: d.label })) };
    },

    // Одно правило уведомлений всем активным людям сразу
    'POST /api/notify/apply': async ({ body }) => {
      if (!isPushRule(body.rule_id)) throw bad('Неизвестное правило уведомлений');
      if (String(body.confirm || '').trim() !== 'всем') throw bad('Подтверждение не совпало: введите слово «всем»');
      const r = await syn.users({ limit: 100, guests: 'false' });
      let n = 0, failed = 0;
      for (const u of (r.users || []).filter((x) => !x.deactivated && !x.admin)) {
        try { await setNotify(syn, u.name, body.rule_id, Boolean(body.notifies)); n++; } catch { failed++; }
      }
      audit('notify.rule_all', { rule: body.rule_id, notifies: Boolean(body.notifies), changed: n, failed });
      return { changed: n, failed };
    },

    'GET /api/setup/check': async () => {
      const checks = [];
      const add = (id, ok, text) => checks.push({ id, ok, text });
      try { const w = await syn.whoami(); add('synapse', true, `Synapse отвечает, вы вошли как ${w.user_id}`); } catch (e) { add('synapse', false, e.message); }
      try { const v = await syn.version(); add('admin', true, `Административный доступ есть, версия ${v.server_version}`); } catch (e) { add('admin', false, 'Нет прав администратора Synapse'); }
      try { await syn.dvMe(); add('dv', true, 'Модуль dv_social подключён'); } catch (e) { add('dv', false, e.status === 404 ? 'Модуль dv_social не подключён (каталог server/ репозитория)' : e.message); }
      return { checks };
    },

    'POST /api/setup/env': async ({ body }) => {
      let existing = ''; try { existing = readFileSync(cfg.envPath, 'utf8'); } catch { /* ещё не создан */ }
      const text = envText(body, existing);
      if (body.save === true) {
        mkdirSync(dirname(cfg.envPath), { recursive: true });
        const tmp = cfg.envPath + '.tmp';
        writeFileSync(tmp, text, { mode: 0o600 });
        renameSync(tmp, cfg.envPath);
        audit('setup.env_saved', {});
      }
      return { text: maskedEnvText(text), path: body.save === true ? cfg.envPath : '' };
    },

    // Файл читается как есть; адреса с секретом отдаются маской, настоящие только по кнопке «Показать» (запись в журнале)
    'GET /api/setup/env': async ({ query }) => {
      let text = ''; try { text = readFileSync(cfg.envPath, 'utf8'); } catch { /* ещё не создан */ }
      const kv = parseEnv(text);
      const reveal = query.reveal === '1';
      if (reveal) audit('setup.env_revealed', {});
      const f = (k) => (reveal ? (kv[k] || '') : maskUrl(kv[k] || ''));
      const others = Object.keys(kv).filter((k) => !Object.values(KEYS).includes(k));
      return { exists: Boolean(text), path: cfg.envPath, revealed: reveal, others,
        fields: { homeserver: kv.DVCHAT_HOMESERVER || '', pushGateway: f('DVCHAT_PUSH_GATEWAY'), updateUrl: f('DVCHAT_UPDATE_URL') } };
    },
  };
  return { routes, serverName };
}
