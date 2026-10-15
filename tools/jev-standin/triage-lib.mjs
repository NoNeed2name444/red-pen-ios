// Layer 6 of the open stand-in for Jev (§22a): card and question triage by
// an open cross-encoder (an NLI model), scored in batch on GitHub Actions
// (score_nli.py), its thresholds tuned on our own labelled items here.
//
// What it is for, and what it is not (§22a, layer-by-layer verdict): it
// sorts items for a person or the checkers to look at first - a question
// whose key the model reads as less likely than another option, a card
// whose answer does not follow from its question. It is never a verifier:
// nothing it says makes an item Verified, and it never stands alone on
// dose correctness, numeric ranges or diagnosis (§22a, "Never").
//
// Pure, so it is tested (tests/jev-standin/standin.test.mjs).

/// One question's triage features from its options' entailment scores
/// (0-1 each): the key's score, the best other option's, the margin between
/// them, and the key's rank (0 = the model's own first choice).
export function questionFeatures(scores, key) {
  const s = (Array.isArray(scores) ? scores : []).map(Number);
  if (!s.length || !Number.isInteger(key) || key < 0 || key >= s.length || s.some(x => !Number.isFinite(x))) return null;
  const others = s.filter((_, i) => i !== key);
  const best = others.length ? Math.max(...others) : 0;
  return { key: s[key], best, margin: s[key] - best, rank: s.filter(x => x > s[key]).length };
}

/// A card's: how strongly its answer follows from its question.
export function cardFeatures(score) {
  const x = Number(score);
  return Number.isFinite(x) ? { key: x, best: 0, margin: x, rank: 0 } : null;
}

/// The triage of one item at thresholds {suspect, pass}: 'suspect' (the
/// model prefers another answer by at least -suspect), 'pass' (the key leads
/// by at least `pass`), else 'review'. Never 'verified'.
export function triage(f, t) {
  if (!f) return 'review';
  if (f.margin <= t.suspect) return 'suspect';
  if (f.margin >= t.pass) return 'pass';
  return 'review';
}

/// A row's half for tuning (0) or confirming (1), fixed by its id, so an
/// item and its wrong-key twin ("x#right", "x#wrong") land in the same half.
export function half(id) {
  const base = String(id).replace(/#(?:right|wrong)$/, '');
  let h = 2166136261;
  for (let i = 0; i < base.length; i++) { h ^= base.charCodeAt(i); h = Math.imul(h, 16777619) >>> 0; }
  return h % 2;
}

/// Balanced accuracy of 'suspect' as a finder of wrong items.
export function balanced(rows, t) {
  const wrong = rows.filter(r => r.truth === 'wrong'), right = rows.filter(r => r.truth === 'right');
  if (!wrong.length || !right.length) return 0;
  const tpr = wrong.filter(r => triage(r.f, t) === 'suspect').length / wrong.length;
  const tnr = right.filter(r => triage(r.f, t) !== 'suspect').length / right.length;
  return (tpr + tnr) / 2;
}

/// Cohen's kappa between 'suspect' and the label 'wrong'.
export function kappa(rows, t) {
  const n = rows.length;
  if (!n) return 0;
  let a = 0, b = 0, c = 0, d = 0;
  for (const r of rows) {
    const s = triage(r.f, t) === 'suspect', w = r.truth === 'wrong';
    if (s && w) a++; else if (s) b++; else if (w) c++; else d++;
  }
  const po = (a + d) / n;
  const pe = ((a + b) * (a + c) + (c + d) * (b + d)) / (n * n);
  return pe === 1 ? 1 : (po - pe) / (1 - pe);
}

/// The thresholds, tuned on one half by balanced accuracy (§22a: "cutoff by
/// balanced accuracy ... confirm on the held-out half"); `pass` is the
/// smallest margin above which no tuning item is wrong (so 'pass' is
/// conservative). Reports both halves.
export function tune(rows) {
  const usable = rows.filter(r => r.f && (r.truth === 'right' || r.truth === 'wrong'));
  const fit = usable.filter(r => half(r.id) === 0), hold = usable.filter(r => half(r.id) === 1);
  const margins = [...new Set(fit.map(r => r.f.margin))].sort((x, y) => x - y);
  let best = { suspect: -Infinity, score: -1 };
  for (const m of margins) {
    const score = balanced(fit, { suspect: m, pass: Infinity });
    if (score > best.score) best = { suspect: m, score };
  }
  const wrongMargins = fit.filter(r => r.truth === 'wrong').map(r => r.f.margin);
  const pass = wrongMargins.length ? Math.max(...wrongMargins) + 1e-9 : Infinity;
  const t = { suspect: best.suspect, pass: Math.max(pass, best.suspect + 1e-9) };
  const report = list => ({
    n: list.length, wrong: list.filter(r => r.truth === 'wrong').length,
    balanced: balanced(list, t), kappa: kappa(list, t),
    passWrong: list.filter(r => r.truth === 'wrong' && triage(r.f, t) === 'pass').length,
    passed: list.filter(r => triage(r.f, t) === 'pass').length,
  });
  return { thresholds: t, fit: report(fit), held: report(hold) };
}

/// How many labelled items a gate needs (§22a): 300 per gate to tune and
/// confirm (150 + 150), 200 for kappa >= 0.8 on card/MCQ triage; and, for a
/// claim that the gate misses at most `rate` with 95% confidence and none
/// missed, ln(0.05)/ln(1 - rate) positives (the rule of three, about 3/rate).
export function labelsNeeded(rate = 0.01) {
  return { tune: 300, kappa: 200, positivesForRecall: Math.ceil(Math.log(0.05) / Math.log(1 - rate)) };
}
