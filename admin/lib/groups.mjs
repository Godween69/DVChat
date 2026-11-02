// Группы: роли и права через уровни доступа Matrix (power levels).
// Уровни — лестница: выдавая право, человек получает и все права ниже него. Это ограничение самой Matrix.
//
// На сервере могут быть запрещены приглашения от обычных людей (block_non_admin_invites).
// Поэтому права и исключения выполняет сам владелец группы (вход от его имени на 2 минуты),
// а администратор заходит в группу только чтобы добавить людей: через служебную комнату,
// в которой состоит он один. Группа разрешает вход участникам этой комнаты (restricted),
// приглашение администратору не нужно. Закончив, администратор сразу выходит.
export const LADDER = [
  { key: 'invite', level: 10, label: 'Приглашать людей' },
  { key: 'kick', level: 20, label: 'Удалять людей из группы' },
  { key: 'ban', level: 30, label: 'Блокировать людей' },
  { key: 'redact', level: 40, label: 'Удалять чужие сообщения' },
  { key: 'edit', level: 50, label: 'Менять название, фото и тему' },
  { key: 'manage', level: 100, label: 'Управлять правами (владелец)' },
];

export const levelFromPerms = (perms) =>
  LADDER.reduce((lvl, p) => (perms && perms[p.key] ? Math.max(lvl, p.level) : lvl), 0);

export const permsFromLevel = (level) =>
  Object.fromEntries(LADDER.map((p) => [p.key, level >= p.level]));

// Пороги в комнате: что сколько стоит
export function roomPowerTemplate({ owner }) {
  // Создателя комнаты (администратора) в списке не указываем: в новых версиях комнат это запрещено
  return {
    users: { [owner]: 100 },
    users_default: 0,
    events_default: 0,
    state_default: 50,
    invite: 10, kick: 20, ban: 30, redact: 40,
    events: {
      'm.room.name': 50, 'm.room.avatar': 50, 'm.room.topic': 50,
      'm.room.power_levels': 100, 'm.room.encryption': 100, 'm.room.history_visibility': 100,
      'm.room.join_rules': 100, 'm.room.tombstone': 100, 'm.room.server_acl': 100,
    },
  };
}

// Ошибка, понятная человеку: уходит в панель как есть (статус 400)
export class GroupError extends Error {
  constructor(message) { super(message); this.status = 400; this.code = 'BAD_REQUEST'; }
}

// Правило входа «только участники служебной комнаты (плюс приглашённые)»
export const gateRule = (serviceRoomId) => ({ join_rule: 'restricted', allow: [{ type: 'm.room_membership', room_id: serviceRoomId }] });

// Кто в комнате и какие у кого права
async function powerInfo(syn, roomId) {
  const [members, state] = await Promise.all([syn.roomMembers(roomId), syn.roomState(roomId)]);
  const events = state.state || [];
  const pl = events.find((e) => e.type === 'm.room.power_levels')?.content || {};
  return {
    members: members.members || [], pl, events,
    level: (id) => pl.users?.[id] ?? pl.users_default ?? 0,
    need: (type) => pl.events?.[type] ?? pl.state_default ?? 50,
  };
}

// Подходящий человек для действия: с достаточными правами, выше цели, не удалённый (за удалённого войти нельзя)
async function pickActor(syn, info, need, { exclude = [], above = -1 } = {}) {
  const cands = info.members.filter((m) => !exclude.includes(m) && info.level(m) >= need && info.level(m) > above)
    .sort((a, b) => info.level(b) - info.level(a));
  for (const m of cands) {
    const u = await syn.user(m).catch(() => null);
    if (u && !u.deactivated) return m;
  }
  throw new GroupError('В группе нет человека, у которого хватает прав на это действие (Matrix не даёт менять права равного или более высокого)');
}

export async function createGroup(ctx, { name, topic, owner, members = [], encrypted = true }) {
  const { syn, serviceRoom } = ctx;
  const gate = gateRule(await serviceRoom());
  const initial = [{ type: 'm.room.join_rules', state_key: '', content: gate }];
  if (encrypted) initial.push({ type: 'm.room.encryption', state_key: '', content: { algorithm: 'm.megolm.v1.aes-sha2' } });
  const { room_id: roomId } = await syn.createRoom({
    name, topic: topic || undefined, preset: 'private_chat', visibility: 'private',
    power_level_content_override: roomPowerTemplate({ owner }), initial_state: initial,
  });
  const failed = [];
  for (const uid of new Set([owner, ...members])) {
    try { await syn.joinUser(roomId, uid); } catch (e) { failed.push({ user: uid, error: e.message }); }
  }
  // Администратор уходит: в списке чатов у людей его не будет
  await syn.leaveRoom(roomId);
  await syn.forgetRoom(roomId);
  return { room_id: roomId, failed };
}

export async function groupDetails(syn, roomId) {
  const [room, info] = await Promise.all([syn.room(roomId), powerInfo(syn, roomId)]);
  const members = [];
  for (const id of info.members) {
    const u = await syn.user(id).catch(() => null);
    members.push({ user_id: id, displayname: u?.displayname || '', deactivated: Boolean(u?.deactivated), level: info.level(id), perms: permsFromLevel(info.level(id)) });
  }
  return { room_id: roomId, name: room.name, topic: room.topic, encrypted: Boolean(room.encryption), members };
}

export async function setMemberPerms(ctx, roomId, userId, perms) {
  const { syn } = ctx;
  const level = levelFromPerms(perms);
  const info = await powerInfo(syn, roomId);
  const cur = info.level(userId);
  if (cur >= 100 && level < 100 && !info.members.some((m) => m !== userId && info.level(m) >= 100)) {
    throw new GroupError('Нельзя снять права у единственного владельца: сначала назначьте другого');
  }
  const actor = await pickActor(syn, info, info.need('m.room.power_levels'), { exclude: [userId], above: cur });
  await syn.asUser(actor, async (as) => {
    const now = await as.getState(roomId, 'm.room.power_levels');
    const users = { ...(now.users || {}) };
    if (level === 0) delete users[userId]; else users[userId] = level;
    await as.sendState(roomId, 'm.room.power_levels', { ...now, users });
  });
  return { level, perms: permsFromLevel(level) };
}

export async function removeMember(ctx, roomId, userId) {
  const { syn } = ctx;
  const info = await powerInfo(syn, roomId);
  const actor = await pickActor(syn, info, info.pl.kick ?? 50, { exclude: [userId], above: info.level(userId) });
  await syn.asUser(actor, (as) => as.kick(roomId, userId, 'Удалён администратором'));
}

export async function addMembers(ctx, roomId, userIds) {
  const { syn, adminId, serviceRoom } = ctx;
  const info = await powerInfo(syn, roomId);
  const service = await serviceRoom();
  const jr = info.events.find((e) => e.type === 'm.room.join_rules')?.content || {};
  const gated = jr.join_rule === 'restricted' && (jr.allow || []).some((a) => a.type === 'm.room_membership' && a.room_id === service);
  if (!gated) {
    const actor = await pickActor(syn, info, info.need('m.room.join_rules'));
    await syn.asUser(actor, (as) => as.sendState(roomId, 'm.room.join_rules', gateRule(service)));
  }
  const wasIn = info.members.includes(adminId);
  if (!wasIn) await syn.joinRoom(roomId);
  const failed = [];
  try {
    for (const uid of userIds) {
      try { await syn.joinUser(roomId, uid); } catch (e) { if (!/already in the room/.test(e.message)) failed.push({ user: uid, error: e.message }); }
    }
  } finally {
    if (!wasIn) { try { await syn.leaveRoom(roomId); await syn.forgetRoom(roomId); } catch { /* уже вышел */ } }
  }
  return { failed };
}

// Из каких комнат человека надо вывести перед удалением и где он единственный владелец
export async function userRoomsPlan(syn, userId) {
  const ids = (await syn.joinedRooms(userId)).joined_rooms || [];
  const leave = [], blockers = [];
  for (const id of ids) {
    const info = await powerInfo(syn, id);
    const others = info.members.filter((m) => m !== userId);
    if (others.length && info.level(userId) >= 100 && !others.some((m) => info.level(m) >= 100)) {
      const room = await syn.room(id).catch(() => ({}));
      blockers.push(room.name || id);
    }
    leave.push(id);
  }
  return { leave, blockers };
}

export async function leaveRooms(syn, userId, roomIds) {
  if (!roomIds.length) return 0;
  return syn.asUser(userId, async (as) => {
    let n = 0;
    for (const id of roomIds) {
      try { await as.leaveRoom(id); n++; } catch { /* уже не в комнате */ }
      try { await as.forgetRoom(id); } catch { /* не критично */ }
    }
    return n;
  });
}
