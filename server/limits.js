// The database everyone shares, kept usable for everyone.
//
// D1's free plan allows 100,000 rows written a day across the account. The
// day that runs out, every write fails until midnight UTC: sign-in, pairing,
// the AI allowances, everything. Sync is by far the largest writer (a first
// sync of a big library is thousands of documents), so it gets a daily budget
// of its own and leaves the rest of the day to everything else; and the
// writers anyone can reach with a free device account (support messages,
// question reports, crash reports) get a ceiling for all accounts together on
// top of each account's own. What they keep is pruned nightly, so the database
// cannot be filled a little at a time either.

const today = () => new Date().toISOString().slice(0, 10);
const nowSeconds = () => Math.floor(Date.now() / 1000);

/// Rows written a day that sync may use, and what one document costs: its
/// revision, the document and its index entry, and the account's usage row.
export const SYNC_ROWS_PER_DAY = 60_000;
export const ROWS_PER_DOC = 5;

/// Ceilings for all accounts together, per UTC day.
export const SUPPORT_PER_DAY = 100;
export const REPORTS_PER_DAY = 200;
export const DIAGNOSTICS_PER_DAY = 2_000;

/// How long what they keep is kept, and how much one night removes (a large
/// delete is itself rows written, so it is spread over nights).
export const SUPPORT_KEEP_DAYS = 120;
export const REPORTS_KEEP_DAYS = 120;
export const COUNTERS_KEEP_DAYS = 7;
/// A deleted account's purchase tag and sign-in (released_tokens): long enough
/// to come back within a subscription year and keep what was bought, not for
/// ever.
export const RELEASED_KEEP_DAYS = 365;
/// A checked item's verdict is reused this long (accuracy.js reads the same
/// setting); older ones would be checked again anyway, so they go.
export const VERDICTS_KEEP_DAYS = 365;
/// Apple sign-in nonces already used (worker.js): an identity token lives ten
/// minutes, so a day is plenty.
export const NONCES_KEEP_SECONDS = 86400;
export const PRUNE_ROWS = 5_000;

/// Adds `n` to a counter for today, all or nothing, while it stays within
/// `limit`: one statement, so two requests at once cannot both take the last
/// of it. Kept in ai_usage, under a name no account has.
export async function takeToday(env, name, n, limit) {
  if (n <= 0) return true;
  if (n > limit) return false;
  const result = await env.DB.prepare(
    `INSERT INTO ai_usage (account_id, day, requests) VALUES (?, ?, ?)
     ON CONFLICT (account_id, day) DO UPDATE SET requests = requests + excluded.requests
     WHERE requests + excluded.requests <= ?`)
    .bind(name, today(), n, limit).run();
  return (result.meta?.changes ?? 0) > 0;
}

/// A ceiling from the environment, or the default when unset or unreadable.
export function ceiling(raw, fallback) {
  const n = Number(raw);
  return raw !== undefined && raw !== null && raw !== '' && Number.isFinite(n) && n >= 0 ? n : fallback;
}

/// Nightly (worker.js scheduled): support messages and question reports past
/// their time, and the daily counters of days long gone. Only rows dated as
/// days are counters' days; the few rows kept under other names (a month, a
/// flag) are left alone.
export async function pruneStores(env, clock = nowSeconds) {
  const at = clock();
  const removed = {};
  removed.support = (await env.DB.prepare(
    `DELETE FROM support_messages WHERE id IN (
       SELECT id FROM support_messages WHERE created_at < ? LIMIT ?)`)
    .bind(at - SUPPORT_KEEP_DAYS * 86400, PRUNE_ROWS).run()).meta?.changes ?? 0;
  removed.reports = (await env.DB.prepare(
    `DELETE FROM accuracy_reports WHERE rowid IN (
       SELECT rowid FROM accuracy_reports WHERE created_at < ? LIMIT ?)`)
    .bind(at - REPORTS_KEEP_DAYS * 86400, PRUNE_ROWS).run()).meta?.changes ?? 0;
  const before = new Date((at - COUNTERS_KEEP_DAYS * 86400) * 1000).toISOString().slice(0, 10);
  removed.counters = (await env.DB.prepare(
    `DELETE FROM ai_usage WHERE rowid IN (
       SELECT rowid FROM ai_usage
       WHERE day GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]' AND day < ? LIMIT ?)`)
    .bind(before, PRUNE_ROWS).run()).meta?.changes ?? 0;
  // tables a deploy may not have created yet are skipped, not fatal
  const prune = async (name, sql, ...args) => {
    try {
      removed[name] = (await env.DB.prepare(sql).bind(...args, PRUNE_ROWS).run()).meta?.changes ?? 0;
    } catch (error) {
      console.error('prune', name, error?.message || error);
      removed[name] = 0;
    }
  };
  // pairing and device-account tries, counted per address per hour
  await prune('attempts',
    `DELETE FROM pair_attempts WHERE rowid IN (SELECT rowid FROM pair_attempts WHERE hour < ? LIMIT ?)`,
    Math.floor(at / 3600) - 24);
  const verdictDays = Number(env.ACCURACY_CACHE_DAYS) || VERDICTS_KEEP_DAYS;
  await prune('verdicts',
    `DELETE FROM accuracy_verdicts WHERE hash IN (SELECT hash FROM accuracy_verdicts WHERE created_at < ? LIMIT ?)`,
    at - verdictDays * 86400);
  await prune('released',
    `DELETE FROM released_tokens WHERE token IN (SELECT token FROM released_tokens WHERE released_at < ? LIMIT ?)`,
    at - RELEASED_KEEP_DAYS * 86400);
  await prune('nonces',
    `DELETE FROM used_nonces WHERE nonce IN (SELECT nonce FROM used_nonces WHERE used_at < ? LIMIT ?)`,
    at - NONCES_KEEP_SECONDS);
  return removed;
}
