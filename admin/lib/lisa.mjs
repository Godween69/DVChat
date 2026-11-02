import { TZ_MS } from './tz.mjs';
// Раздел «Лиза»: правка файла настроек сервиса Лизы (config.json) с проверкой значений и копией перед записью.
import { readFileSync, writeFileSync, renameSync, copyFileSync, readdirSync, unlinkSync, existsSync, statSync } from 'node:fs';
import { dirname, basename, join } from 'node:path';

export const GAMES = [
  ['ttt', 'Крестики-нолики'], ['bs', 'Морской бой'], ['ckr', 'Шашки'], ['c4', 'Четыре в ряд'],
  ['chess', 'Шахматы'], ['durak', 'Дурак'], ['nardy', 'Нарды'], ['domino', 'Домино'],
];
const GAME_IDS = new Set(GAMES.map((g) => g[0]));
// Статистика игр хранится в профиле человека (account data, тип dv.game_stats), её сохраняет приложение.
// Формат v1: { v: 1, games: { chess: { played, won, lost, drawn, last, days: { "2026-11-01": 3 } } } }
// last = время последней партии (мс), days = сколько партий по дням (необязательно, последние 30 дней).
export const GAME_STATS_TYPE = 'dv.game_stats';
const natural = (v) => (Number.isFinite(Number(v)) && Number(v) >= 0 ? Math.floor(Number(v)) : 0);
export function parseGameStats(content) {
  const out = {};
  if (!content || typeof content !== 'object' || !content.games || typeof content.games !== 'object') return out;
  for (const [id, g] of Object.entries(content.games)) {
    if (!GAME_IDS.has(id) || !g || typeof g !== 'object') continue;
    const played = natural(g.played);
    if (!played) continue;
    const days = {};
    if (g.days && typeof g.days === 'object') for (const [d, n] of Object.entries(g.days).slice(0, 60)) if (/^\d{4}-\d{2}-\d{2}$/.test(d) && natural(n)) days[d] = natural(n);
    out[id] = { played, won: Math.min(natural(g.won), played), lost: Math.min(natural(g.lost), played), drawn: Math.min(natural(g.drawn), played), last: natural(g.last) || null, days };
  }
  return out;
}

// Сводка по всем людям: по играм, по людям и по дням (последние 14 суток по Москве)
export function summarizeGames(rows, now = Date.now()) {
  const names = new Map(GAMES);
  const games = GAMES.map(([id, name]) => ({ id, name, players: 0, played: 0, won: 0, lost: 0, drawn: 0, last: null, top: [] }));
  const byId = new Map(games.map((g) => [g.id, g]));
  const dayKey = (ms) => new Date(ms + TZ_MS).toISOString().slice(0, 10);
  const perDay = new Map();
  const people = [];
  for (const r of rows) {
    const st = parseGameStats(r.data), ids = Object.keys(st);
    if (!ids.length) continue;
    let played = 0, won = 0, last = 0, fav = null;
    for (const id of ids) {
      const s = st[id], g = byId.get(id);
      g.players++; g.played += s.played; g.won += s.won; g.lost += s.lost; g.drawn += s.drawn;
      if (s.last) g.last = Math.max(g.last || 0, s.last);
      g.top.push({ label: r.label, played: s.played, won: s.won });
      played += s.played; won += s.won; last = Math.max(last, s.last || 0);
      if (!fav || s.played > st[fav].played) fav = id;
      for (const [d, n] of Object.entries(s.days)) perDay.set(d, (perDay.get(d) || 0) + n);
    }
    people.push({ user_id: r.user_id, label: r.label, played, won, last: last || null, favorite: fav, favorite_name: names.get(fav), games: st });
  }
  for (const g of games) { g.top.sort((a, b) => b.played - a.played); g.top = g.top.slice(0, 5); }
  people.sort((a, b) => b.played - a.played || a.label.localeCompare(b.label));
  const series = [];
  for (let i = 13; i >= 0; i--) { const d = dayKey(now - i * 86400e3); series.push({ day: d, n: perDay.get(d) || 0 }); }
  return { games: games.sort((a, b) => b.played - a.played || a.name.localeCompare(b.name)), people, with_data: people.length,
    total_played: people.reduce((a, p) => a + p.played, 0), series, has_days: perDay.size > 0 };
}

export const FEATURES = [
  ['search', 'Поиск в интернете'], ['weather', 'Погода'], ['chat_context', 'Разбор выбранного чата (по согласию человека)'],
];
const FEATURE_IDS = FEATURES.map((f) => f[0]);
const DEFAULT_FEATURES = { search: true, weather: true, chat_context: false };

const bad = (m) => Object.assign(new Error(m), { status: 400, code: 'BAD_REQUEST' });
const int = (v, min, max, name) => {
  const n = Number(v);
  if (!Number.isInteger(n) || n < min || n > max) throw bad(`${name}: целое число от ${min} до ${max}`);
  return n;
};
const bool = (v, name) => { if (typeof v !== 'boolean') throw bad(`${name}: нужно да или нет`); return v; };

export function readLisa(path) {
  return JSON.parse(readFileSync(path, 'utf8'));
}

export function saveLisa(path, cfg) {
  const dir = dirname(path), base = basename(path);
  const stamp = new Date().toISOString().replace(/[-:T]/g, '').slice(0, 14);
  copyFileSync(path, join(dir, `${base}.bak-${stamp}`));
  // Оставляем десять последних копий
  const baks = readdirSync(dir).filter((f) => f.startsWith(base + '.bak-')).sort();
  for (const old of baks.slice(0, Math.max(0, baks.length - 10))) { try { unlinkSync(join(dir, old)); } catch { /* ничего */ } }
  const tmp = join(dir, `.${base}.tmp`);
  writeFileSync(tmp, JSON.stringify(cfg, null, 2) + '\n', { mode: 0o644 });
  renameSync(tmp, path);
}

const featuresOf = (cfg) => (cfg.features ||= { defaults: { ...DEFAULT_FEATURES }, users: {} });

export function applyGlobal(cfg, p) {
  if ('system_prompt' in p) {
    const s = String(p.system_prompt);
    if (s.trim().length < 20 || s.length > 6000) throw bad('Инструкция Лизы: от 20 до 6000 символов');
    cfg.system_prompt = s;
  }
  if ('tools_enabled' in p) cfg.tools_enabled = bool(p.tools_enabled, 'Инструменты');
  if ('default_city' in p) {
    const s = String(p.default_city).trim();
    if (!s || s.length > 64 || /[\r\n<>]/.test(s)) throw bad('Город по умолчанию: до 64 символов');
    cfg.default_city = s;
  }
  if ('search_url' in p) {
    const s = String(p.search_url).trim();
    if (!/^https?:\/\/[A-Za-z0-9.\-]+(:\d+)?\/?$/.test(s)) throw bad('Адрес поиска: http://хост:порт');
    cfg.search_url = s.replace(/\/$/, '');
  }
  if ('log_questions_days' in p) cfg.log_questions_days = int(p.log_questions_days, 0, 30, 'Срок хранения вопросов (дни, 0 = не хранить)');
  if ('model_timeout' in p) cfg.model_timeout = int(p.model_timeout, 5, 90, 'Ожидание ответа модели (секунды)');
  if ('read_pages' in p) cfg.read_pages = int(p.read_pages, 0, 4, 'Сколько страниц читать');
  if ('safesearch' in p) { const n = int(p.safesearch, 1, 2, 'Фильтр поиска'); cfg.safesearch = n; }
  if ('news_range' in p) { if (!['day', 'week', 'month'].includes(p.news_range)) throw bad('Свежесть новостей: day, week или month'); cfg.news_range = p.news_range; }
  if ('key_warn_usd' in p) { const n = Number(p.key_warn_usd); if (!Number.isFinite(n) || n < 0 || n > 10000) throw bad('Порог остатка на ключе: число от 0 до 10000'); cfg.key_warn_usd = n; }
  if ('search_engines' in p) {
    const a = Array.isArray(p.search_engines) ? p.search_engines.map((x) => String(x).trim()).filter(Boolean) : null;
    if (!a || a.length > 12 || a.some((x) => !/^[A-Za-z0-9 _.\-]{1,40}$/.test(x))) throw bad('Поисковые движки: до 12 названий через запятую');
    if (a.length) cfg.search_engines = a; else delete cfg.search_engines;
  }
  if (p.limits) {
    cfg.limits ||= {};
    const L = p.limits;
    if ('per_user_per_day' in L) cfg.limits.per_user_per_day = int(L.per_user_per_day, 1, 10000, 'Запросов на человека в сутки');
    if ('global_per_day' in L) cfg.limits.global_per_day = int(L.global_per_day, 1, 100000, 'Запросов всего в сутки');
    if ('max_output_tokens' in L) cfg.limits.max_output_tokens = int(L.max_output_tokens, 100, 8000, 'Длина ответа (токены)');
    if ('max_history_messages' in L) cfg.limits.max_history_messages = int(L.max_history_messages, 1, 50, 'Сообщений истории');
  }
  if (p.features_defaults) {
    const f = featuresOf(cfg);
    for (const k of FEATURE_IDS) if (k in p.features_defaults) f.defaults[k] = bool(p.features_defaults[k], k);
  }
  if ('games_off_all' in p) {
    if (!Array.isArray(p.games_off_all) || p.games_off_all.some((g) => !GAME_IDS.has(g))) throw bad('Неизвестная игра в списке');
    const f = featuresOf(cfg);
    if (p.games_off_all.length) f.games_off = [...new Set(p.games_off_all)]; else delete f.games_off;
  }
  if ('allow_all' in p) {
    const list = (cfg.allowed_dv_ids ||= []).map(String).filter((x) => x !== '*');
    cfg.allowed_dv_ids = bool(p.allow_all, 'Всем') ? [...list, '*'] : list;
  }
  return cfg;
}

export function applyUser(cfg, { userId, dvId }, p) {
  if ('allowed' in p) {
    if (!dvId) throw bad('У человека нет ID: сначала он должен войти по ссылке');
    const set = new Set((cfg.allowed_dv_ids ||= []).map(String));
    if (bool(p.allowed, 'Доступ')) set.add(String(dvId)); else set.delete(String(dvId));
    cfg.allowed_dv_ids = [...set];
  }
  if ('limit' in p) {
    cfg.limits ||= {};
    cfg.limits.overrides ||= {};
    if (p.limit === null) delete cfg.limits.overrides[userId];
    else cfg.limits.overrides[userId] = int(p.limit, 1, 10000, 'Лимит');
  }
  const f = featuresOf(cfg);
  f.users ||= {};
  const u = (f.users[userId] ||= {});
  if (p.features) for (const k of FEATURE_IDS) if (k in p.features) { if (p.features[k] === null) delete u[k]; else u[k] = bool(p.features[k], k); }
  if ('games_off' in p) {
    if (!Array.isArray(p.games_off) || p.games_off.some((g) => !GAME_IDS.has(g))) throw bad('Неизвестная игра в списке');
    if (p.games_off.length) u.games_off = [...new Set(p.games_off)]; else delete u.games_off;
  }
  if (!Object.keys(u).length) delete f.users[userId];
  return cfg;
}

// Массово разрешить или запретить Лизу людям. Люди без ID (ещё не входили) пропускаются и возвращаются списком.
export function applyAllowBulk(cfg, items, allowed) {
  if (!Array.isArray(items) || items.length > 500) throw bad('Список людей: до 500 человек');
  bool(allowed, 'Доступ');
  const set = new Set((cfg.allowed_dv_ids ||= []).map(String));
  const skipped = [];
  for (const it of items) {
    if (!it.dvId) { skipped.push(it.userId); continue; }
    if (allowed) set.add(String(it.dvId)); else set.delete(String(it.dvId));
  }
  cfg.allowed_dv_ids = [...set];
  return { cfg, skipped };
}

export function lisaView(cfg, people) {
  const allow = (cfg.allowed_dv_ids || []).map(String);
  const f = cfg.features || { defaults: DEFAULT_FEATURES, users: {} };
  return {
    enabled: true,
    settings: {
      log_questions_days: cfg.log_questions_days ?? 14, model_timeout: cfg.model_timeout ?? 25, read_pages: cfg.read_pages ?? 2,
      safesearch: cfg.safesearch ?? 2, news_range: cfg.news_range || 'week', key_warn_usd: cfg.key_warn_usd ?? 2,
      search_engines: cfg.search_engines || [],
    },
    system_prompt: cfg.system_prompt || '', tools_enabled: cfg.tools_enabled !== false,
    default_city: cfg.default_city || '', search_url: cfg.search_url || '',
    limits: { per_user_per_day: cfg.limits?.per_user_per_day, global_per_day: cfg.limits?.global_per_day, max_output_tokens: cfg.limits?.max_output_tokens, max_history_messages: cfg.limits?.max_history_messages },
    allow_all: allow.includes('*'),
    features_defaults: { ...DEFAULT_FEATURES, ...(f.defaults || {}) },
    features: FEATURES, games: GAMES, games_off_all: f.games_off || [],
    people: people.map((p) => ({
      user_id: p.user_id, displayname: p.displayname, dv_id: p.dv_id,
      admin: (cfg.admins || []).includes(p.user_id),
      allowed: allow.includes('*') || (cfg.admins || []).includes(p.user_id) || (p.dv_id ? allow.includes(p.dv_id) : false),
      limit: cfg.limits?.overrides?.[p.user_id] ?? null,
      features: f.users?.[p.user_id] ? Object.fromEntries(FEATURE_IDS.filter((k) => k in f.users[p.user_id]).map((k) => [k, f.users[p.user_id][k]])) : {},
      games_off: f.users?.[p.user_id]?.games_off || [],
    })),
  };
}
export const lisaConfigured = (path) => Boolean(path) && existsSync(path);

// ---------- Модели, ключ, деньги: данные пишет сама Лиза в каталог panel (панель только читает) ----------
export function readPanel(dir, name) {
  try {
    const p = join(dir, name);
    return { data: JSON.parse(readFileSync(p, 'utf8')), age: (Date.now() - statSync(p).mtimeMs) / 1000 };
  } catch { return null; }
}

// Каталог пишет Лиза: pin/pout (доллары за миллион токенов), ctx. Панели удобнее price_in/price_out/context и признак free
// Для чего подходит модель. Каталог OpenRouter оценок качества не даёт, поэтому метки выводятся из того,
// что в нём есть: имя, возможности (инструменты, рассуждения, картинки), размер контекста.
export function purposeTags(m) {
  const id = String(m.id || '').toLowerCase(), t = [];
  t.push({ key: 'chat', label: 'чат', hint: 'Обычный разговор и вопросы-ответы.' });
  if (/code|coder|codestral|devstral|codex/.test(id)) t.push({ key: 'code', label: 'кодинг', hint: 'Сделана для написания и разбора кода.' });
  if (m.reasoning) t.push({ key: 'reason', label: 'рассуждения', hint: 'Умеет «думать» перед ответом: лучше с задачами и логикой, но медленнее и дороже.' });
  if (m.tools) t.push({ key: 'tools', label: 'инструменты', hint: 'Умеет вызывать инструменты (поиск, функции). Лизе это нужно для поиска в интернете.' });
  if (m.vision) t.push({ key: 'vision', label: 'картинки', hint: 'Понимает присланные картинки.' });
  if ((m.context || m.ctx || 0) >= 200000) t.push({ key: 'long', label: 'длинные тексты', hint: 'Контекст от 200 тысяч токенов: помнит длинную переписку и большие документы.' });
  if (/flash|mini|lite|haiku|small|nano|instant/.test(id)) t.push({ key: 'fast', label: 'быстрая', hint: 'Лёгкая версия: отвечает быстро и дёшево, но проще в сложных задачах.' });
  return t;
}

export function catalogView(raw) {
  return (raw || []).map((m) => {
    const pin = Number(m.pin ?? m.price_in), pout = Number(m.pout ?? m.price_out);
    const ok = Number.isFinite(pin) && Number.isFinite(pout);
    return { id: m.id, name: m.name || m.id, price_in: ok ? pin : null, price_out: ok ? pout : null,
      context: m.ctx ?? m.context ?? null, vision: Boolean(m.vision), free: ok && pin === 0 && pout === 0,
      tags: purposeTags({ id: m.id, vision: Boolean(m.vision), tools: Boolean(m.tools), reasoning: Boolean(m.reasoning), context: m.ctx ?? m.context }),
      tier: !ok ? 'unknown' : (pin === 0 && pout === 0) ? 'free' : pout <= 0.6 ? 'cheap' : pout <= 8 ? 'middle' : 'expensive' };
  });
}

// Расшифровка ошибки модели простыми словами: что случилось и что делать
export function explainError(text) {
  const s = String(text || '');
  const m = /\b([45]\d\d)\b/.exec(s);
  const code = m ? Number(m[1]) : 0;
  const T = {
    429: ['Лимит запросов', 'Модель сейчас перегружена или вы исчерпали её лимит. Для бесплатных моделей это обычное дело: лимит общий для всех пользователей OpenRouter.', 'Подождать, поставить другую модель главной или использовать платную (там лимиты свободнее).'],
    401: ['Ключ не принят', 'OpenRouter не узнал ключ.', 'Заменить ключ: кнопка «Сменить ключ…».'],
    402: ['Не хватает денег', 'На счёте OpenRouter нет средств для платной модели.', 'Пополнить счёт на openrouter.ai или выбрать бесплатную модель.'],
    403: ['Доступ запрещён', 'Провайдер не пускает этот ключ или регион.', 'Выбрать другую модель.'],
    404: ['Модели нет', 'Такой модели у OpenRouter больше нет или у неё нет провайдера.', 'Убрать её из списка и выбрать другую.'],
    408: ['Долгий ответ', 'Модель не ответила вовремя.', 'Обычно проходит само; если повторяется, выберите другую.'],
    500: ['Ошибка у провайдера', 'Сбой на стороне модели.', 'Подождать. Лиза сама переключится на запасную.'],
    502: ['Провайдер недоступен', 'Нет связи с провайдером модели.', 'Подождать. Лиза сама переключится на запасную.'],
    503: ['Модель отключена', 'Провайдер временно не принимает запросы.', 'Подождать или выбрать другую модель.'],
  };
  const t = T[code] || (code >= 500 ? T[500] : null);
  return t ? { code, title: t[0], what: t[1], todo: t[2] } : { code, title: 'Неизвестная ошибка', what: s.slice(0, 200) || 'Причина не указана.', todo: 'Подождать; если не проходит, выбрать другую модель.' };
}

// Подсказки по выбору: из каталога берём только то, что в нём есть (цена, контекст, картинки).
// Качество каталог не сообщает, поэтому «лучше всех» не утверждаем.
export function recommend(list) {
  const paid = list.filter((m) => m.price_out != null && !m.free);
  const cheapest = (arr) => arr.slice().sort((a, b) => (a.price_out + a.price_in) - (b.price_out + b.price_in) || (b.context || 0) - (a.context || 0))[0];
  const pick = (title, m, why) => (m ? { title, id: m.id, price_in: m.price_in, price_out: m.price_out, context: m.context, vision: m.vision, why } : null);
  const longest = list.filter((m) => m.free).sort((a, b) => (b.context || 0) - (a.context || 0))[0];
  return [
    pick('Самая дешёвая с картинками', cheapest(paid.filter((m) => m.vision && (m.context || 0) >= 32000)), 'Платная, понимает картинки, контекст от 32 тысяч.'),
    pick('Самая дешёвая только для текста', cheapest(paid.filter((m) => !m.vision && (m.context || 0) >= 64000)), 'Платная, без картинок, контекст от 64 тысяч.'),
    pick('Бесплатная с самым длинным контекстом', longest, 'Бесплатно, но с общим лимитом (возможна ошибка 429).'),
  ].filter(Boolean);
}

export function applyModels(cfg, ids, catalog) {
  if (!Array.isArray(ids) || ids.length < 1 || ids.length > 6) throw bad('Моделей должно быть от 1 до 6');
  const cat = new Map((catalog || []).map((m) => [m.id, m]));
  const old = new Map((cfg.models || []).map((m) => [m.id, m]));
  const seen = new Set(), out = [];
  for (const id of ids) {
    if (typeof id !== 'string' || id.length > 120 || !/^[A-Za-z0-9._\-]+\/[A-Za-z0-9._:\-]+$/.test(id)) throw bad('Некорректное название модели: ' + String(id).slice(0, 60));
    if (seen.has(id)) throw bad('Модель указана дважды: ' + id);
    seen.add(id);
    if (cat.size && !cat.has(id) && !old.has(id)) throw bad('Такой модели нет в каталоге OpenRouter: ' + id);
    const prev = old.get(id) || {};
    out.push({ ...prev, id, vision: cat.has(id) ? Boolean(cat.get(id).vision) : Boolean(prev.vision) });
  }
  cfg.models = out;
  return cfg;
}

const dayShift = (str, n) => { const d = new Date(str + 'T00:00:00Z'); d.setUTCDate(d.getUTCDate() + n); return d.toISOString().slice(0, 10); };
const zero = () => ({ n: 0, tin: 0, tout: 0, cost: 0 });
const plus = (a, r) => { a.n += r.n || 0; a.tin += r.tin || 0; a.tout += r.tout || 0; a.cost += r.cost || 0; return a; };

export function summarize(stats) {
  const today = stats.today;
  const from7 = dayShift(today, -6), from30 = dayShift(today, -29);
  const win = (rows) => { const t = { today: zero(), d7: zero(), d30: zero() };
    for (const r of rows) { if (r.day === today) plus(t.today, r); if (r.day >= from7) plus(t.d7, r); if (r.day >= from30) plus(t.d30, r); } return t; };
  const byUser = new Map();
  for (const r of stats.users || []) { if (!byUser.has(r.user)) byUser.set(r.user, []); byUser.get(r.user).push(r); }
  const users = [...byUser].map(([user, rows]) => ({ user, ...win(rows) })).sort((a, b) => b.d30.cost - a.d30.cost);
  const byDay = new Map((stats.days || []).map((r) => [r.day, r]));
  const series = [];
  for (let i = 29; i >= 0; i--) { const d = dayShift(today, -i); const r = byDay.get(d); series.push({ day: d, n: r?.n || 0, cost: r?.cost || 0 }); }
  return { totals: win(stats.days || []), users, models: stats.models || [], series };
}

// ---------- Справочник по DVChat: обычный текстовый файл, Лиза перечитывает его сама ----------
export const GUIDE_MAX = 30000;   // столько символов Лиза берёт в инструкцию

export function readGuide(path) {
  try { return readFileSync(path, 'utf8'); } catch { return ''; }
}

export function saveGuide(path, text) {
  if (typeof text !== 'string') throw bad('Нужен текст справочника');
  const t = text.replace(/\r\n/g, '\n');
  if (t.trim().length < 50) throw bad('Справочник слишком короткий (меньше 50 знаков)');
  if (t.length > GUIDE_MAX) throw bad(`Справочник длиннее ${GUIDE_MAX} знаков: Лиза читает только начало. Сократите на ${t.length - GUIDE_MAX}`);
  const dir = dirname(path), base = basename(path);
  if (existsSync(path)) {
    const stamp = new Date().toISOString().replace(/[-:T]/g, '').slice(0, 14);
    copyFileSync(path, join(dir, `${base}.bak-${stamp}`));
    const baks = readdirSync(dir).filter((f) => f.startsWith(base + '.bak-')).sort();
    for (const old of baks.slice(0, Math.max(0, baks.length - 10))) { try { unlinkSync(join(dir, old)); } catch { /* ничего */ } }
  }
  const tmp = join(dir, `.${base}.tmp`);
  writeFileSync(tmp, t.endsWith('\n') ? t : t + '\n', { mode: 0o644 });
  renameSync(tmp, path);
}
