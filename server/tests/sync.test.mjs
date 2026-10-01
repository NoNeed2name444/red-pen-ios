// The sync worker, run against a real SQLite - not a mock.
//
// A mock would happily accept the one statement in this file that actually
// matters: the conditional upsert that makes compare-and-set atomic. Its whole
// correctness lives in SQLite's own handling of `ON CONFLICT ... DO UPDATE ...
// WHERE`, and in whether a refused update reports zero changed rows. A hand
// written fake would just agree with whatever we believed when we wrote it.
//
// Run: node --experimental-sqlite server/tests/sync.test.mjs

import { DatabaseSync } from 'node:sqlite';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { changes, push, missingBlobs, putBlob, wipe } from '../sync.js';
import { sign, verify, decodeClaims } from '../tokens.js';

const here = dirname(fileURLToPath(import.meta.url));

let failures = 0;
const ok = (cond, what) => {
  console.log((cond ? 'ok   ' : 'FAIL ') + what);
  if (!cond) failures++;
};

// MARK: the smallest thing that behaves like D1

function d1(db) {
  return {
    prepare(sql) {
      const stmt = db.prepare(sql);
      let args = [];
      const api = {
        bind(...a) { args = a; return api; },
        first() { return stmt.get(...args) ?? null; },
        all() { return { results: stmt.all(...args) }; },
        run() {
          const r = stmt.run(...args);
          return { meta: { changes: Number(r.changes) } };
        },
        // what a batch runs: rows for a statement that returns them
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
    // D1's batch: one transaction, all or nothing
    async batch(statements) {
      db.exec('BEGIN');
      try {
        const out = statements.map(s => s.exec());
        db.exec('COMMIT');
        return out;
      } catch (error) { db.exec('ROLLBACK'); throw error; }
    },
  };
}

function blobStore() {
  const held = new Map();
  return {
    held,
    async head(k) { return held.has(k) ? { key: k } : null; },
    async put(k, v) { held.set(k, v); },
    async get(k) { return held.has(k) ? { body: held.get(k) } : null; },
    async list({ prefix }) {
      return {
        objects: [...held.keys()].filter(k => k.startsWith(prefix)).map(key => ({ key })),
        truncated: false,
      };
    },
    async delete(keys) { for (const k of keys) held.delete(k); },
  };
}

function freshEnv() {
  const db = new DatabaseSync(':memory:');
  const sql = readFileSync(join(here, '..', 'schema.sql'), 'utf8');
  // The schema carries the whole server, accounts and all; only the syncing
  // tables are needed here and the rest may reference things we have not made.
  for (const statement of sql.split(';')) {
    const trimmed = statement.trim();
    if (!trimmed) continue;
    try { db.exec(trimmed); } catch { /* not a table this test needs */ }
  }
  return { DB: d1(db), BLOBS: blobStore(), db };
}

const body = async res => JSON.parse(await res.text());
const doc = (id, rev, extra = {}) => ({
  id, kind: 'set', rev,
  updatedAt: new Date('2026-01-01T00:00:00Z').toISOString(),
  deleted: false, payload: 'aGk=', ...extra,
});

// MARK: the tables really exist

const env0 = freshEnv();
ok(env0.db.prepare("SELECT name FROM sqlite_master WHERE name='docs'").get() !== undefined,
   'the schema really creates the docs table');
ok(env0.db.prepare("SELECT name FROM sqlite_master WHERE name='sync_state'").get() !== undefined,
   'and the revision counter table');

// MARK: a first push, and reading it back

let env = freshEnv();
let res = await body(await push(env, 'acc', { docs: [doc('a', 0)] }));
ok(res.accepted.length === 1 && res.conflicts.length === 0, 'something new is accepted');
ok(res.accepted[0].rev === 1, 'and is given the first revision');

res = await body(await changes(env, 'acc', { since: 0 }));
ok(res.docs.length === 1 && res.docs[0].id === 'a', 'and comes back to a device asking from nothing');
ok(res.cursor === 1 && res.more === false, 'with a cursor and nothing more to fetch');

res = await body(await changes(env, 'acc', { since: 1 }));
ok(res.docs.length === 0 && res.cursor === 1, 'a device already up to date is told nothing changed');

// MARK: a payload that is not text is skipped, not a failed batch

{
  const e = freshEnv();
  const r = await body(await push(e, 'acc', { docs: [doc('odd', 0, { payload: { not: 'text' } }), doc('fine', 0)] }));
  ok(r.accepted.length === 1 && r.accepted[0].id === 'fine', 'an object payload is skipped and the rest of the batch still lands');
}

// MARK: one account cannot see another's

res = await body(await changes(env, 'someone-else', { since: 0 }));
ok(res.docs.length === 0, "another account sees none of it");

// MARK: compare-and-set

env = freshEnv();
await push(env, 'acc', { docs: [doc('a', 0)] });                 // rev 1
await push(env, 'acc', { docs: [doc('a', 1, { payload: 'dHdv' })] }); // rev 2

res = await body(await push(env, 'acc', { docs: [doc('a', 1, { payload: 'c3RhbGU=' })] }));
ok(res.accepted.length === 0 && res.conflicts.length === 1,
   'a push from a revision that has moved on is refused');
ok(res.conflicts[0].payload === 'dHdv', 'and the refusal carries what is actually there');

res = await body(await changes(env, 'acc', { since: 0 }));
ok(res.docs[0].payload === 'dHdv', 'so the stale copy never landed');

// MARK: the race the fast path alone cannot catch
//
// Two devices that both read revision 1 before either wrote. The pre-flight
// check passes for both; only the statement's own WHERE can refuse the second.

// Running two pushes side by side would prove nothing here: this file's
// database is synchronous, so the first would finish before the second began
// and the pre-flight check would catch it - the very check we are trying to do
// without. So the other device is made to write at the one instant that
// matters: after our SELECT has already returned, and before our INSERT runs.
env = freshEnv();
await push(env, 'acc', { docs: [doc('a', 0)] });                 // rev 1

const realPrepare = env.DB.prepare.bind(env.DB);
let interrupted = false;
const realBatch = env.DB.batch;
env.DB.prepare = sql => {
  const stmt = realPrepare(sql);
  if (!interrupted && sql.includes('id IN (')) {
    const all = stmt.all.bind(stmt);
    stmt.all = async () => {
      const rows = await all();
      interrupted = true;
      // The other device, arriving in the gap. It works from revision 1 too,
      // and it gets there first.
      await push({ ...env, DB: { prepare: realPrepare, batch: realBatch } }, 'acc',
                 { docs: [doc('a', 1, { payload: 'dGhlaXJz' })] });
      return rows;   // what WE read a moment ago - now out of date
    };
  }
  return stmt;
};

res = await body(await push(env, 'acc', { docs: [doc('a', 1, { payload: 'b3Vycw==' })] }));
env.DB.prepare = realPrepare;
ok(res.accepted.length === 0 && res.conflicts.length === 1,
   'a device that read before another device wrote is refused, not accepted');
ok(res.conflicts[0].payload === 'dGhlaXJz',
   'and is handed the version that actually won, to merge against');

res = await body(await changes(env, 'acc', { since: 0 }));
const latest = res.docs[res.docs.length - 1];
ok(latest.payload === 'dGhlaXJz',
   "so the winner's work is still there rather than quietly overwritten");

// MARK: one stale document does not spoil the batch

env = freshEnv();
await push(env, 'acc', { docs: [doc('a', 0)] });
await push(env, 'acc', { docs: [doc('a', 1, { payload: 'bmV3' })] });
res = await body(await push(env, 'acc', {
  docs: [doc('a', 1), doc('b', 0), doc('c', 0)],
}));
ok(res.accepted.length === 2 && res.conflicts.length === 1,
   'the good documents in a batch land even when one of them is stale');

// MARK: tombstones

env = freshEnv();
await push(env, 'acc', { docs: [doc('f', 0, { kind: 'folder' })] });
res = await body(await push(env, 'acc', {
  docs: [doc('f', 1, { kind: 'set', deleted: true })],
}));
ok(res.accepted[0].kind === 'folder',
   'a tombstone does not relabel a folder as a set');
ok(res.accepted[0].payload === null, 'and it drops the body of what was deleted');

// MARK: paging

env = freshEnv();
for (let i = 0; i < 5; i++) await push(env, 'acc', { docs: [doc('d' + i, 0)] });
res = await body(await changes(env, 'acc', { since: 0, limit: 2 }));
ok(res.docs.length === 2 && res.more === true, 'a big library comes back a page at a time');
ok(res.cursor === 2, 'and the cursor is the last one actually sent, not the last one looked at');
res = await body(await changes(env, 'acc', { since: res.cursor, limit: 2 }));
ok(res.docs.map(d => d.id).join() === 'd2,d3', 'the next page carries on where it stopped');

// MARK: pictures

env = freshEnv();
const name = 'a'.repeat(64);
env.BLOBS.held.set('acc/' + name, 'bytes');
res = await body(await missingBlobs(env, 'acc', { names: [name, 'b'.repeat(64), 'nonsense'] }));
ok(res.missing.length === 1 && res.missing[0] === 'b'.repeat(64),
   'only pictures the server lacks are asked for, and a bad name is ignored');
res = await body(await missingBlobs(env, 'other', { names: [name] }));
ok(res.missing.length === 1, "and one account's pictures do not count as another's");

// MARK: leaving

await push(env, 'acc', { docs: [doc('a', 0)] });
await wipe(env, 'acc');
res = await body(await changes(env, 'acc', { since: 0 }));
ok(res.docs.length === 0, 'deleting an account leaves no documents');
ok([...env.BLOBS.held.keys()].filter(k => k.startsWith('acc/')).length === 0,
   'and no pictures');

// MARK: a batch cannot be unbounded

env = freshEnv();
res = await body(await push(env, 'acc', {
  docs: Array.from({ length: 900 }, (_, i) => doc('x' + i, 0)),
}));
ok(res.accepted.length === 500, 'an implausibly large batch is capped rather than run');

// MARK: picture storage has a floor under it

env = freshEnv();
const small = new Uint8Array(1024).buffer;
const hashOf = async buf => {
  const d = await crypto.subtle.digest('SHA-256', buf);
  return [...new Uint8Array(d)].map(b => b.toString(16).padStart(2, '0')).join('');
};
const req = buf => ({ arrayBuffer: async () => buf });
// The store has to report sizes for a budget to mean anything.
env.BLOBS.put = async (k, v) => { env.BLOBS.held.set(k, v); };
env.BLOBS.list = async ({ prefix }) => ({
  objects: [...env.BLOBS.held.entries()]
    .filter(([k]) => k.startsWith(prefix))
    .map(([key, v]) => ({ key, size: v.byteLength })),
  truncated: false,
});

const n1 = await hashOf(small);
res = await body(await putBlob(env, 'acc', n1, req(small), 4096));
ok(res.ok === true, 'a picture within the budget is stored');

res = await body(await putBlob(env, 'acc', n1, req(small), 4096));
ok(res.ok === true, 'and sending the same one again is free, not counted twice');

const big = new Uint8Array(8192).buffer;
const n2 = await hashOf(big);
const tooMuch = await putBlob(env, 'acc', n2, req(big), 4096);
ok(tooMuch.status === 507, 'one that would go over the budget is refused');

const wrongName = await putBlob(env, 'acc', 'f'.repeat(64), req(big), Infinity);
ok(wrongName.status === 400, 'and a picture filed under a name that is not its hash is refused');

// MARK: the revision is taken in the same transaction as the write
//
// Taken separately, a device pulling between the two could see a later
// revision land first, move its cursor past this one, and never be sent it.
{
  const e = freshEnv();
  const loose = [];
  let batches = 0, calls = 0;
  const prepare = e.DB.prepare.bind(e.DB);
  e.DB.prepare = sql => {
    const stmt = prepare(sql);
    for (const f of ['first', 'all', 'run']) {
      const real = stmt[f].bind(stmt);
      stmt[f] = (...a) => { calls++; if (sql.includes('sync_state')) loose.push(sql); return real(...a); };
    }
    return stmt;
  };
  const batch = e.DB.batch.bind(e.DB);
  e.DB.batch = async st => { batches++; calls++; return batch(st); };
  const r = await body(await push(e, 'acc', { docs: Array.from({ length: 45 }, (_, i) => doc('r' + i, 0)) }));
  ok(r.accepted.length === 45 && new Set(r.accepted.map(d => d.rev)).size === 45, 'every document gets its own revision');
  ok(loose.length === 0 && batches === 3, 'and takes it inside the transaction that writes it, twenty documents a call');
  calls = 0;
  await push(e, 'acc', { docs: Array.from({ length: 500 }, (_, i) => doc('big' + i, 0)) });
  ok(calls < 60, `a batch of 500 is a few dozen database calls (${calls}), far inside a Worker's thousand`);
  const feed = await body(await changes(e, 'acc', { since: 0, limit: 500 }));
  ok(feed.docs.length === 500 && feed.more, 'and every one of them is in the changes feed');
}

// MARK: one account cannot fill the database everyone shares

{
  const e = { ...freshEnv(), DOC_BYTES_PER_ACCOUNT: '20' };
  let r = await body(await push(e, 'acc', { docs: [doc('q1', 0, { payload: 'x'.repeat(12) })] }));
  ok(r.accepted.length === 1, 'a document within the account\'s share is kept');
  const refused = await push(e, 'acc', { docs: [doc('q2', 0, { payload: 'y'.repeat(12) })] });
  ok(refused.status === 507, 'one that would take it past its share is refused (507)');
  r = await body(await push(e, 'acc', { docs: [doc('q1', 1, { deleted: true })] }));
  ok(r.accepted.length === 1, 'but deleting still works on a full library');
  r = await body(await push(e, 'acc', { docs: [doc('q2', 0, { payload: 'y'.repeat(12) })] }));
  ok(r.accepted.length === 1, 'and frees the room it took');
  const row = e.db.prepare("SELECT bytes, docs FROM doc_usage WHERE account_id = 'acc'").get();
  ok(row.bytes === 12 && row.docs === 2, 'the running total follows every write, tombstones included');
  await wipe(e, 'acc');
  ok(!e.db.prepare("SELECT * FROM doc_usage WHERE account_id = 'acc'").get(), 'and goes with the account');

  // the whole database nearly full: nothing may grow, for anyone
  const f = freshEnv();
  const batch = f.DB.batch.bind(f.DB);
  f.DB.batch = async st => (await batch(st)).map(x => ({ ...x, meta: { ...x.meta, size_after: 450_000_000 } }));
  const r2 = await body(await push(f, 'acc', { docs: Array.from({ length: 30 }, (_, i) => doc('g' + i, 0)) }));
  ok(r2.accepted.length === 20, 'once the database is nearly full, writes that grow it stop');
}

// MARK: a page of changes is cut by size too

{
  const e = { ...freshEnv(), SYNC_PAGE_BYTES: '10' };
  for (let i = 0; i < 3; i++) await push(e, 'acc', { docs: [doc('p' + i, 0, { payload: 'z'.repeat(8) })] });
  let r = await body(await changes(e, 'acc', { since: 0, limit: 200 }));
  ok(r.docs.length === 1 && r.more && r.cursor === 1, 'large documents come a page at a time by size');
  r = await body(await changes(e, 'acc', { since: r.cursor, limit: 200 }));
  ok(r.docs.length === 1 && r.docs[0].id === 'p1', 'and the next page carries on from the last one sent');
  const huge = { ...freshEnv(), SYNC_PAGE_BYTES: '1' };
  await push(huge, 'acc', { docs: [doc('h', 0, { payload: 'z'.repeat(50) })] });
  ok((await body(await changes(huge, 'acc', { since: 0 }))).docs.length === 1, 'one document bigger than a page still goes, on its own');
}

// MARK: past the names checked in one call, pictures are reported missing

{
  const e = freshEnv();
  let heads = 0;
  const head = e.BLOBS.head.bind(e.BLOBS);
  e.BLOBS.head = async k => { heads++; return head(k); };
  const names = Array.from({ length: 600 }, (_, i) => i.toString(16).padStart(64, '0'));
  names.forEach(n => e.BLOBS.held.set('acc/' + n, 'x'));
  const r = await body(await missingBlobs(e, 'acc', { names }));
  ok(heads === 500 && r.missing.length === 100 && r.missing[0] === names[500],
     'names past the 500 checked come back missing, never quietly present');
  const capped = { ...freshEnv(), BLOB_CHECKS_DAILY: '600' };
  await missingBlobs(capped, 'acc', { names: names.slice(0, 500) });
  ok((await missingBlobs(capped, 'acc', { names: names.slice(0, 500) })).status === 429, 'and each account checks only so many a day');
}

// MARK: uploads arriving together cannot all pass the storage check

{
  const e = freshEnv();
  let lists = 0;
  e.BLOBS.list = async ({ prefix }) => {
    lists++;
    return { objects: [...e.BLOBS.held.entries()].filter(([k]) => k.startsWith(prefix)).map(([key, v]) => ({ key, size: v.byteLength })), truncated: false };
  };
  const hash = async buf => [...new Uint8Array(await crypto.subtle.digest('SHA-256', buf))].map(b => b.toString(16).padStart(2, '0')).join('');
  const bufs = Array.from({ length: 6 }, (_, i) => new Uint8Array(1024).fill(i + 1).buffer);
  const results = await Promise.all(bufs.map(async b => (await putBlob(e, 'acc', await hash(b), { arrayBuffer: async () => b }, 4096)).status));
  ok(results.filter(x => x === 200).length === 4 && e.BLOBS.held.size === 4, 'six at once against room for four: four are stored');
  lists = 0;
  for (const b of bufs) await putBlob(e, 'acc2', await hash(b), { arrayBuffer: async () => b }, 1 << 20);
  ok(lists === 1, 'and R2 is listed once to start the count, not on every upload');
  const failing = freshEnv();
  failing.BLOBS.put = async () => { throw new Error('R2 down'); };
  const one = new Uint8Array(100).buffer;
  try { await putBlob(failing, 'acc', await hash(one), { arrayBuffer: async () => one }, 4096); } catch {}
  ok(failing.db.prepare("SELECT bytes FROM blob_usage WHERE account_id = 'acc'").get().bytes === 0, 'an upload that fails gives its room back');
  e.BLOBS.held.set('tts/acc/x.mp3', 'audio');
  await wipe(e, 'acc');
  ok(![...e.BLOBS.held.keys()].some(k => k.startsWith('acc/') || k.startsWith('tts/acc/')) && e.BLOBS.held.size === 6 && !e.db.prepare("SELECT * FROM blob_usage WHERE account_id = 'acc'").get(),
     'deleting the account takes its pictures, its read-aloud lines and its count');
}

// MARK: tokens
//
// The session token is the only thing standing between one student's library
// and anybody else, so the ways it can be malformed matter as much as the way
// it is signed.

const secret = 'test-secret';
const good = await sign({ sub: 'acc', typ: 'access' }, secret, 60);
ok((await verify(good, secret))?.sub === 'acc', 'a token we signed verifies');
ok(await verify(good, 'other-secret') === null, 'and does not under a different secret');

const [h, p] = good.split('.');
ok(await verify(`${h}.${p}.`, secret) === null, 'a token with its signature removed is refused');
ok(await verify(`${h}.${p}.!!!not base64!!!`, secret) === null,
   'and one whose signature is not even base64 is refused, not an error');
ok(await verify('rubbish', secret) === null, 'as is something that is not a token at all');
ok(await verify('', secret) === null, 'and nothing at all');

const expired = await sign({ sub: 'acc', typ: 'access' }, secret, -60);
ok(await verify(expired, secret) === null, 'an expired token is refused');

// A token with no expiry at all, correctly signed. The naive check is
// `claims.exp * 1000 < Date.now()`, which on a missing exp is NaN < now -
// false - and the token lives for ever.
const b64 = o => Buffer.from(JSON.stringify(o)).toString('base64url');
const forever = await (async () => {
  const head = b64({ alg: 'HS256', typ: 'JWT' });
  const payload = b64({ sub: 'acc', typ: 'access' });   // no exp
  const key = await crypto.subtle.importKey('raw', new TextEncoder().encode(secret),
    { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  const sig = await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(`${head}.${payload}`));
  return `${head}.${payload}.${Buffer.from(sig).toString('base64url')}`;
})();
ok(decodeClaims(forever)?.sub === 'acc', 'the never-expiring token really is well formed');
ok(await verify(forever, secret) === null, 'but a token with no expiry is refused, not honoured for ever');

console.log(failures === 0 ? '\nALL SERVER TESTS PASS' : `\n${failures} FAILED`);
process.exit(failures === 0 ? 0 : 1);
