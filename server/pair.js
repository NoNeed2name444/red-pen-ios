// A second device, without Apple or Google.
//
// The phone already signed in shows a code; the iPad types it and is in the
// same account, so the library syncs between them. A device that started "on
// this device only" first gets an account of its own here (no name, no email:
// a random id), which is what makes it able to sync at all.
//
// The code is 8 characters from 31 (about 40 bits), lives ten minutes, works
// once, and each address gets 10 wrong tries an hour: guessing one is out of
// reach.
const ALPHABET = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
const CODE_SECONDS = 600;
export const WRONG_PER_HOUR = 10;
export const DEVICES_PER_HOUR = 5;

const now = () => Math.floor(Date.now() / 1000);

export function newCode() {
  const bytes = crypto.getRandomValues(new Uint8Array(8));
  // 256 is not a multiple of 31; the bias left is too small to matter for a
  // ten-minute, rate-limited code
  return [...bytes].map(b => ALPHABET[b % ALPHABET.length]).join('');
}

export function normalise(raw) {
  return typeof raw === 'string' ? raw.toUpperCase().replace(/[^A-Z0-9]/g, '').slice(0, 8) : '';
}

/// Counts one try of `what` from this address; false once the hour's are used.
export async function allowed(env, ip, what, limit) {
  const hour = Math.floor(now() / 3600);
  await env.DB.prepare(
    `INSERT INTO pair_attempts (ip, hour, what, n) VALUES (?, ?, ?, 0)
     ON CONFLICT (ip, hour, what) DO NOTHING`).bind(ip, hour, what).run();
  const r = await env.DB.prepare(
    'UPDATE pair_attempts SET n = n + 1 WHERE ip = ? AND hour = ? AND what = ? AND n < ?')
    .bind(ip, hour, what, limit).run();
  return r.meta.changes === 1;
}

/// For a signed-in device: a fresh code for this account (any older one goes).
export async function startPairing(env, accountId) {
  await env.DB.prepare('DELETE FROM pair_codes WHERE account_id = ? OR expires_at < ?')
    .bind(accountId, now()).run();
  const code = newCode();
  await env.DB.prepare('INSERT INTO pair_codes (code, account_id, expires_at) VALUES (?, ?, ?)')
    .bind(code, accountId, now() + CODE_SECONDS).run();
  return { code, expiresIn: CODE_SECONDS };
}

/// For the new device: the account the code belongs to, or a reason.
export async function finishPairing(env, ip, raw) {
  const code = normalise(raw);
  if (!await allowed(env, ip, 'code', WRONG_PER_HOUR)) {
    return { status: 429, error: 'Too many tries. Wait an hour, or make a new code.' };
  }
  const row = code.length === 8
    ? await env.DB.prepare('SELECT account_id, expires_at FROM pair_codes WHERE code = ?').bind(code).first()
    : null;
  if (!row || row.expires_at < now()) return { status: 404, error: 'That code is wrong or has expired.' };
  // used once: deleted before the session is made, so two devices racing
  // with the same code cannot both get in
  const gone = await env.DB.prepare('DELETE FROM pair_codes WHERE code = ?').bind(code).run();
  if (gone.meta.changes !== 1) return { status: 404, error: 'That code is wrong or has expired.' };
  // a right code does not use up a try
  const hour = Math.floor(now() / 3600);
  await env.DB.prepare('UPDATE pair_attempts SET n = n - 1 WHERE ip = ? AND hour = ? AND what = ? AND n > 0')
    .bind(ip, hour, 'code').run();
  return { accountId: row.account_id };
}
