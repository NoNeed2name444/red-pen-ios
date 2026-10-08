// The source proof's mutation bench (plan SP3): does server/proof.js ever
// prove a statement that no official source states?
//
// Each statement of real openFDA labels and MedlinePlus summaries is proven
// as it stands (the bench's positives: how much of what a source says the
// proof can find), then changed so it means something else - another number,
// unit, frequency, route, population or direction; a negation put in or taken
// out; another drug; words cut, dropped, swapped or added - and proven again.
// A changed statement whose words (spelled the proof's way) are still some
// statement of the source is left out: the source does state it. Any other
// changed statement proven is a false proof, and the bench fails.
//
// What it does not cover: a statement true only under a heading the claim
// leaves out, and wordings no rule here makes; proof.js keeps those out by
// how it reads (headings travel with statements; lead-ins, qualified and
// taken-back sentences never prove alone), and server/tests/proof.test.mjs
// tests them by hand.
//
// Data: openFDA label JSON (api.fda.gov/drug/label.json?search=...&limit=3)
// and MedlinePlus web-service XML (wsearch.nlm.nih.gov/ws/query?db=healthTopics
// &term=...), one file each:
//   node tools/verification-bench/proof-mutations.mjs --fda DIR --mlp DIR
//        [--per-statement 40] [--out report.json]
import { readFileSync, readdirSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import * as P from '../../server/proof.js';

const arg = (name, fallback) => { const i = process.argv.indexOf(`--${name}`); return i >= 0 ? process.argv[i + 1] : fallback; };
const fdaDir = arg('fda', null);
const mlpDir = arg('mlp', null);
const perStatement = Number(arg('per-statement', '40'));
const outFile = arg('out', null);
if (!fdaDir && !mlpDir) { console.error('give --fda DIR and/or --mlp DIR'); process.exit(2); }

// MARK: sources

const unescape = s => s.replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"').replace(/&#39;/g, "'").replace(/&apos;/g, "'").replace(/&amp;/g, '&');
const sources = [];
for (const f of fdaDir ? readdirSync(fdaDir).filter(f => f.endsWith('.json')).sort() : []) {
  for (const r of JSON.parse(readFileSync(join(fdaDir, f), 'utf8')).results || []) {
    const drug = r.openfda?.generic_name?.[0];
    if (!drug) continue;
    const sections = {};
    for (const name of P.FDA_SECTIONS) if (r[name]) sections[name] = r[name];
    sources.push({ kind: 'fda', drug, entry: { source: 'openFDA label', title: `${drug} label`, url: `https://example.org/${r.id}`, official: { drug, sections } } });
  }
}
for (const f of mlpDir ? readdirSync(mlpDir).filter(f => f.endsWith('.xml')).sort() : []) {
  const xml = readFileSync(join(mlpDir, f), 'utf8');
  for (const doc of xml.split('<document ').slice(1, 3)) {
    const title = doc.match(/<content name="title">([\s\S]*?)<\/content>/)?.[1];
    const html = doc.match(/<content name="FullSummary">([\s\S]*?)<\/content>/)?.[1];
    if (!title || !html) continue;
    const t = P.structuredText(unescape(unescape(title)));
    sources.push({ kind: 'mlp', drug: t, entry: { source: 'MedlinePlus', title: t, url: `https://example.org/${f}`, full: P.structuredText(unescape(html)) } });
  }
}

// a statement's words, the proof's way, but for the salt a label names its
// drug with (server/tests/proof.test.mjs's oracle)
const SALT = new Set(['hydrochloride', 'hcl', 'mesylate', 'besylate', 'maleate', 'sodium', 'potassium', 'calcium']);
const plainKey = t => (P.normalize(t) || []).filter(w => !SALT.has(w)).join(' ');
const statementsOf = s => {
  if (s.kind === 'fda') {
    const anchor = new Set(P.drugTokens(s.drug));
    return Object.values(s.entry.official.sections).flatMap(t => P.fdaSegments([].concat(t).join('\n'), anchor).map(x => x.text));
  }
  const anchor = new Set((P.normalize(s.drug) || []));
  return P.mlpSegments(s.entry.full, anchor).map(x => x.text);
};

// MARK: mutations (each a function from a statement to changed statements)

const swapWords = pairs => text => {
  const out = [];
  for (const [a, b] of pairs) for (const [x, y] of [[a, b], [b, a]]) {
    const re = new RegExp(`\\b${x}\\b`, 'gi');
    let m;
    while ((m = re.exec(text))) {
      const keep = m[0][0] === m[0][0].toUpperCase() ? y[0].toUpperCase() + y.slice(1) : y;
      out.push(text.slice(0, m.index) + keep + text.slice(m.index + m[0].length));
    }
  }
  return out;
};
const NUM = /\b\d+(?:\.\d+)?\b/g;
const numbers = text => {
  const out = [];
  for (const m of text.matchAll(NUM)) {
    const n = Number(m[0]);
    for (const k of [n * 2, n / 2, n + 1, n * 10, n === 0 ? 1 : n - 1]) {
      const s = String(Math.round(k * 1000) / 1000);
      if (s !== m[0]) out.push(text.slice(0, m.index) + s + text.slice(m.index + m[0].length));
    }
  }
  return out;
};
const NEG = /\b(not|no|never|without)\s+/i;
const negation = text => {
  const out = [];
  const m = text.match(NEG);
  if (m) out.push(text.slice(0, m.index) + text.slice(m.index + m[0].length));
  for (const v of ['is', 'are', 'may', 'should', 'can', 'will', 'does', 'do', 'must']) {
    const re = new RegExp(`\\b${v}\\b(?! not)`, 'i');
    const r = text.match(re);
    if (r) { out.push(text.slice(0, r.index + r[0].length) + ' not' + text.slice(r.index + r[0].length)); break; }
  }
  return out;
};
const words = text => text.split(/\s+/).filter(Boolean);
const STOP = new Set(['the', 'a', 'an', 'of', 'and', 'or', 'to', 'in', 'on', 'for', 'with', 'by', 'at', 'as', 'is', 'are', 'be', 'that', 'this', 'it']);
const cuts = text => {
  const w = words(text), out = [];
  for (const k of [1, 2, 3]) if (w.length > k + 2) { out.push(w.slice(k).join(' ')); out.push(w.slice(0, -k).join(' ')); }
  return out;
};
const drops = text => {
  const w = words(text), out = [];
  for (let i = 0; i < w.length; i++) if (!STOP.has(w[i].toLowerCase().replace(/\W/g, ''))) out.push([...w.slice(0, i), ...w.slice(i + 1)].join(' '));
  return out;
};
const swaps = text => {
  const w = words(text), out = [];
  const content = w.map((x, i) => [x, i]).filter(([x]) => !STOP.has(x.toLowerCase().replace(/\W/g, '')) && /[a-z]/i.test(x));
  for (let i = 0; i + 1 < content.length; i++) {
    const v = [...w];
    [v[content[i][1]], v[content[i + 1][1]]] = [v[content[i + 1][1]], v[content[i][1]]];
    out.push(v.join(' '));
  }
  return out;
};
const inserts = text => {
  const w = words(text), out = [];
  for (const add of ['always', 'only', 'never', 'rarely', 'usually']) for (let i = 1; i < Math.min(w.length, 6); i++) out.push([...w.slice(0, i), add, ...w.slice(i)].join(' '));
  return out;
};
let drugNames = [];
const drugSwap = (text, own) => {
  const out = [];
  for (const t of own) {
    const re = new RegExp(`\\b${t.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}\\b`, 'i');
    const m = text.match(re);
    if (!m) continue;
    for (const other of drugNames) if (other.toLowerCase() !== t.toLowerCase()) out.push(text.slice(0, m.index) + other + text.slice(m.index + m[0].length));
  }
  return out;
};

const CLASSES = {
  number: numbers,
  unit: swapWords([['mg', 'mcg'], ['mg', 'g'], ['mcg', 'g'], ['mL', 'L'], ['hours', 'days'], ['hours', 'minutes'], ['days', 'weeks'], ['hour', 'day'], ['mg/kg', 'mg/m2']]),
  frequency: swapWords([['once', 'twice'], ['twice', 'three times'], ['daily', 'weekly'], ['day', 'week'], ['every', 'every other']]),
  route: swapWords([['oral', 'intravenous'], ['orally', 'intravenously'], ['intravenous', 'subcutaneous'], ['intramuscular', 'intravenous'], ['topical', 'oral'], ['subcutaneously', 'intramuscularly']]),
  negation,
  antonym: swapWords([['increase', 'decrease'], ['increased', 'decreased'], ['increases', 'decreases'], ['higher', 'lower'], ['before', 'after'], ['with', 'without'],
    ['adults', 'children'], ['adult', 'pediatric'], ['hypotension', 'hypertension'], ['hypoglycemia', 'hyperglycemia'], ['hypokalemia', 'hyperkalemia'],
    ['contraindicated', 'indicated'], ['common', 'rare'], ['acute', 'chronic'], ['more', 'less'], ['above', 'below'], ['maximum', 'minimum'],
    ['men', 'women'], ['male', 'female'], ['first', 'second'], ['early', 'late'], ['mild', 'severe'], ['high', 'low'], ['may', 'must'],
    ['recommended', 'not recommended'], ['safe', 'unsafe'], ['all', 'some'], ['upper', 'lower'], ['left', 'right'], ['inhibits', 'induces'],
    ['inhibitors', 'inducers'], ['benign', 'malignant'], ['viral', 'bacterial'], ['type 1', 'type 2'], ['excess', 'deficiency'], ['and', 'or']]),
  drug: null,
  cut: cuts,
  drop: drops,
  swap: swaps,
  insert: inserts,
};

// MARK: run

drugNames = [...new Set(sources.filter(s => s.kind === 'fda').map(s => P.drugTokens(s.drug)[0]).filter(Boolean))];
const fact = text => ({ kind: 'fact', text });
const counts = Object.fromEntries(Object.keys(CLASSES).map(k => [k, { cases: 0, live: 0, guarded: 0, same: 0, proven: 0 }]));
const falses = [];
let bases = 0, basesProven = 0, positives = 0, positivesProven = 0, cases = 0, live = 0;
const why = new Map();
const t0 = Date.now();
// a deterministic pick of `n` from a list, so runs compare
const pick = (list, n, seed) => {
  if (list.length <= n) return list;
  // a seeded shuffle's first n: a step through the list by a stride prime to
  // its length, from a seeded start
  const gcd = (a, b) => (b ? gcd(b, a % b) : a);
  let stride = 1 + (seed * 7919) % (list.length - 1);
  while (gcd(stride, list.length) !== 1) stride++;
  const start = (seed * 104729) % list.length;
  return Array.from({ length: n }, (_, i) => list[(start + i * stride) % list.length]);
};
// one batch's purse per source: a section is read once, as a batch reads it
let paid = new Map();

for (const s of sources) {
  paid = new Map();
  const stated = [...new Set(statementsOf(s))];
  const keys = new Set(stated.map(plainKey));
  const own = s.kind === 'fda' ? P.drugTokens(s.drug) : [];
  for (const [si, st] of stated.entries()) {
    if (plainKey(st) === '') continue;
    bases++;
    const base = P.prove(fact(st), [s.entry], { paid });
    const baseOk = P.fullyProven(base);
    if (baseOk) basesProven++;
    else why.set(base.why, (why.get(base.why) || 0) + 1);
    const baseKey = plainKey(st);
    for (const [cls, gen] of Object.entries(CLASSES)) {
      const raw = cls === 'drug' ? drugSwap(st, own) : gen(st);
      const changed = pick([...new Set(raw)].filter(t => t !== st), perStatement, si * 31 + cls.length);
      for (const t of changed) {
        const key = plainKey(t);
        const c = counts[cls];
        cases++;
        c.cases++;
        if (key === baseKey) {
          // the same words the proof's way: a positive, not a change
          c.same++;
          positives++;
          if (P.fullyProven(P.prove(fact(t), [s.entry], { paid }))) positivesProven++;
          continue;
        }
        if (keys.has(key) || key === '') { c.guarded++; continue; }
        // live: a change of a statement the proof finds as it stands, so
        // the proof was one change away from proving it
        if (baseOk) { c.live++; live++; }
        const r = P.prove(fact(t), [s.entry], { paid });
        if (P.fullyProven(r)) {
          c.proven++;
          falses.push({ cls, source: s.entry.title, statement: st, changed: t, quotes: r.quotes.map(q => q.quote) });
        }
      }
    }
  }
}

const secs = (Date.now() - t0) / 1000;
const report = {
  sources: { fda: sources.filter(s => s.kind === 'fda').length, mlp: sources.filter(s => s.kind === 'mlp').length },
  statements: bases, statementsProven: basesProven, unprovenWhy: Object.fromEntries(why),
  cases, live, falseProofs: falses.length, positives, positivesProven, classes: counts, seconds: secs,
  firstFalse: falses.slice(0, 20),
};
console.log(`sources: ${report.sources.fda} openFDA labels, ${report.sources.mlp} MedlinePlus summaries`);
console.log(`statements: ${bases}, proven as they stand: ${basesProven} (${(100 * basesProven / Math.max(1, bases)).toFixed(1)}%); not, by why: ${JSON.stringify(report.unprovenWhy)}`);
console.log(`changed statements: ${cases} (${live} of statements proven as they stand) in ${secs.toFixed(0)} s; same words (positives): ${positives}, proven ${positivesProven}`);
for (const [k, c] of Object.entries(counts)) console.log(`  ${k.padEnd(10)} ${String(c.cases).padStart(8)} cases, ${String(c.live).padStart(7)} live, ${String(c.guarded).padStart(6)} still stated, ${String(c.same).padStart(6)} same words, ${c.proven} FALSE PROOFS`);
for (const f of falses.slice(0, 10)) console.log(`FALSE [${f.cls}] ${f.source}\n  stated:  ${f.statement.slice(0, 200)}\n  changed: ${f.changed.slice(0, 200)}\n  quote:   ${f.quotes.join(' | ').slice(0, 200)}`);
console.log(falses.length ? `FAIL: ${falses.length} false proofs` : `ok: 0 false proofs in ${cases} changed statements`);
if (outFile) writeFileSync(outFile, JSON.stringify(report, null, 2));
process.exit(falses.length ? 1 : 0);
