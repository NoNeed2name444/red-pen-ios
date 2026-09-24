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

// ---------- living within the free limits ----------
//
// Google: the limits are not published; each 429 names the one that was hit
// ("[quota ...PerMinute...=15; retry 20s]" or "...PerDay...=20"). A per-minute
// limit is waited out; a per-day one stops that model until tomorrow.
// Cloudflare Workers AI: 10,000 neurons a day for the whole account, reset at
// 00:00 UTC, priced per model per million tokens (developers.cloudflare.com/
// workers-ai/platform/pricing). Each run gets a share (NEURONS) and spends it
// across the Workers AI models by their published rates.
const NEURONS = Number(process.env.NEURONS || 4500);
export const NEURON_RATES = {   // neurons per million tokens: [input, output]
  '@cf/meta/llama-4-scout-17b-16e-instruct': [24545, 77273],
  '@cf/openai/gpt-oss-120b': [31818, 68182],
  '@cf/nvidia/nemotron-3-120b-a12b': [45455, 136364],
  '@cf/qwen/qwq-32b': [60000, 90909],
  '@cf/google/gemma-4-26b-a4b-it': [9091, 27273],
};

/// 'day' (stop until tomorrow), 'minute' (wait and go on), or null.
export function limitKind(message) {
  const m = String(message || '');
  if (/PerDay|4006|daily free allocation|per day/i.test(m)) return 'day';
  if (/PerMinute|per minute|RESOURCE_EXHAUSTED|exceeded your current quota|overloaded|rate limit/i.test(m)) return 'minute';
  return null;
}

/// How long Google asked to wait, in seconds (20 when it didn't say).
export function waitFor(message) {
  const m = String(message || '').match(/retry (\d+(?:\.\d+)?)s/);
  return m ? Math.min(90, Math.ceil(Number(m[1]))) : 20;
}

/// Roughly what one check costs in neurons: a characters-to-tokens estimate
/// of the prompt, and the answer's length (reasoning models write more).
export function neuronsFor(model, promptChars, answerChars) {
  const rate = NEURON_RATES[model.replace(/^workers-ai:/, '')];
  if (!rate) return 0;
  const tokensIn = promptChars / 4;
  const tokensOut = Math.max(answerChars / 4, 300);
  return (tokensIn * rate[0] + tokensOut * rate[1]) / 1_000_000;
}

const limitsSeen = {};

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
  let waits = 0;
  for (let attempt = 0; attempt < 3; attempt++) {
    let r;
    try { r = await fetch(`${WORKER}/v1/chat/completions`, {
      method: 'POST',
      // one stuck provider must not hold the whole comparison
      signal: AbortSignal.timeout(150_000),
      headers: { 'content-type': 'application/json', authorization: `Bearer ${KEY}` },
      body: JSON.stringify({ model: 'cramdown-checker', use, max_tokens: 900, temperature: 0, messages: [{ role: 'user', content }] }),
    }); } catch (error) {
      if (attempt === 2) return { error: `no answer: ${String(error?.name || error).slice(0, 80)}` };
      continue;
    }
    const j = await r.json().catch(() => ({}));
    if (r.ok) return { text: j.choices?.[0]?.message?.content || '', ms: Date.now() - started };
    const message = String(j.message || '');
    const kind = r.status === 429 || /quota|4006|RESOURCE_EXHAUSTED/i.test(message) ? (limitKind(message) || 'minute') : null;
    if (kind) {
      const named = message.match(/\[quota [^\]]+\]/);
      if (named) limitsSeen[use] = named[0];
      else if (/4006|daily free allocation/i.test(message)) limitsSeen['workers-ai'] = 'Workers AI: 10,000 neurons a day (account-wide)';
      // today's allowance is gone: stop; a per-minute limit: wait it out
      if (kind === 'day') return { error: `quota: ${message.slice(0, 200)}`, quota: 'day' };
      if (waits >= 8) return { error: `quota: still limited after 8 waits: ${message.slice(0, 160)}`, quota: 'day' };
      waits++;
      await new Promise(res => setTimeout(res, waitFor(message) * 1000));
      attempt--;
      continue;
    }
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
  const workersModels = MODELS.filter(m => m.startsWith('workers-ai:'));
  const neuronShare = workersModels.length ? NEURONS / workersModels.length : 0;
  let workersDone = false;
  await Promise.all(MODELS.map(async model => {
    let calls = 0;
    let spent = 0;
    const cap = CAPS[model] ?? Infinity;
    for (const q of qs) for (const kase of CASES) {
      if (done.has(`${model}|${q.index}|${kase}`)) continue;
      if (calls >= cap) { notes[model] = `stopped at today's cap of ${cap} calls`; return; }
      const isWorkers = model.startsWith('workers-ai:');
      if (isWorkers && workersDone) { notes[model] = 'stopped: Workers AI daily neurons used up'; return; }
      if (isWorkers && spent >= neuronShare) { notes[model] = `stopped at its share of today's neurons (~${Math.round(spent)} of ${Math.round(neuronShare)})`; return; }
      calls++;
      const text = prompt(q, kase);
      const reply = await check(model, text);
      if (reply.error) {
        results.push({ model, index: q.index, case: kase, risk: null, error: reply.error });
        if (reply.quota) {
          if (isWorkers) workersDone = true;
          notes[model] = `stopped: today's free limit reached ${limitsSeen[model] || limitsSeen['workers-ai'] || ''}`.trim();
          return;
        }
        continue;
      }
      if (isWorkers) spent += neuronsFor(model, text.length, reply.text.length);
      results.push({ model, index: q.index, case: kase, risk: riskFrom(reply.text), ms: reply.ms });
      process.stdout.write('.');
      // kept as it goes: a run that is stopped still leaves what it measured
      if (results.length % 10 === 0) writeFileSync(REPORT.replace(/\.md$/, '.json'), JSON.stringify(results, null, 1));
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
    ``, `## Free limits met`, ``,
    ...(Object.keys(limitsSeen).length ? Object.entries(limitsSeen).map(([m, l]) => `- ${m}: ${l}`) : ['- none hit']),
    ``, `## Notes`, ``,
    ...Object.entries(notes).map(([m, n]) => `- ${m}: ${n}`),
    ...[...new Set(results.filter(r => r.error && !/quota/.test(r.error)).map(r => `${r.model}: ${r.error}`))].slice(0, 12).map(e => `- ${e}`),
  ];
  writeFileSync(REPORT, lines.join('\n') + '\n');
  writeFileSync(REPORT.replace(/\.md$/, '.json'), JSON.stringify(results, null, 1));
  console.log('\n' + lines.join('\n'));
}

if (import.meta.url === `file://${process.argv[1]}`) main();
