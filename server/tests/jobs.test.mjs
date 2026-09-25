// Background generation jobs: what a phone may hand over, and a job run to
// the end on a fake storage and a fake model - repeats dropped, the list of
// what is written fed back into the next prompt, pages kept in order.
//
// Run: node server/tests/jobs.test.mjs

import { DatabaseSync } from 'node:sqlite';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { checkSpec, fill, itemsIn, differentialText, differentialBlock, withReasoningChecks, REASONING_CHECKS, GenerationJobs, LIMITS } from '../jobs.js';
import { checkerOrder } from '../ai.js';

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
function env() {
  const db = new DatabaseSync(':memory:');
  const sql = readFileSync(join(here, '..', 'schema.sql'), 'utf8')
    .split('\n').map(line => line.replace(/--.*$/, '')).join('\n');
  for (const statement of sql.split(';')) if (statement.trim()) db.exec(statement);
  return { DB: d1(db), AI_API_KEY: 'k' };
}
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
    clearAlarm() { alarm = null; },
  };
}
// every alarm that is due soon - not the one a week out that expires finished jobs
async function runAll(object, store, limit = 50) {
  for (let i = 0; i < limit; i++) {
    const at = await store.getAlarm();
    if (!at || at > Date.now() + 3_600_000) break;
    store.clearAlarm();
    await object.alarm();
  }
}

// what is refused at the door
ok(checkSpec({ mode: 'loop', extract: 'lines', steps: [] }).error, 'a job with no prompts is refused');
ok(checkSpec({ mode: 'x', extract: 'lines', steps: [{ user: 'a' }] }).error, 'an unknown mode is refused');
ok(checkSpec({ mode: 'loop', extract: 'lines', steps: [{ user: 'a', source: 2 }], sources: ['s'] }).error, 'a prompt naming a missing source is refused');
ok(checkSpec({ mode: 'loop', extract: 'lines', steps: [{ user: 'x'.repeat(70_000) }] }).error, 'an oversized prompt is refused');
ok(checkSpec({ mode: 'loop', extract: 'lines', count: 10, steps: [{ user: 'a', maxTokens: 1e9 }] }).spec.steps[0].maxTokens === 8000, 'tokens are capped');
ok(!checkSpec({ mode: 'loop', extract: 'lines', count: 10, sources: Array(45).fill('x'.repeat(40_000)), steps: [{ user: 'a', source: 0 }] }).error,
   'a long lecture in 45 windows of 40,000 characters is one job');
ok(checkSpec({ mode: 'loop', extract: 'lines', count: 10, sources: Array(5).fill('x'.repeat(1_400_000)), steps: [{ user: 'a' }] }).error,
   'but the lecture as a whole still has a limit');

// placeholders
ok(fill('SOURCE:\n{{SOURCE}}', 'the lecture', []) === 'SOURCE:\nthe lecture', 'the source goes in');
ok(fill('Done:\n- {{ALREADY}}\nend', '', ['a', 'b']) === 'Done:\n- a\n- b\nend', 'what is written is listed with the line\'s prefix');
ok(fill('- {{ALREADY}}', '', []) === '- (none yet)', 'an empty list says so');

// reading replies
const lines = itemsIn('1. Q one | A one\nnot a card\n- Q two | A two\n{{c1::cloze}} line', { extract: 'lines', minFields: 2, keyFields: 1, cloze: true });
ok(lines.length === 3 && lines[0].key === 'Q one', 'card lines are read, numbering stripped');
const qs = itemsIn('Here: {"questions":[{"stem":"A man of 60","options":["x","y"],"correctIndex":1,"explanation":"e"}]}', { extract: 'questions' });
ok(qs.length === 1 && qs[0].key.includes('[answer: y]'), 'questions are read from JSON with their answer');

// a question's differential goes to the checker with it, worded as the app words it
{
  const ddx = {
    mostLikely: [{ name: 'Indirect inguinal hernia', for: ['young man', 'reaches the scrotum'], against: [], test: 'sac lateral to the inferior epigastric vessels' }],
    expanded: [{ name: 'Femoral hernia', for: ['groin lump'], against: ['above and medial to the pubic tubercle'], test: 'ultrasound' }],
    cantMiss: [{ name: 'Strangulated hernia', against: ['reducible', 'painless'], test: 'urgent surgical review if tender and irreducible' }],
  };
  ok(differentialText(ddx) === [
    '- Most likely: Indirect inguinal hernia (for: young man, reaches the scrotum; test: sac lateral to the inferior epigastric vessels)',
    '- Expanded: Femoral hernia (for: groin lump; against: above and medial to the pubic tubercle; test: ultrasound)',
    '- Can\u2019t miss: Strangulated hernia (against: reducible, painless; test: urgent surgical review if tender and irreducible)',
  ].join('\n'), 'the differential is written tier by tier, for and against and the test');
  ok(differentialText({ most_likely: ['Hydrocele'], cant_miss: [] }) === '- Most likely: Hydrocele', 'other key spellings and bare names are read');
  ok(differentialBlock(undefined) === '' && differentialBlock('text') === '' && differentialBlock({}) === '', 'no differential adds nothing');
  const withDdx = itemsIn(JSON.stringify({ questions: [{ stem: 'A man of 24 with a groin lump', options: ['x', 'y'], differential: ddx, correctIndex: 0, explanation: 'e' }] }), { extract: 'questions' });
  ok(withDdx[0].check.includes('Explanation: e\nDifferential:\n- Most likely: Indirect inguinal hernia'), 'the checker sees the differential after the explanation');
  ok(!qs[0].check.includes('Differential'), 'a question without one is checked as before');
}

// a MedVAL template from an app built before the reasoning checks gets them on
// the server, after MedVAL's own three fields; a new one is left as it is
{
  const old = 'Your output fields are:\n3. `risk_level\' (Literal[1, 2, 3, 4]):\n    Level 4 (High Risk): ...\n\n' +
    'All interactions will be structured in the following way.\n\n[[ ## output ## ]]\n{{OUTPUT}}\n\n' +
    '[[ ## risk_level ## ]]\n# TO_BE_FILLED_BY_MODEL\n\n[[ ## completed ## ]]';
  const up = withReasoningChecks(old);
  ok(up.includes("4. `reasoning_issues' (str):\n    " + REASONING_CHECKS + '\n\nAll interactions'), 'the reasoning checks are described after risk_level');
  ok(up.includes('fit ALL the key findings') && up.includes("can't-miss") && up.includes('Unsupported claim'),
     'they ask whether the answer fits every finding, about a can\'t-miss diagnosis, and for unsupported claims');
  ok(up.indexOf('[[ ## risk_level ## ]]') < up.indexOf('[[ ## reasoning_issues ## ]]\n# TO_BE_FILLED_BY_MODEL\n\n[[ ## completed ## ]]'),
     'and the field is filled in after the risk level, so the grade reads as before');
  ok(withReasoningChecks(up) === up, 'a template that already asks for them is unchanged');
  ok(withReasoningChecks('CHECK {{OUTPUT}}') === 'CHECK {{OUTPUT}}', 'a template that is not MedVAL\'s is unchanged');
  ok(checkSpec({ mode: 'loop', extract: 'questions', count: 1, steps: [{ user: 'a' }], check: { template: old } }).spec.check.template === up,
     'a job\'s check is upgraded when the job is made');
}

// the evidence the checker read comes back with its verdict, for the app to cite
{
  const store = storage();
  const fake = async (url, init) => {
    if (url.includes('europepmc')) return new Response(JSON.stringify({ resultList: { result: [
      { title: 'Groin hernia guidelines', journalTitle: 'Hernia', pubYear: '2023', doi: '10.1007/hernia', abstractText: 'Mesh repair is recommended for symptomatic inguinal hernia in adults.', source: 'MED', id: '9' },
    ] } }), { status: 200 });
    if (!init?.body) return new Response('', { status: 404 });
    const body = JSON.parse(init.body);
    const text = body.messages.map(m => m.content).join('\n');
    const content = text.includes('You pick search terms') ? '{"queries":["inguinal hernia"],"drugs":[]}'
      : text.includes('[[ ## output ## ]]') ? '[[ ## errors ## ]]\nNone\n[[ ## risk_level ## ]]\n1\n[[ ## reasoning_issues ## ]]\nNone'
      : '{"questions":[{"stem":"Q1 stem","options":["a","b"],"correctIndex":0,"explanation":"e"}]}';
    return new Response(JSON.stringify({ choices: [{ message: { content } }] }), { status: 200 });
  };
  const object = new GenerationJobs({ storage: store }, env(), fake);
  const spec = checkSpec({ title: 'MCQ', mode: 'loop', extract: 'questions', count: 1, sources: ['Hernia lecture'],
    steps: [{ system: 'Write {{SOURCE}}', user: 'Now.', source: 0 }],
    check: { template: '[[ ## instruction ## ]]\nCheck\n\n[[ ## input ## ]]\n{{INPUT}}\n\n[[ ## output ## ]]\n{{OUTPUT}}\n\n[[ ## reasoning ## ]]' } }).spec;
  const made = await (await object.create({ accountId: 'owner', owner: true, spec })).json();
  await runAll(object, store);
  const got = await (await object.fetch(new Request(`https://jobs/get?id=${made.job.id}&outputs=1`))).json();
  const verdict = got.checks?.[0];
  ok(verdict?.evidence?.[0]?.id === 'S1' && verdict.evidence[0].url === 'https://doi.org/10.1007/hernia' && verdict.evidence[0].source === 'Europe PMC',
     'the verdict carries the evidence it was checked against: id, source and link');
  ok(!('text' in (verdict?.evidence?.[0] || {})), 'but not the abstracts themselves');
}

// a card job, start to finish
{
  const store = storage();
  const prompts = [];
  let call = 0;
  const replies = ['Q1 | A1\nQ2 | A2', 'Q2 | A2\nQ3 | A3', 'Q4 | A4\nQ5 | A5'];
  const fake = async (url, init) => {
    const body = JSON.parse(init.body);
    prompts.push(body);
    return new Response(JSON.stringify({ choices: [{ message: { content: replies[call++ % replies.length] } }] }), { status: 200 });
  };
  const object = new GenerationJobs({ storage: store }, env(), fake);
  const spec = checkSpec({ title: 'Cards', mode: 'loop', extract: 'lines', count: 4, sources: ['LECTURE TEXT'],
    steps: [{ system: 'Rules\nAlready:\n- {{ALREADY}}\nSOURCE:\n{{SOURCE}}', user: 'Write 2.', source: 0 }] }).spec;
  const made = await (await object.create({ accountId: 'owner', owner: true, spec })).json();
  await runAll(object, store);
  const got = await (await object.fetch(new Request(`https://jobs/get?id=${made.job.id}&outputs=1`))).json();
  ok(got.job.status === 'done' && got.job.done === 4, 'the job runs to the count on its own');
  ok(got.outputs.length === 3, 'every useful reply is kept');
  ok(prompts[0].messages[0].content.includes('LECTURE TEXT'), 'the lecture is put into the prompt');
  ok(prompts[1].messages[0].content.includes('- Q1\n- Q2'), 'the next prompt lists what is already written');
  ok(![...store.map.keys()].some(k => k.startsWith('src:') || k.startsWith('step:')),
     'a finished job lets go of its lecture and prompts');
  await object.fetch(new Request(`https://jobs/cancel?id=${made.job.id}`, { method: 'POST' }));
  ok(store.map.size === 0, 'a collected job leaves nothing behind');
}

// finished jobs waiting to be collected are capped; the oldest make room
{
  const store = storage();
  const fake = async () => new Response(JSON.stringify({ choices: [{ message: { content: 'Q | A' } }] }), { status: 200 });
  const object = new GenerationJobs({ storage: store }, env(), fake);
  const spec = checkSpec({ title: 'C', mode: 'loop', extract: 'lines', count: 1, sources: ['s'],
    steps: [{ user: 'Write 1.', source: 0 }] }).spec;
  for (let i = 0; i < LIMITS.kept + 3; i++) {
    const r = await object.create({ accountId: 'owner', owner: true, spec });
    if (r.status !== 201) ok(false, 'a new job is taken');
    await runAll(object, store);
  }
  ok((await object.all()).length === LIMITS.kept, 'no more than the cap are kept');
}

// pages stay in order, and a refusal ends the job
{
  const store = storage();
  let n = 0;
  const fake = async () => new Response(JSON.stringify({ choices: [{ message: { content: `## Page ${++n}` } }] }), { status: 200 });
  const object = new GenerationJobs({ storage: store }, env(), fake);
  const spec = checkSpec({ title: 'Book', mode: 'each', extract: 'pages', sources: ['a', 'b'],
    steps: [{ user: 'Write {{SOURCE}}', source: 0 }, { user: 'Write {{SOURCE}}', source: 1 }] }).spec;
  const made = await (await object.create({ accountId: 'owner', owner: true, spec })).json();
  await runAll(object, store);
  const got = await (await object.fetch(new Request(`https://jobs/get?id=${made.job.id}&outputs=1`))).json();
  ok(got.job.status === 'done' && got.outputs.join('|') === '## Page 1|## Page 2', 'a textbook comes back page by page, in order');

  const refused = new GenerationJobs({ storage: storage() }, env(), fake);
  const job = await (await refused.create({ accountId: 'a1', owner: false, spec })).json();
  await runAll(refused, refused.storage);
  const failed = await (await refused.fetch(new Request(`https://jobs/get?id=${job.job.id}`))).json();
  ok(failed.job.status === 'failed' && failed.job.error, "an account the model refuses gets a failed job with the reason");
}

// the accuracy check runs on the server once the writing is done
{
  const store = storage();
  const calls = [];
  const fake = async (url, init) => {
    const body = JSON.parse(init.body);
    calls.push(body);
    const prompt = body.messages.at(-1).content;
    const content = prompt.startsWith('CHECK')
      ? `risk ${prompt.includes('Q2') ? 5 : 1}`
      : '{"questions":[{"stem":"Q1 stem","options":["a","b"],"correctIndex":0,"explanation":"e"},{"stem":"Q2 stem","options":["a","b"],"correctIndex":1,"explanation":"e"}]}';
    return new Response(JSON.stringify({ choices: [{ message: { content } }] }), { status: 200 });
  };
  const object = new GenerationJobs({ storage: store }, env(), fake);
  const spec = checkSpec({ title: 'MCQ', mode: 'loop', extract: 'questions', count: 2, sources: ['Para about Q1\n\nPara about Q2'],
    steps: [{ system: 'Write\n- {{ALREADY}}\n{{SOURCE}}', user: 'Now.', source: 0 }],
    check: { template: 'CHECK\nSOURCE: {{INPUT}}\nOUTPUT: {{OUTPUT}}' } }).spec;
  const made = await (await object.create({ accountId: 'owner', owner: true, spec })).json();
  await runAll(object, store);
  const got = await (await object.fetch(new Request(`https://jobs/get?id=${made.job.id}&outputs=1`))).json();
  ok(got.job.status === 'done' && got.job.checked === 2 && got.job.phase === 'checking', 'every question is checked before the job is done');
  ok(calls.filter(c => JSON.stringify(c).includes('CHECK')).length === 2, 'one check per question');
  ok(got.checks.length === 2 && got.checks.find(c => c.key === 'q2 stem').reply === 'risk 5', 'each verdict comes back under its question');
  ok(calls[1].messages[0].content.includes('Answer: A') && calls[1].messages[0].content.includes('Para about Q1'), 'the checker sees the question as the app writes it, and the lecture');
}

// the checker is never the model that wrote the work, while another is left
{
  const all = ['gemini-3.1-pro-preview', 'gemini-3.5-flash', 'gemini-3.5-flash-lite', 'gemma-4-31b-it'];
  ok(checkerOrder({}, all, ['gemini-3.1-pro-preview'])[0] === 'gemini-3.5-flash', 'Pro wrote it: 3.5 Flash checks');
  ok(checkerOrder({}, all, ['gemini-3.5-flash'])[0] === 'gemini-3.1-pro-preview', 'Flash wrote it: 3.1 Pro checks');
  ok(!checkerOrder({}, all.slice(1), ['gemini-3.5-flash']).includes('gemini-3.5-flash'), 'the writer is left out of the checker chain');
  ok(checkerOrder({}, ['gemma-4-31b-it'], ['gemma-4-31b-it']).length === 1, 'with nothing else left, the one model still checks');
}

// a job's replies are as long as it asked for
{
  const store = storage();
  let sent;
  const fake = async (url, init) => { sent = JSON.parse(init.body);
    return new Response(JSON.stringify({ choices: [{ message: { content: 'Q | A' } }] }), { status: 200 }); };
  const object = new GenerationJobs({ storage: store }, env(), fake);
  const spec = checkSpec({ title: 'C', mode: 'loop', extract: 'lines', count: 1, steps: [{ user: 'Write.', maxTokens: 3800 }] }).spec;
  await object.create({ accountId: 'owner', owner: true, spec });
  await runAll(object, store);
  ok(sent.max_tokens === 3800, 'a step asking for 3,800 tokens is sent 3,800, not cut to 2,000');
}

// cancelled while its model call was out: nothing of that call is kept
{
  const store = storage();
  let object, id;
  const fake = async (url, init) => {
    await object.fetch(new Request(`https://jobs/cancel?id=${id}`, { method: 'POST' }));
    return new Response(JSON.stringify({ choices: [{ message: { content: '{"questions":[{"stem":"S","options":["a","b"],"correctIndex":0}]}' } }] }), { status: 200 });
  };
  object = new GenerationJobs({ storage: store }, env(), fake);
  const spec = checkSpec({ title: 'MCQ', mode: 'loop', extract: 'questions', count: 3, sources: ['L'], steps: [{ user: 'Write {{SOURCE}}', source: 0 }],
    check: { template: 'CHECK {{INPUT}} {{OUTPUT}}' } }).spec;
  id = (await (await object.create({ accountId: 'owner', owner: true, spec })).json()).job.id;
  await runAll(object, store);
  ok(store.map.size === 0, 'a cancel that lands mid-call leaves no reply, queue or keys behind');
}

// a finished job nobody collects is still gone after a week
{
  const store = storage();
  const fake = async () => new Response(JSON.stringify({ choices: [{ message: { content: 'Q | A' } }] }), { status: 200 });
  const object = new GenerationJobs({ storage: store }, env(), fake);
  const spec = checkSpec({ title: 'C', mode: 'loop', extract: 'lines', count: 1, steps: [{ user: 'Write.' }] }).spec;
  await object.create({ accountId: 'owner', owner: true, spec });
  await runAll(object, store);
  const at = await store.getAlarm();
  ok(at > Date.now() + 6 * 86_400_000, 'once it is done, the next alarm is when it expires');
  // a new job does not wait a week for that alarm
  await object.create({ accountId: 'owner', owner: true, spec });
  ok((await store.getAlarm()) < Date.now() + 1000, 'a new job brings the alarm forward and starts at once');
  await runAll(object, store);
  const realNow = Date.now;
  Date.now = () => realNow() + 8 * 86_400_000;
  try { store.clearAlarm(); await object.alarm(); } finally { Date.now = realNow; }
  ok(store.map.size === 0 && !(await store.getAlarm()), 'a week on, the alarm removes it, and sets no other');
}

// an account deleted: its object is emptied
{
  const store = storage();
  const fake = async () => new Response(JSON.stringify({ choices: [{ message: { content: 'Q | A' } }] }), { status: 200 });
  const object = new GenerationJobs({ storage: store }, env(), fake);
  const spec = checkSpec({ title: 'C', mode: 'loop', extract: 'lines', count: 5, steps: [{ user: 'Write.' }] }).spec;
  await object.create({ accountId: 'owner', owner: true, spec });
  await object.fetch(new Request('https://jobs/wipe', { method: 'POST' }));
  ok(store.map.size === 0 && !(await store.getAlarm()), '/wipe leaves nothing, and nothing set to wake up');
}

// anything a job left behind without a job to point at it is swept
{
  const store = storage();
  const object = new GenerationJobs({ storage: store }, env(), async () => new Response('{}'));
  await store.put({ 'out:00000000-0000-0000-0000-000000000000:0': 'old reply', 'keys:00000000-0000-0000-0000-000000000000': [] });
  await store.setAlarm(Date.now());
  store.clearAlarm();
  await object.alarm();
  ok(store.map.size === 0, 'orphaned replies from an old cancel are removed');
}

// a running job whose alarm was lost starts again when the app asks after it; one lost a day ago ends
{
  const store = storage();
  const fake = async () => new Response(JSON.stringify({ choices: [{ message: { content: 'Q | A' } }] }), { status: 200 });
  const object = new GenerationJobs({ storage: store }, env(), fake);
  const spec = checkSpec({ title: 'C', mode: 'loop', extract: 'lines', count: 1, steps: [{ user: 'Write.' }] }).spec;
  const made = await (await object.create({ accountId: 'owner', owner: true, spec })).json();
  store.clearAlarm();
  await object.fetch(new Request(`https://jobs/get?id=${made.job.id}`));
  ok(await store.getAlarm(), 'asking after a running job with no alarm sets one');
  const job = await store.get(`job:${made.job.id}`);
  job.updated = Date.now() - 2 * 86_400_000;
  await store.put(`job:${made.job.id}`, job);
  store.clearAlarm();
  const other = new GenerationJobs({ storage: store }, env(), async () => { throw new Error('should not be called'); });
  await other.alarm();
  const got = await (await object.fetch(new Request(`https://jobs/get?id=${made.job.id}`))).json();
  ok(got.job.status === 'failed' && got.job.error, 'a job untouched for a day ends instead of holding a place for ever');
}

// a storage write that keeps failing counts as a failure, so the paid call is not made for ever
{
  const store = storage();
  let calls = 0;
  const fake = async () => { calls++; return new Response(JSON.stringify({ choices: [{ message: { content: 'Q | A' } }] }), { status: 200 }); };
  const object = new GenerationJobs({ storage: store }, env(), fake);
  const spec = checkSpec({ title: 'C', mode: 'loop', extract: 'lines', count: 5, steps: [{ user: 'Write.' }] }).spec;
  const made = await (await object.create({ accountId: 'owner', owner: true, spec })).json();
  const put = store.put;
  store.put = async (k, v) => { if (typeof k === 'object' && Object.keys(k).some(x => x.startsWith('out:'))) throw new Error('value too large'); return put(k, v); };
  for (let i = 0; i < 10; i++) { const at = await store.getAlarm(); if (!at || at > Date.now() + 3_600_000) break; store.clearAlarm(); await object.alarm(); }
  const got = await (await object.fetch(new Request(`https://jobs/get?id=${made.job.id}`))).json();
  ok(calls === 4 && got.job.status === 'failed', 'it stops after four tries, not when the day\'s allowance runs out');
}

// the check queue and verdicts are stored item by item, and the checker reads only the item's own window
{
  const store = storage();
  const checks = [];
  const fake = async (url, init) => {
    const prompt = JSON.parse(init.body).messages.at(-1).content;
    if (prompt.startsWith('CHECK')) { checks.push(prompt); return new Response(JSON.stringify({ choices: [{ message: { content: 'risk 1' } }] })); }
    const n = prompt.includes('WINDOW TWO') ? 2 : 1;
    return new Response(JSON.stringify({ choices: [{ message: { content: `{"questions":[{"stem":"Stem ${n}","options":["a","b"],"correctIndex":0}]}` } }] }));
  };
  const object = new GenerationJobs({ storage: store }, env(), fake);
  const spec = checkSpec({ title: 'MCQ', mode: 'loop', extract: 'questions', count: 2, sources: ['WINDOW ONE text', 'WINDOW TWO text'],
    steps: [{ user: '{{SOURCE}}', source: 0 }, { user: '{{SOURCE}}', source: 1 }], check: { template: 'CHECK {{INPUT}} | {{OUTPUT}}' } }).spec;
  const made = await (await object.create({ accountId: 'owner', owner: true, spec })).json();
  let pendKeys = 0;
  const put = store.put;
  store.put = async (k, v) => { if (typeof k === 'object') pendKeys += Object.keys(k).filter(x => /^pend:.+:\d+$/.test(x)).length; return put(k, v); };
  await runAll(object, store);
  const got = await (await object.fetch(new Request(`https://jobs/get?id=${made.job.id}&outputs=1`))).json();
  ok(pendKeys === 2 && got.checks.length === 2, 'each queued item and verdict is its own stored value');
  ok(checks.find(c => c.includes('Stem 2')).includes('WINDOW TWO') && !checks.find(c => c.includes('Stem 2')).includes('WINDOW ONE'),
     'a question is checked against the window it was written from');
}

// stopped early by the day's allowance: done, but marked partial with the reason, and checked as far as it can be
{
  const store = storage();
  let n = 0;
  const fake = async (url, init) => {
    const prompt = JSON.parse(init.body).messages.at(-1).content;
    if (prompt.startsWith('CHECK')) return new Response(JSON.stringify({ choices: [{ message: { content: 'risk 1' } }] }));
    n++;
    return new Response(JSON.stringify({ choices: [{ message: { content: `{"questions":[{"stem":"Stem ${n}","options":["a","b"],"correctIndex":0}]}` } }] }));
  };
  const e = { ...env(), OWNER_DAILY_LIMIT: '2' };
  const object = new GenerationJobs({ storage: store }, e, fake);
  const spec = checkSpec({ title: 'MCQ', mode: 'loop', extract: 'questions', count: 10, steps: [{ user: 'Write.' }],
    check: { template: 'CHECK {{INPUT}} {{OUTPUT}}' } }).spec;
  const made = await (await object.create({ accountId: 'owner', owner: true, spec })).json();
  await runAll(object, store);
  const got = await (await object.fetch(new Request(`https://jobs/get?id=${made.job.id}&outputs=1`))).json();
  ok(got.job.status === 'done' && got.job.partial === true && got.job.done === 2 && /cloud requests/.test(got.job.reason),
     'two of ten written, then the allowance: done, partial, and why');
  ok(got.job.phase === 'checking' && got.job.checkError, 'the check was tried, and says why it could not run');
}

console.log(failures ? `\n${failures} failed` : '\nall passed');
process.exit(failures ? 1 : 0);
