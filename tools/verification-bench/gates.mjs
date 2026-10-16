// What held each check back from Verified, and what a bench run cost: every
// condition the verdict (server/accuracy-model.js verdict) asks for, counted
// on a bench's results by truth, and why the source proof (proof.js) said no;
// then, per run, the cost and the quality of the numbers around the verdict
// (docs/verification/rag-plan.md section 5, "Value, reported per run"):
//
//   - the conditions table for Verified, by truth
//   - neurons per check (each reply's usage times NEURON_RATES, server/ai.js,
//     else the Worker's own estimate)
//   - CPU per batch (process.cpuUsage, as server/tests/claims.test.mjs)
//   - external fetches per batch (counted in the fetcher)
//   - the share of votes saying "evidence: none"
//   - families answering per check
//   - the calibration of P(accurate): Brier score and a 5-bin reliability
//     table, by truth
//
// docs/verification/why-not-verified.md was written from the first table.
//
//   node tools/verification-bench/gates.mjs runs/<id>/results.json [--run runs/<id>/run.json]
import { readFileSync } from 'node:fs';
import { DEFAULT_WEIGHTS, MIN_VERIFY_VOTERS, familyOf } from '../../server/accuracy-model.js';

/// Each condition of Verified, as a test of one check's saved result: the
/// seven conditions of verdict() (P(accurate), no sensor, enough voters,
/// independent families, unanimity, the blind solves, the proof), after the
/// one before them all, that a checker answered. The proof is the source's
/// word for word, or - with the vignette route on - a proven packet.
export const GATES = [
  ['a checker answered', r => !r.features?.no_models],
  [`P(accurate) >= ${DEFAULT_WEIGHTS.thresholds.verified}`, r => (Number(r.p) || 0) >= DEFAULT_WEIGHTS.thresholds.verified],
  ['no sensor fired', r => !r.features?.rule_severe && !r.features?.rule_minor],
  [`${MIN_VERIFY_VOTERS} checkers read it`, r => Math.round((r.features?.voters || 0) * 3) >= MIN_VERIFY_VOTERS],
  [`${MIN_VERIFY_VOTERS} families passed it`, r => (r.features?.families || 0) >= MIN_VERIFY_VOTERS],
  ['no concern, no literature against it', r => !r.features?.flag_frac && !r.features?.ev_contradict],
  [`${MIN_VERIFY_VOTERS} blind families on the key, none elsewhere`, r => (r.features?.blind_agree || 0) >= MIN_VERIFY_VOTERS && !r.features?.blind_dissent],
  ['an official source states it word for word', r => r.features?.source_proof === 1 || r.features?.vignette_proof === 1],
];

/// The conditions table: for each truth, how many checks met each condition,
/// how many failed only that one, and why the proof said no.
export function conditionsReport(rows) {
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

// MARK: neurons

/// Neurons per million tokens, [input, output], read from server/ai.js's
/// NEURON_RATES (the table is not exported, and this file may not change the
/// server), so the bench never keeps a second copy that could drift.
export function neuronRates(source = readFileSync(new URL('../../server/ai.js', import.meta.url), 'utf8')) {
  const block = source.match(/const NEURON_RATES = \{([\s\S]*?)\n\};/);
  const rates = {};
  if (block) for (const m of block[1].matchAll(/'([^']+)':\s*\[\s*([\d.]+)\s*,\s*([\d.]+)\s*\]/g)) rates[m[1]] = [Number(m[2]), Number(m[3])];
  return rates;
}
export const NEURON_RATES = neuronRates();
/// What the Worker rates a model it has no row for at (ai.js askWorkersAI).
const FALLBACK_RATE = '@cf/nvidia/nemotron-3-120b-a12b';

/// The Workers AI model a pin or model name names ("workers-ai:@cf/..",
/// "bench:workers-ai:@cf/.."), or null for any other family (no neurons).
export function workersModel(name) {
  const m = String(name || '').match(/(?:^|:)workers-ai:(@cf\/.+)$/) || String(name || '').match(/^(@cf\/.+)$/);
  return m ? m[1] : null;
}

/// The neurons one model call took. From the reply's own usage
/// (prompt_tokens, completion_tokens) times the model's rates; else the
/// Worker's estimate when it takes them (askWorkersAI): a quarter of the
/// prompt's characters in, `maxTokens` out. 0 for a model that is not on
/// Workers AI. `basis` says which.
export function neuronsOf(call, rates = NEURON_RATES) {
  const model = workersModel(call.model);
  if (!model) return { neurons: 0, basis: 'none' };
  const [rin, rout] = rates[model] || rates[FALLBACK_RATE] || [0, 0];
  const input = Number(call.usage?.prompt_tokens ?? call.usage?.input_tokens);
  const output = Number(call.usage?.completion_tokens ?? call.usage?.output_tokens);
  if (Number.isFinite(input) && Number.isFinite(output) && input >= 0 && output >= 0) {
    return { neurons: input * rin / 1e6 + output * rout / 1e6, basis: 'usage' };
  }
  return { neurons: ((Number(call.chars) || 0) / 4) * rin / 1e6 + (Number(call.maxTokens) || 0) * rout / 1e6, basis: 'estimate' };
}

const percentile = (list, q) => {
  if (!list.length) return null;
  const s = [...list].sort((a, b) => a - b);
  return s[Math.min(s.length - 1, Math.ceil(q * s.length) - 1)];
};
const mean = list => (list.length ? list.reduce((a, b) => a + b, 0) / list.length : null);
const fmt = (x, d = 1) => (x === null || x === undefined || Number.isNaN(x) ? 'n/a' : x.toFixed(d));
const pct = (a, b) => (b ? `${(100 * a / b).toFixed(1)}%` : 'n/a');

/// Neurons per check over a run's batches: each batch's neurons shared over
/// its items, then the mean and the 95th percentile of those, the total, and
/// how many calls were counted from usage and how many estimated.
/// `batches`: [{ items, calls: [{ model, usage?, chars, maxTokens }] }].
export function neuronSummary(batches, rates = NEURON_RATES) {
  const perCheck = [];
  let total = 0, usage = 0, estimate = 0, checks = 0;
  for (const b of batches) {
    let n = 0;
    for (const call of b.calls || []) {
      const r = neuronsOf(call, rates);
      n += r.neurons;
      if (r.basis === 'usage') usage++; else if (r.basis === 'estimate') estimate++;
    }
    total += n;
    const items = b.items || 0;
    checks += items;
    for (let i = 0; i < items; i++) perCheck.push(n / items);
  }
  return { checks, total, mean: mean(perCheck), p95: percentile(perCheck, 0.95), fromUsage: usage, estimated: estimate };
}

// MARK: CPU and fetches

/// The batches' CPU (ms) and external fetches (lookups and model calls),
/// as the median, the 95th percentile and the largest.
export function costSummary(batches) {
  const cpu = batches.map(b => b.cpuMs).filter(Number.isFinite);
  const lookups = batches.map(b => b.lookups).filter(Number.isFinite);
  const models = batches.map(b => (b.calls || []).length);
  const fetches = batches.map(b => (Number.isFinite(b.lookups) ? b.lookups : 0) + (b.calls || []).length);
  const stat = list => ({ median: percentile(list, 0.5), p95: percentile(list, 0.95), max: list.length ? Math.max(...list) : null });
  return { batches: batches.length, cpu: stat(cpu), lookups: stat(lookups), models: stat(models), fetches: stat(fetches) };
}

/// CPU time so far, in ms: what a Worker request is charged for (and, unlike
/// a clock, it stands still while the machine runs something else); the same
/// reading as server/tests/claims.test.mjs.
export const cpuMs = () => { const u = process.cpuUsage(); return (u.user + u.system) / 1000; };

// MARK: votes and calibration

/// The share of votes that said "evidence: none" (the literature shown did
/// not cover the item), over every vote that carries an evidence field.
export function evidenceNone(rows) {
  let none = 0, votes = 0;
  for (const r of rows) for (const v of r.votes || []) { if (!v || typeof v.evidence !== 'string') continue; votes++; if (v.evidence === 'none') none++; }
  return { none, votes };
}

/// Families answering each check: how many checks had 0, 1, 2, 3... distinct
/// model families vote, and the mean.
export function familiesPerCheck(rows) {
  const hist = {};
  const counts = rows.map(r => new Set((r.votes || []).filter(v => v?.model).map(v => familyOf(v.model))).size);
  for (const c of counts) hist[c] = (hist[c] || 0) + 1;
  return { hist, mean: mean(counts), checks: rows.length };
}

/// Calibration of P(accurate): the Brier score (mean squared gap between P
/// and what happened: 1 for a right key, 0 for a wrong one) and a 5-bin
/// reliability table; each bin's checks, their mean P, and the share that
/// really were right. Over `rows` as given; a row with no P is left out.
export function calibration(rows, bins = 5) {
  const scored = rows.filter(r => Number.isFinite(Number(r.p)) && r.p !== null && (r.truth === 'right' || r.truth === 'wrong'));
  const table = Array.from({ length: bins }, (_, i) => ({ lo: i / bins, hi: (i + 1) / bins, n: 0, meanP: 0, right: 0 }));
  let sum = 0;
  for (const r of scored) {
    const p = Math.min(1, Math.max(0, Number(r.p)));
    const y = r.truth === 'right' ? 1 : 0;
    sum += (p - y) ** 2;
    const b = table[Math.min(bins - 1, Math.floor(p * bins))];
    b.n++; b.meanP += p; b.right += y;
  }
  for (const b of table) if (b.n) b.meanP /= b.n;
  return { n: scored.length, brier: scored.length ? sum / scored.length : null, bins: table };
}

// MARK: the report

/// The run's whole gates report: the conditions table, then (when `run` is
/// given) its costs, and the votes and calibration from the results.
/// `run`: { batches: [{ items, cpuMs, lookups, calls: [...] }] }.
export function gateReport(rows, run = null) {
  const out = [conditionsReport(rows)];
  const verified = rows.filter(r => r.verdict === 'verified');
  const kept = rows.filter(r => r.truth === 'right' || r.truth === 'wrong');
  const none = evidenceNone(rows);
  out.push('## Cost and quality of this run', '');
  out.push('| measure | result |', '|---|---|');
  out.push(`| Verified, by truth | right ${verified.filter(r => r.truth === 'right').length}, wrong ${verified.filter(r => r.truth === 'wrong').length} |`);
  out.push(`| votes saying "evidence: none" | ${pct(none.none, none.votes)} (${none.none} of ${none.votes}) |`);
  for (const truth of ['right', 'wrong']) {
    const f = familiesPerCheck(rows.filter(r => r.truth === truth));
    if (!f.checks) continue;
    out.push(`| families answering per check, ${truth} keys | mean ${fmt(f.mean, 2)}; ${Object.entries(f.hist).sort((a, b) => a[0] - b[0]).map(([k, n]) => `${k} famil${k === '1' ? 'y' : 'ies'}: ${n}`).join(', ')} |`);
  }
  const batches = run?.batches || [];
  if (batches.length) {
    const nu = neuronSummary(batches);
    const c = costSummary(batches);
    out.push(`| neurons per check | mean ${fmt(nu.mean)}, p95 ${fmt(nu.p95)}; ${fmt(nu.total, 0)} in all over ${nu.checks} checks (${nu.fromUsage} calls from a reply's usage, ${nu.estimated} estimated as the Worker does) |`);
    out.push(`| CPU per batch (ms) | median ${fmt(c.cpu.median)}, p95 ${fmt(c.cpu.p95)}, max ${fmt(c.cpu.max)} (${c.batches} batches) |`);
    out.push(`| external fetches per batch | median ${fmt(c.fetches.median, 0)}, p95 ${fmt(c.fetches.p95, 0)}, max ${fmt(c.fetches.max, 0)}: lookups max ${fmt(c.lookups.max, 0)}, model calls max ${fmt(c.models.max, 0)} |`);
  } else {
    out.push('| neurons, CPU and fetches per batch | n/a (no per-batch record: the live Worker checked these) |');
  }
  const cal = calibration(kept);
  out.push('', `### Calibration of P(accurate)`, '');
  const byTruth = ['right', 'wrong'].map(t => ({ t, c: calibration(kept.filter(r => r.truth === t)) })).filter(x => x.c.n);
  out.push(`Brier score ${fmt(cal.brier, 3)} over ${cal.n} checks (0 is perfect; 0.25 is a coin); ${byTruth.map(x => `${x.t} keys ${fmt(x.c.brier, 3)} (${x.c.n})`).join(', ')}.`, '');
  out.push('| P(accurate) | checks | right keys | wrong keys | mean P | share right |', '|---|---|---|---|---|---|');
  const rightBins = calibration(kept.filter(r => r.truth === 'right')).bins, wrongBins = calibration(kept.filter(r => r.truth === 'wrong')).bins;
  cal.bins.forEach((b, i) => {
    out.push(`| ${b.lo.toFixed(1)} to ${b.hi.toFixed(1)} | ${b.n} | ${rightBins[i].n} | ${wrongBins[i].n} | ${b.n ? fmt(b.meanP, 2) : '-'} | ${b.n ? pct(b.right, b.n) : '-'} |`);
  });
  out.push('');
  return out.join('\n');
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const args = process.argv.slice(2);
  const at = args.indexOf('--run');
  const run = at >= 0 ? JSON.parse(readFileSync(args[at + 1], 'utf8')) : null;
  const files = args.filter((a, i) => a !== '--run' && !(at >= 0 && i === at + 1));
  const rows = files.flatMap(f => JSON.parse(readFileSync(f, 'utf8')));
  console.log(gateReport(rows, run));
}
