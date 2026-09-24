// Background generation jobs: what a phone may hand over, and a job run to
// the end on a fake storage and a fake model - repeats dropped, the list of
// what is written fed back into the next prompt, pages kept in order.
//
// Run: node server/tests/jobs.test.mjs

import { DatabaseSync } from 'node:sqlite';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { checkSpec, fill, itemsIn, GenerationJobs } from '../jobs.js';

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
    clearAlarm() { alarm = null; },
  };
}
async function runAll(object, store, limit = 50) {
  for (let i = 0; i < limit && await store.getAlarm(); i++) { store.clearAlarm(); await object.alarm(); }
}

// what is refused at the door
ok(checkSpec({ mode: 'loop', extract: 'lines', steps: [] }).error, 'a job with no prompts is refused');
ok(checkSpec({ mode: 'x', extract: 'lines', steps: [{ user: 'a' }] }).error, 'an unknown mode is refused');
ok(checkSpec({ mode: 'loop', extract: 'lines', steps: [{ user: 'a', source: 2 }], sources: ['s'] }).error, 'a prompt naming a missing source is refused');
ok(checkSpec({ mode: 'loop', extract: 'lines', steps: [{ user: 'x'.repeat(70_000) }] }).error, 'an oversized prompt is refused');
ok(checkSpec({ mode: 'loop', extract: 'lines', count: 10, steps: [{ user: 'a', maxTokens: 1e9 }] }).spec.steps[0].maxTokens === 8000, 'tokens are capped');

// placeholders
ok(fill('SOURCE:\n{{SOURCE}}', 'the lecture', []) === 'SOURCE:\nthe lecture', 'the source goes in');
ok(fill('Done:\n- {{ALREADY}}\nend', '', ['a', 'b']) === 'Done:\n- a\n- b\nend', 'what is written is listed with the line\'s prefix');
ok(fill('- {{ALREADY}}', '', []) === '- (none yet)', 'an empty list says so');

// reading replies
const lines = itemsIn('1. Q one | A one\nnot a card\n- Q two | A two\n{{c1::cloze}} line', { extract: 'lines', minFields: 2, keyFields: 1, cloze: true });
ok(lines.length === 3 && lines[0].key === 'Q one', 'card lines are read, numbering stripped');
const qs = itemsIn('Here: {"questions":[{"stem":"A man of 60","options":["x","y"],"correctIndex":1,"explanation":"e"}]}', { extract: 'questions' });
ok(qs.length === 1 && qs[0].key.includes('[answer: y]'), 'questions are read from JSON with their answer');

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
  await object.fetch(new Request(`https://jobs/cancel?id=${made.job.id}`, { method: 'POST' }));
  ok(store.map.size === 0, 'a collected job leaves nothing behind');
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

console.log(failures ? `\n${failures} failed` : '\nall passed');
process.exit(failures ? 1 : 0);
