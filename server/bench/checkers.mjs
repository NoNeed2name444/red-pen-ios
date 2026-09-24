// Which model makes the best accuracy checker? Measured, not assumed.
//
// Every model gets the same test questions - MedQA (USMLE, 4 options) or
// MedXpertQA (expert level, 10 options; DATASET=medxpertqa) - each with one
// examiner-set correct answer, shown three ways with MedVAL's rubric - the
// same prompt the app's checker uses:
//
//   (a) the correct answer, with a lecture that agrees     -> should PASS
//   (b) a wrong answer, with a lecture giving the right one -> should FLAG
//   (c) a wrong answer that the lecture states too          -> should FLAG
//       (only the model's own medical knowledge can catch it)
//
// Evidence lookup is off, so this measures each model's own judgement.
// Results accumulate across runs (PREVIOUS, the last run's JSON): free daily
// quotas are small for some models, so each run adds what today allows, and
// every rate carries a 95% Wilson interval that says how far to trust it.
//
// Env: WORKER, KEY (owner key), MODELS ("gemini:gemini-3.5-flash,..."),
//      N (questions per model), CAPS ("gemini:gemini-3.5-flash=6,..." - most
//      calls per model this run), SEED, PREVIOUS, REPORT

import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { sample, wilson, riskFrom, medvalPrompt } from './accuracy.mjs';

const WORKER = (process.env.WORKER || 'https://redpen-auth.vv7sh4rnnw.workers.dev').replace(/\/+$/, '');
const KEY = process.env.KEY || '';
const N = Number(process.env.N || 40);
const SEED = Number(process.env.SEED || 20260924);
const DATASET = process.env.DATASET === 'medxpertqa' ? 'medxpertqa' : 'medqa';
const SETS = {
  medqa: { name: 'MedQA (USMLE)', path: 'GBaker%2FMedQA-USMLE-4-options', config: 'default', rows: 1273 },
  medxpertqa: { name: 'MedXpertQA (Text)', path: 'TsinghuaC3I%2FMedXpertQA', config: 'Text', rows: 2450 },
};
const REPORT = process.env.REPORT || 'checker-report.md';
const PREVIOUS = process.env.PREVIOUS || '';
const MODELS = (process.env.MODELS || '').split(',').map(s => s.trim()).filter(Boolean);
const CAPS = Object.fromEntries((process.env.CAPS || '').split(',').map(s => s.trim()).filter(Boolean)
  .map(s => { const at = s.lastIndexOf('='); return [s.slice(0, at), Number(s.slice(at + 1))]; }));

export const CASES = ['correct', 'wrongVsCorrect', 'wrongEverywhere'];

/// Pass/flag rates for one model's results, each with its interval.
export function score(results) {
  const of = kase => results.filter(r => r.case === kase && r.risk !== null);
  const passed = of('correct').filter(r => r.risk <= 2).length;
  const b = of('wrongVsCorrect'), c = of('wrongEverywhere');
  const flaggedB = b.filter(r => r.risk >= 3).length, flaggedC = c.filter(r => r.risk >= 3).length;
  const spec = of('correct').length ? passed / of('correct').length : 0;
  const sensB = b.length ? flaggedB / b.length : 0, sensC = c.length ? flaggedC / c.length : 0;
  return {
    specificity: [passed, of('correct').length],
    catchWithLecture: [flaggedB, b.length],
    catchByKnowledge: [flaggedC, c.length],
    // one number to rank by: the three rates weighted equally
    balanced: (spec + sensB + sensC) / 3,
    unreadable: results.filter(r => r.risk === null && !r.error).length,
    failed: results.filter(r => r.error).length,
  };
}

/// One question in the shape both datasets are used in: stem, options by
/// letter, the right letter.
export function normalise(dataset, index, row) {
  if (dataset === 'medxpertqa') {
    const options = Object.fromEntries(Object.entries(row.options || {}).filter(([, v]) => typeof v === 'string' && v.trim()));
    // the options are also written into the question; they are shown once
    const stem = String(row.question).split(/\nAnswer Choices:/)[0].trim();
    return { index, question: stem, options, answer_idx: String(row.label).trim() };
  }
  return { index, question: row.question, options: row.options, answer_idx: row.answer_idx };
}

async function rows(indices) {
  const out = [];
  const set = SETS[DATASET];
  for (const i of indices) {
    const url = `https://datasets-server.huggingface.co/rows?dataset=${set.path}&config=${set.config}&split=test&offset=${i}&length=1`;
    for (let attempt = 0; attempt < 4; attempt++) {
      const r = await fetch(url);
      if (r.ok) { const j = await r.json(); out.push(normalise(DATASET, i, j.rows[0].row)); break; }
      await new Promise(res => setTimeout(res, 1500 * (attempt + 1)));
    }
  }
  return out;
}

async function check(use, content) {
  const started = Date.now();
  for (let attempt = 0; attempt < 3; attempt++) {
    const r = await fetch(`${WORKER}/v1/chat/completions`, {
      method: 'POST',
      headers: { 'content-type': 'application/json', authorization: `Bearer ${KEY}` },
      body: JSON.stringify({ model: 'cramdown-checker', use, max_tokens: 900, temperature: 0, messages: [{ role: 'user', content }] }),
    });
    const j = await r.json().catch(() => ({}));
    if (r.ok) return { text: j.choices?.[0]?.message?.content || '', ms: Date.now() - started };
    // out of today's quota: stop this model for today rather than burn retries
    if (r.status === 429 || /quota|RESOURCE_EXHAUSTED|daily/i.test(j.message || '')) return { error: `quota: ${(j.message || '').slice(0, 160)}`, quota: true };
    if (![500, 502, 503, 504].includes(r.status) || attempt === 2) return { error: `${r.status}: ${(j.message || '').slice(0, 200)}` };
    await new Promise(res => setTimeout(res, 5000 * (attempt + 1)));
  }
}

const question = q => `${q.question}\n\n${Object.entries(q.options).map(([l, t]) => `${l}. ${t}`).join('\n')}`;
const stated = (q, l) => `${question(q)}\n\nCorrect answer: ${l}. ${q.options[l]}`;
const INSTRUCTION = 'Write a single-best-answer exam question with its correct answer, from the source.';

function prompt(q, kase) {
  const others = Object.keys(q.options).filter(l => l !== q.answer_idx);
  const wrong = others[q.index % others.length];
  if (kase === 'correct') return medvalPrompt(INSTRUCTION, stated(q, q.answer_idx), stated(q, q.answer_idx));
  if (kase === 'wrongVsCorrect') return medvalPrompt(INSTRUCTION, stated(q, q.answer_idx), stated(q, wrong));
  return medvalPrompt(INSTRUCTION, stated(q, wrong), stated(q, wrong));
}

const pct = x => `${(100 * x).toFixed(0)}%`;
const rate = ([k, n]) => { if (!n) return '—'; const [lo, hi] = wilson(k, n); return `${pct(k / n)} (${k}/${n}; ${pct(lo)}–${pct(hi)})`; };

async function main() {
  if (!KEY) { console.error('KEY (owner key) is required'); process.exit(2); }
  const previous = PREVIOUS && existsSync(PREVIOUS) ? JSON.parse(readFileSync(PREVIOUS, 'utf8')) : [];
  const done = new Set(previous.filter(r => !r.error).map(r => `${r.model}|${r.index}|${r.case}`));
  const results = previous.filter(r => !r.error);
  const qs = await rows(sample(SETS[DATASET].rows, N, SEED));
  console.log(`${qs.length} questions, ${MODELS.length} models, ${results.length} results carried over`);
  const notes = {};

  // models side by side, each at its own pace; within a model one call at a time
  await Promise.all(MODELS.map(async model => {
    let calls = 0;
    const cap = CAPS[model] ?? Infinity;
    for (const q of qs) for (const kase of CASES) {
      if (done.has(`${model}|${q.index}|${kase}`)) continue;
      if (calls >= cap) { notes[model] = `stopped at today's cap of ${cap} calls`; return; }
      calls++;
      const reply = await check(model, prompt(q, kase));
      if (reply.error) {
        results.push({ model, index: q.index, case: kase, risk: null, error: reply.error });
        if (reply.quota) { notes[model] = 'stopped: free quota used up for today'; return; }
        continue;
      }
      results.push({ model, index: q.index, case: kase, risk: riskFrom(reply.text), ms: reply.ms });
      process.stdout.write('.');
    }
  }));

  const table = MODELS.map(model => {
    const mine = results.filter(r => r.model === model);
    const s = score(mine);
    const times = mine.filter(r => r.ms).map(r => r.ms).sort((a, b) => a - b);
    const median = times.length ? `${(times[Math.floor(times.length / 2)] / 1000).toFixed(1)} s` : '—';
    return { model, s, median, questions: new Set(mine.filter(r => r.risk !== null).map(r => r.index)).size };
  }).sort((a, b) => b.s.balanced - a.s.balanced);

  const lines = [
    `# Accuracy checker comparison: ${SETS[DATASET].name}`, ``,
    `${new Date().toISOString().slice(0, 16)} UTC · ${SETS[DATASET].name} test questions, seed ${SEED}, up to ${N} per model · MedVAL's rubric, the app's own checker prompt · evidence lookup off (each model's own judgement).`, ``,
    `A good checker **passes** correct answers and **flags** wrong ones (risk 3–4). Percentages with 95% intervals; a wide interval means too few questions yet to be sure - results add up over runs.`, ``,
    `| Model | Questions | Passes correct | Catches wrong (lecture right) | Catches wrong (lecture also wrong) | Balanced | Median time | Unreadable / failed |`,
    `|---|---|---|---|---|---|---|---|`,
    ...table.map(({ model, s, median, questions }) =>
      `| ${model} | ${questions} | ${rate(s.specificity)} | ${rate(s.catchWithLecture)} | ${rate(s.catchByKnowledge)} | ${pct(s.balanced)} | ${median} | ${s.unreadable} / ${s.failed} |`),
    ``, `## Notes`, ``,
    ...Object.entries(notes).map(([m, n]) => `- ${m}: ${n}`),
    ...[...new Set(results.filter(r => r.error && !/quota/.test(r.error)).map(r => `${r.model}: ${r.error}`))].slice(0, 12).map(e => `- ${e}`),
  ];
  writeFileSync(REPORT, lines.join('\n') + '\n');
  writeFileSync(REPORT.replace(/\.md$/, '.json'), JSON.stringify(results, null, 1));
  console.log('\n' + lines.join('\n'));
}

if (import.meta.url === `file://${process.argv[1]}`) main();
