// Панель 0.3.3: подружить, убрать из друзей, служебный пуш, очистка переписки через модуль dv_social (метка для телефонов).
// Нужен Synapse с модулем dv_social. Переменные: SYNAPSE_URL, SYNAPSE_ADMIN_USER, SYNAPSE_ADMIN_PASSWORD
import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createApp } from '../server.mjs';
import { loadConfig } from '../lib/config.mjs';
import { hashPassword } from '../lib/auth.mjs';
import { Synapse } from '../lib/synapse.mjs';

const SYN = process.env.SYNAPSE_URL || 'http://127.0.0.1:18008';
const PW = 'panel-test-password';
const lr = await (await fetch(SYN + '/_matrix/client/v3/login', { method: 'POST', headers: { 'content-type': 'application/json' },
  body: JSON.stringify({ type: 'm.login.password', identifier: { type: 'm.id.user', user: process.env.SYNAPSE_ADMIN_USER || 'root' }, password: process.env.SYNAPSE_ADMIN_PASSWORD || 'Adm1n-test-pass', initial_device_display_name: 'DVChat admin' }) })).json();
const dir = mkdtempSync(join(tmpdir(), 'dv033-'));
const cfg = { ...loadConfig({ DVADMIN_DATA_DIR: dir, DVADMIN_SYNAPSE_URL: SYN }), passwordHash: hashPassword(PW), synapseToken: lr.access_token, envPath: join(dir, 'dvchat.env') };
const { server } = createApp(cfg);
await new Promise((r) => server.listen(0, '127.0.0.1', r));
const base = `http://127.0.0.1:${server.address().port}`;
test.after(() => server.close());
const syn = new Synapse({ url: SYN, token: lr.access_token });

let ck = '';
async function c(method, path, body) {
  const r = await fetch(base + path, { method, headers: { 'x-requested-with': 'dvchat-admin', ...(ck ? { cookie: ck } : {}), ...(body ? { 'content-type': 'application/json' } : {}) }, body: body ? JSON.stringify(body) : undefined });
  const sc = r.headers.get('set-cookie'); if (sc && !sc.includes('Max-Age=0')) ck = sc.split(';')[0];
  let json = {}; try { json = await r.json(); } catch {}
  return { status: r.status, json };
}
const sfx = Date.now().toString(36);
const [A, B, C] = ['pa', 'pb', 'pc'].map((x) => x + sfx);
const id = (u) => `@${u}:test.local`;
const enc = encodeURIComponent;

test('вход и создание людей', async () => {
  assert.equal((await c('POST', '/api/login', { password: PW })).status, 200);
  for (const u of [A, B, C]) assert.equal((await c('POST', '/api/users', { username: u })).status, 200);
});

let room;
test('подружить: взаимно и с личным чатом, повтор безопасен', async () => {
  const r = await c('POST', '/api/people/befriend', { a: A, b: B });
  assert.equal(r.status, 200, JSON.stringify(r.json));
  assert.equal(r.json.status, 'added'); assert.ok(r.json.room_id); room = r.json.room_id;
  const again = await c('POST', '/api/people/befriend', { a: id(B), b: id(A) });
  assert.equal(again.json.status, 'already'); assert.equal(again.json.room_id, room); assert.equal(again.json.chat_existed, true);
  const f = (await c('POST', '/api/users/friends', { user_id: id(A) })).json;
  assert.ok(f.friends.some((x) => x.user_id === id(B)));
  const g = (await c('POST', '/api/users/friends', { user_id: id(B) })).json;
  assert.ok(g.friends.some((x) => x.user_id === id(A)));
  assert.equal((await c('POST', '/api/people/befriend', { a: A, b: A })).status, 400);
  assert.equal((await c('POST', '/api/people/befriend', { a: A, b: 'net' + sfx })).status, 404);
});

test('пуш от «DVChat»: приходит сообщением в личный чат получателя', async () => {
  const r = await c('POST', '/api/people/push', { user_ids: [A, B], text: 'Привет из админки' });
  assert.equal(r.status, 200, JSON.stringify(r.json)); assert.equal(r.json.sent.length, 2); assert.deepEqual(r.json.failed, []);
  assert.equal((await c('POST', '/api/people/push', { user_ids: [], text: 'x' })).status, 400);
  assert.equal((await c('POST', '/api/people/push', { user_ids: [A], text: '  ' })).status, 400);
  const seen = await syn.asUser(id(A), async (as) => {
    const jr = (await as.req('GET', '/_matrix/client/v3/joined_rooms')).joined_rooms;
    for (const rid of jr) {
      const m = (await as.req('GET', `/_matrix/client/v3/rooms/${enc(rid)}/messages?dir=b&limit=20`)).chunk || [];
      if (m.some((e) => e.content?.body === 'Привет из админки')) return true;
    }
    return false;
  });
  assert.ok(seen);
});

test('очистка через модуль: сообщения стёрты, метка очистки поставлена', async () => {
  await syn.asUser(id(A), (as) => as.req('PUT', `/_matrix/client/v3/rooms/${enc(room)}/send/m.room.message/t${sfx}1`, { msgtype: 'm.text', body: 'одно' }));
  await syn.asUser(id(B), (as) => as.req('PUT', `/_matrix/client/v3/rooms/${enc(room)}/send/m.room.message/t${sfx}2`, { msgtype: 'm.text', body: 'два' }));
  assert.equal((await c('POST', '/api/rooms/clear', { room_id: room, confirm: 'нет' })).status, 400);
  const r = await c('POST', '/api/rooms/clear', { room_id: room, confirm: 'очистить' });
  assert.equal(r.status, 200, JSON.stringify(r.json)); assert.equal(r.json.notified, true);
  const left = await syn.asUser(id(A), async (as) => ({
    msgs: ((await as.req('GET', `/_matrix/client/v3/rooms/${enc(room)}/messages?dir=b&limit=50`)).chunk || []).filter((e) => e.type === 'm.room.message'),
    mark: await as.getState(room, 'online.dvbstudio.dvchat.cleared'),
  }));
  assert.equal(left.msgs.length, 0); assert.ok(left.mark.ts > 0);
});

test('убрать из друзей: у обоих, чат остаётся', async () => {
  const r = await c('POST', '/api/people/unfriend', { a: A, b: B });
  assert.equal(r.status, 200, JSON.stringify(r.json)); assert.equal(r.json.status, 'removed');
  assert.equal((await c('POST', '/api/people/unfriend', { a: A, b: B })).json.status, 'not_friends');
  const f = (await c('POST', '/api/users/friends', { user_id: id(B) })).json;
  assert.ok(!f.friends.some((x) => x.user_id === id(A)));
  assert.ok((await syn.room(room)).joined_members >= 2);
});
