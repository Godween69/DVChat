// Маршруты админки. Каждая изменяющая операция пишется в журнал (без секретов).
import { writeFileSync, appendFileSync, mkdirSync, readFileSync } from 'node:fs';
import { dirname } from 'node:path';
import { generateSecret } from './auth.mjs';
import * as G from './groups.mjs';
import { readLisa, saveLisa, applyGlobal, applyUser, lisaView, lisaConfigured } from './lisa.mjs';

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

export function envText(v) {
  const clean = (x, name) => {
    const s = String(x ?? '').trim();
    if (/[\r\n"'\\\s]/.test(s)) throw bad(`Поле ${name}: пробелы, кавычки и переводы строк недопустимы`);
    return s;
  };
  const host = clean(v.homeserver, 'Адрес сервера');
  if (!/^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?(:\d+)?$/.test(host)) throw bad('Адрес сервера: укажите имя хоста без https://, например chat.example.org');
  const url = (x, name) => {
    const s = clean(x, name);
    if (!s) return '';
    if (!/^https:\/\/[A-Za-z0-9.-]+(:\d+)?(\/[A-Za-z0-9._~\-\/]*)?$/.test(s)) throw bad(`Поле ${name}: нужен адрес вида https://…`);
    return s;
  };
  const push = url(v.pushGateway, 'Шлюз уведомлений');
  const upd = url(v.updateUrl, 'Канал обновлений');
  const lines = ['# Настройки сборки DVChat. Создано мастером админки. В git не добавлять.', `DVCHAT_HOMESERVER=${host}`];
  if (push) lines.push(`DVCHAT_PUSH_GATEWAY=${push}`);
  if (upd) lines.push(`DVCHAT_UPDATE_URL=${upd}`);
  return lines.join('\n') + '\n';
}

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

  const routes = {
    'GET /api/overview': async () => {
      const [ver, users, rooms] = await Promise.all([
        syn.version().catch(() => ({})), syn.users({ limit: 1, deactivated: 'true' }).catch(() => ({})),
        syn.rooms({ limit: 1 }).catch(() => ({})),
      ]);
      const all = await syn.users({ limit: 1 });
      const grp = await syn.rooms({ limit: 500 }).catch(() => ({ rooms: [] }));
      const list = grp.rooms || [];
      return {
        server_name: await serverName(), synapse: ver.server_version || '',
        users_active: all.total ?? 0, users_with_deactivated: users.total ?? 0,
        rooms_total: rooms.total_rooms ?? 0,
        rooms_groups: list.filter((r) => r.joined_members > 2 || (r.name && r.joined_members > 2)).length,
        rooms_orphans: list.filter((r) => r.joined_local_members === 0).length,
      };
    },

    'GET /api/users': async ({ query }) => {
      const r = await syn.users({ limit: 100, from: query.from, name: query.q, guests: 'false', deactivated: query.deactivated === '1' ? 'true' : 'false' });
      const dv = await dvPeople();
      return {
        total: r.total, next: r.next_token ?? null,
        users: (r.users || []).map((u) => ({
          user_id: u.name, displayname: u.displayname || '', admin: Boolean(u.admin),
          deactivated: Boolean(u.deactivated), created: u.creation_ts, dv_id: dv.get(u.name) || '',
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
      await syn.putUser(userId, { password, logout_devices: false });
      const issued = await issueLink(userId, { password, ttl: body.ttl_hours });
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
      if (u.admin) throw bad('Администраторов здесь удалять нельзя');
      confirmName(body.confirm, userId.slice(1).split(':')[0]);
      await syn.deactivate(userId, body.erase === true);
      audit('user.deactivate', { user: userId, erase: body.erase === true });
      return { ok: true };
    },

    'GET /api/rooms': async ({ query }) => {
      const r = await syn.rooms({ limit: 100, from: query.from, search_term: query.q, order_by: 'joined_members', dir: 'b' });
      let rooms = (r.rooms || []).map((x) => ({
        room_id: x.room_id, name: x.name || '', members: x.joined_members, local_members: x.joined_local_members,
        creator: x.creator, encrypted: Boolean(x.encryption),
        kind: x.joined_members > 2 || (x.name && x.joined_members > 2) ? 'group' : 'direct',
      }));
      if (query.filter === 'orphans') rooms = rooms.filter((x) => x.local_members === 0);
      if (query.filter === 'groups') rooms = rooms.filter((x) => x.kind === 'group');
      if (query.filter === 'direct') rooms = rooms.filter((x) => x.kind === 'direct');
      return { total: r.total_rooms, next: r.next_batch ?? null, rooms };
    },

    'POST /api/rooms/delete': async ({ body }) => {
      const id = roomId(body.room_id);
      const room = await syn.room(id);
      confirmName(body.confirm, room.name || id);
      const r = await syn.deleteRoom(id, true);
      audit('room.delete', { room: id });
      return { delete_id: r.delete_id || '' };
    },

    'GET /api/groups': async () => {
      const r = await syn.rooms({ limit: 500, order_by: 'joined_members', dir: 'b' });
      return { groups: (r.rooms || []).filter((x) => x.joined_members > 2 || (x.name && x.joined_members > 1))
        .map((x) => ({ room_id: x.room_id, name: x.name || '', members: x.joined_members, encrypted: Boolean(x.encryption) })), ladder: G.LADDER };
    },

    'POST /api/groups': async ({ body }) => {
      const name = String(body.name || '').trim();
      if (!name || name.length > 80) throw bad('Название группы: от 1 до 80 символов');
      const owner = await fullId(body.owner);
      await syn.user(owner);
      const members = [];
      for (const m of body.members || []) members.push(await fullId(m));
      const r = await G.createGroup(syn, await me(), { name, topic: String(body.topic || '').slice(0, 200), owner, members, encrypted: body.encrypted !== false });
      audit('group.create', { room: r.room_id, owner, members: members.length });
      return r;
    },

    'POST /api/groups/details': async ({ body }) => G.groupDetails(syn, roomId(body.room_id)),

    'POST /api/groups/perms': async ({ body }) => {
      const userId = await fullId(body.user_id);
      const r = await G.setMemberPerms(syn, await me(), roomId(body.room_id), userId, body.perms || {});
      audit('group.perms', { room: body.room_id, user: userId, level: r.level });
      return r;
    },

    'POST /api/groups/add': async ({ body }) => {
      const ids = []; for (const m of body.members || []) ids.push(await fullId(m));
      const r = await G.addMembers(syn, await me(), roomId(body.room_id), ids);
      audit('group.add', { room: body.room_id, users: ids.length });
      return r;
    },

    'POST /api/groups/remove': async ({ body }) => {
      const userId = await fullId(body.user_id);
      await G.removeMember(syn, await me(), roomId(body.room_id), userId);
      audit('group.remove', { room: body.room_id, user: userId });
      return { ok: true };
    },

    'GET /api/lisa': async () => {
      if (!lisaConfigured(cfg.lisaConfigPath)) return { enabled: false };
      const r = await syn.users({ limit: 200, guests: 'false', deactivated: 'false' });
      const dv = await dvPeople();
      const people = (r.users || []).map((u) => ({ user_id: u.name, displayname: u.displayname || '', dv_id: dv.get(u.name) || '' }));
      return lisaView(readLisa(cfg.lisaConfigPath), people);
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

    'GET /api/setup/check': async () => {
      const checks = [];
      const add = (id, ok, text) => checks.push({ id, ok, text });
      try { const w = await syn.whoami(); add('synapse', true, `Synapse отвечает, вы вошли как ${w.user_id}`); } catch (e) { add('synapse', false, e.message); }
      try { const v = await syn.version(); add('admin', true, `Административный доступ есть, версия ${v.server_version}`); } catch (e) { add('admin', false, 'Нет прав администратора Synapse'); }
      try { await syn.dvMe(); add('dv', true, 'Модуль dv_social подключён'); } catch (e) { add('dv', false, e.status === 404 ? 'Модуль dv_social не подключён (каталог server/ репозитория)' : e.message); }
      return { checks };
    },

    'POST /api/setup/env': async ({ body }) => {
      const text = envText(body);
      if (body.save === true) {
        mkdirSync(dirname(cfg.envPath), { recursive: true });
        writeFileSync(cfg.envPath, text, { mode: 0o600 });
        audit('setup.env_saved', {});
      }
      return { text, path: body.save === true ? cfg.envPath : '' };
    },

    'GET /api/setup/env': async () => {
      let text = ''; try { text = readFileSync(cfg.envPath, 'utf8'); } catch { /* ещё не создан */ }
      return { text, path: cfg.envPath };
    },
  };
  return { routes, serverName };
}
