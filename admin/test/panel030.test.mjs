// Панель 0.3.0: каталог моделей как его пишет Лиза, смена ключа, доступ по людям, игры, друзья, уведомления, обзор, файл настроек
import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, writeFileSync, readFileSync, mkdirSync, existsSync, statSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createApp } from '../server.mjs';
import { loadConfig } from '../lib/config.mjs';
import { hashPassword } from '../lib/auth.mjs';
import { envText, maskUrl, maskedEnvText, parseEnv } from '../lib/api.mjs';
import { catalogView, applyAllowBulk, applyGlobal, lisaView } from '../lib/lisa.mjs';

const SYN = process.env.SYNAPSE_URL || 'http://127.0.0.1:18008';
const lr = await (await fetch(SYN + '/_matrix/client/v3/login', { method: 'POST', headers: { 'content-type': 'application/json' },
  body: JSON.stringify({ type: 'm.login.password', identifier: { type: 'm.id.user', user: process.env.SYNAPSE_ADMIN_USER || 'root' }, password: process.env.SYNAPSE_ADMIN_PASSWORD || 'Adm1n-test-pass', initial_device_display_name: 'DVChat admin' }) })).json();
const dir = mkdtempSync(join(tmpdir(), 'dv030-'));
const pdir = join(dir, 'panel'); mkdirSync(pdir);
const ldir = join(dir, 'lisa'); mkdirSync(ldir);
const cpath = join(ldir, 'config.json');
const today = new Date().toISOString().slice(0, 10);
writeFileSync(cpath, JSON.stringify({ admins: [], allowed_dv_ids: ['*'], models: [{ id: 'a/one' }], system_prompt: 'x'.repeat(40), features: { defaults: {}, users: {} } }));
const J = (n, o) => writeFileSync(join(pdir, n), JSON.stringify(o));
// Каталог в том виде, в каком его пишет сервер Лизы: pin/pout/ctx (доллары за миллион токенов)
J('catalog.json', { ts: 1, models: [
  { id: 'a/one', name: 'One', pin: 1, pout: 5, ctx: 1000, vision: false },
  { id: 'free/model:free', name: 'Free Model', pin: 0, pout: 0, ctx: 8000, vision: false },
  { id: 'c/three', name: 'Three Haiku', pin: 0.1, pout: 0.5, ctx: 200000, vision: true },
  { id: 'd/four', name: 'Four', pin: 3, pout: 15, ctx: 128000, vision: true }] });
J('state.json', { ts: Date.now() / 1000, version: '3.1', active: 'a/one', models: [{ id: 'a/one', up: true, price_in: 1, price_out: 5 }], key: { mask: 'sk-or-v1-…1234', ok: true } });
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

test('каталог моделей Лизы: цены видны, фильтры бесплатные и платные', async () => {
  assert.equal((await call('POST', '/api/login', { password: 'pw-test' })).status, 200);
  const v = catalogView([{ id: 'x/y', pin: 0, pout: 0, ctx: 5 }, { id: 'p/q', price_in: 2, price_out: 3 }, { id: 'n/n' }]);
  assert.deepEqual(v.map((m) => [m.free, m.price_in]), [[true, 0], [false, 2], [false, null]]);
  const all = (await call('GET', '/api/lisa/catalog')).json;
  assert.equal(all.matched, 4); assert.equal(all.free_total, 1);
  assert.equal(all.models[0].id, 'free/model:free', 'сначала бесплатные, потом по цене');
  assert.equal(all.models.find((m) => m.id === 'd/four').price_out, 15, 'цена не undefined');
  assert.equal(all.models.find((m) => m.id === 'c/three').context, 200000);
  assert.deepEqual((await call('GET', '/api/lisa/catalog?kind=free')).json.models.map((m) => m.id), ['free/model:free']);
  assert.equal((await call('GET', '/api/lisa/catalog?kind=paid')).json.matched, 3);
  assert.deepEqual((await call('GET', '/api/lisa/catalog?vision=1&kind=paid')).json.models.map((m) => m.id), ['c/three', 'd/four']);
  assert.equal((await call('GET', '/api/lisa/catalog?q=haiku')).json.matched, 1);
  assert.equal((await call('GET', '/api/lisa/catalog?limit=2&offset=2')).json.models.length, 2);
  assert.equal((await call('POST', '/api/lisa/models', { models: ['a/one', 'free/model:free'] })).status, 200);
  assert.deepEqual(cfgNow().models.map((m) => m.id), ['a/one', 'free/model:free']);
  assert.equal(cfgNow().models[1].vision, false);
});

test('обзор Лизы отдаёт движки SearXNG из файла Лизы', async () => {
  const o = (await call('GET', '/api/lisa/overview')).json;
  assert.deepEqual(o.engines.map((e) => e.name), ['duckduckgo', 'wikipedia', 'bing']);
});

test('смена ключа: заявка кладётся файлом, ключ нигде не возвращается', async () => {
  assert.equal((await call('POST', '/api/lisa/key', { key: 'не ключ' })).status, 400);
  assert.equal((await call('POST', '/api/lisa/key', { key: 'sk-or-коротко' })).status, 400);
  const key = 'sk-or-v1-' + 'a1b2c3d4e5'.repeat(4);
  const r = await call('POST', '/api/lisa/key', { key });
  assert.equal(r.status, 200); assert.ok(r.json.id);
  assert.ok(!JSON.stringify(r.json).includes(key));
  const f = join(ldir, 'key-request.json');
  assert.equal(statSync(f).mode & 0o777, 0o600, 'файл заявки закрыт от посторонних');
  assert.equal(JSON.parse(readFileSync(f, 'utf8')).key, key);
  assert.equal((await call('POST', '/api/lisa/key', { key })).status, 409, 'вторую заявку не принимаем, пока первая в работе');
  const st = (await call('GET', '/api/lisa/key-status')).json;
  assert.equal(st.pending, true); assert.ok(!JSON.stringify(st).includes(key));
  const log = readFileSync(join(dir, 'audit.log'), 'utf8');
  assert.match(log, /lisa\.key_requested/); assert.ok(!log.includes(key), 'ключа нет в журнале действий');
  assert.equal((await call('POST', '/api/lisa/key-cancel')).status, 200);
  assert.equal(existsSync(f), false, 'после отмены файла с ключом нет');
  assert.equal((await call('POST', '/api/lisa/key-cancel')).status, 200, 'повторная отмена безвредна');
  const r2 = await call('POST', '/api/lisa/key', { key });
  assert.equal(r2.status, 200);
  // служба сервера отвечает файлом результата и забирает заявку
  writeFileSync(join(ldir, 'key-result.json'), JSON.stringify({ id: r2.json.id, ok: false, message: 'OpenRouter ответил 401', ts: Date.now() }));
  (await import('node:fs')).unlinkSync(f);
  const st2 = (await call('GET', '/api/lisa/key-status')).json;
  assert.equal(st2.pending, false); assert.equal(st2.result.ok, false); assert.match(st2.result.message, /401/);
});

test('доступ по списку: массово, люди без ID пропускаются; игры запрещаются для всех', async () => {
  const { cfg: c, skipped } = applyAllowBulk({ allowed_dv_ids: ['*', '1'] }, [{ userId: '@a:t', dvId: '2' }, { userId: '@b:t', dvId: '' }], true);
  assert.deepEqual(c.allowed_dv_ids.sort(), ['*', '1', '2'].sort()); assert.deepEqual(skipped, ['@b:t']);
  assert.deepEqual(applyAllowBulk({ allowed_dv_ids: ['1', '2'] }, [{ userId: '@a:t', dvId: '2' }], false).cfg.allowed_dv_ids, ['1']);
  assert.throws(() => applyAllowBulk({}, [], 'да'), /да или нет/);
  const g = applyGlobal({ features: { defaults: {}, users: {} } }, { games_off_all: ['chess', 'nardy'] });
  assert.deepEqual(lisaView(g, []).games_off_all, ['chess', 'nardy']);
  assert.throws(() => applyGlobal({}, { games_off_all: ['покер'] }), /Неизвестная игра/);
  assert.equal((await call('POST', '/api/lisa/global', { games_off_all: ['durak'] })).status, 200);
  assert.deepEqual(cfgNow().features.games_off, ['durak']);
  assert.deepEqual((await call('GET', '/api/lisa')).json.games_off_all, ['durak']);
  assert.equal((await call('POST', '/api/lisa/global', { games_off_all: [] })).status, 200);
  assert.equal(cfgNow().features.games_off, undefined);
});

test('файл настроек сборки: маска секрета, сохранение чужих строк, неизменённая маска не затирает адрес', async () => {
  assert.equal(maskUrl('https://updates.example.org/s3cr3t/path/'), 'https://updates.example.org/••••••••');
  assert.equal(maskUrl('chat.example.org'), 'chat.example.org');
  writeFileSync(envPath, '# мои значения\nDVCHAT_HOMESERVER=chat.example.org\nDVCHAT_UPDATE_URL=https://u.example.org/SECRET123/\nDVCHAT_OTHER=секрет-не-для-показа\n');
  const g = (await call('GET', '/api/setup/env')).json;
  assert.equal(g.fields.updateUrl, 'https://u.example.org/••••••••');
  assert.ok(!JSON.stringify(g).includes('SECRET123') && !JSON.stringify(g).includes('секрет-не-для-показа'));
  assert.deepEqual(g.others, ['DVCHAT_OTHER']);
  // маску вернули как есть: настоящий адрес остаётся, свои строки на месте
  const s = await call('POST', '/api/setup/env', { homeserver: 'chat.example.org', pushGateway: 'https://push.example.org/PUSHSEC/', updateUrl: g.fields.updateUrl, save: true });
  assert.equal(s.status, 200);
  assert.ok(!s.json.text.includes('SECRET123') && !s.json.text.includes('PUSHSEC') && !s.json.text.includes('секрет-не-для-показа'), 'в ответе всё скрыто');
  const real = readFileSync(envPath, 'utf8');
  assert.match(real, /DVCHAT_UPDATE_URL=https:\/\/u\.example\.org\/SECRET123\//);
  assert.match(real, /DVCHAT_PUSH_GATEWAY=https:\/\/push\.example\.org\/PUSHSEC\//);
  assert.match(real, /DVCHAT_OTHER=секрет-не-для-показа/); assert.match(real, /# мои значения/);
  assert.equal(statSync(envPath).mode & 0o777, 0o600);
  assert.equal((await call('GET', '/api/setup/env?reveal=1')).json.fields.updateUrl, 'https://u.example.org/SECRET123/');
  assert.match(readFileSync(join(dir, 'audit.log'), 'utf8'), /setup\.env_revealed/);
  // очистка поля удаляет ключ
  await call('POST', '/api/setup/env', { homeserver: 'chat.example.org', pushGateway: '', updateUrl: 'https://u.example.org/SECRET123/', save: true });
  assert.ok(!/PUSH_GATEWAY/.test(readFileSync(envPath, 'utf8')));
  assert.equal((await call('POST', '/api/setup/env', { homeserver: 'плохо адрес', save: false })).status, 400);
  assert.equal(maskedEnvText('A=1\nDVCHAT_HOMESERVER=h\n').split('\n')[0], 'A=<скрыто>');
  assert.deepEqual(parseEnv('X=1\n#c\nY=2'), { X: '1', Y: '2' });
  assert.match(envText({ homeserver: 'h.example.org' }), /^# Настройки сборки DVChat/);
});

test('друзья и уведомления человека, обзор: на настоящем Synapse', async (t) => {
  const mk = await call('POST', '/api/users', { username: uname, displayname: 'Пробный', ttl_hours: 1 });
  assert.equal(mk.status, 200, JSON.stringify(mk.json));
  const uid = mk.json.user_id;
  await t.test('друзья и входящие заявки', async () => {
    const f = (await call('POST', '/api/users/friends', { user_id: uid })).json;
    assert.equal(f.friends[0].dv_id, 'DV111'); assert.equal(f.friends[0].user_id, '@anna:test.local');
    assert.equal(f.requests[0].user_id, '@bob:test.local'); assert.equal(f.all_users, false);
  });
  await t.test('уведомления: правила видны и переключаются', async () => {
    const n = (await call('POST', '/api/users/notify', { user_id: uid })).json;
    const rule = n.rules.find((r) => r.id === '.m.rule.message');
    assert.ok(rule, 'правило сообщений есть'); assert.equal(rule.notifies, true);
    assert.ok(Array.isArray(n.pushers));
    assert.equal((await call('POST', '/api/users/notify-rule', { user_id: uid, rule_id: '.m.rule.message', notifies: false })).status, 200);
    assert.equal((await call('POST', '/api/users/notify', { user_id: uid })).json.rules.find((r) => r.id === '.m.rule.message').notifies, false);
    // «подавляющее» правило: уведомлять = правило выключено
    const mem = (await call('POST', '/api/users/notify', { user_id: uid })).json.rules.find((r) => r.id === '.m.rule.member_event');
    if (mem) {
      await call('POST', '/api/users/notify-rule', { user_id: uid, rule_id: '.m.rule.member_event', notifies: !mem.notifies });
      assert.equal((await call('POST', '/api/users/notify', { user_id: uid })).json.rules.find((r) => r.id === '.m.rule.member_event').notifies, !mem.notifies);
    }
    assert.equal((await call('POST', '/api/users/notify-rule', { user_id: uid, rule_id: '.m.rule.чужое', notifies: true })).status, 400);
    assert.equal((await call('POST', '/api/users/notify-rule', { user_id: '@нет:test.local', rule_id: '.m.rule.message', notifies: true })).status >= 400, true);
  });
  await t.test('одно правило всем', async () => {
    assert.equal((await call('POST', '/api/notify/apply', { rule_id: '.m.rule.message', notifies: true })).status, 400, 'нужно слово «всем»');
    const r = await call('POST', '/api/notify/apply', { rule_id: '.m.rule.message', notifies: true, confirm: 'всем' });
    assert.equal(r.status, 200); assert.ok(r.json.changed >= 1);
    assert.equal((await call('POST', '/api/users/notify', { user_id: uid })).json.rules.find((r2) => r2.id === '.m.rule.message').notifies, true);
    const all = (await call('POST', '/api/notify/overview')).json;
    assert.ok(all.people.some((p) => p.user_id === uid)); assert.ok(all.rules.length >= 5);
  });
  await t.test('обзор: заходы, виды комнат, Лиза', async () => {
    const o = (await call('GET', '/api/overview')).json;
    assert.ok(o.users_active >= 1); assert.equal(typeof o.rooms_kinds.groups, 'number');
    assert.equal(o.activity.series.length, 14); assert.ok(o.activity.total >= 1);
    assert.equal(o.lisa.connected, true); assert.equal(o.lisa.active, 'a/one'); assert.equal(o.lisa.today.n, 2);
  });
});
