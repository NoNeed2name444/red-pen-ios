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
  rows.push({ id: s.id, gate: item.gate || 'all', truth: item.truth || null, source: item.source || 'own', f });
}
const need = labelsNeeded(0.01);
const pct = x => `${(100 * x).toFixed(1)}%`;
const out = [`# Layer 6 triage (open NLI cross-encoder)`, '', `${rows.length} items scored, ${rows.filter(r => r.truth).length} labelled.`, ''];
// each gate tuned on its own: a question, a card and a health claim read
// differently, so one cut-off for all would fit none
const gates = [...new Set(rows.map(r => r.gate))];
const thresholds = {};
const summary = {};
out.push(`| gate | half | items | wrong | balanced accuracy | kappa | passed | wrong passed |`, `|---|---|---|---|---|---|---|---|`);
const notes = [];
for (const gate of gates) {
  const labelled = rows.filter(r => r.gate === gate && r.truth);
  if (labelled.filter(r => r.truth === 'wrong').length < 10 || labelled.filter(r => r.truth === 'right').length < 10) {
    notes.push(`${gate}: too few labels to tune (at least 10 right and 10 wrong; §22a asks for ${need.tune} per gate).`);
    continue;
  }
  const t = tune(labelled);
  thresholds[gate] = t.thresholds;
  summary[gate] = { fit: t.fit, held: t.held };
  for (const [name, r] of [['tuned on', t.fit], ['held out', t.held]]) {
    out.push(`| ${gate} | ${name} | ${r.n} | ${r.wrong} | ${pct(r.balanced)} | ${r.kappa.toFixed(3)} | ${r.passed} | ${r.passWrong} |`);
  }
  notes.push(`${gate}: suspect at a margin of ${t.thresholds.suspect.toFixed(4)} or below, pass at ${t.thresholds.pass.toFixed(4)} or above; held-out kappa ${t.held.kappa.toFixed(3)} on ${t.held.n} (§22a bar 0.8 on ${need.kappa}: ${t.held.kappa >= 0.8 && t.held.n >= need.kappa ? 'met' : t.held.kappa >= 0.8 ? 'met on fewer labels' : 'not met'}).`);
}
out.push('', ...notes.map(n => `- ${n}`));
const counts = { suspect: 0, review: 0, pass: 0 };
for (const r of rows) if (thresholds[r.gate]) counts[triage(r.f, thresholds[r.gate])]++;
out.push('', `Triage of the tuned gates' items: ${counts.suspect} suspect, ${counts.review} review, ${counts.pass} pass. A triage only orders work; it never verifies.`);
writeFileSync(join(outDir, 'report.md'), out.join('\n') + '\n');
writeFileSync(join(outDir, 'thresholds.json'), JSON.stringify({ thresholds, summary, labelled: rows.filter(r => r.truth).length, need }, null, 1) + '\n');
console.log(out.join('\n'));
