// Linking a second device by code: works once, expires, and cannot be guessed.
//
// Run: node server/tests/pair.test.mjs
import { DatabaseSync } from 'node:sqlite';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { startPairing, finishPairing, allowed, normalise, WRONG_PER_HOUR } from '../pair.js';

const here = dirname(fileURLToPath(import.meta.url));
let failures = 0;
const ok = (cond, what) => { console.log((cond ? 'ok   ' : 'FAIL ') + what); if (!cond) failures++; };
const db = new DatabaseSync(':memory:');
const sql = readFileSync(join(here, '..', 'schema.sql'), 'utf8').split('\n').map(l => l.replace(/--.*$/, '')).join('\n');
for (const s of sql.split(';')) if (s.trim()) db.exec(s);
const env = { DB: { prepare(q) { const st = db.prepare(q); let a = []; const api = {
  bind(...x) { a = x; return api; }, first() { return st.get(...a) ?? null; },
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

console.log(failures ? `\n${failures} failed` : '\nall passed');
process.exit(failures ? 1 : 0);
