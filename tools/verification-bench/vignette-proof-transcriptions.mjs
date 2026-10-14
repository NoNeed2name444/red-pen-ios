#!/usr/bin/env node
// B6, rule transcription (docs/verification/vignette-proof-research.md, the
// benches table): what the registry review (server/criteria/review.js)
// catches of a rule copied wrongly from its source.
//
// 1. As shipped: every rule file's transcriptions agree, its worked examples
//    pass, and the admitted and pending rules are what the registry says.
// 2. One transcriber's slip: every leaf of a rule's formal part (each
//    number, operator, unit, value, list item, quote, alias) changed in the
//    second transcription only. Check (a), the two compared by code, must
//    refuse every one.
// 3. A shared slip (both transcribers make the same error, the
//    formalisation gap): the same change made to the rule and both
//    transcriptions. What checks (b) and (c) - the quote against the pinned
//    source, the numbers read from its words, the worked examples - still
//    catch, and what gets through, listed: that remainder is what the
//    owner's sign-off is for.
//
//   node tools/verification-bench/vignette-proof-transcriptions.mjs [--out file.json]
//
// Exit 1 if a rule as shipped fails, or a one-sided slip gets through.

import { readFileSync, readdirSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { reviewRule } from '../../server/criteria/review.js';
import REGISTRY from '../../server/criteria/registry.js';

const root = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const dir = join(root, 'server', 'criteria');
const OUT = (i => (i > 0 ? process.argv[i + 1] : null))(process.argv.indexOf('--out'));
const sources = Object.fromEntries(JSON.parse(readFileSync(join(dir, 'sources.json'), 'utf8')).sources.map(s => [s.id, s]));
const snapshots = Object.fromEntries(Object.values(sources).map(s => [s.id, { text: readFileSync(join(dir, s.snapshot.file), 'utf8') }]));
const ctx = { sources, snapshots };
const rules = readdirSync(join(dir, 'rules')).filter(f => f.endsWith('.json')).sort().map(f => JSON.parse(readFileSync(join(dir, 'rules', f), 'utf8')));
const clone = x => JSON.parse(JSON.stringify(x));

// MARK: 1. as shipped

const shipped = rules.map(r => ({ id: r.id, ...reviewRule(r, ctx) }));
const admitted = new Set(REGISTRY.rules.map(r => r.id));
let bad = 0;
for (const r of shipped) {
  const want = admitted.has(r.id);
  if (r.ok !== want) { bad++; console.log(`FAIL ${r.id}: review says ${r.ok ? 'admit' : r.why}, the registry ${want ? 'admits it' : 'does not'}`); }
}
console.log(`B6.1 as shipped: ${shipped.filter(r => r.ok).length} admitted, ${shipped.filter(r => !r.ok).length} pending (${shipped.filter(r => !r.ok).map(r => `${r.id}: ${r.why}`).join('; ')})`);

// MARK: the slips

/// Every leaf of a value, as [path, value].
function leaves(v, path = []) {
  if (Array.isArray(v)) return v.flatMap((x, i) => leaves(x, [...path, i]));
  if (v && typeof v === 'object') return Object.entries(v).flatMap(([k, x]) => leaves(x, [...path, k]));
  return [[path, v]];
}
const set = (o, path, value) => { let x = o; for (const k of path.slice(0, -1)) x = x[k]; x[path.at(-1)] = value; };
/// The slips a transcriber could make on one leaf.
function slips(value, key) {
  if (typeof value === 'number') return [value + 1, value - 1, value * 10, value / 2].filter(x => x !== value);
  if (typeof value === 'boolean') return [!value];
  if (typeof value !== 'string') return [];
  const out = [];
  if (key === 'op') out.push(...['>=', '>', '<=', '<', 'present', 'anyOf'].filter(o => o !== value));
  else if (key === 'unit') out.push(...['mm', 'hours', 'cm'].filter(u => u !== value));
  else if (key === 'slot') out.push(`${value}_x`, 'tst_group', 'induration_mm');
  else {
    const words = value.split(' ');
    if (words.length > 1) out.push(words.slice(1).join(' '), words.slice(0, -1).join(' '));
    out.push(value.replace(/\d+/, d => String(Number(d) + 1)), value.replace(/\bor more\b/, 'or less'), value.replace(/positive/i, 'negative'), `${value} not`);
  }
  return [...new Set(out)].filter(x => x !== value && x !== '');
}

let oneSided = 0, oneCaught = 0, shared = 0, sharedCaught = 0;
const through = [];
const caughtBy = {};
for (const rule of rules.filter(r => admitted.has(r.id))) {
  // a criterion's id is a label the proof refers to, with no medical meaning
  for (const [path, value] of leaves(rule.formal).filter(([p]) => p.at(-1) !== 'id')) {
    for (const v of slips(value, path.at(-1))) {
      // 2. the second transcriber alone
      const one = clone(rule);
      set(one.transcriptions[1].formal, path, v);
      oneSided++;
      const r1 = reviewRule(one, ctx);
      if (!r1.ok && r1.why === 'transcription') oneCaught++;
      else console.log(`FAIL one-sided slip at ${rule.id} ${path.join('.')} = ${JSON.stringify(v)} got ${r1.ok ? 'admitted' : r1.why}`);
      // 3. both transcribers, the same slip
      const both = clone(rule);
      for (const f of [both.formal, ...both.transcriptions.map(t => t.formal)]) set(f, path, v);
      shared++;
      const r2 = reviewRule(both, ctx);
      if (!r2.ok) { sharedCaught++; caughtBy[r2.why] = (caughtBy[r2.why] || 0) + 1; }
      else through.push({ rule: rule.id, at: path.join('.'), from: value, to: v });
    }
  }
}
if (oneCaught !== oneSided) bad++;
console.log(`B6.2 one transcriber's slip: ${oneCaught} of ${oneSided} caught by comparing the two`);
console.log(`B6.3 a slip both make: ${sharedCaught} of ${shared} caught (${Object.entries(caughtBy).sort((a, b) => b[1] - a[1]).map(([w, n]) => `${w} ${n}`).join(', ')}); ${through.length} get through:`);
for (const t of through) console.log(`  ${t.rule} ${t.at}: ${JSON.stringify(t.from)} -> ${JSON.stringify(t.to)}`);
if (OUT) writeFileSync(OUT, `${JSON.stringify({ bench: 'B6 rule transcription', shipped, oneSided, oneCaught, shared, sharedCaught, caughtBy, through }, null, 1)}\n`);
process.exit(bad ? 1 : 0);
