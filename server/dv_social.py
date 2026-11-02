# SPDX-License-Identifier: AGPL-3.0-or-later
# DVChat: ID, друзья, заявки и одноразовые коды входа (модуль Synapse).
# Адреса: /_synapse/client/dv/{me,friends,friends/add,requests,requests/answer,issue,login}
import calendar
import hashlib
import json
import logging
import secrets
import time
from collections import defaultdict, deque

try:
    from synapse.module_api import DirectServeJsonResource
except ImportError:  # запасной путь для других версий Synapse
    from synapse.http.server import DirectServeJsonResource

import dv_shared

PREFIX = "/_synapse/client/dv"
LIMIT_ALL = 60      # запросов за 60 секунд на пользователя
LIMIT_ADD = 10      # добавлений друзей за 60 секунд
LIMIT_LOGIN_IP = 10 # попыток входа за 60 секунд с одного адреса
MAX_BAD_ID = 5      # неверных ID, после которых код сгорает
DEFAULT_TTL_H = 24
MAX_TTL_H = 72
LIMIT_CHAT = 6      # открытий и созданий чата за 60 секунд

logger = logging.getLogger(__name__)


def _now_ms():
    return int(time.time() * 1000)


def _hash(code):
    return hashlib.sha256(code.encode("utf-8")).hexdigest()


def _init_tables(txn):
    txn.execute(
        "CREATE TABLE IF NOT EXISTS dv_ids ("
        "user_id TEXT PRIMARY KEY, dv_id TEXT UNIQUE NOT NULL, created_ts BIGINT NOT NULL)"
    )
    txn.execute("ALTER TABLE dv_ids ADD COLUMN IF NOT EXISTS logged_in BOOLEAN NOT NULL DEFAULT FALSE")
    txn.execute(
        "CREATE TABLE IF NOT EXISTS dv_friends ("
        "user_id TEXT NOT NULL, friend_id TEXT NOT NULL, created_ts BIGINT NOT NULL, "
        "PRIMARY KEY (user_id, friend_id))"
    )
    txn.execute(
        "CREATE TABLE IF NOT EXISTS dv_requests ("
        "from_user TEXT NOT NULL, to_user TEXT NOT NULL, created_ts BIGINT NOT NULL, "
        "PRIMARY KEY (from_user, to_user))"
    )
    txn.execute(
        "CREATE TABLE IF NOT EXISTS dv_login_codes ("
        "code_hash TEXT PRIMARY KEY, user_id TEXT NOT NULL, password TEXT, "
        "need_id BOOLEAN NOT NULL, fails INT NOT NULL DEFAULT 0, "
        "expires_ts BIGINT NOT NULL, used BOOLEAN NOT NULL DEFAULT FALSE)"
    )
    txn.execute(
        "CREATE TABLE IF NOT EXISTS dv_profile ("
        "user_id TEXT PRIMARY KEY, bday_day INT, bday_month INT, bday_year INT, "
        "notify_birthdays BOOLEAN NOT NULL DEFAULT TRUE, updated_ts BIGINT NOT NULL)"
    )
    txn.execute(
        "CREATE TABLE IF NOT EXISTS dv_keys ("
        "user_id TEXT PRIMARY KEY, passphrase TEXT NOT NULL)"
    )
    txn.execute(
        "CREATE TABLE IF NOT EXISTS dv_support ("
        "user_id TEXT PRIMARY KEY, room_id TEXT NOT NULL, admin_id TEXT NOT NULL, "
        "invited BOOLEAN NOT NULL DEFAULT FALSE, created_ts BIGINT NOT NULL)"
    )


def _get_or_create_id(txn, user_id):
    txn.execute("SELECT dv_id FROM dv_ids WHERE user_id = ?", (user_id,))
    row = txn.fetchone()
    if row:
        return row[0]
    for _ in range(30):
        dv_id = str(secrets.randbelow(9_000_000_000) + 1_000_000_000)  # 10 цифр
        txn.execute("SELECT 1 FROM dv_ids WHERE dv_id = ?", (dv_id,))
        if txn.fetchone():
            continue
        txn.execute(
            "INSERT INTO dv_ids (user_id, dv_id, created_ts) VALUES (?, ?, ?)",
            (user_id, dv_id, _now_ms()),
        )
        return dv_id
    raise RuntimeError("не удалось подобрать свободный ID")


def _list_friends(txn, user_id, is_admin):
    if is_admin:
        # Администратор видит всех действующих пользователей сервера
        txn.execute(
            "SELECT u.name, i.dv_id FROM users u LEFT JOIN dv_ids i ON i.user_id = u.name "
            "WHERE u.deactivated = 0 AND u.name <> ? ORDER BY u.name",
            (user_id,),
        )
    else:
        txn.execute(
            "SELECT f.friend_id, i.dv_id FROM dv_friends f "
            "JOIN users u ON u.name = f.friend_id AND u.deactivated = 0 "
            "LEFT JOIN dv_ids i ON i.user_id = f.friend_id "
            "WHERE f.user_id = ? ORDER BY f.created_ts",
            (user_id,),
        )
    return [{"user_id": r[0], "dv_id": r[1]} for r in txn.fetchall()]


def _profile_get(txn, viewer, ids, is_admin):
    """Профили видят сам человек, его друзья и администратор."""
    out = {}
    for uid in ids[:60]:
        if uid != viewer and not is_admin:
            txn.execute(
                "SELECT 1 FROM dv_friends WHERE user_id = ? AND friend_id = ?", (viewer, uid)
            )
            if not txn.fetchone():
                continue
        txn.execute(
            "SELECT bday_day, bday_month, bday_year, notify_birthdays "
            "FROM dv_profile WHERE user_id = ?",
            (uid,),
        )
        row = txn.fetchone()
        txn.execute("SELECT dv_id FROM dv_ids WHERE user_id = ?", (uid,))
        idrow = txn.fetchone()
        item = {"birthday": None, "dv_id": idrow[0] if idrow else None}
        if row and row[0]:
            item["birthday"] = {"day": row[0], "month": row[1], "year": row[2]}
        if uid == viewer:
            item["notify_birthdays"] = bool(row[3]) if row else True
        out[uid] = item
    return out


def _profile_set(txn, user_id, has_bday, bday, notify):
    txn.execute(
        "SELECT bday_day, bday_month, bday_year, notify_birthdays "
        "FROM dv_profile WHERE user_id = ?",
        (user_id,),
    )
    row = txn.fetchone()
    day, month, year, nt = row if row else (None, None, None, True)
    if has_bday:
        if bday is None:
            day = month = year = None
        else:
            day, month, year = bday
    if notify is not None:
        nt = notify
    txn.execute(
        "INSERT INTO dv_profile (user_id, bday_day, bday_month, bday_year, notify_birthdays, updated_ts) "
        "VALUES (?, ?, ?, ?, ?, ?) ON CONFLICT (user_id) DO UPDATE SET "
        "bday_day = EXCLUDED.bday_day, bday_month = EXCLUDED.bday_month, "
        "bday_year = EXCLUDED.bday_year, notify_birthdays = EXCLUDED.notify_birthdays, "
        "updated_ts = EXCLUDED.updated_ts",
        (user_id, day, month, year, bool(nt), _now_ms()),
    )


def _keys_phrase(txn, user_id):
    """Кодовая фраза шифрования самого пользователя (или None)."""
    txn.execute("SELECT passphrase FROM dv_keys WHERE user_id = ?", (user_id,))
    row = txn.fetchone()
    return row[0] if row and row[0] else None


def _make_friends(txn, a, b):
    ts = _now_ms()
    for x, y in ((a, b), (b, a)):
        txn.execute(
            "INSERT INTO dv_friends (user_id, friend_id, created_ts) VALUES (?, ?, ?) "
            "ON CONFLICT DO NOTHING",
            (x, y, ts),
        )
    txn.execute(
        "DELETE FROM dv_requests WHERE (from_user = ? AND to_user = ?) "
        "OR (from_user = ? AND to_user = ?)",
        (a, b, b, a),
    )


def _add_friend(txn, me, target_dv_id, via_qr):
    txn.execute("SELECT user_id FROM dv_ids WHERE dv_id = ?", (target_dv_id,))
    row = txn.fetchone()
    if not row:
        return "not_found", None
    other = row[0]
    if other == me:
        return "self", other
    txn.execute("SELECT deactivated FROM users WHERE name = ?", (other,))
    urow = txn.fetchone()
    if not urow or urow[0]:
        return "not_found", None
    txn.execute(
        "SELECT 1 FROM dv_friends WHERE user_id = ? AND friend_id = ?", (me, other)
    )
    if txn.fetchone():
        return "already", other
    if via_qr:
        _make_friends(txn, me, other)
        return "added", other
    # Ввод ID вручную: если человек уже сам отправил нам заявку, принимаем сразу
    txn.execute(
        "SELECT 1 FROM dv_requests WHERE from_user = ? AND to_user = ?", (other, me)
    )
    if txn.fetchone():
        _make_friends(txn, me, other)
        return "added", other
    # Новая это заявка или такая уже лежит: о новой сообщаем получателю всегда
    txn.execute(
        "SELECT 1 FROM dv_requests WHERE from_user = ? AND to_user = ?", (me, other)
    )
    fresh = txn.fetchone() is None
    txn.execute(
        "INSERT INTO dv_requests (from_user, to_user, created_ts) VALUES (?, ?, ?) "
        "ON CONFLICT DO NOTHING",
        (me, other, _now_ms()),
    )
    return ("requested" if fresh else "requested_again"), other


def _remove_friend(txn, a, b):
    """Разорвать дружбу с обеих сторон и убрать заявки между этими людьми."""
    txn.execute(
        "DELETE FROM dv_friends WHERE (user_id = ? AND friend_id = ?) "
        "OR (user_id = ? AND friend_id = ?)",
        (a, b, b, a),
    )
    txn.execute(
        "DELETE FROM dv_requests WHERE (from_user = ? AND to_user = ?) "
        "OR (from_user = ? AND to_user = ?)",
        (a, b, b, a),
    )


def _incoming_requests(txn, me):
    txn.execute(
        "SELECT from_user FROM dv_requests WHERE to_user = ? ORDER BY created_ts", (me,)
    )
    return [{"user_id": r[0]} for r in txn.fetchall()]


def _answer_request(txn, me, from_user, accept):
    txn.execute(
        "SELECT 1 FROM dv_requests WHERE from_user = ? AND to_user = ?", (from_user, me)
    )
    if not txn.fetchone():
        return False
    if accept:
        _make_friends(txn, me, from_user)
    else:
        txn.execute(
            "DELETE FROM dv_requests WHERE from_user = ? AND to_user = ?", (from_user, me)
        )
    return True


RELAY_KEY = "online.dvbstudio.dvchat.relay"  # метка служебных сообщений формы обратной связи
RELAY_LOCALPART = "dvsupport"  # служебный пользователь: пишет письма формы админу
NOTICE_LOCALPART = "dvnotice"  # служебный пользователь «DVChat»: пишет людям о заявках в друзья
NOTICE_NAME = "DVChat"
NOTICE_GAME_REPEAT_S = 15  # приглашения в игру одному человеку от одного не чаще, чем раз в 15 секунд
LIMIT_GAME_NOTICE = 12     # запросов на уведомление об игре за 60 секунд от одного человека
NOTICE_REPEAT_S = 300  # повторную заявку тому же человеку напоминаем не чаще, чем раз в 5 минут
SUPPORT_MARK_TYPE = "online.dvbstudio.dvchat.support"  # метка «чат с администратором»
MAX_SUBJECT = 100
MAX_MESSAGE = 2000


def _support_get(txn, user_id):
    txn.execute("SELECT room_id, admin_id, invited FROM dv_support WHERE user_id = ?", (user_id,))
    return txn.fetchone()


def _support_put(txn, user_id, room_id, admin_id):
    txn.execute(
        "INSERT INTO dv_support (user_id, room_id, admin_id, invited, created_ts) "
        "VALUES (?, ?, ?, FALSE, ?) "
        "ON CONFLICT (user_id) DO UPDATE SET room_id = EXCLUDED.room_id, "
        "admin_id = EXCLUDED.admin_id, invited = FALSE, created_ts = EXCLUDED.created_ts",
        (user_id, room_id, admin_id, _now_ms()),
    )


def _support_by_room(txn, room_id):
    txn.execute("SELECT user_id, admin_id, invited FROM dv_support WHERE room_id = ?", (room_id,))
    return txn.fetchone()


def _support_mark_invited(txn, room_id):
    txn.execute("UPDATE dv_support SET invited = TRUE WHERE room_id = ?", (room_id,))


def _first_admin(txn):
    txn.execute("SELECT name FROM users WHERE admin = 1 AND deactivated = 0 ORDER BY creation_ts LIMIT 1")
    row = txn.fetchone()
    return row[0] if row else None


def _membership(txn, room_id, user_id):
    txn.execute(
        "SELECT membership FROM local_current_membership WHERE room_id = ? AND user_id = ?",
        (room_id, user_id),
    )
    row = txn.fetchone()
    return row[0] if row else None


def _has_state(txn, room_id, etype):
    txn.execute(
        "SELECT 1 FROM current_state_events WHERE room_id = ? AND type = ? AND state_key = ''",
        (room_id, etype),
    )
    return txn.fetchone() is not None


def _room_name_now(txn, room_id):
    txn.execute("SELECT name FROM room_stats_state WHERE room_id = ?", (room_id,))
    r = txn.fetchone()
    return r[0] if r else None


def _plain_users(txn):
    txn.execute(
        "SELECT name FROM users WHERE admin = 0 AND deactivated = 0 AND is_guest = 0 "
        "AND name NOT LIKE ? AND name NOT LIKE ? ORDER BY name",
        ("@" + RELAY_LOCALPART + ":%", "@" + NOTICE_LOCALPART + ":%"),
    )
    return [r[0] for r in txn.fetchall()]


def _issue(txn, user_id, password, passphrase, ttl_h):
    """Выдаёт одноразовый код входа; кодовую фразу сохраняет в базе."""
    txn.execute("SELECT deactivated FROM users WHERE name = ?", (user_id,))
    urow = txn.fetchone()
    if not urow or urow[0]:
        return None
    dv_id = _get_or_create_id(txn, user_id)
    txn.execute("SELECT logged_in FROM dv_ids WHERE user_id = ?", (user_id,))
    need_id = bool(txn.fetchone()[0])
    txn.execute(
        "INSERT INTO dv_keys (user_id, passphrase) VALUES (?, ?) "
        "ON CONFLICT (user_id) DO UPDATE SET passphrase = EXCLUDED.passphrase",
        (user_id, passphrase),
    )
    # Просроченные коды больше не нужны: вместе с ними стираются и пароли, не дождавшиеся входа
    txn.execute("DELETE FROM dv_login_codes WHERE expires_ts < ?", (_now_ms(),))
    # Прежние неиспользованные коды человека больше не действуют
    txn.execute("DELETE FROM dv_login_codes WHERE user_id = ? AND used = FALSE", (user_id,))
    code = secrets.token_urlsafe(18)
    expires = _now_ms() + ttl_h * 3600 * 1000
    txn.execute(
        "INSERT INTO dv_login_codes (code_hash, user_id, password, need_id, expires_ts) "
        "VALUES (?, ?, ?, ?, ?)",
        (_hash(code), user_id, password, need_id, expires),
    )
    return {"code": code, "dv_id": dv_id, "need_id": need_id, "expires_ts": expires}


def _redeem(txn, code, dv_id):
    """Гасит код и отдаёт данные для входа. Возвращает (статус, данные)."""
    # Просроченные коды (и пароли в них) удаляем при каждой попытке входа
    txn.execute("DELETE FROM dv_login_codes WHERE expires_ts < ?", (_now_ms(),))
    h = _hash(code)
    txn.execute(
        "SELECT user_id, password, need_id, fails, expires_ts, used "
        "FROM dv_login_codes WHERE code_hash = ?",
        (h,),
    )
    row = txn.fetchone()
    if not row:
        return "bad_code", None
    user_id, password, need_id, fails, expires, used = row
    if used or expires < _now_ms() or not password:
        return "bad_code", None
    if need_id:
        if not dv_id:
            return "need_id", None  # код не тратим: приложение спросит ID
        txn.execute("SELECT dv_id FROM dv_ids WHERE user_id = ?", (user_id,))
        real = txn.fetchone()
        if not real or real[0] != dv_id:
            fails += 1
            if fails >= MAX_BAD_ID:
                txn.execute(
                    "UPDATE dv_login_codes SET fails = ?, used = TRUE, password = NULL "
                    "WHERE code_hash = ?",
                    (fails, h),
                )
            else:
                txn.execute(
                    "UPDATE dv_login_codes SET fails = ? WHERE code_hash = ?", (fails, h)
                )
            return "bad_id", None
    txn.execute("SELECT passphrase FROM dv_keys WHERE user_id = ?", (user_id,))
    krow = txn.fetchone()
    txn.execute(
        "UPDATE dv_login_codes SET used = TRUE, password = NULL WHERE code_hash = ?", (h,)
    )
    txn.execute("UPDATE dv_ids SET logged_in = TRUE WHERE user_id = ?", (user_id,))
    localpart = user_id[1:].split(":")[0]
    return "ok", {
        "user_id": user_id,
        "u": localpart,
        "p": password,
        "k": krow[0] if krow else None,
    }


def _is_friend(txn, a, b):
    txn.execute("SELECT 1 FROM dv_friends WHERE user_id = ? AND friend_id = ?", (a, b))
    return txn.fetchone() is not None


def _find_dm(txn, a, b):
    """Живой личный чат: оба в комнате и больше никого, и комната записана как личная.

    Раньше проверялось только «в комнате двое». Из-за этого группа из двух человек
    принималась за личный чат: приложение получало её вместо нового чата и ждало его
    бесконечно. Теперь комната обязана числиться личной (m.direct) хотя бы у одного
    из двоих: так записывает и приложение, и _create_dm.
    """
    txn.execute(
        "SELECT x.room_id FROM local_current_membership x "
        "JOIN local_current_membership y ON x.room_id = y.room_id "
        "WHERE x.user_id = ? AND y.user_id = ? "
        "AND x.membership = 'join' AND y.membership = 'join' "
        "AND (SELECT count(*) FROM local_current_membership m "
        "     WHERE m.room_id = x.room_id AND m.membership = 'join') = 2 "
        "AND EXISTS (SELECT 1 FROM account_data d "
        "     WHERE d.user_id IN (x.user_id, y.user_id) "
        "     AND d.account_data_type = 'm.direct' "
        "     AND position(x.room_id in d.content) > 0) "
        "LIMIT 1",
        (a, b),
    )
    row = txn.fetchone()
    return row[0] if row else None


class _Root(DirectServeJsonResource):
    isLeaf = True  # все подпути обрабатываем сами

    def __init__(self, mod):
        super().__init__()
        self._m = mod

    async def _async_render_GET(self, request):
        return await self._m.handle(request, "GET")

    async def _async_render_POST(self, request):
        return await self._m.handle(request, "POST")


class DvSocial:
    def __init__(self, config, api):
        self._api = api
        self._ready = False
        self._hits = defaultdict(deque)
        self._last_notice = {}  # (от кого, кому) -> время последнего сообщения о заявке
        api.register_web_resource(PREFIX, _Root(self))
        self._log = logging.getLogger(__name__)
        api.register_third_party_rules_callbacks(on_new_event=self._on_new_event)

    @staticmethod
    def parse_config(config):
        return config

    async def _ensure(self):
        if not self._ready:
            await self._api.run_db_interaction("dv_init_tables", _init_tables)
            self._ready = True

    def _limited(self, key, limit):
        now = time.time()
        # Пустые и давние ключи убираем, чтобы память не росла от множества разных адресов
        if len(self._hits) > 2000:
            for k in [k for k, v in self._hits.items() if not v or now - v[-1] > 60]:
                del self._hits[k]
        q = self._hits[key]
        while q and now - q[0] > 60:
            q.popleft()
        if len(q) >= limit:
            return True
        q.append(now)
        return False

    @staticmethod
    def _body(request):
        try:
            data = json.loads(request.content.read().decode("utf-8"))
            return data if isinstance(data, dict) else {}
        except Exception:
            return {}

    @staticmethod
    def _ip(request):
        try:
            return request.getClientAddress().host
        except Exception:
            return "?"

    async def _add_direct(self, user_id, other, room_id):
        """Записывает комнату в m.direct, чтобы приложение видело её как личный чат."""
        am = self._api.account_data_manager
        cur = await am.get_global(user_id, "m.direct") or {}
        data = {k: list(v) for k, v in dict(cur).items()}
        rooms = data.setdefault(other, [])
        if room_id not in rooms:
            rooms.append(room_id)
        await am.put_global(user_id, "m.direct", data)

    async def _create_dm(self, user_id, other):
        config = {
            "visibility": "private",
            "preset": "trusted_private_chat",
            "is_direct": True,
            "initial_state": [
                {
                    "type": "m.room.encryption",
                    "state_key": "",
                    "content": {"algorithm": "m.megolm.v1.aes-sha2"},
                }
            ],
            "dv_nonce": dv_shared.new_nonce(),
        }
        room_id, _ = await self._api.create_room(user_id, config, ratelimit=False)
        dv_shared.allow_invite(user_id, other, room_id)
        await self._api.update_room_membership(
            user_id, other, room_id, "invite", content={"is_direct": True}
        )
        await self._api.update_room_membership(other, other, room_id, "join")
        await self._add_direct(user_id, other, room_id)
        await self._add_direct(other, user_id, room_id)
        return room_id

    async def _who(self, user_id):
        """Имя для показа и ID человека."""
        dv_id = await self._api.run_db_interaction("dv_me", _get_or_create_id, user_id)
        local = user_id[1:].split(":")[0]
        try:
            prof = await self._api.get_profile_for_user(local)
            name = prof.display_name or local
        except Exception:
            name = local
        return name, dv_id

    async def _support_room(self, user_id, admin_id=None):
        """Комната админа с человеком. Создаётся без шифрования и без человека:
        он попадёт в неё после первого сообщения админа."""
        run = self._api.run_db_interaction
        if admin_id is None:
            admin_id = await run("dv_firstadmin", _first_admin)
        if not admin_id:
            return None
        row = await run("dv_sup_get", _support_get, user_id)
        if row and await run("dv_sup_mem", _membership, row[0], row[1]) == "join":
            old_room, _adm, invited = row
            if invited and await run("dv_sup_pmem", _membership, old_room, user_id) not in ("join", "invite"):
                # Человек удалил чат у себя: старую комнату помечаем, для новых писем заводим новую
                try:
                    nm, did = await self._who(user_id)
                    await self._api.create_and_send_event_into_room(
                        {
                            "type": "m.room.name",
                            "state_key": "",
                            "room_id": old_room,
                            "sender": row[1],
                            "content": {"name": "%s @%s (%s), старый чат" % (nm, user_id.split(":")[0].lstrip("@"), did)},
                        }
                    )
                except Exception:
                    self._log.exception("dv_social: не удалось пометить старую комнату")
            else:
                await self._mark_support(old_room, row[1])
                return old_room
        name, dv_id = await self._who(user_id)
        login = user_id.split(":")[0].lstrip("@")
        config = {
            "visibility": "private",
            "preset": "private_chat",
            "name": "%s @%s (%s)" % (name, login, dv_id),
            "initial_state": [
                {
                    "type": "m.room.history_visibility",
                    "state_key": "",
                    "content": {"history_visibility": "shared"},
                },
                {"type": SUPPORT_MARK_TYPE, "state_key": "", "content": {"v": 1}},
            ],
        }
        room_id, _ = await self._api.create_room(admin_id, config, ratelimit=False)
        await run("dv_sup_put", _support_put, user_id, room_id, admin_id)
        return room_id

    async def _fix_room_name(self, person):
        """Название комнаты, куда человек ещё не вошёл: «Имя @логин (ID)».
        После его входа название очищается самим сервером (шаг первого ответа админа)."""
        run = self._api.run_db_interaction
        row = await run("dv_sup_get", _support_get, person)
        if not row or row[2]:
            return False
        name, dv_id = await self._who(person)
        login = person.split(":")[0].lstrip("@")
        want = "%s @%s (%s)" % (name, login, dv_id)
        try:
            if await run("dv_rname", _room_name_now, row[0]) == want:
                return False
        except Exception:
            pass
        await self._api.create_and_send_event_into_room(
            {
                "type": "m.room.name",
                "state_key": "",
                "room_id": row[0],
                "sender": row[1],
                "content": {"name": want},
            }
        )
        return True

    async def _mark_support(self, room_id, admin_id):
        """Метка «чат с администратором»: по ней приложение скрывает чат вместо удаления."""
        try:
            if await self._api.run_db_interaction("dv_hasmark", _has_state, room_id, SUPPORT_MARK_TYPE):
                return
            await self._api.create_and_send_event_into_room(
                {
                    "type": SUPPORT_MARK_TYPE,
                    "state_key": "",
                    "room_id": room_id,
                    "sender": admin_id,
                    "content": {"v": 1},
                }
            )
        except Exception:
            self._log.exception("dv_social: не удалось поставить метку на комнату")

    async def _ensure_relay(self, room_id, admin_id):
        """Служебный пользователь создаётся при первом письме и входит в комнату админа."""
        run = self._api.run_db_interaction
        relay = "@%s:%s" % (RELAY_LOCALPART, self._api.server_name)
        if not await self._api.check_user_exists(relay):
            await self._api.register_user(RELAY_LOCALPART, displayname="Обратная связь")
        if await run("dv_relay_mem", _membership, room_id, relay) != "join":
            await self._api.update_room_membership(admin_id, relay, room_id, "invite")
            await self._api.update_room_membership(relay, relay, room_id, "join")
        return relay

    async def _send_text(self, room_id, sender, body, relay=False):
        content = {"msgtype": "m.text", "body": body}
        if relay:
            content[RELAY_KEY] = True
        await self._api.create_and_send_event_into_room(
            {"type": "m.room.message", "room_id": room_id, "sender": sender, "content": content}
        )

    async def _room_profile(self, person):
        """Имя и аватар человека для события участия в комнате поддержки:
        имя с ID, аватар как в профиле. Действует только в этой комнате."""
        name, dv_id = await self._who(person)
        localpart = person.split(":")[0].lstrip("@")
        content = {"displayname": "%s @%s (%s)" % (name, localpart, dv_id)}
        try:
            prof = await self._api.get_profile_for_user(localpart)
            avatar = getattr(prof, "avatar_url", None)
            if avatar:
                content["avatar_url"] = str(avatar)
        except Exception:
            self._log.exception("dv_social: профиль для комнаты поддержки не прочитался")
        return content

    async def _fix_person_name(self, person):
        """Подписать человека «Имя (ID)» в его комнате поддержки (если он уже в ней)."""
        run = self._api.run_db_interaction
        row = await run("dv_sup_get", _support_get, person)
        if not row or not row[2]:
            return False
        room_id = row[0]
        if await run("dv_sup_pmem", _membership, room_id, person) != "join":
            return False
        content = await self._room_profile(person)
        await self._api.update_room_membership(person, person, room_id, "join", content=content)
        return True

    async def _notice_room(self, person):
        """Личная комната служебного пользователя «DVChat» с человеком (создаётся при первой
        заявке). Без шифрования: служебному пользователю нечем шифровать, а обычный пуш
        Synapse срабатывает на любое сообщение в личной комнате."""
        run = self._api.run_db_interaction
        bot = "@%s:%s" % (NOTICE_LOCALPART, self._api.server_name)
        if not await self._api.check_user_exists(bot):
            await self._api.register_user(NOTICE_LOCALPART, displayname=NOTICE_NAME)
        room_id = await run("dv_notice_find", _find_dm, bot, person)
        if room_id:
            return bot, room_id
        config = {
            "visibility": "private",
            "preset": "trusted_private_chat",
            "is_direct": True,
            "dv_nonce": dv_shared.new_nonce(),
        }
        room_id, _ = await self._api.create_room(bot, config, ratelimit=False)
        dv_shared.allow_invite(bot, person, room_id)
        await self._api.update_room_membership(
            bot, person, room_id, "invite", content={"is_direct": True}
        )
        await self._api.update_room_membership(person, person, room_id, "join")
        await self._add_direct(bot, person, room_id)
        await self._add_direct(person, bot, room_id)
        return bot, room_id

    async def _notify_request(self, sender, person, fresh):
        """Сообщить получателю о заявке в друзья: сообщение в его комнате с «DVChat» даёт
        обычное уведомление на телефон. Любой сбой только пишется в журнал, заявку не ломает."""
        try:
            key = (sender, person)
            now = time.time()
            if not fresh and now - self._last_notice.get(key, 0) < NOTICE_REPEAT_S:
                return
            self._last_notice[key] = now
            name, _ = await self._who(sender)
            bot, room_id = await self._notice_room(person)
            await self._send_text(
                room_id,
                bot,
                "👋 %s хочет добавить вас в друзья. Откройте вкладку «Друзья»: "
                "там заявку можно принять или отклонить." % name,
            )
        except Exception:
            self._log.exception("dv_social: не удалось сообщить о заявке в друзья")

    async def _notify_game(self, sender, person, title):
        """Сообщить, что друг зовёт в игру: сообщение от «DVChat» даёт обычное уведомление.
        Приглашение само идёт скрытым событием, а такие уведомлений не вызывают."""
        try:
            key = (sender, person, "game")
            now = time.time()
            if now - self._last_notice.get(key, 0) < NOTICE_GAME_REPEAT_S:
                return
            self._last_notice[key] = now
            name, _ = await self._who(sender)
            bot, room_id = await self._notice_room(person)
            what = (" в «%s»" % title) if title else ""
            await self._send_text(
                room_id,
                bot,
                "🎮 %s зовёт вас сыграть%s. Откройте вкладку «Игры»: приглашение ждёт там."
                % (name, what),
            )
        except Exception:
            self._log.exception("dv_social: не удалось сообщить о приглашении в игру")

    async def _on_member(self, event):
        """Человек сменил общее имя, и Synapse затёр подпись с ID: возвращаем её."""
        if event.state_key != event.sender or event.content.get("membership") != "join":
            return
        run = self._api.run_db_interaction
        row = await run("dv_sup_room", _support_by_room, event.room_id)
        if not row or not row[2] or row[0] != event.sender:
            return
        want = await self._room_profile(event.sender)
        if event.content.get("displayname") == want["displayname"]:
            return
        await self._api.update_room_membership(
            event.sender, event.sender, event.room_id, "join", content=want
        )

    async def _on_new_event(self, event, *_):
        """Первое сообщение админа в комнате человека: включаем шифрование,
        убираем служебное название и подключаем человека."""
        try:
            if event.type == "m.room.member":
                await self._on_member(event)
                return
            if event.type not in ("m.room.message", "m.room.encrypted"):
                return
            if event.content.get(RELAY_KEY):
                return
            run = self._api.run_db_interaction
            row = await run("dv_sup_room", _support_by_room, event.room_id)
            if not row:
                return
            person, admin_id, invited = row
            if invited or event.sender != admin_id:
                return
            await run("dv_sup_inv", _support_mark_invited, event.room_id)
            room_id = event.room_id
            relay = "@%s:%s" % (RELAY_LOCALPART, self._api.server_name)
            if await run("dv_relay_mem", _membership, room_id, relay) == "join":
                await self._api.update_room_membership(relay, relay, room_id, "leave")
            await self._api.create_and_send_event_into_room(
                {
                    "type": "m.room.encryption",
                    "state_key": "",
                    "room_id": room_id,
                    "sender": admin_id,
                    "content": {"algorithm": "m.megolm.v1.aes-sha2"},
                }
            )
            await self._api.create_and_send_event_into_room(
                {
                    "type": "m.room.name",
                    "state_key": "",
                    "room_id": room_id,
                    "sender": admin_id,
                    "content": {"name": ""},
                }
            )
            prof = await self._room_profile(person)
            invite_content = {"is_direct": True}
            invite_content.update(prof)
            await self._api.update_room_membership(
                admin_id, person, room_id, "invite", content=invite_content
            )
            await self._api.update_room_membership(person, person, room_id, "join", content=prof)
            await self._add_direct(admin_id, person, room_id)
            await self._add_direct(person, admin_id, room_id)
        except Exception:
            self._log.exception("dv_social: не удалось подключить человека к комнате с админом")

    async def handle(self, request, method):
        sub = request.path.decode("utf-8")[len(PREFIX):].strip("/")

        # Вход по коду: токена ещё нет, защита — строгий лимит по адресу
        if sub == "login" and method == "POST":
            if self._limited(("ip", self._ip(request)), LIMIT_LOGIN_IP):
                return 429, {"errcode": "M_LIMIT_EXCEEDED", "error": "Слишком часто"}
            await self._ensure()
            body = self._body(request)
            code = str(body.get("code", "")).strip()
            dv_id = str(body.get("dv_id", "")).strip()
            if not code or len(code) > 200:
                return 404, {"errcode": "DV_BAD_CODE", "error": "Ссылка недействительна"}
            status, data = await self._api.run_db_interaction(
                "dv_redeem", _redeem, code, dv_id
            )
            if status == "ok":
                return 200, data
            if status == "need_id":
                return 403, {"errcode": "DV_NEED_ID", "error": "Введите ваш ID"}
            if status == "bad_id":
                return 403, {"errcode": "DV_BAD_ID", "error": "Неверный ID"}
            return 404, {
                "errcode": "DV_BAD_CODE",
                "error": "Ссылка недействительна или уже использована",
            }

        requester = await self._api.get_user_by_req(request)
        user_id = requester.user.to_string()
        if self._limited((user_id, "all"), LIMIT_ALL):
            return 429, {"errcode": "M_LIMIT_EXCEEDED", "error": "Слишком часто"}
        await self._ensure()
        run = self._api.run_db_interaction

        if sub == "me" and method == "GET":
            dv_id = await run("dv_me", _get_or_create_id, user_id)
            return 200, {"user_id": user_id, "dv_id": dv_id}

        if sub == "friends" and method == "GET":
            is_admin = await self._api.is_user_admin(user_id)
            friends = await run("dv_friends", _list_friends, user_id, is_admin)
            return 200, {"friends": friends, "all_users": bool(is_admin)}

        if sub == "friends/add" and method == "POST":
            if self._limited((user_id, "add"), LIMIT_ADD):
                return 429, {"errcode": "M_LIMIT_EXCEEDED", "error": "Слишком часто"}
            body = self._body(request)
            target = str(body.get("dv_id", "")).strip()
            if not (target.isdigit() and len(target) == 10):
                return 400, {"errcode": "DV_BAD_ID", "error": "Неверный формат ID"}
            await run("dv_me", _get_or_create_id, user_id)
            status, other = await run(
                "dv_add", _add_friend, user_id, target, bool(body.get("via_qr"))
            )
            if status == "not_found":
                return 404, {"errcode": "DV_NOT_FOUND", "error": "Такого ID нет"}
            if status == "self":
                return 400, {"errcode": "DV_SELF", "error": "Это ваш собственный ID"}
            if status in ("requested", "requested_again"):
                await self._notify_request(user_id, other, fresh=status == "requested")
                status = "requested"
            return 200, {"status": status, "user_id": other}

        # Профили (день рождения): читать можно у себя и у друзей
        if sub == "profile/get" and method == "POST":
            body = self._body(request)
            ids = body.get("user_ids")
            if not isinstance(ids, list):
                ids = [user_id]
            ids = [str(x) for x in ids if str(x).startswith("@")]
            is_admin = await self._api.is_user_admin(user_id)
            res = await run("dv_profile_get", _profile_get, user_id, ids, is_admin)
            return 200, {"profiles": res}

        # Свой профиль: день рождения (или null, чтобы убрать) и уведомления о днях рождения друзей
        if sub == "profile/set" and method == "POST":
            body = self._body(request)
            has_bday = "birthday" in body
            bday = None
            if has_bday and body["birthday"] is not None:
                b = body["birthday"]
                try:
                    d = int(b["day"])
                    m = int(b["month"])
                    y = int(b["year"]) if b.get("year") is not None else None
                except Exception:
                    return 400, {"errcode": "M_BAD_JSON", "error": "Неверная дата"}
                if not (1 <= m <= 12 and 1 <= d <= calendar.monthrange(2000, m)[1]):
                    return 400, {"errcode": "M_BAD_JSON", "error": "Неверная дата"}
                if y is not None and not (1900 <= y <= 2100):
                    return 400, {"errcode": "M_BAD_JSON", "error": "Неверный год"}
                bday = (d, m, y)
            notify = body.get("notify_birthdays")
            notify = bool(notify) if notify is not None else None
            await run("dv_profile_set", _profile_set, user_id, has_bday, bday, notify)
            return 200, {}

        # Кодовая фраза шифрования: только хозяину токена
        if sub == "keys/phrase" and method == "POST":
            phrase = await run("dv_keys_phrase", _keys_phrase, user_id)
            if not phrase:
                return 404, {"errcode": "DV_NOT_FOUND", "error": "Фраза не найдена"}
            return 200, {"phrase": phrase}

        # Выйти на всех устройствах, кроме текущего (пароль не нужен: человек уже вошёл)
        if sub == "devices/logout_others" and method == "POST":
            current = getattr(requester, "device_id", None)
            if not current:
                return 400, {"errcode": "M_BAD_JSON", "error": "Не удалось определить это устройство"}
            handler = self._api._hs.get_device_handler()
            devices = await handler.get_devices_by_user(user_id)
            try:
                wanted = self._body(request).get("device_ids")
            except Exception:
                wanted = None
            others = [
                d["device_id"]
                for d in devices
                if d["device_id"] != current
                and (not isinstance(wanted, list) or d["device_id"] in wanted)
            ]
            if others:
                await handler.delete_devices(user_id, others)
            self._log.info("DVChat: %s вышел на других устройствах: %d", user_id, len(others))
            return 200, {"logged_out": len(others)}

        # Удалить из друзей (с обеих сторон). Личные чаты закрывает приложение.
        if sub == "friends/remove" and method == "POST":
            body = self._body(request)
            other = str(body.get("user_id", "")).strip()
            if not other.startswith("@") or other == user_id:
                return 400, {"errcode": "M_BAD_JSON", "error": "Неверный пользователь"}
            await run("dv_unfriend", _remove_friend, user_id, other)
            return 200, {}

        if sub == "requests" and method == "GET":
            reqs = await run("dv_requests", _incoming_requests, user_id)
            return 200, {"requests": reqs}

        if sub == "requests/answer" and method == "POST":
            body = self._body(request)
            from_user = str(body.get("user_id", ""))
            ok = await run(
                "dv_answer", _answer_request, user_id, from_user, bool(body.get("accept"))
            )
            if not ok:
                return 404, {"errcode": "DV_NOT_FOUND", "error": "Заявки нет"}
            return 200, {}

        # Приглашение в игру: приложение просит сообщить другу уведомлением
        if sub == "games/invite" and method == "POST":
            if self._limited((user_id, "game_notice"), LIMIT_GAME_NOTICE):
                return 429, {"errcode": "M_LIMIT_EXCEEDED", "error": "Слишком часто"}
            body = self._body(request)
            other = str(body.get("user_id", "")).strip()
            title = str(body.get("title", "")).strip()[:40]
            if not other.startswith("@") or other == user_id:
                return 400, {"errcode": "M_BAD_JSON", "error": "Неверный пользователь"}
            if not await self._api.is_user_admin(user_id) and not await run(
                "dv_isfriend", _is_friend, user_id, other
            ):
                return 403, {"errcode": "M_FORBIDDEN", "error": "Только другу"}
            await self._notify_game(user_id, other, title)
            return 200, {}

        # Выдача одноразового кода: только администратор (вызывает dvuser.sh)
        if sub == "issue" and method == "POST":
            if not await self._api.is_user_admin(user_id):
                return 403, {"errcode": "M_FORBIDDEN", "error": "Только администратор"}
            body = self._body(request)
            target = str(body.get("user_id", ""))
            password = str(body.get("password", ""))
            passphrase = str(body.get("passphrase", ""))
            try:
                ttl = int(body.get("ttl_hours", DEFAULT_TTL_H))
            except Exception:
                ttl = DEFAULT_TTL_H
            ttl = max(1, min(ttl, MAX_TTL_H))
            if not target.startswith("@") or not password or not passphrase:
                return 400, {"errcode": "M_BAD_JSON", "error": "Нужны user_id, password, passphrase"}
            res = await run("dv_issue", _issue, target, password, passphrase, ttl)
            if res is None:
                return 404, {"errcode": "DV_NOT_FOUND", "error": "Нет такого пользователя"}
            # Комната админа с этим человеком (сам он попадёт в неё после первого ответа админа)
            try:
                if not await self._api.is_user_admin(target):
                    res["support_room"] = await self._support_room(target, user_id)
            except Exception:
                self._log.exception("dv_social: комната поддержки не создалась")
            return 200, res

        # Открыть (или создать) личный чат с другом
        if sub == "chat" and method == "POST":
            if self._limited((user_id, "chat"), LIMIT_CHAT):
                return 429, {"errcode": "M_LIMIT_EXCEEDED", "error": "Слишком часто"}
            body = self._body(request)
            other = str(body.get("user_id", "")).strip()
            if not other.startswith("@") or other == user_id:
                return 400, {"errcode": "M_BAD_JSON", "error": "Неверный пользователь"}
            if not await self._api.check_user_exists(other):
                return 404, {"errcode": "DV_NOT_FOUND", "error": "Нет такого пользователя"}
            is_admin = await self._api.is_user_admin(user_id)
            if not is_admin and not await run("dv_isfriend", _is_friend, user_id, other):
                return 403, {"errcode": "DV_NOT_FRIEND", "error": "Этот человек не в списке друзей"}
            existing = await run("dv_finddm", _find_dm, user_id, other)
            if existing:
                return 200, {"room_id": existing, "existing": True}
            room_id = await self._create_dm(user_id, other)
            return 200, {"room_id": room_id, "existing": False}

        # Обратная связь: тема и сообщение попадают в комнату админа с этим человеком
        if sub == "feedback" and method == "POST":
            if await self._api.is_user_admin(user_id):
                return 400, {"errcode": "M_BAD_JSON", "error": "Администратору форма не нужна"}
            if self._limited((user_id, "fb"), 1):
                return 429, {"errcode": "M_LIMIT_EXCEEDED", "error": "Не чаще одного сообщения в минуту"}
            body = self._body(request)
            subject = str(body.get("subject", "")).strip()[:MAX_SUBJECT]
            text = str(body.get("message", "")).strip()
            if not text:
                return 400, {"errcode": "M_BAD_JSON", "error": "Напишите сообщение"}
            if len(text) > MAX_MESSAGE:
                return 400, {"errcode": "M_BAD_JSON", "error": "Слишком длинное сообщение"}
            room_id = await self._support_room(user_id)
            if not room_id:
                return 503, {"errcode": "M_UNKNOWN", "error": "Администратор недоступен"}
            row = await run("dv_sup_get", _support_get, user_id)
            person_in = await run("dv_sup_pmem", _membership, room_id, user_id) == "join"
            invited = bool(row and row[2]) and person_in
            if invited:
                # человек уже в комнате: пишем от его имени
                out = ("Тема: %s\n\n%s" % (subject, text)) if subject else text
                await self._send_text(room_id, user_id, out)
            else:
                name, dv_id = await self._who(user_id)
                head = "✉ %s (%s)" % (name, dv_id)
                if subject:
                    head += "\nТема: " + subject
                relay = await self._ensure_relay(room_id, row[1])
                await self._send_text(room_id, relay, head + "\n\n" + text, relay=True)
            return 200, {}

        # Создать комнаты админа со всеми нынешними людьми (разово)
        if sub == "support/backfill" and method == "POST":
            if not await self._api.is_user_admin(user_id):
                return 403, {"errcode": "M_FORBIDDEN", "error": "Только администратор"}
            made = 0
            named = 0
            renamed = 0
            for u in await run("dv_plain", _plain_users):
                try:
                    if await self._support_room(u, user_id):
                        made += 1
                    if await self._fix_person_name(u):
                        named += 1
                    if await self._fix_room_name(u):
                        renamed += 1
                except Exception:
                    self._log.exception("dv_social: комната не создалась для %s", u)
            return 200, {"count": made, "named": named, "renamed": renamed}

        return 404, {"errcode": "M_NOT_FOUND", "error": "Нет такого адреса"}
