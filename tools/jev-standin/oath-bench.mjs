// Layer 7 of the open stand-in for Jev (§22a): the oath check (server/oath.js,
// our own rules plus the source proof, fail closed) measured on labelled
// claims. §22a's bar: recall of at least 0.99 on 200 labelled claims, and any
// miss blocks launch; so this exits 1 on any miss.
//
//   node tools/jev-standin/oath-bench.mjs labels.jsonl [more.jsonl ...]
//   each line: { "text": "...", "oath": true | false }
//
// oath-seed.jsonl is a seed, written to exercise the rules, not the owner's
// labels: the launch bar needs our own labelled claims (see report).
import { readFileSync } from 'node:fs';
import { oathCheck } from '../../server/oath.js';
import { labelsNeeded, half } from './triage-lib.mjs';

/// The one-sided 95% lower bound on a rate from k successes in n (exact,
/// Clopper-Pearson): the p at which k or more successes have chance 0.05.
export function lowerBound(k, n, alpha = 0.05) {
  if (!n) return null;
  if (k === n) return Math.pow(alpha, 1 / n);
  if (k === 0) return 0;
  const lgamma = x => { // Lanczos
    const g = 7, c = [0.99999999999980993, 676.5203681218851, -1259.1392167224028, 771.32342877765313, -176.61502916214059, 12.507343278686905, -0.13857109526572012, 9.9843695780195716e-6, 1.5056327351493116e-7];
    if (x < 0.5) return Math.log(Math.PI / Math.sin(Math.PI * x)) - lgamma(1 - x);
    x -= 1; let a = c[0]; const t = x + g + 0.5;
    for (let i = 1; i < g + 2; i++) a += c[i] / (x + i);
    return 0.5 * Math.log(2 * Math.PI) + (x + 0.5) * Math.log(t) - t + Math.log(a);
  };
  const tail = p => { let s = 0; for (let i = k; i <= n; i++) s += Math.exp(lgamma(n + 1) - lgamma(i + 1) - lgamma(n - i + 1) + i * Math.log(p) + (n - i) * Math.log(1 - p)); return s; };
  let lo = 0, hi = k / n;
  for (let i = 0; i < 60; i++) { const mid = (lo + hi) / 2; if (tail(mid) < alpha) lo = mid; else hi = mid; }
  return (lo + hi) / 2;
}

export function measure(rows) {
  let tp = 0, fn = 0, fp = 0, tn = 0;
  const missed = [];
  for (const r of rows) {
    const said = oathCheck(r.text).oath;
    if (r.oath && said) tp++; else if (r.oath) { fn++; missed.push(r.text); } else if (said) fp++; else tn++;
  }
  // the one-sided 95% lower bound on recall (exact; 0.05^(1/n) with no miss)
  const pos = tp + fn;
  const lower = lowerBound(tp, pos);
  return { tp, fn, fp, tn, recall: pos ? tp / pos : null, precision: tp + fp ? tp / (tp + fp) : null, lower, missed };
}

if (import.meta.url === `file://${process.argv[1]}`) {
  // --report: measure and report, but a miss does not fail the command
  // (the public FDA set measures the rules; the launch bar is our own labels)
  const report = process.argv.includes('--report');
  const files = process.argv.slice(2).filter(a => !a.startsWith('--'));
  const rows = files.flatMap(f => readFileSync(f, 'utf8').split('\n').filter(l => l.trim()).map(l => JSON.parse(l)));
  const need = labelsNeeded(0.01);
  const pct = x => (x === null ? 'n/a' : `${(100 * x).toFixed(1)}%`);
  const line = (name, m) => `| ${name} | ${m.tp + m.fn} | ${pct(m.recall)} | ${pct(m.lower)} | ${pct(m.precision)} | ${m.fn} | ${m.fp} |`;
  const m = measure(rows);
  console.log(`# Layer 7 oath check\n\n${files.join(', ')}: ${rows.length} labelled claims, ${m.tp + m.fn} oath.\n`);
  console.log(`| set | oath claims | recall | lower bound (95%) | precision | missed | false alarms |\n|---|---|---|---|---|---|---|`);
  console.log(line('all', m));
  // rows with ids (the public sets) split as the rules were developed: on
  // half 0 only, so half 1 is the honest, held-out number
  if (rows.every(r => r.id)) {
    console.log(line('developed on (half 0)', measure(rows.filter(r => half(r.id) === 0))));
    console.log(line('held out (half 1)', measure(rows.filter(r => half(r.id) === 1))));
  }
  console.log('');
  for (const t of m.missed.slice(0, 30)) console.log(`- missed: ${t}`);
  console.log(`\n§22a's bar: recall >= 0.99 on 200 labelled claims, no miss. To show recall >= 0.99 at 95% confidence with none missed takes ${need.positivesForRecall} oath claims.`);
  process.exit(m.fn && !report ? 1 : 0);
}
