// Linking a second device by code: works once, expires, and cannot be guessed.
//
// Run: node server/tests/pair.test.mjs
import { DatabaseSync } from 'node:sqlite';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import worker from '../worker.js';
import { sign } from '../tokens.js';
import { startPairing, finishPairing, allowed, normalise, WRONG_PER_HOUR } from '../pair.js';

const here = dirname(fileURLToPath(import.meta.url));
let failures = 0;
const ok = (cond, what) => { console.log((cond ? 'ok   ' : 'FAIL ') + what); if (!cond) failures++; };
const db = new DatabaseSync(':memory:');
const sql = readFileSync(join(here, '..', 'schema.sql'), 'utf8').split('\n').map(l => l.replace(/--.*$/, '')).join('\n');
for (const s of sql.split(';')) if (s.trim()) db.exec(s);
const env = { DB: { prepare(q) { const st = db.prepare(q); let a = []; const api = {
  bind(...x) { a = x; return api; }, first() { return st.get(...a) ?? null; },
  all() { return { results: st.all(...a) }; },
  run() { return { meta: { changes: Number(st.run(...a).changes) } }; } }; return api; } } };

const { code } = await startPairing(env, 'acct');
ok(/^[A-Z2-9]{8}$/.test(code), 'a code is 8 readable characters');
ok(normalise(code.toLowerCase().slice(0, 4) + '-' + code.slice(4)) === code, 'typed in lower case with a dash still works');
const first = await finishPairing(env, 'ip1', code);
ok(first.accountId === 'acct', 'the right code joins the account');
ok((await finishPairing(env, 'ip1', code)).status === 404, 'a code works once');

const { code: second } = await startPairing(env, 'acct');
const { code: third } = await startPairing(env, 'acct');
ok((await finishPairing(env, 'ip2', second)).status === 404, 'a new code replaces the old one');
db.prepare('UPDATE pair_codes SET expires_at = 0').run();
ok((await finishPairing(env, 'ip2', third)).status === 404, 'an expired code is refused');

let last;
for (let i = 0; i < WRONG_PER_HOUR + 1; i++) last = await finishPairing(env, 'ip3', 'AAAAAAAA');
ok(last.status === 429, 'guessing is cut off after the hour\'s tries');
const { code: fresh } = await startPairing(env, 'acct');
ok((await finishPairing(env, 'ip3', fresh)).status === 429, 'even a right code waits once an address is cut off');
ok(await allowed(env, 'ip4', 'device', 1) && !await allowed(env, 'ip4', 'device', 1), 'new device accounts are limited per address');

// sync is part of Pro: refused for an account without it, open to one with it
{
  db.prepare(`INSERT INTO accounts (id, provider, subject, created_at) VALUES ('free', 'device', 'f', 0), ('paid', 'device', 'p', 0)`).run();
  const wenv = { ...env, SESSION_SECRET: 'secret', OWNER_ACCOUNT_IDS: 'paid' };
  const ask = async (who, path) => worker.fetch(new Request('https://w' + path, {
    method: 'POST', headers: { authorization: 'Bearer ' + await sign({ sub: who, typ: 'access', iat: Math.floor(Date.now() / 1000) }, 'secret', 600), 'content-length': '2' },
    body: '{}' }), wenv);
  ok((await ask('free', '/sync/changes')).status === 402, 'sync is refused without Pro');
  ok((await ask('free', '/pair/start')).status === 402, 'a pairing code needs Pro');
  ok((await ask('paid', '/sync/changes')).status === 200, 'sync works with Pro');
}

// the owner's claim works once, and only for the claim itself
{
  const claim = 'c'.repeat(40);
  const hash = [...new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(claim)))].map(b => b.toString(16).padStart(2, '0')).join('');
  db.prepare('INSERT INTO owner_claims (hash) VALUES (?)').run(hash);
  const wenv = { ...env, SESSION_SECRET: 'secret' };
  const make = async body => (await worker.fetch(new Request('https://w/auth/device', {
    method: 'POST', headers: { 'content-length': '50', 'cf-connecting-ip': 'ip9' }, body: JSON.stringify(body) }), wenv)).json();
  const wrong = await make({ claim: 'd'.repeat(40) });
  const first = await make({ claim });
  const again = await make({ claim });
  const owner = id => db.prepare('SELECT owner FROM accounts WHERE id = ?').get(id)?.owner;
  ok(owner(first.userId) === 1, 'the claim makes the owner\'s account');
  ok(owner(wrong.userId) === 0, 'a wrong claim makes an ordinary account');
  ok(again.userId === first.userId && again.token, 'presented again (a lost answer, a sign-out) it opens the same owner account, not an ordinary one');

  // the owner deleted that account: the claim makes a new one, the owner's
  db.prepare('DELETE FROM accounts WHERE id = ?').run(first.userId);
  const fresh = await make({ claim });
  ok(fresh.userId !== first.userId && owner(fresh.userId) === 1, 'after the owner account is deleted, the claim makes a new owner account');

  // a claim redeemed before the account was recorded: the one owner account is adopted
  const claim2 = 'e'.repeat(40);
  const hash2 = [...new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(claim2)))].map(b => b.toString(16).padStart(2, '0')).join('');
  db.prepare('UPDATE accounts SET owner = 0').run();
  db.prepare(`INSERT INTO accounts (id, provider, subject, created_at, owner) VALUES ('old-owner', 'device', 'o', 0, 1)`).run();
  db.prepare('INSERT INTO owner_claims (hash, used) VALUES (?, 1)').run(hash2);
  ok((await make({ claim: claim2 })).userId === 'old-owner', 'a claim used before this change finds its owner account again');
}

// deleting an account: gone first, then everything it had, and again at night
{
  const wenv = { ...env, SESSION_SECRET: 'secret' };
  const wiped = [];
  wenv.JOBS = { idFromName: id => id, get: id => ({ fetch: async req => { wiped.push([id, new URL(req.url).pathname]); return new Response('{}'); } }) };
  db.prepare(`INSERT INTO accounts (id, provider, subject, created_at) VALUES ('leaver', 'apple', 'apple-sub', 0)`).run();
  db.prepare(`INSERT INTO docs (account_id, id, kind, rev, updated_at, payload) VALUES ('leaver', 'd1', 'set', 1, 0, 'x')`).run();
  const token = await sign({ sub: 'leaver', typ: 'access', iat: Math.floor(Date.now() / 1000) }, 'secret', 600);
  const call = path => worker.fetch(new Request('https://w' + path, { method: 'POST', headers: { authorization: 'Bearer ' + token, 'content-length': '2' }, body: '{}' }), wenv);
  await startPairing(env, 'leaver');
  ok((await call('/account/delete')).status === 200, 'an account can be deleted');
  ok(!db.prepare(`SELECT * FROM accounts WHERE id = 'leaver'`).get() && !db.prepare(`SELECT * FROM docs WHERE account_id = 'leaver'`).get(),
     'the account and its library are gone');
  ok(wiped.some(([id, path]) => id === 'leaver' && path === '/wipe'), 'and so are its background jobs and their outputs');
  ok(!db.prepare(`SELECT * FROM pair_codes WHERE account_id = 'leaver'`).get(), 'and any pairing code it had');
  ok((await call('/sync/changes')).status === 401, 'its tokens no longer work anywhere');
  const released = db.prepare('SELECT provider, subject FROM released_tokens').get();
  ok(released?.provider === 'apple' && released.subject === 'apple-sub', 'its purchase tag is released to the same Apple sign-in');

  // a push that was already under way lands afterwards; the nightly pass removes it
  db.prepare(`INSERT INTO docs (account_id, id, kind, rev, updated_at, payload) VALUES ('leaver', 'late', 'set', 2, 0, 'x')`).run();
  const { sweepDeleted } = await import('../worker.js');
  const later = () => Math.floor(Date.now() / 1000) + 3600;
  await sweepDeleted(wenv, later);
  ok(!db.prepare(`SELECT * FROM docs WHERE account_id = 'leaver'`).get(), 'a late write is removed by the nightly pass');
  ok(db.prepare(`SELECT passes FROM deleted_accounts WHERE id = 'leaver'`).get()?.passes === 1, 'which comes back once more');
  await sweepDeleted(wenv, later);
  ok(!db.prepare(`SELECT * FROM deleted_accounts WHERE id = 'leaver'`).get(), 'and then forgets the account ever existed');
}

// signing out everywhere also ends any pairing code on a screen
{
  const wenv = { ...env, SESSION_SECRET: 'secret' };
  db.prepare(`INSERT INTO accounts (id, provider, subject, created_at) VALUES ('outer', 'apple', 'o2', 0)`).run();
  const { code } = await startPairing(env, 'outer');
  const token = await sign({ sub: 'outer', typ: 'access', iat: Math.floor(Date.now() / 1000) }, 'secret', 600);
  await worker.fetch(new Request('https://w/account/signout', { method: 'POST', headers: { authorization: 'Bearer ' + token, 'content-length': '2' }, body: '{}' }), wenv);
  ok((await finishPairing(env, 'ip20', code)).status === 404, 'signing out everywhere cancels a pairing code too');
}

// asking Apple about a subscription is limited per account
{
  const wenv = { ...env, SESSION_SECRET: 'secret' };
  db.prepare(`INSERT INTO accounts (id, provider, subject, created_at) VALUES ('asker', 'apple', 'o3', 0)`).run();
  const token = await sign({ sub: 'asker', typ: 'access', iat: Math.floor(Date.now() / 1000) }, 'secret', 600);
  const body = JSON.stringify({ originalTransactionId: '123' });
  let last;
  for (let i = 0; i < 31; i++) {
    last = await worker.fetch(new Request('https://w/account/subscription', { method: 'POST',
      headers: { authorization: 'Bearer ' + token, 'content-length': String(body.length), 'cf-connecting-ip': 'ip30' }, body }), wenv);
  }
  ok(last.status === 429, 'a loop of subscription checks is cut off, so it cannot use up Apple\'s limit for everyone');
}

console.log(failures ? `\n${failures} failed` : '\nall passed');
process.exit(failures ? 1 : 0);
