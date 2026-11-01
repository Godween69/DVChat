// Настройки админки DVChat: только переменные окружения и файлы секретов.
// Никаких значений «по умолчанию» с чужими адресами: всё либо задаёт владелец, либо нейтрально.
import { readFileSync, existsSync } from 'node:fs';

function readFile(path) {
  try { return readFileSync(path, 'utf8').trim(); } catch { return ''; }
}

export function loadConfig(env = process.env) {
  const port = Number(env.DVADMIN_PORT || 3101);
  const dataDir = env.DVADMIN_DATA_DIR || '/data';
  const secretsDir = env.DVADMIN_SECRETS_DIR || `${dataDir}/secrets`;
  const hashFile = env.DVADMIN_PASSWORD_HASH_FILE || `${secretsDir}/dvadmin_password_hash`;
  const tokenFile = env.DVADMIN_SYNAPSE_TOKEN_FILE || `${secretsDir}/dvadmin_synapse_token`;
  const hosts = (env.DVADMIN_ALLOWED_HOSTS || 'localhost,127.0.0.1')
    .split(',').map((s) => s.trim().toLowerCase()).filter(Boolean);
  return {
    port,
    bind: env.DVADMIN_BIND || '127.0.0.1',
    synapseUrl: (env.DVADMIN_SYNAPSE_URL || 'http://synapse:8008').replace(/\/+$/, ''),
    dataDir,
    hashFile,
    tokenFile,
    passwordHash: readFile(hashFile),
    synapseToken: readFile(tokenFile),
    // Куда мастер настройки пишет dvchat.env (в контейнере это смонтированный файл или папка data)
    envPath: env.DVADMIN_ENV_PATH || `${dataDir}/dvchat.env`,
    allowedHosts: hosts,
    cookieSecure: env.DVADMIN_COOKIE_SECURE === '1',
    idleMs: Number(env.DVADMIN_IDLE_MINUTES || 15) * 60_000,
    absoluteMs: Number(env.DVADMIN_ABSOLUTE_HOURS || 8) * 3_600_000,
    // Лиза: файл настроек сервиса (если смонтирован), иначе раздел скрыт
    lisaConfigPath: env.DVADMIN_LISA_CONFIG || '',
    // Справочник по DVChat (текстовый файл; правится в панели, Лиза перечитывает его сама)
    lisaGuidePath: env.DVADMIN_LISA_GUIDE || '',
    // Каталог, куда Лиза пишет состояние, каталог моделей и статистику (панель читает его только на чтение)
    lisaPanelDir: env.DVADMIN_LISA_PANEL_DIR || '',
    hasDataDir: existsSync(dataDir),
  };
}

export function isConfigured(c) {
  return Boolean(c.passwordHash && c.synapseToken);
}
