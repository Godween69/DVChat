// Полная очистка переписки комнаты на сервере: комната, участники и группы остаются.
// Synapse не стирает самое последнее событие, поэтому после первой очистки автор само сообщение удаляет (от его имени),
// затем очистка повторяется. Файлы из зашифрованных чатов этим не удаляются (Synapse их в комнате не видит).
const enc = encodeURIComponent;

async function purge(syn, roomId) {
  const r = await syn.req('POST', `/_synapse/admin/v1/purge_history/${enc(roomId)}`, { purge_up_to_ts: Date.now() + 2000, delete_local_events: true });
  for (let i = 0; i < 100; i++) {
    const s = await syn.req('GET', `/_synapse/admin/v1/purge_history_status/${enc(r.purge_id)}`);
    if (s.status === 'complete') return;
    if (s.status === 'failed') throw Object.assign(new Error('Сервер не смог очистить историю комнаты'), { status: 502 });
    await new Promise((x) => setTimeout(x, 300));
  }
  throw Object.assign(new Error('Очистка идёт слишком долго, проверьте комнату позже'), { status: 504 });
}

export async function clearRoom(syn, roomId) {
  await purge(syn, roomId);
  const members = (await syn.roomMembers(roomId)).members || [];
  let viewer = null;
  for (const m of members) {
    const u = await syn.user(m).catch(() => null);
    if (u && !u.deactivated) { viewer = m; break; }
  }
  if (!viewer) return { redacted: 0, remaining: 0 };
  const left = await syn.asUser(viewer, async (as) =>
    ((await as.req('GET', `/_matrix/client/v3/rooms/${enc(roomId)}/messages?dir=b&limit=50`)).chunk || []).filter((e) => e.state_key === undefined && e.type !== 'm.room.redaction'));
  const bySender = new Map();
  for (const e of left) bySender.set(e.sender, [...(bySender.get(e.sender) || []), e.event_id]);
  let redacted = 0, skipped = 0;
  for (const [sender, ids] of bySender) {
    const u = await syn.user(sender).catch(() => null);
    if (!u || u.deactivated) { skipped += ids.length; continue; }
    await syn.asUser(sender, async (as) => {
      for (const id of ids) {
        await as.req('PUT', `/_matrix/client/v3/rooms/${enc(roomId)}/redact/${enc(id)}/${Math.random().toString(36).slice(2)}`, { reason: 'Очистка переписки администратором' });
        redacted++;
      }
    });
  }
  if (redacted) await purge(syn, roomId);
  return { redacted, remaining: skipped };
}
