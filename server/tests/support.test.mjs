// "Contact us": a signed-in message is kept, limited per day, readable only
// with the owner key, and gone with the account.
//
// Run: node server/tests/support.test.mjs
import { DatabaseSync } from 'node:sqlite';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import worker from '../worker.js';
import { sign } from '../tokens.js';
import { supportMessage, forgetSupport, DAILY } from '../support.js';

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

const sent = await supportMessage(env, 'acct', { topic: 'idea', message: '  Dark mode for the dock please ', version: '1.2' });
ok(sent.status === 200, 'a message is taken');
const row = db.prepare('SELECT * FROM support_messages').get();
ok(row.topic === 'idea' && row.message === 'Dark mode for the dock please' && row.version === '1.2', 'kept trimmed, with its topic and version');
ok((await supportMessage(env, 'acct', { message: 'hi' })).status === 400, 'two letters is not a message');
await supportMessage(env, 'acct', { topic: 'nonsense', message: 'odd topic here' });
ok(db.prepare("SELECT topic FROM support_messages ORDER BY id DESC").get().topic === 'other', 'an unknown topic is filed as other');
const long = await supportMessage(env, 'acct2', { message: 'x'.repeat(10_000) });
ok(long.status === 200 && db.prepare("SELECT length(message) AS n FROM support_messages WHERE account_id = 'acct2'").get().n === 4000, 'a long message is cut, not refused');
let last;
for (let i = 0; i < DAILY + 1; i++) last = await supportMessage(env, 'spammer', { message: 'again and again' });
ok(last.status === 429, 'only a few a day');

// through the worker: signed in only; the list needs the owner key
{
  const wenv = { ...env, SESSION_SECRET: 'secret' };
  db.prepare(`INSERT INTO accounts (id, provider, subject, created_at) VALUES ('w1', 'device', 'w', 0)`).run();
  const post = async (path, headers, body) => worker.fetch(new Request('https://w' + path, {
    method: 'POST', headers: { 'content-length': String(body.length), ...headers }, body }), wenv);
  const token = await sign({ sub: 'w1', typ: 'access', iat: Math.floor(Date.now() / 1000) }, 'secret', 600);
  const body = JSON.stringify({ topic: 'problem', message: 'The timer froze' });
  ok((await post('/support/message', {}, body)).status === 401, 'signed out is refused');
  ok((await post('/support/message', { authorization: 'Bearer ' + token }, body)).status === 200, 'signed in is taken');
  ok((await post('/support/messages', { authorization: 'Bearer ' + token }, '{}')).status === 404, 'the list is not for students');
}

await forgetSupport(env, 'acct');
ok(db.prepare("SELECT COUNT(*) AS n FROM support_messages WHERE account_id = 'acct'").get().n === 0, 'gone with the account');

if (failures) { console.log(`${failures} FAILED`); process.exit(1); }
console.log('ALL SUPPORT TESTS PASS');
