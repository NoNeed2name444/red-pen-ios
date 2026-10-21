#!/usr/bin/env node
// The question bank's source fetcher (plan Task 5b step 2). It reads passages
// only from sources the licence allowlist allows, and only through the
// interfaces those sources sanction:
//   - MedlinePlus health topics, through the MedlinePlus web service
//     (wsearch.nlm.nih.gov), text only; the A.D.A.M. encyclopedia (/ency/)
//     and drug monographs (/druginfo/) are refused by the licence gate.
//   - PMC Open Access articles, through NCBI E-utilities (esearch, then
//     efetch for the article's JATS XML). Each article's own <license> decides;
//     only CC0 and CC BY pass, and an article with no readable licence is
//     refused.
// Every passage goes through licenceVerdict before it is kept. Anything
// refused is written to the refusals log with its reason, never to the bank.
//
// Run: node tools/question-bank/fetch.mjs --out bank/passages.jsonl \
//        --topics "asthma,heart failure" [--pmc-per-topic 2]
// Optional environment: NCBI_API_KEY (10 requests a second instead of 3),
// NCBI_EMAIL (sent to NCBI as the contact, as E-utilities asks).
// Node 22, no dependencies. See README.md for the exact endpoints.
import { createWriteStream, mkdirSync, readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { licenceVerdict } from '../../governance/licences/licences.mjs';

export const USER_AGENT = 'StethoscoreQuestionBank/0.1 (+https://github.com/NoNeed2name444/red-pen-ios; licence-checked study passages)';
export const MEDLINEPLUS_SEARCH = 'https://wsearch.nlm.nih.gov/ws/query';
export const EUTILS = 'https://eutils.ncbi.nlm.nih.gov/entrez/eutils';
export const PMC_ARTICLE = 'https://pmc.ncbi.nlm.nih.gov/articles/';
const MEDLINEPLUS_LICENCE = 'US-GOV-PD-MEDLINEPLUS';
const TOOL = 'stethoscore-question-bank';

// ---------------------------------------------------------------- XML ----
// A small, strict-enough XML reader: elements, attributes, text, CDATA and
// entities. Comments, doctype and processing instructions are skipped.

const XML_ENTITIES = { amp: '&', lt: '<', gt: '>', quot: '"', apos: "'", nbsp: ' ', ndash: '–', mdash: '—', rsquo: '’', lsquo: '‘', rdquo: '”', ldquo: '“', hellip: '…', middot: '·', deg: '°', plusmn: '±', times: '×', micro: 'µ', reg: '®', copy: '©', trade: '™' };

export function decodeEntities(s) {
  return s.replace(/&(#x[0-9a-f]+|#\d+|[a-z][a-z0-9]*);/gi, (m, e) => {
    if (e[0] === '#') {
      const cp = e[1] === 'x' || e[1] === 'X' ? parseInt(e.slice(2), 16) : parseInt(e.slice(1), 10);
      try { return String.fromCodePoint(cp); } catch { return m; }
    }
    return XML_ENTITIES[e] ?? XML_ENTITIES[e.toLowerCase()] ?? m;
  });
}

/// The document as {name, attrs, children}; children are nodes or strings.
export function parseXml(xml) {
  const root = { name: '#document', attrs: {}, children: [] };
  const stack = [root];
  let i = 0;
  const top = () => stack[stack.length - 1];
  while (i < xml.length) {
    const lt = xml.indexOf('<', i);
    if (lt < 0) { top().children.push(decodeEntities(xml.slice(i))); break; }
    if (lt > i) top().children.push(decodeEntities(xml.slice(i, lt)));
    if (xml.startsWith('<!--', lt)) { const e = xml.indexOf('-->', lt + 4); i = e < 0 ? xml.length : e + 3; continue; }
    if (xml.startsWith('<![CDATA[', lt)) { const e = xml.indexOf(']]>', lt + 9); top().children.push(xml.slice(lt + 9, e < 0 ? xml.length : e)); i = e < 0 ? xml.length : e + 3; continue; }
    if (xml.startsWith('<?', lt)) { const e = xml.indexOf('?>', lt + 2); i = e < 0 ? xml.length : e + 2; continue; }
    if (xml.startsWith('<!', lt)) {
      // DOCTYPE, possibly with an internal subset in brackets.
      let j = lt + 2, depth = 0;
      for (; j < xml.length; j++) { const c = xml[j]; if (c === '[') depth++; else if (c === ']') depth--; else if (c === '>' && depth <= 0) break; }
      i = j + 1; continue;
    }
    // A tag: find its end outside quoted attribute values.
    let j = lt + 1, quote = null;
    for (; j < xml.length; j++) { const c = xml[j]; if (quote) { if (c === quote) quote = null; } else if (c === '"' || c === "'") quote = c; else if (c === '>') break; }
    const raw = xml.slice(lt + 1, j);
    i = j + 1;
    if (raw[0] === '/') {
      const name = raw.slice(1).trim();
      // Close up to the matching element; tolerate stray closers.
      for (let k = stack.length - 1; k > 0; k--) if (stack[k].name === name) { stack.length = k; break; }
      continue;
    }
    const selfClosing = raw.endsWith('/');
    const body = selfClosing ? raw.slice(0, -1) : raw;
    const name = body.match(/^[^\s/>]+/)?.[0] ?? '';
    const attrs = {};
    for (const a of body.slice(name.length).matchAll(/([^\s=]+)\s*=\s*("([^"]*)"|'([^']*)')/g)) attrs[a[1]] = decodeEntities(a[3] ?? a[4] ?? '');
    const node = { name, attrs, children: [] };
    top().children.push(node);
    if (!selfClosing) stack.push(node);
  }
  return root;
}

const local = name => name.includes(':') ? name.slice(name.indexOf(':') + 1) : name;
const isNode = n => n && typeof n === 'object';
export function children(node, name) { return (node?.children ?? []).filter(c => isNode(c) && (!name || local(c.name) === name)); }
export function child(node, name) { return children(node, name)[0] ?? null; }
/// Every descendant with this (namespace-free) name, in document order,
/// not looking inside any element named in `skip`.
export function findAll(node, name, out = [], skip = null) {
  for (const c of node?.children ?? []) if (isNode(c)) {
    if (skip?.has(local(c.name))) continue;
    if (local(c.name) === name) out.push(c);
    findAll(c, name, out, skip);
  }
  return out;
}
export function find(node, name) { return findAll(node, name)[0] ?? null; }
/// The text inside a node, with whitespace collapsed, skipping the elements
/// named in `skip` (figures, tables, formulas, citation markers).
export function textOf(node, skip = new Set()) {
  if (node == null) return '';
  if (typeof node === 'string') return node;
  if (skip.has(local(node.name))) return '';
  return node.children.map(c => textOf(c, skip)).join('');
}
const squash = s => s.replace(/\s+/g, ' ').trim();

// -------------------------------------------------------- MedlinePlus ----

/// HTML (as the web service's FullSummary holds it) as plain text, with
/// paragraphs and list items on their own lines.
export function htmlToText(html) {
  const text = html
    .replace(/<\s*(script|style)[^>]*>[\s\S]*?<\s*\/\s*\1\s*>/gi, '')
    .replace(/<\s*li[^>]*>/gi, '\n- ')
    .replace(/<\s*(br|\/p|\/li|\/ul|\/ol|\/h\d|p|ul|ol|h\d)[^>]*>/gi, '\n')
    .replace(/<[^>]+>/g, '');
  return decodeEntities(text).split('\n').map(l => l.replace(/[ \t ]+/g, ' ').trim()).filter(Boolean).join('\n');
}

/// Candidate passages from a MedlinePlus web service response, before the
/// licence gate: one per health topic, its full summary as text.
export function parseMedlinePlus(xml, { retrieved }) {
  const doc = parseXml(xml);
  const out = [];
  for (const d of findAll(doc, 'document')) {
    // rettype=topic gives the whole health-topic record; the plain search
    // gives highlighted fields. Either way only the summary text is kept.
    const topic = find(d, 'health-topic');
    const field = n => children(d, 'content').find(c => c.attrs.name === n);
    const title = topic ? squash(topic.attrs.title ?? '') : htmlToText(textOf(field('title')));
    const text = htmlToText(textOf(topic ? find(topic, 'full-summary') : field('FullSummary')));
    const organisation = topic ? squash(textOf(find(topic, 'primary-institute'))) : htmlToText(textOf(field('organizationName')));
    out.push({
      source: 'medlineplus-health-topics',
      url: topic?.attrs?.url || d.attrs.url,
      licenceStatement: MEDLINEPLUS_LICENCE,
      licence: MEDLINEPLUS_LICENCE,
      title,
      section: 'Summary',
      text,
      retrieved,
      language: topic?.attrs?.language ?? null,
      organisation: organisation || null,
    });
  }
  return out;
}

// ---------------------------------------------------------------- PMC ----

const SKIP = new Set(['fig', 'table-wrap', 'table', 'disp-formula', 'inline-formula', 'graphic', 'media', 'supplementary-material', 'xref', 'fn', 'label', 'alternatives', 'tex-math', 'math']);
/// Where a section's paragraphs are not looked for: captions, table notes,
/// supplementary material, boxes and reference lists. These often hold
/// material reproduced "with permission" from elsewhere, which the
/// article's own licence does not cover, so they never reach the bank.
const PARA_SKIP = new Set([...SKIP, 'boxed-text', 'fn-group', 'ref-list', 'table-wrap-foot', 'caption']);

/// An article's licence as JATS states it: the ALI licence_ref or the
/// <license> link first, then a Creative Commons URL in its text. Anything
/// the statement says about non-commercial, no-derivatives or share-alike
/// terms wins, so a mixed statement is refused rather than read generously.
export function pmcLicence(article) {
  const permissions = find(find(article, 'article-meta') ?? article, 'permissions');
  const licences = permissions ? findAll(permissions, 'license') : [];
  if (!licences.length) return { licence: null, statement: squash(textOf(find(permissions, 'copyright-statement'))) || null };
  const candidates = [];
  for (const l of licences) {
    for (const ref of findAll(l, 'license_ref')) candidates.push(squash(textOf(ref)));
    if (l.attrs['xlink:href']) candidates.push(l.attrs['xlink:href']);
    for (const link of findAll(l, 'ext-link')) if (link.attrs['xlink:href']) candidates.push(link.attrs['xlink:href']);
    for (const m of textOf(l).matchAll(/https?:\/\/creativecommons\.org\/[^\s"'<>)]+/gi)) candidates.push(m[0]);
  }
  const statement = squash(licences.map(l => { const ps = findAll(l, 'license-p'); return ps.length ? ps.map(p => textOf(p)).join(' ') : textOf(l); }).join(' '));
  const types = licences.map(l => l.attrs['license-type'] ?? '').concat(findAll(permissions, 'license_ref').map(r => r.attrs['content-type'] ?? ''));
  const restricted = /\bby[-_]?(nc|nd|sa)|(nc|nd|sa)license\b/i;
  const restrictive = candidates.find(c => /creativecommons\.org\/licenses\/[a-z-]*-(nc|nd|sa)\b/i.test(c))
    ?? types.find(t => restricted.test(t))
    ?? (/\b(non-?commercial|no-?derivatives|no-?derivs|share-?alike|not (be )?used for commercial)\b/i.test(statement) ? statement : null);
  if (restrictive) return { licence: /not (be )?used for commercial/i.test(restrictive) ? `${restrictive} (NonCommercial)` : restrictive, statement };
  const cc = candidates.find(c => /creativecommons\.org\/(licenses|publicdomain)\//i.test(c));
  return { licence: cc ?? (squash(textOf(licences[0])) || null), statement };
}

function articleMeta(article) {
  const meta = find(article, 'article-meta');
  const id = type => squash(textOf(children(meta, 'article-id').find(a => a.attrs['pub-id-type'] === type)));
  let pmcid = id('pmcid') || id('pmc');
  if (pmcid && !/^PMC/i.test(pmcid)) pmcid = `PMC${pmcid}`;
  const title = squash(textOf(find(find(meta, 'title-group'), 'article-title'), SKIP));
  const journal = squash(textOf(find(find(article, 'journal-meta'), 'journal-title')));
  const authors = findAll(find(meta, 'contrib-group'), 'contrib').filter(c => (c.attrs['contrib-type'] ?? 'author') === 'author').map(c => {
    const n = find(c, 'name');
    if (n) return squash(`${textOf(child(n, 'given-names'))} ${textOf(child(n, 'surname'))}`);
    return squash(textOf(find(c, 'collab'), SKIP));
  }).filter(Boolean);
  const dates = findAll(meta, 'pub-date');
  const year = squash(textOf(find(dates.find(d => /epub|pub/.test(d.attrs['pub-type'] ?? d.attrs['date-type'] ?? 'pub')) ?? dates[0], 'year'))) || null;
  return { pmcid, pmid: id('pmid') || null, doi: id('doi') || null, title, journal, authors, year };
}

/// "A Author, B Author, et al. (2026). Title. Journal. doi:... Licensed
/// under CC BY 4.0 (url)." - the per-item attribution CC BY requires.
export function pmcAttribution(meta, licence, licenceUrl) {
  const who = meta.authors.length > 3 ? `${meta.authors.slice(0, 3).join(', ')}, et al.` : meta.authors.join(', ') || 'Unknown authors';
  const parts = [`${who} (${meta.year ?? 'n.d.'}).`, `${meta.title}.`];
  if (meta.journal) parts.push(`${meta.journal}.`);
  if (meta.doi) parts.push(`doi:${meta.doi}.`);
  parts.push(`${meta.pmcid}.`, `Licensed under ${licence.replace(/-/g, ' ').replace(/^CC BY/, 'CC BY')} (${licenceUrl}).`);
  return parts.join(' ');
}

/// Paragraphs joined into passages of at most `maxChars` (a longer single
/// paragraph stays whole), so one passage is a question's worth of text.
export function chunk(paras, maxChars) {
  const out = [];
  let cur = '';
  for (const p of paras) {
    if (cur && cur.length + 1 + p.length > maxChars) { out.push(cur); cur = ''; }
    cur = cur ? `${cur}\n${p}` : p;
  }
  if (cur) out.push(cur);
  return out;
}

/// Candidate passages from an efetch response (one or more articles), before
/// the licence gate: the abstract, then each top-level body section.
export function parsePmcArticles(xml, { retrieved, maxPassages = 8, maxChars = 4000 } = {}) {
  const doc = parseXml(xml);
  const out = [];
  for (const article of findAll(doc, 'article')) {
    const meta = articleMeta(article);
    const { licence, statement } = pmcLicence(article);
    const url = meta.pmcid ? `${PMC_ARTICLE}${meta.pmcid}/` : null;
    const base = { source: 'pmc-open-access', url, licence, licenceStatement: statement, title: meta.title, retrieved, pmcid: meta.pmcid, pmid: meta.pmid, doi: meta.doi, journal: meta.journal, authors: meta.authors, year: meta.year };
    const sections = [];
    const abstract = children(find(article, 'article-meta'), 'abstract').find(a => !a.attrs['abstract-type']) ?? find(find(article, 'article-meta'), 'abstract');
    if (abstract) sections.push({ section: 'Abstract', node: abstract });
    const body = child(article, 'body');
    for (const sec of children(body, 'sec')) sections.push({ section: squash(textOf(child(sec, 'title'), SKIP)) || 'Section', node: sec });
    if (!sections.length) { out.push({ ...base, meta, section: null, text: '' }); continue; }
    let made = 0;
    for (const { section, node } of sections) {
      const paras = findAll(node, 'p', [], PARA_SKIP).map(p => squash(textOf(p, SKIP))).filter(Boolean);
      for (const text of chunk(paras, maxChars)) {
        if (made++ >= maxPassages) break;
        out.push({ ...base, meta, section, text });
      }
      if (made >= maxPassages) break;
    }
  }
  return out;
}

// --------------------------------------------------------- the gate ------

/// A candidate kept as a bank passage, or refused with its reason.
export function judge(candidate) {
  const where = candidate.url ?? candidate.pmcid ?? candidate.title ?? 'unknown';
  if (!candidate.text || candidate.text.length < 40) return { kept: false, refusal: { source: candidate.source, url: where, title: candidate.title ?? null, reason: 'no usable text' } };
  const verdict = licenceVerdict({ source: candidate.source, licence: candidate.licence, url: candidate.url });
  if (!verdict.ok) {
    const reason = candidate.licence ? verdict.reason : `no licence stated (${candidate.licenceStatement ? `only "${candidate.licenceStatement.slice(0, 120)}"` : 'nothing in its permissions'}), so it is refused`;
    return { kept: false, refusal: { source: candidate.source, url: where, title: candidate.title ?? null, licence: candidate.licence ?? null, reason } };
  }
  const attribution = candidate.source === 'pmc-open-access'
    ? pmcAttribution(candidate.meta, verdict.licence, verdict.licenceUrl)
    : `${candidate.title}. ${verdict.attribution}. ${candidate.url}. Retrieved ${candidate.retrieved}.`;
  const passage = {
    source: candidate.source,
    url: candidate.url,
    licence: verdict.licence,
    licenceUrl: verdict.licenceUrl,
    licenceStatement: candidate.licenceStatement ?? null,
    attribution,
    title: candidate.title,
    section: candidate.section ?? null,
    retrieved: candidate.retrieved,
    text: candidate.text,
  };
  if (candidate.source === 'pmc-open-access') Object.assign(passage, { pmcid: candidate.pmcid, pmid: candidate.pmid, doi: candidate.doi, journal: candidate.journal, authors: candidate.authors, year: candidate.year });
  return { kept: true, passage };
}

// ---------------------------------------------------------- network ------

/// Spaces calls to one host so they never exceed `perSecond`.
export function throttle(perSecond, { now = () => Date.now(), sleep = ms => new Promise(r => setTimeout(r, ms)) } = {}) {
  const gap = Math.ceil(1000 / perSecond) + 10;
  let next = 0;
  return async () => {
    const t = now();
    const wait = Math.max(0, next - t);
    next = Math.max(t, next) + gap;
    if (wait) await sleep(wait);
  };
}

async function politeGet(url, { fetchImpl, wait, tries = 3, sleep }) {
  let last;
  for (let attempt = 1; attempt <= tries; attempt++) {
    await wait();
    try {
      const res = await fetchImpl(url, { headers: { 'User-Agent': USER_AGENT, Accept: 'application/xml, application/json, text/xml' }, signal: AbortSignal.timeout(30_000) });
      if (res.ok) return await res.text();
      last = new Error(`HTTP ${res.status} from ${new URL(url).host}`);
      if (res.status !== 429 && res.status < 500) throw last;
    } catch (e) {
      last = e;
      if (/^HTTP 4/.test(e.message) && !/HTTP 429/.test(e.message)) throw e;
    }
    await sleep(1000 * 2 ** attempt);
  }
  throw last;
}

/// Fetches every topic from every source, sending kept passages to `keep`
/// and refusals to `refuse`. A failed request skips that topic for that
/// source and is logged; it never stops the run or loses what was kept.
export async function run({ topics, sources = ['medlineplus', 'pmc'], medlinePerTopic = 1, pmcPerTopic = 2, maxPassages = 8, retrieved = new Date().toISOString().slice(0, 10), fetchImpl = fetch, apiKey = process.env.NCBI_API_KEY, email = process.env.NCBI_EMAIL, keep, refuse, log = () => {}, sleep = ms => new Promise(r => setTimeout(r, ms)) }) {
  const ncbiWait = throttle(apiKey ? 10 : 3, { sleep });
  // The MedlinePlus web service allows 85 requests a minute per IP.
  const mpWait = throttle(1.2, { sleep });
  const ncbiParams = new URLSearchParams({ tool: TOOL });
  if (email) ncbiParams.set('email', email);
  if (apiKey) ncbiParams.set('api_key', apiKey);
  const counts = { kept: 0, refused: 0, failed: 0 };
  const seen = new Set();
  const handle = c => {
    const key = `${c.url}#${c.section}#${c.text.slice(0, 80)}`;
    if (seen.has(key)) return;
    seen.add(key);
    const j = judge(c);
    if (j.kept) { counts.kept++; keep(j.passage); return; }
    // One refusal line per item and reason, not one per section.
    const once = `refused ${j.refusal.url} ${j.refusal.reason}`;
    if (seen.has(once)) return;
    seen.add(once);
    counts.refused++; refuse(j.refusal); log(`refused ${j.refusal.url}: ${j.refusal.reason}`);
  };
  for (const topic of topics) {
    if (sources.includes('medlineplus')) {
      try {
        const q = new URLSearchParams({ db: 'healthTopics', term: topic, retmax: String(medlinePerTopic), rettype: 'topic' });
        const xml = await politeGet(`${MEDLINEPLUS_SEARCH}?${q}`, { fetchImpl, wait: mpWait, sleep });
        parseMedlinePlus(xml, { retrieved }).forEach(handle);
      } catch (e) { counts.failed++; log(`MedlinePlus "${topic}" failed: ${e.message}`); }
    }
    if (sources.includes('pmc')) {
      try {
        // The OA filter narrows the search; each article's own licence still decides.
        const q = new URLSearchParams({ db: 'pmc', term: `${topic}[Title/Abstract] AND open access[filter]`, retmax: String(pmcPerTopic), retmode: 'json', sort: 'relevance' });
        for (const [k, v] of ncbiParams) q.set(k, v);
        const found = JSON.parse(await politeGet(`${EUTILS}/esearch.fcgi?${q}`, { fetchImpl, wait: ncbiWait, sleep }));
        const ids = found?.esearchresult?.idlist ?? [];
        if (ids.length) {
          const f = new URLSearchParams({ db: 'pmc', id: ids.join(','), retmode: 'xml' });
          for (const [k, v] of ncbiParams) f.set(k, v);
          const xml = await politeGet(`${EUTILS}/efetch.fcgi?${f}`, { fetchImpl, wait: ncbiWait, sleep });
          const articles = parsePmcArticles(xml, { retrieved, maxPassages });
          articles.forEach(handle);
          // An id esearch returned that efetch did not is logged, not silently dropped.
          const got = new Set(articles.map(a => a.pmcid));
          for (const id of ids) if (!got.has(`PMC${id}`)) log(`PMC${id} for "${topic}" came back without an article`);
        }
      } catch (e) { counts.failed++; log(`PMC "${topic}" failed: ${e.message}`); }
    }
  }
  return counts;
}

// -------------------------------------------------------------- CLI ------

export function parseArgs(argv) {
  const args = { sources: ['medlineplus', 'pmc'], pmcPerTopic: 2, medlinePerTopic: 1, maxPassages: 8, topics: [] };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i], v = () => argv[++i];
    if (a === '--out') args.out = v();
    else if (a === '--topics') args.topics.push(...v().split(',').map(s => s.trim()).filter(Boolean));
    else if (a === '--topics-file') args.topics.push(...readFileSync(v(), 'utf8').split('\n').map(s => s.replace(/#.*/, '').trim()).filter(Boolean));
    else if (a === '--sources') args.sources = v().split(',').map(s => s.trim());
    else if (a === '--pmc-per-topic') args.pmcPerTopic = Math.max(0, Math.min(20, Number(v()) || 0));
    else if (a === '--medline-per-topic') args.medlinePerTopic = Math.max(0, Math.min(10, Number(v()) || 0));
    else if (a === '--max-passages') args.maxPassages = Math.max(1, Math.min(40, Number(v()) || 1));
    else throw new Error(`unknown argument ${a}`);
  }
  if (!args.out) throw new Error('--out <path.jsonl> is required');
  if (!args.topics.length) throw new Error('give --topics "a,b" or --topics-file <file>');
  return args;
}

async function main() {
  let args;
  try { args = parseArgs(process.argv.slice(2)); } catch (e) { console.error(e.message); process.exit(2); }
  const out = resolve(args.out);
  const refusedPath = out.replace(/\.jsonl$/, '') + '.refused.jsonl';
  mkdirSync(dirname(out), { recursive: true });
  const kept = createWriteStream(out), refused = createWriteStream(refusedPath);
  const counts = await run({
    topics: args.topics, sources: args.sources, pmcPerTopic: args.pmcPerTopic, medlinePerTopic: args.medlinePerTopic, maxPassages: args.maxPassages,
    keep: p => kept.write(JSON.stringify(p) + '\n'),
    refuse: r => refused.write(JSON.stringify(r) + '\n'),
    log: m => console.error(m),
  });
  await Promise.all([new Promise(r => kept.end(r)), new Promise(r => refused.end(r))]);
  console.log(`kept ${counts.kept} passages -> ${out}\nrefused ${counts.refused} -> ${refusedPath}\nfailed requests ${counts.failed}`);
  process.exit(counts.kept === 0 && counts.failed > 0 ? 1 : 0);
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) main();
