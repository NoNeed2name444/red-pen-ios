// Replays verification-bench results under other verdict rules, to choose
// the strictest rule that still commits: the layer may only say Verified or
// Flagged where the bench shows it right at least `--target` of the time
// (the owner: 99.9%), and says Check this everywhere else.
//
// Every share comes with its one-sided 95% lower bound (Clopper-Pearson):
// 200 right out of 200 is a lower bound of 98.5%, not "100%"; showing 99.9%
// with nothing wrong takes about 3,000 committed verdicts.
//
//   node tools/verification-bench/policy.mjs runs/*/results.json [--target=0.999]
//   results saved before the keyed letter was: add --data=DIR (fetch.sh's
//   folder) and that run's --per-source=N, to rebuild each check's key
import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import { familyOf } from '../../server/accuracy-model.js';
import { loadQuestions, benchCases } from './datasets.mjs';

const files = process.argv.slice(2).filter(a => a.endsWith('.json'));
const target = Number((process.argv.find(a => a.startsWith('--target=')) || '--target=0.999').split('=')[1]);
const opt = (name, fallback) => (process.argv.find(a => a.startsWith(`--${name}=`)) || `=${fallback}`).split('=')[1];
const rows = files.flatMap(f => JSON.parse(readFileSync(f, 'utf8')));
const dataDir = opt('data', '');
const keys = new Map();
if (dataDir) {
  const all = loadQuestions(readdirSync(dataDir).filter(f => f.endsWith('.json')).map(f => join(dataDir, f)));
  const { cases } = benchCases(all, { wanted: opt('sources', 'MedXpertQA,MedQA,CareQA Medicine').split(','),
    perSource: Number(opt('per-source', '30')), seed: Number(opt('seed', '7')) });
  for (const c of cases) keys.set(c.item.id, String.fromCharCode(65 + c.item.key));
}

// MARK: what the votes say, per item

const LETTERS = 'ABCDEFGHIJ';
function facts(r) {
  const key = keyOf(r);
  const blind = new Map(), sighted = [];
  for (const v of r.votes || []) {
    if (!v || !v.model) continue;
    if (v.blind && typeof v.answer === 'string' && LETTERS.includes(v.answer)) {
      if (!blind.has(v.answer)) blind.set(v.answer, new Set());
      blind.get(v.answer).add(familyOf(v.model));
    } else if (!v.blind && Number.isFinite(v.risk)) sighted.push(v);
  }
  const answering = new Set([...blind.values()].flatMap(s => [...s]));
  const forKey = key ? blind.get(key)?.size || 0 : 0;
  const against = Math.max(0, ...[...blind].filter(([l]) => l !== key).map(([, s]) => s.size));
  return {
    key, forKey, against, answering: answering.size,
    dissent: [...blind].filter(([l]) => l !== key).reduce((n, [, s]) => n + s.size, 0),
    sightedFlags: sighted.filter(v => v.risk >= 3).length, sighted: sighted.length,
    severe: (r.rules || []).some(h => h.severity === 'severe'),
    p: Number(r.p) || 0,
  };
}
// the keyed letter: saved by newer runs, rebuilt from the data for older ones
const keyOf = r => r.keyLetter || keys.get(r.id) || null;

// MARK: candidate rules

const verifyRules = {
  'now: p>=.85, 2 blind families on the key': x => x.p >= 0.85 && x.forKey >= 2,
  '2 blind families on the key, none against': x => x.p >= 0.85 && x.forKey >= 2 && x.dissent === 0,
  '2 on the key, none against, no sighted flag': x => x.p >= 0.85 && x.forKey >= 2 && x.dissent === 0 && x.sightedFlags === 0,
  '3 blind families on the key': x => x.p >= 0.85 && x.forKey >= 3,
  '3 on the key, none against': x => x.p >= 0.85 && x.forKey >= 3 && x.dissent === 0,
};
const flagRules = {
  'now: 2 blind families on another answer, or p<.4': x => x.severe || x.against >= 2 || x.p < 0.4,
  '2 on another answer, none on the key': x => x.severe || (x.against >= 2 && x.forKey === 0),
  '2 on another, none on the key, a sighted flag': x => x.severe || (x.against >= 2 && x.forKey === 0 && x.sightedFlags > 0),
  '3 on another answer': x => x.severe || x.against >= 3,
  'sensors only': x => x.severe,
};

// MARK: shares with honest bounds

function lowerBound(k, n, alpha = 0.05) {
  if (!n) return 0;
  if (k === 0) return 0;
  // P(X >= k | n, q) = alpha, by bisection on q
  const tail = q => { let s = 0; for (let i = k; i <= n; i++) s += Math.exp(logChoose(n, i) + i * Math.log(q) + (n - i) * Math.log1p(-q)); return s; };
  let lo = 0, hi = k / n;
  for (let i = 0; i < 60; i++) { const mid = (lo + hi) / 2; if (tail(mid) < alpha) lo = mid; else hi = mid; }
  return lo;
}
const logFact = (() => { const c = [0]; return n => { for (let i = c.length; i <= n; i++) c[i] = c[i - 1] + Math.log(i); return c[n]; }; })();
const logChoose = (n, k) => logFact(n) - logFact(k) - logFact(n - k);
const pct = x => `${(100 * x).toFixed(1)}%`;

const scored = rows.map(r => ({ truth: r.truth, x: facts(r), source: r.source })).filter(r => r.x.key);
if (!scored.length) { console.error('No check has a keyed letter: give --data=DIR and --per-source=N for results saved before it was.'); process.exit(2); }
console.log(`${scored.length} checks from ${files.length} run(s). Target: ${pct(target)}.\n`);
console.log('| Verified when | Flagged when | committed | right | lower bound | Verified right | Flagged right |');
console.log('|---|---|---|---|---|---|---|');
const table = [];
for (const [vn, vr] of Object.entries(verifyRules)) {
  for (const [fn, fr] of Object.entries(flagRules)) {
    let ok = 0, n = 0, vOk = 0, vN = 0, fOk = 0, fN = 0;
    for (const { truth, x } of scored) {
      const flagged = fr(x), verified = !flagged && vr(x) && !x.severe;
      if (verified) { vN++; n++; if (truth === 'right') { vOk++; ok++; } }
      else if (flagged) { fN++; n++; if (truth === 'wrong') { fOk++; ok++; } }
    }
    table.push({ vn, fn, n, ok, lb: lowerBound(ok, n), vOk, vN, fOk, fN });
  }
}
table.sort((a, b) => b.lb - a.lb || b.n - a.n);
for (const t of table) {
  console.log(`| ${t.vn} | ${t.fn} | ${t.n}/${scored.length} (${pct(t.n / scored.length)}) | ${t.n ? pct(t.ok / t.n) : 'n/a'} | ${pct(t.lb)} | ${t.vOk}/${t.vN} | ${t.fOk}/${t.fN} |`);
}
const n0 = Math.ceil(Math.log(0.05) / Math.log(target));
console.log(`\nWith nothing wrong, a ${pct(target)} lower bound needs ${n0} committed verdicts.`);
