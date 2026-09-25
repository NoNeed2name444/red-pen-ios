// The accuracy engine: its rules, its model (inference, fitting, calibration),
// the training set it learns from, and its routes against a real SQLite and
// fake models - who votes, when a third is asked, what is cached, what is refused.
//
// Run: node server/tests/accuracy.test.mjs

import { DatabaseSync } from 'node:sqlite';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { ruleHits, doses, labValues, explainedAnswer, sourceMatch, itemText, DRUGS, LABS } from '../accuracy-rules.js';
import { FEATURES, DEFAULT_WEIGHTS, features, predict, verdict, validWeights, fit, crossValidate, metrics, thresholds, auc, probability } from '../accuracy-model.js';
import { checkBatch, report, modelWeights, setWeights, listReports, itemTerms, parseVotes, disagree, votersFor, suggestedFix, itemHash, cleanItem, forgetWeights } from '../accuracy.js';
import { normaliseMedQA, normaliseMedMCQA, variants, corrupt, reportedExamples, train, reportMarkdown } from '../bench/train-accuracy.mjs';

const here = dirname(fileURLToPath(import.meta.url));
let failures = 0;
const ok = (cond, what) => { console.log((cond ? 'ok   ' : 'FAIL ') + what); if (!cond) failures++; };
const rules = item => ruleHits(item).map(h => `${h.rule}:${h.severity}`);
const has = (item, id) => rules(item).some(r => r.startsWith(id));

// MARK: rules
{
  ok(has({ kind: 'card', text: 'Give paracetamol 10 g orally for fever.' }, 'dose-range:severe'), 'paracetamol 10 g is a severe dose error');
  ok(!has({ kind: 'card', text: 'Metformin 500 mg twice daily with meals.' }, 'dose-range'), 'metformin 500 mg is fine');
  ok(has({ kind: 'card', text: 'Digoxin 25 mg once daily for rate control.' }, 'dose-range:severe'), 'digoxin 25 mg (a microgram/milligram slip) is severe');
  ok(!has({ kind: 'card', text: 'Adrenaline 0.5 mg IM for anaphylaxis.' }, 'dose-range'), 'adrenaline 0.5 mg IM is fine');
  ok(!has({ kind: 'card', text: 'Vancomycin 15 mg/kg every 12 hours.' }, 'dose-range'), 'a per-kg dose is left alone');
  ok(doses('500 mg of amoxicillin three times a day')[0]?.mg === 500, 'a dose before the drug name is read');
  ok(doses('levothyroxine 100 micrograms daily')[0]?.mg === 0.1, 'micrograms are converted');
  ok(has({ kind: 'card', text: 'Atorvastatin 800 mg at night.' }, 'dose-range:severe'), 'atorvastatin 800 mg is severe');
  ok(has({ kind: 'card', text: 'Fasting glucose 5.5 mg/dL is normal.' }, 'lab-implausible'), 'glucose 5.5 mg/dL is not a possible value (a unit error)');
  ok(!has({ kind: 'card', text: 'Sodium 128 mmol/L indicates hyponatraemia.' }, 'lab'), 'sodium 128 mmol/L is fine');
  ok(has({ kind: 'card', text: 'Sodium 140 mg/dL is normal.' }, 'lab-unit'), 'sodium in mg/dL is the wrong unit');
  ok(has({ kind: 'card', text: 'Normal potassium is 5.5-7.5 mmol/L.' }, 'reference-range:severe'), 'a wrong reference range is severe');
  ok(!has({ kind: 'card', text: 'Normal potassium is 3.5-5.0 mmol/L.' }, 'reference-range'), 'the right reference range is not flagged');
  ok(labValues('pH 7.21 and PaCO2 60 mmHg').length === 2, 'pH and PaCO2 are read');
  ok(has({ kind: 'card', text: 'In SIADH sodium is low. Sodium is elevated in SIADH.' }, 'direction-conflict'), 'one analyte both raised and lowered');
  ok(!has({ kind: 'card', text: 'Vitamin K 10 mg IV reverses warfarin.' }, 'lab'), 'vitamin K is not read as potassium');

  const q = { kind: 'mcq', stem: 'A 60-year-old man has crushing chest pain. Which drug reduces mortality first?',
    options: ['Aspirin', 'Morphine', 'Oxygen', 'Nitrates', 'Furosemide'], key: 0,
    explanation: 'Aspirin reduces mortality in acute coronary syndrome.' };
  ok(ruleHits(q).length === 0, 'a clean question has no rule hits');
  ok(has({ ...q, explanation: 'The correct answer is B. Morphine relieves pain.' }, 'key-explanation-conflict:severe'), 'an explanation naming another letter conflicts with the key');
  ok(has({ ...q, explanation: 'Morphine is the correct answer here.' }, 'key-explanation-conflict'), 'or naming another option by its words');
  ok(has({ ...q, explanation: 'Aspirin is not the correct answer here.' }, 'key-called-wrong'), 'an explanation calling the key wrong');
  ok(has({ ...q, options: ['Aspirin', 'aspirin', 'Oxygen', 'Nitrates', 'Furosemide'] }, 'duplicate-option:severe'), 'a duplicate of the key is severe');
  ok(has({ ...q, options: ['Aspirin', 'All of the above', 'Oxygen', 'Nitrates', 'None of the above'] }, 'non-answer-position'), '"all of the above" not last');
  ok(has({ ...q, options: ['Aspirin', 'Morphine', 'Oxygen', 'None of the above', 'All of the above'], key: 4 }, 'all-above-contradiction'), '"all of the above" keyed beside "none of the above"');
  ok(has({ ...q, key: 7 }, 'no-key:severe'), 'a key outside the options');
  ok(has({ kind: 'mcq', stem: 'A woman has sodium 118 mmol/L after a marathon. What is the cause?', options: ['Water excess', 'Salt loss'], key: 0,
            explanation: 'Her sodium of 128 mmol/L reflects water excess.' }, 'numbers-disagree'), 'the stem and explanation quote different values');
  ok(has({ kind: 'mcq', stem: 'Which is NOT a feature of nephrotic syndrome?', options: ['Haematuria', 'Proteinuria'], key: 0,
            explanation: 'Haematuria is a characteristic feature.' }, 'negation-mismatch'), 'an EXCEPT question whose explanation calls the key true');
  ok(explainedAnswer('Ans. is the correct answer: (C) because', ['a', 'b', 'c']) === 2, 'the explanation\'s letter is read');
  ok(sourceMatch({ kind: 'card', text: 'Aspirin reduces mortality' }, 'aspirin reduces mortality in ACS') === 1 && sourceMatch({ kind: 'card', text: 'x' }, '') === null, 'the source match');
}

// MARK: the model
{
  const pass = features({ kind: 'mcq', votes: [{ risk: 1, answer: 'A', evidence: 'supports' }, { risk: 1, answer: 'A', evidence: 'supports' }], evidenceCount: 3, sourceMatch: 0.7, keyLetter: 'A' });
  const p1 = predict(pass);
  ok(p1 > 0.95 && verdict(p1, pass) === 'verified', `two passing votes with support are Verified (${p1.toFixed(3)})`);
  const bad = features({ kind: 'mcq', votes: [{ risk: 4, answer: 'B', evidence: 'contradicts' }, { risk: 4, answer: 'B', evidence: 'contradicts' }], keyLetter: 'A', sourceMatch: 0.7 });
  ok(verdict(predict(bad), bad) === 'flagged', 'two flagging votes are Flagged');
  const split = features({ kind: 'mcq', votes: [{ risk: 1, answer: 'A', evidence: 'none' }, { risk: 3, answer: 'A', evidence: 'none' }], keyLetter: 'A', sourceMatch: 0.5 });
  ok(verdict(predict(split), split) === 'check', 'a split vote is Check this');
  const none = features({ kind: 'card', rules: [] });
  ok(verdict(predict(none), none) === 'unchecked', 'rules alone never verify');
  const ruled = features({ kind: 'card', rules: [{ severity: 'severe' }] });
  ok(verdict(predict(ruled), ruled) === 'flagged', 'a severe rule hit with no model is Flagged');
  const passRuled = features({ kind: 'card', rules: [{ severity: 'severe' }], votes: [{ risk: 1, evidence: 'supports' }, { risk: 1, evidence: 'supports' }], sourceMatch: 1, evidenceCount: 5 });
  ok(verdict(predict(passRuled), passRuled) !== 'verified', 'a severe rule hit is never Verified');
  ok(features({ kind: 'mcq', votes: [{ risk: 1, answer: 'C' }, { risk: 1, answer: 'A' }], keyLetter: 'A' }).key_disagree === 0.5, 'key disagreement is the share answering otherwise');
  ok(validWeights(DEFAULT_WEIGHTS) && !validWeights({ ...DEFAULT_WEIGHTS, weights: [1] }) && !validWeights({ ...DEFAULT_WEIGHTS, thresholds: { verified: 0.3, flagged: 0.5 } }), 'weights are validated');

  // the phone carries the same prior
  const swift = readFileSync(join(here, '..', '..', 'ios', 'RedPen', 'Shared', 'Accuracy', 'AccuracyModel.swift'), 'utf8');
  const literal = swift.split('// BEGIN DEFAULT WEIGHTS')[1].split('// END DEFAULT WEIGHTS')[0];
  const onPhone = JSON.parse(literal.slice(literal.indexOf('"""') + 3, literal.lastIndexOf('"""')));
  ok(JSON.stringify(Object.keys(onPhone.weights)) === JSON.stringify(FEATURES) && JSON.stringify(FEATURES.map(f => onPhone.weights[f])) === JSON.stringify(DEFAULT_WEIGHTS.weights)
     && onPhone.thresholds.verified === DEFAULT_WEIGHTS.thresholds.verified && onPhone.thresholds.flagged === DEFAULT_WEIGHTS.thresholds.flagged
     && onPhone.version === DEFAULT_WEIGHTS.version, 'the app\'s bundled weights are the server\'s');

  // and the same rule tables
  const rulesSwift = readFileSync(join(here, '..', '..', 'ios', 'RedPen', 'Shared', 'Accuracy', 'AccuracyRules.swift'), 'utf8');
  const table = (begin, end) => rulesSwift.split(begin)[1].split(end)[0].split('"""')[1].replace(/\s*\n\s*/g, '').split(';').filter(Boolean)
    .map(e => { const at = e.lastIndexOf('='); return [e.slice(0, at).replace(/~/g, '/'), e.slice(at + 1).split(':').map(Number)]; });
  const drugs = Object.fromEntries(table('// BEGIN DRUGS', '// END DRUGS'));
  const labs = {};
  for (const [k, v] of table('// BEGIN LABS', '// END LABS')) { const [a, u] = k.split('|'); (labs[a] ||= {})[u] = v; }
  ok(JSON.stringify(drugs) === JSON.stringify(DRUGS) && JSON.stringify(labs) === JSON.stringify(LABS), 'the app\'s dose and lab tables are the server\'s');
}

// MARK: fitting and calibration
{
  // a known model: P = sigmoid(-1 + 3 x1 - 2 x2)
  let s = 1;
  const rand = () => { s = (s * 16807) % 2147483647; return s / 2147483647; };
  const X = [], y = [];
  for (let i = 0; i < 3000; i++) {
    const x = [1, rand(), rand()];
    const p = 1 / (1 + Math.exp(-(-1 + 3 * x[1] - 2 * x[2])));
    X.push(x); y.push(rand() < p ? 1 : 0);
  }
  const beta = fit(X, y, { lambda: 0.01 });
  ok(Math.abs(beta[0] + 1) < 0.3 && Math.abs(beta[1] - 3) < 0.4 && Math.abs(beta[2] + 2) < 0.4, `the fit recovers the true weights (${beta.map(b => b.toFixed(2))})`);
  const cv = crossValidate(X, y, { k: 5, lambda: 0.01 });
  const m = metrics(cv, y);
  ok(m.ece < 0.05, `held-out predictions are calibrated (ECE ${m.ece.toFixed(3)})`);
  ok(m.auc > 0.65 && m.auc < 0.9, `and discriminate (AUC ${m.auc.toFixed(3)})`);
  ok(auc([0.1, 0.2, 0.8, 0.9], [0, 0, 1, 1]) === 1 && auc([0.9, 0.8, 0.2, 0.1], [0, 0, 1, 1]) === 0 && auc([0.5, 0.5], [0, 1]) === 0.5, 'AUC at its extremes and on a tie');
  const bins = metrics([0.05, 0.95, 0.95, 0.95], [0, 1, 1, 0]);
  ok(Math.abs(bins.ece - 0.225) < 1e-9 && bins.bins[9].n === 3, 'ECE by hand');
  const cut = thresholds(cv, y);
  ok(cut.flagged < cut.verified && cut.verifiedStats.precision >= 0.97 || cut.verified === 0.99, 'Verified is cut where it is at least 97% precise');
  ok(Math.abs(probability([0, 1], [1, 0]) - 0.5) < 1e-12, 'probability of a zero score is a half');
  // all-zero feature column: still solvable
  const b2 = fit([[1, 0], [1, 0], [1, 0], [1, 0]], [1, 0, 1, 1]);
  ok(Number.isFinite(b2[0]) && b2[1] === 0, 'an unused feature gets weight 0');
}

// MARK: the training set
{
  const mq = normaliseMedQA({ question: 'Q?', options: { A: 'a', B: 'b', C: 'c', D: 'd' }, answer_idx: 'C' }, 4);
  ok(mq.key === 2 && mq.options.length === 4 && mq.qid === 'medqa:4', 'MedQA rows');
  const mm = normaliseMedMCQA({ id: 'x1', question: 'Q?', opa: 'a', opb: 'b', opc: 'c', opd: 'd', cop: 1, choice_type: 'single', exp: 'Because b.' }, 0);
  ok(mm.key === 1 && mm.explanation === 'Because b.', 'MedMCQA rows');
  ok(normaliseMedMCQA({ question: 'Q', opa: 'a', opb: 'b', opc: 'c', opd: 'd', cop: 1, choice_type: 'multi' }, 0) === null, 'multi-answer MedMCQA rows are skipped');
  ok(corrupt('Give 5 mg daily', 'x', 'y') === 'Give 50 mg daily' && corrupt('Aspirin is first line', 'Aspirin', 'Morphine') === 'Morphine is first line'
     && corrupt('It is first line', 'zz', 'y') === 'It is not first line' && corrupt('', 'a', 'b') === null, 'explanations are corrupted three ways');
  const q = { qid: 'medmcqa:1', stem: 'Drug of choice for absence seizures?', options: ['Ethosuximide', 'Phenytoin', 'Carbamazepine', 'Gabapentin'], key: 0, explanation: 'Ethosuximide is the drug of choice.' };
  const all = [0, 1, 2, 3, 4, 5, 6, 7].flatMap(i => variants(q, i));
  ok(all.filter(e => e.label === 1).length === all.filter(e => e.label === 0).length, 'right and wrong items are balanced');
  ok(new Set(all.map(e => e.variant)).size === 4, `every wrong variant is used (${[...new Set(all.map(e => e.variant))]})`);
  ok(all.some(e => e.item.kind === 'card') && all.every(e => e.group === 'medmcqa:1'), 'cards too, grouped by question');
  const sw = variants(q, 0).find(e => e.variant === 'swapped-key');
  ok(sw.item.key !== 0 && sw.item.explanation === q.explanation, 'a swapped key keeps the right explanation');
  const we = variants(q, 1).find(e => e.variant === 'wrong-everywhere');
  ok(we.item.source === we.item.explanation && we.item.key !== 0 && we.item.explanation.includes(q.options[we.item.key]) && !we.item.explanation.includes('Ethosuximide'),
     'wrong everywhere: the real explanation with the distractor written in, the "lecture" saying the same');
  const bare = { ...q, qid: 'medqa:2', explanation: '' };
  const bareWrong = variants(bare, 1).find(e => e.label === 0), bareRight = variants(bare, 1).find(e => e.label === 1);
  ok(bareWrong.item.source === '' && bareRight.item.source === '', 'with no explanation, neither twin has a lecture (no shape to learn from)');
  ok(reportedExamples([{ hash: 'h', reports: 1, item: { kind: 'card', text: 'x' } }])[0].weight === 0.5, 'a single report is a half-weight wrong example');

  // train() on synthetic worker results: wrong items get risky votes
  let s = 3;
  const rand = () => { s = (s * 16807) % 2147483647; return s / 2147483647; };
  const results = [];
  for (let i = 0; i < 400; i++) {
    const label = i % 2;
    const risk = () => (label ? (rand() < 0.85 ? 1 : 3) : (rand() < 0.75 ? 4 : 1));
    const votes = [{ risk: risk(), answer: 'A', evidence: label ? 'supports' : 'none' }, { risk: risk(), answer: label ? 'A' : 'B', evidence: 'none' }];
    results.push({ id: `x${i}`, group: `g${i >> 1}`, variant: label ? 'correct' : 'swapped-key', label, weight: 1,
                   features: features({ kind: 'mcq', votes, keyLetter: 'A', sourceMatch: 0.6, evidenceCount: 2 }) });
  }
  const t = train(results, { version: 'test' });
  ok(t && t.cv.auc > 0.9 && t.weights.version === 'test' && validWeights(t.weights), `training fits and validates (held-out AUC ${t?.cv.auc.toFixed(3)})`);
  ok(t.weights.features.length === FEATURES.length && t.cut.verified > t.cut.flagged, 'with every feature and two cut-offs');
  const md = reportMarkdown(t, ['a note']);
  ok(md.includes('Calibration') && md.includes('Verified') && md.includes('a note'), 'the report');
  ok(train(results.slice(0, 5)) === null && reportMarkdown(null).includes('Not enough'), 'too little data: no weights');
}

// MARK: the engine's pure parts
{
  const mcq = cleanItem({ kind: 'mcq', stem: 'A patient with AF on warfarin. Which reverses it fastest?', options: ['Vitamin K', 'Prothrombin complex concentrate'], key: 1, explanation: '' });
  const t = itemTerms(mcq);
  ok(t.queries[0].includes('prothrombin') && t.drugs.includes('warfarin'), 'search terms from the key, and the drugs named');
  ok(itemTerms({ kind: 'card', text: 'Bisoprolol in heart failure\nreduces mortality' }).drugs[0] === 'bisoprolol', 'drug names by table');
  ok(itemTerms({ kind: 'card', text: 'Empagliflozin in heart failure' }).drugs[0] === 'empagliflozin', 'and by suffix');
  const votes = parseVotes('Here: {"items":[{"i":2,"risk":4,"answer":"c","evidence":"contradicts","cites":["S1","bad"],"issues":["wrong"],"fix":{"field":"key","value":"C"}},{"i":1,"risk":"1"}]}', 2);
  ok(votes[1].risk === 4 && votes[1].answer === 'C' && votes[1].cites.join() === 'S1' && votes[1].fix.value === 'C' && votes[0].risk === 1 && votes[0].evidence === 'none', 'votes are parsed item by item');
  ok(parseVotes('no json', 2).every(v => v === null), 'an unreadable reply is no vote');
  ok(disagree([{ risk: 1 }], [{ risk: 4 }]) && !disagree([{ risk: 1, answer: 'A' }], [{ risk: 2, answer: 'A' }]) && disagree([{ risk: 1, answer: 'A' }], [{ risk: 1, answer: 'B' }]), 'disagreement');
  ok(!votersFor({}, 'gpt-oss-120b').some(v => v.includes('gpt-oss')) && votersFor({}, '').length === 4, 'the writing model never votes');
  ok(suggestedFix(mcq, [{ model: 'a', answer: 'A', risk: 4 }, { model: 'b', answer: 'A', risk: 3 }])?.value === 'A', 'voters agreeing on another answer suggest it as the key');
  ok(suggestedFix(mcq, [{ model: 'a', answer: 'A', risk: 4 }, { model: 'b', answer: 'B', risk: 1 }]) === null, 'a split does not');
  ok((await itemHash(mcq)) === (await itemHash({ ...mcq, id: 'other' })) && (await itemHash(mcq)) !== (await itemHash({ ...mcq, key: 0 })), 'the hash is of the content, not the id');
  ok(cleanItem({ kind: 'nope', text: 'x' }) === null && cleanItem({ kind: 'mcq', stem: 'x', options: ['a'] }) === null, 'unreadable items are refused');
  ok(itemText(mcq).includes('Keyed answer: B.'), 'the checker is shown the key');
  const { votePrompt } = await import('../accuracy.js');
  const huge = { kind: 'mcq', stem: 'x'.repeat(3500), options: ['a', 'b'], key: 0, explanation: 'y'.repeat(3500), source: 'z'.repeat(1400) };
  const ev = [...Array(3)].map((_, i) => ({ id: `S${i + 1}`, source: 'Europe PMC', title: 't', text: 'e'.repeat(500) }));
  const chars = votePrompt([...Array(4)].map(() => ({ item: huge, evidence: ev }))).reduce((n, m) => n + m.content.length, 0);
  ok(chars < 24_000, `four of the largest items fit what Workers AI takes (${chars} characters)`);
}

// MARK: the routes
function d1(db) {
  return {
    prepare(sql) {
      const stmt = db.prepare(sql);
      let args = [];
      const api = {
        bind(...a) { args = a; return api; },
        first() { return stmt.get(...args) ?? null; },
        all() { return { results: stmt.all(...args) }; },
        run() { const r = stmt.run(...args); return { meta: { changes: Number(r.changes) } }; },
      };
      return api;
    },
  };
}
function freshEnv(extra = {}) {
  const db = new DatabaseSync(':memory:');
  const sql = readFileSync(join(here, '..', 'schema.sql'), 'utf8').split('\n').map(l => l.replace(/--.*$/, '')).join('\n');
  for (const statement of sql.split(';')) if (statement.trim()) db.exec(statement);
  db.prepare(`INSERT INTO accounts (id, provider, subject, created_at) VALUES ('a1', 'apple', 's1', 0)`).run();
  return { DB: d1(db), db, FIREBASE_API_KEY: 'k', FIREBASE_PROJECT_ID: 'p', APPLE_BUNDLE_ID: 'x', ...extra };
}
const calls = [];
let geminiReply = null, workersReply = null;
const reply = n => JSON.stringify({ items: [...Array(n)].map((_, i) => ({ i: i + 1, risk: 1, answer: 'B', evidence: 'supports', cites: ['S1'], issues: [], fix: null })) });
const fetcher = async (url, init) => {
  if (url.includes('firebasevertexai')) {
    calls.push(`gemini:${url.split('/models/')[1].split(':')[0]}`);
    const text = geminiReply ?? reply(4);
    return new Response(JSON.stringify({ candidates: [{ content: { parts: [{ text }] } }] }), { status: 200 });
  }
  if (url.includes('medlineplus') || url.includes('wsearch.nlm')) return new Response('<nlmSearchResult><document url="https://medlineplus.gov/x.html"><content name="title">Warfarin</content><content name="FullSummary">Warfarin is reversed by vitamin K and PCC.</content></document></nlmSearchResult>', { status: 200 });
  return new Response('{}', { status: 404 });
};
const workers = { run: async (model) => { calls.push(`workers:${model}`); return { choices: [{ message: { content: workersReply ?? reply(4) } }], usage: { prompt_tokens: 10, completion_tokens: 10 } }; } };
const items = [
  { id: 'q1', kind: 'mcq', stem: 'A patient on warfarin bleeds. Best immediate reversal?', options: ['Vitamin K', 'Prothrombin complex concentrate'], key: 1, explanation: 'PCC works fastest.', source: 'PCC reverses warfarin within minutes.' },
  { id: 'c1', kind: 'card', text: 'Q: Antidote to warfarin?\nA: Vitamin K', source: '' },
];
{
  const env = freshEnv({ AI: workers });
  forgetWeights();
  let r = await checkBatch(env, 'a1', { items }, fetcher);
  ok(r.status === 402 && calls.length === 0, 'an account that is not Pro is refused before any model is asked');
  r = await checkBatch(env, 'owner', { items: [...items, ...items, items[0]] }, fetcher, { owner: true });
  ok(r.status === 400, 'more than four items in a batch is refused');

  calls.length = 0;
  r = await checkBatch(env, 'owner', { items }, fetcher, { owner: true });
  let body = await r.json();
  ok(r.status === 200 && body.items.length === 2 && body.items[0].id === 'q1', 'a batch is checked');
  ok(calls.join() === 'gemini:gemini-3.5-flash-lite,workers:@cf/openai/gpt-oss-120b', `two free voters, one call each for the whole batch (${calls.join()})`);
  ok(body.items[0].votes.length === 2 && body.items[0].evidence.some(e => e.url.includes('medlineplus')), 'with both votes and the evidence they were shown');
  ok(body.items[0].verdict === 'verified' && body.items[0].p > 0.85, `agreeing votes with support: Verified (${body.items[0].p})`);
  ok(body.items[1].verdict === 'check' || body.items[1].verdict === 'verified', 'the card is scored too');
  ok(Array.isArray(body.items[0].rules) && typeof body.items[0].features.no_models === 'number', 'rules and features come back for the app to re-score');

  calls.length = 0;
  r = await checkBatch(env, 'owner', { items }, fetcher, { owner: true });
  body = await r.json();
  ok(calls.length === 0 && body.items.every(i => i.cached), 'checked again unchanged: from the cache, no model asked');
  calls.length = 0;
  await checkBatch(env, 'owner', { items: [{ ...items[1], text: items[1].text + ' (edited)' }] }, fetcher, { owner: true });
  ok(calls.length === 2, 'an edited item is checked again');

  // disagreement brings in a third voter; the writer never votes
  calls.length = 0;
  workersReply = JSON.stringify({ items: [{ i: 1, risk: 4, answer: "A", evidence: "contradicts", issues: ["PCC is wrong"], fix: { field: "key", value: "A" } }] });
  r = await checkBatch(env, 'owner', { items: [{ ...items[0], stem: items[0].stem + ' Now.' }], writer: 'gemini-3.5-flash-lite' }, fetcher, { owner: true });
  body = await r.json();
  ok(!calls.includes('gemini:gemini-3.5-flash-lite'), 'the model that wrote the items does not judge them');
  ok(calls.join() === 'workers:@cf/openai/gpt-oss-120b,workers:@cf/nvidia/nemotron-3-120b-a12b', `the next two free voters instead (${calls.join()})`);
  ok(body.items[0].verdict === 'flagged' && body.items[0].fix?.field === 'key' && body.items[0].fix.value === 'A', 'both flag it and agree on the key: Flagged, with the key as the fix');
  workersReply = null;

  calls.length = 0;
  workersReply = JSON.stringify({ items: [{ i: 1, risk: 4, answer: 'A', evidence: 'contradicts', issues: ['wrong'] }] });
  r = await checkBatch(env, 'owner', { items: [{ ...items[0], stem: items[0].stem + ' Today.' }] }, fetcher, { owner: true });
  body = await r.json();
  ok(calls.length === 3, `a split vote asks a third model (${calls.join()})`);
  ok(body.items[0].votes.length === 3 && body.items[0].verdict !== 'verified', 'and the split is not Verified');
  workersReply = null;

  // nobody answers: unchecked, not cached
  calls.length = 0;
  geminiReply = 'nothing'; workersReply = 'nothing';
  r = await checkBatch(env, 'owner', { items: [{ ...items[1], text: 'Q: fresh\nA: x' }] }, fetcher, { owner: true });
  body = await r.json();
  ok(body.items[0].verdict === 'unchecked' && body.items[0].reason === 'busy', 'no readable vote: unchecked');
  geminiReply = null; workersReply = null;
  calls.length = 0;
  await checkBatch(env, 'owner', { items: [{ ...items[1], text: 'Q: fresh\nA: x' }] }, fetcher, { owner: true });
  ok(calls.length === 2, 'and asked again next time');
}
{
  // a Pro account's background share and daily batches
  const env = freshEnv({ AI: workers, OWNER_ACCOUNT_IDS: 'a1', ACCURACY_BACKGROUND_BATCHES: '1', ACCURACY_DAILY_BATCHES: '2' });
  const one = t => ({ items: [{ kind: 'card', text: `Q: ${t}\nA: y` }], priority: 'background' });
  let r = await checkBatch(env, 'a1', one('a'), fetcher);
  ok(r.status === 200, 'a background batch within its share');
  r = await checkBatch(env, 'a1', one('b'), fetcher);
  const b = await r.json();
  ok(r.status === 429 && b.limit === 'day' && b.items[0].verdict === 'unchecked', 'the background share used: 429 with the items unchecked');
  r = await checkBatch(env, 'a1', { items: [{ kind: 'card', text: 'Q: c\nA: y' }] }, fetcher);
  ok(r.status === 200, 'a check the student asked for still goes through');
  r = await checkBatch(env, 'a1', { items: [{ kind: 'card', text: 'Q: d\nA: y' }] }, fetcher);
  ok(r.status === 429, 'until the day\'s batches are used');
  r = await checkBatch(env, 'a1', one('a'), fetcher);
  ok(r.status === 200, 'a cached item costs nothing, even then');

  // free shares: an account whose Flash-Lite share is used votes with the others
  const env2 = freshEnv({ AI: workers, OWNER_ACCOUNT_IDS: 'a1', FREE_MODEL_SHARES: 'gemini-3.5-flash-lite:1' });
  await checkBatch(env2, 'a1', { items: [{ kind: 'card', text: 'Q: share first\nA: y' }] }, fetcher);
  calls.length = 0;
  r = await checkBatch(env2, 'a1', { items: [{ kind: 'card', text: 'Q: share\nA: y' }] }, fetcher);
  ok(r.status === 200 && !calls.includes('gemini:gemini-3.5-flash-lite') && calls.length === 2, `the account's free share is respected (${calls.join()})`);
  // neurons: an account with no Workers AI share left
  const env3 = freshEnv({ AI: workers, OWNER_ACCOUNT_IDS: 'a1', WORKERS_AI_NEURONS_PER_ACCOUNT: '0' });
  calls.length = 0;
  await checkBatch(env3, 'a1', { items: [{ kind: 'card', text: 'Q: neurons\nA: y' }] }, fetcher);
  ok(!calls.some(c => c.startsWith('workers')), 'and so is its share of the free neurons');
}
{
  // reports, the model's weights
  const env = freshEnv();
  let r = await report(env, 'a1', { item: items[1], note: 'The antidote list is incomplete' });
  let b = await r.json();
  ok(r.status === 200 && b.reports === 1 && b.hash.length === 32, 'a report is stored by the item\'s hash');
  env.db.prepare(`INSERT INTO accounts (id, provider, subject, created_at) VALUES ('a2', 'apple', 's2', 0)`).run();
  r = await report(env, 'a2', { item: { ...items[1], id: 'different id' } });
  b = await r.json();
  ok(b.reports === 2, 'two accounts reporting the same content count twice');
  await report(env, 'a2', { item: items[1] });
  ok((await (await report(env, 'a2', { item: items[1] })).json()).reports === 2, 'one account, one report per item');
  ok((await report(env, 'a1', { item: { kind: 'x' } })).status === 400, 'an unreadable report is refused');
  const listed = await (await listReports(env, {})).json();
  ok(listed.reports.length === 1 && listed.reports[0].reports === 2 && listed.reports[0].item.kind === 'card' && !JSON.stringify(listed).includes('a1'), 'the training run sees the items, never who reported them');

  forgetWeights();
  let w = await (await modelWeights(env)).json();
  ok(w.weights.version === DEFAULT_WEIGHTS.version, 'before any training: the bundled prior');
  ok((await setWeights(env, { weights: { ...DEFAULT_WEIGHTS, weights: [1] } })).status === 400, 'malformed weights are refused');
  r = await setWeights(env, { weights: { ...DEFAULT_WEIGHTS, version: 'trained-x' } });
  w = await (await modelWeights(env)).json();
  ok(r.status === 200 && w.weights.version === 'trained-x', 'published weights are served');
}
{
  // the worker's routing: the owner-only routes are hidden from everyone else
  const worker = (await import('../worker.js')).default;
  const env = freshEnv({ OWNER_KEY: 'o'.repeat(40), SESSION_SECRET: 's'.repeat(40) });
  const post = (path, body, key) => worker.fetch(new Request(`https://w${path}`, { method: 'POST', headers: { 'content-type': 'application/json', ...(key ? { authorization: `Bearer ${key}` } : {}) }, body: JSON.stringify(body) }), env);
  ok((await post('/accuracy/model/set', { weights: DEFAULT_WEIGHTS })).status === 404, '/accuracy/model/set needs the owner key');
  ok((await post('/accuracy/reports', {})).status === 404, '/accuracy/reports needs the owner key');
  ok((await post('/accuracy/check', { items })).status === 401, '/accuracy/check needs a session');
  ok((await post('/accuracy/report', { item: items[1] })).status === 401, '/accuracy/report needs a session');
  ok((await post('/accuracy/model', {})).status === 200, '/accuracy/model is open');
  ok((await post('/accuracy/reports', {}, 'o'.repeat(40))).status === 200, 'the owner key lists reports');
}

if (failures) { console.error(`${failures} failed`); process.exit(1); }
console.log('all passed');
