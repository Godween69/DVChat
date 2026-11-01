// Тесты против настоящего Synapse: SYNAPSE_URL, SYNAPSE_ADMIN_USER, SYNAPSE_ADMIN_PASSWORD
import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createApp } from '../server.mjs';
import { loadConfig } from '../lib/config.mjs';
import { hashPassword } from '../lib/auth.mjs';
import { envText, normalizeDvPeople, makeLink } from '../lib/api.mjs';

const SYN = process.env.SYNAPSE_URL || 'http://127.0.0.1:18008';
const PANEL_PW = 'panel-test-password';
const lr = await (await fetch(SYN + '/_matrix/client/v3/login', { method: 'POST', headers: { 'content-type': 'application/json' },
  body: JSON.stringify({ type: 'm.login.password', identifier: { type: 'm.id.user', user: process.env.SYNAPSE_ADMIN_USER || 'root' }, password: process.env.SYNAPSE_ADMIN_PASSWORD || 'Adm1n-test-pass', initial_device_display_name: 'DVChat admin' }) })).json();
const dir = mkdtempSync(join(tmpdir(), 'dvadmin-'));
const cfg = { ...loadConfig({ DVADMIN_DATA_DIR: dir, DVADMIN_SYNAPSE_URL: SYN }), passwordHash: hashPassword(PANEL_PW), synapseToken: lr.access_token, envPath: join(dir, 'dvchat.env') };
const { server } = createApp(cfg);
await new Promise((r) => server.listen(0, '127.0.0.1', r));
const base = `http://127.0.0.1:${server.address().port}`;
test.after(() => server.close());

let cookie = '';
const H = { 'x-requested-with': 'dvchat-admin' };
async function call(method, path, body, extra = {}) {
  const r = await fetch(base + path, { method, headers: { ...H, ...(cookie ? { cookie } : {}), ...(body ? { 'content-type': 'application/json' } : {}), ...extra }, body: body ? JSON.stringify(body) : undefined });
  const sc = r.headers.get('set-cookie'); if (sc && sc.includes('dvadmin_sid=') && !sc.includes('Max-Age=0')) cookie = sc.split(';')[0];
  let json = {}; try { json = await r.json(); } catch {}
  return { status: r.status, json, headers: r.headers };
}
const uname = 'u' + Date.now().toString(36);

test('безопасность: без входа закрыто, Host, CSRF, заголовки', async () => {
  assert.equal((await call('GET', '/api/users')).status, 401);
  const { request } = await import('node:http');
  const st = await new Promise((res) => { const q = request({ host: '127.0.0.1', port: server.address().port, path: '/api/users', headers: { host: 'evil.example' } }, (r) => { r.resume(); res(r.statusCode); }); q.end(); });
  assert.equal(st, 421);
  assert.equal((await call('POST', '/api/login', { password: 'x' }, { 'x-requested-with': '' })).status, 403);
  assert.equal((await call('POST', '/api/login', { password: 'x' }, { origin: 'http://evil.example' })).status, 403);
  const page = await fetch(base + '/');
  assert.match(page.headers.get('content-security-policy'), /script-src 'self'/);
  assert.equal(page.headers.get('x-frame-options'), 'DENY');
  assert.equal((await fetch(base + '/health')).status, 200);
});

test('вход: неверный пароль, лимитер, верный пароль', async () => {
  for (let i = 0; i < 5; i++) assert.equal((await call('POST', '/api/login', { password: 'wrong' + i })).status, 401);
  assert.equal((await call('POST', '/api/login', { password: PANEL_PW })).status, 429, 'после 5 ошибок вход блокируется даже с верным паролем');
  // следующие тесты работают с отдельным приложением без блокировки
});

// Свежее приложение для рабочих сценариев
const app2 = createApp(cfg);
await new Promise((r) => app2.server.listen(0, '127.0.0.1', r));
const base2 = `http://127.0.0.1:${app2.server.address().port}`;
test.after(() => app2.server.close());
let ck = '';
async function c2(method, path, body) {
  const r = await fetch(base2 + path, { method, headers: { ...H, ...(ck ? { cookie: ck } : {}), ...(body ? { 'content-type': 'application/json' } : {}) }, body: body ? JSON.stringify(body) : undefined });
  const sc = r.headers.get('set-cookie'); if (sc && !sc.includes('Max-Age=0')) ck = sc.split(';')[0];
  let json = {}; try { json = await r.json(); } catch {}
  return { status: r.status, json };
}

test('сценарии админки на настоящем Synapse', async (t) => {
  assert.equal((await c2('POST', '/api/login', { password: PANEL_PW })).status, 200);
  assert.equal((await c2('GET', '/api/session')).json.server_name, 'test.local');

  await t.test('создание человека и ссылка', async () => {
    const r = await c2('POST', '/api/users', { username: uname, displayname: 'Тест', ttl_hours: 24 });
    assert.equal(r.status, 200, JSON.stringify(r.json));
    assert.match(r.json.link, /^dvchat:\/\/login#/);
    const dec = JSON.parse(Buffer.from(r.json.link.split('#')[1], 'base64url').toString());
    assert.equal(dec.c, r.json.code);
    assert.equal((await c2('POST', '/api/users', { username: uname })).status, 409);
    assert.equal((await c2('POST', '/api/users', { username: 'Bad Name!' })).status, 400);
    assert.equal(r.json.password, undefined, 'пароль не уходит в ответ');
  });

  await t.test('список, ID, устройства, выход везде', async () => {
    const l = await c2('GET', '/api/users?q=' + uname);
    assert.equal(l.json.users.length, 1);
    const a = await c2('GET', '/api/users?q=anna');
    assert.equal(a.json.users.find((u) => u.user_id === '@anna:test.local')?.dv_id, 'DV111');
    const o = await c2('POST', '/api/users/logout-all', { user_id: uname });
    assert.equal(o.status, 200);
  });

  await t.test('новая ссылка для существующего', async () => {
    const r = await c2('POST', '/api/users/link', { user_id: uname, ttl_hours: 1 });
    assert.equal(r.status, 200); assert.ok(r.json.code);
    const r2 = await c2('POST', '/api/users/link', { user_id: uname, ttl_hours: 1 });
    assert.equal(r2.status, 200, 'повторная выдача тому же человеку без технических условий');
    assert.equal((await c2('POST', '/api/users/link', { user_id: 'nobody-here' })).status, 404);
  });

  await t.test('группа: создание, права, добавление, удаление, админа внутри нет', async () => {
    const g = await c2('POST', '/api/groups', { name: 'Тестовая ' + uname, owner: 'anna', members: ['boris', uname], encrypted: true });
    assert.equal(g.status, 200, JSON.stringify(g.json));
    const rid = g.json.room_id;
    let d = (await c2('POST', '/api/groups/details', { room_id: rid })).json;
    assert.equal(d.members.length, 3);
    assert.ok(!d.members.some((m) => m.user_id === '@root:test.local'), 'администратор не состоит в группе');
    assert.equal(d.members.find((m) => m.user_id === '@anna:test.local').perms.manage, true);
    const p = await c2('POST', '/api/groups/perms', { room_id: rid, user_id: 'boris', perms: { invite: true, kick: true } });
    assert.equal(p.json.level, 20);
    d = (await c2('POST', '/api/groups/details', { room_id: rid })).json;
    assert.deepEqual(d.members.find((m) => m.user_id === '@boris:test.local').perms, { invite: true, kick: true, ban: false, redact: false, edit: false, manage: false });
    assert.ok(!d.members.some((m) => m.user_id === '@root:test.local'), 'после правки админ снова вышел');
    assert.equal((await c2('POST', '/api/groups/remove', { room_id: rid, user_id: uname })).status, 200);
    d = (await c2('POST', '/api/groups/details', { room_id: rid })).json;
    assert.equal(d.members.length, 2);
    const list = await c2('GET', '/api/groups');
    assert.ok(list.json.groups.some((x) => x.room_id === rid));
    // удаление комнаты: нужно имя
    assert.equal((await c2('POST', '/api/rooms/delete', { room_id: rid, confirm: 'не то' })).status, 400);
    assert.equal((await c2('POST', '/api/rooms/delete', { room_id: rid, confirm: 'Тестовая ' + uname })).status, 200);
  });

  await t.test('удаление человека требует имя и не трогает админа', async () => {
    assert.equal((await c2('POST', '/api/users/deactivate', { user_id: uname, confirm: 'нет' })).status, 400);
    assert.equal((await c2('POST', '/api/users/deactivate', { user_id: 'root', confirm: 'root' })).status, 400);
    assert.equal((await c2('POST', '/api/users/deactivate', { user_id: uname, confirm: uname })).status, 200);
    assert.equal((await c2('GET', '/api/users?q=' + uname)).json.users.length, 0);
  });

  await t.test('обзор, комнаты, проверка сервера', async () => {
    const o = await c2('GET', '/api/overview'); assert.equal(o.status, 200); assert.ok(o.json.users_active >= 3);
    assert.equal((await c2('GET', '/api/rooms?filter=orphans')).status, 200);
    const ch = (await c2('GET', '/api/setup/check')).json.checks; assert.ok(ch.every((x) => x.ok), JSON.stringify(ch));
  });

  await t.test('мастер dvchat.env: проверка и запись с правами 600', async () => {
    assert.equal((await c2('POST', '/api/setup/env', { homeserver: 'https://x' })).status, 400);
    assert.equal((await c2('POST', '/api/setup/env', { homeserver: 'chat.example.org', updateUrl: 'http://x' })).status, 400);
    assert.equal((await c2('POST', '/api/setup/env', { homeserver: 'a.b\nX=1' })).status, 400);
    const r = await c2('POST', '/api/setup/env', { homeserver: 'chat.example.org', pushGateway: 'https://push.example.org', save: true });
    assert.match(r.json.text, /DVCHAT_HOMESERVER=chat.example.org\nDVCHAT_PUSH_GATEWAY=https:\/\/push.example.org\n/);
    const { statSync } = await import('node:fs');
    assert.equal((statSync(cfg.envPath).mode & 0o777), 0o600);
    assert.match((await c2('GET', '/api/setup/env')).json.text, /chat.example.org/);
  });

  await t.test('выход закрывает сессию', async () => {
    assert.equal((await c2('POST', '/api/logout')).status, 200);
    assert.equal((await fetch(base2 + '/api/users', { headers: { cookie: ck } })).status, 401);
  });
});

test('чистые функции', () => {
  assert.equal(envText({ homeserver: 'chat.example.org' }), '# Настройки сборки DVChat. Создано мастером админки. В git не добавлять.\nDVCHAT_HOMESERVER=chat.example.org\n');
  assert.equal(normalizeDvPeople({ friends: [{ user_id: '@a:s', dv_id: 'X1' }] }).get('@a:s'), 'X1');
  assert.equal(makeLink('abc'), 'dvchat://login#' + Buffer.from('{"c":"abc"}').toString('base64url'));
});

// ---------- Лиза: чистые функции и запись файла ----------
import { applyGlobal, applyUser, lisaView, saveLisa, readLisa } from '../lib/lisa.mjs';
import { writeFileSync as wf, readdirSync as rd } from 'node:fs';

test('Лиза: проверка значений и права по людям', () => {
  const c = { system_prompt: 'x'.repeat(30), admins: ['@a:s'], allowed_dv_ids: ['111'], limits: { per_user_per_day: 50, global_per_day: 300 } };
  assert.throws(() => applyGlobal(c, { limits: { per_user_per_day: 0 } }), /от 1/);
  assert.throws(() => applyGlobal(c, { search_url: 'file:///etc/passwd' }), /Адрес поиска/);
  assert.throws(() => applyGlobal(c, { system_prompt: 'коротко' }), /Инструкция/);
  applyGlobal(c, { limits: { per_user_per_day: 70 }, allow_all: true, features_defaults: { chat_context: true } });
  assert.equal(c.limits.per_user_per_day, 70); assert.ok(c.allowed_dv_ids.includes('*')); assert.equal(c.features.defaults.chat_context, true);
  applyGlobal(c, { allow_all: false }); assert.ok(!c.allowed_dv_ids.includes('*'));
  assert.throws(() => applyUser(c, { userId: '@b:s', dvId: '' }, { allowed: true }), /нет ID/);
  applyUser(c, { userId: '@b:s', dvId: '222' }, { allowed: true, limit: 5, features: { search: false }, games_off: ['chess', 'durak'] });
  assert.deepEqual(c.allowed_dv_ids.sort(), ['111', '222']); assert.equal(c.limits.overrides['@b:s'], 5);
  assert.deepEqual(c.features.users['@b:s'], { search: false, games_off: ['chess', 'durak'] });
  assert.throws(() => applyUser(c, { userId: '@b:s', dvId: '222' }, { games_off: ['hack'] }), /игра/);
  applyUser(c, { userId: '@b:s', dvId: '222' }, { allowed: false, limit: null, features: { search: null }, games_off: [] });
  assert.equal(c.features.users['@b:s'], undefined); assert.equal(c.limits.overrides['@b:s'], undefined);
  const v = lisaView(c, [{ user_id: '@a:s', displayname: 'A', dv_id: '' }, { user_id: '@c:s', displayname: 'C', dv_id: '111' }]);
  assert.equal(v.people[0].allowed, true, 'админ допущен всегда'); assert.equal(v.people[1].allowed, true);
});

test('Лиза: запись файла с копией и без потери чужих ключей', () => {
  const p = join(dir, 'lisa.json');
  wf(p, JSON.stringify({ admins: ['@a:s'], models: [{ id: 'm' }], system_prompt: 'y'.repeat(30), secret_like: 'keep' }));
  const c = readLisa(p); applyGlobal(c, { default_city: 'Город' }); saveLisa(p, c);
  assert.equal(readLisa(p).secret_like, 'keep'); assert.equal(readLisa(p).default_city, 'Город'); assert.deepEqual(readLisa(p).models, [{ id: 'm' }]);
  assert.ok(rd(dir).some((f) => f.startsWith('lisa.json.bak-')), 'копия создана');
});

// ---------- Лиза: модели, настройки, сводка расходов ----------
import { applyModels, summarize, readPanel } from '../lib/lisa.mjs';

test('Лиза: порядок моделей и проверка по каталогу', () => {
  const cat = [{ id: 'a/one', vision: true }, { id: 'b/two', vision: false }];
  const c = { models: [{ id: 'a/one', timeout: 9 }] };
  applyModels(c, ['a/one', 'b/two'], cat);
  assert.deepEqual(c.models.map((m) => m.id), ['a/one', 'b/two']); assert.equal(c.models[0].timeout, 9, 'свои поля модели сохраняются');
  assert.throws(() => applyModels(c, [], cat), /от 1 до 6/);
  assert.throws(() => applyModels(c, ['a/one', 'a/one'], cat), /дважды/);
  assert.throws(() => applyModels(c, ['x/none'], cat), /нет в каталоге/);
  assert.throws(() => applyModels(c, ['плохо'], cat), /Некорректное/);
  applyModels(c, ['b/two'], []); assert.equal(c.models.length, 1, 'без каталога допустим только известный/верный по формату id');
});

test('Лиза: новые настройки проверяются', () => {
  const c = { system_prompt: 'x'.repeat(30) };
  applyGlobal(c, { safesearch: 2, read_pages: 3, news_range: 'day', model_timeout: 30, log_questions_days: 14, key_warn_usd: 1.5, search_engines: ['google', 'bing'] });
  assert.equal(c.read_pages, 3); assert.deepEqual(c.search_engines, ['google', 'bing']); assert.equal(c.log_questions_days, 14);
  assert.throws(() => applyGlobal(c, { safesearch: 0 }), /Фильтр/);
  assert.throws(() => applyGlobal(c, { news_range: 'year' }), /Свежесть/);
  assert.throws(() => applyGlobal(c, { search_engines: ['a;rm -rf'] }), /движки/);
  assert.throws(() => applyGlobal(c, { log_questions_days: 99 }), /Срок/);
  applyGlobal(c, { search_engines: [] }); assert.equal(c.search_engines, undefined);
  assert.equal(lisaView(c, []).settings.news_range, 'day');
});

test('Лиза: сводка расходов за день, неделю и месяц', () => {
  const s = summarize({ today: '2026-10-30',
    days: [{ day: '2026-10-30', n: 2, tin: 100, tout: 50, cost: 0.5 }, { day: '2026-10-26', n: 1, tin: 10, tout: 5, cost: 0.25 }, { day: '2026-10-05', n: 1, tin: 1, tout: 1, cost: 1 }, { day: '2026-08-01', n: 9, tin: 9, tout: 9, cost: 9 }],
    users: [{ user: '@a:s', day: '2026-10-30', n: 2, tin: 100, tout: 50, cost: 0.5 }, { user: '@b:s', day: '2026-10-05', n: 1, tin: 1, tout: 1, cost: 1 }], models: [] });
  assert.equal(s.totals.today.cost, 0.5); assert.equal(s.totals.d7.cost, 0.75); assert.equal(s.totals.d30.cost, 1.75);
  assert.equal(s.series.length, 30); assert.equal(s.series[29].day, '2026-10-30');
  assert.equal(s.users[0].user, '@b:s', 'сортировка по деньгам за 30 дней'); assert.equal(s.users[1].today.n, 2);
  assert.equal(readPanel('/нет/такого', 'state.json'), null);
});
