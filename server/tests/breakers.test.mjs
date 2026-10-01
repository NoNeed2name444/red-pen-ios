// Circuit breakers on the model chain's providers (breakers.js), on a fake
// clock and a fake upstream.
//
// What matters: a provider that keeps failing is skipped, not waited on; it is
// tried again, once, after its cooldown; and when every provider is resting
// the answer is a quick "busy, try again" that spends nothing - never a hang.
//
// Run: node server/tests/breakers.test.mjs

import { DatabaseSync } from 'node:sqlite';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { Breakers, breakers, resetBreakers, breakerSettings, failed } from '../breakers.js';
import { chat, askModel, transcribeChunk } from '../ai.js';

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
        all() { return { results: stmt.all(...args) }; },
      };
      return api;
    },
  };
}
function freshEnv(extra = {}) {
  const db = new DatabaseSync(':memory:');
  const sql = readFileSync(join(here, '..', 'schema.sql'), 'utf8')
    .split('\n').map(line => line.replace(/--.*$/, '')).join('\n');
  for (const statement of sql.split(';')) if (statement.trim()) db.exec(statement);
  db.prepare(`INSERT INTO accounts (id, provider, subject, created_at) VALUES ('a1', 'apple', 's1', 0)`).run();
  return { DB: d1(db), db, APPLE_BUNDLE_ID: 'com.cramdown.app', OWNER_ACCOUNT_IDS: 'a1', ...extra };
}
const used = (env, key) => env.db.prepare('SELECT requests FROM ai_usage WHERE account_id = ?').get(key)?.requests ?? 0;

// a clock the tests move by hand
let t = 1_000_000;
const clock = () => t;
const later = seconds => { t += seconds * 1000; };

const request = { model: 'cramdown-writer', messages: [{ role: 'user', content: 'hi' }], max_tokens: 50 };
const answer = text => new Response(JSON.stringify({ candidates: [{ content: { parts: [{ text }] } }] }), { status: 200 });
const down = status => new Response(JSON.stringify({ error: { message: 'overloaded' } }), { status });
const firebase = { FIREBASE_API_KEY: 'fk', FIREBASE_PROJECT_ID: 'p' };
const modelOf = url => url.match(/models\/([^:]+):/)?.[1];

// MARK: the breaker on its own

{
  const env = {};
  const b = new Breakers(clock);
  const s = breakerSettings(env);
  ok(s.failures === 3 && s.windowSeconds === 120 && s.cooldownSeconds === 60, 'defaults: 3 failures in 120 s open it for 60 s');
  const tuned = breakerSettings({ STETHOSCORE_BREAKER_FAILURES: '5', STETHOSCORE_BREAKER_WINDOW_SECONDS: '30', STETHOSCORE_BREAKER_COOLDOWN_SECONDS: 'x' });
  ok(tuned.failures === 5 && tuned.windowSeconds === 30 && tuned.cooldownSeconds === 60, 'tuned from wrangler.toml [vars]; a value that is not a number keeps the default');
  ok(breakerSettings({ STETHOSCORE_BREAKER_FAILURES: '0' }).failures === 3, 'a threshold of 0 (always open) is refused');
  ok(failed(500) && failed(503) && failed(504) && failed(529) && failed(408), 'a 5xx or a 408 counts against the provider');
  ok(!failed(429) && !failed(400) && !failed(401) && !failed(200), 'a quota, a refusal or an answer does not');

  ok(b.allow(env, 'x'), 'a lane never seen is closed');
  b.failure(env, 'x'); later(10); b.failure(env, 'x');
  ok(b.allow(env, 'x') && !b.resting(env, 'x'), 'two failures: still closed');
  later(115);
  b.failure(env, 'x');
  ok(b.allow(env, 'x'), 'a third failure outside the window (the first is 125 s old): still closed');
  b.failure(env, 'x');
  ok(!b.allow(env, 'x') && b.resting(env, 'x'), 'three inside 120 s: open, the lane is skipped');
  later(59);
  ok(!b.allow(env, 'x'), 'still open just before the cooldown ends');
  later(1);
  ok(!b.resting(env, 'x'), 'the cooldown over: no longer resting');
  ok(b.allow(env, 'x'), 'half-open: one trial goes through');
  ok(!b.allow(env, 'x') && b.resting(env, 'x'), 'and only one: a second caller is still skipped');
  b.failure(env, 'x');
  ok(!b.allow(env, 'x') && b.retryAfter(env, ['x']) === 60, 'the trial failed: open again, for a whole new cooldown');
  later(60);
  ok(b.allow(env, 'x'), 'the next trial');
  b.success(env, 'x');
  ok(b.allow(env, 'x') && b.allow(env, 'x') && !b.resting(env, 'x'), 'it answered: closed, every caller goes through');
  b.failure(env, 'x');
  ok(b.allow(env, 'x'), 'and its failures count from nothing again');

  // a trial given up (the call was not made after all) lets the next go
  const r = new Breakers(clock);
  for (let i = 0; i < 3; i++) r.failure(env, 'y');
  later(61);
  ok(r.allow(env, 'y') && !r.allow(env, 'y'), 'half-open, trial taken');
  r.release('y');
  ok(r.allow(env, 'y'), 'released unused: the next caller makes the trial');
  later(301);
  ok(r.allow(env, 'y'), 'a trial that never reported back stops blocking after five minutes');

  // a call that went out before the breaker opened, failing late, does not
  // start the cooldown over
  const late = new Breakers(clock);
  for (let i = 0; i < 3; i++) late.failure(env, 'z');
  later(50);
  late.failure(env, 'z');
  ok(late.retryAfter(env, ['z']) === 10, 'a late failure leaves the running cooldown alone');

  const snap = late.snapshot(env);
  ok(snap.scope === 'isolate' && snap.lanes.z.state === 'open' && snap.lanes.z.retryInSeconds === 10 && snap.lanes.z.timesOpened === 1,
     'the snapshot: per isolate, each lane with its state and when it may be tried');
  later(10);
  ok(late.snapshot(env).lanes.z.state === 'half-open', 'past its cooldown it shows as half-open, ready for a trial');
  ok(late.retryAfter(env, ['z', 'never-failed']) === 1, 'a closed lane among them: try again at once');
}

// MARK: in the chain (ai.js), with a fake upstream

// Flash keeps failing: after three failures it is not asked at all, and
// Flash-Lite answers straight away
{
  resetBreakers(clock);
  const env = freshEnv(firebase);
  const asked = [];
  const fetcher = async url => {
    asked.push(modelOf(url));
    return modelOf(url) === 'gemini-3.5-flash' ? down(503) : answer('lite');
  };
  for (let i = 0; i < 3; i++) await chat(env, 'a1', request, fetcher);
  ok(asked.filter(m => m === 'gemini-3.5-flash').length === 3, 'Flash overloaded three times in a row');
  asked.length = 0;
  const r = await chat(env, 'a1', request, fetcher);
  ok(r.status === 200 && (await r.json()).source === 'gemini-3.5-flash-lite', 'the fourth request is answered');
  ok(asked.join() === 'gemini-3.5-flash-lite', 'without asking Flash: its breaker is open');
  ok(breakers.snapshot(env).lanes['gemini:gemini-3.5-flash'].state === 'open', 'and the snapshot says so');

  // after the cooldown, one trial: Flash is back
  later(60);
  asked.length = 0;
  const back = async url => { asked.push(modelOf(url)); return answer('flash'); };
  const b = await chat(env, 'a1', request, back);
  ok(b.status === 200 && (await b.json()).source === 'gemini-3.5-flash' && asked.join() === 'gemini-3.5-flash', 'after 60 s Flash is tried once, and answers');
  ok(breakers.snapshot(env).lanes['gemini:gemini-3.5-flash'].state === 'closed', 'its breaker is closed again');
}

// A host that never answers in time (the fetch is aborted) counts as failing
// too, and a per-minute 429 does not
{
  resetBreakers(clock);
  const env = freshEnv({ AI_API_KEY: 'hf' }); // the Hugging Face route alone
  let calls = 0;
  const timeout = async () => { calls++; throw Object.assign(new Error('The operation was aborted due to timeout'), { name: 'TimeoutError' }); };
  for (let i = 0; i < 3; i++) {
    const r = await chat(env, 'a1', request, timeout);
    ok(r.status === 502, `timed out (${i + 1}): reported as unavailable`);
  }
  const lane = Object.keys(breakers.snapshot(env).lanes).find(l => l.startsWith('openai:'));
  ok(breakers.snapshot(env).lanes[lane].state === 'open', 'three time-outs open the host\'s breaker');

  resetBreakers(clock);
  const quota = async () => { calls++; return new Response(JSON.stringify({ error: { message: 'slow down' } }), { status: 429 }); };
  for (let i = 0; i < 5; i++) await chat(env, 'a1', request, quota);
  ok(!Object.values(breakers.snapshot(env).lanes).some(l => l.state !== 'closed'), 'five 429s in a row: the breaker stays closed (a quota, not an outage)');
}

// Every provider resting: a quick, clean "busy" - no provider is asked, and
// the day's allowance is not spent
{
  resetBreakers(clock);
  let workersAsked = 0;
  const env = freshEnv({ ...firebase, AI: { run: async () => { workersAsked++; throw new Error('3040: Capacity temporarily exceeded'); } } });
  const asked = [];
  const allDown = async url => { asked.push(modelOf(url)); return down(500); };
  for (let i = 0; i < 3; i++) await chat(env, 'a1', request, allDown);
  const spentBefore = used(env, 'a1');
  ok(spentBefore === 3 && workersAsked === 3, 'three requests, every Gemini model and Workers AI failing each time');
  asked.length = 0;
  workersAsked = 0;
  const started = Date.now();
  const r = await chat(env, 'a1', request, allDown);
  const body = await r.json();
  ok(r.status === 503 && body.busy === true && /busy right now/.test(body.message), 'the fourth: 503 "busy, try again", a message the app shows');
  ok(r.headers.get('retry-after') === '60' && body.retryAfter === 60, 'with how long to wait (Retry-After)');
  ok(asked.length === 0 && workersAsked === 0, 'no provider is asked');
  ok(Date.now() - started < 1000, 'at once, not after a wait');
  ok(used(env, 'a1') === spentBefore, "today's allowance is not spent on it");

  // a background job's call gets the same answer (jobs.js waits it out)
  const job = await chat(env, 'a1', request, allDown, { rounds: 1, maxTokensCap: 8000 });
  ok(job.status === 503 && (await job.json()).busy === true, "a background job's call: the same busy answer");

  // half an hour of "busy" is still only the cooldown: after it, one trial each
  later(60);
  const healthy = async url => { asked.push(modelOf(url)); return answer('back'); };
  const h = await chat(env, 'a1', request, healthy);
  ok(h.status === 200 && (await h.json()).choices[0].message.content === 'back', 'after the cooldown the chain answers again');
}

// Providers that fail while a request is on its way: still the busy answer,
// not the generic failure
{
  resetBreakers(clock);
  const env = freshEnv({ ...firebase, CLOUD_MODELS: 'gemma-4-31b-it' });
  for (let i = 0; i < 2; i++) await chat(env, 'a1', request, async () => down(503));
  // the third failure opens Gemma's breaker mid-request; nothing else is set up
  const third = await chat(env, 'a1', request, async () => down(503));
  ok(third.status === 502, 'the request that opens the breaker reports the failure it saw');
  const r = await chat(env, 'a1', request, async () => { throw new Error('must not be called'); });
  ok(r.status === 503 && (await r.json()).busy === true, 'the next one is busy at once');
}

// Two requests in the half-open moment: only one reaches the provider
{
  resetBreakers(clock);
  const env = freshEnv({ ...firebase, CLOUD_MODELS: 'gemma-4-31b-it' });
  for (let i = 0; i < 3; i++) await chat(env, 'a1', request, async () => down(503));
  later(60);
  let release;
  const gate = new Promise(resolve => { release = resolve; });
  let reached = 0;
  const slow = async () => { reached++; await gate; return answer('trial'); };
  const first = chat(env, 'a1', request, slow);
  // let the first request get as far as its call
  for (let i = 0; i < 50 && !reached; i++) await new Promise(r => setTimeout(r, 1));
  const second = await chat(env, 'a1', request, slow);
  ok(reached === 1 && second.status === 503 && (await second.json()).busy === true, 'the second is told busy while the trial is out');
  release();
  const r = await first;
  ok(r.status === 200 && (await r.json()).choices[0].message.content === 'trial', 'the trial answers and closes the breaker');
  const third = await chat(env, 'a1', request, async () => answer('closed'));
  ok(third.status === 200, 'after which everyone is let through');
}

// The accuracy engine's voters (askModel) are behind the same breakers,
// without accuracy.js knowing
{
  resetBreakers(clock);
  const env = freshEnv(firebase);
  for (let i = 0; i < 3; i++) await askModel(env, 'owner', true, 'gemini:gemma-4-31b-it', [{ role: 'user', content: 'vote' }], 100, async () => down(500));
  let asked = 0;
  const r = await askModel(env, 'owner', true, 'gemini:gemma-4-31b-it', [{ role: 'user', content: 'vote' }], 100, async () => { asked++; return answer('x'); });
  ok(!r.ok && r.status === 503 && r.resting === true && asked === 0, 'a resting voter is not asked: its ballot is missing (the item stays Unverified)');
}

// Cloud transcription: every Gemini model resting is "busy" before a chunk of
// today's allowance is used
{
  resetBreakers(clock);
  const env = freshEnv({ ...firebase, TRANSCRIBE_MODELS: 'gemini-3.5-flash' });
  const body = { audio: 'AAAA'.repeat(100), prompt: 'Transcribe.' };
  for (let i = 0; i < 3; i++) await transcribeChunk(env, 'a1', body, async () => down(503));
  const before = used(env, 'transcribe:a1');
  let asked = 0;
  const r = await transcribeChunk(env, 'a1', body, async () => { asked++; return answer('[]'); });
  const said = await r.json();
  ok(r.status === 429 && said.busy === true && /transcribe on this phone/.test(said.message), 'transcription: busy (429, which the app shows), this phone can still transcribe');
  ok(asked === 0 && used(env, 'transcribe:a1') === before, 'nothing sent to Google, no chunk of the allowance used');
}

// Paid lanes (Claude, while Pro pays) have breakers of their own, and the free
// chain carries on behind them
{
  resetBreakers(clock);
  const env = freshEnv({ ...firebase, PRO_PAYS: 'on', PRO_MONTHLY_BUDGET_USD: '5', ANTHROPIC_API_KEY: 'ak',
                         GEMINI_PRICES: 'gemini-3.5-flash:0.30/2.50' });
  const asked = [];
  const fetcher = async url => {
    if (url.includes('anthropic')) { asked.push('claude'); return down(529); }
    asked.push(modelOf(url));
    return answer('gemini');
  };
  const first = await chat(env, 'a1', request, fetcher);
  ok(first.status === 200 && (await first.json()).choices[0].message.content === 'gemini' && asked.join() === 'claude,gemini-3.5-flash',
     'Claude overloaded (529): the free chain answers that same request');
  for (let i = 0; i < 2; i++) await chat(env, 'a1', request, fetcher);
  ok(asked.filter(a => a === 'claude').length === 3, 'Claude overloaded three times');
  asked.length = 0;
  const r = await chat(env, 'a1', request, fetcher);
  ok(r.status === 200 && !asked.includes('claude') && (await r.json()).choices[0].message.content === 'gemini',
     'then skipped while it rests: Gemini answers without waiting on Claude');
}

resetBreakers();
if (failures) { console.error(`${failures} failed`); process.exit(1); }
console.log('all passed');
