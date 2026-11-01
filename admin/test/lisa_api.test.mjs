// Раздел «Лиза»: интерфейс обмена с файлами, которые пишет сама Лиза (panel_dir), и с config.json
import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, writeFileSync, readFileSync, mkdirSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createApp } from '../server.mjs';
import { loadConfig } from '../lib/config.mjs';
import { hashPassword } from '../lib/auth.mjs';

const SYN = process.env.SYNAPSE_URL || 'http://127.0.0.1:18008';
const lr = await (await fetch(SYN + '/_matrix/client/v3/login', { method: 'POST', headers: { 'content-type': 'application/json' },
  body: JSON.stringify({ type: 'm.login.password', identifier: { type: 'm.id.user', user: process.env.SYNAPSE_ADMIN_USER || 'root' }, password: process.env.SYNAPSE_ADMIN_PASSWORD || 'Adm1n-test-pass', initial_device_display_name: 'DVChat admin' }) })).json();
const dir = mkdtempSync(join(tmpdir(), 'dvlisa-'));
const pdir = join(dir, 'panel'); mkdirSync(pdir);
const cpath = join(dir, 'config.json');
const today = new Date().toISOString().slice(0, 10);
writeFileSync(cpath, JSON.stringify({ admins: [], allowed_dv_ids: [], models: [{ id: 'a/one' }, { id: 'b/two' }], system_prompt: 'x'.repeat(40) }));
const J = (n, o) => writeFileSync(join(pdir, n), JSON.stringify(o));
J('state.json', { ts: Date.now() / 1000, version: '3', active: 'b/two', questions_days: 14,
  models: [{ id: 'a/one', up: false, error: 'таймаут', price_in: 1, price_out: 5 }, { id: 'b/two', up: true, price_in: 0.1, price_out: 0.5 }],
  key: { mask: 'sk-or-v1-…1234', ok: true, usage: 3.2, limit: 10, remaining: 6.8, checked: Date.now() / 1000 } });
J('catalog.json', { models: [{ id: 'a/one', name: 'One', price_in: 1, price_out: 5 }, { id: 'c/three', name: 'Three Haiku', price_in: 0.1, price_out: 0.5 }] });
J('stats.json', { today, days: [{ day: today, n: 3, tin: 30, tout: 10, cost: 0.12 }], users: [{ user: '@root:test', day: today, n: 3, tin: 30, tout: 10, cost: 0.12 }], models: [{ model: 'b/two', n: 3, tin: 30, tout: 10, cost: 0.12 }] });
J('requests.json', { ts: 1, days: 14, items: [{ ts: 1, user: '@root:test', model: 'b/two', ok: true, tool: 'search', question: 'Какая погода?', tin: 1, tout: 1, cost: 0.01 }] });

const gpath = join(dir, 'guide.md'); writeFileSync(gpath, 'Старый справочник. '.repeat(10));
const cfg = { ...loadConfig({ DVADMIN_LISA_GUIDE: gpath, DVADMIN_DATA_DIR: dir, DVADMIN_SYNAPSE_URL: SYN, DVADMIN_LISA_CONFIG: cpath, DVADMIN_LISA_PANEL_DIR: pdir }), passwordHash: hashPassword('pw-test'), synapseToken: lr.access_token, envPath: join(dir, 'e.env') };
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

test('Лиза: обзор показывает ключ маской, модели, расход', async () => {
  assert.equal((await call('POST', '/api/login', { password: 'pw-test' })).status, 200);
  const o = (await call('GET', '/api/lisa/overview')).json;
  assert.equal(o.enabled, true); assert.equal(o.state.key.mask, 'sk-or-v1-…1234'); assert.equal(o.state.active, 'b/two');
  assert.equal(o.models[0].up, false); assert.equal(o.models[1].price_in, 0.1);
  assert.equal(o.stats.totals.today.cost, 0.12); assert.equal(o.stats.users[0].label, 'root');
  assert.ok(!JSON.stringify(o).includes('sk-or-v1-abc'), 'полного ключа нет нигде');
});

test('Лиза: каталог, запросы и смена порядка моделей', async () => {
  const c = (await call('GET', '/api/lisa/catalog?q=haiku')).json; assert.equal(c.models.length, 1); assert.equal(c.models[0].id, 'c/three');
  const r = (await call('GET', '/api/lisa/requests')).json; assert.equal(r.items[0].question, 'Какая погода?'); assert.equal(r.items[0].label, 'root');
  assert.equal((await call('GET', '/api/lisa/requests?user=@кто:test')).json.items.length, 0);
  assert.equal((await call('POST', '/api/lisa/models', { models: ['x/нет'] })).status, 400);
  assert.equal((await call('POST', '/api/lisa/models', { models: ['b/two', 'c/three', 'a/one'] })).status, 200);
  assert.deepEqual(JSON.parse(readFileSync(cpath, 'utf8')).models.map((m) => m.id), ['b/two', 'c/three', 'a/one']);
  assert.equal(JSON.parse(readFileSync(cpath, 'utf8')).system_prompt.length, 40, 'чужие поля не потеряны');
});

test('Лиза: без подключённых файлов раздел отключён, а не падает', async () => {
  const a = createApp({ ...cfg, lisaConfigPath: '', lisaPanelDir: '' });
  await new Promise((r) => a.server.listen(0, '127.0.0.1', r));
  const b = `http://127.0.0.1:${a.server.address().port}`;
  const lg = await fetch(b + '/api/login', { method: 'POST', headers: { 'x-requested-with': 'dvchat-admin', 'content-type': 'application/json' }, body: JSON.stringify({ password: 'pw-test' }) });
  const cookie = lg.headers.get('set-cookie').split(';')[0];
  const r = await fetch(b + '/api/lisa/overview', { headers: { 'x-requested-with': 'dvchat-admin', cookie } });
  assert.deepEqual(await r.json(), { enabled: false });
  a.server.close();
});

test('Лиза: справочник читается, правится, копия сохраняется, лишнего не пускает', async () => {
  const { readdirSync, statSync } = await import('node:fs');
  const g = (await call('GET', '/api/lisa/guide')).json; assert.equal(g.enabled, true); assert.match(g.text, /Старый справочник/);
  assert.equal((await call('POST', '/api/lisa/guide', { text: 'коротко' })).status, 400);
  assert.equal((await call('POST', '/api/lisa/guide', { text: 'я'.repeat(30001) })).status, 400);
  const txt = 'Новая функция: сторис. '.repeat(10);
  assert.equal((await call('POST', '/api/lisa/guide', { text: txt })).status, 200);
  assert.match(readFileSync(gpath, 'utf8'), /Новая функция/);
  assert.ok(readdirSync(dir).some((f) => f.startsWith('guide.md.bak-')), 'копия прежней версии');
  assert.equal(statSync(gpath).mode & 0o777, 0o644, 'Лиза читает файл под другим пользователем');
});
