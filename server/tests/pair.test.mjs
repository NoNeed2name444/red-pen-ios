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
  const owner = id => db.prepare('SELECT owner FROM accounts WHERE id = ?').get(id).owner;
  ok(owner(first.userId) === 1, 'the claim makes the owner\'s account');
  ok(owner(wrong.userId) === 0 && owner(again.userId) === 0, 'a wrong or reused claim makes an ordinary account');
}

console.log(failures ? `\n${failures} failed` : '\nall passed');
process.exit(failures ? 1 : 0);
