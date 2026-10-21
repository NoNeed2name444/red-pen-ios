// The retrieval set R (docs/verification/rag-plan.md A2): how well the engine's
// literature lookup finds what a question is about, measured before the
// lookup is changed. Every label is mechanical and never comes from a model.
//
//   R-dev   150 items for tuning only, from the proof ladder's training splits
//           (tools/proof-ladder/ladder.mjs): 100 one-sentence items and 50
//           vignettes (case stems: isVignette), from MedMCQA (Apache-2.0) and MedQA (CC-BY-4.0)
//   R-test  the 90 bench questions (seed 7, 30 a source), as layer.mjs picks them
//
// Labels (an item is its question with its true key):
//   2  an official document is relevant when either
//        - it is an FDA label the engine reads as a drug's alone (officialLabel,
//          evidence.js), of a drug named in the key or in an option; or
//        - it is a MedlinePlus topic whose title or "also called" name equals the
//          key's words, or the key's MeSH preferred term (looked up once,
//          keyless, and stored in the label file)
//   1  a passage is on-topic when it holds the key's words (or the stored MeSH
//      term's) and at least one content word of the stem's last two sentences
//   0  anything else
// The drugs named are the bench's own test (drugsNamed), not the engine's
// dictionary: an option whose words, salts aside, are an RxNav ingredient or
// the generic name of a single-ingredient openFDA label, and the engine's
// list and drug endings inside longer options. Words are read the bench's own
// frozen way (benchWords), so no engine change can move a label.
//
// The official documents that exist for an item (its oracle, the recall's
// denominator) are looked up once and stored with the labels (oracleFor);
// none is pooled from what the engine retrieves. An item with none is left
// out of recall but counted.
//
// Metrics: official recall@3 and @5, micro (over the documents that exist)
// and macro (the mean of each item's); key-document recall@5 (the key's own
// label or topic, micro); nDCG@5 of what the voters are shown (evidenceFor's
// list, in its order) against an ideal that holds the oracle's documents, and
// the order-only nDCG@5 beside it; the on-topic share of what they are shown;
// the label-2 documents retrieved outside the oracle (each an oracle hole,
// fixed by re-labelling, never by changing a run); and lookups per item.
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
import { existsSync, readFileSync, readdirSync, writeFileSync, mkdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { drugTokens, claimsFor } from '../../server/proof.js';
import { evidenceFor, officialFor } from '../../server/accuracy.js';
import { DRUGS } from '../../server/accuracy-rules.js';
import { loadQuestions, benchCases, validQuestionOf } from './datasets.mjs';
import { diskCache, cachedFetcher, newTally, jsonPage } from './lookup-cache.mjs';

const here = dirname(fileURLToPath(import.meta.url));
export const LABELS_DIR = join(here, 'labels');

// MARK: the label rules (pure)

/// A text's words as the bench reads them: accents dropped, lower case, Greek
/// letters spelled out, split at anything not a letter or a digit. Frozen
/// here, not proof.js's normalizeWords, so that the label inputs and the
/// on-topic test cannot move with the engine; WORDS names this reading in the
/// label files, and a run refuses a file read another way.
export const WORDS = 'bench-words-1';
const GREEK = { α: 'alpha', β: 'beta', γ: 'gamma', δ: 'delta', ε: 'epsilon', κ: 'kappa', λ: 'lambda', μ: 'mu', σ: 'sigma', τ: 'tau', ω: 'omega' };
export const benchWords = text => String(text || '').normalize('NFKD').toLowerCase().replace(/[̀-ͯ]/g, '')
  .replace(/[α-ω]/g, c => ` ${GREEK[c] || ''} `).split(/[^a-z0-9]+/).filter(Boolean);
const wordsOf = benchWords;

// words that carry no topic: a stem's glue, not its subject
const STOP = new Set(['which', 'following', 'most', 'likely', 'patient', 'patients', 'year', 'years', 'what', 'this', 'that', 'these',
  'those', 'best', 'next', 'step', 'steps', 'with', 'from', 'after', 'before', 'about', 'there', 'their', 'shows', 'show', 'been', 'have',
  'does', 'used', 'many', 'following', 'true', 'false', 'except', 'would', 'could', 'should', 'into', 'than', 'then', 'when', 'where',
  'while', 'also', 'both', 'each', 'other', 'such', 'only', 'more', 'less', 'some', 'case', 'seen', 'found', 'given', 'following']);

/// The content words of a text: longer than three letters, not glue, not a number.
export const contentWords = text => wordsOf(text).filter(w => w.length > 3 && !STOP.has(w) && !/^\d+$/.test(w));

/// A stem's last two sentences.
export function lastSentences(stem, n = 2) {
  const parts = String(stem || '').split(/(?<=[.?!])\s+/).map(s => s.trim()).filter(Boolean);
  return parts.slice(-n).join(' ');
}

// the engine's drug cues (accuracy.js itemTerms), read inside longer options:
// the list it knows and the endings drug names take
const DRUG_SUFFIX = /\b[a-z]{3,}(?:olol|pril|sartan|statin|dipine|mab|cillin|mycin|floxacin|azole|prazole|tidine|parin|gliptin|gliflozin|triptan|setron|lukast|olone|asone|tinib|vir)\b/g;

/// The drugs of the engine's list and endings a text names, lower case.
export function drugsIn(text) {
  const t = String(text || '').toLowerCase();
  const found = new Set();
  for (const d of Object.keys(DRUGS)) if (new RegExp(`(^|[^a-z])${d.replace(/[-]/g, '\\-')}([^a-z]|$)`).test(t)) found.add(d);
  for (const m of t.matchAll(DRUG_SUFFIX)) found.add(m[0]);
  return [...found];
}

const same = (a, b) => a.length > 0 && a.length === b.length && a.every((w, i) => w === b[i]);
const holds = (a, b) => b.length > 0 && a.some((_, i) => b.every((w, j) => a[i + j] === w));
const tokensOf = name => drugTokens(name).join(' ');
// past this many words (salts aside) an option is read for the drugs inside it only
const WHOLE_MAX = 5;

/// The drugs named in the key or in any option, by the bench's own test: an
/// option whose words, salts aside, are an RxNav ingredient (named as RxNav
/// names it) or the generic name of a single-ingredient openFDA label, and
/// the engine's list and endings inside longer options (drugsIn). `look` is
/// what drugLookups found: { rx: Map words -> ingredient | null, fda: Set of words }.
/// [{ name (its words, salts aside), by: 'rxnav' | 'openFDA' | 'dictionary', key }]
export function drugsNamed(item, look) {
  const found = new Map();
  const add = (name, by, key) => {
    const t = tokensOf(name);
    if (t) found.set(t, { name: t, by: found.get(t)?.by || by, key: Boolean(found.get(t)?.key || key) });
  };
  (item.options || []).forEach((o, i) => {
    const t = tokensOf(o), key = i === item.key;
    if (look.rx.get(t)) add(look.rx.get(t), 'rxnav', key);
    else if (look.fda.has(t)) add(t, 'openFDA', key);
    for (const d of drugsIn(o)) add(d, 'dictionary', key);
  });
  return [...found.values()];
}

/// What a question's labels are made from, with the stored MeSH term.
/// `keyWords`: the key's words; `meshWords`: the MeSH preferred term's;
/// `tail`: the content words of the stem's last two sentences that are not
/// the key's. The drugs named come from lookups (drugsNamed).
export function labelInputs(item, mesh = null) {
  const keyWords = wordsOf(item.options?.[item.key]);
  const meshWords = mesh ? wordsOf(mesh) : [];
  const tail = [...new Set(contentWords(lastSentences(item.stem)))].filter(w => !keyWords.includes(w));
  return { keyWords, mesh: mesh || null, meshWords, tail };
}

/// A run's label inputs: the label file's keyWords, meshWords and drugs as
/// stored, never computed again from the engine's lists; the tail from the
/// bench's frozen words. Throws when the stored inputs are not what those
/// words make of the question now, so a label cannot move while its sha256
/// still passes.
export function inputsFor(l, q) {
  const now = labelInputs(q, l.mesh);
  const eq = (a, b) => (a || []).join(' ') === (b || []).join(' ');
  if (!eq(now.keyWords, l.keyWords) || !eq(now.meshWords, l.meshWords)) throw new Error(`${l.id}: the stored label inputs are not what the bench's words make of the question`);
  return { keyWords: l.keyWords, mesh: l.mesh, meshWords: l.meshWords || [], drugs: (l.drugs || []).map(d => d.name), tail: now.tail, oracle: (l.oracle || []).map(o => o.id) };
}

/// Label 2: whether an official document is relevant to the question.
/// `doc`: { source: 'openFDA label' | 'MedlinePlus', title, official?: { drug }, alsoCalled?: [names] }.
/// A label counts only when the engine could read it as the drug's alone
/// (`official`, which officialLabel in evidence.js sets only then).
export function officialRelevant(doc, inputs) {
  if (doc?.source === 'openFDA label') {
    const got = tokensOf(doc.official?.drug);
    return Boolean(got) && (inputs.drugs || []).some(d => (typeof d === 'string' ? d : d.name) === got);
  }
  if (doc?.source === 'MedlinePlus') {
    return [doc.title, ...(doc.alsoCalled || [])].some(name => {
      const w = wordsOf(name);
      return same(w, inputs.keyWords) || same(w, inputs.meshWords || []);
    });
  }
  return false;
}

/// Label 1: whether a passage is on-topic: it holds the key's words (all of
/// them) or the MeSH term's, and at least one content word of the stem's tail.
export function onTopic(doc, inputs) {
  const words = new Set(wordsOf(`${doc?.title || ''} ${doc?.text || ''}`));
  const has = ws => ws.length > 0 && ws.every(w => words.has(w));
  return (has(inputs.keyWords) || has(inputs.meshWords || [])) && (inputs.tail || []).some(w => words.has(w));
}

/// The label of a document shown: 2, 1 or 0.
export const labelOf = (doc, inputs) => (officialRelevant(doc, inputs) ? 2 : onTopic(doc, inputs) ? 1 : 0);

/// A document's identity across lookups: an FDA label by its drug, anything
/// else by its address.
export const docId = doc => (doc?.source === 'openFDA label' && doc.official?.drug ? `fda:${tokensOf(doc.official.drug)}` : doc?.url || '');

// MARK: the drugs and the official documents that exist (keyless lookups)

/// JSON from a source; null for its 404 ("nothing matches"); throws on a
/// failure, so a label is never made from a lookup that was not read.
const getJSON = async (fetcher, url) => {
  const res = await fetcher(url);
  if (res.status === 404) return null;
  if (!res.ok) throw new Error(`${String(url).split('?')[0]}: ${res.status}`);
  return JSON.parse(await res.text());
};

/// RxNav's ingredient of a name (an exact or normalised match whose concept
/// is of term type IN, PIN or MIN), lower case; null when RxNav has none.
export async function rxIngredient(name, fetcher) {
  const ids = (await getJSON(fetcher, `https://rxnav.nlm.nih.gov/REST/rxcui.json?name=${encodeURIComponent(name)}&search=2`))?.idGroup?.rxnormId || [];
  for (const id of ids.slice(0, 3)) {
    const p = (await getJSON(fetcher, `https://rxnav.nlm.nih.gov/REST/rxcui/${encodeURIComponent(id)}/properties.json`))?.properties;
    if (p?.name && ['IN', 'PIN', 'MIN'].includes(p.tty)) return String(p.name).toLowerCase();
  }
  return null;
}

const FDA_TERMS = 1000;
const fdaCountUrl = names => `https://api.fda.gov/drug/label.json?search=${names.map(n => `openfda.generic_name:%22${encodeURIComponent(n)}%22`).join('+')}&count=openfda.generic_name.exact&limit=${FDA_TERMS}`;

/// openFDA's exact generic names on the labels whose generic name holds any
/// of the names: a keyless count, 25 names a question (keyless openFDA
/// allows an address 1,000 lookups a day); a batch whose answer reaches the
/// count's cap is asked again in halves. [{ term, count }], most labels first.
export async function fdaTerms(names, fetcher, size = 25) {
  const terms = new Map();
  const ask = async batch => {
    const got = (await getJSON(fetcher, fdaCountUrl(batch)))?.results || [];
    if (got.length >= FDA_TERMS && batch.length > 1) {
      const h = Math.ceil(batch.length / 2);
      await ask(batch.slice(0, h)); await ask(batch.slice(h)); return;
    }
    for (const t of got) terms.set(t.term, Math.max(t.count, terms.get(t.term) || 0));
  };
  const plain = [...new Set(names)].filter(n => /^[a-z0-9]+(?: [a-z0-9]+)*$/.test(n));
  for (let i = 0; i < plain.length; i += size) await ask(plain.slice(i, i + size));
  return [...terms].map(([term, count]) => ({ term, count })).sort((a, b) => b.count - a.count);
}

/// What drugsNamed asks, for every option at once: RxNav for each option of
/// at most WHOLE_MAX words (salts aside), and openFDA's exact generic names
/// for those RxNav does not know as an ingredient.
export async function drugLookups(items, fetcher) {
  const names = [...new Set(items.flatMap(q => (q.options || []).map(tokensOf)))].filter(t => t && t.split(' ').length <= WHOLE_MAX);
  const rx = new Map();
  for (const t of names) rx.set(t, await rxIngredient(t, fetcher));
  const ask = new Set(names.filter(t => !rx.get(t)));
  const fda = new Set((await fdaTerms([...ask], fetcher)).map(t => tokensOf(t.term)).filter(t => ask.has(t)));
  return { rx, fda };
}

// a generic name of one ingredient: no "and", "with", comma, slash, plus or ampersand
const oneIngredient = term => !/[,/;&+]|\b(?:and|with)\b/i.test(term);

/// The FDA label of a drug that exists: of openFDA's exact generic names
/// (`terms`, fdaTerms) those equal to the drug by drugTokens, most labels
/// first, and of their labels (an exact search, past the first hit) the
/// first whose every generic name equals the drug. { status, id, title,
/// setId }: 'label' (fda:<drug tokens>, its set_id as provenance);
/// 'salt-only' (it has labels only as another salt, as warfarin sodium is
/// warfarin's: out of label 2, but counted); 'combination-only'; 'none'.
export async function fdaOracle(drug, terms, fetcher) {
  const want = drugTokens(drug);
  for (const { term } of terms.filter(t => same(drugTokens(t.term), want))) {
    for (let skip = 0; skip < 3; skip++) {
      const label = (await getJSON(fetcher, `https://api.fda.gov/drug/label.json?search=openfda.generic_name.exact:%22${encodeURIComponent(term)}%22&limit=1&skip=${skip}`))?.results?.[0];
      if (!label) break;
      const names = label.openfda?.generic_name || [];
      if (names.length && names.every(n => same(drugTokens(n), want))) return { status: 'label', id: `fda:${want.join(' ')}`, title: term, setId: label.set_id || label.id || null };
    }
  }
  const holding = terms.filter(t => holds(drugTokens(t.term), want));
  if (holding.some(t => oneIngredient(t.term) && drugTokens(t.term)[0] === want[0])) return { status: 'salt-only' };
  return { status: holding.length ? 'combination-only' : 'none' };
}

const unhtml = s => String(s || '')
  .replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"').replace(/&#39;|&apos;/g, "'").replace(/&amp;/g, '&')
  .replace(/<[^>]+>/g, ' ').replace(/&[a-z#0-9]+;/gi, ' ').replace(/\s+/g, ' ').trim();

/// MedlinePlus's English health topics from its full XML, by the words of
/// each topic's title and "also called" names: { topics, byWords: Map words -> [{ url, title }] }.
export function healthTopics(xml) {
  const byWords = new Map();
  let topics = 0;
  for (const m of String(xml || '').matchAll(/<health-topic\s([^>]*)>([\s\S]*?)<\/health-topic>/g)) {
    const attr = name => unhtml((m[1].match(new RegExp(`(?:^|\\s)${name}="([^"]*)"`)) || [])[1]);
    if (attr('language') !== 'English') continue;
    const topic = { url: attr('url'), title: attr('title') };
    topics++;
    const names = [topic.title, ...[...m[2].matchAll(/<also-called>([\s\S]*?)<\/also-called>/g)].map(a => unhtml(a[1]))];
    for (const words of new Set(names.map(n => wordsOf(n).join(' ')).filter(Boolean))) {
      if (!byWords.has(words)) byWords.set(words, []);
      byWords.get(words).push(topic);
    }
  }
  return { topics, byWords };
}

/// The latest health-topics XML that medlineplus.gov/xml.html lists (keyless),
/// kept in the cache directory, read by healthTopics; `file` names it.
export async function topicIndex(fetcher, dir) {
  const page = await (await fetcher('https://medlineplus.gov/xml.html')).text();
  const file = [...page.matchAll(/xml\/(mplus_topics_\d{4}-\d{2}-\d{2}\.xml)/g)].map(m => m[1]).sort().at(-1);
  if (!file) throw new Error('MedlinePlus: medlineplus.gov/xml.html lists no health-topics XML');
  const path = join(dir, file);
  if (!existsSync(path)) {
    const res = await fetcher(`https://medlineplus.gov/xml/${file}`);
    if (!res.ok) throw new Error(`MedlinePlus ${file}: ${res.status}`);
    writeFileSync(path, await res.text());
  }
  return { file, ...healthTopics(readFileSync(path, 'utf8')) };
}

/// The official documents that exist for a question, by the label-2 rules,
/// looked up once and stored (the recall's denominator): each drug named's
/// FDA label (fdaOracle), and the MedlinePlus topics whose title or "also
/// called" name is the key's words or the MeSH term's (topicIndex). The
/// engine's own lookups are not used, and nothing is pooled from what it
/// retrieves, so the documents that exist do not depend on what it finds.
/// { drugs: the drugs with their FDA status, oracle: [{ id, title, setId?, key }] },
/// `key`: the key's own label or topic.
export async function oracleFor(inputs, { terms, topics, fetcher }) {
  const found = new Map();
  const drugs = [];
  for (const d of inputs.drugs) {
    const fda = await fdaOracle(d.name, terms, fetcher);
    drugs.push({ ...d, fda: fda.status });
    if (fda.status === 'label') found.set(fda.id, { id: fda.id, title: fda.title, setId: fda.setId, key: d.key });
  }
  for (const words of [inputs.keyWords, inputs.meshWords]) {
    for (const t of (words.length && topics.byWords.get(words.join(' '))) || []) found.set(t.url, { id: t.url, title: t.title, key: true });
  }
  return { drugs, oracle: [...found.values()] };
}

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

/// nDCG at k of a shown list's labels. The ideal is the best order of that
/// list together with the item's oracle documents it did not show
/// (`missing`, label 2 each), so a missed official document costs; with
/// `missing` 0 it is the order-only figure. 0 when nothing relevant was shown
/// or exists (and for an empty list).
export function ndcgAt(k, labels, missing = 0) {
  const ideal = dcgAt(k, [...labels, ...Array(missing).fill(2)].sort((a, b) => b - a));
  return ideal > 0 ? dcgAt(k, labels) / ideal : 0;
}

/// The set's numbers from its items' rows: { id, group, oracle: [ids],
/// keyDocs: [ids], retrieved: [ids], shown: [labels], missing, outside: [ids],
/// lookups }. Recall is micro (over the documents that exist) and macro (the
/// mean of each item's); an item with no document that exists is left out of
/// recall and counted. An item whose lookups failed (row.failed > 0) is not
/// a miss: nothing is known about what it would have found, so it is left out
/// of recall and nDCG and counted apart (lookupFailed), as proof-only.mjs
/// counts a failed lookup apart from not proven.
export function summarize(rows) {
  const lookupFailed = rows.filter(r => (r.failed || 0) > 0);
  const measured = rows.filter(r => !((r.failed || 0) > 0));
  const answerable = measured.filter(r => r.oracle.length);
  const found = (k, r, want) => recallAt(k, r.retrieved, want) * want.length;
  const wants = answerable.reduce((s, r) => s + r.oracle.length, 0);
  const keyed = measured.filter(r => (r.keyDocs || []).length);
  const keyWants = keyed.reduce((s, r) => s + r.keyDocs.length, 0);
  const shown = rows.flatMap(r => r.shown);
  const mean = list => (list.length ? list.reduce((a, b) => a + b, 0) / list.length : null);
  return {
    items: rows.length,
    lookupFailed: lookupFailed.length,
    lookupFailedUnread: lookupFailed.reduce((s, r) => s + (r.unread || 0), 0),
    measured: measured.length,
    answerable: answerable.length,
    officialDocs: wants,
    recall3: wants ? answerable.reduce((s, r) => s + found(3, r, r.oracle), 0) / wants : null,
    recall5: wants ? answerable.reduce((s, r) => s + found(5, r, r.oracle), 0) / wants : null,
    recall5Macro: mean(answerable.map(r => recallAt(5, r.retrieved, r.oracle))),
    keyItems: keyed.length,
    keyDocs: keyWants,
    keyRecall5: keyWants ? keyed.reduce((s, r) => s + found(5, r, r.keyDocs), 0) / keyWants : null,
    outside: rows.reduce((s, r) => s + (r.outside || []).length, 0),
    ndcg5: mean(measured.map(r => ndcgAt(5, r.shown, r.missing || 0))),
    ndcg5Order: mean(measured.map(r => ndcgAt(5, r.shown))),
    passages: shown.length,
    onTopic: shown.length ? shown.filter(l => l >= 1).length / shown.length : null,
    official: shown.length ? shown.filter(l => l === 2).length / shown.length : null,
    lookupsPerItem: mean(rows.map(r => r.lookups)),
    shownPerItem: mean(rows.map(r => r.shown.length)),
    noPassage: rows.filter(r => !r.shown.length).length,
  };
}

// MARK: MedlinePlus and MeSH, read for labels

/// The topics in a MedlinePlus search answer (wsearch XML): [{ url, title, alsoCalled: [names] }].
export function topicsIn(xml) {
  const out = [];
  for (const doc of String(xml || '').matchAll(/<document[^>]*url="([^"]+)"[^>]*>([\s\S]*?)<\/document>/g)) {
    const field = name => [...doc[2].matchAll(new RegExp(`<content name="${name}">([\\s\\S]*?)</content>`, 'g'))].map(m => unhtml(m[1]));
    out.push({ url: doc[1], title: field('title')[0] || '', alsoCalled: field('altTitle') });
  }
  return out;
}

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
  const file = JSON.parse(raw);
  if (file.words !== WORDS) throw new Error(`labels/${name}.json was not read with the bench's words (${WORDS}): build it again`);
  return { ...file, sha256: want };
}

/// The R-dev selection, in the proof ladder's training splits: from a fixed
/// row onward, the first questions that qualify. A one-sentence item is one
/// the source proof can read (the ladder's `readable`) that is no vignette; a
/// vignette is a case stem (isVignette), never one picked for the proof
/// declining it.
export const DEV_PLAN = [
  { src: 'medmcqa-train', dataset: 'openlifescienceai/medmcqa', split: 'train', start: 100000, want: 100, kind: 'one-sentence', rule: 'the source proof reads it (claimsFor gives no why) and it is no vignette' },
  { src: 'medqa-train', dataset: 'GBaker/MedQA-USMLE-4-options', split: 'train', start: 5000, want: 25, kind: 'vignette', rule: 'isVignette: two or more sentences with a patient presentation' },
  { src: 'medmcqa-train', dataset: 'openlifescienceai/medmcqa', split: 'train', start: 120000, want: 25, kind: 'vignette', rule: 'isVignette: two or more sentences with a patient presentation' },
];

/// A stem's sentences: split after ".", "?" or "!" before a capital, a digit
/// or a quote; each of three words or more.
export const sentencesOf = stem => String(stem || '').split(/(?<=[.?!])\s+(?=[A-Z0-9"'(])/).filter(s => s.trim().split(/\s+/).length >= 3);
// a patient presentation: an age, or a person with what brought them
const AGE = /\b\d{1,3}[- ]?(?:years?|yrs?|months?|weeks?|days?)[- ]old\b|\baged \d{1,3}\b/i;
const PERSON = /\b(?:man|woman|male|female|boy|girl|child|infant|neonate|newborn|baby|patient|lady|gentleman|adolescent)\b/i;
const PRESENTS = /\b(?:presents?|presented|presenting|comes?|came|brought|admitted|complains?|complained|complaining|reports?|reported|referred|develops?|developed|noticed)\b/i;

/// Whether a question is a vignette: a case stem of two or more sentences
/// with a patient presentation (an age, or a person and what brought them).
export const isVignette = q => sentencesOf(q.stem).length >= 2 && (AGE.test(q.stem) || (PERSON.test(q.stem) && PRESENTS.test(q.stem)));

export function classify(q) {
  if (isVignette(q)) return 'vignette';
  try { return claimsFor({ ...q, kind: 'mcq' }, 5e6).why ? null : 'one-sentence'; } catch { return null; }
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
  const shownDocs = shown.map(docOf), foundDocs = entries.map(docOf);
  const shownIds = shownDocs.map(docId);
  const oracle = new Set(inputs.oracle || []);
  return {
    retrieved: foundDocs.map(docId),
    shown: shownDocs.map(d => labelOf(d, inputs)),
    shownIds,
    // the oracle's documents the voters were not shown: nDCG's ideal holds them
    missing: [...oracle].filter(id => !shownIds.includes(id)).length,
    // label-2 documents found that the oracle lacks: oracle holes, fixed by re-labelling
    outside: [...new Set([...foundDocs, ...shownDocs].filter(d => labelOf(d, inputs) === 2 && !oracle.has(docId(d))).map(docId))],
    shownTitles: shown.map(e => `${e.source}: ${e.title}`),
    lookups: tally.lookups, unread, failed: tally.failed, tally,
  };
}

// MARK: the report

const f2 = x => (x === null || x === undefined ? 'n/a' : x.toFixed(2));
const pc = x => (x === null || x === undefined ? 'n/a' : `${(100 * x).toFixed(1)}%`);

export function reportFor(name, sets, notes = []) {
  const lines = [`# Retrieval set R: ${name}`, ''];
  for (const [label, rows, extra = []] of sets) {
    const s = summarize(rows);
    lines.push(`## ${label}`, '', `${s.items} items; ${s.answerable} have an official document that exists (${s.officialDocs} in all); ${s.measured - s.answerable} have none (left out of recall, counted here); ${s.lookupFailed} had a failed lookup (${s.lookupFailedUnread} sources unread; left out of recall and nDCG, not counted as misses).`, '',
      '| measure | result |', '|---|---|',
      `| official recall@3, micro (over the documents that exist) | ${pc(s.recall3)} |`, `| official recall@5, micro | ${pc(s.recall5)} |`,
      `| official recall@5, macro (the mean of each item's) | ${pc(s.recall5Macro)} |`,
      `| key-document recall@5, micro (the key's own label or topic: ${s.keyDocs} in ${s.keyItems} items) | ${pc(s.keyRecall5)} |`,
      `| nDCG@5 of what voters are shown (ideal: the list and the oracle's documents) | ${f2(s.ndcg5)} |`,
      `| nDCG@5, order only (ideal: the list itself) | ${f2(s.ndcg5Order)} |`,
      `| on-topic share of passages shown | ${pc(s.onTopic)} (${s.passages} passages, ${f2(s.shownPerItem)} an item; ${s.noPassage} items showed none) |`,
      `| official share of passages shown | ${pc(s.official)} |`,
      `| label-2 documents retrieved outside the oracle (oracle holes: re-label, never change a run) | ${s.outside} |`,
      `| lookups per item | ${f2(s.lookupsPerItem)} |`, '', ...extra, ...(extra.length ? [''] : []));
  }
  return [...lines, ...notes].join('\n');
}

/// What the label files say of the drugs named: how each was found, and its FDA label.
export function drugNote(items) {
  const d = items.flatMap(i => i.drugs || []);
  const n = (k, v) => d.filter(x => x[k] === v).length;
  return `Drugs named: ${d.length} (RxNav ${n('by', 'rxnav')}, openFDA ${n('by', 'openFDA')}, the engine's list and endings ${n('by', 'dictionary')}); with a single-ingredient FDA label ${n('fda', 'label')}, only as other salts ${n('fda', 'salt-only')} (out of label 2, counted), only in combinations ${n('fda', 'combination-only')}, no label ${n('fda', 'none')}.`;
}

// MARK: command line

async function main() {
  const arg = (name, fallback = null) => { const i = process.argv.indexOf(`--${name}`); return i > 0 ? process.argv[i + 1] : fallback; };
  const cacheDir = arg('cache', join(process.env.TMPDIR || '/tmp', 'ragbench-cache'));
  const cache = diskCache(cacheDir);
  const tally = newTally();
  const shared = cachedFetcher({ cache, tally });
  const page = jsonPage(shared);
  const build = arg('build-labels');
  if (build) {
    const items = build === 'dev'
      ? (await selectDev(page)).map(d => ({ id: d.id, group: d.group, row: { dataset: d.dataset, split: d.split, offset: d.offset }, q: d.q }))
      : loadTest(arg('data', 'verification-bench-data')).map(q => ({ id: q.id, group: q.source, q }));
    let vignettes;
    if (build === 'dev') {
      const v = items.filter(it => it.group === 'vignette');
      const n = v.map(it => sentencesOf(it.q.stem).length).sort((a, b) => a - b);
      vignettes = { medqa: v.filter(it => it.id.startsWith('medqa')).length, medmcqa: v.filter(it => it.id.startsWith('medmcqa')).length, leastSentences: n[0], medianSentences: n[n.length >> 1] };
      console.log(`R-dev: ${v.length} vignettes (${vignettes.medqa} MedQA, ${vignettes.medmcqa} MedMCQA), each a case stem of two or more sentences with a patient presentation (sentences: least ${n[0]}, median ${vignettes.medianSentences}); none picked for the proof declining it.`);
    }
    const look = await drugLookups(items.map(it => it.q), shared);
    const inputs = [];
    for (const it of items) {
      inputs.push({ ...labelInputs(it.q, await meshPreferred(it.q.options[it.q.key], shared)), drugs: drugsNamed(it.q, look) });
      process.stdout.write(`\rinputs ${inputs.length}/${items.length}`);
    }
    const terms = await fdaTerms(inputs.flatMap(i => i.drugs.map(d => d.name)), shared);
    const topics = await topicIndex(shared, cacheDir);
    const out = [];
    for (const [n, it] of items.entries()) {
      const { drugs, oracle } = await oracleFor(inputs[n], { terms, topics, fetcher: shared });
      out.push({ id: it.id, group: it.group, ...(it.row ? { row: it.row } : {}), sha: itemSha(it.q), keyWords: inputs[n].keyWords, mesh: inputs[n].mesh, meshWords: inputs[n].meshWords, drugs, oracle });
      process.stdout.write(`\roracle ${out.length}/${items.length}`);
    }
    console.log('');
    if (tally.failed) throw new Error(`${tally.failed} lookups failed ${JSON.stringify(tally.byStatus)}: no label file written; run again (the cache keeps what was read)`);
    const file = {
      v: 1, set: `r-${build}`, words: WORDS,
      about: build === 'dev'
        ? 'R-dev, for tuning only: 150 items from the proof ladder training splits (MedMCQA Apache-2.0, MedQA CC-BY-4.0): the first that qualify from each plan row.'
        : 'R-test, for reporting: the 90 bench questions (seed 7, 30 a source: MedXpertQA, MedQA, CareQA Medicine), as layer.mjs picks them.',
      ...(build === 'dev' ? { plan: DEV_PLAN, vignettes } : {}),
      labels: 'mechanical (retrieval-set.mjs header): keyWords and meshWords are the key\'s and the MeSH term\'s words (benchWords); drugs are the drugs named (drugsNamed: found by RxNav, openFDA or the engine\'s list; key: named in the key; fda: its FDA label, fdaOracle); oracle is the official documents that exist for the item (label 2), looked up once and never pooled from a run (an FDA label as fda:<drug tokens> with its set_id, a MedlinePlus topic by its address; key: the key\'s own); a passage\'s label 1 is computed at run time from the item, these inputs and the bench\'s words.',
      sources: { rxnav: 'rxcui.json search=2, then the concept\'s term type (IN, PIN, MIN)', openFDA: 'keyless: counts of openfda.generic_name.exact, then generic_name.exact searches', medlinePlus: topics.file, mesh: 'id.nlm.nih.gov/mesh lookup' },
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
    console.log(`${name}: ${out.length} items, ${out.filter(o => o.oracle.length).length} with an official document, ${(body.length / 1024).toFixed(0)} KB, sha256 ${sums[name]}. ${drugNote(out)}`);
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
      const inputs = inputsFor(l, q);
      const { tally: spent, ...m } = await measureItem(q, inputs, { cache });
      for (const k of ['lookups', 'disk', 'network', 'retried', 'failed', 'bytes']) tally[k] += spent[k];
      for (const [k, n] of Object.entries(spent.byStatus)) tally.byStatus[k] = (tally.byStatus[k] || 0) + n;
      rows.push({ id: l.id, group: l.group, oracle: inputs.oracle, keyDocs: l.oracle.filter(o => o.key).map(o => o.id), ...m });
      process.stdout.write(`\r${name}: ${rows.length}`);
    }
    console.log('');
    const groups = [...new Set(rows.map(r => r.group))];
    sets.push([`R-${name} (all ${rows.length} items; labels sha256 ${labels.sha256.slice(0, 16)})`, rows, [drugNote(labels.items.slice(0, rows.length))]]);
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
