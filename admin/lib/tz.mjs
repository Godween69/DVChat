// Часовой пояс для подсчёта суток в панели: сдвиг от UTC в часах.
// Задаётся переменной DVADMIN_TZ_HOURS (например 3 для UTC+3), по умолчанию 0 (UTC).
const h = Number(process.env.DVADMIN_TZ_HOURS);
export const TZ_MS = (Number.isFinite(h) ? h : 0) * 3600e3;
