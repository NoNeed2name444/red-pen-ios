// The natural voice, against a real SQLite, a fake Workers AI and a fake R2.
//
// What matters: only Pro gets through, a line is never paid for twice, the
// free Aura-2 allowance holds, MeloTTS takes over when it is spent, and the
// phone is told to use its own voice when nothing answers.
//
// Run: node server/tests/tts.test.mjs

import { DatabaseSync } from 'node:sqlite';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { speech, voiceFor, tidy, audioBytes, AURA, MELO, MAX_TTS_CHARS } from '../tts.js';

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
        run() { const r = stmt.run(...args); return { meta: { changes: Number(r.changes) } }; },
      };
      return api;
    },
  };
}

/// A pretend MP3: big enough to count as speech.
const mp3 = tag => new TextEncoder().encode(tag.padEnd(2000, '.'));

function fakeAI({ auraFails = false, meloFails = false } = {}) {
  const calls = [];
  return {
    calls,
    async run(model, input) {
      calls.push({ model, input });
      if (model === AURA) {
        if (auraFails) throw new Error('3036: daily free allocation used');
        // Aura-2 answers with a stream, as the binding does
        return new Response(mp3(`aura:${input.speaker}`)).body;
      }
      if (model === MELO) {
        if (meloFails) throw new Error('3036: daily free allocation used');
        return { audio: Buffer.from(mp3('melo')).toString('base64') };
      }
      throw new Error('unknown model');
    },
  };
}

function fakeR2() {
  const store = new Map();
  return {
    store,
    async get(key) { return store.has(key) ? { arrayBuffer: async () => store.get(key).buffer } : null; },
    async put(key, bytes) { store.set(key, new Uint8Array(bytes)); },
  };
}

function freshEnv(extra = {}) {
  const db = new DatabaseSync(':memory:');
  const sql = readFileSync(join(here, '..', 'schema.sql'), 'utf8')
    .split('\n').map(line => line.replace(/--.*$/, '')).join('\n');
  for (const statement of sql.split(';')) if (statement.trim()) db.exec(statement);
  db.prepare(`INSERT INTO accounts (id, provider, subject, created_at) VALUES ('a1', 'apple', 's1', 0)`).run();
  db.prepare(`INSERT INTO accounts (id, provider, subject, created_at) VALUES ('pro', 'apple', 's2', 0)`).run();
  return { DB: d1(db), db, AI: fakeAI(), BLOBS: fakeR2(), OWNER_ACCOUNT_IDS: 'pro', ...extra };
}
const noApple = async () => new Response('{}', { status: 404 });
const said = async r => new TextDecoder().decode(await r.arrayBuffer());

// not Pro: refused before any model is asked
{
  const env = freshEnv();
  const r = await speech(env, 'a1', { text: 'Hello there.' }, noApple);
  ok(r.status === 402, 'an account without Pro is refused (402)');
  ok(env.AI.calls.length === 0, 'no model is called for it');
}

// Pro: Aura-2, the narrator's voice, MP3 back, and cached
{
  const env = freshEnv();
  const r = await speech(env, 'pro', { text: '  Good   morning. ', voice: 'narrator' }, noApple);
  ok(r.status === 200 && r.headers.get('content-type') === 'audio/mpeg', 'Pro gets audio/mpeg');
  ok(r.headers.get('x-voice-model') === 'aura-2' && r.headers.get('x-voice-cache') === 'miss', 'from Aura-2, not cached yet');
  ok((await said(r)).startsWith('aura:pandora'), 'the narrator is Pandora');
  const sent = env.AI.calls[0];
  ok(sent.model === AURA && sent.input.text === 'Good morning.' && sent.input.encoding === 'mp3', 'Aura-2 is sent the tidied text, asking for MP3');
  ok(env.BLOBS.store.size === 1, 'the line is kept in R2');

  const again = await speech(env, 'pro', { text: 'Good morning.', voice: 'narrator' }, noApple);
  ok(again.headers.get('x-voice-cache') === 'hit' && env.AI.calls.length === 1, 'the same line again comes from R2, not the model');

  const patient = await speech(env, 'pro', { text: 'Good morning.', voice: 'patient' }, noApple);
  ok((await said(patient)).startsWith('aura:draco'), 'the patient is Draco, a different voice');
  ok(env.AI.calls.length === 2, 'a different voice is a different cached line');
}

// input checks
{
  const env = freshEnv();
  ok((await speech(env, 'pro', { text: '   ' }, noApple)).status === 400, 'empty text is refused');
  const long = 'a'.repeat(MAX_TTS_CHARS + 1);
  ok((await speech(env, 'pro', { text: long }, noApple)).status === 413, `more than ${MAX_TTS_CHARS} characters is refused`);
  ok(env.AI.calls.length === 0, 'neither reaches the model');
}

// the free Aura-2 allowance, then MeloTTS
{
  const env = freshEnv({ TTS_FREE_DAILY_CHARS: '30' });
  const first = await speech(env, 'pro', { text: 'Twenty characters!!!' }, noApple);
  ok(first.headers.get('x-voice-model') === 'aura-2', 'within the free characters: Aura-2');
  const second = await speech(env, 'pro', { text: 'Another twenty chars' }, noApple);
  ok(second.headers.get('x-voice-model') === 'melotts', 'past them: MeloTTS');
  ok((await said(second)).startsWith('melo'), "MeloTTS's base64 answer is decoded to bytes");
  ok(env.AI.calls.at(-1).input.prompt === 'Another twenty chars', 'MeloTTS is sent the text as its prompt');
  const cachedFirst = await speech(env, 'pro', { text: 'Twenty characters!!!' }, noApple);
  ok(cachedFirst.headers.get('x-voice-model') === 'aura-2', 'a line already made with Aura-2 still comes back in Aura-2');
}

// once Pro pays, Aura-2 carries on out of the budget, and is counted
{
  const env = freshEnv({ TTS_FREE_DAILY_CHARS: '0', PRO_PAYS: 'on', PRO_MONTHLY_BUDGET_USD: '1', PRO_NET_MONTHLY_USD: '5' });
  env.db.prepare(`UPDATE accounts SET verified_until = 9999999999, checked_at = 9999999999 WHERE id = 'pro'`).run();
  const r = await speech(env, 'pro', { text: 'x'.repeat(1000) }, noApple);
  ok(r.headers.get('x-voice-model') === 'aura-2', 'with PRO_PAYS on, past the free characters: still Aura-2');
  const row = env.db.prepare(`SELECT micro_usd FROM ai_cost WHERE account_id = 'pro'`).get();
  ok(row?.micro_usd === 30000, '1,000 characters are counted as $0.03');
}

// Aura-2 down: MeloTTS; everything down: 503 so the phone reads it itself
{
  const env = freshEnv({ AI: fakeAI({ auraFails: true }) });
  const r = await speech(env, 'pro', { text: 'Hello.' }, noApple);
  ok(r.status === 200 && r.headers.get('x-voice-model') === 'melotts', 'Aura-2 failing falls back to MeloTTS');
  const env2 = freshEnv({ AI: fakeAI({ auraFails: true, meloFails: true }) });
  const r2 = await speech(env2, 'pro', { text: 'Hello.' }, noApple);
  ok(r2.status === 503, 'nothing answering is 503');
  const env3 = freshEnv({ AI: undefined });
  ok((await speech(env3, 'pro', { text: 'Hello.' }, noApple)).status === 503, 'no Workers AI binding is 503');
}

// without R2 it still works, just uncached
{
  const env = freshEnv({ BLOBS: undefined });
  const r = await speech(env, 'pro', { text: 'Hello.' }, noApple);
  ok(r.status === 200, 'no R2 bucket: audio still comes back');
}

// the daily cap per account
{
  const env = freshEnv({ TTS_DAILY_LIMIT: '2' });
  await speech(env, 'pro', { text: 'One.' }, noApple);
  await speech(env, 'pro', { text: 'Two.' }, noApple);
  const third = await speech(env, 'pro', { text: 'Three.' }, noApple);
  ok(third.status === 429, 'past TTS_DAILY_LIMIT lines a day: 429');
}

// the owner key: no Pro check, own allowance
{
  const env = freshEnv();
  const r = await speech(env, 'owner', { text: 'Owner line.' }, noApple, { owner: true });
  ok(r.status === 200, 'the owner key gets audio');
}

// the cache is each account's own: it cannot tell anyone what someone else had read
{
  const env = freshEnv({ OWNER_ACCOUNT_IDS: 'pro,pro2' });
  env.db.prepare(`INSERT INTO accounts (id, provider, subject, created_at) VALUES ('pro2', 'apple', 's3', 0)`).run();
  await speech(env, 'pro', { text: 'A private note.' }, noApple);
  const other = await speech(env, 'pro2', { text: 'A private note.' }, noApple);
  ok(other.headers.get('x-voice-cache') === 'miss' && env.AI.calls.length === 2, "another account's line is not a hit");
  ok([...env.BLOBS.store.keys()].every(k => /^tts\/pro2?\/[0-9a-f]{64}\.mp3$/.test(k)), 'lines are kept under the account they were made for');
}

// a line from the cache costs nothing, so it is not counted against the day
{
  const env = freshEnv({ TTS_DAILY_LIMIT: '1' });
  const statuses = [];
  for (let i = 0; i < 3; i++) statuses.push((await speech(env, 'pro', { text: 'Same line.' }, noApple)).status);
  ok(statuses.join() === '200,200,200', 'a cached line again and again stays within a one-line day');
}

// Aura-2 failing gives its free characters back
{
  const env = freshEnv({ AI: fakeAI({ auraFails: true }), TTS_FREE_DAILY_CHARS: '10' });
  await speech(env, 'pro', { text: 'Hello.' }, noApple);
  const row = env.db.prepare(`SELECT requests FROM ai_usage WHERE account_id = 'tts-chars:all'`).get();
  ok(row.requests === 0, 'a line Aura-2 never made does not use up the day\'s free characters');
}

// one account's share of the free neurons, not everyone's
{
  const env = freshEnv({ OWNER_ACCOUNT_IDS: 'pro,pro2', WORKERS_AI_NEURONS_PER_ACCOUNT: '30' });
  env.db.prepare(`INSERT INTO accounts (id, provider, subject, created_at) VALUES ('pro2', 'apple', 's3', 0)`).run();
  const first = await speech(env, 'pro', { text: 'Ten chars.' }, noApple);
  ok(first.headers.get('x-voice-model') === 'aura-2', 'within its share: Aura-2');
  const second = await speech(env, 'pro', { text: 'Ten again.' }, noApple);
  ok(second.headers.get('x-voice-model') === 'melotts', 'past its share of Aura-2: MeloTTS, which costs far less');
  for (let i = 0; i < 3; i++) await speech(env, 'pro', { text: 'Line ' + i }, noApple);
  const other = await speech(env, 'pro2', { text: 'Ten chars.' }, noApple);
  ok(other.headers.get('x-voice-model') === 'aura-2', "and another account's share is untouched");
  const empty = freshEnv({ WORKERS_AI_NEURONS_PER_ACCOUNT: '0' });
  ok((await speech(empty, 'pro', { text: 'Hello.' }, noApple)).status === 503 && empty.AI.calls.length === 0,
     'with no share left the model is not called, and the phone reads it');
}

// small pieces
ok(voiceFor({}, 'narrator') === 'pandora' && voiceFor({}, 'patient') === 'draco', 'default voices');
ok(voiceFor({ TTS_VOICES: 'patient:thalia,bogus:x,narrator:BAD!' }, 'patient') === 'thalia', 'TTS_VOICES overrides a voice');
ok(voiceFor({ TTS_VOICES: 'narrator:BAD!' }, 'narrator') === 'pandora', 'a malformed voice name is ignored');
ok(tidy(' a \n b ') === 'a b' && tidy(5) === '', 'tidy collapses spaces and ignores non-strings');
ok((await audioBytes(new Uint8Array([1, 2, 3]))).length === 3, 'raw bytes pass through');
ok((await audioBytes(null)) === null, 'nothing is nothing');

if (failures) { console.log(`\n${failures} failed`); process.exit(1); }
console.log('\nall passed');
