// Kill switches (switches.js): an AI feature switched off in the server's
// configuration is refused with a message the app shows - before anything is
// read, signed in, spent or queued - and nothing a student already has is
// lost: jobs can still be collected and cancelled, a running job ends with
// what it wrote and says why, and what cannot be checked stays Unverified.
//
// Run: node server/tests/switches.test.mjs

import { DatabaseSync } from 'node:sqlite';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import worker from '../worker.js';
import { FEATURES, switchedOff, isOff, featuresOf, featureOfModel, switchStates } from '../switches.js';
import { GenerationJobs, checkSpec, LIMITS } from '../jobs.js';
import { breakers, resetBreakers } from '../breakers.js';

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
        run() { const r = stmt.run(...args); return { meta: { changes: Number(r.changes) } }; },
      };
      return api;
    },
  };
}
function database() {
  const db = new DatabaseSync(':memory:');
  const sql = readFileSync(join(here, '..', 'schema.sql'), 'utf8')
    .split('\n').map(line => line.replace(/--.*$/, '')).join('\n');
  for (const statement of sql.split(';')) if (statement.trim()) db.exec(statement);
  return db;
}
const OWNER = 'k'.repeat(64);
/// A worker env whose database, models and job storage all count being
/// touched, so a refusal can be shown to have touched none of them.
function freshEnv(off, extra = {}) {
  const db = database();
  const touched = { db: 0, ai: 0, jobs: [] };
  const real = d1(db);
  return {
    touched, db,
    env: {
      STETHOSCORE_OFF: off, SESSION_SECRET: 'secret', OWNER_KEY: OWNER,
      DB: { prepare(sql) { touched.db++; return real.prepare(sql); } },
      AI: { run: async model => { touched.ai++; return { response: `from ${model}` }; } },
      JOBS: {
        idFromName: name => name,
        get: () => ({ fetch: async req => { touched.jobs.push(new URL(req.url).pathname); return new Response(JSON.stringify({ jobs: [], ok: true }), { status: 200 }); } }),
      },
      ...extra,
    },
  };
}
const call = (env, path, { method = 'POST', body = {}, auth = OWNER, headers = {} } = {}) => {
  const text = method === 'GET' || method === 'DELETE' ? undefined : JSON.stringify(body);
  return worker.fetch(new Request('https://w' + path, {
    method, body: text,
    headers: { authorization: 'Bearer ' + auth, ...(text ? { 'content-length': String(text.length) } : {}), ...headers },
  }), env);
};

// MARK: reading STETHOSCORE_OFF

{
  ok(switchedOff({}).off.size === 0 && switchedOff({ STETHOSCORE_OFF: '' }).off.size === 0, 'unset or empty: everything on');
  ok([...switchedOff({ STETHOSCORE_OFF: 'tts' }).off].join() === 'tts', 'one feature off');
  const many = switchedOff({ STETHOSCORE_OFF: ' TTS , transcribe\ncheck' });
  ok(many.off.has('tts') && many.off.has('transcribe') && many.off.has('check') && many.off.size === 3,
     'several, in any case, with spaces or new lines between them');
  ok(switchedOff({ STETHOSCORE_OFF: 'all' }).off.size === Object.keys(FEATURES).length, '"all" switches every AI feature off');
  const typo = switchedOff({ STETHOSCORE_OFF: 'ttts,write,ttts' });
  ok(typo.off.size === 1 && typo.unknown.join() === 'ttts', 'a name that is not a feature switches nothing off, and is reported once');
  ok(isOff({ STETHOSCORE_OFF: 'jobs' }, 'jobs') && !isOff({ STETHOSCORE_OFF: 'jobs' }, 'write'), 'isOff asks about one feature');
  ok(Object.keys(FEATURES).join() === 'write,check,jobs,accuracy,transcribe,tts', 'the features: write, check, jobs, accuracy, transcribe, tts');
  ok(Object.values(FEATURES).every(f => [429, 503].includes(f.status) && f.message.length > 20), 'each refused with 429 or 503 and a sentence');

  ok(featuresOf('/jobs', 'POST').join() === 'jobs,write' && featuresOf('/jobs/', 'POST').join() === 'jobs,write', 'a new background job needs jobs and write');
  ok(featuresOf('/jobs', 'GET').length === 0 && featuresOf('/jobs/0e4b6c2a-1111-2222-3333-444455556666', 'DELETE').length === 0,
     'collecting or cancelling a job needs nothing');
  ok(featuresOf('/accuracy/check', 'POST').join() === 'accuracy' && featuresOf('/transcribe/chunk', 'POST').join() === 'transcribe'
     && featuresOf('/tts', 'POST').join() === 'tts', 'the accuracy engine, transcription and the voice by path');
  ok(featuresOf('/accuracy/report', 'POST').length === 0 && featuresOf('/accuracy/model', 'POST').length === 0
     && featuresOf('/sync/push', 'POST').length === 0, 'reports, weights and sync are not AI features');
  ok(featureOfModel('cramdown-writer') === 'write' && featureOfModel('cramdown-doctor') === 'write'
     && featureOfModel('cramdown-checker') === 'check' && featureOfModel('cramdown-medval') === 'check' && featureOfModel('x') === null,
     'the cloud models by name: writers write, checkers check');
}

// MARK: each feature refused at the door

async function refused(r, feature, what) {
  const body = await r.json().catch(() => ({}));
  ok(r.status === FEATURES[feature].status && body.off === feature && body.message === FEATURES[feature].message
     && body.error === body.message && r.headers.get('retry-after') === '600',
     `${what}: ${r.status} with the message, off: "${feature}", Retry-After`);
}

// the natural voice: before sign-in, the database or Workers AI
{
  const { env, touched } = freshEnv('tts');
  await refused(await call(env, '/tts', { body: { text: 'Hello' }, auth: 'not-a-token' }), 'tts', 'the voice');
  ok(touched.db === 0 && touched.ai === 0, 'nothing signed in, counted or spoken');
}

// transcription: refused before its (up to 10 MB) body is read
{
  const { env, touched } = freshEnv('transcribe');
  let pulled = false;
  // highWaterMark 0: the stream is pulled only when somebody reads it
  const stream = new ReadableStream({ pull(controller) { pulled = true; controller.enqueue(new Uint8Array(1024)); controller.close(); } },
                                    { highWaterMark: 0 });
  const r = await worker.fetch(new Request('https://w/transcribe/chunk', {
    method: 'POST', body: stream, duplex: 'half', headers: { authorization: 'Bearer ' + OWNER, 'content-length': '3000000' } }), env);
  await refused(r, 'transcribe', 'transcription');
  ok(!pulled && touched.db === 0, 'the audio is never read, no chunk of the allowance is used');
}

// the accuracy engine: guarded in worker.js (accuracy.js is not changed)
{
  const { env, touched } = freshEnv('accuracy');
  let asked = 0;
  const realFetch = globalThis.fetch;
  globalThis.fetch = async () => { asked++; return new Response('{}'); };
  try {
    await refused(await call(env, '/accuracy/check', { body: { items: [{ id: '1', text: 'Aspirin 75 mg daily' }] } }), 'accuracy', 'the accuracy check');
  } finally { globalThis.fetch = realFetch; }
  ok(asked === 0 && touched.db === 0 && touched.ai === 0, 'no voter, no evidence source, no allowance');
  const report = await call(env, '/accuracy/model', {});
  ok(report.status !== 503, 'the published weights are still served');
}

// background jobs: a new one is refused and nothing is queued; collecting and
// cancelling still work
{
  const { env, touched } = freshEnv('jobs');
  const spec = { title: 'Cards', mode: 'loop', extract: 'lines', count: 5, steps: [{ user: 'Write.' }] };
  await refused(await call(env, '/jobs', { body: spec }), 'jobs', 'a new background job');
  ok(touched.jobs.length === 0 && touched.db === 0, 'nothing queued');
  const list = await call(env, '/jobs', { method: 'GET' });
  const cancel = await call(env, '/jobs/0e4b6c2a-1111-2222-3333-444455556666', { method: 'DELETE' });
  ok(list.status === 200 && cancel.status === 200 && touched.jobs.join() === '/list,/cancel',
     'the jobs already there can still be listed, collected and cancelled');

  const writing = freshEnv('write');
  await refused(await call(writing.env, '/jobs', { body: spec }), 'write', 'a new job with writing switched off');
  ok(writing.touched.jobs.length === 0, 'is not queued either');
}

// the cloud models: by the model asked for
{
  const { env, touched } = freshEnv('check');
  const ask = model => call(env, '/v1/chat/completions', { body: { model, messages: [{ role: 'user', content: 'hi' }] } });
  await refused(await ask('cramdown-checker'), 'check', 'the cloud checker');
  await refused(await ask('cramdown-medval'), 'check', 'MedVAL');
  ok(touched.ai === 0, 'no model asked');
  const w = await ask('cramdown-writer');
  ok(w.status === 200 && (await w.json()).choices[0].message.content.startsWith('from @cf/') && touched.ai === 1,
     'writing still answers while only the check is off');

  const writing = freshEnv('write');
  await refused(await call(writing.env, '/v1/chat/completions', { body: { model: 'cramdown-writer', messages: [{ role: 'user', content: 'hi' }] } }), 'write', 'the cloud writer');
  ok(writing.touched.db === 0 && writing.touched.ai === 0, 'before the allowance is touched');
}

// "all": every AI feature off, everything else as before; the owner too
{
  const { env } = freshEnv('all');
  const tried = await Promise.all([
    call(env, '/v1/chat/completions', { body: { model: 'cramdown-writer', messages: [{ role: 'user', content: 'hi' }] } }),
    call(env, '/jobs', { body: { mode: 'loop' } }),
    call(env, '/accuracy/check', { body: {} }),
    call(env, '/transcribe/chunk', { body: {} }),
    call(env, '/tts', { body: {} }),
  ]);
  ok(tried.every(r => r.status === 503 || r.status === 429), 'every AI route refused, the owner key included');
  ok((await Promise.all(tried.map(r => r.json()))).every(b => typeof b.off === 'string' && b.message), 'each saying which feature is off');
  const exams = await call(env, '/exams/catalogue', {});
  const refresh = await call(env, '/auth/refresh', { body: { refreshToken: 'x' } });
  ok(exams.status === 200 && refresh.status === 401, 'what is not AI is untouched (the exam catalogue, sign-in)');
}

// a typo switches nothing off
{
  const { env } = freshEnv('ttts');
  const r = await call(env, '/v1/chat/completions', { body: { model: 'cramdown-writer', messages: [{ role: 'user', content: 'hi' }] } });
  ok(r.status === 200, 'an unknown name in STETHOSCORE_OFF leaves every feature on');
}

// MARK: the owner's diagnostics show the switches and the breakers, read-only

{
  resetBreakers();
  const { env } = freshEnv('tts, ttts');
  for (let i = 0; i < 3; i++) breakers.failure(env, 'gemini:gemini-3.5-flash');
  const r = await worker.fetch(new Request('https://w/diagnostics/summary', { headers: { authorization: 'Bearer ' + OWNER } }), env);
  const body = await r.json();
  ok(r.status === 200 && body.health?.switches?.features?.tts === 'off' && body.health.switches.features.write === 'on',
     'GET /diagnostics/summary: which features are on and off');
  ok(body.health.switches.unknown?.join() === 'ttts', 'and a name in STETHOSCORE_OFF that is not a feature');
  ok(body.health.breakers?.scope === 'isolate' && body.health.breakers.lanes['gemini:gemini-3.5-flash'].state === 'open'
     && body.health.breakers.settings.failures === 3, "and this isolate's breakers, with their settings");
  ok(Array.isArray(body.groups) && Array.isArray(body.builds), 'the crash groups are there as before');
  const stranger = await worker.fetch(new Request('https://w/diagnostics/summary'), env);
  ok(stranger.status === 404, 'nobody else sees any of it');
  ok(JSON.stringify(switchStates({ STETHOSCORE_OFF: '' })) === JSON.stringify({ features: Object.fromEntries(Object.keys(FEATURES).map(f => [f, 'on'])) }),
     'with nothing off, every feature reads "on"');
  resetBreakers();
}

// MARK: a job already running

function storage() {
  const map = new Map();
  let alarm = null;
  const copy = v => v === undefined ? undefined : structuredClone(v);
  return {
    map,
    async get(key) { return copy(map.get(key)); },
    async put(key, value) {
      if (typeof key === 'object') for (const [k, v] of Object.entries(key)) map.set(k, copy(v));
      else map.set(key, copy(value));
    },
    async delete(keys) { for (const k of [].concat(keys)) map.delete(k); },
    async list({ prefix }) { return new Map([...map].filter(([k]) => k.startsWith(prefix)).map(([k, v]) => [k, copy(v)])); },
    async getAlarm() { return alarm; },
    async setAlarm(at) { alarm = at; },
    async deleteAlarm() { alarm = null; },
    async deleteAll() { map.clear(); },
  };
}
const jobEnv = off => ({ DB: d1(database()), AI_API_KEY: 'k', STETHOSCORE_OFF: off });
const get = async (object, id) => (await (await object.fetch(new Request(`https://jobs/get?id=${id}&outputs=1`))).json());

// writing switched off mid-job: it ends at once with what it wrote and says
// why - never a progress bar left standing while the switch stays off
{
  const store = storage();
  const env = jobEnv('');
  let calls = 0;
  const fake = async () => { calls++; return new Response(JSON.stringify({ choices: [{ message: { content: `Q${calls} | A${calls}` } }] }), { status: 200 }); };
  const object = new GenerationJobs({ storage: store }, env, fake);
  const spec = checkSpec({ title: 'Cards', mode: 'loop', extract: 'lines', count: 3, steps: [{ user: 'Write 1.' }] }).spec;
  const made = await (await object.create({ accountId: 'owner', owner: true, spec })).json();
  await object.alarm();
  ok((await get(object, made.job.id)).job.done === 1, 'one card written');

  env.STETHOSCORE_OFF = 'write';
  await object.alarm();
  const ended = await get(object, made.job.id);
  ok(calls === 1, 'switched off: no model is asked');
  ok(ended.job.status === 'done' && ended.job.partial && ended.job.done === 1 && /switched off/.test(ended.job.reason),
     'the job ends at once: done, partial, with the reason the app shows');
  ok(ended.outputs.length === 1 && ended.job.held === null, 'what was written is there to collect; nothing is left waiting');
  await object.alarm();
  ok(calls === 1 && (await get(object, made.job.id)).job.status === 'done', 'and nothing more is asked afterwards');
}

// all background work switched off before anything was written: failed, with
// the reason - the app shows it rather than a spinner
{
  const store = storage();
  const env = jobEnv('');
  let calls = 0;
  const fake = async () => { calls++; return new Response(JSON.stringify({ choices: [{ message: { content: 'Q | A' } }] }), { status: 200 }); };
  const object = new GenerationJobs({ storage: store }, env, fake);
  const spec = checkSpec({ title: 'Cards', mode: 'loop', extract: 'lines', count: 5, steps: [{ user: 'Write 1.' }] }).spec;
  const made = await (await object.create({ accountId: 'owner', owner: true, spec })).json();
  env.STETHOSCORE_OFF = 'jobs';
  await object.alarm();
  const ended = await get(object, made.job.id);
  ok(calls === 0 && ended.job.status === 'failed' && /switched off/.test(ended.job.error), 'nothing written: failed, saying writing is switched off');
}

// the check switched off while a job is being checked: the writing is handed
// over, and what was not checked stays Unverified
{
  const store = storage();
  const env = jobEnv('');
  const asked = [];
  const fake = async (url, init) => {
    const prompt = JSON.parse(init.body).messages.at(-1).content;
    asked.push(prompt.startsWith('CHECK') ? 'check' : 'write');
    const content = prompt.startsWith('CHECK') ? 'risk 1'
      : '{"questions":[{"stem":"Q1 stem","options":["a","b"],"correctIndex":0},{"stem":"Q2 stem","options":["a","b"],"correctIndex":1}]}';
    return new Response(JSON.stringify({ choices: [{ message: { content } }] }), { status: 200 });
  };
  const object = new GenerationJobs({ storage: store }, env, fake);
  const spec = checkSpec({ title: 'MCQ', mode: 'loop', extract: 'questions', count: 2, sources: ['Lecture'],
    steps: [{ user: 'Write {{SOURCE}}', source: 0 }], check: { template: 'CHECK {{INPUT}} {{OUTPUT}}' } }).spec;
  const made = await (await object.create({ accountId: 'owner', owner: true, spec })).json();
  await object.alarm();   // the writing
  await object.alarm();   // the first check
  env.STETHOSCORE_OFF = 'check';
  await object.alarm();
  const got = await get(object, made.job.id);
  ok(asked.join() === 'write,check', 'the second question is never sent to the checker');
  ok(got.job.status === 'done' && got.outputs.length === 1 && got.checks.length === 1, 'the job is done: both questions, one verdict');
  ok(/switched off/.test(got.job.checkError) && /Unverified/.test(got.job.checkError), 'the rest stays Unverified, and the app is told why');
}

// every provider resting (breakers.js): the job waits for them rather than
// counting failures towards giving up
{
  resetBreakers();
  const store = storage();
  const env = jobEnv('');
  let calls = 0;
  const fake = async () => { calls++; return new Response(JSON.stringify({ choices: [{ message: { content: 'Q | A' } }] }), { status: 200 }); };
  const object = new GenerationJobs({ storage: store }, env, fake);
  const spec = checkSpec({ title: 'Cards', mode: 'loop', extract: 'lines', count: 1, steps: [{ user: 'Write 1.' }] }).spec;
  const made = await (await object.create({ accountId: 'owner', owner: true, spec })).json();
  for (let i = 0; i < 3; i++) breakers.failure(env, 'openai:baichuan-inc/Baichuan-M2-32B:featherless-ai');
  for (let i = 0; i < 6; i++) await object.alarm();
  const waiting = await get(object, made.job.id);
  ok(calls === 0 && waiting.job.status === 'running' && /busy/.test(waiting.job.held), 'six turns with the only provider resting: still waiting, not failed');
  const at = await store.getAlarm();
  ok(at >= Date.now() + 55_000, 'each time until the provider may be tried again (about a minute), not every 20 s');
  resetBreakers();
  await object.alarm();
  ok((await get(object, made.job.id)).job.status === 'done' && calls === 1, 'the provider back: the job finishes');
}

// waiting on busy answers costs the student nothing, and is bounded: past
// holdMinutes the job ends with what it has, rather than a bar that never moves
{
  resetBreakers();
  const store = storage();
  const env = jobEnv('');
  const db = env.DB;
  let calls = 0;
  const fake = async () => { calls++; return new Response(JSON.stringify({ choices: [{ message: { content: `Q${calls} | A${calls}` } }] }), { status: 200 }); };
  const object = new GenerationJobs({ storage: store }, env, fake);
  const spec = checkSpec({ title: 'Cards', mode: 'loop', extract: 'lines', count: 5, steps: [{ user: 'Write 1.' }] }).spec;
  const made = await (await object.create({ accountId: 'a1', owner: false, spec })).json();
  // a Pro account (an owner id), so the job's calls go through the allowance
  env.OWNER_ACCOUNT_IDS = 'a1';
  db.prepare(`INSERT INTO accounts (id, provider, subject, created_at) VALUES ('a1', 'apple', 's1', 0)`).run();
  await object.alarm();
  const usedNow = () => db.prepare('SELECT requests FROM ai_usage WHERE account_id = ?').bind('a1').first()?.requests ?? 0;
  ok((await get(object, made.job.id)).job.done === 1 && usedNow() === 1, 'one card written, one request counted');
  for (let i = 0; i < 3; i++) breakers.failure(env, 'openai:baichuan-inc/Baichuan-M2-32B:featherless-ai');
  for (let i = 0; i < 5; i++) await object.alarm();
  const waiting = await get(object, made.job.id);
  ok(waiting.job.status === 'running' && /busy/.test(waiting.job.held) && calls === 1, 'the only provider resting: the job waits');
  ok(usedNow() === 1, "five busy turns: none of the student's day is used");
  const job = await store.get(`job:${made.job.id}`);
  job.heldSince = Date.now() - LIMITS.holdMinutes * 60_000 - 1;
  await store.put(`job:${made.job.id}`, job);
  await object.alarm();
  const ended = await get(object, made.job.id);
  ok(LIMITS.holdMinutes <= 15 && ended.job.status === 'done' && ended.job.partial && /busy/.test(ended.job.reason) && ended.outputs.length === 1,
     'busy past holdMinutes: it ends as a partial set the app collects, with the reason');
  resetBreakers();
}

if (failures) { console.error(`${failures} failed`); process.exit(1); }
console.log('all passed');
