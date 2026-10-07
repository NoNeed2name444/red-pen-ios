// The database everyone shares (limits.js): sync's daily write budget, the
// ceilings for all accounts together, and the nightly prune - against a real
// SQLite, like the sync tests.
//
// Run: node server/tests/limits.test.mjs

import { DatabaseSync } from 'node:sqlite';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { takeToday, ceiling, pruneStores, ROWS_PER_DOC, SUPPORT_KEEP_DAYS, REPORTS_KEEP_DAYS } from '../limits.js';
import { push } from '../sync.js';
import { supportMessage } from '../support.js';
import { report } from '../accuracy.js';
import { diagnosticsRoute } from '../diagnostics.js';

const here = dirname(fileURLToPath(import.meta.url));
let failures = 0;
const ok = (cond, what) => { console.log((cond ? 'ok   ' : 'FAIL ') + what); if (!cond) failures++; };

function d1(db) {
  return {
    prepare(sql) {
      const stmt = db.prepare(sql);
      let args = [];
      const api = {
        bind(...a) { args = a; return api; },
        first() { return stmt.get(...args) ?? null; },
        all() { return { results: stmt.all(...args) }; },
        run() { return { meta: { changes: Number(stmt.run(...args).changes) } }; },
        exec() {
          if (/\bRETURNING\b|^\s*SELECT/i.test(sql)) {
            const results = stmt.all(...args);
            return { results, meta: { changes: results.length } };
          }
          return { results: [], meta: { changes: Number(stmt.run(...args).changes) } };
        },
      };
      return api;
    },
    async batch(statements) {
      db.exec('BEGIN');
      try { const out = statements.map(s => s.exec()); db.exec('COMMIT'); return out; }
      catch (error) { db.exec('ROLLBACK'); throw error; }
    },
  };
}

function freshEnv(extra = {}) {
  const db = new DatabaseSync(':memory:');
  const sql = readFileSync(join(here, '..', 'schema.sql'), 'utf8').split('\n').map(l => l.replace(/--.*$/, '')).join('\n');
  for (const statement of sql.split(';')) {
    if (!statement.trim()) continue;
    try { db.exec(statement); } catch { /* a table these tests do not need */ }
  }
  return { DB: d1(db), db, ...extra };
}
const body = async res => JSON.parse(await res.text());
const doc = (id, rev = 0) => ({ id, kind: 'set', rev, updatedAt: '2026-01-01T00:00:00.000Z', deleted: false, payload: 'aGk=' });
const today = new Date().toISOString().slice(0, 10);

// MARK: a counter for today

{
  const env = freshEnv();
  ok(await takeToday(env, 'x', 3, 5), 'a counter takes what fits');
  ok(!(await takeToday(env, 'x', 3, 5)), 'and refuses what would pass the limit, all or nothing');
  ok(await takeToday(env, 'x', 2, 5), 'while what still fits is taken');
  ok(env.db.prepare("SELECT requests FROM ai_usage WHERE account_id = 'x' AND day = ?").get(today).requests === 5,
     'and the count is exactly what was taken');
  ok(!(await takeToday(env, 'y', 6, 5)), 'more than the whole limit at once is refused, even on a fresh day');
  ok(await takeToday(env, 'z', 0, 0), 'nothing taken is always allowed');
  ok(ceiling(undefined, 7) === 7 && ceiling('', 7) === 7 && ceiling('abc', 7) === 7 && ceiling('-1', 7) === 7 && ceiling('12', 7) === 12,
     'a ceiling from the environment, or the default when it is unset or unreadable');
}

// MARK: sync's share of the day's writes

{
  const env = freshEnv({ SYNC_ROWS_DAILY: String(ROWS_PER_DOC * 2) });
  let r = await push(env, 'acc', { docs: [doc('a'), doc('b'), doc('c')] });
  let b = await body(r);
  ok(r.status === 200 && b.resting === true && b.accepted.length === 0,
     'a batch the day\'s budget cannot cover is not written, and the answer says sync is resting');
  ok(r.status !== 507, 'never "too large": nothing was refused for its size');
  ok(env.db.prepare('SELECT COUNT(*) AS n FROM docs').get().n === 0, 'and nothing of it reached the database');

  r = await push(env, 'acc', { docs: [doc('a'), doc('b')] });
  b = await body(r);
  ok(r.status === 200 && b.accepted.length === 2 && !b.resting, 'a batch that fits is written whole');
  r = await push(env, 'acc', { docs: [doc('c')] });
  b = await body(r);
  ok(b.resting === true && b.accepted.length === 0, 'and once the day\'s share is spent the next batch waits for tomorrow');
  ok(env.db.prepare("SELECT requests FROM ai_usage WHERE account_id = 'd1-rows:sync'").get().requests === ROWS_PER_DOC * 2,
     'the budget counts the rows of what was written, not of what was refused');

  const roomy = freshEnv();
  const many = Array.from({ length: 45 }, (_, i) => doc(`s${i}`));
  b = await body(await push(roomy, 'acc', { docs: many }));
  ok(b.accepted.length === 45 && !b.resting, 'with the default budget an ordinary batch goes through in its chunks');
}

// MARK: ceilings for all accounts together

{
  const env = freshEnv({ SUPPORT_DAILY_ALL: '2' });
  ok((await supportMessage(env, 'a1', { message: 'first message' })).status === 200, 'a support message is taken');
  ok((await supportMessage(env, 'a2', { message: 'second message' })).status === 200, 'and another account\'s');
  const third = await supportMessage(env, 'a3', { message: 'third message' });
  ok(third.status === 429 && (await body(third)).message.includes('kept'),
     'past the ceiling for everybody a message waits, and the app is told it is kept for tomorrow');
  ok(env.db.prepare('SELECT COUNT(*) AS n FROM support_messages').get().n === 2, 'and nothing past the ceiling is stored');
}
{
  const env = freshEnv({ ACCURACY_REPORTS_DAILY_ALL: '1' });
  const item = { id: 'c1', kind: 'card', text: 'Q: Antidote to warfarin?\nA: Vitamin K', source: '' };
  ok((await report(env, 'a1', { item })).status === 200, 'a question report is taken');
  ok((await report(env, 'a2', { item: { ...item, text: 'Q: Antidote to heparin?\nA: Protamine' } })).status === 429,
     'and past the ceiling for everybody the next waits');
}
{
  const env = freshEnv({ DIAGNOSTICS_DAILY_ALL: '2' });
  const device = { model: 'iPhone17,3', os: '26.0.1', idiom: 'phone', app: '1.2', build: '45', flavour: 'testflight', binary: 'RedPen' };
  const at = Math.floor(Date.now() / 1000);
  const failure = { kind: 'error', area: 'sync', at: at - 30, message: 'sync.failed', error: { domain: 'NSURLErrorDomain', code: -1001 }, count: 1 };
  let r = await diagnosticsRoute(env, 'a1', { device, events: [failure, { ...failure, message: 'sync.pull_failed' }] });
  ok(r.status === 200 && (await body(r)).accepted === 2, 'crash and failure reports are taken');
  r = await diagnosticsRoute(env, 'a2', { device, events: [failure] });
  ok(r.status === 429, 'and past the ceiling for everybody the next account\'s wait for tomorrow');
}

// MARK: the nightly prune

{
  const env = freshEnv();
  const at = 2_000_000_000;
  const old = at - (Math.max(SUPPORT_KEEP_DAYS, REPORTS_KEEP_DAYS) + 1) * 86400;
  const recent = at - 86400;
  const ins = (q, ...a) => env.db.prepare(q).run(...a);
  ins('INSERT INTO support_messages (account_id, topic, message, version, created_at) VALUES (?, ?, ?, ?, ?)', 'a', 'idea', 'old', '', old);
  ins('INSERT INTO support_messages (account_id, topic, message, version, created_at) VALUES (?, ?, ?, ?, ?)', 'a', 'idea', 'new', '', recent);
  ins('INSERT INTO accuracy_reports (hash, account_id, kind, item, note, created_at) VALUES (?, ?, ?, ?, ?, ?)', 'h1', 'a', 'card', '{}', '', old);
  ins('INSERT INTO accuracy_reports (hash, account_id, kind, item, note, created_at) VALUES (?, ?, ?, ?, ?, ?)', 'h2', 'a', 'card', '{}', '', recent);
  const day = s => new Date(s * 1000).toISOString().slice(0, 10);
  ins('INSERT INTO ai_usage (account_id, day, requests) VALUES (?, ?, ?)', 'a', day(at - 30 * 86400), 3);
  ins('INSERT INTO ai_usage (account_id, day, requests) VALUES (?, ?, ?)', 'a', day(at - 86400), 3);
  ins('INSERT INTO ai_usage (account_id, day, requests) VALUES (?, ?, ?)', 'gemini:billed', 'seen', 1);
  ins('INSERT INTO ai_usage (account_id, day, requests) VALUES (?, ?, ?)', 'month-kept', '2020-01', 1);
  ins('INSERT INTO pair_attempts (ip, hour, what, n) VALUES (?, ?, ?, ?)', 'old-ip', Math.floor(at / 3600) - 48, 'pair', 1);
  ins('INSERT INTO pair_attempts (ip, hour, what, n) VALUES (?, ?, ?, ?)', 'new-ip', Math.floor(at / 3600), 'pair', 1);
  ins('INSERT INTO accuracy_verdicts (hash, signals, created_at) VALUES (?, ?, ?)', 'v-old', '{}', at - 400 * 86400);
  ins('INSERT INTO accuracy_verdicts (hash, signals, created_at) VALUES (?, ?, ?)', 'v-new', '{}', at - 86400);
  ins('INSERT INTO released_tokens (token, provider, subject, released_at) VALUES (?, ?, ?, ?)', 't-old', 'apple', 's', at - 400 * 86400);
  ins('INSERT INTO released_tokens (token, provider, subject, released_at) VALUES (?, ?, ?, ?)', 't-new', 'apple', 's', at - 30 * 86400);
  ins('INSERT INTO used_nonces (nonce, used_at) VALUES (?, ?)', 'n-old', at - 2 * 86400);
  ins('INSERT INTO used_nonces (nonce, used_at) VALUES (?, ?)', 'n-new', at - 60);
  const removed = await pruneStores(env, () => at);
  const left = q => env.db.prepare(q).all().map(r => Object.values(r)[0]);
  ok(left('SELECT message FROM support_messages').join() === 'new', 'support messages past their time go, recent ones stay');
  ok(left('SELECT hash FROM accuracy_reports').join() === 'h2', 'question reports past their time go, recent ones stay');
  ok(left("SELECT day FROM ai_usage WHERE account_id = 'a'").join() === day(at - 86400), 'a daily counter from a month ago goes, yesterday\'s stays');
  ok(left("SELECT day FROM ai_usage WHERE account_id = 'gemini:billed'").join() === 'seen'
     && left("SELECT day FROM ai_usage WHERE account_id = 'month-kept'").join() === '2020-01',
     'rows kept under names that are not days are never touched');
  ok(removed.support === 1 && removed.reports === 1 && removed.counters === 1, 'and the prune says what it removed');
  ok(left('SELECT ip FROM pair_attempts').join() === 'new-ip', "pairing tries from days ago go, this hour's stay");
  ok(left('SELECT hash FROM accuracy_verdicts').join() === 'v-new', 'verdicts older than the cache period go');
  ok(left('SELECT token FROM released_tokens').join() === 't-new', "a deleted account's sign-in is kept a year, not for ever");
  ok(left('SELECT nonce FROM used_nonces').join() === 'n-new', 'used sign-in nonces go after a day');
}

// a table the deploy has not created yet does not stop the rest of the prune
{
  const env = freshEnv();
  env.db.exec('DROP TABLE used_nonces');
  const removed = await pruneStores(env, () => 2_000_000_000);
  ok(removed.nonces === 0 && removed.released === 0, 'a missing table is skipped and the others still pruned');
}

console.log(failures ? `\n${failures} LIMITS TEST FAILURE(S)` : '\nALL LIMITS TESTS PASS');
process.exit(failures ? 1 : 0);
