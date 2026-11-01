// Раздел «Лиза»: правка файла настроек сервиса Лизы (config.json) с проверкой значений и копией перед записью.
import { readFileSync, writeFileSync, renameSync, copyFileSync, readdirSync, unlinkSync, existsSync, statSync } from 'node:fs';
import { dirname, basename, join } from 'node:path';

export const GAMES = [
  ['ttt', 'Крестики-нолики'], ['bs', 'Морской бой'], ['ckr', 'Шашки'], ['c4', 'Четыре в ряд'],
  ['chess', 'Шахматы'], ['durak', 'Дурак'], ['nardy', 'Нарды'], ['domino', 'Домино'],
];
const GAME_IDS = new Set(GAMES.map((g) => g[0]));
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
    features: FEATURES, games: GAMES,
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
