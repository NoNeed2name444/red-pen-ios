// Layer 6's thresholds and triage, from score_nli.py's scores and the
// items' labels (triage-lib.mjs). Writes report.md and thresholds.json.
//
//   node tools/jev-standin/triage.mjs --items items.jsonl --scores scores.jsonl --out DIR
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { join } from 'node:path';
import { questionFeatures, cardFeatures, triage, tune, labelsNeeded } from './triage-lib.mjs';

const arg = (name, fallback = null) => { const i = process.argv.indexOf(`--${name}`); return i > 0 ? process.argv[i + 1] : fallback; };
const lines = f => readFileSync(f, 'utf8').split('\n').filter(l => l.trim()).map(l => JSON.parse(l));
const items = new Map(lines(arg('items')).map(r => [r.id, r]));
const outDir = arg('out', 'out/jev-standin');
mkdirSync(outDir, { recursive: true });
const rows = [];
for (const s of lines(arg('scores'))) {
  const item = items.get(s.id);
  if (!item) continue;
  const f = item.kind === 'card' ? cardFeatures(s.scores[0]) : questionFeatures(s.scores, item.key);
  rows.push({ id: s.id, truth: item.truth || null, source: item.source || 'own', f });
}
const labelled = rows.filter(r => r.truth);
const need = labelsNeeded(0.01);
const pct = x => `${(100 * x).toFixed(1)}%`;
const out = [`# Layer 6 triage (open NLI cross-encoder)`, '', `${rows.length} items scored, ${labelled.length} labelled.`, ''];
let thresholds = null;
if (labelled.filter(r => r.truth === 'wrong').length >= 10 && labelled.filter(r => r.truth === 'right').length >= 10) {
  const t = tune(labelled);
  thresholds = t.thresholds;
  out.push(`| half | items | wrong | balanced accuracy | kappa | passed | wrong passed |`, `|---|---|---|---|---|---|---|`);
  for (const [name, r] of [['tuned on', t.fit], ['held out', t.held]]) {
    out.push(`| ${name} | ${r.n} | ${r.wrong} | ${pct(r.balanced)} | ${r.kappa.toFixed(3)} | ${r.passed} | ${r.passWrong} |`);
  }
  out.push('', `Thresholds (key's margin over the best other option): suspect at ${t.thresholds.suspect.toFixed(4)} or below, pass at ${t.thresholds.pass.toFixed(4)} or above.`);
  out.push(`The §22a pilot bar: kappa of at least 0.8 on ${need.kappa} labels; held out here: ${t.held.kappa.toFixed(3)} (${t.held.kappa >= 0.8 ? 'met' : 'not met'}).`);
} else {
  out.push(`Too few labels to tune: at least 10 right and 10 wrong are needed to run, and §22a asks for ${need.tune} of our own per gate (${need.kappa} for the kappa bar).`);
}
const counts = { suspect: 0, review: 0, pass: 0 };
if (thresholds) for (const r of rows) counts[triage(r.f, thresholds)]++;
if (thresholds) out.push('', `Triage of all ${rows.length}: ${counts.suspect} suspect, ${counts.review} review, ${counts.pass} pass. A triage only orders work; it never verifies.`);
writeFileSync(join(outDir, 'report.md'), out.join('\n') + '\n');
writeFileSync(join(outDir, 'thresholds.json'), JSON.stringify({ thresholds, labelled: labelled.length, need }, null, 1) + '\n');
console.log(out.join('\n'));
