// The whole verification layer, end to end, on hard real exam questions with
// known answers: the sensors, the literature lookup (Europe PMC, MedlinePlus,
// openFDA), the checker models from different families, the blind re-solve,
// the oath check and the calibrated verdict - server/accuracy.js's checkBatch,
// unchanged. Each question is checked twice: with its true key, and with a
// wrong key planted (a distractor keyed instead). Nothing else is changed, so
// the explanation cannot give the error away: the models have to find it.
//
// Two ways to run it (.github/workflows/verification-bench.yml picks one):
//   live:     WORKER=<url> KEY=<owner key> ... --data DIR --out DIR
//             the deployed Worker checks each batch with its own free models -
//             exactly what students get
//   provider: BENCH_BASE_URL=<OpenAI-compatible url> BENCH_API_KEY=<key> ...
//             --voters bench:<model>,bench:<model>,... - this repository's
//             checkBatch, run here, with a free provider's models voting
//   options:  [--per-source 30] [--sources MedXpertQA,MedQA,CareQA Medicine] [--seed 7] [--stub]
import { readFileSync, writeFileSync, mkdirSync, readdirSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { DatabaseSync } from 'node:sqlite';
import { checkBatch } from '../../server/accuracy.js';
import { resetBreakers } from '../../server/breakers.js';
import { familyOf } from '../../server/accuracy-model.js';
import { loadQuestions, seeded } from './datasets.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const arg = (name, fallback) => { const i = process.argv.indexOf(`--${name}`); return i >= 0 ? process.argv[i + 1] : fallback; };
const dataDir = arg('data', 'verification-bench-data');
const outDir = arg('out', 'verification-bench-out');
const perSource = Number(arg('per-source', '30'));
const wanted = arg('sources', 'MedXpertQA,MedQA,CareQA Medicine').split(',');
const voters = arg('voters', process.env.BENCH_VOTERS || '').split(',').filter(Boolean);
const perBatch = Number(arg('batch', '2'));
const seed = Number(arg('seed', '7'));
const live = Boolean(process.env.WORKER && process.env.KEY);
const stubbed = process.argv.includes('--stub');
if (!live && !stubbed && !(process.env.BENCH_BASE_URL && process.env.BENCH_API_KEY)) {
  console.error('Set WORKER and KEY (the live Worker), or BENCH_BASE_URL and BENCH_API_KEY (a free provider).'); process.exit(2);
}
if (!live && voters.length < 2) { console.error('give at least two --voters (bench:<model>)'); process.exit(2); }
mkdirSync(outDir, { recursive: true });

// MARK: the questions, right and wrong

const rand = seeded(seed);
const all = loadQuestions(readdirSync(dataDir).filter(f => f.endsWith('.json')).map(f => join(dataDir, f)));
const chosen = [];
for (const src of wanted) {
  const pool = all.filter(q => q.source === src);
  for (let i = pool.length - 1; i > 0; i--) { const j = Math.floor(rand() * (i + 1)); [pool[i], pool[j]] = [pool[j], pool[i]]; }
  chosen.push(...pool.slice(0, perSource));
}
const cases = [];
for (const q of chosen) {
  cases.push({ truth: 'right', item: { ...q, id: `${q.id}#right` } });
  const others = q.options.map((_, i) => i).filter(i => i !== q.key);
  const wrong = others[Math.floor(rand() * others.length)];
  cases.push({ truth: 'wrong', item: { ...q, id: `${q.id}#wrong`, key: wrong } });
}
for (let i = cases.length - 1; i > 0; i--) { const j = Math.floor(rand() * (i + 1)); [cases[i], cases[j]] = [cases[j], cases[i]]; }

// MARK: the Worker's world: an in-memory database, the bench's voters

function d1(db) {
  return {
    prepare(sql) {
      const stmt = db.prepare(sql);
      let args = [];
      const api = {
        bind(...a) { args = a; return api; },
        first: async () => stmt.get(...args) ?? null,
        all: async () => ({ results: stmt.all(...args) }),
        run: async () => { const r = stmt.run(...args); return { meta: { changes: Number(r.changes) } }; },
      };
      return api;
    },
  };
}
const db = new DatabaseSync(':memory:');
const schema = readFileSync(join(here, '..', '..', 'server', 'schema.sql'), 'utf8').split('\n').map(l => l.replace(/--.*$/, '')).join('\n');
for (const statement of schema.split(';')) if (statement.trim()) db.exec(statement);
db.prepare(`INSERT INTO accounts (id, provider, subject, created_at) VALUES ('bench', 'apple', 'bench', 0)`).run();

const sleep = ms => new Promise(r => setTimeout(r, ms));
let modelCalls = 0, throttled = 0, shown = 0;
// free-tier limits answer 429: wait as told and ask again, so a busy minute
// is not scored as a checker that could not answer
// --stub: the plumbing alone, offline - every checker answers the keyed
// letter with no error, the literature finds nothing (for trying the harness)
const stub = stubbed;
const stubReply = init => {
  const isChat = String(init.body || '').includes('"messages"');
  if (!isChat) return new Response('{}', { status: 404 });
  const body = JSON.parse(init.body);
  const n = (body.messages.at(-1).content.match(/### Item /g) || []).length;
  const items = Array.from({ length: n }, (_, i) => ({ i: i + 1, answer: 'A', risk: 1, evidence: 'none', cites: [], issues: [], fix: null }));
  return new Response(JSON.stringify({ choices: [{ message: { content: JSON.stringify({ items }) } }] }), { status: 200 });
};
const fetcher = async (url, init) => {
  if (stub) return String(url).includes('/chat/completions') ? stubReply(init) : new Response('{}', { status: 404 });
  for (let attempt = 0; ; attempt++) {
    const res = await fetch(url, init);
    if (String(url).includes('/chat/completions')) {
      modelCalls++;
      // the first replies, and any refusal, word for word: a run whose every
      // call fails says why
      if (shown < 3 || (res.status !== 200 && shown < 8)) {
        shown++;
        const text = await res.clone().text();
        console.error(`${JSON.parse(init.body).model} -> ${res.status}: ${text.slice(0, 500).replace(/\s+/g, ' ')}`);
      }
    }
    if (res.status !== 429 || attempt >= 5) return res;
    throttled++;
    const wait = Number(res.headers.get('retry-after')) || 20 * (attempt + 1);
    await sleep(Math.min(wait, 120) * 1000);
  }
};

// MARK: run

const results = [];
const started = Date.now();
for (let b = 0; b < cases.length; b += perBatch) {
  const batch = cases.slice(b, b + perBatch);
  resetBreakers();
  // the first voter turns over each batch, so no one model carries the run
  const order = voters.slice((b / perBatch) % voters.length).concat(voters.slice(0, (b / perBatch) % voters.length));
  let res;
  if (live) {
    // the deployed Worker, signed in as the owner, counted apart as a bench
    for (let attempt = 0; ; attempt++) {
      res = await fetch(`${process.env.WORKER.replace(/\/+$/, '')}/accuracy/check`, {
        method: 'POST', headers: { 'content-type': 'application/json', authorization: `Bearer ${process.env.KEY}`, 'x-bench': '1' },
        body: JSON.stringify({ items: batch.map(c => c.item) }),
      });
      modelCalls++;
      const busy = res.status === 429 || res.status === 503;
      if (!busy || attempt >= 4) break;
      throttled++;
      await sleep(30_000 * (attempt + 1));
    }
  } else {
    const env = { DB: d1(db), BENCH_MODELS: 'on', BENCH_BASE_URL: process.env.BENCH_BASE_URL, BENCH_API_KEY: process.env.BENCH_API_KEY,
      ACCURACY_VOTERS: order.join(','), OWNER_ACCOUNT_IDS: 'bench', OWNER_BENCH_DAILY_LIMIT: '100000', ACCURACY_DAILY_CEILING: '100000' };
    res = await checkBatch(env, 'bench', { items: batch.map(c => c.item) }, fetcher,
      { owner: true, bench: true, budgets: { votes: 240_000, evidence: 30_000, jev: 5_000 } });
  }
  const body = await res.json();
  (body.items || []).forEach((r, n) => results.push({ ...batch[n], result: r }));
  if (body.failures) console.error('failures:', body.failures.join(' | '));
  // nobody answered the first batches: stop and say so, rather than spend the run
  if (b >= perBatch * 2 && results.every(r => (r.result?.verdict || 'unchecked') === 'unchecked')) {
    console.error('No checker answered the first batches: stopping. See the replies above.');
    process.exit(1);
  }
  process.stdout.write(`\r${Math.min(b + perBatch, cases.length)}/${cases.length} checked, ${modelCalls} model calls, ${throttled} waits`);
}
console.log('');

// MARK: the measures

const pct = (a, b) => (b ? `${(100 * a / b).toFixed(1)}%` : 'n/a');
const verdictOf = r => r.result?.verdict || 'unchecked';
const by = (list, f) => list.filter(f).length;
function measures(list) {
  const right = list.filter(r => r.truth === 'right'), wrong = list.filter(r => r.truth === 'wrong');
  const verified = list.filter(r => verdictOf(r) === 'verified'), flagged = list.filter(r => verdictOf(r) === 'flagged');
  const committed = verified.length + flagged.length;
  const correctCommitted = by(verified, r => r.truth === 'right') + by(flagged, r => r.truth === 'wrong');
  return {
    items: list.length,
    accuracy: { n: correctCommitted, of: committed, text: pct(correctCommitted, committed) },
    dependability: { n: by(verified, r => r.truth === 'right'), of: verified.length, text: pct(by(verified, r => r.truth === 'right'), verified.length) },
    caught: { n: by(wrong, r => verdictOf(r) !== 'verified'), of: wrong.length, text: pct(by(wrong, r => verdictOf(r) !== 'verified'), wrong.length) },
    rightVerified: { n: by(right, r => verdictOf(r) === 'verified'), of: right.length, text: pct(by(right, r => verdictOf(r) === 'verified'), right.length) },
    rightFlagged: { n: by(right, r => verdictOf(r) === 'flagged'), of: right.length, text: pct(by(right, r => verdictOf(r) === 'flagged'), right.length) },
    binary: { n: by(right, r => verdictOf(r) === 'verified') + by(wrong, r => verdictOf(r) !== 'verified'), of: list.length,
      text: pct(by(right, r => verdictOf(r) === 'verified') + by(wrong, r => verdictOf(r) !== 'verified'), list.length) },
    abstained: { n: by(list, r => verdictOf(r) === 'check'), of: list.length, text: pct(by(list, r => verdictOf(r) === 'check'), list.length) },
    unchecked: by(list, r => verdictOf(r) === 'unchecked'),
  };
}
const overall = measures(results);
const lines = [];
lines.push(`# The verification layer on hard questions`, '');
lines.push(`${chosen.length} real questions (${wanted.map(s => `${s} ${chosen.filter(q => q.source === s).length}`).join(', ')}), each checked with its true key and with a wrong key planted: ${results.length} checks. Checkers: ${live ? `the live Worker's own (${process.env.WORKER})` : voters.join(', ')}. ${modelCalls} ${live ? 'batches sent' : 'model calls'}, ${throttled} rate-limit waits, ${Math.round((Date.now() - started) / 60000)} min.`, '');
lines.push(`| measure | what it means | result |`, `|---|---|---|`);
lines.push(`| accuracy | of the checks that gave a verdict (Verified or Flagged), the share that were right | ${overall.accuracy.text} (${overall.accuracy.n}/${overall.accuracy.of}) |`);
lines.push(`| dependability | of the items marked Verified, the share that really were right | ${overall.dependability.text} (${overall.dependability.n}/${overall.dependability.of}) |`);
lines.push(`| errors caught | wrong keys not marked Verified | ${overall.caught.text} (${overall.caught.n}/${overall.caught.of}) |`);
lines.push(`| right items Verified | correct questions passed | ${overall.rightVerified.text} (${overall.rightVerified.n}/${overall.rightVerified.of}) |`);
lines.push(`| right items Flagged | correct questions wrongly flagged | ${overall.rightFlagged.text} (${overall.rightFlagged.n}/${overall.rightFlagged.of}) |`);
lines.push(`| Check this | left for a person (no verdict either way) | ${overall.abstained.text} |`);
lines.push(`| pass/fail accuracy | Verified only when right, not Verified when wrong, over every check | ${overall.binary.text} |`);
lines.push(`| unchecked | no checker answered | ${overall.unchecked} |`, '');
lines.push(`## By source`, '', `| source | checks | accuracy | dependability | caught | right Verified | Check this |`, `|---|---|---|---|---|---|---|`);
for (const src of wanted) {
  const m = measures(results.filter(r => r.item.source === src));
  lines.push(`| ${src} | ${m.items} | ${m.accuracy.text} | ${m.dependability.text} | ${m.caught.text} | ${m.rightVerified.text} | ${m.abstained.text} |`);
}
// rijal: each checker's own answer against the truth, its reliability as a narrator
const per = {};
for (const r of results) {
  const trueKey = String.fromCharCode(65 + (r.truth === 'right' ? r.item.key : chosen.find(q => `${q.id}#wrong` === r.item.id)?.key ?? -1));
  for (const v of r.result?.votes || []) {
    if (!v.model || !v.answer) continue;
    const p = per[v.model] || (per[v.model] = { family: familyOf(v.model), answered: 0, right: 0, blind: 0, blindRight: 0 });
    p.answered++; if (v.answer === trueKey) p.right++;
    if (v.blind) { p.blind++; if (v.answer === trueKey) p.blindRight++; }
  }
}
lines.push('', `## Each checker's own answers (its reliability as a witness)`, '', `| model | family | answered | right | blind solves right |`, `|---|---|---|---|---|`);
for (const [m, p] of Object.entries(per).sort((a, b) => b[1].answered - a[1].answered)) {
  lines.push(`| ${m} | ${p.family} | ${p.answered} | ${pct(p.right, p.answered)} | ${pct(p.blindRight, p.blind)} |`);
}
writeFileSync(join(outDir, 'report.md'), lines.join('\n') + '\n');
writeFileSync(join(outDir, 'results.json'), JSON.stringify(results.map(r => ({ id: r.item.id, source: r.item.source, truth: r.truth,
  verdict: verdictOf(r), p: r.result?.p, reasons: r.result?.reasons, rules: r.result?.rules, votes: r.result?.votes })), null, 1));
console.log(lines.join('\n'));
