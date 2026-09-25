// The accuracy engine: is this question, card, case or page medically right?
//
// Every item is checked against its own lecture AND the free literature
// (evidence.js: Europe PMC, MedlinePlus, openFDA), by two free checker models
// voting - a third when they disagree - never by the model that wrote it
// alone. Deterministic rule checks (accuracy-rules.js) run alongside, and the
// app's trained accuracy model (accuracy-model.js) turns all of it into one
// P(accurate) and a verdict: Verified, Check this or Flagged.
//
// It costs nothing: items come in batches of up to four (one call per voter
// per batch), the evidence sources are free and cached for a day, every model
// call goes through ai.js's free-share and neuron limits, and a verdict is
// kept by the hash of the item's own content, so an item is never checked
// twice unless it is edited. A batch that finds everything cached spends no
// allowance at all.
//
// Routes (worker.js):
//   POST /accuracy/check      { items: [...], priority?, writer?, exam? }   Pro (or owner)
//     exam: a catalogue id (exams.js); its management questions need more to be Verified
//   POST /accuracy/report     { item, note }                         signed in
//   POST /accuracy/model      -> the accuracy model's current weights (anyone)
//   POST /accuracy/model/set  { weights }                            owner key
//   POST /accuracy/reports    { limit }                              owner key (training)

import { proGate, askModel, spend } from './ai.js';
import { europePMC, medlinePlus, openFDA } from './evidence.js';
import { ruleHits, itemText, sourceMatch, DRUGS } from './accuracy-rules.js';
import { DEFAULT_WEIGHTS, KINDS, features, predict, verdict, validWeights, examWeights } from './accuracy-model.js';
import { exam as examById } from './exams.js';

export const BATCH = 4;
/// Best by the checker bench: Flash-Lite (fast, reliable), gpt-oss-120b and
/// Nemotron on Workers AI, Gemma 4 31B as the slower backup. Not Llama 4
/// Scout (it passed only half the correct answers); not 3.1 Pro (no free tier).
export const DEFAULT_VOTERS = 'gemini:gemini-3.5-flash-lite,workers-ai:@cf/openai/gpt-oss-120b,workers-ai:@cf/nvidia/nemotron-3-120b-a12b,gemini:gemma-4-31b-it';
const MAX_ITEM_CHARS = 3500;
const MAX_SOURCE_CHARS = 1400;
const MAX_EVIDENCE_CHARS = 1500;
const MAX_CALLS = 4;
/// What of an item a voter is shown: four of them, with their lectures and
/// evidence, stay under the 24,000 characters Workers AI takes.
const SHOWN_ITEM_CHARS = 2200;

const json = (body, status = 200) => new Response(JSON.stringify(body), { status, headers: { 'content-type': 'application/json' } });
const fail = (status, message, extra = {}) => json({ error: { message }, message, ...extra }, status);
const now = () => Math.floor(Date.now() / 1000);
const list = text => String(text).split(',').map(s => s.trim()).filter(Boolean);
const str = (v, max) => (typeof v === 'string' ? v.slice(0, max) : '');
const letter = i => String.fromCharCode(65 + i);

/// An item as the app sends it, cleaned: only the fields the engine reads,
/// each kept to a sane length. Null when it cannot be an item.
export function cleanItem(raw) {
  if (!raw || typeof raw !== 'object' || !KINDS.includes(raw.kind)) return null;
  const item = { id: str(raw.id, 80), kind: raw.kind, source: str(raw.source, 20_000) };
  if (raw.kind === 'mcq') {
    if (!Array.isArray(raw.options) || raw.options.length < 2 || raw.options.length > 10) return null;
    item.stem = str(raw.stem, MAX_ITEM_CHARS);
    item.options = raw.options.map(o => str(o, 400));
    item.key = Number.isInteger(raw.key) ? raw.key : -1;
    item.explanation = str(raw.explanation, MAX_ITEM_CHARS);
    if (!item.stem.trim()) return null;
  } else {
    item.text = str(raw.text, MAX_ITEM_CHARS);
    if (!item.text.trim()) return null;
  }
  return item;
}

/// The cache key: the item's own content and the lecture excerpt it is
/// checked against. Computed here, never taken from the app, so no client can
/// file a verdict under somebody else's content.
export async function itemHash(item) {
  const data = new TextEncoder().encode(JSON.stringify(['v1', item.kind, itemText(item), (item.source || '').trim()]));
  const digest = new Uint8Array(await crypto.subtle.digest('SHA-256', data));
  return [...digest.slice(0, 16)].map(b => b.toString(16).padStart(2, '0')).join('');
}

const STOP = new Set(['which', 'following', 'most', 'likely', 'patient', 'year', 'old', 'presents', 'with', 'what', 'the',
  'this', 'that', 'best', 'next', 'step', 'management', 'diagnosis', 'from', 'after', 'about', 'there', 'their', 'shows']);
const DRUG_SUFFIX = /\b[a-z]{3,}(?:olol|pril|sartan|statin|dipine|mab|cillin|mycin|floxacin|azole|prazole|tidine|parin|gliptin|gliflozin|triptan|setron|lukast|olone|asone|tinib|vir)\b/g;

/// What to look up for an item, chosen without a model (a model call per
/// item would spend the free allowance on search terms): the keyed answer or
/// the card's first line, and any drug it names.
export function itemTerms(item) {
  const text = itemText(item).toLowerCase();
  const words = s => s.toLowerCase().replace(/[^a-z0-9 \-]/g, ' ').split(/\s+/).filter(w => w.length > 2 && !STOP.has(w));
  let focus = [];
  if (item.kind === 'mcq' && item.key >= 0 && item.key < item.options.length) {
    const key = words(item.options[item.key]);
    const stemEnd = words(String(item.stem).split(/[.?!]\s/).filter(Boolean).at(-1) || '');
    focus = key.length >= 2 ? [...key.slice(0, 4), ...stemEnd.slice(0, 2)] : [...key, ...stemEnd.slice(0, 4)];
  } else {
    focus = words(String(item.text).split('\n')[0]).slice(0, 5);
  }
  const drugs = new Set();
  for (const d of Object.keys(DRUGS)) if (text.includes(d)) drugs.add(d);
  for (const m of text.matchAll(DRUG_SUFFIX)) drugs.add(m[0]);
  const query = focus.join(' ').trim();
  return { queries: query ? [query.slice(0, 60)] : [], drugs: [...drugs].slice(0, 1) };
}

/// The literature for one item, numbered [S1]... Lookups are shared within a
/// batch (`seen`), and each source answers from a day's cache.
export async function evidenceFor(item, fetcher, seen = new Map()) {
  const t = itemTerms(item);
  const once = (key, run) => { if (!seen.has(key)) seen.set(key, run().catch(() => [])); return seen.get(key); };
  const lookups = [
    ...t.queries.map(q => once(`pmc:${q}`, () => europePMC(q, fetcher))),
    ...t.queries.map(q => once(`mlp:${q}`, () => medlinePlus(q, fetcher))),
    ...t.drugs.map(d => once(`fda:${d}`, () => openFDA(d, fetcher))),
  ];
  const found = (await Promise.all(lookups)).flat();
  const urls = new Set();
  const out = [];
  let used = 0;
  for (const e of found) {
    if (urls.has(e.url)) continue;
    urls.add(e.url);
    const text = e.text.slice(0, 600);
    if (used + text.length > MAX_EVIDENCE_CHARS) break;
    used += text.length;
    out.push({ ...e, text, id: `S${out.length + 1}` });
  }
  return out;
}

const KIND_NAMES = { mcq: 'multiple-choice question', card: 'flashcard', case: 'clinical case', osce: 'OSCE station checklist',
  page: 'textbook page', fact: 'key facts from a narrated lecture', note: "a student's own note" };

/// The one prompt a voter answers for a whole batch.
export function votePrompt(entries) {
  const system = [
    'You are a strict medical accuracy checker for study material used by medical students.',
    'For each item, decide whether every medical fact in it is correct by CURRENT evidence and consensus - not only whether it matches its source lecture.',
    'The lecture itself can be wrong or out of date: if the item agrees with the lecture but contradicts the REFERENCE EVIDENCE or well-established current consensus, it is wrong.',
    'For a multiple-choice question: first work out the single best answer yourself and give its letter as "answer"; then judge the keyed answer and the explanation.',
    'Risk levels: 1 = no error, 2 = minor wording issue that would not mislead, 3 = an error that could mislead a student, 4 = a clearly wrong fact, dose, key or criterion.',
    '"evidence": "supports" when the reference evidence backs the item\'s main claims, "contradicts" when any of it contradicts the item, "none" when it does not cover the item.',
    '"cites": the [Sn] ids you relied on. "issues": short sentences naming each error (empty when none).',
    '"fix": only when you are confident - {"field":"key","value":"C"} for a wrong key, {"field":"explanation"|"answer"|"text","value":"corrected wording"} otherwise; null when nothing needs fixing.',
    'Do not invent sources. Reply with JSON only, exactly: {"items":[{"i":1,"answer":"B","risk":1,"evidence":"supports","cites":["S1"],"issues":[],"fix":null}]}',
  ].join('\n');
  const blocks = entries.map((e, n) => {
    const src = (e.item.source || '').trim();
    const ev = e.evidence.map(s => `[${s.id}] ${s.source}: ${s.title}\n${s.text}`).join('\n');
    return [
      `### Item ${n + 1} (${KIND_NAMES[e.item.kind]})`,
      itemText(e.item).slice(0, SHOWN_ITEM_CHARS),
      `SOURCE LECTURE: ${src ? src.slice(0, MAX_SOURCE_CHARS) : '(none - judge against current medical teaching)'}`,
      `REFERENCE EVIDENCE:\n${ev || '(none found)'}`,
    ].join('\n');
  });
  return [{ role: 'system', content: system }, { role: 'user', content: blocks.join('\n\n') }];
}

/// One voter's reply, item by item: [{ risk, answer, evidence, cites, issues, fix } | null].
export function parseVotes(reply, count) {
  const text = String(reply || '');
  let data = null;
  try { data = JSON.parse(text.slice(text.indexOf('{'), text.lastIndexOf('}') + 1)); } catch { data = null; }
  const rows = Array.isArray(data?.items) ? data.items : Array.isArray(data) ? data : [];
  const out = new Array(count).fill(null);
  rows.forEach((r, n) => {
    const i = Number.isInteger(r?.i) ? r.i - 1 : n;
    if (i < 0 || i >= count) return;
    const risk = Number(r?.risk);
    if (!Number.isFinite(risk)) return;
    const answer = typeof r.answer === 'string' && /^[A-J]$/i.test(r.answer.trim()) ? r.answer.trim().toUpperCase() : null;
    const evidence = ['supports', 'contradicts', 'none'].includes(r.evidence) ? r.evidence : 'none';
    const fix = r.fix && typeof r.fix === 'object' && ['key', 'explanation', 'answer', 'text'].includes(r.fix.field)
      && typeof r.fix.value === 'string' && r.fix.value.trim() ? { field: r.fix.field, value: r.fix.value.trim().slice(0, 1500) } : null;
    out[i] = {
      risk: Math.min(4, Math.max(1, Math.round(risk))), answer, evidence,
      cites: (Array.isArray(r.cites) ? r.cites : []).filter(c => /^S\d{1,2}$/.test(String(c))).slice(0, 6),
      issues: (Array.isArray(r.issues) ? r.issues : []).map(s => String(s).slice(0, 300)).filter(Boolean).slice(0, 5),
      fix,
    };
  });
  return out;
}

/// Whether two voters disagree about any item (pass against flag, or a
/// different answer to a question): the moment to ask a third.
export function disagree(a, b) {
  return a.some((x, i) => {
    const y = b[i];
    if (!x || !y) return false;
    return (x.risk >= 3) !== (y.risk >= 3) || (x.answer && y.answer && x.answer !== y.answer);
  });
}

/// Which voters may judge: the configured order, minus the model that wrote
/// the items (a model grading its own work agrees with itself).
export function votersFor(env, writer) {
  const all = list(env.ACCURACY_VOTERS || DEFAULT_VOTERS);
  const w = String(writer || '').toLowerCase().trim();
  if (!w) return all;
  return all.filter(v => { const model = v.slice(v.indexOf(':') + 1).toLowerCase(); return model !== w && !model.endsWith(`/${w}`); });
}

// MARK: the accuracy model's weights

let weightsCache = { value: null, until: 0 };
export async function currentWeights(env) {
  if (weightsCache.value && weightsCache.until > Date.now()) return weightsCache.value;
  let value = DEFAULT_WEIGHTS;
  try {
    const row = await env.DB.prepare('SELECT body FROM accuracy_model ORDER BY created_at DESC LIMIT 1').first();
    const parsed = row ? JSON.parse(row.body) : null;
    if (validWeights(parsed)) value = parsed;
  } catch { /* no table yet: the bundled prior */ }
  weightsCache = { value, until: Date.now() + 10 * 60_000 };
  return value;
}
export function forgetWeights() { weightsCache = { value: null, until: 0 }; }

/// What the app is told about one item: the verdict, P(accurate), why, and
/// the raw features (so the phone can re-score it when the weights change).
export function describe(item, hash, signals, weights, strictness = 0) {
  const rules = ruleHits(item);
  const votes = signals?.votes || [];
  const keyLetter = item.kind === 'mcq' && item.key >= 0 ? letter(item.key) : null;
  const f = features({ kind: item.kind, rules, votes, evidenceCount: (signals?.evidence || []).length,
                       sourceMatch: signals ? signals.sourceMatch : sourceMatch(item, item.source), keyLetter });
  const p = predict(f, weights);
  return {
    id: item.id, hash, p: Math.round(p * 1000) / 1000, verdict: verdict(p, f, examWeights(weights, item, strictness)), modelVersion: weights.version,
    features: f, rules, votes, evidence: signals?.evidence || [], fix: suggestedFix(item, votes),
  };
}

/// The correction to offer: a key the voters agree on over the keyed one,
/// or the first fix a flagging voter wrote.
export function suggestedFix(item, votes) {
  const read = votes.filter(Boolean);
  if (item.kind === 'mcq') {
    const keyed = item.key >= 0 ? letter(item.key) : null;
    const answers = read.map(v => v.answer).filter(Boolean);
    const other = answers.filter(a => a !== keyed);
    if (answers.length >= 2 && other.length === answers.length && other.every(a => a === other[0])
        && other[0].charCodeAt(0) - 65 < item.options.length) {
      return { field: 'key', value: other[0], by: read.filter(v => v.answer === other[0]).map(v => v.model) };
    }
  }
  const flagging = read.find(v => v.risk >= 3 && v.fix);
  return flagging ? { ...flagging.fix, by: [flagging.model] } : null;
}

// MARK: routes

/// POST /accuracy/check
export async function checkBatch(env, account, body, fetcher = fetch, { owner = false, bench = false } = {}) {
  if (!owner) {
    const refused = await proGate(env, account, fetcher, 'The accuracy check is part of Pro.');
    if (refused) return refused;
  }
  const raw = Array.isArray(body?.items) ? body.items : [];
  if (!raw.length || raw.length > BATCH) return fail(400, `Send 1 to ${BATCH} items.`);
  const items = raw.map(cleanItem);
  if (items.some(i => !i)) return fail(400, 'An item could not be read.');
  // the source is cut to the part the checker is shown, so the hash is of
  // what was actually checked
  for (const item of items) item.source = (item.source || '').trim().slice(0, MAX_SOURCE_CHARS);
  const weights = await currentWeights(env);
  const strict = examById(body?.exam)?.strict || 0;
  const hashes = await Promise.all(items.map(itemHash));

  const cached = await Promise.all(hashes.map(h => readVerdict(env, h)));
  const todo = items.map((_, i) => i).filter(i => !cached[i]);
  const results = items.map((item, i) => (cached[i] ? { ...describe(item, hashes[i], cached[i], weights, strict), cached: true } : null));
  if (!todo.length) return json({ items: results });

  // the day's allowance, per batch: background checks have a smaller share of
  // their own, so a library being checked never leaves the student without
  // the checks they ask for
  const who = bench ? 'owner-bench' : owner ? 'owner' : account;
  const limit = bench ? Number(env.OWNER_BENCH_DAILY_LIMIT) || 2500 : owner ? Number(env.OWNER_DAILY_LIMIT) || 3000
    : Number(env.ACCURACY_DAILY_BATCHES) || 40;
  const background = body.priority === 'background';
  const unchecked = reason => items.map((item, i) => results[i] || { ...describe(item, hashes[i], null, weights, strict), reason });
  if (background && !owner && !await spend(env, `accuracy-bg:${account}`, Number(env.ACCURACY_BACKGROUND_BATCHES) || 20)) {
    return json({ items: unchecked('day'), limit: 'day' }, 429);
  }
  if (!await spend(env, `accuracy:${who}`, limit) || !await spend(env, 'accuracy:all', Number(env.ACCURACY_DAILY_CEILING) || 3000)) {
    return json({ items: unchecked('day'), limit: 'day' }, 429);
  }

  const seen = new Map();
  const entries = await Promise.all(todo.map(async i => ({ i, item: items[i], evidence: await evidenceFor(items[i], fetcher, seen) })));
  const messages = votePrompt(entries);
  const ballots = [];
  const failures = [];
  let wanted = 2, calls = 0;
  for (const use of votersFor(env, body.writer)) {
    if (ballots.length >= wanted || calls >= MAX_CALLS) break;
    calls++;
    // room for a reasoning model to think before it answers every item
    const r = await askModel(env, account, owner, use, messages, 500 * entries.length + 600, fetcher);
    if (!r.ok) { failures.push(`${use}: ${r.status}`); continue; }
    const parsed = parseVotes(r.content, entries.length);
    if (!parsed.some(Boolean)) { failures.push(`${use}: unreadable`); continue; }
    ballots.push({ model: use.slice(use.indexOf(':') + 1), parsed });
    if (ballots.length === 2 && disagree(ballots[0].parsed, ballots[1].parsed)) wanted = 3;
  }

  for (const [n, e] of entries.entries()) {
    const votes = ballots.map(b => (b.parsed[n] ? { model: b.model, ...b.parsed[n] } : null)).filter(Boolean);
    const signals = {
      votes, sourceMatch: sourceMatch(e.item, e.item.source),
      evidence: e.evidence.map(({ id, source, title, url }) => ({ id, source, title, url })),
    };
    if (votes.length) await writeVerdict(env, hashes[e.i], signals);
    results[e.i] = { ...describe(e.item, hashes[e.i], votes.length ? signals : null, weights, strict),
                     ...(votes.length ? {} : { reason: 'busy' }) };
  }
  if (!ballots.length) console.error('accuracy: no voter answered', failures.join(' | '));
  return json({ items: results, ...(owner && failures.length ? { failures } : {}) });
}

async function readVerdict(env, hash) {
  try {
    const row = await env.DB.prepare('SELECT signals, created_at FROM accuracy_verdicts WHERE hash = ?').bind(hash).first();
    if (!row) return null;
    const days = Number(env.ACCURACY_CACHE_DAYS) || 365;
    if (row.created_at < now() - days * 86_400) return null;
    return JSON.parse(row.signals);
  } catch { return null; }
}

async function writeVerdict(env, hash, signals) {
  try {
    await env.DB.prepare('INSERT OR REPLACE INTO accuracy_verdicts (hash, signals, created_at) VALUES (?, ?, ?)')
      .bind(hash, JSON.stringify(signals), now()).run();
  } catch (error) { console.error('accuracy cache', error); }
}

/// POST /accuracy/report: a student says this item is wrong. Kept per item
/// hash and account (one report each), with their note, for the next
/// training run; costs nothing, so any signed-in account may report.
export async function report(env, account, body) {
  const item = cleanItem(body?.item);
  if (!item) return fail(400, 'That item could not be read.');
  item.source = (item.source || '').trim().slice(0, MAX_SOURCE_CHARS);
  if (!await spend(env, `accuracy-report:${account}`, Number(env.ACCURACY_REPORTS_DAILY) || 60)) {
    return fail(429, "That's today's reports sent. Thank you - try again tomorrow.", { limit: 'day' });
  }
  const hash = await itemHash(item);
  const note = str(body?.note, 1000);
  await env.DB.prepare(
    'INSERT OR REPLACE INTO accuracy_reports (hash, account_id, kind, item, note, created_at) VALUES (?, ?, ?, ?, ?, ?)')
    .bind(hash, account, item.kind, JSON.stringify(item), note, now()).run();
  const count = (await env.DB.prepare('SELECT COUNT(*) AS n FROM accuracy_reports WHERE hash = ?').bind(hash).first())?.n || 1;
  return json({ ok: true, hash, reports: count });
}

/// POST /accuracy/model: the weights the app should score with.
export async function modelWeights(env) {
  return json({ weights: await currentWeights(env) });
}

/// POST /accuracy/model/set (owner key): the training run's new weights.
export async function setWeights(env, body) {
  const w = body?.weights;
  if (!validWeights(w)) return fail(400, 'Those weights are not in the accuracy model\'s shape.');
  await env.DB.prepare('INSERT OR REPLACE INTO accuracy_model (version, body, created_at) VALUES (?, ?, ?)')
    .bind(w.version, JSON.stringify(w), now()).run();
  forgetWeights();
  return json({ ok: true, version: w.version });
}

/// POST /accuracy/reports (owner key): the reported items, most-reported
/// first, for training. Items only - never who reported them.
export async function listReports(env, body) {
  const limit = Math.min(Math.max(Number(body?.limit) || 200, 1), 1000);
  const rows = (await env.DB.prepare(
    `SELECT hash, MIN(item) AS item, COUNT(*) AS reports, MAX(created_at) AS last
     FROM accuracy_reports GROUP BY hash ORDER BY reports DESC, last DESC LIMIT ?`).bind(limit).all()).results || [];
  return json({ reports: rows.map(r => ({ hash: r.hash, reports: r.reports, item: JSON.parse(r.item) })) });
}
