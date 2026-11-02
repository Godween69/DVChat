// Тесты групп и комнат против настоящего Synapse с запретом приглашений от обычных людей
// (block_non_admin_invites: true). Переменные: SYNAPSE_URL, SYNAPSE_ADMIN_USER, SYNAPSE_ADMIN_PASSWORD
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
const dir = mkdtempSync(join(tmpdir(), 'dvgroups-'));
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
const [A, B, C, D, E] = ['oa', 'ob', 'oc', 'od', 'oe'].map((x) => x + sfx);
const id = (u) => `@${u}:test.local`;

test('вход и создание людей', async () => {
  assert.equal((await c('POST', '/api/login', { password: PW })).status, 200);
  for (const u of [A, B, C, D, E]) assert.equal((await c('POST', '/api/users', { username: u, displayname: 'Имя ' + u })).status, 200);
});

test('группа при запрете приглашений: создание, добавление, права, исключение', async (t) => {
  const g = await c('POST', '/api/groups', { name: 'Группа ' + sfx, owner: A, members: [B], encrypted: true });
  assert.equal(g.status, 200, JSON.stringify(g.json)); assert.deepEqual(g.json.failed, []);
  const rid = g.json.room_id;
  const det = async () => (await c('POST', '/api/groups/details', { room_id: rid })).json;
  assert.equal((await det()).members.length, 2);

  await t.test('приглашение владельцем сервер запрещает (условие теста)', async () => {
    await assert.rejects(() => syn.asUser(id(A), (as) => as.invite(rid, id(C))), /Invites have been disabled/);
  });
  await t.test('добавить человека', async () => {
    const r = await c('POST', '/api/groups/add', { room_id: rid, members: [C] });
    assert.equal(r.status, 200, JSON.stringify(r.json)); assert.deepEqual(r.json.failed, []);
    const d = await det(); assert.equal(d.members.length, 3);
    assert.ok(!d.members.some((m) => m.user_id === '@root:test.local'), 'администратор вышел');
  });
  await t.test('добавить ещё раз (вход уже разрешён)', async () => {
    assert.equal((await c('POST', '/api/groups/add', { room_id: rid, members: [D] })).status, 200);
    assert.equal((await det()).members.length, 4);
  });
  await t.test('права флажками', async () => {
    const p = await c('POST', '/api/groups/perms', { room_id: rid, user_id: B, perms: { invite: true, kick: true } });
    assert.equal(p.status, 200, JSON.stringify(p.json)); assert.equal(p.json.level, 20);
    assert.equal((await det()).members.find((m) => m.user_id === id(B)).perms.kick, true);
    assert.equal((await c('POST', '/api/groups/perms', { room_id: rid, user_id: B, perms: {} })).json.level, 0);
  });
  await t.test('нельзя снять права у единственного владельца', async () => {
    const r = await c('POST', '/api/groups/perms', { room_id: rid, user_id: A, perms: {} });
    assert.equal(r.status, 400); assert.match(r.json.error, /единственного владельца/);
  });
  await t.test('убрать человека', async () => {
    assert.equal((await c('POST', '/api/groups/remove', { room_id: rid, user_id: D })).status, 200);
    assert.equal((await det()).members.length, 3);
  });
  await t.test('подписи в группе и в списке комнат', async () => {
    const rooms = (await c('GET', '/api/rooms')).json.rooms;
    const mine = rooms.find((x) => x.room_id === rid);
    assert.equal(mine.kind, 'group'); assert.equal(mine.label, 'Группа ' + sfx);
  });
});

test('служебная комната: одна, защищена от удаления', async () => {
  const rooms = (await c('GET', '/api/rooms')).json.rooms;
  const svc = rooms.filter((x) => x.kind === 'service');
  assert.equal(svc.length, 1); assert.equal(svc[0].members, 1);
  assert.equal(svc[0].label, 'Служебная комната админки');
  const r = await c('POST', '/api/rooms/delete', { room_id: svc[0].room_id, confirm: svc[0].name });
  assert.equal(r.status, 400);
});

test('удаление человека выводит его из групп; единственного владельца не удалить', async () => {
  const g = await c('POST', '/api/groups', { name: 'Вторая ' + sfx, owner: A, members: [B, E], encrypted: true });
  const rid = g.json.room_id;
  const r1 = await c('POST', '/api/users/deactivate', { user_id: A, confirm: A });
  assert.equal(r1.status, 400); assert.match(r1.json.error, /единственный владелец/);
  const r2 = await c('POST', '/api/users/deactivate', { user_id: E, confirm: E });
  assert.equal(r2.status, 200, JSON.stringify(r2.json)); assert.ok(r2.json.left >= 1);
  const d = (await c('POST', '/api/groups/details', { room_id: rid })).json;
  assert.ok(!d.members.some((m) => m.user_id === id(E)), 'удалённый вышел из группы');
});

test('комнаты: подписи безымянных, пустые, фильтр удалённых', async () => {
  // личный чат без названия между B и C
  const dm = (await syn.createRoom({ preset: 'trusted_private_chat', is_direct: true })).room_id;
  await syn.joinUser(dm, id(B)); await syn.joinUser(dm, id(C)); await syn.leaveRoom(dm); await syn.forgetRoom(dm);
  // чат, где остался один (второй удалён): D и удалённый E
  const half = (await syn.createRoom({ preset: 'trusted_private_chat', is_direct: true })).room_id;
  await syn.joinUser(half, id(D)); await syn.leaveRoom(half); await syn.forgetRoom(half);
  // чат, где собеседник вышел: B вошёл и вышел, остался C
  const gone = (await syn.createRoom({ preset: 'trusted_private_chat', is_direct: true })).room_id;
  await syn.joinUser(gone, id(B)); await syn.joinUser(gone, id(C)); await syn.leaveRoom(gone); await syn.forgetRoom(gone);
  await syn.asUser(id(B), (as) => as.leaveRoom(gone));
  // обращение в поддержку: название «Имя @логин (ID)», внутри админ, человек приглашён
  const sup = (await syn.createRoom({ name: 'Проба @' + C + ' (1234567890)', preset: 'private_chat', invite: [id(C)] }).catch(() => syn.createRoom({ name: 'Проба @' + C + ' (1234567890)', preset: 'private_chat' }))).room_id;
  // пустая
  const empty = (await syn.createRoom({ name: undefined })).room_id; await syn.leaveRoom(empty); await syn.forgetRoom(empty);

  const rooms = (await c('GET', '/api/rooms')).json;
  const m = rooms.rooms.find((x) => x.room_id === dm);
  assert.equal(m.kind, 'direct'); assert.match(m.label, /^Личный чат: Имя ob.+ и Имя oc.+|^Личный чат: Имя oc.+ и Имя ob.+/);
  const gn = rooms.rooms.find((x) => x.room_id === gone);
  assert.match(gn.label, /собеседник вышел/, gn.label);
  const sp = rooms.rooms.find((x) => x.room_id === sup);
  assert.equal(sp.kind, 'support'); assert.match(sp.label, /^Поддержка: /);
  assert.ok((await c('GET', '/api/rooms?filter=support')).json.rooms.every((x) => x.kind === 'support'));
  const e = rooms.rooms.find((x) => x.room_id === empty);
  assert.equal(e.kind, 'empty'); assert.equal(e.label, 'Пустая комната (никого внутри)');
  assert.ok(rooms.empty_count >= 1);
  const only = (await c('GET', '/api/rooms?filter=empty')).json.rooms; assert.ok(only.every((x) => x.kind === 'empty'));
  const del = (await c('GET', '/api/rooms?filter=deleted')).json.rooms; assert.ok(del.every((x) => x.has_deleted));

  // удалить пустые: нужно ввести число, служебная комната остаётся
  assert.equal((await c('POST', '/api/rooms/delete-empty', { confirm: '999999' })).status, 400);
  const n = rooms.empty_count;
  const r = await c('POST', '/api/rooms/delete-empty', { confirm: String(n) });
  assert.equal(r.status, 200); assert.equal(r.json.deleted, n);
  await new Promise((res) => setTimeout(res, 1500));
  const after = (await c('GET', '/api/rooms')).json;
  assert.equal(after.empty_count, 0); assert.ok(after.rooms.some((x) => x.kind === 'service'), 'служебная комната осталась');

  // удаление безымянной комнаты: подтверждение словом «удалить»
  assert.equal((await c('POST', '/api/rooms/delete', { room_id: dm, confirm: 'не то' })).status, 400);
  assert.equal((await c('POST', '/api/rooms/delete', { room_id: dm, confirm: 'удалить' })).status, 200);
});

test('выход на остальных устройствах, кроме выбранного', async () => {
  const u = id(B);
  // Устройства создаёт обычный вход по паролю
  await syn.putUser(u, { password: 'Devices-test-pass-1' });
  for (let i = 0; i < 3; i++) {
    const lg = await fetch(SYN + '/_matrix/client/v3/login', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ type: 'm.login.password', identifier: { type: 'm.id.user', user: B }, password: 'Devices-test-pass-1', initial_device_display_name: 'тест ' + i }) });
    assert.equal(lg.status, 200);
  }
  const devs = (await c('POST', '/api/users/devices', { user_id: B })).json.devices;
  assert.ok(devs.length >= 3);
  assert.equal((await c('POST', '/api/users/logout-others', { user_id: B, keep: 'нет-такого' })).status, 400);
  const keep = devs[0].id;
  const r = await c('POST', '/api/users/logout-others', { user_id: B, keep });
  assert.equal(r.status, 200); assert.equal(r.json.devices_removed, devs.length - 1);
  const left = (await c('POST', '/api/users/devices', { user_id: B })).json.devices;
  assert.deepEqual(left.map((x) => x.id), [keep]);
});

test('очистка переписки: сообщения стёрты, комната и люди остаются', async () => {
  const g = await c('POST', '/api/groups', { name: 'Очистка ' + sfx, owner: B, members: [C], encrypted: true });
  const rid = g.json.room_id; const q = encodeURIComponent(rid);
  const say = (as, t) => as.req('PUT', `/_matrix/client/v3/rooms/${q}/send/m.room.message/${Math.random().toString(36).slice(2)}`, { msgtype: 'm.text', body: t });
  const lineOf = (as) => as.req('GET', `/_matrix/client/v3/rooms/${q}/messages?dir=b&limit=100`).then((r) => r.chunk.filter((e) => e.state_key === undefined && e.type === 'm.room.message'));
  await syn.asUser(id(B), async (as) => { for (let i = 1; i <= 4; i++) await say(as, 'привет ' + i); });
  await syn.asUser(id(C), async (as) => { await say(as, 'ответ'); });
  assert.equal((await syn.asUser(id(B), lineOf)).length, 5);
  assert.equal((await c('POST', '/api/rooms/clear', { room_id: rid, confirm: 'не то' })).status, 400);
  const r = await c('POST', '/api/rooms/clear', { room_id: rid, confirm: 'очистить' });
  assert.equal(r.status, 200, JSON.stringify(r.json));
  assert.equal((await syn.asUser(id(B), lineOf)).length, 0, 'лента пустая');
  const d = (await c('POST', '/api/groups/details', { room_id: rid })).json;
  assert.equal(d.members.length, 2); assert.equal(d.name, 'Очистка ' + sfx);
  await syn.asUser(id(C), async (as) => { await say(as, 'после очистки'); });
  assert.equal((await syn.asUser(id(B), lineOf)).length, 1, 'новые сообщения работают');
  const svc = (await c('GET', '/api/rooms')).json.rooms.find((x) => x.kind === 'service');
  assert.equal((await c('POST', '/api/rooms/clear', { room_id: svc.room_id, confirm: 'очистить' })).status, 400);
});
