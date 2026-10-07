// Evidence from official, current medical sources, for CramDown Cloud's
// accuracy checker.
//
// A lecture can be out of date and a model can be confidently wrong, so the
// checker does not only compare an answer with the lecture: it is also shown
// what current, citable sources say, and told to flag anything that
// contradicts them. All three sources are free and need no key:
//
//   Europe PMC   - PubMed and more; recent reviews and guidelines first
//   MedlinePlus  - the US National Library of Medicine's reviewed topic pages
//   openFDA      - the current FDA label of any drug named (dose, contraindications)
//
// Every lookup has a short timeout and is cached for a day, so a slow source
// costs a check a few seconds at most and never fails it.
//
// MedlinePlus and openFDA entries also carry the source's own full text for
// proof (server/proof.js): `html`, the summary as MedlinePlus sends it, and
// `official`, the label's sections. They stay on the server: the evidence a
// model is shown, or the app is sent, never has them (gather, and accuracy.js
// evidenceFor, leave them out).

import { FDA_SECTIONS, drugTokens } from './proof.js';

const TIMEOUT_MS = 6000;
const CACHE_SECONDS = 24 * 60 * 60;
const MAX_EVIDENCE_CHARS = 7000;
// the longest summary kept for proof, as sent (escaped HTML): proof reads a
// summary whole, never a cut one that could end on half a sentence, and the
// longest topics run to about 15,000 characters
const MAX_SUMMARY_HTML = 40_000;

/// Pull the output being checked (and the lecture it came from) out of a
/// MedVAL-format prompt. Null when the text is not one.
export function medvalParts(text) {
  if (typeof text !== 'string' || !text.includes('[[ ## output ## ]]')) return null;
  const section = name => {
    const m = text.match(new RegExp(`\\[\\[ ## ${name} ## \\]\\]\\n([\\s\\S]*?)(?=\\n\\[\\[ ## |$)`));
    return m ? m[1].trim() : '';
  };
  return { instruction: section('instruction'), input: section('input'), output: section('output') };
}

/// Search terms for what is being checked: a few short medical queries and
/// any drug names, chosen by the model itself so the lookup is about the claim
/// rather than about every word in it.
export function termsPrompt(output) {
  return [
    { role: 'system', content: 'You pick search terms for checking medical study material against the literature. Reply with JSON only.' },
    { role: 'user', content:
      'From the study material below, list up to 3 short English search queries (2-5 words each, the medical topics whose facts matter most) ' +
      'and up to 3 drug generic names it mentions. Reply exactly as {"queries":["..."],"drugs":["..."]}.\n\n' + output.slice(0, 3000) },
  ];
}

export function parseTerms(reply) {
  try {
    const json = JSON.parse(String(reply).slice(String(reply).indexOf('{'), String(reply).lastIndexOf('}') + 1));
    const clean = list => (Array.isArray(list) ? list : [])
      .map(s => String(s).replace(/[^\p{L}\p{N} \-]/gu, ' ').replace(/\s+/g, ' ').trim())
      .filter(s => s.length > 2 && s.length < 60);
    return { queries: clean(json.queries).slice(0, 3), drugs: clean(json.drugs).slice(0, 3) };
  } catch {
    return { queries: [], drugs: [] };
  }
}

async function getJSON(url, fetcher, sendAs = url) {
  const text = await getText(url, fetcher, sendAs);
  try { return text ? JSON.parse(text) : null; } catch { return null; }
}

// Answers already fetched, kept in this isolate for the same day. The edge
// cache (caches.default) does nothing on a workers.dev host, which is the one
// the app calls, so without this every batch asked the same sources again.
// Kept per fetcher, so one service's answers are never handed to another
// (the worker always passes fetch, tests their own fakes).
const MEMORY_ENTRIES = 300;
let memories = new WeakMap();
const memoryOf = fetcher => {
  if (!memories.has(fetcher)) memories.set(fetcher, new Map());
  return memories.get(fetcher);
};

function recall(remembered, url, at = Date.now()) {
  const hit = remembered.get(url);
  if (!hit) return null;
  if (at - hit.at > CACHE_SECONDS * 1000) { remembered.delete(url); return null; }
  // most recently used last, so the oldest is the one dropped
  remembered.delete(url);
  remembered.set(url, hit);
  return hit.text;
}

function remember(remembered, url, text, at = Date.now()) {
  remembered.delete(url);
  remembered.set(url, { text, at });
  while (remembered.size > MEMORY_ENTRIES) remembered.delete(remembered.keys().next().value);
}

/// Tests only: start from an empty memory.
export function forgetEvidence() { memories = new WeakMap(); }

// openFDA allows 1,000 calls a day per address without a key and 120,000
// with one (free, from open.fda.gov). worker.js passes env.OPENFDA_API_KEY.
let openFDAKey = '';
export function useOpenFDAKey(key) { openFDAKey = typeof key === 'string' ? key.trim() : ''; }

async function getText(url, fetcher, sendAs = url) {
  const remembered = memoryOf(fetcher);
  const known = recall(remembered, url);
  if (known !== null) return known;
  const cache = globalThis.caches?.default;
  if (cache) {
    const hit = await cache.match(url).catch(() => null);
    if (hit) {
      const text = await hit.text();
      remember(remembered, url, text);
      return text;
    }
  }
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), TIMEOUT_MS);
  try {
    const response = await fetcher(sendAs, { signal: controller.signal, headers: { 'user-agent': 'CramDown/1.0 (study app)' } });
    if (!response.ok) return null;
    const text = await response.text();
    remember(remembered, url, text);
    if (cache) {
      await cache.put(url, new Response(text, { headers: { 'cache-control': `max-age=${CACHE_SECONDS}` } })).catch(() => {});
    }
    return text;
  } catch {
    return null;
  } finally {
    clearTimeout(timer);
  }
}

const trim = (s, n) => (s.length > n ? s.slice(0, n).replace(/\s+\S*$/, '') + '…' : s);
// MedlinePlus sends its HTML escaped inside XML: decode first, then strip
const unhtml = s => String(s || '')
  .replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"').replace(/&#39;|&apos;/g, "'").replace(/&amp;/g, '&')
  .replace(/<[^>]+>/g, ' ').replace(/&[a-z#0-9]+;/gi, ' ').replace(/\s+/g, ' ').trim();

/// Europe PMC: reviews and guidelines from the last six years, most relevant
/// first, never a retracted record or a retraction notice (a discredited
/// source supports nothing).
export async function europePMC(query, fetcher = fetch) {
  const since = new Date().getUTCFullYear() - 6;
  const q = `(${query}) AND (PUB_TYPE:"review" OR PUB_TYPE:"guideline" OR PUB_TYPE:"practice guideline") AND NOT (PUB_TYPE:"retracted publication" OR PUB_TYPE:"retraction of publication") AND FIRST_PDATE:[${since}-01-01 TO 3000-01-01] AND HAS_ABSTRACT:y`;
  const url = `https://www.ebi.ac.uk/europepmc/webservices/rest/search?query=${encodeURIComponent(q)}&resultType=core&format=json&pageSize=2`; // relevance is the default order (an explicit sort=RELEVANCE answers 503)
  const data = await getJSON(url, fetcher);
  return (data?.resultList?.result || []).map(r => ({
    source: 'Europe PMC',
    title: `${unhtml(r.title)} (${r.journalInfo?.journal?.isoabbreviation || r.journalTitle || 'journal'}, ${r.pubYear})`,
    url: r.doi ? `https://doi.org/${r.doi}` : `https://europepmc.org/article/${r.source}/${r.id}`,
    text: trim(unhtml(r.abstractText), 900),
  })).filter(e => e.text);
}

/// MedlinePlus health topics (NLM), the reviewed summary for the topic; with
/// `html`, the whole summary as sent, when it is not past MAX_SUMMARY_HTML.
export async function medlinePlus(query, fetcher = fetch) {
  const url = `https://wsearch.nlm.nih.gov/ws/query?db=healthTopics&term=${encodeURIComponent(query)}&retmax=1`;
  const xml = await getText(url, fetcher);
  if (!xml) return [];
  const doc = xml.match(/<document[^>]*url="([^"]+)"[\s\S]*?<\/document>/);
  if (!doc) return [];
  const raw = name => (doc[0].match(new RegExp(`<content name="${name}">([\\s\\S]*?)</content>`)) || [])[1];
  const field = name => unhtml(raw(name));
  const text = field('FullSummary') || field('snippet');
  if (!text) return [];
  const entry = { source: 'MedlinePlus', title: field('title') || query, url: doc[1], text: trim(text, 700) };
  const html = raw('FullSummary');
  if (html && html.length <= MAX_SUMMARY_HTML) entry.html = html;
  return [entry];
}

/// The label's own sections, for proof: only when it is the label of this
/// drug alone, every generic name it lists naming the drug and nothing more
/// (a salt the name leaves out aside, as "metformin hydrochloride" is
/// metformin). A combination ("lisinopril and hydrochlorothiazide"), another
/// salt ("warfarin sodium"), a form in the name ("metformin ER 500 mg") or one
/// of a class ("insulin lispro") is not the drug a claim names, so it proves
/// nothing about it. Only the sections proof reads, as the label has them.
function officialLabel(drug, label) {
  const want = drugTokens(drug);
  const names = label.openfda?.generic_name;
  if (!want.length || !Array.isArray(names) || !names.length) return null;
  const same = names.every(name => {
    const got = drugTokens(name);
    return got.length === want.length && got.every((t, i) => t === want[i]);
  });
  if (!same) return null;
  const sections = {};
  for (const key of FDA_SECTIONS) {
    const texts = (Array.isArray(label[key]) ? label[key] : [label[key]]).filter(v => typeof v === 'string' && v);
    if (texts.length) sections[key] = texts;
  }
  return Object.keys(sections).length ? { drug, effective: label.effective_time || null, sections } : null;
}

/// openFDA: the current label of a drug, the parts a question would test;
/// with `official`, its sections whole, when it is the drug's alone.
export async function openFDA(drug, fetcher = fetch) {
  const url = `https://api.fda.gov/drug/label.json?search=openfda.generic_name:%22${encodeURIComponent(drug)}%22&limit=1`;
  // cached under the address without the key, so the key is never stored
  const data = await getJSON(url, fetcher, openFDAKey ? `${url}&api_key=${encodeURIComponent(openFDAKey)}` : url);
  const label = data?.results?.[0];
  if (!label) return [];
  const part = key => trim(unhtml((label[key] || []).join(' ')), 350);
  const text = [
    ['Indications', part('indications_and_usage')],
    ['Dosage', part('dosage_and_administration')],
    ['Contraindications', part('contraindications')],
    ['Warnings', part('boxed_warning') || part('warnings_and_cautions') || part('warnings')],
  ].filter(([, v]) => v).map(([k, v]) => `${k}: ${v}`).join(' ');
  const setId = label.set_id || label.id;
  if (!text) return [];
  const entry = {
    source: 'openFDA label', title: `${drug} (FDA label, effective ${label.effective_time || 'current'})`,
    url: setId ? `https://dailymed.nlm.nih.gov/dailymed/lookup.cfm?setid=${setId}` : 'https://open.fda.gov/apis/drug/label/',
    text,
  };
  const official = officialLabel(drug, label);
  if (official) entry.official = official;
  return [entry];
}

/// A title as the same work's other records write it: the "(journal, year)"
/// the listing adds and any case, markup or punctuation set aside.
export function workKey(title) {
  const words = String(title || '').replace(/\s*\([^()]*\)\s*$/, '').toLowerCase()
    .replace(/[^a-z0-9]+/g, ' ').trim().slice(0, 120);
  return words ? 't:' + words : '';
}

/// Everything found for these terms, deduplicated and numbered [S1], [S2]...
export async function gather(terms, fetcher = fetch) {
  const lookups = [
    ...terms.queries.map(q => europePMC(q, fetcher)),
    ...terms.queries.slice(0, 2).map(q => medlinePlus(q, fetcher)),
    ...terms.drugs.map(d => openFDA(d, fetcher)),
  ];
  const found = (await Promise.all(lookups.map(p => p.catch(() => [])))).flat();
  // one work counts once: the same review found by two queries, or as a
  // preprint and as published (another DOI, the same title), is one source,
  // not two agreeing (Islamic brief: two chains through one narrator are one)
  const seen = new Set();
  const unique = found.filter(e => {
    const work = workKey(e.title);
    if (seen.has(e.url) || (work && seen.has(work))) return false;
    seen.add(e.url);
    if (work) seen.add(work);
    return true;
  });
  const out = [];
  let used = 0;
  for (const e of unique) {
    if (used + e.text.length > MAX_EVIDENCE_CHARS) break;
    used += e.text.length;
    out.push({ ...forModels(e), id: `S${out.length + 1}` });
  }
  return out;
}

/// An entry as a model or the app may see it: without the full texts kept
/// for proof.
export function forModels(entry) {
  const { official, html, ...rest } = entry;
  return rest;
}

export function evidenceBlock(evidence) {
  return evidence.map(e => `[${e.id}] ${e.source}: ${e.title}\n${e.url}\n${e.text}`).join('\n\n');
}

/// The checker's instructions when there is evidence: judge against the
/// lecture as MedVAL does, and ALSO against current evidence, citing it.
export function groundedMessages(messages, evidence) {
  if (!evidence.length) return messages;
  const note = {
    role: 'system',
    content:
      'You are checking medical study material for accuracy. Besides comparing the output with the input as instructed, ' +
      'use the REFERENCE EVIDENCE below: current reviews, guidelines, NLM MedlinePlus and FDA drug labels. ' +
      'If the output states something that contradicts the reference evidence or well-established current medical consensus ' +
      '(for example an outdated first-line treatment, a wrong dose, a wrong diagnostic criterion, a wrong answer to a clinical question), ' +
      'list it as an error even if the input (the lecture) says the same: write "Other: contradicts current evidence [Sn]" citing the source, ' +
      'or "Other: contradicts current medical consensus" when no source covers it, and set the risk level to 3 or 4. ' +
      'If the output format has a reasoning_issues field, a factual claim supported by neither the input nor the reference evidence ' +
      'is an "Unsupported claim" there, and a claim the evidence contradicts is also named there, citing [Sn]. ' +
      'Do not invent sources. Keep the exact output format asked for.\n\n' +
      'REFERENCE EVIDENCE\n\n' + evidenceBlock(evidence),
  };
  return [note, ...messages];
}

/// For a question rather than a check: the evidence goes first, with the
/// instruction to use it and to say when it does not cover the question.
export function answerWithEvidence(messages, evidence) {
  if (!evidence.length) return messages;
  return [{
    role: 'system',
    content: 'Use the REFERENCE EVIDENCE below (current reviews, guidelines, NLM MedlinePlus, FDA labels) where it is relevant, ' +
      'cite it as [Sn], and prefer it over older teaching. If it does not cover the question, answer from established medical knowledge.\n\n' +
      'REFERENCE EVIDENCE\n\n' + evidenceBlock(evidence),
  }, ...messages];
}
