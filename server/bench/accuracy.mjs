// Is CramDown Cloud medically accurate? Measured, not assumed.
//
// Questions: USMLE-style MCQs from MedQA's test split (GBaker/MedQA-USMLE-4-
// options on Hugging Face), each with one known correct answer written by
// examiners. A fixed random sample, so runs are comparable.
//
// Three measurements, all through the deployed worker exactly as the app
// reaches it (owner key), with the official-source evidence switched on:
//
//   1. Answering: the model answers each question with the evidence in hand.
//   2. Checking:  the grounded checker (MedVAL rubric + evidence) is shown
//        (a) the correct answer                  - it should pass it
//        (b) a wrong answer, against a correct "lecture" - it should flag it
//        (c) a wrong answer that the "lecture" also states - it should still
//            flag it: the case only the evidence can catch
//   3. The pipeline the app runs: an answer is shown only if the checker
//      passes it. "Accuracy of what the student sees" is the share of shown
//      answers that are correct - the number that has to reach 98%.
//
// Every rate comes with a 95% Wilson interval: 98% measured on 50 questions
// is not 98% proven, and the report says so.
//
// Env: WORKER (base URL), KEY (owner key), N (questions, default 150),
//      SEED, CONCURRENCY, REPORT (markdown path), TARGET (default 0.98)

import { writeFileSync } from 'node:fs';
import { limitKind, waitFor } from './checkers.mjs';

const WORKER = (process.env.WORKER || 'https://redpen-auth.vv7sh4rnnw.workers.dev').replace(/\/+$/, '');
const KEY = process.env.KEY || '';
const N = Number(process.env.N || 150);
const SEED = Number(process.env.SEED || 20260923);
const CONCURRENCY = Number(process.env.CONCURRENCY || 3);
const TARGET = Number(process.env.TARGET || 0.98);
const REPORT = process.env.REPORT || 'accuracy-report.md';

// ---------- small pure helpers (tested in tests/bench.test.mjs) ----------

export function rng(seed) {
  let a = seed >>> 0;
  return () => { a = (a + 0x6D2B79F5) >>> 0; let t = a; t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61); return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
}

export function sample(total, n, seed) {
  const r = rng(seed); const picked = new Set();
  while (picked.size < Math.min(n, total)) picked.add(Math.floor(r() * total));
  return [...picked].sort((a, b) => a - b);
}

export function wilson(k, n, z = 1.96) {
  if (!n) return [0, 0];
  const p = k / n, d = 1 + z * z / n;
  const c = (p + z * z / (2 * n)) / d, h = (z * Math.sqrt(p * (1 - p) / n + z * z / (4 * n * n))) / d;
  return [Math.max(0, c - h), Math.min(1, c + h)];
}

export function letterFrom(reply) {
  const text = String(reply);
  try {
    const j = JSON.parse(text.slice(text.indexOf('{'), text.lastIndexOf('}') + 1));
    if (/^[A-D]$/i.test(String(j.answer).trim())) return String(j.answer).trim().toUpperCase();
  } catch {}
  const m = text.match(/\b(?:answer|option)\s*(?:is|:)?\s*\(?([A-D])\)?\b/i) || text.match(/^\s*\(?([A-D])[).:]/m);
  return m ? m[1].toUpperCase() : null;
}

/// MedVAL's risk level out of a checker reply (the same parse the app uses).
export function riskFrom(reply) {
  const m = String(reply).match(/\[\[ ## risk_level ## \]\]\s*\n?\s*(?:Level\s*)?([1-4])/i)
    || String(reply).match(/risk[_ ]level[^0-9]{0,20}([1-4])/i);
  return m ? Number(m[1]) : null;
}

export function medvalPrompt(instruction, input, output) {
  return `Your objective is to evaluate the output in comparison to the input composed by an expert.

Instructions:
1. Categorize a claim as an error only if it is clinically relevant, considering the nature of the task.
2. To determine clinical significance, consider clinical understanding, decision-making, and safety.

Your output fields are:
1. \`reasoning' (str)
2. \`errors' (str): numbered as Error 1: ..., or None.
3. \`risk_level' (Literal[1, 2, 3, 4]): 1 no risk, 2 low, 3 moderate (could affect clinical interpretation), 4 high (incorrect or unsafe).

[[ ## instruction ## ]]
${instruction}

[[ ## input ## ]]
${input}

[[ ## output ## ]]
${output}

[[ ## reasoning ## ]]
# TO_BE_FILLED_BY_MODEL

[[ ## errors ## ]]
# TO_BE_FILLED_BY_MODEL

[[ ## risk_level ## ]]
# TO_BE_FILLED_BY_MODEL`;
}

// ---------- the run ----------

async function rows(indices) {
  const out = [];
  for (const i of indices) {
    const url = `https://datasets-server.huggingface.co/rows?dataset=GBaker%2FMedQA-USMLE-4-options&config=default&split=test&offset=${i}&length=1`;
    for (let attempt = 0; attempt < 4; attempt++) {
      const r = await fetch(url);
      if (r.ok) { const j = await r.json(); out.push({ index: i, ...j.rows[0].row }); break; }
      await new Promise(res => setTimeout(res, 1500 * (attempt + 1)));
    }
  }
  return out;
}

// The free limits: a per-minute limit is waited out (as long as the server
// asks), a per-day one ends the run with what it has, reported as such.
let dayLimit = null;

async function ask(model, content, { ground = true, maxTokens = 700 } = {}) {
  if (dayLimit) return { error: `skipped: ${dayLimit}` };
  let waits = 0;
  for (let attempt = 0; attempt < 4; attempt++) {
    let r, j;
    try {
      r = await fetch(`${WORKER}/v1/chat/completions`, {
        method: 'POST', signal: AbortSignal.timeout(150_000),
        headers: { 'content-type': 'application/json', authorization: `Bearer ${KEY}` },
        body: JSON.stringify({ model, ground, max_tokens: maxTokens, temperature: 0, messages: [{ role: 'user', content }] }),
      });
      j = await r.json().catch(() => ({}));
    } catch (e) {
      if (attempt === 3) return { error: `timeout: ${e.message}`.slice(0, 200) };
      continue;
    }
    if (r.ok) return { text: j.choices?.[0]?.message?.content || '', source: j.source || '?', evidence: j.evidence || [] };
    const message = `${r.status}: ${j.message || ''}`;
    const kind = r.status === 429 ? (limitKind(message) || 'minute') : limitKind(message);
    if (kind === 'day') { dayLimit ||= message.slice(0, 200); return { error: message.slice(0, 200) }; }
    if (kind === 'minute' && waits < 8) {
      waits++; attempt--;
      await new Promise(res => setTimeout(res, waitFor(message) * 1000));
      continue;
    }
    if (![429, 500, 502, 503, 504].includes(r.status) || attempt === 3) return { error: message.slice(0, 200) };
    await new Promise(res => setTimeout(res, 4000 * (attempt + 1)));
  }
}

const question = q => `${q.question}\n\nA. ${q.options.A}\nB. ${q.options.B}\nC. ${q.options.C}\nD. ${q.options.D}`;

async function one(q) {
  const wrong = ['A', 'B', 'C', 'D'].filter(l => l !== q.answer_idx)[q.index % 3];
  const stated = l => `${question(q)}\n\nCorrect answer: ${l}. ${q.options[l]}`;
  const answered = await ask('cramdown-writer',
    `Answer this USMLE question. Think it through, then reply with JSON only: {"answer":"A|B|C|D","reason":"one or two sentences"}.\n\n${question(q)}`);
  const pick = answered.text ? letterFrom(answered.text) : null;
  const check = (input, output) => ask('cramdown-checker',
    medvalPrompt('Write a single-best-answer exam question with its correct answer, from the source.', input, output), { maxTokens: 900 });
  const [a, b, c, own] = await Promise.all([
    check(stated(q.answer_idx), stated(q.answer_idx)),   // correct: should pass
    check(stated(q.answer_idx), stated(wrong)),          // wrong vs correct lecture: flag
    check(stated(wrong), stated(wrong)),                 // wrong in lecture too: flag (evidence)
    pick ? check(question(q), stated(pick)) : Promise.resolve({ error: 'no answer' }), // the pipeline
  ]);
  const risk = x => (x && x.text ? riskFrom(x.text) : null);
  return {
    index: q.index, key: q.answer_idx, pick, wrong,
    answerSource: answered.source, error: answered.error,
    evidence: answered.evidence?.length || 0,
    risk: { correct: risk(a), wrongVsCorrect: risk(b), wrongEverywhere: risk(c), own: risk(own) },
    checkErrors: [a, b, c, own].filter(x => x?.error).map(x => x.error),
    reason: (answered.text || '').slice(0, 300),
    stem: q.question.slice(0, 220),
  };
}

async function pool(items, worker, width) {
  const out = []; let next = 0;
  await Promise.all(Array.from({ length: width }, async () => {
    while (next < items.length && !dayLimit) { const i = next++; out[i] = await worker(items[i]); process.stdout.write('.');
      writeFileSync(REPORT.replace(/\.md$/, '.json'), JSON.stringify(out.filter(Boolean), null, 1)); }
  }));
  return out;
}

const pct = x => `${(100 * x).toFixed(1)}%`;
const ci = (k, n) => { const [lo, hi] = wilson(k, n); return `${pct(n ? k / n : 0)} (${k}/${n}; 95% CI ${pct(lo)}–${pct(hi)})`; };

async function main() {
  if (!KEY) { console.error('KEY (owner key) is required'); process.exit(2); }
  const indices = sample(1273, N, SEED);
  const qs = await rows(indices);
  console.log(`${qs.length} questions loaded`);
  const results = (await pool(qs, one, CONCURRENCY)).filter(Boolean);

  const answered = results.filter(r => r.pick);
  const correct = answered.filter(r => r.pick === r.key);
  const passed = r => r !== null && r <= 2;
  const flagged = r => r !== null && r >= 3;
  const aSet = results.filter(r => r.risk.correct !== null);
  const bSet = results.filter(r => r.risk.wrongVsCorrect !== null);
  const cSet = results.filter(r => r.risk.wrongEverywhere !== null);
  const shown = answered.filter(r => passed(r.risk.own));
  const shownRight = shown.filter(r => r.pick === r.key);
  const [shownLow] = wilson(shownRight.length, shown.length);
  const sources = {};
  for (const r of results) sources[r.answerSource || 'error'] = (sources[r.answerSource || 'error'] || 0) + 1;

  const verdict = shown.length === 0 ? 'NO RESULT'
    : shownLow >= TARGET ? `PASS — the lower end of the 95% interval is at or above ${pct(TARGET)}`
    : shownRight.length / shown.length >= TARGET ? `NOT PROVEN — measured at or above ${pct(TARGET)}, but the sample is too small to be sure; run with a larger N`
    : `FAIL — below ${pct(TARGET)}`;

  const lines = [
    `# CramDown Cloud medical accuracy benchmark`, ``,
    `${new Date().toISOString().slice(0, 16)} UTC · ${results.length} MedQA (USMLE) test questions, seed ${SEED} · evidence from Europe PMC, MedlinePlus and openFDA on every call.`, ``,
    `Models that answered: ${Object.entries(sources).map(([k, v]) => `${k} ×${v}`).join(', ')}.`, ``,
    `## The number that matters`, ``,
    `**Accuracy of the answers a student would see** (answered, then passed by the grounded checker): ${ci(shownRight.length, shown.length)}`, ``,
    `Target ${pct(TARGET)}: **${verdict}**`, ``,
    `Answers withheld by the checker: ${answered.length - shown.length} of ${answered.length} (${pct(answered.length ? (answered.length - shown.length) / answered.length : 0)}).`, ``,
    `## Each part`, ``,
    `| Measurement | Result |`, `|---|---|`,
    `| Answering with evidence (raw) | ${ci(correct.length, answered.length)} |`,
    `| Checker passes a correct answer (specificity) | ${ci(aSet.filter(r => passed(r.risk.correct)).length, aSet.length)} |`,
    `| Checker flags a wrong answer against a correct lecture | ${ci(bSet.filter(r => flagged(r.risk.wrongVsCorrect)).length, bSet.length)} |`,
    `| Checker flags a wrong answer the lecture also states (evidence only) | ${ci(cSet.filter(r => flagged(r.risk.wrongEverywhere)).length, cSet.length)} |`,
    `| Questions with official-source evidence found | ${results.filter(r => r.evidence > 0).length}/${results.length} |`,
    `| Calls that failed | ${results.reduce((s, r) => s + r.checkErrors.length + (r.error ? 1 : 0), 0)} |`, ``,
    `## Wrong answers that got through`, ``,
    ...shown.filter(r => r.pick !== r.key).slice(0, 15).map(r =>
      `- Q${r.index}: picked **${r.pick}**, key **${r.key}** (checker risk ${r.risk.own}). _${r.stem}…_ — model said: ${r.reason.replace(/\n/g, ' ')}`),
    shown.every(r => r.pick === r.key) ? '_None._' : '', ``,
    ...(dayLimit ? [`## Free limit met`, ``, `The run stopped early at a daily free limit, so fewer questions were scored: ${dayLimit}`, ``] : []),
    `## Errors`, ``,
    ...[...new Set(results.flatMap(r => [...r.checkErrors, ...(r.error ? [r.error] : [])]))].slice(0, 10).map(e => `- ${e}`),
  ];
  writeFileSync(REPORT, lines.join('\n') + '\n');
  writeFileSync(REPORT.replace(/\.md$/, '.json'), JSON.stringify(results, null, 1));
  console.log('\n' + lines.slice(0, 22).join('\n'));
}

if (import.meta.url === `file://${process.argv[1]}`) main();
