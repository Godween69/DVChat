// Пароль (scrypt), сессии, защита от подбора, проверка Host и CSRF.
import { scryptSync, randomBytes, timingSafeEqual, createHash } from 'node:crypto';

const N = 16384, R = 8, P = 1, KEYLEN = 32;

export function hashPassword(password) {
  const salt = randomBytes(16);
  const hash = scryptSync(password, salt, KEYLEN, { N, r: R, p: P });
  return `scrypt$${N}$${R}$${P}$${salt.toString('base64url')}$${hash.toString('base64url')}`;
}

export function verifyPassword(password, stored) {
  const parts = String(stored || '').split('$');
  if (parts.length !== 6 || parts[0] !== 'scrypt') return false;
  const [, n, r, p, salt, hash] = parts;
  const expected = Buffer.from(hash, 'base64url');
  let actual;
  try {
    actual = scryptSync(password, Buffer.from(salt, 'base64url'), expected.length,
      { N: Number(n), r: Number(r), p: Number(p) });
  } catch { return false; }
  return actual.length === expected.length && timingSafeEqual(actual, expected);
}

export function generateSecret(length = 24) {
  const alphabet = 'abcdefghjkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  const bytes = randomBytes(length);
  let out = '';
  for (let i = 0; i < length; i++) out += alphabet[bytes[i] % alphabet.length];
  return out;
}

const sha = (s) => createHash('sha256').update(s).digest('hex');

export class Sessions {
  constructor({ idleMs, absoluteMs, now = () => Date.now() }) {
    this.idleMs = idleMs; this.absoluteMs = absoluteMs; this.now = now;
    this.map = new Map();
    this.timer = setInterval(() => this.sweep(), 60_000);
    this.timer.unref();
  }
  create() {
    const token = randomBytes(32).toString('base64url');
    const t = this.now();
    this.map.set(sha(token), { created: t, seen: t });
    return token;
  }
  check(token) {
    if (!token) return false;
    const key = sha(token);
    const s = this.map.get(key);
    if (!s) return false;
    const t = this.now();
    if (t - s.seen > this.idleMs || t - s.created > this.absoluteMs) { this.map.delete(key); return false; }
    s.seen = t;
    return true;
  }
  destroy(token) { if (token) this.map.delete(sha(token)); }
  sweep() {
    const t = this.now();
    for (const [k, s] of this.map) if (t - s.seen > this.idleMs || t - s.created > this.absoluteMs) this.map.delete(k);
  }
}

// Ограничитель попыток входа: по адресу и общий
export class LoginLimiter {
  constructor({ perIp = 5, total = 30, windowMs = 15 * 60_000, now = () => Date.now() } = {}) {
    Object.assign(this, { perIp, total, windowMs, now });
    this.ips = new Map(); this.all = [];
  }
  _prune(arr) { const t = this.now(); while (arr.length && t - arr[0] > this.windowMs) arr.shift(); return arr; }
  blocked(ip) {
    const a = this._prune(this.ips.get(ip) || []);
    return a.length >= this.perIp || this._prune(this.all).length >= this.total;
  }
  fail(ip) {
    const a = this.ips.get(ip) || []; a.push(this.now()); this.ips.set(ip, a); this.all.push(this.now());
  }
  ok(ip) { this.ips.delete(ip); }
}

export function parseCookies(header) {
  const out = {};
  for (const part of String(header || '').split(';')) {
    const i = part.indexOf('=');
    if (i > 0) out[part.slice(0, i).trim()] = part.slice(i + 1).trim();
  }
  return out;
}

export function hostAllowed(hostHeader, allowed) {
  const host = String(hostHeader || '').toLowerCase().replace(/:\d+$/, '');
  return allowed.includes(host);
}

export const CSRF_HEADER = 'dvchat-admin';
export function csrfOk(req, allowedHosts) {
  if (req.headers['x-requested-with'] !== CSRF_HEADER) return false;
  const site = req.headers['sec-fetch-site'];
  if (site && !['same-origin', 'none'].includes(site)) return false;
  const origin = req.headers.origin;
  if (origin) {
    try { if (!hostAllowed(new URL(origin).host, allowedHosts)) return false; } catch { return false; }
  }
  return true;
}
