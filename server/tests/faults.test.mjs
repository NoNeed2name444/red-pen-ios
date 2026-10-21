// Fault injection (plan Task 5c step 4): every AI entry point the app calls,
// against providers that fail in each way a network can - a 500, a 429, a
// timeout, a reply that is not what was asked for, no network at all. Closed
// means an honest error the app can show or queue, never a throw, a hang or a
// 200 with nothing in it.
//
// Run: node server/tests/faults.test.mjs

import { DatabaseSync } from 'node:sqlite';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { chat, transcribeChunk } from '../ai.js';
import { speech } from '../tts.js';
import { evidenceFor } from '../accuracy.js';
import { jevOath } from '../jev.js';
import { resetBreakers } from '../breakers.js';

const here = dirname(fileURLToPath(import.meta.url));
let failures = 0;
const ok = (cond, what, detail = '') => { console.log((cond ? 'ok   ' : 'FAIL ') + what + (cond ? '' : `  | ${detail}`)); if (!cond) failures++; };

function d1(db) {
  return {
    prepare(sql) {
      const stmt = db.prepare(sql);
      let args = [];
      const api = {
        bind(...a) { args = a; return api; },
        first() { return stmt.get(...args) ?? null; },
        all() { return { results: stmt.all(...args) }; },
        run() { const r = stmt.run(...args); return { meta: { changes: Number(r.changes) } }; },
      };
      return api;
    },
    async batch(list) { return Promise.all(list.map(s => s.run())); },
  };
}

function env() {
  resetBreakers();
  const db = new DatabaseSync(':memory:');
  const sql = readFileSync(join(here, '..', 'schema.sql'), 'utf8').split('\n').map(l => l.replace(/--.*$/, '')).join('\n');
  for (const s of sql.split(';')) if (s.trim()) db.exec(s);
  db.prepare(`INSERT INTO accounts (id, provider, subject, created_at) VALUES ('a1', 'apple', 's1', 0)`).run();
  return { DB: d1(db), AI_API_KEY: 'k', FIREBASE_API_KEY: 'fk', FIREBASE_PROJECT_ID: 'p', OWNER_ACCOUNT_IDS: 'a1',
           GEMINI_TTS: 'on', JEV_URL: 'https://jev.example/v1', JEV_KEY: 'jk' };
}

// each fault, as a fetcher; a timeout is what AbortSignal.timeout delivers
const timeoutError = () => Object.assign(new Error('The operation was aborted due to timeout'), { name: 'TimeoutError' });
const FAULTS = {
  '500': async () => new Response('{"error":{"message":"internal"}}', { status: 500 }),
  '429': async () => new Response('{"error":{"message":"rate limit"}}', { status: 429, headers: { 'Retry-After': '30' } }),
  'timeout': async () => { throw timeoutError(); },
  'garbage': async () => new Response('<html>502 Bad Gateway</html>', { status: 200 }),
  'offline': async () => { throw new TypeError('fetch failed'); },
};

// a promise that has not settled in 40 s is a hang: a busy provider is
// waited for once, for at most 30 s (ai.js generate), never longer
const settle = (p) => {
  let timer;
  const limit = new Promise(r => { timer = setTimeout(() => r({ hang: true }), 40000); });
  return Promise.race([p.then(v => ({ v }), e => ({ e })), limit]).finally(() => clearTimeout(timer));
};

async function closed(name, fault, run) {
  const out = await settle(run());
  if (out.hang) return ok(false, `${name} / ${fault}: settles`, 'hung');
  if (out.e) return ok(false, `${name} / ${fault}: does not throw`, String(out.e));
  const r = out.v;
  let body = null;
  try { body = await r.clone().json(); } catch { /* checked below */ }
  ok(r.status >= 400 && body && typeof (body.message ?? body.error) === 'string',
     `${name} / ${fault}: an honest error (${r.status})`, `${r.status} ${JSON.stringify(body)?.slice(0, 120)}`);
}

const ask = { model: 'cramdown-writer', messages: [{ role: 'user', content: 'hi' }], max_tokens: 50 };
const audio = { audio: Buffer.from('not really audio but base64').toString('base64'), prompt: 'Transcribe.' };

for (const [fault, fetcher] of Object.entries(FAULTS)) {
  await closed('chat', fault, () => chat(env(), 'a1', ask, fetcher, { owner: true }));
  await closed('transcribe', fault, () => transcribeChunk(env(), 'a1', audio, fetcher, { owner: true }));
  await closed('speech', fault, () => speech(env(), 'a1', { text: 'Hello there.', speaker: 'lecturer' }, fetcher, { owner: true }));

  // evidence: a source that fails is simply no evidence, never a failed check
  const ev = await settle(evidenceFor({ kind: 'mcq', stem: 'Warfarin and aspirin in atrial fibrillation', answer: 'warfarin' }, fetcher));
  ok(!ev.hang && !ev.e && Array.isArray(ev.v) && ev.v.length === 0, `evidence / ${fault}: none, and no throw`, JSON.stringify(ev).slice(0, 120));

  // Jev: a failure is "no answer", which the check takes as Unverified
  const j = await settle(jevOath(env(), 'Some text to check.', fetcher));
  ok(!j.hang && !j.e, `jev / ${fault}: settles without a throw`, JSON.stringify(j).slice(0, 120));
}

console.log(failures ? `\n${failures} FAULT TEST FAILURE(S)` : '\nall fault tests pass');
process.exit(failures ? 1 : 0);
