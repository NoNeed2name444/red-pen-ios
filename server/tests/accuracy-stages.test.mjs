// The accuracy check as named stages (accuracy.js, plan Task 5d step 1).
//
// The stages run in a fixed order; a stage that runs out of time or fails
// gives its safe result (an unanswered vote is no vote, an evidence timeout
// is no evidence, a cache failure never blocks a verdict); and on a set of
// fixed inputs the staged check gives exactly what the check gave before it
// was split into stages - kept below, as it was at 52514d3, as the reference.
//
// Run: node server/tests/accuracy-stages.test.mjs

import { DatabaseSync } from 'node:sqlite';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import {
  checkBatch, STAGES, BUDGETS, budgetsFor, within, rulesStage, claimsStage, lookupStage, evidenceStage, votesStage, jevStage, cacheStage,
  BATCH, cleanItem, itemHash, currentWeights, forgetWeights, evidenceFor, votePrompt, parseVotes, disagree, votersFor, suggestedFix, staleSignals } from '../accuracy.js';
import { proGate, askModel, spend } from '../ai.js';
import { resetBreakers } from '../breakers.js';
import { jevOath, oathWithJev, TIMEOUT_MS as JEV_TIMEOUT_MS } from '../jev.js';
import { ruleHits, itemText, sourceMatch } from '../accuracy-rules.js';
import { features, predict, verdict, examWeights, isOath, oathClaims, familyOf } from '../accuracy-model.js';
import { exam as examById } from '../exams.js';

const here = dirname(fileURLToPath(import.meta.url));
let failures = 0;
const ok = (cond, what) => { console.log((cond ? 'ok   ' : 'FAIL ') + what); if (!cond) failures++; };
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));

// MARK: the reference - checkBatch as it was before the stages (52514d3),
// word for word but for its private helpers, which are copied beside it.

const MAX_SOURCE_CHARS = 1400;
const MAX_CALLS = 4;
const json = (body, status = 200) => new Response(JSON.stringify(body), { status, headers: { 'content-type': 'application/json' } });
const fail = (status, message, extra = {}) => json({ error: { message }, message, ...extra }, status);
const now = () => Math.floor(Date.now() / 1000);
const letter = i => String.fromCharCode(65 + i);

function oldDescribe(item, hash, signals, weights, strictness = 0) {
  const rules = ruleHits(item);
  const votes = signals?.votes || [];
  const keyLetter = item.kind === 'mcq' && item.key >= 0 ? letter(item.key) : null;
  const f = features({ kind: item.kind, rules, votes, evidenceCount: (signals?.evidence || []).length,
                       sourceMatch: signals ? signals.sourceMatch : sourceMatch(item, item.source), keyLetter });
  const p = predict(f, weights);
  // the oath check: a dose, a diagnosis or a treatment needs evidence behind
  // it; Jev's yes (jev.js, recorded with the votes) can only add one
  const text = itemText(item);
  const oath = oathWithJev(isOath(text), signals?.jevOath);
  return {
    id: item.id, hash, p: Math.round(p * 1000) / 1000, verdict: verdict(p, f, examWeights(weights, item, strictness), oath), modelVersion: weights.version,
    features: f, rules, votes, evidence: signals?.evidence || [], fix: suggestedFix(item, votes),
    ...(oath ? { oath: oathClaims(text) } : {}),
  };
}

async function oldCheckBatch(env, account, body, fetcher = fetch, { owner = false, bench = false } = {}) {
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

  const cached = await Promise.all(hashes.map(h => oldReadVerdict(env, h)));
  const todo = items.map((_, i) => i).filter(i => !cached[i]);
  const results = items.map((item, i) => (cached[i] ? { ...oldDescribe(item, hashes[i], cached[i], weights, strict), cached: true } : null));
  if (!todo.length) return json({ items: results });

  // the day's allowance, per batch: background checks have a smaller share of
  // their own, so a library being checked never leaves the student without
  // the checks they ask for
  const who = bench ? 'owner-bench' : owner ? 'owner' : account;
  const limit = bench ? Number(env.OWNER_BENCH_DAILY_LIMIT) || 2500 : owner ? Number(env.OWNER_DAILY_LIMIT) || 3000
    : Number(env.ACCURACY_DAILY_BATCHES) || 40;
  const background = body.priority === 'background';
  const unchecked = reason => items.map((item, i) => results[i] || { ...oldDescribe(item, hashes[i], null, weights, strict), reason });
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
    // Jev, where paid calls are on: asked only about items the patterns did not hold
    if (votes.length && !isOath(itemText(e.item))) {
      const jevP = await jevOath(env, itemText(e.item), fetcher);
      if (jevP !== null) signals.jevOath = Math.round(jevP * 1000) / 1000;
    }
    if (votes.length) await oldWriteVerdict(env, hashes[e.i], signals);
    results[e.i] = { ...oldDescribe(e.item, hashes[e.i], votes.length ? signals : null, weights, strict),
                     ...(votes.length ? {} : { reason: 'busy' }) };
  }
  if (!ballots.length) console.error('accuracy: no voter answered', failures.join(' | '));
  return json({ items: results, ...(owner && failures.length ? { failures } : {}) });
}

async function oldReadVerdict(env, hash) {
  try {
    const row = await env.DB.prepare('SELECT signals, created_at FROM accuracy_verdicts WHERE hash = ?').bind(hash).first();
    if (!row) return null;
    const days = Number(env.ACCURACY_CACHE_DAYS) || 365;
    if (row.created_at < now() - days * 86_400) return null;
    return JSON.parse(row.signals);
  } catch { return null; }
}

async function oldWriteVerdict(env, hash, signals) {
  try {
    await env.DB.prepare('INSERT OR REPLACE INTO accuracy_verdicts (hash, signals, created_at) VALUES (?, ?, ?)')
      .bind(hash, JSON.stringify(signals), now()).run();
  } catch (error) { console.error('accuracy cache', error); }
}

// MARK: a world to check in - a real SQLite, and every outside service faked
// deterministically: the checker models, the literature and Jev.

/// D1 over node:sqlite. `trouble(sql, kind)` may return 'hang' (never
/// answers) or 'throw' for a statement, to stand for a database that stops
/// answering or fails.
function d1(db, trouble = () => null) {
  return {
    prepare(sql) {
      const stmt = db.prepare(sql);
      let args = [];
      const act = (kind, run) => {
        const t = trouble(sql, kind);
        if (t === 'hang') return new Promise(() => {});
        if (t === 'throw') return Promise.reject(new Error('D1 is unavailable'));
        return run();
      };
      const api = {
        bind(...a) { args = a; return api; },
        first() { return act('first', () => stmt.get(...args) ?? null); },
        all() { return act('all', () => ({ results: stmt.all(...args) })); },
        run() { return act('run', () => { const r = stmt.run(...args); return { meta: { changes: Number(r.changes) } }; }); },
      };
      return api;
    },
  };
}

const PASS = { risk: 1, answer: 'B', evidence: 'supports', cites: ['S1'], issues: [], fix: null };

/// One voter's verdict on one item of the prompt, by what the item says:
/// the tests write their intent into the items' text.
function voteOn(model, block) {
  if (block.includes('MUTE') && model.includes('flash-lite')) return null;
  if (block.includes('KEYWRONG')) return { risk: 1, answer: 'A', evidence: 'none', cites: [], issues: [], fix: null };
  if (block.includes('WRONG')) return { risk: 4, answer: 'A', evidence: 'contradicts', cites: [], issues: ['That is wrong.'], fix: { field: 'text', value: 'Corrected.' } };
  if (block.includes('SPLIT')) {
    return model.includes('gpt-oss') ? { risk: 4, answer: 'A', evidence: 'contradicts', cites: [], issues: ['The key is wrong.'], fix: { field: 'key', value: 'A' } } : PASS;
  }
  if (block.includes('NOEVIDENCE')) return { ...PASS, evidence: 'none', cites: [] };
  return PASS;
}

/// What a model sends back for a whole prompt: one row per item.
function replyTo(model, prompt) {
  const blocks = prompt.split('### Item ').slice(1);
  const rows = blocks.map((block, n) => { const v = voteOn(model, block); return v ? { i: n + 1, ...v } : null; }).filter(Boolean);
  return JSON.stringify({ items: rows });
}

/// A world: env, fetcher, a log of every outside call, and `release()` to
/// answer the calls told to hang (so nothing is left waiting at the end).
/// plan: { down, garbage, hang: Sets of model names; evidence: 'hang';
///         jev: 'hang'; db: trouble(sql, kind) }
function world(extra = {}, plan = {}) {
  // every breaker closed: a world starts with no provider remembered as failing
  resetBreakers();
  const db = new DatabaseSync(':memory:');
  const sql = readFileSync(join(here, '..', 'schema.sql'), 'utf8').split('\n').map(l => l.replace(/--.*$/, '')).join('\n');
  for (const statement of sql.split(';')) if (statement.trim()) db.exec(statement);
  db.prepare(`INSERT INTO accounts (id, provider, subject, created_at) VALUES ('a1', 'apple', 's1', 0)`).run();
  db.prepare(`INSERT INTO accounts (id, provider, subject, created_at) VALUES ('a2', 'apple', 's2', 0)`).run();
  const log = [];
  const prompts = [];
  const waiting = [];
  const hang = (fallback) => new Promise(resolve => waiting.push(() => resolve(fallback())));
  const down = plan.down || new Set(), garbage = plan.garbage || new Set(), hung = plan.hang || new Set();
  const answer = (model, prompt) => (garbage.has(model) ? 'nothing' : replyTo(model, prompt));
  const fetcher = async (url, init = {}) => {
    if (url.includes('firebasevertexai')) {
      const model = url.split('/models/')[1].split(':')[0];
      log.push(`gemini:${model}`);
      const prompt = String(init.body || '');
      prompts.push(prompt);
      const respond = () => (down.has(model) ? new Response('{"error":{"message":"overloaded"}}', { status: 503 })
        : new Response(JSON.stringify({ candidates: [{ content: { parts: [{ text: answer(model, prompt) }] } }] }), { status: 200 }));
      return hung.has(model) ? hang(respond) : respond();
    }
    if (url.includes('europepmc')) {
      const q = new URL(url).searchParams.get('query').split(')')[0].slice(1);
      log.push(`pmc:${q}`);
      const respond = () => new Response(JSON.stringify({ resultList: { result: [{
        title: `A review of ${q}`, journalInfo: { journal: { isoabbreviation: 'J Med' } }, pubYear: '2024',
        doi: `10.1/${q.replace(/\W+/g, '-')}`, abstractText: `What reviews say about ${q}: it is current practice.`,
      }] } }), { status: 200 });
      return plan.evidence === 'hang' ? hang(respond) : respond();
    }
    if (url.includes('wsearch.nlm')) {
      const q = new URL(url).searchParams.get('term');
      log.push(`medlineplus:${q}`);
      const respond = () => new Response(`<nlmSearchResult><document url="https://medlineplus.gov/${q.replace(/\W+/g, '')}.html"><content name="title">${q}</content><content name="FullSummary">MedlinePlus on ${q}.</content></document></nlmSearchResult>`, { status: 200 });
      return plan.evidence === 'hang' ? hang(respond) : respond();
    }
    if (url.includes('api.fda.gov')) {
      const drug = decodeURIComponent(url.split('generic_name:%22')[1].split('%22')[0]);
      log.push(`openfda:${drug}`);
      const respond = () => new Response(JSON.stringify({ results: [{ set_id: `set-${drug}`, effective_time: '20250101',
        indications_and_usage: [`${drug} is indicated for infections.`], dosage_and_administration: ['500 mg every 8 hours.'] }] }), { status: 200 });
      return plan.evidence === 'hang' ? hang(respond) : respond();
    }
    if (url.includes('typesafe')) {
      const state = JSON.parse(init.body).state;
      log.push('jev');
      const respond = () => new Response(JSON.stringify({ model: 'jev-1', answers: { oath: { type: 'noul', noul: state.includes('Start') ? 0.95 : 0.1 } } }), { status: 200 });
      return plan.jev === 'hang' ? hang(respond) : respond();
    }
    log.push(`other:${url.split('?')[0]}`);
    return new Response('{}', { status: 404 });
  };
  const AI = {
    run: async (model, input) => {
      log.push(`workers:${model}`);
      const prompt = JSON.stringify(input.messages);
      prompts.push(prompt);
      const respond = () => {
        if (down.has(model)) throw new Error('Workers AI is down');
        return { choices: [{ message: { content: answer(model, prompt) } }], usage: { prompt_tokens: 10, completion_tokens: 10 } };
      };
      return hung.has(model) ? hang(respond) : respond();
    },
  };
  const env = { DB: d1(db, plan.db), db, FIREBASE_API_KEY: 'k', FIREBASE_PROJECT_ID: 'p', APPLE_BUNDLE_ID: 'x', AI, OWNER_ACCOUNT_IDS: 'a1', ...extra };
  const release = () => { for (const go of waiting.splice(0)) go(); };
  return { env, db, fetcher, log, prompts, release };
}

const dump = db => ({
  verdicts: db.prepare('SELECT hash, signals FROM accuracy_verdicts ORDER BY hash').all().map(r => ({ ...r })),
  usage: db.prepare('SELECT account_id, day, requests FROM ai_usage ORDER BY account_id, day').all().map(r => ({ ...r })),
});

// the items: what each one is for is written into its text
const Q1 = { id: 'q1', kind: 'mcq', stem: 'A patient on warfarin bleeds. Best immediate reversal?', options: ['Vitamin K', 'Prothrombin complex concentrate'], key: 1,
  explanation: 'PCC works fastest.', source: 'PCC reverses warfarin within minutes.' };
const C1 = { id: 'c1', kind: 'card', text: 'Q: Antidote to warfarin?\nA: Vitamin K', source: '' };
const DOSE = { id: 'd1', kind: 'card', text: 'Q: Dose of amoxicillin for otitis media?\nA: 500 mg PO three times a day', source: 'Amoxicillin is first-line for acute otitis media.' };
const MGMT = { id: 'm1', kind: 'mcq', stem: 'A 54-year-old has crushing chest pain with ST elevation. What is the most appropriate next step in management?',
  options: ['Aspirin and primary PCI', 'Discharge home'], key: 0, explanation: 'Primary PCI is the treatment of choice for STEMI.', source: '' };
const TREAT = { id: 't1', kind: 'card', text: 'Start ceftriaxone for suspected bacterial meningitis. NOEVIDENCE', source: '' };
const WRONG = { id: 'w1', kind: 'card', text: 'Q: Antidote to heparin?\nA: Vitamin K WRONG', source: 'Protamine reverses heparin.' };
const SPLIT = { id: 's1', kind: 'mcq', stem: 'Drug of choice for absence seizures? SPLIT', options: ['Ethosuximide', 'Phenytoin'], key: 1, explanation: 'Phenytoin.', source: '' };
const SEVERE = { id: 'p1', kind: 'card', text: 'Give paracetamol 10 g orally for fever.', source: '' };
const MUTE = { id: 'u1', kind: 'case', text: 'A 30-year-old with fever and neck stiffness. MUTE', source: 'Meningitis presents with fever and neck stiffness.' };
const NOTE = { id: 'n1', kind: 'note', text: 'Metformin is first-line in type 2 diabetes. NOEVIDENCE', source: '' };
const card = t => ({ kind: 'card', text: `Q: ${t}\nA: y` });
const CARDSPLIT = { id: 'cs1', kind: 'card', text: 'Q: Drug of choice for absence seizures? SPLIT\nA: Phenytoin', source: '' };
// both checkers, solving blind, reach A; the key says B
const KEYWRONG = { id: 'k1', kind: 'mcq', stem: 'First-line drug for absence seizures? KEYWRONG', options: ['Ethosuximide', 'Phenytoin', 'Carbamazepine'], key: 1, explanation: '', source: '' };
const EXPLAINED = { id: 'e1', kind: 'mcq', stem: 'A patient on warfarin bleeds. Best immediate reversal?', options: ['Vitamin K', 'Prothrombin complex concentrate'], key: 1,
  explanation: 'Prothrombin complex concentrate reverses warfarin within minutes; vitamin K takes hours.', source: '' };

/// One way of checking (old or staged), run through a list of calls in a
/// fresh world: every reply, every outside call, and the database after.
async function play(check, extra, plan, calls) {
  forgetWeights();
  const w = world(extra, plan);
  const replies = [];
  for (const c of calls) {
    const r = await check(w.env, c.account ?? 'owner', structuredClone(c.body), w.fetcher, c.opts ?? { owner: true });
    replies.push({ status: r.status, body: await r.text() });
  }
  w.release();
  return { replies, log: w.log, db: dump(w.db) };
}

/// The first place two runs differ, for the failure message.
function firstDifference(a, b, path = '') {
  if (JSON.stringify(a) === JSON.stringify(b)) return null;
  if (a && b && typeof a === 'object' && typeof b === 'object') {
    for (const k of new Set([...Object.keys(a), ...Object.keys(b)])) {
      const d = firstDifference(a[k], b[k], `${path}.${k}`);
      if (d) return d;
    }
    return `${path}: key order`;
  }
  return `${path}: ${JSON.stringify(a)?.slice(0, 300)} | ${JSON.stringify(b)?.slice(0, 300)}`;
}

// MARK: the same answers as before the stages, on fixed inputs
{
  const jevOn = { JEV_API_KEY: 'k', PRO_PAYS: 'on' };
  const scenarios = [
    ['refusals: not Pro, too many items, an unreadable item, none', {}, {}, [
      { account: 'a2', body: { items: [Q1] }, opts: {} },
      { body: { items: [Q1, C1, DOSE, MGMT, NOTE] } },
      { body: { items: [Q1, { kind: 'nope', text: 'x' }] } },
      { body: { items: [] } },
      { body: null },
    ]],
    ['a fresh batch, then the same from the cache, then one item edited', {}, {}, [
      { body: { items: [C1, DOSE, NOTE, TREAT] } },
      { body: { items: [C1, DOSE, NOTE, TREAT] } },
      { body: { items: [NOTE, { ...C1, text: `${C1.text} (edited)` }] } },
    ]],
    ['the writer never votes; a split asks a third voter', {}, {}, [
      { body: { items: [CARDSPLIT], writer: 'gemini-3.5-flash-lite' } },
      { body: { items: [{ ...CARDSPLIT, text: `${CARDSPLIT.text} Again.` }] } },
      { body: { items: [WRONG, C1] } },
    ]],
    ['voters down or unreadable: failures for the owner, unchecked when nobody answers', {}, {
      down: new Set(['gemini-3.5-flash-lite']), garbage: new Set(['@cf/openai/gpt-oss-120b']) }, [
      { body: { items: [C1, SEVERE] } },
      { body: { items: [C1] } },
    ]],
    ['nobody answers: busy, nothing kept, asked again next time', {}, {
      garbage: new Set(['gemini-3.5-flash-lite', '@cf/openai/gpt-oss-120b', '@cf/nvidia/nemotron-3-120b-a12b', 'gemma-4-31b-it']) }, [
      { body: { items: [card('fresh'), SEVERE] } },
      { body: { items: [card('fresh')] } },
    ]],
    ['a voter that skips an item, and the same item twice in a batch', {}, {}, [
      { body: { items: [MUTE, C1] } },
      { body: { items: [NOTE, NOTE, DOSE] } },
    ]],
    ['Jev on: asked only about what the patterns did not hold', jevOn, {}, [
      { body: { items: [TREAT, DOSE, C1, NOTE] } },
      { body: { items: [TREAT, NOTE] } },
    ]],
    ['a Pro account: background share, the day\'s batches, cached items free', { ACCURACY_BACKGROUND_BATCHES: '1', ACCURACY_DAILY_BATCHES: '3' }, {}, [
      { account: 'a1', body: { items: [card('a')], priority: 'background' }, opts: {} },
      { account: 'a1', body: { items: [card('b'), card('a')], priority: 'background' }, opts: {} },
      { account: 'a1', body: { items: [card('c')] }, opts: {} },
      { account: 'a1', body: { items: [card('d')] }, opts: {} },
      { account: 'a1', body: { items: [card('e'), card('a')] }, opts: {} },
      { account: 'a1', body: { items: [card('a')] }, opts: {} },
    ]],
    ['the owner\'s bench and the global ceiling', { ACCURACY_DAILY_CEILING: '2' }, {}, [
      { body: { items: [card('one')] }, opts: { owner: true, bench: true } },
      { body: { items: [card('two')] }, opts: { owner: true } },
      { body: { items: [card('three'), card('one')] }, opts: { owner: true } },
    ]],
  ];
  // The old implementation is the reference for everything the staged one
  // did not change on purpose. Intended since then, and set aside here:
  // the families count beside the features, the blind voter's marker and its
  // withheld fix, the "busy" reply when nobody answered, the allowance that
  // reply gives back, and the reasons now sent with each verdict. Batches
  // with questions are not compared: they are solved blind by two families
  // first (1 Oct, the briefs), tested on their own below. Verdicts, P and
  // calls must still agree.
  const normalize = run => {
    const votes = list => (list || []).forEach(v => { if (v && v.blind) { delete v.blind; v.fix = null; } });
    const blindAt = {};
    const blindModels = {};
    let busy = false;
    const body = (text, ri) => {
      let j; try { j = JSON.parse(text); } catch { return text; }
      if (j.busy) busy = true;
      delete j.busy;
      for (const [ii, it] of (j.items || []).entries()) {
        if (it.features) delete it.features.families;
        delete it.reasons;
        (it.votes || []).forEach((v, n) => { if (v && v.blind) { (blindAt[`${ri}:${ii}`] ||= []).push(n); (blindModels[`${ri}:${ii}`] ||= []).push(v.model); } });
        votes(it.votes);
      }
      return j;
    };
    const replies = run.replies.map((r, ri) => ({ status: r.status, body: body(r.body, ri) }));
    const db = JSON.parse(JSON.stringify(run.db, (k, v) => {
      if (k === 'signals' && typeof v === 'string') { try { const s = JSON.parse(v); votes(s.votes); delete s.kind; return JSON.stringify(s); } catch { return v; } }
      return v;
    }));
    if (db && typeof db === 'object') delete db.ai_usage;
    return { replies, log: run.log, db, blindAt, blindModels, busy };
  };
  const unblind = (before, staged) => {
    // a blind voter fixes nothing: the reference's fix in that seat is set aside too
    const strip = run => run.replies.forEach((r, ri) => (r.body?.items || []).forEach((it, ii) => (it.votes || []).forEach((v, n) => { if ((staged.blindAt[`${ri}:${ii}`] || []).includes(n) && v) v.fix = null; })));
    strip(before); delete before.blindAt; delete staged.blindAt;
    // a fix only a now-blind voter proposed is withheld on purpose
    before.replies.forEach((r, ri) => (r.body?.items || []).forEach((it, ii) => {
      const blind = staged.blindModels[`${ri}:${ii}`] || [];
      if (it.fix && Array.isArray(it.fix.by) && it.fix.by.every(m => blind.includes(m))) it.fix = null;
    }));
    // a "busy" reply gave its allowance back on purpose
    if (staged.busy) { delete before.db.usage; delete staged.db.usage; }
    for (const run of [before, staged]) { delete run.blindModels; delete run.busy; }
    const signals = run => JSON.parse(JSON.stringify(run.db, (k, v) => {
      if (k === 'signals' && typeof v === 'string') { try { const s = JSON.parse(v); (s.votes || []).forEach(x => { if (x) x.fix = null; }); return JSON.stringify(s); } catch { return v; } }
      return v;
    }));
    before.db = signals(before); staged.db = signals(staged);
    run2(before); run2(staged);
    function run2(run) { run.replies.forEach(r => (r.body?.items || []).forEach(it => (it.votes || []).forEach(v => { if (v) v.fix = v.fix ?? null; }))); }
  };
  for (const [what, extra, plan, calls] of scenarios) {
    const before = normalize(await play(oldCheckBatch, extra, plan, calls));
    const staged = normalize(await play(checkBatch, extra, plan, calls));
    unblind(before, staged);
    const d = firstDifference(before, staged);
    ok(!d, `same replies, calls and cache as before: ${what}${d ? ` - differs at ${d}` : ''}`);
  }
  // the scenarios do reach what they are about
  const seen = await play(checkBatch, {}, {}, [{ body: { items: [SPLIT], writer: 'gemini-3.5-flash-lite' } }]);
  const split = JSON.parse(seen.replies[0].body).items[0];
  ok(split.votes.length === 3 && !seen.log.includes('gemini:gemini-3.5-flash-lite'), 'the split scenario does bring in a third voter, and not the writer');
  const jev = await play(checkBatch, jevOn, {}, [{ body: { items: [TREAT, DOSE] } }]);
  ok(jev.log.filter(c => c === 'jev').length === 1 && JSON.parse(jev.replies[0].body).items[0].oath, 'the Jev scenario does ask Jev, once, and its yes adds the oath check');
  const day = await play(checkBatch, { ACCURACY_BACKGROUND_BATCHES: '1' }, {}, [
    { account: 'a1', body: { items: [card('a')], priority: 'background' }, opts: {} },
    { account: 'a1', body: { items: [card('b'), card('a')], priority: 'background' }, opts: {} },
  ]);
  const refused = JSON.parse(day.replies[1].body);
  ok(day.replies[1].status === 429 && refused.items[1].cached && refused.items[0].reason === 'day', 'the allowance scenario is refused, keeping the cached item');
}

// MARK: the stages, in order, with typed results
{
  ok(JSON.stringify(STAGES) === JSON.stringify(['rules', 'claims', 'lookup', 'evidence', 'votes', 'jev', 'verdict', 'cache']), `the stages: ${STAGES.join(', ')}`);
  ok(STAGES.every(s => BUDGETS[s] > 0), 'every stage has its own time budget');
  forgetWeights();
  const w = world();
  const run = async (body, opts = { owner: true }) => {
    const trace = [];
    const r = await checkBatch(w.env, 'owner', body, w.fetcher, { ...opts, onStage: s => trace.push(s) });
    return { r, body: await r.json(), trace, at: name => trace.find(s => s.stage === name) };
  };
  let t = await run({ items: [Q1, DOSE] });
  ok(t.trace.map(s => s.stage).join() === STAGES.join() && t.trace.every(s => s.status === 'ok'), 'a fresh batch runs every stage, in order, each ending ok');
  ok(t.trace.every(s => Number.isFinite(s.ms) && s.ms >= 0 && s.budget === budgetsFor(w.env)[s.stage]), 'each stage says how long it took and what its budget was');
  ok(t.at('rules').value.length === 2 && t.at('rules').value.every(Array.isArray), 'rules: the hits of each item');
  ok(t.at('claims').value.length === 2 && t.at('claims').value.every(g => !g.hard.length && g.complete), 'claims: the gate\'s findings for each item (none here)');
  ok(t.at('lookup').value.every(v => v === null), 'lookup: nothing cached yet');
  ok(t.at('evidence').value.length === 2 && t.at('evidence').value[1].some(e => e.url.includes('dailymed')), 'evidence: each item\'s literature, the drug\'s label among it');
  ok(t.at('votes').value.ballots.length === 2 && t.at('votes').value.failures.length === 0, 'votes: the ballots and the failures');
  ok(t.at('jev').value.every(v => v === null), 'jev: no answer while Jev is not set up');
  ok(t.at('verdict').value.map(v => v.id).join() === 'q1,d1' && t.at('verdict').value.every(v => typeof v.verdict === 'string'), 'verdict: what each item is told');
  ok(t.at('cache').value.join() === 'true,true', 'cache: each verdict kept');
  ok(JSON.stringify(t.body.items) === JSON.stringify(t.at('verdict').value), 'the reply is the verdict stage\'s result');

  t = await run({ items: [Q1, DOSE] });
  ok(t.trace.map(s => s.stage).join() === STAGES.join(), 'all cached: still every stage, in order');
  ok(t.trace.filter(s => s.status === 'skipped').map(s => s.stage).join() === 'evidence,votes,jev,cache' && t.body.items.every(i => i.cached),
     'with evidence, votes, Jev and the cache write skipped, nothing asked');

  const pro = world({ ACCURACY_DAILY_BATCHES: '1' });
  forgetWeights();
  await checkBatch(pro.env, 'a1', { items: [card('first')] }, pro.fetcher);
  const trace = [];
  const r = await checkBatch(pro.env, 'a1', { items: [card('second')] }, pro.fetcher, { onStage: s => trace.push(s) });
  ok(r.status === 429 && trace.map(s => s.stage).join() === STAGES.join() && trace.filter(s => s.status === 'skipped').length === 4,
     'no allowance left: every stage in order, the ones that would spend it skipped');
}

// MARK: the claim gate, before the votes (plan Task 5d step 3)
{
  // the voters all call it right; only its own lecture says otherwise
  const FLIP = { id: 'f1', kind: 'card', text: 'Q: First-line drug in type 2 diabetes?\nA: Metformin is not first-line in type 2 diabetes.',
    source: 'Metformin is first-line in type 2 diabetes.' };
  const DOSED = { id: 'f2', kind: 'fact', text: 'Aspirin reduces mortality after myocardial infarction by 50%.', source: 'Aspirin reduces mortality after myocardial infarction by 23%.' };
  const run = async (items, opts = {}) => {
    forgetWeights();
    const w = world();
    const trace = [];
    const r = await checkBatch(w.env, 'owner', { items }, w.fetcher, { owner: true, onStage: s => trace.push(s), ...opts });
    return { r, body: await r.json(), trace, at: name => trace.find(s => s.stage === name), w };
  };
  const quiet = () => ({ hard: [], soft: [], checks: 0, work: 0, complete: true });
  const open = await run([FLIP, DOSED, Q1], { gate: quiet });
  ok(open.body.items[0].verdict === 'verified' && open.body.items[1].verdict === 'verified' && !('claims' in open.body.items[0]),
     'without the gate, the votes alone would have Verified both');
  const gated = await run([FLIP, DOSED, Q1]);
  const [flip, dosed, q1] = gated.body.items;
  ok(gated.trace.map(s => s.stage).join() === STAGES.join() && gated.at('claims').status === 'ok', 'the gate is a stage of its own, before lookup and the votes');
  ok(flip.verdict === 'check' && flip.claims.hard.map(f => f.code).join() === 'negation', 'an item that flips its lecture\'s negation is Check this, with the finding');
  ok(dosed.verdict === 'check' && dosed.claims.hard.map(f => f.code).join() === 'percentage', 'an item that gives another percentage is Check this, with the finding');
  ok(flip.p === open.body.items[0].p && JSON.stringify(flip.votes) === JSON.stringify(open.body.items[0].votes), 'the votes and P(accurate) are left as they were');
  ok(JSON.stringify(q1) === JSON.stringify(open.body.items[2]), 'an item the gate finds nothing in is told exactly what it was before');
  ok(gated.trace.findIndex(s => s.stage === 'claims') < gated.trace.findIndex(s => s.stage === 'votes'), 'the gate runs before any vote');
  const cachedAgain = await checkBatch(gated.w.env, 'owner', { items: [FLIP] }, gated.w.fetcher, { owner: true });
  const again = (await cachedAgain.json()).items[0];
  ok(again.cached && again.verdict === 'check' && again.claims.hard.length === 1, 'a cached item is gated too: it never comes back Verified');

  // a gate that fails never lets an item through, and holds nothing else up
  const broken = await run([FLIP, Q1], { gate: item => { if (item.id === 'f1') throw new Error('bug'); return quiet(); } });
  ok(broken.r.status === 200 && broken.at('claims').status === 'error', 'a failing gate: the stage says so, and the batch still answers');
  ok(broken.body.items[0].verdict === 'check' && broken.body.items[0].claims.hard[0].code === 'gate_failed', 'the item it failed on is held at Check this');
  ok(broken.body.items[1].verdict === open.body.items[2].verdict && !('claims' in broken.body.items[1]), 'the others are graded as before');

  // the batch shares the work budget; what one item leaves goes to the next
  const shares = [];
  const spy = used => (item, share) => { shares.push(share); return { ...quiet(), work: Math.min(used, share) }; };
  claimsStage([FLIP, DOSED, Q1, C1], 250, 120, spy(4));
  ok(shares.join() === '75,86,97,108', `each item what is left but half an even share for each after it (${shares.join()})`);
  shares.length = 0;
  claimsStage([FLIP, DOSED], 250, 120, spy(1000));
  ok(shares.join() === '90,30', 'and the last item still has half an even share when the first uses all it may');
  const long = { id: 'l1', kind: 'note', text: 'Metformin is not first-line in type 2 diabetes. '.repeat(60), source: 'Metformin is first-line in type 2 diabetes. '.repeat(30) };
  const cut = claimsStage([long], 250, 3);
  ok(cut.value[0].checks <= 3 && cut.value[0].complete === false, 'a long page stops at the budget, saying it was cut short');
  const partial = await run([long], { maxWork: 0 });
  ok(partial.body.items[0].claims?.partial === true, 'and the reply says the gate did not finish');
}

// MARK: a stage out of time gives its safe result
{
  // within(): the value, or the safe result and why
  ok(JSON.stringify(await within(50, async () => 7, 0)) === '{"status":"ok","value":7}', 'within: the value in time');
  let started = Date.now();
  const late = await within(30, () => new Promise(() => {}), 'safe');
  ok(late.status === 'timeout' && late.value === 'safe' && Date.now() - started < 500, 'within: work that never ends gives the safe result at the budget');
  const thrown = await within(30, () => { throw new Error('x'); }, 'safe');
  const rejected = await within(30, async () => { throw new Error('y'); }, 'safe');
  ok(thrown.status === 'error' && rejected.status === 'error' && thrown.value === 'safe' && rejected.error.message === 'y', 'within: a failure gives the safe result too');

  // evidence: an evidence timeout is no evidence; the voters are still asked
  {
    forgetWeights();
    const w = world({}, { evidence: 'hang' });
    const trace = [];
    started = Date.now();
    const r = await checkBatch(w.env, 'owner', { items: [DOSE, Q1] }, w.fetcher, { owner: true, budgets: { evidence: 40 }, onStage: s => trace.push(s) });
    const body = await r.json();
    const ev = trace.find(s => s.stage === 'evidence');
    ok(Date.now() - started < 3000 && ev.status === 'timeout' && ev.value.every(e => e.length === 0), 'evidence that never comes: out of time, no evidence');
    ok(r.status === 200 && body.items.every(i => i.evidence.length === 0 && i.votes.length === 2), 'and the items are still voted on, shown none');
    ok(w.prompts.length === 2 && w.prompts.every(p => p.includes('(none found)')), 'the voters are told no evidence was found');
    ok(body.stages?.[0]?.stage === 'evidence' && body.stages[0].status === 'timeout', 'the owner is told which stage ran out of time');
    w.release();
  }

  // votes: an unanswered vote is no vote, and the next voter is asked
  {
    forgetWeights();
    const w = world({}, { hang: new Set(['gemini-3.5-flash-lite']) });
    const trace = [];
    started = Date.now();
    const r = await checkBatch(w.env, 'owner', { items: [Q1] }, w.fetcher, { owner: true, budgets: { votes: 40 }, onStage: s => trace.push(s) });
    const body = await r.json();
    const v = trace.find(s => s.stage === 'votes');
    ok(Date.now() - started < 3000 && v.status === 'timeout', 'a voter that never answers: the votes stage says it ran out of time');
    ok(body.failures?.includes('gemini:gemini-3.5-flash-lite: timeout') && body.items[0].votes.map(x => x.model).join() === '@cf/openai/gpt-oss-120b,@cf/nvidia/nemotron-3-120b-a12b',
       'that voter is no vote, and the next two are asked');
    ok(dump(w.db).verdicts.length === 1, 'the votes that came are kept');
    w.release();

    forgetWeights();
    const all = new Set(['gemini-3.5-flash-lite', '@cf/openai/gpt-oss-120b', '@cf/nvidia/nemotron-3-120b-a12b', 'gemma-4-31b-it']);
    const quiet = world({}, { hang: all });
    started = Date.now();
    const r2 = await checkBatch(quiet.env, 'owner', { items: [Q1] }, quiet.fetcher, { owner: true, budgets: { votes: 25 } });
    const b2 = await r2.json();
    ok(Date.now() - started < 3000 && b2.items[0].verdict === 'unchecked' && b2.items[0].reason === 'busy' && b2.items[0].votes.length === 0,
       'no voter answers in time: unchecked and busy, never a verdict without votes');
    ok(b2.failures.length === MAX_CALLS && b2.failures.every(f => f.endsWith(': timeout')), `at most ${MAX_CALLS} voters asked`);
    ok(dump(quiet.db).verdicts.length === 0, 'and nothing is kept, so the item is checked again next time');
    quiet.release();

    forgetWeights();
    const broken = world({}, {});
    let asked = 0;
    const throwing = async (url, init) => {
      if (url.includes('firebasevertexai') && !asked++) throw new TypeError('network gone');
      return broken.fetcher(url, init);
    };
    const r3 = await checkBatch(broken.env, 'owner', { items: [Q1] }, throwing, { owner: true });
    const b3 = await r3.json();
    ok(r3.status === 200 && b3.items[0].votes.length === 2, 'a voter whose call fails is no vote, and others still decide');
  }

  // jev: out of time, no answer - the patterns' answer stands
  {
    forgetWeights();
    const env = { JEV_API_KEY: 'k', PRO_PAYS: 'on', JEV_TIMEOUT_MS: '5000' };
    const answered = world(env);
    const a = await (await checkBatch(answered.env, 'owner', { items: [TREAT] }, answered.fetcher, { owner: true })).json();
    forgetWeights();
    const w = world(env, { jev: 'hang' });
    const trace = [];
    started = Date.now();
    const r = await checkBatch(w.env, 'owner', { items: [TREAT] }, w.fetcher, { owner: true, budgets: { jev: 40 }, onStage: s => trace.push(s) });
    const body = await r.json();
    ok(a.items[0].oath && a.items[0].verdict === 'check', 'Jev answering yes adds the oath check (no evidence behind it: Check this)');
    ok(Date.now() - started < 3000 && trace.find(s => s.stage === 'jev').status === 'timeout' && trace.find(s => s.stage === 'jev').value[0] === null,
       'Jev never answering: out of time, no answer');
    ok(!body.items[0].oath && body.items[0].verdict === 'verified' && !JSON.parse(dump(w.db).verdicts[0].signals).jevOath,
       'and the patterns\' answer stands, as when Jev is not set up');
    w.release();
  }

  // lookup: a read that never comes is no cached verdict - the item is checked afresh
  {
    forgetWeights();
    let trouble = null;
    const w = world({}, { db: (sql, kind) => (trouble && sql.includes('FROM accuracy_verdicts') && kind === 'first' ? trouble : null) });
    await checkBatch(w.env, 'owner', { items: [Q1] }, w.fetcher, { owner: true });
    const calls = w.log.length;
    trouble = 'hang';
    const trace = [];
    started = Date.now();
    const r = await checkBatch(w.env, 'owner', { items: [Q1] }, w.fetcher, { owner: true, budgets: { lookup: 40 }, onStage: s => trace.push(s) });
    const body = await r.json();
    ok(Date.now() - started < 3000 && trace.find(s => s.stage === 'lookup').status === 'timeout', 'a cache read that never answers: out of time');
    ok(!body.items[0].cached && body.items[0].votes.length === 2 && w.log.length > calls, 'the item is checked afresh, never left without a verdict');
    trouble = 'throw';
    const r2 = await (await checkBatch(w.env, 'owner', { items: [Q1] }, w.fetcher, { owner: true })).json();
    ok(!r2.items[0].cached && r2.items[0].votes.length === 2, 'a cache read that fails: the same');
  }

  // cache: a cache failure never blocks a verdict
  {
    forgetWeights();
    let trouble = 'hang';
    const w = world({}, { db: (sql, kind) => (sql.includes('INTO accuracy_verdicts') && kind === 'run' ? trouble : null) });
    const before = await Promise.race([oldCheckBatch(w.env, 'owner', { items: [C1] }, w.fetcher, { owner: true }).then(() => 'answered'), sleep(300).then(() => 'still waiting')]);
    ok(before === 'still waiting', 'before the stages, a cache write that never ended held the verdict back for good');
    const trace = [];
    started = Date.now();
    const r = await checkBatch(w.env, 'owner', { items: [Q1] }, w.fetcher, { owner: true, budgets: { cache: 40 }, onStage: s => trace.push(s) });
    const body = await r.json();
    ok(Date.now() - started < 3000 && r.status === 200 && body.items[0].votes.length === 2 && ['verified', 'check', 'flagged'].includes(body.items[0].verdict),
       'now the verdict comes back when the write never ends');
    ok(trace.find(s => s.stage === 'cache').status === 'timeout' && trace.find(s => s.stage === 'cache').value[0] === false, 'the cache stage says the write ran out of time');
    trouble = 'throw';
    const trace2 = [];
    const r2 = await checkBatch(w.env, 'owner', { items: [DOSE] }, w.fetcher, { owner: true, onStage: s => trace2.push(s) });
    ok(r2.status === 200 && (await r2.json()).items[0].votes.length === 2 && trace2.find(s => s.stage === 'cache').status === 'error',
       'and when the write fails');
    trouble = null;
    const calls = w.log.length;
    const r3 = await (await checkBatch(w.env, 'owner', { items: [DOSE] }, w.fetcher, { owner: true })).json();
    ok(!r3.items[0].cached && w.log.length > calls, 'an item whose verdict was not kept is simply checked again');
  }

  // the stage functions on their own
  {
    const w = world();
    const rules = rulesStage([cleanItem(SEVERE)]);
    ok(rules.stage === 'rules' && rules.status === 'ok' && rules.value[0].some(h => h.rule === 'dose-range'), 'rulesStage: typed result with the hits');
    const lookup = await lookupStage(w.env, ['00'], 40);
    ok(lookup.stage === 'lookup' && lookup.value[0] === null, 'lookupStage: null when nothing is cached');
    const ev = await evidenceStage([cleanItem(DOSE)], w.fetcher, 2000);
    ok(ev.status === 'ok' && ev.value[0][0].id === 'S1', 'evidenceStage: numbered evidence per item');
    const votes = await votesStage(w.env, 'owner', true, '', [{ item: cleanItem(C1), evidence: [] }], w.fetcher, 2000);
    ok(votes.value.ballots.length === 2, 'votesStage: two ballots');
    const jev = await jevStage({}, [{ item: cleanItem(TREAT) }], [[{ risk: 1 }]], w.fetcher, 40);
    ok(jev.status === 'ok' && jev.value[0] === null, 'jevStage: no key, no question');
    const kept = await cacheStage(w.env, [{ hash: 'h1', signals: { votes: [] } }], 2000);
    ok(kept.value[0] === true && dump(w.db).verdicts.length === 1, 'cacheStage: written');
  }
}

// MARK: every budget is longer than the timeout already inside its work
{
  const source = name => readFileSync(join(here, '..', name), 'utf8');
  const constant = (text, name) => Number(text.match(new RegExp(`const ${name} = ([\\d_]+);`))?.[1].replace(/_/g, ''));
  const upstream = constant(source('ai.js'), 'UPSTREAM_TIMEOUT_MS');
  const lookups = constant(source('evidence.js'), 'TIMEOUT_MS');
  ok(upstream > 0 && BUDGETS.votes > upstream, `a voter's budget (${BUDGETS.votes} ms) outlasts ai.js's own model timeout (${upstream} ms)`);
  ok(lookups > 0 && BUDGETS.evidence > lookups, `the evidence budget (${BUDGETS.evidence} ms) outlasts evidence.js's per-source timeout (${lookups} ms)`);
  ok(budgetsFor({}).jev > JEV_TIMEOUT_MS && budgetsFor({ JEV_TIMEOUT_MS: '3000' }).jev > 3000, 'Jev\'s budget follows its own timeout');
  ok(BUDGETS.votes * MAX_CALLS < 10 * 60_000, 'and the voters together stay within ten minutes');
  ok(budgetsFor({}, { cache: 7 }).cache === 7 && budgetsFor({}).lookup === BUDGETS.lookup, 'a test may set any budget');
}

// MARK: what the briefs changed (1 Oct): a blind second voter, two families, refunds, no retractions
{
  // a question is solved blind by two families before anyone sees its key
  const w = world();
  forgetWeights();
  const r = await checkBatch(w.env, 'owner', { items: [Q1] }, w.fetcher, { owner: true });
  const body = JSON.parse(await r.text());
  const withheld = w.prompts.filter(p => p.includes('Keyed answer and explanation withheld'));
  const full = w.prompts.filter(p => p.includes('Keyed answer: B'));
  ok(withheld.length === 2 && full.length === 0 && !withheld.some(p => p.includes('PCC works fastest')),
     'the first two voters solve the question blind: no key, no explanation (a short explanation needs no third look)');
  const votes = body.items[0].votes;
  ok(votes.length === 2 && votes.every(v => v.blind === true && v.fix === null), 'their votes are marked blind and fix nothing');
  ok(new Set(votes.map(v => familyOf(v.model))).size === 2, 'and come from two model families');
  ok(body.items[0].verdict === 'verified', 'two independent blind solves reaching the key, passing it: Verified');
  w.release();
}
{
  // a question cached before blind-first voting is checked again, not graded on votes that saw the key
  const w = world();
  forgetWeights();
  const first = await checkBatch(w.env, 'owner', { items: [Q1] }, w.fetcher, { owner: true });
  const hash = JSON.parse(await first.text()).items[0].hash;
  const old = { votes: [{ model: 'gemini-3.5-flash-lite', risk: 1, answer: 'B', evidence: 'supports' }, { model: 'gpt-oss-120b', risk: 1, answer: 'B', evidence: 'supports', blind: true }], sourceMatch: 1, evidence: [] };
  w.db.prepare('UPDATE accuracy_verdicts SET signals = ? WHERE hash = ?').run(JSON.stringify(old), hash);
  const calls = w.prompts.length;
  const again = JSON.parse(await (await checkBatch(w.env, 'owner', { items: [Q1] }, w.fetcher, { owner: true })).text()).items[0];
  ok(!again.cached && w.prompts.length === calls + 2 && again.votes.filter(v => v.blind).length === 2, 'old question votes are stale: asked again, blind');
  ok(staleSignals(old) && !staleSignals(again) && !staleSignals({ votes: [{ risk: 1, answer: null }] }), 'stale means a question with fewer than two blind solves');
  w.release();
}
{
  // an explanation worth judging brings a third voter, shown the key
  const w = world();
  forgetWeights();
  const r = await checkBatch(w.env, 'owner', { items: [EXPLAINED] }, w.fetcher, { owner: true });
  const item = JSON.parse(await r.text()).items[0];
  ok(item.votes.length === 3 && item.votes.filter(v => v.blind).length === 2 && !item.votes[2].blind
     && w.prompts.some(p => p.includes('vitamin K takes hours')), 'two blind solves, then a review shown the key and the explanation');
  w.release();
}
{
  // a wrong key: both families, solving blind, choose another answer
  const w = world();
  forgetWeights();
  const r = await checkBatch(w.env, 'owner', { items: [KEYWRONG] }, w.fetcher, { owner: true });
  const item = JSON.parse(await r.text()).items[0];
  ok(item.verdict === 'flagged' && item.fix?.field === 'key' && item.fix.value === 'A', 'Flagged, with the answer they chose offered as the fix');
  ok(item.reasons.some(x => x.includes('another answer (A)')), 'and the reason says why', JSON.stringify(item.reasons));
  w.release();
}
{
  // blind solves that split: a third family breaks the tie
  const w = world();
  forgetWeights();
  const r = await checkBatch(w.env, 'owner', { items: [SPLIT] }, w.fetcher, { owner: true });
  const item = JSON.parse(await r.text()).items[0];
  ok(item.votes.length === 3 && item.votes.every(v => v.blind), 'a split between the blind solves asks a third, also blind');
  w.release();
}
{
  // a question beside a card: the card still gets two full votes, and the question its blind solves
  const w = world();
  forgetWeights();
  const r = await checkBatch(w.env, 'owner', { items: [Q1, C1] }, w.fetcher, { owner: true });
  const items = JSON.parse(await r.text()).items;
  ok(items[0].verdict === 'verified' && items[1].verdict === 'verified' && items[1].votes.length === 2, 'a mixed batch verifies both kinds');
  w.release();
}
{
  // a card has no key: both voters see it whole
  const w = world();
  forgetWeights();
  await checkBatch(w.env, 'owner', { items: [C1] }, w.fetcher, { owner: true });
  ok(!w.prompts.some(p => p.includes('withheld')), 'a batch with no question asks nobody blind');
  w.release();
}
{
  // after a Google vote, the next voter is from another family even when a Google model is next in line
  const w = world({ ACCURACY_VOTERS: 'gemini:gemini-3.5-flash-lite,gemini:gemma-4-31b-it,workers-ai:@cf/openai/gpt-oss-120b' });
  forgetWeights();
  const r = await checkBatch(w.env, 'owner', { items: [C1] }, w.fetcher, { owner: true });
  const item = JSON.parse(await r.text()).items[0];
  ok(item.votes.map(v => v.model).join() === 'gemini-3.5-flash-lite,@cf/openai/gpt-oss-120b' && item.verdict === 'verified',
     'Gemma waits: the second voter is gpt-oss, a second family');
  w.release();
}
{
  // only one family to ask: never Verified
  const w = world({ ACCURACY_VOTERS: 'gemini:gemini-3.5-flash-lite,gemini:gemma-4-31b-it' });
  forgetWeights();
  const r = await checkBatch(w.env, 'owner', { items: [C1] }, w.fetcher, { owner: true });
  const item = JSON.parse(await r.text()).items[0];
  ok(item.votes.length === 2 && item.verdict === 'check', 'two Google votes pass the card but leave it Check this');
  w.release();
}
{
  // nobody answers: the batch's allowance comes back and the app is told to wait
  const all = new Set(['gemini-3.5-flash-lite', '@cf/openai/gpt-oss-120b', '@cf/nvidia/nemotron-3-120b-a12b', 'gemma-4-31b-it']);
  const w = world({}, { garbage: all });
  forgetWeights();
  const r = await checkBatch(w.env, 'a1', { items: [card('refund')] }, w.fetcher, { owner: false });
  const body = JSON.parse(await r.text());
  const used = w.db.prepare("SELECT account_id, requests FROM ai_usage WHERE account_id LIKE 'accuracy%'").all();
  ok(body.busy === true && body.items[0].verdict === 'unchecked', 'nobody answered: "busy", and the item stays unchecked');
  ok(used.length > 0 && used.every(u => u.requests === 0), 'and every count the batch took is given back', JSON.stringify(used));
  w.release();
}
{
  // the evidence search excludes retracted records and retraction notices
  const w = world();
  forgetWeights();
  let asked = '';
  const watch = async (url, init) => { if (url.includes('europepmc')) asked = new URL(url).searchParams.get('query'); return w.fetcher(url, init); };
  await checkBatch(w.env, 'owner', { items: [Q1] }, watch, { owner: true });
  ok(asked.includes('NOT (PUB_TYPE:"retracted publication" OR PUB_TYPE:"retraction of publication")'), 'Europe PMC is asked for no retracted record', asked);
  w.release();
}

console.log(failures ? `\n${failures} STAGE TEST FAILURE(S)` : '\nALL STAGE TESTS PASS');
process.exit(failures ? 1 : 0);
