// The proof-only bench P (docs/verification/rag-plan.md A3): how often the
// source proof alone reaches "fully proven", and why it does not, measured
// before the proof or its lookups are changed. It spends 0 neurons: no model
// is asked, and the network is used only to read the official sources
// (MedlinePlus, openFDA) and the questions.
//
// Items: 600 readable one-sentence questions from the proof ladder's training
// splits (tools/proof-ladder/ladder.mjs pick: each question once, half of them,
// by id, keyed with a wrong option by itemOf), plus the 90 bench questions
// (seed 7, 30 a source), each with its true key and with a wrong key planted
// (the bench's 180 checks, as layer.mjs makes them).
//
// Each item runs what checkBatch (server/accuracy.js) runs for the proof,
// in its order, in batches of four sharing their lookups and their reading
// budget: itemTerms (what to look up), officialFor (the official sources),
// prove(), then fullyProven. Reported: fullyProven and the proof.why
// histogram, each split by truth - and the lookups that failed (a rate limit,
// an error, no answer) counted APART from "not proven": an item whose source
// could not be read is a failed lookup, never evidence about the proof.
//
//   node tools/verification-bench/proof-only.mjs [--limit N] [--only ladder|bench] [--ladder 600] [--data DIR] [--cache DIR] [--out DIR]
//
// --data: where tools/verification-bench/fetch.sh put the bench questions;
// --cache: a directory kept between runs for what was fetched (never in the
// repository; at most 200 MB); --limit N: the first N items of the two lists
// merged in proportion (a sample).
import { readdirSync, writeFileSync, mkdirSync } from 'node:fs';
import { join } from 'node:path';
import { itemTerms, officialFor } from '../../server/accuracy.js';
import { prove, fullyProven, PROOF_CHARS } from '../../server/proof.js';
import { pick } from '../proof-ladder/ladder.mjs';
import { loadQuestions, benchCases } from './datasets.mjs';
import { diskCache, cachedFetcher, newTally, jsonPage } from './lookup-cache.mjs';

export const BATCH = 4;

/// Two lists merged in proportion to their lengths, each in its own order,
/// so that the first N of the result are a fair sample of both (`totalA` and
/// `totalB` are the lists' full lengths, when a list was cut short).
export function interleave(a, b, totalA = a.length, totalB = b.length) {
  const tagged = [...a.map((x, i) => [(i + 0.5) / totalA, x]), ...b.map((x, i) => [(i + 0.5) / totalB, x])];
  return tagged.sort((x, y) => x[0] - y[0]).map(t => t[1]);
}

/// One batch through the proof, as proofStage (accuracy.js) shares the
/// reading budget: the sources of every item looked up together, then each
/// item proved in order with what is left. Returns one record per item:
/// { id, truth, group, queries, drugs, entries, unread, failed, proven, why }.
/// `failed`: a source could not be read (or the lookup threw); then an item
/// that is not proven is a failed lookup, not a "not proven".
export async function proveBatch(batch, fetcher, { chars = PROOF_CHARS } = {}) {
  const seen = new Map();
  const looked = await Promise.all(batch.map(x => officialFor(x.item, fetcher, seen).catch(() => null)));
  const lookups = seen.size;
  let left = chars;
  const kept = Math.floor(chars / batch.length / 2);
  const paid = new Map();
  const out = batch.map((x, n) => {
    const terms = itemTerms(x.item);
    const base = { id: x.item.id, truth: x.truth, group: x.group, queries: terms.queries, drugs: terms.drugs, lookups };
    if (!looked[n]) return { ...base, entries: 0, unread: 1, failed: true, proven: false, why: 'error' };
    const { entries, unread } = looked[n];
    const share = Math.max(0, left - kept * (batch.length - n - 1));
    let proof;
    try {
      const { read, ...p } = prove(x.item, entries, { chars: share, paid, unread });
      left -= read;
      proof = p;
    } catch { return { ...base, entries: entries.length, unread, failed: true, proven: false, why: 'error' }; }
    const proven = fullyProven(proof);
    const why = proven ? null : proof.why || 'unproven';
    // A13: network failures alone count as failed lookup, apart from budget skips
    const failed = unread > 0 && why !== 'budget';
    return { ...base, entries: entries.length, unread, failed, proven, why };
  });
  out.lookups = lookups;
  return out;
}

/// Where an unproven item's story ends: proven; a failed lookup (its source
/// could not be read, so nothing is known about the proof); or not proven,
/// with proof.why.
export const outcomeOf = r => (r.proven ? 'proven' : r.failed ? 'lookup failed' : 'not proven');

/// The report's numbers from the records: by truth (and by group), how many
/// were proven, not proven (with the why histogram) and lookup-failed, and
/// the wrong keys proven (a false proof: must be 0).
export function summarize(records) {
  const part = list => {
    const out = { n: list.length, proven: 0, notProven: 0, lookupFailed: 0, unreadButProven: 0, why: {} };
    for (const r of list) {
      const o = outcomeOf(r);
      if (o === 'proven') { out.proven++; if (r.failed) out.unreadButProven++; }
      else if (o === 'lookup failed') { out.lookupFailed++; out.why[`LOOKUP FAILED (${r.why})`] = (out.why[`LOOKUP FAILED (${r.why})`] || 0) + 1; }
      else { out.notProven++; out.why[r.why] = (out.why[r.why] || 0) + 1; }
    }
    return out;
  };
  const groups = [...new Set(records.map(r => r.group))];
  const batchLookups = [];
  for (let i = 0; i < records.length; i += BATCH) {
    const chunk = records.slice(i, i + BATCH);
    if (chunk.length && typeof chunk[0].lookups === 'number') batchLookups.push(chunk[0].lookups);
  }
  return {
    all: part(records),
    right: part(records.filter(r => r.truth === 'right')),
    wrong: part(records.filter(r => r.truth === 'wrong')),
    byGroup: Object.fromEntries(groups.map(g => [g, { right: part(records.filter(r => r.group === g && r.truth === 'right')), wrong: part(records.filter(r => r.group === g && r.truth === 'wrong')) }])),
    wrongProven: records.filter(r => r.truth === 'wrong' && r.proven).map(r => r.id),
    ...(batchLookups.length ? { lookupsPerBatch: { mean: batchLookups.reduce((a, b) => a + b, 0) / batchLookups.length, max: Math.max(...batchLookups) } } : {}),
  };
}

const pc = (a, b) => (b ? `${(100 * a / b).toFixed(1)}%` : 'n/a');

export function reportFor(records, tally, notes = []) {
  const s = summarize(records);
  const lines = ['# Proof-only bench P', '', `${records.length} items (${s.right.n} right keys, ${s.wrong.n} wrong keys planted). No model was asked: 0 neurons.`, ''];
  const row = (label, p) => `| ${label} | ${p.n} | ${p.proven} (${pc(p.proven, p.n)}) | ${p.notProven} | ${p.lookupFailed} |`;
  lines.push('| split | items | fully proven | not proven | lookup failed |', '|---|---|---|---|---|');
  lines.push(row('right keys', s.right), row('wrong keys', s.wrong), row('all', s.all));
  for (const [g, parts] of Object.entries(s.byGroup)) lines.push(row(`${g}, right keys`, parts.right), row(`${g}, wrong keys`, parts.wrong));
  lines.push('', `Wrong keys fully proven (false proofs; must be 0): ${s.wrongProven.length}${s.wrongProven.length ? ` - ${s.wrongProven.join(', ')}` : ''}.`);
  if (s.all.unreadButProven) lines.push(`${s.all.unreadButProven} proven items also had a source that could not be read.`);
  for (const [label, p] of [['Right keys', s.right], ['Wrong keys', s.wrong]]) {
    const hist = Object.entries(p.why).sort((a, b) => b[1] - a[1]).map(([w, n]) => `${w} ${n}`).join(', ');
    lines.push('', `${label}: proof.why when not proven: ${hist || 'none'}.`);
  }
  lines.push('', `Lookups: ${tally.lookups} (${tally.disk} from the disk cache, ${tally.network} network calls, ${tally.retried} retried, ${tally.failed} failed ${JSON.stringify(tally.byStatus)}).`);
  if (s.lookupsPerBatch) lines.push(`Lookups per batch of ${BATCH}: mean ${s.lookupsPerBatch.mean.toFixed(1)}, max ${s.lookupsPerBatch.max}.`);
  lines.push(...notes, '');
  return lines.join('\n');
}

async function main() {
  const arg = (name, fallback = null) => { const i = process.argv.indexOf(`--${name}`); return i > 0 ? process.argv[i + 1] : fallback; };
  const cache = diskCache(arg('cache', join(process.env.TMPDIR || '/tmp', 'ragbench-cache')));
  const tally = newTally();
  const fetcher = cachedFetcher({ cache, tally });
  const only = arg('only');
  const limit = Number(arg('limit', '0')) || Infinity;
  const outDir = arg('out', 'out/proof');
  mkdirSync(outDir, { recursive: true });

  const wantLadder = Number(arg('ladder', '600'));
  const need = Math.min(wantLadder, Math.ceil(limit * wantLadder / (wantLadder + 180)) + 1);
  const ladder = only === 'bench' ? [] : (await pick({ cursor: {} }, need, { page: jsonPage(fetcher) })).picked
    .map(p => ({ truth: p.truth, group: 'ladder', item: p.item }));
  const bench = only === 'ladder' ? [] : (() => {
    const data = arg('data', 'verification-bench-data');
    const all = loadQuestions(readdirSync(data).filter(f => f.endsWith('.json')).map(f => join(data, f)));
    return benchCases(all, { wanted: ['MedXpertQA', 'MedQA', 'CareQA Medicine'], perSource: 30, seed: 7 }).cases
      .map(c => ({ truth: c.truth, group: 'bench', item: c.item }));
  })();
  const items = (ladder.length && bench.length ? interleave(ladder, bench, wantLadder, bench.length) : [...ladder, ...bench]).slice(0, limit);
  const records = [];
  for (let b = 0; b < items.length; b += BATCH) {
    records.push(...await proveBatch(items.slice(b, b + BATCH), fetcher));
    process.stdout.write(`\r${records.length}/${items.length}`);
  }
  console.log('');
  const report = reportFor(records, tally, [`Cache ${(cache.used / 1e6).toFixed(1)} MB.`]);
  writeFileSync(join(outDir, 'proof-report.md'), report);
  writeFileSync(join(outDir, 'proof-results.json'), JSON.stringify(records, null, 1));
  console.log(report);
}

if (import.meta.url === `file://${process.argv[1]}`) main().catch(e => { console.error(e.message); process.exit(1); });
