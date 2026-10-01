// The app's accuracy model: one calibrated number from every signal.
//
// Each item is judged by several things that are each wrong sometimes - two
// or three checker models voting, the literature they were shown, the rule
// checks, how much of the item its own lecture contains. This turns them into
// one P(accurate) with a logistic regression: small enough to run anywhere
// (here, on the phone in AccuracyModel.swift, in the training script), and
// calibrated, so "0.95" means right about 95 times in 100 on the held-out set.
//
// The weights are trained on GitHub Actions (bench/train-accuracy.mjs) from
// public exam questions with known answers, and served by the worker
// (/accuracy/model). DEFAULT_WEIGHTS is a hand-set prior that works before any
// training; the phone carries the same numbers (AccuracyModel.swift, checked
// by tests/accuracy.test.mjs).

export const FEATURES = [
  'bias', 'rule_severe', 'rule_minor', 'risk_max', 'risk_mean', 'flag_frac', 'disagree', 'voters',
  'key_disagree', 'ev_support', 'ev_contradict', 'ev_count', 'source_match', 'no_source', 'no_models',
  'kind_mcq', 'kind_card', 'kind_case', 'kind_osce', 'kind_page',
];

export const KINDS = ['mcq', 'card', 'case', 'osce', 'page', 'fact', 'note'];

// BEGIN DEFAULT WEIGHTS (kept identical to AccuracyModel.swift's defaultJSON)
export const DEFAULT_WEIGHTS = {
  version: 'prior-1',
  features: FEATURES,
  weights: [3.0, -2.5, -0.4, -2.5, -1.5, -2.0, -0.5, 0.3, -2.5, 0.8, -2.5, 0.1, 0.8, -0.3, -1.5, 0, 0, 0, 0, 0],
  thresholds: { verified: 0.85, flagged: 0.4 },
  metrics: null,
};
// END DEFAULT WEIGHTS

const clamp01 = x => Math.min(1, Math.max(0, x));

/// The feature vector for one item, from its rule hits, its votes and its
/// evidence. `votes`: [{ risk 1-4 | null, answer letter | null, evidence:
/// 'supports' | 'contradicts' | 'none' }]; `keyLetter` for a question.
export function features({ kind, rules = [], votes = [], evidenceCount = 0, sourceMatch = null, keyLetter = null }) {
  const read = votes.filter(v => Number.isFinite(v?.risk));
  const risks = read.map(v => (clamp01((v.risk - 1) / 3)));
  const flags = read.map(v => v.risk >= 3);
  const answered = read.filter(v => typeof v.answer === 'string' && /^[A-J]$/.test(v.answer));
  const f = {
    bias: 1,
    rule_severe: Math.min(2, rules.filter(r => r.severity === 'severe').length),
    rule_minor: Math.min(3, rules.filter(r => r.severity !== 'severe').length),
    risk_max: risks.length ? Math.max(...risks) : 0,
    risk_mean: risks.length ? risks.reduce((a, b) => a + b, 0) / risks.length : 0,
    flag_frac: flags.length ? flags.filter(Boolean).length / flags.length : 0,
    disagree: flags.length > 1 && flags.some(Boolean) && flags.some(x => !x) ? 1 : 0,
    voters: Math.min(3, read.length) / 3,
    key_disagree: kind === 'mcq' && keyLetter && answered.length
      ? answered.filter(v => v.answer !== keyLetter).length / answered.length : 0,
    ev_support: read.length ? read.filter(v => v.evidence === 'supports').length / read.length : 0,
    ev_contradict: read.length ? read.filter(v => v.evidence === 'contradicts').length / read.length : 0,
    ev_count: Math.min(5, evidenceCount) / 5,
    source_match: sourceMatch === null || sourceMatch === undefined ? 0 : clamp01(sourceMatch),
    no_source: sourceMatch === null || sourceMatch === undefined ? 1 : 0,
    no_models: read.length ? 0 : 1,
    kind_mcq: kind === 'mcq' ? 1 : 0,
    kind_card: kind === 'card' ? 1 : 0,
    kind_case: kind === 'case' ? 1 : 0,
    kind_osce: kind === 'osce' ? 1 : 0,
    kind_page: kind === 'page' || kind === 'fact' || kind === 'note' ? 1 : 0,
  };
  // not a weighted feature: how many model families the votes that pass the
  // item come from (the verdict needs two)
  f.families = new Set(read.filter(v => v.risk < 3).map(v => familyOf(v.model))).size;
  // not weighted either: the blind solves of a question, counted by family,
  // since a witness from the same family as another is not a second witness
  // (DNA brief: independence multiplies, correlation does not; Islamic brief:
  // tawatur counts independent chains). blind_agree: families whose blind
  // answer is the key. blind_against: the most families agreeing on one
  // other answer. blind_split: blind families that answered differently.
  if (kind === 'mcq' && keyLetter) {
    const byLetter = new Map();
    for (const v of answered.filter(v => v.blind)) {
      if (!byLetter.has(v.answer)) byLetter.set(v.answer, new Set());
      byLetter.get(v.answer).add(familyOf(v.model));
    }
    f.blind_agree = byLetter.get(keyLetter)?.size || 0;
    f.blind_against = Math.max(0, ...[...byLetter].filter(([l]) => l !== keyLetter).map(([, fams]) => fams.size));
    f.blind_split = byLetter.size > 1 ? 1 : 0;
  }
  return f;
}

export const vector = (f, names = FEATURES) => names.map(n => Number(f[n]) || 0);

/// The family a checker model belongs to. Two models of one family share
/// their training and so their blind spots: two votes from one family are one
/// witness, not two (DNA brief: independence multiplies; Islamic brief:
/// tawatur needs independent chains).
const FAMILIES = [['google', /gemini|gemma/], ['openai', /gpt|openai/], ['nvidia', /nemotron|nvidia/],
  ['meta', /llama|\bmeta\b/], ['alibaba', /qwen/], ['mistral', /mistral|mixtral/], ['deepseek', /deepseek/],
  ['anthropic', /claude|anthropic/], ['baichuan', /baichuan/], ['microsoft', /\bphi-|microsoft/], ['apple', /\bapple\b/]];
export function familyOf(model) {
  const m = String(model || '').toLowerCase();
  for (const [family, pattern] of FAMILIES) if (pattern.test(m)) return family;
  return m || 'unknown';
}
const sigmoid = z => 1 / (1 + Math.exp(-Math.max(-40, Math.min(40, z))));

/// P(accurate) for a feature object, with these weights.
export function predict(f, model = DEFAULT_WEIGHTS) {
  const x = vector(f, model.features);
  return sigmoid(x.reduce((s, xi, i) => s + xi * (model.weights[i] || 0), 0));
}

// MARK: the oath check (plan §22 Layer 7: regex first, fail closed)

/// The fewest checker models whose votes an item needs before it can be
/// Verified: one free model's word is never enough (audit #95, #97).
export const MIN_VERIFY_VOTERS = 2;

/// How much of an oath item its own lecture must contain to stand for the
/// evidence behind it.
export const OATH_SOURCE_MATCH = 0.5;

/// A specific dose: an amount in a dose unit beside a route or a frequency,
/// or per kilogram, day or dose. Lab values in a case ("potassium 6.8
/// mmol/L") are not doses. The app's AccuracyModel.dosePattern, character
/// for character.
export const DOSE_PATTERN = '\\b\\d+(?:\\.\\d+)?\\s?(?:mg|mcg|µg|μg|micrograms?|milligrams?|g|grams?|units?|iu|ml)\\b[^.\\n]{0,30}\\b(?:iv|po|im|sc|sl|oral|orally|intravenous|intravenously|daily|once|twice|bd|bid|tds|tid|qds|qid|nocte|stat|hourly|weekly|per day|a day|every \\d+ ?(?:h|hours?))\\b'
  + '|\\b(?:iv|po|im|sc|oral|orally|intravenous|intravenously)\\b[^.\\n]{0,20}?\\b\\d+(?:\\.\\d+)?\\s?(?:mg|mcg|µg|μg|g|units?|iu|ml)\\b'
  + '|\\b\\d+(?:\\.\\d+)?\\s?(?:mg|mcg|µg|μg|g|units?|iu|ml)\\s?/\\s?(?:kg|day|d|dose|m2|m²)\\b';
const DOSE = new RegExp(DOSE_PATTERN, 'i');

/// Words that make an item a diagnosis - the same list as the app's
/// AccuracyModel.diagnosisCues.
export const DIAGNOSIS_CUES = [
  'most likely diagnosis', 'most probable diagnosis', 'likely diagnosis is', 'the diagnosis is',
  'diagnosis of choice', 'is diagnosed with', 'is diagnostic of', 'confirms the diagnosis', 'pathognomonic',
];

export const hasDose = text => DOSE.test(String(text || ''));
export const isDiagnosis = text => {
  const t = String(text || '').toLowerCase();
  return DIAGNOSIS_CUES.some(c => t.includes(c));
};

/// Does this item give a dose, name a diagnosis or recommend a treatment?
/// Then the oath check holds it to more than the models' word.
export function oathClaims(text) {
  return { dose: hasDose(text), diagnosis: isDiagnosis(text), treatment: isManagement(text) };
}
export const isOath = text => {
  const c = oathClaims(text);
  return c.dose || c.diagnosis || c.treatment;
};

/// Verified / Check this / Flagged, or unchecked when no model has looked.
/// Verified also needs the passing votes to come from two model families.
/// rules alone can flag an item but never verify one, and a severe rule hit
/// keeps an item from being Verified whatever the models said. Verified also
/// needs two models' votes; and an oath item (a dose, a diagnosis, a
/// treatment) needs evidence behind it - the literature the voters were shown
/// supporting it, or its own lecture saying it - or it stays Check this.
export function verdict(p, f, model = DEFAULT_WEIGHTS, oath = false) {
  const t = model.thresholds || DEFAULT_WEIGHTS.thresholds;
  if (f.no_models) return f.rule_severe > 0 ? 'flagged' : 'unchecked';
  // two independent blind solvers agreeing on another answer: an explained
  // objection from two chains, which outweighs any approval (Islamic brief:
  // jarh mufassar, tawatur) - the key is wrong
  const question = Number(f.kind_mcq) === 1;
  if (question && (Number(f.blind_against) || 0) >= MIN_VERIFY_VOTERS) return 'flagged';
  if (p < t.flagged) return 'flagged';
  const enough = Math.round((Number(f.voters) || 0) * 3) >= MIN_VERIFY_VOTERS;
  const backed = !oath || (Number(f.ev_support) || 0) > 0 || (Number(f.source_match) || 0) >= OATH_SOURCE_MATCH;
  const independent = (Number(f.families) || 0) >= MIN_VERIFY_VOTERS;
  // a question is Verified only when two independent blind solves reach its
  // key: a checker shown the key tends to agree with it (DNA brief: kinetic
  // proofreading, a second discrimination that does not see the first)
  const solved = !question || (Number(f.blind_agree) || 0) >= MIN_VERIFY_VOTERS;
  if (p >= t.verified && !f.rule_severe && enough && backed && independent && solved) return 'verified';
  return 'check';
}

/// Why an item got its verdict, in words the student can read: each reason
/// that held it back or brought it down (Islamic brief: always record the
/// reason; an unresolved conflict is said to be one, tawaqquf).
export function reasonsFor(verdictName, p, f, model = DEFAULT_WEIGHTS, oath = false, letters = null) {
  const t = model.thresholds || DEFAULT_WEIGHTS.thresholds;
  const out = [];
  const question = Number(f.kind_mcq) === 1;
  if (f.no_models) return verdictName === 'flagged' ? ['A safety rule failed; no checker has looked yet.'] : ['Not checked yet.'];
  if (question && (Number(f.blind_against) || 0) >= MIN_VERIFY_VOTERS) {
    out.push(`Checkers from ${f.blind_against} different model families, solving it without the key, chose another answer${letters ? ` (${letters})` : ''}.`);
  }
  if (f.rule_severe) out.push('A safety rule failed.');
  if (question && f.blind_split && !(f.blind_against >= MIN_VERIFY_VOTERS) && !(f.blind_agree >= MIN_VERIFY_VOTERS)) {
    out.push('Unresolved: independent checkers solving it blind did not agree.');
  } else if (question && (Number(f.blind_agree) || 0) < MIN_VERIFY_VOTERS && verdictName !== 'flagged') {
    out.push('Fewer than two independent blind solves reached the key.');
  }
  if ((Number(f.families) || 0) < MIN_VERIFY_VOTERS && verdictName !== 'flagged') out.push('Not yet passed by two model families.');
  if (oath && !((Number(f.ev_support) || 0) > 0 || (Number(f.source_match) || 0) >= OATH_SOURCE_MATCH)) {
    out.push('A dose, diagnosis or treatment without evidence behind it.');
  }
  if (p < t.flagged) out.push('The checkers judged it likely wrong.');
  else if (p < t.verified && verdictName !== 'verified') out.push('The checkers were not confident enough.');
  return out;
}

// MARK: stricter for an exam's management questions

/// Lead-ins of a management question - the same list as the app's
/// AccuracyModel.managementCues.
export const MANAGEMENT_CUES = [
  'next step', 'next best step', 'most appropriate management', 'most appropriate treatment',
  'most appropriate therapy', 'most appropriate pharmacotherapy', 'most appropriate initial',
  'most appropriate immediate', 'most appropriate next', 'most appropriate intervention',
  'most appropriate action', 'best management', 'best treatment', 'initial management',
  'immediate management', 'treatment of choice', 'drug of choice', 'first-line', 'first line',
  'should be managed', 'should be prescribed',
];

export function isManagement(text) {
  const t = String(text || '').toLowerCase();
  return MANAGEMENT_CUES.some(c => t.includes(c));
}

/// Cut-offs made stricter by s (0-1): Verified moves s of the way to 0.99,
/// Flagged up by a tenth of s (always 0.05 under Verified). The app's
/// AccuracyModel.stricter, number for number.
export function stricter(t, s) {
  const k = Math.min(1, Math.max(0, Number(s) || 0));
  if (!k) return t;
  const verified = t.verified < 0.99 ? t.verified + (0.99 - t.verified) * k : t.verified;
  const flagged = Math.min(verified - 0.05, t.flagged + 0.1 * k);
  const r4 = x => Math.round(x * 10000) / 10000;
  return { verified: r4(verified), flagged: r4(Math.max(0, flagged)) };
}

/// The weights to grade one item with: stricter cut-offs for a management
/// question when the exam asks for it.
export function examWeights(model, item, strictness) {
  if (!strictness || !item) return model;
  const text = item.kind === 'mcq' ? item.stem : item.text;
  if (!isManagement(text)) return model;
  return { ...model, thresholds: stricter(model.thresholds || DEFAULT_WEIGHTS.thresholds, strictness) };
}

/// Weights the worker will accept: the same feature names, every number finite.
export function validWeights(w) {
  return !!w && Array.isArray(w.features) && Array.isArray(w.weights) && w.features.length === w.weights.length
    && w.features.every(n => FEATURES.includes(n)) && w.weights.every(Number.isFinite)
    && w.thresholds && Number.isFinite(w.thresholds.verified) && Number.isFinite(w.thresholds.flagged)
    && w.thresholds.flagged < w.thresholds.verified && w.thresholds.verified <= 1 && w.thresholds.flagged >= 0
    && typeof w.version === 'string' && w.version.length <= 60;
}

// MARK: training (bench/train-accuracy.mjs), pure so it can be tested

/// L2-regularised logistic regression by Newton's method (IRLS): a few
/// dozen features, so the Hessian is tiny. The bias is not penalised.
/// `w`: optional per-example weights (a student's report counts for less).
export function fit(X, y, { lambda = 0.1, iterations = 50, w = null } = {}) {
  const d = X[0].length;
  let beta = new Array(d).fill(0);
  for (let it = 0; it < iterations; it++) {
    const g = new Array(d).fill(0);
    const H = [...Array(d)].map(() => new Array(d).fill(0));
    for (let i = 0; i < X.length; i++) {
      const p = sigmoid(X[i].reduce((s, x, j) => s + x * beta[j], 0));
      const wi = w ? w[i] : 1;
      const r = (p - y[i]) * wi, s = Math.max(p * (1 - p), 1e-6) * wi;
      for (let j = 0; j < d; j++) {
        if (!X[i][j]) continue;
        g[j] += r * X[i][j];
        for (let k = 0; k < d; k++) if (X[i][k]) H[j][k] += s * X[i][j] * X[i][k];
      }
    }
    for (let j = 1; j < d; j++) { g[j] += lambda * beta[j]; H[j][j] += lambda; }
    H[0][0] += 1e-6;
    // features never seen (all zero) still get a well-posed system
    for (let j = 0; j < d; j++) if (H[j][j] === 0) H[j][j] = 1;
    const step = solve(H, g);
    let biggest = 0;
    for (let j = 0; j < d; j++) { beta[j] -= step[j]; biggest = Math.max(biggest, Math.abs(step[j])); }
    if (biggest < 1e-7) break;
  }
  return beta;
}

function solve(A, b) {
  const n = b.length;
  const M = A.map((row, i) => [...row, b[i]]);
  for (let c = 0; c < n; c++) {
    let p = c;
    for (let r = c + 1; r < n; r++) if (Math.abs(M[r][c]) > Math.abs(M[p][c])) p = r;
    [M[c], M[p]] = [M[p], M[c]];
    const v = M[c][c] || 1e-12;
    for (let r = 0; r < n; r++) {
      if (r === c) continue;
      const f = M[r][c] / v;
      if (!f) continue;
      for (let k = c; k <= n; k++) M[r][k] -= f * M[c][k];
    }
  }
  return M.map((row, i) => row[n] / (row[i] || 1e-12));
}

export const probability = (beta, x) => sigmoid(x.reduce((s, xi, j) => s + xi * beta[j], 0));

/// k-fold cross-validated predictions (every example predicted by a model
/// that never saw it), folds assigned by `group` so an item's correct and
/// wrong versions stay in the same fold and cannot leak into each other.
export function crossValidate(X, y, { k = 5, lambda = 0.1, groups = null, w = null } = {}) {
  const fold = i => (groups ? hashString(String(groups[i])) : i) % k;
  const out = new Array(X.length).fill(0.5);
  for (let f = 0; f < k; f++) {
    const train = X.map((_, i) => i).filter(i => fold(i) !== f);
    const test = X.map((_, i) => i).filter(i => fold(i) === f);
    if (!train.length || !test.length) continue;
    const beta = fit(train.map(i => X[i]), train.map(i => y[i]), { lambda, w: w ? train.map(i => w[i]) : null });
    for (const i of test) out[i] = probability(beta, X[i]);
  }
  return out;
}

export function hashString(s) {
  let h = 2166136261;
  for (let i = 0; i < s.length; i++) { h ^= s.charCodeAt(i); h = Math.imul(h, 16777619) >>> 0; }
  return h >>> 0;
}

/// How good the probabilities are: log loss, Brier score, area under the ROC
/// curve, and expected calibration error over ten bins (with the bins).
export function metrics(p, y) {
  const n = p.length;
  const eps = 1e-9;
  const logLoss = -p.reduce((s, pi, i) => s + (y[i] ? Math.log(pi + eps) : Math.log(1 - pi + eps)), 0) / n;
  const brier = p.reduce((s, pi, i) => s + (pi - y[i]) ** 2, 0) / n;
  const bins = [...Array(10)].map((_, b) => ({ lo: b / 10, hi: (b + 1) / 10, n: 0, meanP: 0, rate: 0 }));
  p.forEach((pi, i) => { const b = bins[Math.min(9, Math.floor(pi * 10))]; b.n++; b.meanP += pi; b.rate += y[i]; });
  let ece = 0;
  for (const b of bins) if (b.n) { b.meanP /= b.n; b.rate /= b.n; ece += (b.n / n) * Math.abs(b.meanP - b.rate); }
  return { n, logLoss, brier, auc: auc(p, y), ece, bins };
}

export function auc(p, y) {
  const pos = p.filter((_, i) => y[i]), neg = p.filter((_, i) => !y[i]);
  if (!pos.length || !neg.length) return 0.5;
  const order = p.map((v, i) => [v, y[i]]).sort((a, b) => a[0] - b[0]);
  let rank = 0, sumPos = 0;
  for (let i = 0; i < order.length;) {
    let j = i;
    while (j < order.length && order[j][0] === order[i][0]) j++;
    const avg = (i + j + 1) / 2;
    for (let t = i; t < j; t++) if (order[t][1]) sumPos += avg;
    rank = j; i = j;
  }
  return (sumPos - pos.length * (pos.length + 1) / 2) / (pos.length * neg.length);
}

/// The two cut-offs: Verified where items above it are accurate at least
/// `verifiedPrecision` of the time; Flagged where items below it are wrong at
/// least `flaggedPrecision` of the time. Each also reports its recall.
export function thresholds(p, y, { verifiedPrecision = 0.97, flaggedPrecision = 0.8 } = {}) {
  const grid = [...Array(99)].map((_, i) => (i + 1) / 100);
  let verified = 0.99, flagged = 0.01;
  for (const t of grid) {
    const above = p.map((pi, i) => [pi, y[i]]).filter(([pi]) => pi >= t);
    if (above.length >= 5 && above.filter(([, yi]) => yi).length / above.length >= verifiedPrecision) { verified = t; break; }
  }
  for (const t of [...grid].reverse()) {
    const below = p.map((pi, i) => [pi, y[i]]).filter(([pi]) => pi < t);
    if (below.length >= 5 && below.filter(([, yi]) => !yi).length / below.length >= flaggedPrecision) { flagged = t; break; }
  }
  if (flagged >= verified) flagged = Math.max(0.01, verified - 0.05);
  const report = (sel, want) => {
    const picked = p.map((pi, i) => [pi, y[i]]).filter(([pi]) => sel(pi));
    const total = y.filter(yi => yi === want).length;
    const right = picked.filter(([, yi]) => yi === want).length;
    return { precision: picked.length ? right / picked.length : 0, recall: total ? right / total : 0, n: picked.length };
  };
  return {
    verified, flagged,
    verifiedStats: report(pi => pi >= verified, 1),
    flaggedStats: report(pi => pi < flagged, 0),
  };
}
