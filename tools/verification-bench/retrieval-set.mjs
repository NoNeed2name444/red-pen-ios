// The retrieval set R (docs/verification/rag-plan.md A2): how well the engine's
// literature lookup finds what a question is about, measured before the
// lookup is changed. Every label is mechanical and never comes from a model.
//
//   R-dev   150 items for tuning only, from the proof ladder's training splits
//           (tools/proof-ladder/ladder.mjs): 100 one-sentence items and 50
//           vignettes, from MedMCQA (Apache-2.0) and MedQA (CC-BY-4.0)
//   R-test  the 90 bench questions (seed 7, 30 a source), as layer.mjs picks them
//
// Labels (an item is its question with its true key):
//   2  an official document is relevant when either
//        - it is an FDA label whose generic name equals (drugTokens, server/proof.js)
//          a drug named in the key or in an option; or
//        - it is a MedlinePlus topic whose title or "also called" name equals the
//          key's normalised words, or the key's MeSH preferred term (looked up
//          once, keyless, and stored in the label file)
//   1  a passage is on-topic when it holds the key's words (or the stored MeSH
//      term) and at least one content word of the stem's last two sentences
//   0  anything else
//
// Metrics: official recall@3 and @5 (of the official documents that exist for
// an item, the share the lookup found in its first 3 and 5), nDCG@5 of what
// the voters are shown (evidenceFor's list, in its order), the on-topic share
// of what they are shown, and lookups per item.
//
// The label files (labels/r-dev.json, labels/r-test.json) are committed with
// their sha256 (labels/SHA256SUMS: `cd labels && sha256sum -c SHA256SUMS`); a
// run refuses a file that does not match. They hold no question text: each
// item's id, a short hash of its content (so a drifted dataset is noticed),
// and the mechanical inputs and stored lookups its labels come from.
//
//   node tools/verification-bench/retrieval-set.mjs --set dev|test|both [--data DIR] [--cache DIR] [--limit N] [--out DIR]
//   node tools/verification-bench/retrieval-set.mjs --build-labels dev|test [--data DIR] [--cache DIR]   (rewrites the label file and SHA256SUMS)
//
// --data is where tools/verification-bench/fetch.sh put the bench questions
// (R-test); --cache is a directory kept between runs for what was fetched
// (never the repository; at most 200 MB).
import { createHash } from 'node:crypto';
import { readFileSync, readdirSync, writeFileSync, mkdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { normalizeWords, drugTokens, claimsFor } from '../../server/proof.js';
import { evidenceFor, officialFor } from '../../server/accuracy.js';
import { DRUGS } from '../../server/accuracy-rules.js';
import { loadQuestions, benchCases, validQuestionOf } from './datasets.mjs';
import { diskCache, cachedFetcher, newTally, jsonPage } from './lookup-cache.mjs';

const here = dirname(fileURLToPath(import.meta.url));
export const LABELS_DIR = join(here, 'labels');

// MARK: the label rules (pure)

// words that carry no topic: a stem's glue, not its subject
const STOP = new Set(['which', 'following', 'most', 'likely', 'patient', 'patients', 'year', 'years', 'what', 'this', 'that', 'these',
  'those', 'best', 'next', 'step', 'steps', 'with', 'from', 'after', 'before', 'about', 'there', 'their', 'shows', 'show', 'been', 'have',
  'does', 'used', 'many', 'following', 'true', 'false', 'except', 'would', 'could', 'should', 'into', 'than', 'then', 'when', 'where',
  'while', 'also', 'both', 'each', 'other', 'such', 'only', 'more', 'less', 'some', 'case', 'seen', 'found', 'given', 'following']);

/// A text's words, normalised as the proof reads them (proof.js
/// normalizeWords); [] for a text it cannot read for certain.
const wordsOf = text => normalizeWords(String(text || '')) || [];

/// The content words of a text: longer than three letters, not glue, not a number.
export const contentWords = text => wordsOf(text).filter(w => w.length > 3 && !STOP.has(w) && !/^\d+$/.test(w));

/// A stem's last two sentences.
export function lastSentences(stem, n = 2) {
  const parts = String(stem || '').split(/(?<=[.?!])\s+/).map(s => s.trim()).filter(Boolean);
  return parts.slice(-n).join(' ');
}

// the engine's own drug cues (accuracy.js itemTerms): the list it knows and
// the endings drug names take
const DRUG_SUFFIX = /\b[a-z]{3,}(?:olol|pril|sartan|statin|dipine|mab|cillin|mycin|floxacin|azole|prazole|tidine|parin|gliptin|gliflozin|triptan|setron|lukast|olone|asone|tinib|vir)\b/g;

/// The drugs a text names, lower case, in order of appearance.
export function drugsIn(text) {
  const t = String(text || '').toLowerCase();
  const found = new Set();
  for (const d of Object.keys(DRUGS)) if (new RegExp(`(^|[^a-z])${d.replace(/[-]/g, '\\-')}([^a-z]|$)`).test(t)) found.add(d);
  for (const m of t.matchAll(DRUG_SUFFIX)) found.add(m[0]);
  return [...found];
}

/// The drugs named in the key or in any option.
export const drugsNamed = item => [...new Set((item.options || []).flatMap(o => drugsIn(o)))];

/// What a question's labels are made from, with the stored MeSH term.
/// `keyWords`: the key's normalised words; `meshWords`: the MeSH preferred
/// term's; `drugs`: the drugs named in the key or an option; `tail`: the
/// content words of the stem's last two sentences that are not the key's.
export function labelInputs(item, mesh = null) {
  const keyWords = wordsOf(item.options?.[item.key]);
  const meshWords = mesh ? wordsOf(mesh) : [];
  const tail = [...new Set(contentWords(lastSentences(item.stem)))].filter(w => !keyWords.includes(w));
  return { keyWords, mesh: mesh || null, meshWords, drugs: drugsNamed(item), tail };
}

const same = (a, b) => a.length > 0 && a.length === b.length && a.every((w, i) => w === b[i]);

/// Label 2: whether an official document is relevant to the question.
/// `doc`: { source: 'openFDA label' | 'MedlinePlus', title, official?: { drug }, alsoCalled?: [names] }.
/// A label counts only when the engine could read it as the drug's alone
/// (`official`, which officialLabel in evidence.js sets only then).
export function officialRelevant(doc, inputs) {
  if (doc?.source === 'openFDA label') {
    const got = drugTokens(doc.official?.drug);
    return got.length > 0 && (inputs.drugs || []).some(d => same(got, drugTokens(d)));
  }
  if (doc?.source === 'MedlinePlus') {
    return [doc.title, ...(doc.alsoCalled || [])].some(name => {
      const w = wordsOf(name);
      return same(w, inputs.keyWords) || same(w, inputs.meshWords);
    });
  }
  return false;
}

/// Label 1: whether a passage is on-topic: it holds the key's words (all of
/// them) or the MeSH term's, and at least one content word of the stem's tail.
export function onTopic(doc, inputs) {
  const words = new Set(wordsOf(`${doc?.title || ''} ${doc?.text || ''}`));
  const holds = ws => ws.length > 0 && ws.every(w => words.has(w));
  return (holds(inputs.keyWords) || holds(inputs.meshWords)) && (inputs.tail || []).some(w => words.has(w));
}

/// The label of a document shown: 2, 1 or 0.
export const labelOf = (doc, inputs) => (officialRelevant(doc, inputs) ? 2 : onTopic(doc, inputs) ? 1 : 0);

/// A document's identity across lookups: an FDA label by its drug, anything
/// else by its address.
export const docId = doc => (doc?.source === 'openFDA label' && doc.official?.drug ? `fda:${drugTokens(doc.official.drug).join(' ')}` : doc?.url || '');

// MARK: the metrics (pure)

/// Recall at k: of the relevant documents, the share found in the first k
/// retrieved (ids). null when nothing is relevant (the item is not counted).
export function recallAt(k, ranked, relevant) {
  const want = new Set(relevant);
  if (!want.size) return null;
  const got = new Set(ranked.slice(0, k).filter(id => want.has(id)));
  return got.size / want.size;
}

/// Discounted cumulative gain at k: gain 2^label - 1, discount log2(rank + 1).
export const dcgAt = (k, labels) => labels.slice(0, k).reduce((s, l, i) => s + (2 ** l - 1) / Math.log2(i + 2), 0);

/// nDCG at k of a shown list's labels against the best order of that same
/// list; 0 when nothing shown is relevant at all (and for an empty list).
export function ndcgAt(k, labels) {
  const ideal = dcgAt(k, [...labels].sort((a, b) => b - a));
  return ideal > 0 ? dcgAt(k, labels) / ideal : 0;
}

/// The set's numbers from its items' rows:
/// { id, group, oracle: [ids], retrieved: [ids], shown: [labels], lookups }.
export function summarize(rows) {
  const answerable = rows.filter(r => r.oracle.length);
  const hits = k => answerable.reduce((s, r) => s + recallAt(k, r.retrieved, r.oracle) * r.oracle.length, 0);
  const wants = answerable.reduce((s, r) => s + r.oracle.length, 0);
  const shown = rows.flatMap(r => r.shown);
  const mean = list => (list.length ? list.reduce((a, b) => a + b, 0) / list.length : null);
  return {
    items: rows.length,
    answerable: answerable.length,
    officialDocs: wants,
    recall3: wants ? hits(3) / wants : null,
    recall5: wants ? hits(5) / wants : null,
    ndcg5: mean(rows.map(r => ndcgAt(5, r.shown))),
    passages: shown.length,
    onTopic: shown.length ? shown.filter(l => l >= 1).length / shown.length : null,
    official: shown.length ? shown.filter(l => l === 2).length / shown.length : null,
    lookupsPerItem: mean(rows.map(r => r.lookups)),
    shownPerItem: mean(rows.map(r => r.shown.length)),
    noPassage: rows.filter(r => !r.shown.length).length,
  };
}

// MARK: MedlinePlus and MeSH, read for labels

const unhtml = s => String(s || '')
  .replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"').replace(/&#39;|&apos;/g, "'").replace(/&amp;/g, '&')
  .replace(/<[^>]+>/g, ' ').replace(/&[a-z#0-9]+;/gi, ' ').replace(/\s+/g, ' ').trim();

/// The topics in a MedlinePlus search answer (wsearch XML): [{ url, title, alsoCalled: [names] }].
export function topicsIn(xml) {
  const out = [];
  for (const doc of String(xml || '').matchAll(/<document[^>]*url="([^"]+)"[^>]*>([\s\S]*?)<\/document>/g)) {
    const field = name => [...doc[2].matchAll(new RegExp(`<content name="${name}">([\\s\\S]*?)</content>`, 'g'))].map(m => unhtml(m[1]));
    out.push({ url: doc[1], title: field('title')[0] || '', alsoCalled: field('altTitle') });
  }
  return out;
}

const mlpUrl = (term, retmax) => `https://wsearch.nlm.nih.gov/ws/query?db=healthTopics&term=${encodeURIComponent(term)}&retmax=${retmax}`;
const text = async (fetcher, url) => { try { const r = await fetcher(url); return r.ok ? await r.text() : null; } catch { return null; } };

/// The key's MeSH preferred term, looked up once through NLM's keyless MeSH
/// lookup: the descriptor of that name, else the descriptor whose concept
/// holds a term of that name (a synonym's way to its preferred term). null
/// when MeSH has neither, or could not be read.
export async function meshPreferred(key, fetcher) {
  const label = encodeURIComponent(String(key || '').trim());
  if (!label) return null;
  const json = async url => { try { return JSON.parse(await text(fetcher, url) || '[]'); } catch { return []; } };
  const descriptor = (await json(`https://id.nlm.nih.gov/mesh/lookup/descriptor?label=${label}&match=exact`))[0];
  if (descriptor?.label) return descriptor.label;
  const term = (await json(`https://id.nlm.nih.gov/mesh/lookup/term?label=${label}&match=exact`))[0];
  const id = String(term?.resource || '').match(/\/(T\d+)$/)?.[1];
  if (!id) return null;
  const query = `PREFIX meshv: <http://id.nlm.nih.gov/mesh/vocab#>\nPREFIX mesh: <http://id.nlm.nih.gov/mesh/>\nPREFIX rdfs: <http://www.w3.org/2000/01/rdf-schema#>\n`
    + `SELECT DISTINCT ?l WHERE { ?c meshv:term|meshv:preferredTerm mesh:${id} . ?d meshv:preferredConcept|meshv:concept ?c . ?d rdfs:label ?l }`;
  try {
    const answer = JSON.parse(await text(fetcher, `https://id.nlm.nih.gov/mesh/sparql?format=JSON&query=${encodeURIComponent(query)}`) || '{}');
    return answer?.results?.bindings?.[0]?.l?.value || null;
  } catch { return null; }
}

/// The official documents that exist for a question, by the label-2 rules,
/// looked up once and stored (the recall's denominator): the FDA label of
/// each drug named (when it is that drug's alone), and the MedlinePlus
/// topics (the first five an exact search on the key and on the MeSH term
/// give) whose title or "also called" name is the key or the MeSH term.
/// [{ id, title }]; the engine's own lookups are not used, so that the
/// documents that exist do not depend on what it finds.
export async function oracleFor(item, inputs, fetcher, { openFDA }) {
  const found = new Map();
  for (const drug of inputs.drugs) {
    for (const e of (await openFDA(drug, fetcher)) || []) {
      if (e.official && officialRelevant({ source: e.source, official: e.official }, inputs)) found.set(docId(e), e.title);
    }
  }
  const queries = [...new Set([String(item.options?.[item.key] || '').trim(), inputs.mesh].filter(Boolean))];
  for (const q of queries) {
    for (const t of topicsIn(await text(fetcher, mlpUrl(q, 5)))) {
      if (officialRelevant({ source: 'MedlinePlus', ...t }, inputs)) found.set(t.url, t.title);
    }
  }
  return [...found].map(([id, title]) => ({ id, title }));
}

// MARK: the items

export const itemSha = q => createHash('sha256').update(JSON.stringify([q.stem, q.options, q.key])).digest('hex').slice(0, 16);
const sha256 = buf => createHash('sha256').update(buf).digest('hex');

/// The label file for a set, and a check that it is the file committed:
/// labels/SHA256SUMS names its sha256, as `sha256sum -c` reads it.
export function readLabels(name, dir = LABELS_DIR) {
  const raw = readFileSync(join(dir, `${name}.json`));
  const sums = Object.fromEntries(readFileSync(join(dir, 'SHA256SUMS'), 'utf8').split('\n').filter(Boolean).map(l => { const [h, f] = l.split(/\s+/); return [f, h]; }));
  const want = sums[`${name}.json`];
  if (!want || want !== sha256(raw)) throw new Error(`labels/${name}.json does not match its sha256 in labels/SHA256SUMS`);
  return { ...JSON.parse(raw), sha256: want };
}

/// The R-dev selection, in the proof ladder's training splits: from a fixed
/// row onward, the first questions that qualify. A one-sentence item is one
/// the source proof can read (the ladder's `readable`); a vignette is one it
/// declines for being a vignette (claimsFor says "stem").
export const DEV_PLAN = [
  { src: 'medmcqa-train', dataset: 'openlifescienceai/medmcqa', split: 'train', start: 100000, want: 100, kind: 'one-sentence' },
  { src: 'medqa-train', dataset: 'GBaker/MedQA-USMLE-4-options', split: 'train', start: 5000, want: 25, kind: 'vignette' },
  { src: 'medmcqa-train', dataset: 'openlifescienceai/medmcqa', split: 'train', start: 120000, want: 25, kind: 'vignette' },
];
export function classify(q) {
  try {
    const why = claimsFor({ ...q, kind: 'mcq' }, 5e6).why;
    return !why ? 'one-sentence' : why === 'stem' ? 'vignette' : null;
  } catch { return null; }
}
const rowsUrl = (dataset, split, offset) => `https://datasets-server.huggingface.co/rows?dataset=${encodeURIComponent(dataset)}&config=default&split=${split}&offset=${offset}&length=100`;
const devId = (src, q) => `${src}:${q.id.split(':').pop()}`;

/// Walks the plan: [{ id, group, dataset, split, offset, q }].
export async function selectDev(page) {
  const picked = [];
  for (const step of DEV_PLAN) {
    let got = 0;
    for (let at = step.start; got < step.want && at < step.start + 20000; at += 100) {
      const { rows = [] } = await page(rowsUrl(step.dataset, step.split, at));
      for (const [n, { row }] of rows.entries()) {
        if (got >= step.want) break;
        const q = validQuestionOf(row, at + n);
        if (q && classify(q) === step.kind) { picked.push({ id: devId(step.src, q), group: step.kind, dataset: step.dataset, split: step.split, offset: at + n, q: { ...q, id: devId(step.src, q) } }); got++; }
      }
    }
  }
  return picked;
}

/// R-dev's questions as the label file names them (by row), from the pages.
export async function loadDev(labels, page) {
  const pages = new Map();
  const items = [];
  for (const l of labels.items) {
    const start = Math.floor(l.row.offset / 100) * 100;
    const url = rowsUrl(l.row.dataset, l.row.split, start);
    if (!pages.has(url)) pages.set(url, (await page(url)).rows || []);
    const row = pages.get(url)[l.row.offset - start]?.row;
    const q = row && validQuestionOf(row, l.row.offset);
    if (!q) throw new Error(`${l.id}: the row is not there any more`);
    items.push({ ...q, id: l.id });
  }
  return items;
}

/// R-test's questions: the bench's 90, as layer.mjs picks them.
export function loadTest(dataDir) {
  const all = loadQuestions(readdirSync(dataDir).filter(f => f.endsWith('.json')).map(f => join(dataDir, f)));
  const { chosen } = benchCases(all, { wanted: ['MedXpertQA', 'MedQA', 'CareQA Medicine'], perSource: 30, seed: 7 });
  return chosen;
}

// MARK: measuring one item

/// What the engine finds for a question, and how it is labelled: the shown
/// evidence (evidenceFor) and the official sources (officialFor), as
/// checkBatch asks them (one `seen` between them), through a fetcher of its
/// own so its lookups are counted.
export async function measureItem(item, inputs, base) {
  const tally = newTally();
  const fetcher = cachedFetcher({ cache: base.cache, fetchImpl: base.fetchImpl, tally, gap: base.gap });
  const raw = new Map();
  const spy = async (url, init) => { const res = await fetcher(url, init); if (String(url).includes('wsearch.nlm.nih.gov')) raw.set(String(url), await res.clone().text()); return res; };
  const seen = new Map();
  const shown = await evidenceFor(item, spy, seen);
  const { entries, unread } = await officialFor(item, spy, seen);
  // MedlinePlus's "also called" names, from the very answers the lookups got
  const alsoBy = new Map();
  for (const xml of raw.values()) for (const t of topicsIn(xml)) alsoBy.set(t.url, t);
  const officialBy = new Map(entries.map(e => [e.url, e]));
  const docOf = e => {
    const official = officialBy.get(e.url) || e;
    return { source: e.source, title: e.title, text: e.text, url: e.url, official: official.official, alsoCalled: alsoBy.get(e.url)?.alsoCalled || [] };
  };
  return {
    retrieved: entries.map(e => docId({ source: e.source, url: e.url, official: e.official })),
    shown: shown.map(e => labelOf(docOf(e), inputs)),
    shownTitles: shown.map(e => `${e.source}: ${e.title}`),
    lookups: tally.lookups, unread, failed: tally.failed, tally,
  };
}

// MARK: the report

const f2 = x => (x === null || x === undefined ? 'n/a' : x.toFixed(2));
const pc = x => (x === null || x === undefined ? 'n/a' : `${(100 * x).toFixed(1)}%`);

export function reportFor(name, sets, notes = []) {
  const lines = [`# Retrieval set R: ${name}`, ''];
  for (const [label, rows] of sets) {
    const s = summarize(rows);
    lines.push(`## ${label}`, '', `${s.items} items; ${s.answerable} have an official document that exists (${s.officialDocs} in all).`, '',
      '| measure | result |', '|---|---|',
      `| official recall@3 | ${pc(s.recall3)} |`, `| official recall@5 | ${pc(s.recall5)} |`,
      `| nDCG@5 of what voters are shown | ${f2(s.ndcg5)} |`,
      `| on-topic share of passages shown | ${pc(s.onTopic)} (${s.passages} passages, ${f2(s.shownPerItem)} an item; ${s.noPassage} items showed none) |`,
      `| official share of passages shown | ${pc(s.official)} |`,
      `| lookups per item | ${f2(s.lookupsPerItem)} |`, '');
  }
  return [...lines, ...notes].join('\n');
}

// MARK: command line

async function main() {
  const arg = (name, fallback = null) => { const i = process.argv.indexOf(`--${name}`); return i > 0 ? process.argv[i + 1] : fallback; };
  const cacheDir = arg('cache', join(process.env.TMPDIR || '/tmp', 'ragbench-cache'));
  const cache = diskCache(cacheDir);
  const tally = newTally();
  const shared = cachedFetcher({ cache, tally });
  const page = jsonPage(shared);
  const { openFDA } = await import('../../server/evidence.js');

  const build = arg('build-labels');
  if (build) {
    const items = build === 'dev'
      ? (await selectDev(page)).map(d => ({ id: d.id, group: d.group, row: { dataset: d.dataset, split: d.split, offset: d.offset }, q: d.q }))
      : loadTest(arg('data', 'verification-bench-data')).map(q => ({ id: q.id, group: q.source, q }));
    const out = [];
    for (const it of items) {
      const mesh = await meshPreferred(it.q.options[it.q.key], shared);
      const inputs = labelInputs(it.q, mesh);
      const oracle = await oracleFor(it.q, inputs, shared, { openFDA });
      out.push({ id: it.id, group: it.group, ...(it.row ? { row: it.row } : {}), sha: itemSha(it.q), keyWords: inputs.keyWords, mesh: inputs.mesh, drugs: inputs.drugs, oracle });
      process.stdout.write(`\r${out.length}/${items.length}`);
    }
    console.log('');
    const file = {
      v: 1, set: `r-${build}`,
      about: build === 'dev'
        ? 'R-dev, for tuning only: 150 items from the proof ladder training splits (MedMCQA Apache-2.0, MedQA CC-BY-4.0): the first that qualify from each plan row.'
        : 'R-test, for reporting: the 90 bench questions (seed 7, 30 a source: MedXpertQA, MedQA, CareQA Medicine), as layer.mjs picks them.',
      ...(build === 'dev' ? { plan: DEV_PLAN } : {}),
      labels: 'mechanical (retrieval-set.mjs header): keyWords, drugs and mesh are the label inputs; oracle is the official documents that exist for the item (label 2), looked up once; a passage\'s label 1 is computed from the item and these inputs at run time.',
      lookedUp: new Date().toISOString().slice(0, 10),
      items: out,
    };
    mkdirSync(LABELS_DIR, { recursive: true });
    const body = JSON.stringify(file, null, 1) + '\n';
    const name = `r-${build}.json`;
    writeFileSync(join(LABELS_DIR, name), body);
    const sums = Object.fromEntries((() => { try { return readFileSync(join(LABELS_DIR, 'SHA256SUMS'), 'utf8').split('\n').filter(Boolean).map(l => { const [h, f] = l.split(/\s+/); return [f, h]; }); } catch { return []; } })());
    sums[name] = sha256(Buffer.from(body));
    writeFileSync(join(LABELS_DIR, 'SHA256SUMS'), Object.entries(sums).sort().map(([f, h]) => `${h}  ${f}`).join('\n') + '\n');
    console.log(`${name}: ${out.length} items, ${out.filter(o => o.oracle.length).length} with an official document, ${(body.length / 1024).toFixed(0)} KB, sha256 ${sums[name]}`);
    return;
  }

  const which = arg('set', 'test');
  const limit = Number(arg('limit', '0')) || Infinity;
  const outDir = arg('out', 'out/retrieval');
  mkdirSync(outDir, { recursive: true });
  const sets = [];
  const rawResults = {};
  const notes = [];
  for (const name of which === 'both' ? ['dev', 'test'] : [which]) {
    const labels = readLabels(`r-${name}`);
    const all = name === 'dev' ? await loadDev(labels, page) : loadTest(arg('data', 'verification-bench-data'));
    const byId = new Map(all.map(q => [q.id, q]));
    const rows = [];
    for (const l of labels.items.slice(0, limit)) {
      const q = byId.get(l.id);
      if (!q) throw new Error(`${l.id} is not among the questions (is --data the bench data?)`);
      if (itemSha(q) !== l.sha) throw new Error(`${l.id}: the question differs from the one labelled (its dataset changed)`);
      const inputs = labelInputs(q, l.mesh);
      const { tally: spent, ...m } = await measureItem(q, inputs, { cache });
      for (const k of ['lookups', 'disk', 'network', 'retried', 'failed', 'bytes']) tally[k] += spent[k];
      for (const [k, n] of Object.entries(spent.byStatus)) tally.byStatus[k] = (tally.byStatus[k] || 0) + n;
      rows.push({ id: l.id, group: l.group, oracle: l.oracle.map(o => o.id), ...m });
      process.stdout.write(`\r${name}: ${rows.length}`);
    }
    console.log('');
    const groups = [...new Set(rows.map(r => r.group))];
    sets.push([`R-${name} (all ${rows.length} items; labels sha256 ${labels.sha256.slice(0, 16)})`, rows]);
    if (groups.length > 1) for (const g of groups) sets.push([`R-${name}: ${g}`, rows.filter(r => r.group === g)]);
    rawResults[name] = rows;
  }
  notes.push(`The engine's lookups: ${tally.lookups} (${tally.disk} from the disk cache, ${tally.network} on the network, ${tally.retried} retried, ${tally.failed} failed ${JSON.stringify(tally.byStatus)}). Cache ${(cache.used / 1e6).toFixed(1)} MB.`);
  const report = reportFor(which, sets, ['', ...notes, '']);
  writeFileSync(join(outDir, 'retrieval-report.md'), report + '\n');
  writeFileSync(join(outDir, 'retrieval-results.json'), JSON.stringify(rawResults, null, 1));
  console.log(report);
}

if (import.meta.url === `file://${process.argv[1]}`) main().catch(e => { console.error(e.message); process.exit(1); });
