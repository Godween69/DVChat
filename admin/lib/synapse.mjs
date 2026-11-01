// Клиент Synapse: Admin API и клиентский API. Токен только из секретного файла, в журнал не попадает.
export class SynapseError extends Error {
  constructor(status, errcode, message) { super(message); this.status = status; this.errcode = errcode; }
}

export class Synapse {
  constructor({ url, token, fetchImpl = fetch }) { this.url = url; this.token = token; this.f = fetchImpl; }

  async req(method, path, body, query) {
    const u = new URL(this.url + path);
    for (const [k, v] of Object.entries(query || {})) if (v !== undefined && v !== '' && v !== null) u.searchParams.set(k, String(v));
    let res;
    try {
      res = await this.f(u, {
        method,
        headers: { Authorization: `Bearer ${this.token}`, ...(body !== undefined ? { 'Content-Type': 'application/json' } : {}) },
        body: body !== undefined ? JSON.stringify(body) : undefined,
        signal: AbortSignal.timeout(30_000),
      });
    } catch (e) {
      throw new SynapseError(502, 'DVADMIN_UNREACHABLE', 'Нет связи с Synapse');
    }
    let json = {};
    try { json = await res.json(); } catch { /* пустой ответ */ }
    if (!res.ok) throw new SynapseError(res.status, json.errcode || 'ERROR', json.error || `Ошибка ${res.status}`);
    return json;
  }

  whoami() { return this.req('GET', '/_matrix/client/v3/account/whoami'); }
  version() { return this.req('GET', '/_synapse/admin/v1/server_version'); }
  users(query) { return this.req('GET', '/_synapse/admin/v2/users', undefined, query); }
  user(id) { return this.req('GET', `/_synapse/admin/v2/users/${encodeURIComponent(id)}`); }
  putUser(id, body) { return this.req('PUT', `/_synapse/admin/v2/users/${encodeURIComponent(id)}`, body); }
  devices(id) { return this.req('GET', `/_synapse/admin/v2/users/${encodeURIComponent(id)}/devices`); }
  deleteDevices(id, ids) { return this.req('POST', `/_synapse/admin/v2/users/${encodeURIComponent(id)}/delete_devices`, { devices: ids }); }
  joinedRooms(id) { return this.req('GET', `/_synapse/admin/v1/users/${encodeURIComponent(id)}/joined_rooms`); }
  deactivate(id, erase) { return this.req('POST', `/_synapse/admin/v1/deactivate/${encodeURIComponent(id)}`, { erase: Boolean(erase) }); }
  rooms(query) { return this.req('GET', '/_synapse/admin/v1/rooms', undefined, query); }
  room(id) { return this.req('GET', `/_synapse/admin/v1/rooms/${encodeURIComponent(id)}`); }
  roomMembers(id) { return this.req('GET', `/_synapse/admin/v1/rooms/${encodeURIComponent(id)}/members`); }
  roomState(id) { return this.req('GET', `/_synapse/admin/v1/rooms/${encodeURIComponent(id)}/state`); }
  deleteRoom(id, purge = true) { return this.req('DELETE', `/_synapse/admin/v2/rooms/${encodeURIComponent(id)}`, { purge, block: false }); }
  deleteRoomStatus(id) { return this.req('GET', `/_synapse/admin/v2/rooms/${encodeURIComponent(id)}/delete_status`); }
  makeRoomAdmin(room, userId) { return this.req('POST', `/_synapse/admin/v1/rooms/${encodeURIComponent(room)}/make_room_admin`, { user_id: userId }); }
  joinUser(room, userId) { return this.req('POST', `/_synapse/admin/v1/join/${encodeURIComponent(room)}`, { user_id: userId }); }
  createRoom(body) { return this.req('POST', '/_matrix/client/v3/createRoom', body); }
  joinRoom(room) { return this.req('POST', `/_matrix/client/v3/rooms/${encodeURIComponent(room)}/join`, {}); }
  leaveRoom(room) { return this.req('POST', `/_matrix/client/v3/rooms/${encodeURIComponent(room)}/leave`, {}); }
  forgetRoom(room) { return this.req('POST', `/_matrix/client/v3/rooms/${encodeURIComponent(room)}/forget`, {}); }
  invite(room, userId) { return this.req('POST', `/_matrix/client/v3/rooms/${encodeURIComponent(room)}/invite`, { user_id: userId }); }
  kick(room, userId, reason) { return this.req('POST', `/_matrix/client/v3/rooms/${encodeURIComponent(room)}/kick`, { user_id: userId, reason }); }
  sendState(room, type, content, key = '') {
    return this.req('PUT', `/_matrix/client/v3/rooms/${encodeURIComponent(room)}/state/${encodeURIComponent(type)}/${encodeURIComponent(key)}`, content);
  }
  getState(room, type, key = '') {
    return this.req('GET', `/_matrix/client/v3/rooms/${encodeURIComponent(room)}/state/${encodeURIComponent(type)}/${encodeURIComponent(key)}`);
  }
  // Модули DVChat (dv_social)
  dvIssue(body) { return this.req('POST', '/_synapse/client/dv/issue', body); }
  dvFriends() { return this.req('GET', '/_synapse/client/dv/friends'); }
  dvKeysPhrase() { return this.req('POST', '/_synapse/client/dv/keys/phrase', {}); }
  dvMe() { return this.req('GET', '/_synapse/client/dv/me'); }
}

// Временный вход от имени человека (Admin API): токен живёт минуты и сразу гасится
Synapse.prototype.loginAs = function (userId) {
  return this.req('POST', `/_synapse/admin/v1/users/${encodeURIComponent(userId)}/login`, { valid_until_ms: Date.now() + 120_000 });
};
Synapse.prototype.renameDevice = function (userId, deviceId, name) {
  return this.req('PUT', `/_synapse/admin/v2/users/${encodeURIComponent(userId)}/devices/${encodeURIComponent(deviceId)}`, { display_name: name });
};
Synapse.prototype.asUser = async function (userId, fn) {
  const { access_token: token } = await this.loginAs(userId);
  const who = await new Synapse({ url: this.url, token, fetchImpl: this.f }).whoami();
  try { await this.renameDevice(userId, who.device_id, 'DVChat admin'); } catch { /* не критично */ }
  const as = new Synapse({ url: this.url, token, fetchImpl: this.f });
  try { return await fn(as); }
  finally { try { await as.req('POST', '/_matrix/client/v3/logout', {}); } catch { /* уже недействителен */ } }
};
