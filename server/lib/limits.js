// Limits, flags and rate limits for every new route.
//
// limit() and flag() read the remote config (config.js); hit() counts one try
// of something per key per hour in pair_attempts, the table pair.js already
// uses. A key is never a raw IP address: it is ipKey() - a keyed hash of the
// address and the UTC day, so it rotates daily and cannot be turned back into
// an address - or 'acct:<id>', or 'code:<CODE>'.

import { flag, limit } from '../config.js';
import { hmacHex } from './crypto.js';

export { flag, limit };

const nowSeconds = () => Math.floor(Date.now() / 1000);

/// The UTC day of a moment in seconds, as YYYY-MM-DD.
export const utcDay = (seconds = nowSeconds()) => new Date(seconds * 1000).toISOString().slice(0, 10);

/// The first 16 hex of HMAC-SHA256(SESSION_SECRET, 'ip:<addr>:<UTC day>').
export async function ipKey(env, ip, day = utcDay()) {
  const secret = env.SESSION_SECRET || 'no-session-secret';
  return 'ipk:' + (await hmacHex(secret, `ip:${ip || 'unknown'}:${day}`)).slice(0, 16);
}

/// Counts one try of `what` under `key` this hour; false once `n` are used.
/// The insert and the conditional increment are two statements, the same
/// pattern as pair.js allowed(): two requests at once cannot both take the
/// last try.
export async function hit(env, key, what, n, clock = nowSeconds) {
  const hour = Math.floor(clock() / 3600);
  const max = Math.max(0, Math.floor(Number(n) || 0));
  await env.DB.prepare(
    `INSERT INTO pair_attempts (ip, hour, what, n) VALUES (?, ?, ?, 0)
     ON CONFLICT (ip, hour, what) DO NOTHING`).bind(String(key), hour, String(what)).run();
  const r = await env.DB.prepare(
    'UPDATE pair_attempts SET n = n + 1 WHERE ip = ? AND hour = ? AND what = ? AND n < ?')
    .bind(String(key), hour, String(what), max).run();
  return (r.meta?.changes ?? 0) === 1;
}

/// Gives one try back (a right code does not use one up).
export async function refund(env, key, what, clock = nowSeconds) {
  const hour = Math.floor(clock() / 3600);
  await env.DB.prepare('UPDATE pair_attempts SET n = n - 1 WHERE ip = ? AND hour = ? AND what = ? AND n > 0')
    .bind(String(key), hour, String(what)).run();
}
