// Админка DVChat: веб-сервер без внешних зависимостей.
import { createServer } from 'node:http';
import { readFileSync, appendFileSync, mkdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join, extname } from 'node:path';
import { loadConfig, isConfigured } from './lib/config.mjs';
import { verifyPassword, Sessions, LoginLimiter, parseCookies, hostAllowed, csrfOk } from './lib/auth.mjs';
import { Synapse } from './lib/synapse.mjs';
import { createApi, HttpError } from './lib/api.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const PUB = join(here, 'public');
const TYPES = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.css': 'text/css; charset=utf-8', '.svg': 'image/svg+xml' };
const COOKIE = 'dvadmin_sid';
const CSP = "default-src 'none'; script-src 'self'; style-src 'self'; img-src 'self' data:; connect-src 'self'; base-uri 'none'; form-action 'self'; frame-ancestors 'none'";

export function createApp(cfg = loadConfig(), { fetchImpl } = {}) {
  const sessions = new Sessions({ idleMs: cfg.idleMs, absoluteMs: cfg.absoluteMs });
  const limiter = new LoginLimiter();
  const syn = new Synapse({ url: cfg.synapseUrl, token: cfg.synapseToken, fetchImpl });
  const audit = (action, data) => {
    try {
      mkdirSync(cfg.dataDir, { recursive: true });
      appendFileSync(join(cfg.dataDir, 'audit.log'), JSON.stringify({ t: new Date().toISOString(), action, ...data }) + '\n');
    } catch { /* журнал не должен ломать работу */ }
  };
  const api = createApi({ cfg, syn, audit });
  const static_ = new Map();
  for (const f of ['index.html', 'app.js', 'qr.js', 'style.css']) static_.set('/' + f, { body: readFileSync(join(PUB, f)), type: TYPES[extname(f)] });

  const send = (res, status, obj, extra = {}) => {
    const body = JSON.stringify(obj);
    res.writeHead(status, { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store', ...extra });
    res.end(body);
  };
  const readBody = (req) => new Promise((resolve, reject) => {
    let size = 0; const chunks = [];
    req.on('data', (c) => { size += c.length; if (size > 65_536) { reject(new HttpError(413, 'Слишком большой запрос')); req.destroy(); } else chunks.push(c); });
    req.on('end', () => { try { resolve(chunks.length ? JSON.parse(Buffer.concat(chunks).toString('utf8')) : {}); } catch { reject(new HttpError(400, 'Некорректный JSON')); } });
    req.on('error', reject);
  });

  const server = createServer(async (req, res) => {
    const secure = {
      'Content-Security-Policy': CSP, 'X-Content-Type-Options': 'nosniff', 'Referrer-Policy': 'no-referrer',
      'X-Frame-Options': 'DENY', 'Cross-Origin-Resource-Policy': 'same-origin',
    };
    for (const [k, v] of Object.entries(secure)) res.setHeader(k, v);
    try {
      if (!hostAllowed(req.headers.host, cfg.allowedHosts)) return send(res, 421, { error: 'Неверный адрес' });
      const url = new URL(req.url, 'http://x');
      const path = url.pathname;
      const ip = req.socket.remoteAddress || '';

      if (req.method === 'GET' && path === '/health') return send(res, 200, { ok: true });
      if (req.method === 'GET' && (path === '/' || static_.has(path))) {
        const f = static_.get(path === '/' ? '/index.html' : path);
        res.writeHead(200, { 'Content-Type': f.type, 'Cache-Control': 'no-cache' });
        return res.end(f.body);
      }
      if (!path.startsWith('/api/')) return send(res, 404, { error: 'Не найдено' });

      if (req.method !== 'GET' && !csrfOk(req, cfg.allowedHosts)) return send(res, 403, { error: 'Запрос отклонён' });

      if (!isConfigured(cfg)) return send(res, 503, { error: 'Админка не настроена: задайте пароль и токен Synapse', code: 'NOT_CONFIGURED' });

      const token = parseCookies(req.headers.cookie)[COOKIE];
      if (req.method === 'POST' && path === '/api/login') {
        if (limiter.blocked(ip)) return send(res, 429, { error: 'Слишком много попыток, подождите' });
        const body = await readBody(req);
        if (!verifyPassword(String(body.password || ''), cfg.passwordHash)) {
          limiter.fail(ip); audit('login.fail', { ip });
          return send(res, 401, { error: 'Неверный пароль' });
        }
        limiter.ok(ip); audit('login.ok', { ip });
        const t = sessions.create();
        const flags = `HttpOnly; SameSite=Strict; Path=/${cfg.cookieSecure ? '; Secure' : ''}`;
        return send(res, 200, { ok: true }, { 'Set-Cookie': `${COOKIE}=${t}; ${flags}` });
      }
      if (req.method === 'POST' && path === '/api/logout') {
        sessions.destroy(token);
        return send(res, 200, { ok: true }, { 'Set-Cookie': `${COOKIE}=; HttpOnly; SameSite=Strict; Path=/; Max-Age=0` });
      }
      if (!sessions.check(token)) return send(res, 401, { error: 'Нужен вход', code: 'LOGIN' });
      if (req.method === 'GET' && path === '/api/session') return send(res, 200, { ok: true, server_name: await api.serverName().catch(() => '') });

      const handler = api.routes[`${req.method} ${path}`];
      if (!handler) return send(res, 404, { error: 'Не найдено' });
      const body = req.method === 'POST' ? await readBody(req) : {};
      const out = await handler({ body, query: Object.fromEntries(url.searchParams) });
      return send(res, 200, out);
    } catch (e) {
      const status = e.status && e.status >= 400 && e.status < 600 ? e.status : 500;
      if (status >= 500) console.error('Ошибка:', e.message);
      return send(res, status, { error: status >= 500 && !(e.errcode || e.code) ? 'Внутренняя ошибка' : e.message, code: e.errcode || e.code || 'ERROR' });
    }
  });
  return { server, sessions, limiter, syn };
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const cfg = loadConfig();
  const { server } = createApp(cfg);
  server.listen(cfg.port, cfg.bind, () => console.log(`Админка DVChat слушает ${cfg.bind}:${cfg.port}${isConfigured(cfg) ? '' : ' (не настроена)'}`));
}
