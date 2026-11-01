// Панель 0.3.1: каталог моделей как его пишет Лиза, смена ключа, доступ по людям, игры, друзья, уведомления, обзор, файл настроек
import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, writeFileSync, readFileSync, mkdirSync, existsSync, statSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createApp } from '../server.mjs';
import { loadConfig } from '../lib/config.mjs';
import { hashPassword } from '../lib/auth.mjs';
import { envText, maskUrl, maskedEnvText, parseEnv, roomKind } from '../lib/api.mjs';
import { catalogView, purposeTags, explainError, recommend, parseGameStats, summarizeGames } from '../lib/lisa.mjs';

const SYN = process.env.SYNAPSE_URL || 'http://127.0.0.1:18008';
const lr = await (await fetch(SYN + '/_matrix/client/v3/login', { method: 'POST', headers: { 'content-type': 'application/json' },
  body: JSON.stringify({ type: 'm.login.password', identifier: { type: 'm.id.user', user: process.env.SYNAPSE_ADMIN_USER || 'root' }, password: process.env.SYNAPSE_ADMIN_PASSWORD || 'Adm1n-test-pass', initial_device_display_name: 'DVChat admin' }) })).json();
const dir = mkdtempSync(join(tmpdir(), 'dv030-'));
const pdir = join(dir, 'panel'); mkdirSync(pdir);
const ldir = join(dir, 'lisa'); mkdirSync(ldir);
const cpath = join(ldir, 'config.json');
const today = new Date().toISOString().slice(0, 10);
writeFileSync(cpath, JSON.stringify({ admins: [], allowed_dv_ids: ['*'], models: [{ id: 'free/model:free' }, { id: 'c/three', vision: true }, { id: 'new/pending' }], system_prompt: 'x'.repeat(40), features: { defaults: {}, users: {} } }));
const J = (n, o) => writeFileSync(join(pdir, n), JSON.stringify(o));
// Каталог в том виде, в каком его пишет сервер Лизы: pin/pout/ctx (доллары за миллион токенов)
J('catalog.json', { ts: 1, models: [
  { id: 'a/one', name: 'One', pin: 1, pout: 5, ctx: 1000, vision: false },
  { id: 'q/qwen-coder', name: 'Coder', pin: 0.2, pout: 0.8, ctx: 64000, vision: false, tools: true, reasoning: true },
  { id: 'free/model:free', name: 'Free Model', pin: 0, pout: 0, ctx: 8000, vision: false },
  { id: 'c/three', name: 'Three Haiku', pin: 0.1, pout: 0.5, ctx: 200000, vision: true },
  { id: 'd/four', name: 'Four', pin: 3, pout: 15, ctx: 128000, vision: true }] });
J('state.json', { ts: Date.now() / 1000, version: '3.2', active: 'c/three', models: [{ id: 'free/model:free', up: false, error: 'http 429', price_in: 0, price_out: 0 }, { id: 'c/three', up: true, price_in: 0.1, price_out: 0.5 }], key: { mask: 'sk-or-v1-…1234', ok: true } });
J('stats.json', { today, days: [{ day: today, n: 2, tin: 10, tout: 5, cost: 0.01 }], users: [], models: [] });
J('engines.json', { ts: 1, engines: [{ name: 'duckduckgo', enabled: true }, { name: 'wikipedia', enabled: true }, { name: 'bing', enabled: false }] });

const envPath = join(dir, 'dvchat.env');
const cfg = { ...loadConfig({ DVADMIN_DATA_DIR: dir, DVADMIN_SYNAPSE_URL: SYN, DVADMIN_LISA_CONFIG: cpath, DVADMIN_LISA_PANEL_DIR: pdir, DVADMIN_LISA_GUIDE: join(ldir, 'g.md') }), passwordHash: hashPassword('pw-test'), synapseToken: lr.access_token, envPath };
const { server } = createApp(cfg);
await new Promise((r) => server.listen(0, '127.0.0.1', r));
const base = `http://127.0.0.1:${server.address().port}`;
test.after(() => server.close());
let ck = '';
async function call(method, path, body) {
  const r = await fetch(base + path, { method, headers: { 'x-requested-with': 'dvchat-admin', ...(ck ? { cookie: ck } : {}), ...(body ? { 'content-type': 'application/json' } : {}) }, body: body ? JSON.stringify(body) : undefined });
  const sc = r.headers.get('set-cookie'); if (sc && !sc.includes('Max-Age=0')) ck = sc.split(';')[0];
  let json = {}; try { json = await r.json(); } catch {}
  return { status: r.status, json };
}
const cfgNow = () => JSON.parse(readFileSync(cpath, 'utf8'));
const uname = 'p030' + Math.random().toString(36).slice(2, 7);


const syn = (path, method = 'GET', body) => fetch(SYN + path, { method, headers: { authorization: 'Bearer ' + lr.access_token, 'content-type': 'application/json' }, body: body ? JSON.stringify(body) : undefined }).then((r) => r.json());
const sname = (await syn('/_matrix/client/v3/account/whoami')).user_id.split(':')[1];

test('расшифровка ошибок моделей простыми словами', () => {
  const e = explainError('http 429');
  assert.equal(e.code, 429); assert.match(e.title, /Лимит/); assert.ok(e.what.length > 20 && e.todo.length > 10);
  assert.equal(explainError('http 401').code, 401); assert.match(explainError('http 402').title, /денег/);
  assert.equal(explainError('http 503').code, 503);
  assert.equal(explainError('TimeoutError').code, 0, 'неизвестное не выдумываем');
  assert.match(explainError('TimeoutError').title, /Неизвестная/);
});

test('метки «для чего модель» берутся из данных каталога, без выдумок', () => {
  const t = (m) => purposeTags(m).map((x) => x.key);
  assert.deepEqual(t({ id: 'a/plain' }), ['chat']);
  assert.ok(t({ id: 'x/qwen3-coder' }).includes('code'));
  assert.ok(t({ id: 'x/y', reasoning: true, tools: true, vision: true, context: 300000 }).join() === 'chat,reason,tools,vision,long');
  assert.ok(t({ id: 'google/gemini-flash' }).includes('fast'));
  assert.ok(purposeTags({ id: 'a/b', vision: true }).every((x) => x.hint.length > 10), 'у каждой метки есть подсказка');
});

test('каталог: цена-класс, метки и подсказки по выбору', async () => {
  await call('POST', '/api/login', { password: 'pw-test' });
  const c = (await call('GET', '/api/lisa/catalog')).json;
  const by = (id) => c.models.find((m) => m.id === id);
  assert.equal(by('free/model:free').tier, 'free'); assert.equal(by('c/three').tier, 'cheap');
  assert.equal(by('a/one').tier, 'middle'); assert.equal(by('d/four').tier, 'expensive');
  assert.ok(by('q/qwen-coder').tags.some((x) => x.key === 'code') && by('q/qwen-coder').tags.some((x) => x.key === 'reason'));
  assert.ok(Array.isArray(c.recommend) && c.recommend.length >= 2);
  const vision = c.recommend.find((r) => /картинками/.test(r.title));
  assert.equal(vision.id, 'c/three', 'самая дешёвая платная с картинками и контекстом от 32 тысяч');
  assert.ok(c.recommend.every((r) => r.id && r.why));
  assert.equal((await call('GET', '/api/lisa/catalog?q=haiku')).json.recommend, undefined, 'при поиске подсказок нет');
  assert.equal(recommend(catalogView([])).length, 0);
});

test('список моделей: причина ошибки, «ждёт применения» и метки', async () => {
  const o = (await call('GET', '/api/lisa/overview')).json;
  const free = o.models.find((m) => m.id === 'free/model:free');
  assert.equal(free.up, false); assert.equal(free.error_info.code, 429); assert.ok(free.error_info.todo);
  const np = o.models.find((m) => m.id === 'new/pending');
  assert.equal(np.pending, true, 'модели ещё нет в состоянии Лизы');
  assert.equal(o.models.find((m) => m.id === 'c/three').pending, false);
  assert.ok(o.models.find((m) => m.id === 'c/three').tags.some((x) => x.key === 'vision'));
  assert.ok(np.tags.length >= 1, 'метки есть даже у модели не из каталога');
});

test('обзор: списки людей и групп для подробностей', async () => {
  const o = (await call('GET', '/api/overview')).json;
  assert.ok(Array.isArray(o.activity.all) && o.activity.all.length >= 1);
  assert.ok(o.activity.all.every((x) => 'user_id' in x && 'label' in x && 'last_seen' in x));
  assert.ok(Array.isArray(o.groups_list));
  assert.ok(Array.isArray(o.lisa.by_user));
});

test('люди: корневой админ неприкосновенен, обычного админа удалить можно, список обновляется', async () => {
  const name = 'adm' + Math.random().toString(36).slice(2, 7), id = `@${name}:${sname}`;
  await syn('/_synapse/admin/v2/users/' + encodeURIComponent(id), 'PUT', { password: 'Xx-' + Math.random().toString(36).slice(2) + 'Aa1!', admin: true, displayname: 'Второй админ' });
  const list = (await call('GET', '/api/users?q=' + name)).json;
  const u = list.users.find((x) => x.user_id === id);
  assert.equal(u.admin, true); assert.equal(u.root, false);
  assert.ok(list.root && list.users.every((x) => x.root === (x.user_id === list.root)), 'root только у учётной записи панели');
  const del = await call('POST', '/api/users/deactivate', { user_id: id, confirm: name });
  assert.equal(del.status, 200, JSON.stringify(del.json));
  assert.equal((await call('GET', '/api/users?q=' + name)).json.users.length, 0, 'удалённый пропал из обычного списка сразу');
  const gone = (await call('GET', '/api/users?q=' + name + '&deactivated=1')).json.users.find((x) => x.user_id === id);
  assert.equal(gone.deactivated, true, 'в списке «удалённые» он виден и помечен');
  const root = (await call('GET', '/api/users?q=root')).json.root;
  const self = await call('POST', '/api/users/deactivate', { user_id: root, confirm: root.slice(1).split(':')[0] });
  assert.equal(self.status, 400, 'корневого удалить нельзя');
  const old = await call('POST', '/api/users/deactivate', { user_id: id, confirm: 'не то' });
  assert.ok(old.status >= 400);
});

test('одно определение комнат: числа на обзоре совпадают со вкладками', async () => {
  const mk = (o) => ({ room_id: '!x:t', joined_members: 2, name: '', ...o });
  assert.equal(roomKind(mk({ joined_members: 0 }), ''), 'empty');
  assert.equal(roomKind(mk({ joined_members: 3 }), ''), 'group');
  assert.equal(roomKind(mk({ name: 'Тест' }), ''), 'group', 'группа с названием, где пока двое, это группа');
  assert.equal(roomKind(mk({}), ''), 'direct');
  assert.equal(roomKind(mk({ name: 'Иван @ivan (123456)' }), ''), 'support');
  assert.equal(roomKind(mk({}), '!x:t'), 'service');
  // живой Synapse: именованная группа из двух человек
  const a = `@gq${Math.random().toString(36).slice(2, 7)}:${sname}`;
  await syn('/_synapse/admin/v2/users/' + encodeURIComponent(a), 'PUT', { password: 'Qq-' + Math.random().toString(36).slice(2) + 'Aa1!', displayname: 'Участник' });
  const made = await call('POST', '/api/groups', { name: 'Тест-группа двое', owner: a, members: [] });
  assert.equal(made.status, 200, JSON.stringify(made.json));
  const o = (await call('GET', '/api/overview')).json, g = (await call('GET', '/api/groups')).json.groups;
  assert.equal(o.rooms_kinds.groups, g.length, 'групп на обзоре и на вкладке поровну');
  assert.equal(o.groups_list.length, g.length);
  const rooms = (await call('GET', '/api/rooms?filter=empty')).json;
  assert.equal(o.rooms_orphans, rooms.empty_count, 'пустых комнат на обзоре и на вкладке поровну');
});

test('статистика игр: разбор профиля, мусор отбрасывается', () => {
  const st = parseGameStats({ v: 1, games: { chess: { played: 5, won: 9, lost: 1, last: 1700000000000, days: { '2026-11-01': 2, 'bad': 5 } }, nope: { played: 3 }, ttt: { played: 0 }, durak: 'x' } });
  assert.deepEqual(Object.keys(st), ['chess']);
  assert.equal(st.chess.won, 5, 'побед не больше партий');
  assert.deepEqual(st.chess.days, { '2026-11-01': 2 });
  assert.deepEqual(parseGameStats(null), {}); assert.deepEqual(parseGameStats({ games: 5 }), {});
  const sum = summarizeGames([{ user_id: '@a:t', label: 'A', data: { games: { chess: { played: 3, won: 2 }, ttt: { played: 1 } } } }, { user_id: '@b:t', label: 'B', data: null }]);
  assert.equal(sum.with_data, 1); assert.equal(sum.total_played, 4); assert.equal(sum.games[0].id, 'chess'); assert.equal(sum.people[0].favorite, 'chess');
  assert.equal(sum.series.length, 14);
});

test('статистика игр: читается из профиля людей через админский запрос', async () => {
  const name = 'gm' + Math.random().toString(36).slice(2, 7), id = `@${name}:${sname}`;
  await syn('/_synapse/admin/v2/users/' + encodeURIComponent(id), 'PUT', { password: 'Gg-' + Math.random().toString(36).slice(2) + 'Aa1!', displayname: 'Игрок ' + name });
  const login = await syn('/_synapse/admin/v1/users/' + encodeURIComponent(id) + '/login', 'POST', {});
  const today = new Date(Date.now() + 3 * 3600e3).toISOString().slice(0, 10);
  const put = await fetch(`${SYN}/_matrix/client/v3/user/${encodeURIComponent(id)}/account_data/dv.game_stats`, { method: 'PUT', headers: { authorization: 'Bearer ' + login.access_token, 'content-type': 'application/json' },
    body: JSON.stringify({ v: 1, games: { chess: { played: 7, won: 4, lost: 2, drawn: 1, last: Date.now(), days: { [today]: 3 } }, durak: { played: 2, won: 1, lost: 1 } } }) });
  assert.equal(put.status, 200);
  const g = (await call('GET', '/api/games/stats')).json;
  assert.ok(g.with_data >= 1 && g.people_total >= 1);
  const p = g.people.find((x) => x.user_id === id);
  assert.equal(p.played, 9); assert.equal(p.favorite, 'chess'); assert.equal(p.won, 5);
  const chess = g.games.find((x) => x.id === 'chess');
  assert.ok(chess.played >= 7 && chess.players >= 1);
  assert.ok(g.has_days && g.series[13].n >= 3, 'партии за сегодня видны на графике');
});
