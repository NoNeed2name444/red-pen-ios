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
import { labelsNeeded } from './triage-lib.mjs';

export function measure(rows) {
  let tp = 0, fn = 0, fp = 0, tn = 0;
  const missed = [];
  for (const r of rows) {
    const said = oathCheck(r.text).oath;
    if (r.oath && said) tp++; else if (r.oath) { fn++; missed.push(r.text); } else if (said) fp++; else tn++;
  }
  // with k misses in n positives, the one-sided 95% lower bound on recall
  // (exact for k = 0: 0.05^(1/n))
  const pos = tp + fn;
  const lower = pos && !fn ? Math.pow(0.05, 1 / pos) : null;
  return { tp, fn, fp, tn, recall: pos ? tp / pos : null, precision: tp + fp ? tp / (tp + fp) : null, lower, missed };
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const rows = process.argv.slice(2).flatMap(f => readFileSync(f, 'utf8').split('\n').filter(l => l.trim()).map(l => JSON.parse(l)));
  const m = measure(rows);
  const need = labelsNeeded(0.01);
  const pct = x => (x === null ? 'n/a' : `${(100 * x).toFixed(1)}%`);
  console.log(`# Layer 7 oath check\n\n${rows.length} labelled claims, ${m.tp + m.fn} oath.\n`);
  console.log(`| recall | lower bound (95%) | precision | missed | false alarms |\n|---|---|---|---|---|`);
  console.log(`| ${pct(m.recall)} | ${pct(m.lower)} | ${pct(m.precision)} | ${m.fn} | ${m.fp} |\n`);
  for (const t of m.missed) console.log(`- missed: ${t}`);
  console.log(`\n§22a's bar: recall >= 0.99 on 200 labelled claims, no miss. To show recall >= 0.99 at 95% confidence with none missed takes ${need.positivesForRecall} oath claims.`);
  process.exit(m.fn ? 1 : 0);
}
