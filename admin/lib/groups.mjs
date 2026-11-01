// Группы: роли и права через уровни доступа Matrix (power levels).
// Уровни — лестница: выдавая право, человек получает и все права ниже него. Это ограничение самой Matrix.
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

// Выполнить действие от имени администратора внутри комнаты и вернуть всё как было
export async function withAdminInRoom(syn, adminId, roomId, fn) {
  const members = await syn.roomMembers(roomId);
  const wasIn = (members.members || []).includes(adminId);
  if (!wasIn) {
    // Закрытая группа: администратора приглашает от своего имени тот, у кого есть право приглашать
    const state = await syn.roomState(roomId);
    const pl = (state.state || []).find((e) => e.type === 'm.room.power_levels')?.content || {};
    const need = pl.invite ?? 0;
    const inviter = (members.members || []).filter((m) => (pl.users?.[m] ?? pl.users_default ?? 0) >= need)
      .sort((a, b) => (pl.users?.[b] ?? 0) - (pl.users?.[a] ?? 0))[0];
    if (!inviter) throw new Error('В группе нет человека с правом приглашать');
    await syn.asUser(inviter, (as) => as.invite(roomId, adminId));
    await syn.joinRoom(roomId);
  }
  try {
    return await fn();
  } finally {
    if (!wasIn) {
      try { await syn.leaveRoom(roomId); await syn.forgetRoom(roomId); } catch { /* уже вышел */ }
    }
  }
}

export async function createGroup(syn, adminId, { name, topic, owner, members = [], encrypted = true }) {
  const body = {
    name, topic: topic || undefined,
    preset: 'private_chat', visibility: 'private',
    power_level_content_override: roomPowerTemplate({ owner }),
    initial_state: encrypted ? [{ type: 'm.room.encryption', state_key: '', content: { algorithm: 'm.megolm.v1.aes-sha2' } }] : [],
  };
  const { room_id: roomId } = await syn.createRoom(body);
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
  const [room, members, state] = await Promise.all([syn.room(roomId), syn.roomMembers(roomId), syn.roomState(roomId)]);
  const pl = (state.state || []).find((e) => e.type === 'm.room.power_levels');
  const users = pl?.content?.users || {};
  return {
    room_id: roomId, name: room.name, topic: room.topic, encrypted: Boolean(room.encryption),
    members: (members.members || []).map((id) => ({ user_id: id, level: users[id] ?? (pl?.content?.users_default ?? 0), perms: permsFromLevel(users[id] ?? 0) })),
  };
}

export async function setMemberPerms(syn, adminId, roomId, userId, perms) {
  const level = levelFromPerms(perms);
  return withAdminInRoom(syn, adminId, roomId, async () => {
    const cur = await syn.getState(roomId, 'm.room.power_levels');
    const users = { ...(cur.users || {}) };
    if (level === 0) delete users[userId]; else users[userId] = level;
    await syn.sendState(roomId, 'm.room.power_levels', { ...cur, users });
    return { level, perms: permsFromLevel(level) };
  });
}

export async function addMembers(syn, adminId, roomId, userIds) {
  const failed = [];
  await withAdminInRoom(syn, adminId, roomId, async () => {
    for (const uid of userIds) {
      try { await syn.joinUser(roomId, uid); } catch (e) { if (!/already in the room/.test(e.message)) failed.push({ user: uid, error: e.message }); }
    }
  });
  return { failed };
}

export async function removeMember(syn, adminId, roomId, userId) {
  return withAdminInRoom(syn, adminId, roomId, () => syn.kick(roomId, userId, 'Удалён администратором'));
}
