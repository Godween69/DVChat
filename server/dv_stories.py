# SPDX-License-Identifier: AGPL-3.0-or-later
# DVChat: сторис (модуль Synapse). Отдельно от dv_social: сбой здесь не трогает друзей и входы.
# Адреса: /_synapse/client/dvs/{feed,publish,view,viewers,react,delete}
# Сторис живёт 24 часа, потом модуль сам удаляет запись и файл с сервера.
# Кто смотрел и реакции видит только автор. Уведомления друзьям шлёт приложение автора.
import json
import logging
import re
import secrets
import time
from collections import defaultdict, deque

try:
    from synapse.module_api import DirectServeJsonResource
except ImportError:  # запасной путь для других версий Synapse
    from synapse.http.server import DirectServeJsonResource

PREFIX = "/_synapse/client/dvs"
TTL_MS = 24 * 3600 * 1000      # сторис живёт сутки
GRACE_MS = 5 * 60 * 1000       # после срока файл удаляется с задержкой в 5 минут
MAX_VIDEO_MS = 10500           # видео до 10 секунд (с небольшим запасом)
MAX_ACTIVE = 30                # живых сторис у одного автора
MAX_AUDIENCE = 200
LIMIT_ALL = 120                # запросов за 60 секунд на пользователя
LIMIT_PUBLISH = 6              # публикаций за 60 секунд
CLEAN_EVERY_MS = 10 * 60 * 1000
EMOJI_MAX = 8
MEDIA_RE = re.compile(r"^mxc://([^/]+)/([A-Za-z0-9_-]{8,64})$")

logger = logging.getLogger(__name__)


def _now_ms():
    return int(time.time() * 1000)


# ---------- работа с базой (функции для run_db_interaction) ----------

def _init_tables(txn):
    txn.execute(
        "CREATE TABLE IF NOT EXISTS dv_stories ("
        "id TEXT PRIMARY KEY, author TEXT NOT NULL, mxc TEXT NOT NULL, kind TEXT NOT NULL, "
        "width INT, height INT, duration_ms INT, caption TEXT NOT NULL DEFAULT '', "
        "created_ts BIGINT NOT NULL, expires_ts BIGINT NOT NULL)"
    )
    txn.execute(
        "CREATE TABLE IF NOT EXISTS dv_story_audience ("
        "story_id TEXT NOT NULL, user_id TEXT NOT NULL, PRIMARY KEY (story_id, user_id))"
    )
    txn.execute(
        "CREATE TABLE IF NOT EXISTS dv_story_views ("
        "story_id TEXT NOT NULL, viewer TEXT NOT NULL, ts BIGINT NOT NULL, "
        "PRIMARY KEY (story_id, viewer))"
    )
    txn.execute(
        "CREATE TABLE IF NOT EXISTS dv_story_reactions ("
        "story_id TEXT NOT NULL, user_id TEXT NOT NULL, emoji TEXT NOT NULL, ts BIGINT NOT NULL, "
        "PRIMARY KEY (story_id, user_id))"
    )
    txn.execute("CREATE INDEX IF NOT EXISTS dv_stories_author_idx ON dv_stories (author, expires_ts)")
    txn.execute("CREATE INDEX IF NOT EXISTS dv_story_audience_user_idx ON dv_story_audience (user_id)")


def _friend_ids(txn, user_id, is_admin):
    """Кому автор может показать сторис: его друзья (у админа - все действующие пользователи)."""
    if is_admin:
        txn.execute("SELECT name FROM users WHERE deactivated = 0 AND name <> ?", (user_id,))
    else:
        txn.execute(
            "SELECT f.friend_id FROM dv_friends f "
            "JOIN users u ON u.name = f.friend_id AND u.deactivated = 0 "
            "WHERE f.user_id = ?",
            (user_id,),
        )
    return [r[0] for r in txn.fetchall()]


def _owns_media(txn, user_id, media_id):
    txn.execute(
        "SELECT 1 FROM local_media_repository WHERE media_id = ? AND user_id = ?",
        (media_id, user_id),
    )
    return txn.fetchone() is not None


def _active_count(txn, author, now):
    txn.execute("SELECT count(*) FROM dv_stories WHERE author = ? AND expires_ts > ?", (author, now))
    return txn.fetchone()[0]


def _publish(txn, author, now, mxc, kind, width, height, duration_ms, caption, audience):
    sid = secrets.token_urlsafe(9)
    txn.execute(
        "INSERT INTO dv_stories (id, author, mxc, kind, width, height, duration_ms, caption, "
        "created_ts, expires_ts) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
        (sid, author, mxc, kind, width, height, duration_ms, caption, now, now + TTL_MS),
    )
    for uid in audience:
        txn.execute(
            "INSERT INTO dv_story_audience (story_id, user_id) VALUES (?, ?) ON CONFLICT DO NOTHING",
            (sid, uid),
        )
    return sid


def _story_dict(r):
    return {
        "id": r[0], "kind": r[1], "mxc": r[2], "width": r[3], "height": r[4],
        "duration_ms": r[5], "caption": r[6], "created_ts": r[7], "expires_ts": r[8],
    }


def _feed(txn, me, now):
    """Мои живые сторис (со счётчиками) и сторис друзей, адресованные мне."""
    txn.execute(
        "SELECT s.id, s.kind, s.mxc, s.width, s.height, s.duration_ms, s.caption, s.created_ts, "
        "s.expires_ts, (SELECT count(*) FROM dv_story_views v WHERE v.story_id = s.id), "
        "(SELECT count(*) FROM dv_story_reactions x WHERE x.story_id = s.id) "
        "FROM dv_stories s WHERE s.author = ? AND s.expires_ts > ? ORDER BY s.created_ts",
        (me, now),
    )
    mine = []
    for r in txn.fetchall():
        d = _story_dict(r)
        d["views"] = r[9]
        d["reactions"] = r[10]
        mine.append(d)
    txn.execute(
        "SELECT s.author, s.id, s.kind, s.mxc, s.width, s.height, s.duration_ms, s.caption, "
        "s.created_ts, s.expires_ts, (v.viewer IS NOT NULL), x.emoji "
        "FROM dv_stories s "
        "JOIN dv_story_audience a ON a.story_id = s.id AND a.user_id = ? "
        "JOIN users u ON u.name = s.author AND u.deactivated = 0 "
        "LEFT JOIN dv_story_views v ON v.story_id = s.id AND v.viewer = ? "
        "LEFT JOIN dv_story_reactions x ON x.story_id = s.id AND x.user_id = ? "
        "WHERE s.expires_ts > ? ORDER BY s.author, s.created_ts",
        (me, me, me, now),
    )
    groups = {}
    order = []
    for r in txn.fetchall():
        author = r[0]
        d = _story_dict(r[1:10])
        d["seen"] = bool(r[10])
        d["my_reaction"] = r[11]
        if author not in groups:
            groups[author] = []
            order.append(author)
        groups[author].append(d)
    return mine, [{"user_id": a, "items": groups[a]} for a in order]


def _in_audience(txn, sid, user_id, now):
    """Сторис живой, адресован этому человеку; возвращает автора или None."""
    txn.execute(
        "SELECT s.author FROM dv_stories s JOIN dv_story_audience a "
        "ON a.story_id = s.id AND a.user_id = ? WHERE s.id = ? AND s.expires_ts > ?",
        (user_id, sid, now),
    )
    row = txn.fetchone()
    return row[0] if row else None


def _view(txn, sid, viewer, now):
    if _in_audience(txn, sid, viewer, now) is None:
        return "not_found"
    txn.execute(
        "INSERT INTO dv_story_views (story_id, viewer, ts) VALUES (?, ?, ?) ON CONFLICT DO NOTHING",
        (sid, viewer, now),
    )
    return "ok"


def _viewers(txn, sid, me, now):
    txn.execute("SELECT 1 FROM dv_stories WHERE id = ? AND author = ? AND expires_ts > ?", (sid, me, now))
    if txn.fetchone() is None:
        return None
    txn.execute(
        "SELECT v.viewer, v.ts, x.emoji FROM dv_story_views v "
        "LEFT JOIN dv_story_reactions x ON x.story_id = v.story_id AND x.user_id = v.viewer "
        "WHERE v.story_id = ? ORDER BY v.ts DESC",
        (sid,),
    )
    return [{"user_id": r[0], "ts": r[1], "reaction": r[2]} for r in txn.fetchall()]


def _react(txn, sid, user_id, emoji, now):
    if _in_audience(txn, sid, user_id, now) is None:
        return "not_found"
    if emoji is None:
        txn.execute("DELETE FROM dv_story_reactions WHERE story_id = ? AND user_id = ?", (sid, user_id))
        return "ok"
    txn.execute(
        "INSERT INTO dv_story_reactions (story_id, user_id, emoji, ts) VALUES (?, ?, ?, ?) "
        "ON CONFLICT (story_id, user_id) DO UPDATE SET emoji = ?, ts = ?",
        (sid, user_id, emoji, now, emoji, now),
    )
    # реакция означает просмотр
    txn.execute(
        "INSERT INTO dv_story_views (story_id, viewer, ts) VALUES (?, ?, ?) ON CONFLICT DO NOTHING",
        (sid, user_id, now),
    )
    return "ok"


def _delete(txn, sid, user_id, is_admin):
    """Скрывает сторис сразу (срок = 0); файл и записи удалит уборка."""
    txn.execute("SELECT author FROM dv_stories WHERE id = ?", (sid,))
    row = txn.fetchone()
    if row is None or (row[0] != user_id and not is_admin):
        return "not_found"
    txn.execute("UPDATE dv_stories SET expires_ts = 0 WHERE id = ?", (sid,))
    return "ok"


def _expired(txn, before_ts, limit=100):
    txn.execute("SELECT id, mxc FROM dv_stories WHERE expires_ts < ? LIMIT ?", (before_ts, limit))
    return [(r[0], r[1]) for r in txn.fetchall()]


def _drop(txn, ids):
    for sid in ids:
        for table, col in (
            ("dv_story_views", "story_id"),
            ("dv_story_reactions", "story_id"),
            ("dv_story_audience", "story_id"),
            ("dv_stories", "id"),
        ):
            txn.execute("DELETE FROM %s WHERE %s = ?" % (table, col), (sid,))


# ---------- HTTP-часть ----------

class _Root(DirectServeJsonResource):
    isLeaf = True  # все подпути обрабатываем сами

    def __init__(self, mod):
        super().__init__()
        self._m = mod

    async def _async_render_GET(self, request):
        return await self._m.handle(request, "GET")

    async def _async_render_POST(self, request):
        return await self._m.handle(request, "POST")


class DvStories:
    def __init__(self, config, api):
        self._api = api
        self._server = (config or {}).get("server_name") or api.server_name
        self._ready = False
        self._hits = defaultdict(deque)
        api.register_web_resource(PREFIX, _Root(self))
        # таблицы создаём сразу после старта, уборку запускаем по таймеру
        api.delayed_background_call(5000, self._start)

    @staticmethod
    def parse_config(config):
        return config

    async def _start(self):
        try:
            await self._ensure()
            logger.info("dv_stories: таблицы готовы")
        except Exception:
            logger.exception("dv_stories: не удалось создать таблицы")
        self._api.looping_background_call(self._cleanup, CLEAN_EVERY_MS, desc="dv_stories_cleanup")

    async def _ensure(self):
        if not self._ready:
            await self._api.run_db_interaction("dvs_init", _init_tables)
            self._ready = True

    def _limited(self, key, limit):
        now = time.time()
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

    async def _cleanup(self):
        """Раз в 10 минут: удаляет файлы протухших сторис, затем их записи."""
        try:
            await self._ensure()
            run = self._api.run_db_interaction
            rows = await run("dvs_expired", _expired, _now_ms() - GRACE_MS)
            if not rows:
                return
            media_ids = []
            for _sid, mxc in rows:
                m = MEDIA_RE.match(mxc or "")
                if m and m.group(1) == self._server:
                    media_ids.append(m.group(2))
            if media_ids:
                repo = self._api._hs.get_media_repository()
                await repo.delete_local_media_ids(media_ids)
            await run("dvs_drop", _drop, [r[0] for r in rows])
            logger.info("dv_stories: удалено сторис: %d", len(rows))
        except Exception:
            logger.exception("dv_stories: ошибка уборки, повтор через 10 минут")

    async def handle(self, request, method):
        sub = request.path.decode("utf-8")[len(PREFIX):].strip("/")
        requester = await self._api.get_user_by_req(request)
        user_id = requester.user.to_string()
        if self._limited((user_id, "all"), LIMIT_ALL):
            return 429, {"errcode": "M_LIMIT_EXCEEDED", "error": "Слишком часто"}
        await self._ensure()
        run = self._api.run_db_interaction
        now = _now_ms()

        if sub == "feed" and method == "GET":
            mine, friends = await run("dvs_feed", _feed, user_id, now)
            return 200, {"mine": mine, "friends": friends, "now": now}

        if sub == "publish" and method == "POST":
            if self._limited((user_id, "pub"), LIMIT_PUBLISH):
                return 429, {"errcode": "M_LIMIT_EXCEEDED", "error": "Слишком часто"}
            b = self._body(request)
            kind = b.get("kind")
            m = MEDIA_RE.match(str(b.get("mxc", "")))
            if kind not in ("photo", "video") or not m or m.group(1) != self._server:
                return 400, {"errcode": "DVS_BAD_MEDIA", "error": "Неверный файл сторис"}
            dur = b.get("duration_ms")
            dur = int(dur) if isinstance(dur, (int, float)) else None
            if kind == "video" and (dur is None or dur <= 0 or dur > MAX_VIDEO_MS):
                return 400, {"errcode": "DVS_TOO_LONG", "error": "Видео длиннее 10 секунд"}
            width = b.get("width") if isinstance(b.get("width"), int) else None
            height = b.get("height") if isinstance(b.get("height"), int) else None
            caption = str(b.get("caption") or "")[:200]
            if not await run("dvs_owns", _owns_media, user_id, m.group(2)):
                return 400, {"errcode": "DVS_BAD_MEDIA", "error": "Файл загружен не вами"}
            if await run("dvs_cnt", _active_count, user_id, now) >= MAX_ACTIVE:
                return 400, {"errcode": "DVS_TOO_MANY", "error": "Слишком много живых сторис"}
            is_admin = await self._api.is_user_admin(user_id)
            friends = await run("dvs_friends", _friend_ids, user_id, is_admin)
            aud = b.get("audience") if isinstance(b.get("audience"), dict) else {}
            if aud.get("mode") == "some":
                wanted = [u for u in (aud.get("users") or []) if isinstance(u, str)]
                audience = [u for u in dict.fromkeys(wanted) if u in set(friends)]
            else:
                audience = friends
            audience = audience[:MAX_AUDIENCE]
            if not audience:
                return 400, {"errcode": "DVS_EMPTY_AUDIENCE", "error": "Некому показывать сторис"}
            sid = await run(
                "dvs_publish", _publish, user_id, now, "mxc://%s/%s" % (m.group(1), m.group(2)),
                kind, width, height, dur, caption, audience,
            )
            return 200, {"id": sid, "audience": audience, "expires_ts": now + TTL_MS}

        if sub in ("view", "viewers", "react", "delete") and method == "POST":
            b = self._body(request)
            sid = str(b.get("id", ""))[:40]
            if not sid:
                return 400, {"errcode": "DVS_BAD_ID", "error": "Нет id"}
            if sub == "view":
                st = await run("dvs_view", _view, sid, user_id, now)
                return (200, {"status": "ok"}) if st == "ok" else (404, {"errcode": "DVS_NOT_FOUND", "error": "Сторис недоступен"})
            if sub == "viewers":
                lst = await run("dvs_viewers", _viewers, sid, user_id, now)
                if lst is None:
                    return 404, {"errcode": "DVS_NOT_FOUND", "error": "Сторис недоступен"}
                return 200, {"viewers": lst}
            if sub == "react":
                emoji = b.get("emoji")
                if emoji is not None and (not isinstance(emoji, str) or not emoji or len(emoji) > EMOJI_MAX):
                    return 400, {"errcode": "DVS_BAD_EMOJI", "error": "Неверная реакция"}
                st = await run("dvs_react", _react, sid, user_id, emoji, now)
                return (200, {"status": "ok"}) if st == "ok" else (404, {"errcode": "DVS_NOT_FOUND", "error": "Сторис недоступен"})
            is_admin = await self._api.is_user_admin(user_id)
            st = await run("dvs_delete", _delete, sid, user_id, is_admin)
            return (200, {"status": "ok"}) if st == "ok" else (404, {"errcode": "DVS_NOT_FOUND", "error": "Сторис недоступен"})

        return 404, {"errcode": "M_NOT_FOUND", "error": "Нет такого адреса"}
