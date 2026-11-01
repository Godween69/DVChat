// Команды первичной настройки: node cli.mjs set-password | synapse-login
import { createInterface } from 'node:readline';
import { writeFileSync, mkdirSync } from 'node:fs';
import { dirname } from 'node:path';
import { hashPassword } from './lib/auth.mjs';
import { loadConfig } from './lib/config.mjs';

function ask(q, hidden) {
  return new Promise((resolve) => {
    const rl = createInterface({ input: process.stdin, output: process.stdout, terminal: true });
    if (hidden) { rl._writeToOutput = (s) => { if (s.includes(q)) process.stdout.write(s); }; }
    rl.question(q, (a) => { rl.close(); if (hidden) process.stdout.write('\n'); resolve(a); });
  });
}
const readAll = async () => { const c = []; for await (const x of process.stdin) c.push(x); return Buffer.concat(c).toString('utf8'); };
const write = (path, text) => { mkdirSync(dirname(path), { recursive: true }); writeFileSync(path, text, { mode: 0o600 }); };

const cfg = loadConfig();
const cmd = process.argv[2];
if (cmd === 'set-password') {
  // Пароль берётся со стандартного ввода (из скрипта) или спрашивается скрытым вводом
  const pw = process.stdin.isTTY ? await ask('Новый пароль админки: ', true) : (await readAll()).replace(/\r?\n$/, '');
  if (pw.length < 10) { console.error('Пароль короче 10 символов'); process.exit(1); }
  write(cfg.hashFile, hashPassword(pw) + '\n');
  console.log('Пароль админки сохранён.');
} else if (cmd === 'synapse-login') {
  // Получает токен администратора Synapse по его паролю и кладёт в файл; сам пароль нигде не хранится
  const user = process.env.DVADMIN_MATRIX_USER || (await ask('Имя администратора Synapse (без @ и домена): ', false));
  const pw = process.env.DVADMIN_MATRIX_PASSWORD || (await ask('Пароль администратора Synapse: ', true));
  const r = await fetch(cfg.synapseUrl + '/_matrix/client/v3/login', {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ type: 'm.login.password', identifier: { type: 'm.id.user', user }, password: pw, initial_device_display_name: 'DVChat admin' }),
  });
  const j = await r.json().catch(() => ({}));
  if (!r.ok || !j.access_token) { console.error('Вход не удался:', j.error || r.status); process.exit(1); }
  write(cfg.tokenFile, j.access_token + '\n');
  console.log(`Токен сохранён для ${j.user_id}.`);
} else {
  console.error('Команды: set-password, synapse-login'); process.exit(2);
}
