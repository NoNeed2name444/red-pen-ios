// The accuracy check as named stages (accuracy.js, plan Task 5d step 1).
//
// The stages run in a fixed order, and a stage that runs out of time or
// fails gives its safe result: an unanswered vote is no vote, an evidence
// timeout is no evidence, a cache failure never blocks a verdict. (The split
// into stages was shown to change nothing against the check as it was at
// 52514d3; the three-family bar of 1 Oct changes every reply on purpose, so
// that copy is no longer the reference and is gone.)
//
// Run: node server/tests/accuracy-stages.test.mjs

import { DatabaseSync } from 'node:sqlite';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import {
  checkBatch, STAGES, BUDGETS, budgetsFor, within, rulesStage, claimsStage, lookupStage, evidenceStage, votesStage, jevStage, cacheStage, proofStage, proofDue,
  BATCH, MAX_CALLS, cleanItem, itemHash, currentWeights, forgetWeights, evidenceFor, votePrompt, parseVotes, disagree, votersFor, suggestedFix, staleSignals } from '../accuracy.js';
import { spend } from '../ai.js';
import { resetBreakers } from '../breakers.js';
import { jevOath, TIMEOUT_MS as JEV_TIMEOUT_MS } from '../jev.js';
import { sourceMatch } from '../accuracy-rules.js';
import { verdict, familyOf, MIN_VERIFY_VOTERS } from '../accuracy-model.js';
import { PROOF_VERSION } from '../proof.js';

const here = dirname(fileURLToPath(import.meta.url));
let failures = 0;
const ok = (cond, what) => { console.log((cond ? 'ok   ' : 'FAIL ') + what); if (!cond) failures++; };
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));

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
      if (plan.mlp === 'down') return new Response('busy', { status: 503 });
      const respond = () => new Response(`<nlmSearchResult><document url="https://medlineplus.gov/${q.replace(/\W+/g, '')}.html"><content name="title">${plan.says ? 'Warfarin' : q}</content><content name="FullSummary">MedlinePlus on ${q}.${plan.says ? ' ' + plan.says : ''}</content></document></nlmSearchResult>`, { status: 200 });
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
// stated word for word by the MedlinePlus summary a world given SAYS sends back
// (its Warfarin summary, whatever was searched)
const SAYS = 'The drug of choice to reverse warfarin is prothrombin complex concentrate. Warfarin is reversed by vitamin K and PCC.';
const PQ = { id: 'pq1', kind: 'mcq', stem: 'The drug of choice to reverse warfarin is:', options: ['Vitamin K', 'Prothrombin complex concentrate'], key: 1, explanation: '', source: '' };
const PC = { id: 'pc1', kind: 'card', text: 'Cloze: Warfarin is reversed by {{c1::vitamin K}} and PCC.', source: '' };
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

// MARK: the scenarios do what they say
{
  const jevOn = { JEV_API_KEY: 'k', PRO_PAYS: 'on' };
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
  ok(JSON.stringify(STAGES) === JSON.stringify(['rules', 'claims', 'lookup', 'evidence', 'proof', 'votes', 'jev', 'verdict', 'cache']), `the stages: ${STAGES.join(', ')}`);
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
  ok(t.at('votes').value.ballots.length === 3 && t.at('votes').value.failures.length === 0, 'votes: the ballots (three families) and the failures');
  ok(t.at('jev').value.every(v => v === null), 'jev: no answer while Jev is not set up');
  ok(t.at('verdict').value.map(v => v.id).join() === 'q1,d1' && t.at('verdict').value.every(v => typeof v.verdict === 'string'), 'verdict: what each item is told');
  ok(t.at('cache').value.join() === 'true,true', 'cache: each verdict kept');
  ok(JSON.stringify(t.body.items) === JSON.stringify(t.at('verdict').value), 'the reply is the verdict stage\'s result');

  t = await run({ items: [Q1, DOSE] });
  ok(t.trace.map(s => s.stage).join() === STAGES.join(), 'all cached: still every stage, in order');
  ok(t.trace.filter(s => s.status === 'skipped').map(s => s.stage).join() === 'evidence,proof,votes,jev,cache' && t.body.items.every(i => i.cached),
     'with evidence, proof, votes, Jev and the cache write skipped, nothing asked');

  const pro = world({ ACCURACY_DAILY_BATCHES: '1' });
  forgetWeights();
  await checkBatch(pro.env, 'a1', { items: [card('first')] }, pro.fetcher);
  const trace = [];
  const r = await checkBatch(pro.env, 'a1', { items: [card('second')] }, pro.fetcher, { onStage: s => trace.push(s) });
  ok(r.status === 429 && trace.map(s => s.stage).join() === STAGES.join() && trace.filter(s => s.status === 'skipped').length === 5,
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
  const onlyProof = i => i.verdict === 'check' && i.p > 0.9 && i.reasons.length === 1 && /no official source states/i.test(i.reasons[0]);
  ok(onlyProof(open.body.items[0]) && onlyProof(open.body.items[1]) && !('claims' in open.body.items[0]),
     'without the gate, only the missing source proof holds both back: the votes alone pass them');
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

// MARK: the source proof (plan SP2): only an official source stating it word for word verifies
{
  // a source that could not be read is 'lookup': Check this, said so, and proved again later without asking the voters
  const plan = { says: SAYS, mlp: 'down' };
  const w = world({}, plan);
  forgetWeights();
  let body = await (await checkBatch(w.env, 'owner', { items: [PC] }, w.fetcher, { owner: true })).json();
  ok(body.items[0].verdict === 'check' && body.items[0].proof.why === 'lookup'
     && body.items[0].reasons.includes('An official source could not be read this time; it will be checked again.'),
     "MedlinePlus down: 'lookup', Check this, saying it will be checked again");
  const before = w.db.prepare('SELECT hash, created_at, signals FROM accuracy_verdicts').all();
  ok(before.length === 1 && JSON.parse(before[0].signals).proof.why === 'lookup', 'the proof is kept with the verdict');
  plan.mlp = 'up';
  const asked = w.log.length;
  const trace = [];
  const r = await checkBatch(w.env, 'owner', { items: [PC] }, w.fetcher, { owner: true, onStage: s => trace.push(s) });
  body = await r.json();
  const fresh = w.log.slice(asked);
  ok(body.items[0].cached && body.items[0].verdict === 'verified' && body.items[0].proof.proven === 1
     && !fresh.some(c => c.startsWith('gemini:') || c.startsWith('workers:')) && fresh.some(c => c.startsWith('medlineplus:')),
     'checked again with MedlinePlus back: proved from the cache, no voter asked, Verified');
  ok(trace.find(s => s.stage === 'proof').status === 'ok' && trace.find(s => s.stage === 'votes').status === 'skipped', 'the proof stage runs; the votes stage is skipped');
  const after = w.db.prepare('SELECT hash, created_at, signals FROM accuracy_verdicts').all();
  ok(after.length === 1 && after[0].created_at === before[0].created_at && JSON.parse(after[0].signals).proof.proven === 1
     && JSON.stringify(JSON.parse(after[0].signals).votes) === JSON.stringify(JSON.parse(before[0].signals).votes),
     'the new proof is written over the old, keeping the votes and the age of the check');
  const t3 = [];
  await checkBatch(w.env, 'owner', { items: [PC] }, w.fetcher, { owner: true, onStage: s => t3.push(s) });
  ok(t3.find(s => s.stage === 'proof').status === 'skipped', 'and once proved, it is not proved again');
  w.release();
}
{
  // which cached proofs are due again
  const p = why => ({ v: PROOF_VERSION, claims: 1, proven: why ? 0 : 1, quotes: [], ...(why ? { why } : {}) });
  ok(proofDue(undefined) && proofDue(null) && proofDue({ ...p(), v: 0 }), 'due: no proof yet, or one from an older prover');
  ok(['budget', 'timeout', 'lookup', 'error'].every(why => proofDue(p(why))), 'due: one cut short (too long, out of time, a source not read, a failure)');
  ok(!proofDue(p()) && !['unproven', 'no-source', 'stem', 'card', 'claim', 'many', 'empty', 'distractor', 'options'].some(why => proofDue(p(why))),
     'not due: one proved, or one its sources were read in full and do not state');
  // the stage's own results
  const fails = async () => { throw new Error('down'); };
  const failed = await proofStage([PC], fails, 2000);
  ok(failed.value[0].why === 'lookup' && failed.value[0].proven === 0, "every lookup failing: 'lookup'");
  const never = await proofStage([PC], () => new Promise(() => {}), 30);
  ok(never.status === 'timeout' && never.value[0].why === 'timeout', "lookups that never end: 'timeout' at the budget");
  const broke = await proofStage([{ kind: 'card', get text() { throw new Error('bad item'); } }], async () => new Response('{}', { status: 404 }), 2000);
  ok(broke.value[0].why === 'error' && broke.status === 'error', "the prover failing on an item: 'error', and the stage says so");
  const w = world({}, { says: SAYS });
  const two = await proofStage([PQ, PC], w.fetcher, 2000);
  ok(two.status === 'ok' && two.value.every(v => v.proven === 1 && !('read' in v)), 'proved, each its own proof, without the count of what was read');
  w.release();
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
    const r = await checkBatch(w.env, 'owner', { items: [DOSE, Q1] }, w.fetcher, { owner: true, budgets: { evidence: 40, proof: 40 }, onStage: s => trace.push(s) });
    const body = await r.json();
    const ev = trace.find(s => s.stage === 'evidence'), pr = trace.find(s => s.stage === 'proof');
    ok(Date.now() - started < 3000 && ev.status === 'timeout' && ev.value.every(e => e.length === 0), 'evidence that never comes: out of time, no evidence');
    ok(pr.status === 'timeout' && body.items.every(i => i.proof?.why === 'timeout' && i.verdict !== 'verified'),
       "official sources that never come: the proof is out of time too, 'timeout', and nothing is Verified");
    ok(r.status === 200 && body.items.every(i => i.evidence.length === 0 && i.votes.length === 3), 'and the items are still voted on, shown none');
    ok(w.prompts.length === 3 && w.prompts.every(p => p.includes('(none found)')), 'the voters are told no evidence was found');
    ok(body.stages?.[0]?.stage === 'evidence' && body.stages[0].status === 'timeout' && body.stages.some(x => x.stage === 'proof' && x.status === 'timeout'), 'the owner is told which stages ran out of time');
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
    ok(body.failures?.includes('gemini:gemini-3.5-flash-lite: timeout') && body.items[0].votes.map(x => x.model).join() === '@cf/openai/gpt-oss-120b,@cf/nvidia/nemotron-3-120b-a12b,gemma-4-31b-it',
       'that voter is no vote, and Gemma stands in for Google');
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
    ok(b2.failures.length === 4 && b2.failures.length <= MAX_CALLS && b2.failures.every(f => f.endsWith(': timeout')), `each of the four voters asked once, never more than ${MAX_CALLS} calls`);
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
    ok(r3.status === 200 && b3.items[0].votes.length === 3 && b3.items[0].votes.some(v => v.model === 'gemma-4-31b-it'), 'a voter whose call fails is no vote, and another of its family stands in');
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
    ok(!body.items[0].oath && body.items[0].verdict === 'check' && !JSON.parse(dump(w.db).verdicts[0].signals).jevOath,
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
    ok(!body.items[0].cached && body.items[0].votes.length === 3 && w.log.length > calls, 'the item is checked afresh, never left without a verdict');
    trouble = 'throw';
    const r2 = await (await checkBatch(w.env, 'owner', { items: [Q1] }, w.fetcher, { owner: true })).json();
    ok(!r2.items[0].cached && r2.items[0].votes.length === 3, 'a cache read that fails: the same');
  }

  // cache: a cache failure never blocks a verdict
  {
    forgetWeights();
    let trouble = 'hang';
    const w = world({}, { db: (sql, kind) => (sql.includes('INTO accuracy_verdicts') && kind === 'run' ? trouble : null) });
    const trace = [];
    started = Date.now();
    const r = await checkBatch(w.env, 'owner', { items: [Q1] }, w.fetcher, { owner: true, budgets: { cache: 40 }, onStage: s => trace.push(s) });
    const body = await r.json();
    ok(Date.now() - started < 3000 && r.status === 200 && body.items[0].votes.length === 3 && ['verified', 'check', 'flagged'].includes(body.items[0].verdict),
       'now the verdict comes back when the write never ends');
    ok(trace.find(s => s.stage === 'cache').status === 'timeout' && trace.find(s => s.stage === 'cache').value[0] === false, 'the cache stage says the write ran out of time');
    trouble = 'throw';
    const trace2 = [];
    const r2 = await checkBatch(w.env, 'owner', { items: [DOSE] }, w.fetcher, { owner: true, onStage: s => trace2.push(s) });
    ok(r2.status === 200 && (await r2.json()).items[0].votes.length === 3 && trace2.find(s => s.stage === 'cache').status === 'error',
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
    ok(votes.value.ballots.length === 3, 'votesStage: three ballots, from three families');
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
  // three at once, then the rest one after another: a call and the ones
  // replacing it, end to end, are at most MAX_CALLS - 2 budgets
  ok(BUDGETS.votes * (MAX_CALLS - MIN_VERIFY_VOTERS + 1) < 10 * 60_000, 'and the voters together stay within ten minutes');
  ok(budgetsFor({}, { cache: 7 }).cache === 7 && budgetsFor({}).lookup === BUDGETS.lookup, 'a test may set any budget');
}

// MARK: what the briefs changed (1 Oct): blind solvers, three families, refunds, no retractions
{
  // a question is solved blind by three families before anyone sees its key
  const w = world();
  forgetWeights();
  const r = await checkBatch(w.env, 'owner', { items: [Q1] }, w.fetcher, { owner: true });
  const body = JSON.parse(await r.text());
  const withheld = w.prompts.filter(p => p.includes('Keyed answer and explanation withheld'));
  const full = w.prompts.filter(p => p.includes('Keyed answer: B'));
  ok(withheld.length === 3 && full.length === 0 && !withheld.some(p => p.includes('PCC works fastest')),
     'the first three voters solve the question blind: no key, no explanation (a short explanation needs no review)');
  const votes = body.items[0].votes;
  ok(votes.length === 3 && votes.every(v => v.blind === true && v.fix === null), 'their votes are marked blind and fix nothing');
  ok(new Set(votes.map(v => familyOf(v.model))).size === 3, 'and come from three model families');
  ok(body.items[0].verdict === 'check' && body.items[0].reasons.includes('No official source states it word for word yet.'),
     'three independent blind solves reaching the key, passing it, with no official source stating it: still Check this');
  w.release();
  const said = world({}, { says: SAYS });
  forgetWeights();
  const proven = JSON.parse(await (await checkBatch(said.env, 'owner', { items: [PQ] }, said.fetcher, { owner: true })).text()).items[0];
  ok(proven.verdict === 'verified' && proven.votes.every(v => v.blind) && proven.proof.proven === proven.proof.claims,
     `three blind solves reaching the key, which MedlinePlus states word for word: Verified (${proven.verdict}, ${JSON.stringify(proven.proof)})`);
  said.release();
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
  ok(!again.cached && w.prompts.length === calls + 3 && again.votes.filter(v => v.blind).length === 3, 'old question votes are stale: asked again, blind');
  ok(staleSignals(old) && !staleSignals(again) && !staleSignals({ votes: [{ risk: 1, answer: null }] }), 'stale means a question with fewer than two blind solves');
  const short = { kind: 'mcq', votes: [{ model: 'gemini-3.5-flash-lite', risk: 1, answer: 'B', blind: true }, { model: 'gpt-oss-120b', risk: 1, answer: 'B', blind: true }] };
  ok(!staleSignals(short, 3600) && staleSignals(short, 90_000), 'a check that reached only two families is tried again once a day has passed');
  ok(!staleSignals({ kind: 'card', votes: [{ model: 'gemini-3.5-flash-lite', risk: 4 }, { model: 'gpt-oss-120b', risk: 1 }, { model: 'nemotron', risk: 1 }] }, 90_000),
     'a card read by three families is not, whatever they said');
  w.release();
}
{
  // an explanation worth judging brings a third voter, shown the key
  const w = world();
  forgetWeights();
  const r = await checkBatch(w.env, 'owner', { items: [EXPLAINED] }, w.fetcher, { owner: true });
  const item = JSON.parse(await r.text()).items[0];
  ok(item.votes.length === 4 && item.votes.filter(v => v.blind).length === 3 && !item.votes[3].blind
     && w.prompts.some(p => p.includes('vitamin K takes hours')), 'three blind solves, then a review shown the key and the explanation');
  w.release();
}
{
  // a wrong key: all three families, solving blind, choose another answer
  const w = world();
  forgetWeights();
  const r = await checkBatch(w.env, 'owner', { items: [KEYWRONG] }, w.fetcher, { owner: true });
  const item = JSON.parse(await r.text()).items[0];
  ok(item.verdict === 'flagged' && item.fix?.field === 'key' && item.fix.value === 'A', 'Flagged, with the answer they chose offered as the fix');
  ok(item.reasons.some(x => x.includes('another answer (A)')), 'and the reason says why', JSON.stringify(item.reasons));
  w.release();
}
{
  // blind solves that split: no fourth family to ask, so Check this
  const w = world();
  forgetWeights();
  const r = await checkBatch(w.env, 'owner', { items: [SPLIT] }, w.fetcher, { owner: true });
  const item = JSON.parse(await r.text()).items[0];
  ok(item.votes.length === 3 && item.votes.every(v => v.blind) && item.verdict === 'check', 'a split between three blind solves is Check this');
  w.release();
}
{
  // a question beside a card: the card still gets three full votes, and the question its blind solves
  const w = world({}, { says: SAYS });
  forgetWeights();
  const r = await checkBatch(w.env, 'owner', { items: [PQ, PC] }, w.fetcher, { owner: true });
  const items = JSON.parse(await r.text()).items;
  ok(items[0].verdict === 'verified' && items[1].verdict === 'verified' && items[1].votes.length === 3,
     `a mixed batch, each stated word for word, verifies both kinds (${items.map(i => i.verdict + ' ' + JSON.stringify(i.proof))})`);
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
  ok(item.votes.map(v => v.model).join() === 'gemini-3.5-flash-lite,@cf/openai/gpt-oss-120b' && !w.log.includes('gemini:gemma-4-31b-it'),
     'Gemma is not asked: the second voter is gpt-oss, a second family, and Google has answered');
  ok(item.verdict === 'check' && item.reasons.includes('Not yet passed by three model families.'), 'two families are not enough: Check this, saying so');
  w.release();
}
{
  // only one family to ask: one vote, never Verified
  const w = world({ ACCURACY_VOTERS: 'gemini:gemini-3.5-flash-lite,gemini:gemma-4-31b-it' });
  forgetWeights();
  const r = await checkBatch(w.env, 'owner', { items: [C1] }, w.fetcher, { owner: true });
  const item = JSON.parse(await r.text()).items[0];
  ok(item.votes.length === 1 && item.verdict === 'check', 'one family: Gemma adds no witness and is not asked; Check this');
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

// MARK: less waiting (1 Oct): the first three voters at once, a slow one hedged
{
  // each checker takes 300 ms: asked one after another the batch would take 900 ms or more
  const w = world();
  forgetWeights();
  const slow = async (url, init) => {
    if (url.includes('firebasevertexai')) await sleep(300);
    return w.fetcher(url, init);
  };
  const env = { ...w.env, AI: { run: async (model, input) => { await sleep(300); return w.env.AI.run(model, input); } } };
  const t0 = Date.now();
  const r = await checkBatch(env, 'owner', { items: [C1] }, slow, { owner: true });
  const took = Date.now() - t0;
  const item = JSON.parse(await r.text()).items[0];
  ok(item.votes.length === 3 && took < 550, `three checkers asked at once: about one call's wait, not three (${took} ms)`);
  w.release();
}
{
  // one checker hangs: after the hedge delay another of its family is asked, and the first answer from each family stands
  const w = world({ ACCURACY_HEDGE_MS: '100' }, { hang: new Set(['gemini-3.5-flash-lite']) });
  forgetWeights();
  const t0 = Date.now();
  const r = await Promise.race([checkBatch(w.env, 'owner', { items: [C1] }, w.fetcher, { owner: true }), sleep(3000).then(() => null)]);
  const took = Date.now() - t0;
  const item = r ? JSON.parse(await r.text()).items[0] : null;
  ok(item && item.votes.length === 3 && !item.votes.some(v => v.model === 'gemini-3.5-flash-lite') && took < 1500,
     `a hung checker is hedged: three families answer and the batch goes on (${took} ms)`);
  ok(item?.votes.some(v => v.model === 'gemma-4-31b-it'), 'the hedge asked Gemma, standing in for the slow Google voter');
  w.release();
}

console.log(failures ? `\n${failures} STAGE TEST FAILURE(S)` : '\nALL STAGE TESTS PASS');
process.exit(failures ? 1 : 0);
