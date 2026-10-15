// What held each check back from Verified: every condition the verdict
// (server/accuracy-model.js verdict) asks for, counted on a bench's results,
// and why the source proof (proof.js) said no. docs/verification/
// why-not-verified.md was written from this.
//
//   node tools/verification-bench/gates.mjs runs/<id>/results.json
import { readFileSync } from 'node:fs';
import { DEFAULT_WEIGHTS, MIN_VERIFY_VOTERS } from '../../server/accuracy-model.js';

/// Each condition of Verified, as a test of one check's saved result.
export const GATES = [
  ['a checker answered', r => !r.features?.no_models],
  [`P(accurate) >= ${DEFAULT_WEIGHTS.thresholds.verified}`, r => (Number(r.p) || 0) >= DEFAULT_WEIGHTS.thresholds.verified],
  ['no sensor fired', r => !r.features?.rule_severe && !r.features?.rule_minor],
  [`${MIN_VERIFY_VOTERS} checkers read it`, r => Math.round((r.features?.voters || 0) * 3) >= MIN_VERIFY_VOTERS],
  [`${MIN_VERIFY_VOTERS} families passed it`, r => (r.features?.families || 0) >= MIN_VERIFY_VOTERS],
  ['no concern, no literature against it', r => !r.features?.flag_frac && !r.features?.ev_contradict],
  [`${MIN_VERIFY_VOTERS} blind families on the key, none elsewhere`, r => (r.features?.blind_agree || 0) >= MIN_VERIFY_VOTERS && !r.features?.blind_dissent],
  ['an official source states it word for word', r => r.features?.source_proof === 1],
];

export function gateReport(rows) {
  const out = [];
  for (const truth of ['right', 'wrong']) {
    const list = rows.filter(r => r.truth === truth);
    if (!list.length) continue;
    out.push(`### ${truth === 'right' ? 'Right keys' : 'Wrong keys planted'} (${list.length})`, '', '| condition | met | the only one not met |', '|---|---|---|');
    for (const [name, test] of GATES) {
      const met = list.filter(test).length;
      const only = list.filter(r => !test(r) && GATES.every(([n, t]) => n === name || t(r))).length;
      out.push(`| ${name} | ${met} | ${only} |`);
    }
    const all = list.filter(r => GATES.every(([, t]) => t(r))).length;
    const butProof = list.filter(r => GATES.slice(0, -1).every(([, t]) => t(r))).length;
    out.push('', `Every condition met: ${all}. Every condition but the source proof: ${butProof}.`);
    const whys = {};
    for (const r of list) { const w = r.proof?.why || (r.proof ? 'proven' : 'none'); whys[w] = (whys[w] || 0) + 1; }
    out.push(`Why the proof said no: ${Object.entries(whys).sort((a, b) => b[1] - a[1]).map(([w, n]) => `${w} ${n}`).join(', ')}.`, '');
  }
  return out.join('\n');
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const rows = process.argv.slice(2).flatMap(f => JSON.parse(readFileSync(f, 'utf8')));
  console.log(gateReport(rows));
}
