// Trains the app's accuracy model (accuracy-model.js) - for free, on GitHub
// Actions (.github/workflows/accuracy-model.yml).
//
// 1. A labelled set from public exam questions whose answers are known:
//      MedQA-USMLE test split (GBaker/MedQA-USMLE-4-options; MedQA is MIT,
//      the mirror CC-BY-4.0) and MedMCQA dev (openlifescienceai/medmcqa
//      validation, Apache-2.0, with explanations). Loaded from Hugging
//      Face's dataset server at run time; nothing is committed but the
//      signals and the weights.
//    Each question is filed under an exam slice - MedQA's Step 1 items,
//    its Step 2&3 items, MedMCQA's AIIMS / NEET-PG items - so the report
//    gives the model's quality per exam style and, for every exam in the
//    catalogue (exams.js), how its stricter cut-offs for management
//    questions would have done on its slice.
//    Each question becomes a correct item and one wrong one, in turn:
//      swapped key        - a distractor keyed, the explanation still right
//      wrong everywhere   - a distractor keyed and explained, the "lecture"
//                           saying the same (only the literature catches it)
//      corrupted reason   - the right key, the explanation's numbers or
//                           claim altered
//    and every fourth question is used as a flashcard instead, so cards are
//    in the set too. Items students reported (/accuracy/reports) join as
//    wrong, weighted by how many reported them.
// 2. Every item goes through the deployed worker's /accuracy/check (owner key,
//    counted on the benchmarks' own allowance), in small slices that add up
//    across runs (STATE, kept on the accuracy-model branch) - the free limits
//    allow only so many calls a day. A cached item costs nothing.
// 3. The combiner is fitted with cross-validation (folds by question, so a
//    question's right and wrong versions never straddle train and test), the
//    report gives calibration, AUC and precision/recall at the chosen
//    cut-offs, and the weights are published to the worker only when they
//    beat the ones it has on the same items.
//
// Env: WORKER, KEY (owner key), STATE (signals so far), OUT (directory),
//      N_MEDQA, N_MEDMCQA (questions), SEED, MAX_BATCHES (this run),
//      MIN_TRAIN (items before any weights are published), PUBLISH=1,
//      ROWS_BASE (the dataset server; Hugging Face's by default)

import { readFileSync, writeFileSync, existsSync, mkdirSync } from 'node:fs';
import { sample, rng } from './accuracy.mjs';
import { limitKind } from './checkers.mjs';
import { FEATURES, DEFAULT_WEIGHTS, vector, fit, crossValidate, probability, metrics, thresholds, predict, isManagement, stricter } from '../accuracy-model.js';
import { EXAMS } from '../exams.js';

const WORKER = (process.env.WORKER || 'https://redpen-auth.vv7sh4rnnw.workers.dev').replace(/\/+$/, '');
const KEY = process.env.KEY || '';
const OUT = process.env.OUT || 'out';
const STATE = process.env.STATE || `${OUT}/signals.json`;
const SEED = Number(process.env.SEED || 20260925);
const N_MEDQA = Number(process.env.N_MEDQA || 300);
const N_MEDMCQA = Number(process.env.N_MEDMCQA || 300);
const MAX_BATCHES = Number(process.env.MAX_BATCHES || 60);
const MIN_TRAIN = Number(process.env.MIN_TRAIN || 200);
// the dataset server (a test run points it elsewhere)
const ROWS = (process.env.ROWS_BASE || 'https://datasets-server.huggingface.co').replace(/\/+$/, '');

export const SETS = {
  medqa: { path: 'GBaker%2FMedQA-USMLE-4-options', config: 'default', split: 'test', rows: 1273 },
  medmcqa: { path: 'openlifescienceai%2Fmedmcqa', config: 'default', split: 'validation', rows: 4183 },
};

const letter = i => String.fromCharCode(65 + i);

// MARK: exam slices

/// The slice a MedQA row belongs to, by its meta_info.
export const sliceOfMedQA = meta => (String(meta || '').trim().toLowerCase() === 'step1' ? 'usmle-step1' : 'usmle-step2-3');

/// Which slice stands for each exam's style: the same bank its exemplars
/// come from (exams.js).
export const SLICE_OF_SOURCE = { 'medqa-step1': 'usmle-step1', 'medqa-step23': 'usmle-step2-3', medmcqa: 'neetpg-aiims' };
export const examSlice = e => SLICE_OF_SOURCE[e.exemplars] || null;

// MARK: the labelled set (pure, tested in tests/accuracy.test.mjs)

export function normaliseMedQA(row, index) {
  const letters = Object.keys(row.options || {}).sort();
  const options = letters.map(l => String(row.options[l]));
  const key = letters.indexOf(String(row.answer_idx).trim());
  if (options.length < 2 || key < 0) return null;
  return { qid: `medqa:${index}`, stem: String(row.question), options, key, explanation: '',
           slice: sliceOfMedQA(row.meta_info) };
}

export function normaliseMedMCQA(row, index) {
  if (row.choice_type && row.choice_type !== 'single') return null;
  const options = [row.opa, row.opb, row.opc, row.opd].map(o => String(o ?? '').trim());
  const key = Number(row.cop);
  if (options.some(o => !o) || !(key >= 0 && key < 4)) return null;
  // MedMCQA's explanations often begin "Ans. is 'a' i.e., ..." - the letter
  // there is lower-case and names the key, which is fine; they are kept whole
  return { qid: `medmcqa:${row.id || index}`, stem: String(row.question), options, key, slice: 'neetpg-aiims',
           explanation: String(row.exp || '').replace(/\s+/g, ' ').trim().slice(0, 1500) };
}

/// Changes an explanation's claim: its numbers scaled tenfold, or failing
/// that its first "is"/"are" negated, or the key's words swapped for a
/// distractor's. Null when nothing could be changed.
export function corrupt(explanation, keyText, distractor) {
  const e = String(explanation || '');
  if (!e.trim()) return null;
  if (/\d/.test(e)) {
    let changed = false;
    const out = e.replace(/(\d+(?:\.\d+)?)/g, m => { const n = Number(m); if (!n) return m; changed = true; return String(Math.round(n * 10 * 100) / 100); });
    if (changed && out !== e) return out;
  }
  if (keyText && keyText.length >= 4 && e.toLowerCase().includes(keyText.toLowerCase())) {
    return e.replace(new RegExp(keyText.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'), 'gi'), distractor);
  }
  const negated = e.replace(/\b(is|are)\b(?!\s+not)/, '$1 not');
  return negated !== e ? negated : null;
}

/// The explanation with the key's words replaced by the distractor's, or
/// null when the key is not named in it.
export function swapIn(explanation, keyText, distractor) {
  const e = String(explanation || '');
  if (!keyText || keyText.length < 3 || !e.toLowerCase().includes(keyText.toLowerCase())) return null;
  return e.replace(new RegExp(keyText.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'), 'gi'), distractor);
}

/// A question's labelled items: the correct one and, in turn, one wrong
/// version. `label` 1 = accurate. Every fourth question becomes a card.
export function variants(q, index) {
  const r = rng(index + 7);
  const others = q.options.map((_, i) => i).filter(i => i !== q.key);
  const d = others[Math.floor(r() * others.length)];
  const keyText = q.options[q.key], dText = q.options[d];
  const right = q.explanation || `The answer is ${letter(q.key)}: ${keyText}.`;
  const card = index % 4 === 3;
  const mcq = (key, explanation, source) => ({ kind: 'mcq', stem: q.stem, options: q.options, key, explanation, source });
  const asCard = (answer, why, source) => ({ kind: 'card', text: `Q: ${q.stem}\nA: ${answer}\nWhy: ${why}`, source });
  const out = [];
  const mgmt = isManagement(q.stem);
  const add = (variant, label, item) => out.push({ id: `${q.qid}:${variant}`, group: q.qid, variant, label, weight: 1, item,
                                                  slice: q.slice || null, mgmt });
  if (card) {
    add('correct', 1, asCard(keyText, right, q.explanation));
    const swapped = q.explanation ? swapIn(q.explanation, keyText, dText) : `The answer is ${dText}.`;
    if (index % 8 === 3 && swapped) add('wrong-everywhere', 0, asCard(dText, swapped, q.explanation ? swapped : ''));
    else add('swapped-key', 0, asCard(dText, right, q.explanation));
    return out;
  }
  add('correct', 1, mcq(q.key, right, q.explanation));
  const turn = index % 3;
  const corrupted = turn === 2 ? corrupt(q.explanation, keyText, dText) : null;
  // "wrong everywhere" must look like its correct twin but for the claim -
  // the real explanation with the distractor written in, or with no lecture
  // at all when the correct twin has none - or the model learns the shape of
  // the text instead of the medicine
  const wrongEverywhere = () => {
    if (!q.explanation) return { explanation: `The answer is ${letter(d)}: ${dText}.`, source: '' };
    const swapped = swapIn(q.explanation, keyText, dText);
    return swapped ? { explanation: swapped, source: swapped } : null;
  };
  const everywhere = turn === 1 ? wrongEverywhere() : null;
  if (everywhere) add('wrong-everywhere', 0, mcq(d, everywhere.explanation, everywhere.source));
  else if (turn === 2 && corrupted) add('corrupted-explanation', 0, mcq(q.key, corrupted, q.explanation));
  else add('swapped-key', 0, mcq(d, right, q.explanation));
  return out;
}

/// Items students reported, as wrong examples: two reports count as one
/// certain label, one report as a doubtful one.
export function reportedExamples(reports) {
  return (reports || []).filter(r => r?.item?.kind).map(r => ({
    id: `report:${r.hash}`, group: `report:${r.hash}`, variant: 'reported', label: 0,
    weight: Math.min(1, 0.5 * (r.reports || 1)), item: r.item,
  }));
}

/// The fitting data from what the worker returned.
export function dataset(results) {
  const done = results.filter(r => r.features && Number.isFinite(r.label));
  return {
    X: done.map(r => vector(r.features, FEATURES)),
    y: done.map(r => r.label),
    w: done.map(r => r.weight ?? 1),
    groups: done.map(r => r.group),
    rows: done,
  };
}

/// Fits the combiner: the L2 strength chosen by cross-validated log loss,
/// the cut-offs from the cross-validated probabilities, then one fit on all.
export function train(results, { lambdas = [0.01, 0.1, 1, 10], k = 5, current = DEFAULT_WEIGHTS, version } = {}) {
  const { X, y, w, groups, rows } = dataset(results);
  if (X.length < 10 || !y.some(v => v === 1) || !y.some(v => v === 0)) return null;
  let best = null;
  for (const lambda of lambdas) {
    const p = crossValidate(X, y, { k, lambda, groups, w });
    const m = metrics(p, y);
    if (!best || m.logLoss < best.m.logLoss) best = { lambda, p, m };
  }
  const cut = thresholds(best.p, y);
  const beta = fit(X, y, { lambda: best.lambda, w });
  const theirs = metrics(rows.map(r => predict(r.features, current)), y);
  const byVariant = {};
  rows.forEach((r, i) => {
    const v = byVariant[r.variant] ||= { n: 0, flagged: 0, verified: 0 };
    v.n++;
    if (best.p[i] < cut.flagged) v.flagged++;
    if (best.p[i] >= cut.verified) v.verified++;
  });
  const bySlice = sliceMetrics(rows, best.p, y, cut);
  const byExam = examMetrics(rows, best.p, y, cut);
  const weights = {
    version: version || `trained-${new Date().toISOString().slice(0, 10)}-${X.length}`,
    features: FEATURES,
    weights: beta.map(b => Math.round(b * 10000) / 10000),
    thresholds: { verified: cut.verified, flagged: cut.flagged },
    metrics: { n: X.length, lambda: best.lambda, cv: pick(best.m), current: pick(theirs),
               verified: cut.verifiedStats, flagged: cut.flaggedStats, bySlice },
  };
  return { weights, cv: best.m, current: theirs, cut, byVariant, bySlice, byExam, better: best.m.logLoss < theirs.logLoss };
}

/// Held-out quality per exam slice: items, AUC, and how many accurate ones
/// are Verified and wrong ones Flagged at the shared cut-offs.
export function sliceMetrics(rows, p, y, cut) {
  const out = {};
  rows.forEach((r, i) => {
    const s = out[r.slice || 'unfiled'] ||= { n: 0, p: [], y: [], verifiedRight: 0, right: 0, flaggedWrong: 0, wrong: 0 };
    s.n++; s.p.push(p[i]); s.y.push(y[i]);
    if (y[i]) { s.right++; if (p[i] >= cut.verified) s.verifiedRight++; }
    else { s.wrong++; if (p[i] < cut.flagged) s.flaggedWrong++; }
  });
  for (const [k, s] of Object.entries(out)) {
    const m = s.p.length && s.y.some(v => v) && s.y.some(v => !v) ? metrics(s.p, s.y) : null;
    out[k] = { n: s.n, auc: m ? round(m.auc) : null, logLoss: m ? round(m.logLoss) : null,
               verifiedRecall: s.right ? round(s.verifiedRight / s.right) : null,
               flaggedRecall: s.wrong ? round(s.flaggedWrong / s.wrong) : null };
  }
  return out;
}

/// For every exam with stricter management cut-offs: on its slice's
/// management items, the precision of Verified at the shared cut-off and at
/// the exam's own, and how many accurate items each still verifies.
export function examMetrics(rows, p, y, cut, exams = EXAMS) {
  const out = {};
  for (const e of exams) {
    const slice = examSlice(e);
    const idx = rows.map((r, i) => i).filter(i => rows[i].slice === slice && rows[i].mgmt);
    const strict = stricter({ verified: cut.verified, flagged: cut.flagged }, e.strict);
    const at = v => {
      const above = idx.filter(i => p[i] >= v);
      const right = above.filter(i => y[i]).length;
      const all = idx.filter(i => y[i]).length;
      return { verified: above.length, precision: above.length ? round(right / above.length) : null,
               recall: all ? round(right / all) : null };
    };
    out[e.id] = { slice, strictness: e.strict, n: idx.length, cutoff: strict.verified, shared: at(cut.verified), own: at(strict.verified) };
  }
  return out;
}

const pick = m => ({ logLoss: round(m.logLoss), brier: round(m.brier), auc: round(m.auc), ece: round(m.ece) });
const round = x => Math.round(x * 10000) / 10000;

export function reportMarkdown(t, notes = []) {
  const pct = x => `${(100 * x).toFixed(1)}%`;
  if (!t) return ['# Accuracy model', '', 'Not enough checked items yet to fit the model.', '', ...notes.map(n => `- ${n}`)].join('\n') + '\n';
  const w = t.weights;
  return [
    `# Accuracy model ${w.version}`, '',
    `${w.metrics.n} items (cross-validated, 5 folds by question) · L2 ${w.metrics.lambda}`, '',
    '| | Log loss | Brier | AUC | Calibration error (ECE) |', '|---|---|---|---|---|',
    `| Trained (held-out) | ${t.cv.logLoss.toFixed(3)} | ${t.cv.brier.toFixed(3)} | ${t.cv.auc.toFixed(3)} | ${t.cv.ece.toFixed(3)} |`,
    `| Current weights | ${t.current.logLoss.toFixed(3)} | ${t.current.brier.toFixed(3)} | ${t.current.auc.toFixed(3)} | ${t.current.ece.toFixed(3)} |`,
    '', `**Verified** at P ≥ ${w.thresholds.verified}: precision ${pct(t.cut.verifiedStats.precision)}, recall ${pct(t.cut.verifiedStats.recall)} of accurate items (${t.cut.verifiedStats.n} items).`,
    `**Flagged** at P < ${w.thresholds.flagged}: precision ${pct(t.cut.flaggedStats.precision)}, recall ${pct(t.cut.flaggedStats.recall)} of wrong items (${t.cut.flaggedStats.n} items).`,
    '', '## Calibration (held-out)', '', '| P(accurate) | Items | Mean P | Actually accurate |', '|---|---|---|---|',
    ...t.cv.bins.filter(b => b.n).map(b => `| ${b.lo.toFixed(1)}–${b.hi.toFixed(1)} | ${b.n} | ${pct(b.meanP)} | ${pct(b.rate)} |`),
    '', '## By kind of item', '', '| Variant | Items | Flagged | Verified |', '|---|---|---|---|',
    ...Object.entries(t.byVariant).map(([v, s]) => `| ${v} | ${s.n} | ${pct(s.flagged / s.n)} | ${pct(s.verified / s.n)} |`),
    ...(t.bySlice ? ['', '## By exam slice (held-out)', '', '| Slice | Items | AUC | Accurate verified | Wrong flagged |', '|---|---|---|---|---|',
      ...Object.entries(t.bySlice).map(([k, s]) => `| ${k} | ${s.n} | ${s.auc ?? '-'} | ${s.verifiedRecall == null ? '-' : pct(s.verifiedRecall)} | ${s.flaggedRecall == null ? '-' : pct(s.flaggedRecall)} |`)] : []),
    ...(t.byExam ? ['', '## Management questions, per exam', '', 'Each exam\'s stricter Verified cut-off for management questions ("next best step", "most appropriate treatment") on its style slice, against the shared one.', '',
      '| Exam | Slice | Strictness | Items | Cut-off | Precision (shared → own) | Accurate verified (shared → own) |', '|---|---|---|---|---|---|---|',
      ...Object.entries(t.byExam).filter(([, e]) => e.strictness > 0).map(([id, e]) =>
        `| ${id} | ${e.slice} | ${e.strictness} | ${e.n} | ${e.cutoff} | ${e.shared.precision == null ? '-' : pct(e.shared.precision)} → ${e.own.precision == null ? '-' : pct(e.own.precision)} | ${e.shared.recall == null ? '-' : pct(e.shared.recall)} → ${e.own.recall == null ? '-' : pct(e.own.recall)} |`)] : []),
    '', '## Weights', '', '| Feature | Weight |', '|---|---|',
    ...w.features.map((f, i) => `| ${f} | ${w.weights[i]} |`),
    '', t.better ? '**Better than the current weights on these items: published.**' : '**Not better than the current weights: kept the current ones.**',
    ...(notes.length ? ['', '## Notes', '', ...notes.map(n => `- ${n}`)] : []),
  ].join('\n') + '\n';
}

// MARK: the run

async function rows(set, indices) {
  const s = SETS[set];
  const out = [];
  for (const i of indices) {
    const url = `${ROWS}/rows?dataset=${s.path}&config=${s.config}&split=${s.split}&offset=${i}&length=1`;
    for (let attempt = 0; attempt < 4; attempt++) {
      const r = await fetch(url).catch(() => null);
      if (r?.ok) { const j = await r.json(); if (j.rows?.[0]) out.push([i, j.rows[0].row]); break; }
      await new Promise(res => setTimeout(res, 1500 * (attempt + 1)));
    }
  }
  return out;
}

async function post(path, body, bench = true) {
  const r = await fetch(`${WORKER}${path}`, {
    method: 'POST', signal: AbortSignal.timeout(170_000),
    headers: { 'content-type': 'application/json', authorization: `Bearer ${KEY}`, ...(bench ? { 'x-bench': '1' } : {}) },
    body: JSON.stringify(body),
  });
  const j = await r.json().catch(() => ({}));
  return { status: r.status, body: j };
}

async function main() {
  if (!KEY) { console.error('KEY (owner key) is required'); process.exit(2); }
  mkdirSync(OUT, { recursive: true });
  const state = existsSync(STATE) ? JSON.parse(readFileSync(STATE, 'utf8')) : [];
  const done = new Map(state.map(r => [r.id, r]));
  const notes = [];

  const questions = [
    ...(await rows('medqa', sample(SETS.medqa.rows, N_MEDQA, SEED))).map(([i, row]) => normaliseMedQA(row, i)),
    ...(await rows('medmcqa', sample(SETS.medmcqa.rows, N_MEDMCQA, SEED + 1))).map(([i, row]) => normaliseMedMCQA(row, i)),
  ].filter(Boolean);
  const reported = await post('/accuracy/reports', { limit: 500 }, false).catch(() => ({ body: {} }));
  const examples = [...questions.flatMap((q, n) => variants(q, n)), ...reportedExamples(reported.body?.reports)];
  const todo = examples.filter(e => !done.has(e.id));
  console.log(`${examples.length} examples, ${done.size} already checked, ${todo.length} to go`);

  let batches = 0;
  outer: for (let i = 0; i < todo.length; i += 4) {
    if (batches >= MAX_BATCHES) { notes.push(`stopped at this run's ${MAX_BATCHES} batches; the next run carries on`); break; }
    const slice = todo.slice(i, i + 4);
    batches++;
    let reply;
    try { reply = await post('/accuracy/check', { items: slice.map(e => ({ ...e.item, id: e.id })), priority: 'bench' }); }
    catch (error) { notes.push(`a batch failed: ${String(error?.name || error)}`); continue; }
    if (reply.status === 429 || limitKind(reply.body?.message, reply.body) === 'day') {
      notes.push('the day\'s free allowance is used; the next run carries on'); break outer;
    }
    if (reply.status !== 200) { notes.push(`batch ${batches}: ${reply.status} ${String(reply.body?.message || '').slice(0, 120)}`); continue; }
    for (const [n, e] of slice.entries()) {
      const got = reply.body.items?.[n];
      // only an item some model actually voted on is a training example
      if (!got || got.features?.no_models) continue;
      done.set(e.id, { id: e.id, group: e.group, variant: e.variant, label: e.label, weight: e.weight,
                       kind: e.item.kind, slice: e.slice, mgmt: e.mgmt, features: got.features, p: got.p, verdict: got.verdict });
    }
    process.stdout.write('.');
    writeFileSync(STATE, JSON.stringify([...done.values()]));
  }
  // signals kept from before slices existed get theirs from this run's questions
  const known = new Map(examples.map(e => [e.id, e]));
  for (const r of done.values()) {
    if (r.slice == null && known.has(r.id)) { r.slice = known.get(r.id).slice; r.mgmt = known.get(r.id).mgmt; }
    if (r.slice == null && String(r.group).startsWith('medmcqa:')) r.slice = 'neetpg-aiims';
  }
  const results = [...done.values()];
  writeFileSync(STATE, JSON.stringify(results));

  const current = (await post('/accuracy/model', {}, false).catch(() => null))?.body?.weights || DEFAULT_WEIGHTS;
  const t = results.length >= MIN_TRAIN ? train(results, { current }) : null;
  if (!t) notes.push(`${results.length} checked items so far; weights are fitted from ${MIN_TRAIN}`);
  if (t) {
    writeFileSync(`${OUT}/weights.json`, JSON.stringify(t.weights, null, 1));
    if (t.better && process.env.PUBLISH === '1') {
      const r = await post('/accuracy/model/set', { weights: t.weights }, false);
      notes.push(r.status === 200 ? `published ${t.weights.version} to the worker` : `publishing failed: ${r.status}`);
    }
  }
  const md = reportMarkdown(t, notes);
  writeFileSync(`${OUT}/report.md`, md);
  console.log('\n' + md);
}

if (import.meta.url === `file://${process.argv[1]}`) main();
