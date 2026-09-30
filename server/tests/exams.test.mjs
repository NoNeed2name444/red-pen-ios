// The exam catalogue as the server holds it, the exam-style exemplars and
// their build, the per-batch exemplar placeholder in jobs, the stricter
// accuracy cut-offs for management questions, and the per-exam report of the
// accuracy model's training.
//
// Run: node server/tests/exams.test.mjs

import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { EXAMS, DOMAINS, exam, classifyDomain, exemplarsFor, exemplarBlock, fillExemplars, formatRules, examsRoute } from '../exams.js';
import { EXEMPLARS } from '../exam-exemplars.js';
import { fnv, fromMedQA, fromMedMCQA, buildIndex, swiftSource, jsSource, offsets } from '../bench/exam-exemplars.mjs';
import { fill } from '../jobs.js';
import { isManagement, stricter, examWeights, DEFAULT_WEIGHTS, verdict } from '../accuracy-model.js';
import { describe } from '../accuracy.js';
import { normaliseMedQA, normaliseMedMCQA, variants, sliceMetrics, examMetrics, examSlice, train, reportMarkdown } from '../bench/train-accuracy.mjs';

const here = dirname(fileURLToPath(import.meta.url));
let failures = 0;
const ok = (cond, what) => { console.log((cond ? 'ok   ' : 'FAIL ') + what); if (!cond) failures++; };

// MARK: the catalogue agrees with the app's
{
  const swift = readFileSync(join(here, '..', '..', 'ios', 'RedPen', 'Shared', 'Exam', 'ExamCatalog.swift'), 'utf8');
  const ids = [...swift.matchAll(/\bid: "([A-Za-z0-9]+)"/g)].map(m => m[1]);
  const gulfIds = [...swift.matchAll(/gulf\("([a-z]+)"/g)].map(m => m[1]);
  const appIds = [...ids, ...gulfIds].sort();
  ok(appIds.length >= 20, `the app lists ${appIds.length} exams`);
  ok(JSON.stringify(appIds) === JSON.stringify(EXAMS.map(e => e.id).sort()), 'the server and the app list the same exams');
  // each full entry: its options, exemplar source and strictness match
  const entries = swift.split('static let ').slice(1);
  let checked = 0;
  for (const chunk of entries) {
    const id = chunk.match(/\bid: "([A-Za-z0-9]+)"/)?.[1];
    if (!id) continue;
    const e = exam(id);
    const options = Number(chunk.match(/\boptions: (\d)/)?.[1]);
    const strict = Number(chunk.match(/accuracyStrictness: ([\d.]+)/)?.[1]);
    const source = chunk.match(/exemplars: \.(\w+)/)?.[1];
    const map = { medqaStep1: 'medqa-step1', medqaStep23: 'medqa-step23', medmcqa: 'medmcqa' };
    ok(e && e.options === options && e.strict === strict && e.exemplars === map[source],
       `${id}: ${options} options, strictness ${strict}, ${map[source]} on both sides`);
    checked++;
  }
  const gulf = swift.slice(swift.indexOf('private static func gulf'));
  const gulfOptions = Number(gulf.match(/options: (\d)/)?.[1]);
  for (const id of gulfIds) ok(exam(id).options === gulfOptions && exam(id).strict === 0.2, `${id}: the Gulf format on both sides`);
  ok(checked + gulfIds.length === EXAMS.length, 'every exam compared');
  const domains = [...swift.matchAll(/^\s+case ([a-z, A-Z]+)$/gm)].flatMap(m => m[1].split(',').map(s => s.trim()));
  ok(DOMAINS.every(d => domains.includes(d)) && domains.filter(d => DOMAINS.includes(d)).length === DOMAINS.length,
     'the topic areas are the same on both sides');
}

// MARK: every exam's prompt facts are sane
{
  for (const e of EXAMS) {
    ok([4, 5].includes(e.options) && e.words[0] < e.words[1] && e.recall >= 0 && e.recall <= 1 && e.strict >= 0 && e.strict <= 1,
       `${e.id}: sane format`);
    const rules = formatRules(e.id);
    ok(rules.includes(`Exactly ${e.options} options`) && rules.includes(e.name), `${e.id}: format rules name the exam and its options`);
  }
  ok(exam('step2ck').strict > exam('step1').strict && exam('step3').strict >= exam('step2ck').strict, 'Step 2 CK and 3 are stricter than Step 1');
  ok(exam('neetpg').options === 4 && exam('plab1').options === 5, 'NEET-PG has four options, PLAB five');
  ok(formatRules('nope') === '' && exam('nope') === null, 'an unknown exam has no rules');
}

// MARK: topics
{
  ok(classifyDomain('A 23-year-old pregnant woman at 22 weeks gestation has burning on urination') === 'obstetrics', 'a pregnant patient is obstetrics');
  ok(classifyDomain('Nerve supply of the deltoid muscle is') === 'anatomy', 'a nerve supply is anatomy');
  ok(classifyDomain('A 45-year-old with 30 minutes of crushing chest pain; ECG shows ST elevation in the anterior leads; troponin raised') === 'cardio', 'ST elevation is cardiovascular');
  ok(classifyDomain('A 30-year-old man says his ear hurts') === 'ent' && classifyDomain('A 30-year-old man') === null, '"ear" is not found in "year"');
  ok(classifyDomain('') === null, 'nothing is nothing');
}

// MARK: the exemplar index
{
  ok(EXEMPLARS.licences.length === 2 && EXEMPLARS.licences.some(l => l.includes('MIT')) && EXEMPLARS.licences.some(l => l.includes('Apache-2.0')),
     'the bundled index names both licences');
  const all = Object.values(EXEMPLARS.sources).flatMap(b => Object.values(b).flat());
  ok(all.length >= 60, `${all.length} exemplars bundled`);
  ok(all.every(x => /^[0-9a-f]{8}$/.test(x.id) && x.s.length <= 720 && x.o.length >= 4 && x.a >= 0 && x.a < x.o.length),
     'every exemplar is hashed, short enough and keyed');
  ok(new Set(all.map(x => x.id)).size === all.length, 'no exemplar twice');
  ok(Object.keys(EXEMPLARS.sources).sort().join() === 'medmcqa,medqa-step1,medqa-step23', 'the three style sources');
  ok(Object.values(EXEMPLARS.sources).every(b => Object.keys(b).every(d => DOMAINS.includes(d))), 'filed only under known topics');
  const banned = /uworld|amboss|passmedicine|pastest|kaplan|onexamination/i;
  ok(!banned.test(JSON.stringify(EXEMPLARS)), 'nothing names a copyrighted bank');
}

// MARK: retrieval
{
  const index = { version: 't', licences: [], sources: {
    'medqa-step23': {
      cardio: [{ id: 'c1', s: 'Cardio one', o: ['a', 'b', 'c', 'd'], a: 0 }, { id: 'c2', s: 'Cardio two', o: ['a', 'b', 'c', 'd'], a: 1 },
               { id: 'c3', s: 'Cardio three', o: ['a', 'b', 'c', 'd'], a: 2 }],
      resp: [{ id: 'r1', s: 'Resp one', o: ['a', 'b', 'c', 'd'], a: 3 }],
    },
    medmcqa: { anatomy: [{ id: 'a1', s: 'Anatomy one', o: ['a', 'b', 'c', 'd'], a: 0 }] },
  } };
  const r0 = exemplarsFor('step2ck', 'cardio', 2, 0, index).map(x => x.id);
  const r1 = exemplarsFor('step2ck', 'cardio', 2, 1, index).map(x => x.id);
  ok(r0.join() === 'c1,c2' && r1.join() === 'c3,c1', 'the topic\'s own exemplars first, rotating by round');
  ok(exemplarsFor('step2ck', 'gi', 2, 0, index).map(x => x.id).join() === 'c1,c2', 'a topic with none borrows the exam\'s others');
  ok(exemplarsFor('neetpg', 'cardio', 2, 0, index).map(x => x.id).join() === 'a1', 'NEET-PG draws only on MedMCQA');
  ok(exemplarsFor('step2ck', 'cardio', 9, 0, index).length === 3, 'never more than three');
  ok(exemplarsFor('nope', 'cardio', 2, 0, index).length === 0, 'an unknown exam gets none');
  const block = exemplarBlock('step2ck', 'resp', 1, 0, index);
  ok(block.includes('Example 1: Resp one') && block.includes('  D. d') && block.includes('Answer: D') && block.includes('never copy'.replace('never', 'Never')),
     'the block shows stem, options, key and the warning');
  const text = 'Write.\n{{EXEMPLARS:step2ck:cardio:2}}\nNow.';
  ok(fillExemplars(text, 0, index).includes('Cardio one') && fillExemplars(text, 1, index).includes('Cardio three'), 'the placeholder is filled, differently each round');
  ok(fillExemplars('{{EXEMPLARS:nope::2}}', 0, index) === '', 'an unknown exam leaves nothing behind');
  ok(fillExemplars('plain', 0, index) === 'plain', 'no placeholder, no change');
  // a job's prompt: filled with the real index, and the lecture never read as a placeholder
  const filled = fill('A {{EXEMPLARS:step2ck:cardio:1}} B {{SOURCE}}', 'lecture says {{EXEMPLARS:step1:cardio:1}}', [], 0);
  ok(filled.includes('STYLE EXAMPLES') && filled.endsWith('lecture says {{EXEMPLARS:step1:cardio:1}}'), 'jobs fill the exemplars before the lecture goes in');
}

// MARK: the route
{
  const cat = await examsRoute('/exams/catalogue').json();
  ok(cat.exams.length === EXAMS.length && cat.exams.every(e => e.id && e.options), 'the catalogue route lists every exam');
  const ex = examsRoute('/exams/exemplars', { exam: 'step2ck', topic: 'chest pain with ST elevation on the ECG', n: 2 });
  const body = await ex.json();
  ok(ex.status === 200 && body.domain === 'cardio' && body.items.length === 2 && body.licences.length === 2, 'the exemplars route picks by topic');
  ok(examsRoute('/exams/exemplars', { exam: 'nope' }).status === 400, 'an unknown exam is refused');
}

// MARK: the build
{
  ok(fnv('abc') === fnv('abc') && fnv('abc') !== fnv('abd') && /^[0-9a-f]{8}$/.test(fnv('x')), 'the hash is stable and short');
  const long = 'A 54-year-old man comes to the emergency department because of crushing chest pain for 40 minutes. '.repeat(3);
  const q = fromMedQA({ question: long, options: { A: 'Aspirin', B: 'Heparin', C: 'Alteplase', D: 'Morphine' }, answer_idx: 'A', meta_info: 'step2&3' });
  ok(q && q.source === 'medqa-step23' && q.item.a === 0 && q.item.o.length === 4 && ['emergency', 'cardio'].includes(q.domain), 'a Step 2&3 vignette is kept whole');
  ok(fromMedQA({ question: 'Too short?', options: { A: 'a', B: 'b', C: 'c', D: 'd' }, answer_idx: 'A', meta_info: 'step1' }) === null, 'a stem too short for a vignette is skipped');
  ok(fromMedQA({ question: long + ' What is shown in the image?', options: { A: 'a', B: 'b', C: 'c', D: 'd' }, answer_idx: 'A', meta_info: 'step1' }) === null, 'an item that needs a picture is skipped');
  ok(fromMedQA({ question: long, options: { A: 'a', B: 'b', C: 'c', D: 'All of the above' }, answer_idx: 'A', meta_info: 'step1' }) === null, '"all of the above" is skipped');
  const m = fromMedMCQA({ question: 'Drug of choice for absence seizures in children is', opa: 'Ethosuximide', opb: 'Phenytoin', opc: 'Carbamazepine', opd: 'Phenobarbitone', cop: 0, choice_type: 'single', subject_name: 'Pharmacology' });
  ok(m && m.source === 'medmcqa' && m.domain === 'pharmacology', 'a MedMCQA one-liner is filed by subject');
  ok(fromMedMCQA({ question: 'Which tooth erupts first?', opa: 'a', opb: 'b', opc: 'c', opd: 'd', cop: 0, choice_type: 'single', subject_name: 'Dental' }) === null, 'dentistry is left out');
  const cands = [m, { ...m, item: { ...m.item } }, { ...m, item: { ...m.item, id: 'ffffffff' } }, { ...m, item: { ...m.item, id: '00000000' } }];
  const idx = buildIndex(cands, { perDomain: 2, version: 'v' });
  ok(idx.sources.medmcqa.pharmacology.length === 2 && idx.sources.medmcqa.pharmacology[0].id === '00000000', 'two per topic, chosen by hash, no repeats');
  ok(swiftSource(idx).includes('static let json: String = #"""') && swiftSource(idx).includes('"""#'), 'the Swift file is a raw string');
  ok(jsSource(idx).startsWith('// Generated') && jsSource(idx).includes('export const EXEMPLARS'), 'the JS file exports the index');
  const o = offsets(10178, 16, 1);
  ok(o.length === 16 && new Set(o).size === 16 && o.every(x => x % 100 === 0 && x < 10178), 'page offsets are distinct and in range');
}

// MARK: stricter for management questions
{
  ok(isManagement('What is the most appropriate next step in management?') && isManagement('Which is the drug of choice?'), 'management lead-ins are recognised');
  ok(!isManagement('Which enzyme is deficient?'), 'a mechanism question is not management');
  const base = { verified: 0.85, flagged: 0.4 };
  ok(stricter(base, 0) === base, 'no strictness, no change');
  const s5 = stricter(base, 0.5);
  ok(s5.verified === 0.92 && s5.flagged === 0.45, `half strict: ${JSON.stringify(s5)}`);
  const s1 = stricter(base, 1);
  ok(s1.verified === 0.99 && s1.flagged === 0.5 && s1.flagged < s1.verified, 'fully strict stays below 0.99 and keeps a gap');
  const mgmt = { kind: 'mcq', stem: 'What is the next best step in management?', options: ['a', 'b'], key: 0 };
  const mech = { kind: 'mcq', stem: 'What is the mechanism?', options: ['a', 'b'], key: 0 };
  ok(examWeights(DEFAULT_WEIGHTS, mgmt, 0.5).thresholds.verified === 0.92 && examWeights(DEFAULT_WEIGHTS, mech, 0.5) === DEFAULT_WEIGHTS,
     'only management items get the stricter cut-off');
  const f = { no_models: 0, rule_severe: 0 };
  ok(verdict(0.9, f, DEFAULT_WEIGHTS) === 'verified' && verdict(0.9, f, examWeights(DEFAULT_WEIGHTS, mgmt, 0.5)) === 'check',
     'P = 0.9 is Verified for Step 1 but Check this for a Step 2 CK management question');
  const d = describe({ ...mgmt, id: 'x', source: '', explanation: '' }, 'h', null, DEFAULT_WEIGHTS, 0.5);
  ok(d.verdict === 'unchecked', 'describe takes the strictness and still says unchecked with no votes');
}

// MARK: training per exam
{
  ok(normaliseMedQA({ question: 'q', options: { A: 'a', B: 'b' }, answer_idx: 'A', meta_info: 'step1' }, 0).slice === 'usmle-step1', 'a Step 1 row is sliced as Step 1');
  ok(normaliseMedQA({ question: 'q', options: { A: 'a', B: 'b' }, answer_idx: 'A', meta_info: 'step2&3' }, 0).slice === 'usmle-step2-3', 'a Step 2&3 row is sliced as Step 2-3');
  ok(normaliseMedMCQA({ question: 'q', opa: 'a', opb: 'b', opc: 'c', opd: 'd', cop: 1 }, 0).slice === 'neetpg-aiims', 'MedMCQA is the NEET-PG / AIIMS slice');
  const q = { qid: 'medqa:1', stem: 'What is the most appropriate next step in management?', options: ['a', 'b', 'c', 'd'], key: 0, explanation: '', slice: 'usmle-step2-3' };
  ok(variants(q, 0).every(e => e.slice === 'usmle-step2-3' && e.mgmt === true), 'every variant carries its slice and whether it is management');
  ok(examSlice(exam('step2ck')) === 'usmle-step2-3' && examSlice(exam('neetpg')) === 'neetpg-aiims' && examSlice(exam('comlex1')) === 'usmle-step1', 'each exam reads its style\'s slice');
  // synthetic results: two slices, management and not
  const results = [];
  for (let i = 0; i < 80; i++) {
    const label = i % 2;
    const slice = i % 4 < 2 ? 'usmle-step2-3' : 'neetpg-aiims';
    const conf = label ? 0.9 : 0.1;
    results.push({ id: `r${i}`, group: `g${Math.floor(i / 2)}`, variant: label ? 'correct' : 'swapped-key', label, weight: 1, slice, mgmt: i % 3 === 0,
                   features: { bias: 1, vote_pass: label ? 1 : (i % 10 === 0 ? 1 : 0), vote_flag: label ? 0 : 1, vote_risk: 1 - conf, no_models: 0 } });
  }
  const t = train(results, { version: 'test' });
  ok(t && t.bySlice['usmle-step2-3'].n === 40 && t.bySlice['neetpg-aiims'].n === 40, 'the fit reports each slice');
  ok(t.byExam.step2ck.slice === 'usmle-step2-3' && t.byExam.step2ck.cutoff >= t.weights.thresholds.verified, 'Step 2 CK is judged on its slice at its stricter cut-off');
  ok(t.byExam.step2ck.own.verified <= t.byExam.step2ck.shared.verified, 'a stricter cut-off never verifies more');
  const md = reportMarkdown(t);
  ok(md.includes('By exam slice') && md.includes('Management questions, per exam') && md.includes('step2ck'), 'the report shows both tables');
  ok(!md.includes('| step1 |'), 'an exam with no stricter cut-off is left out of the management table');
  const sm = sliceMetrics([{ slice: 'a' }, { slice: 'a' }], [0.9, 0.1], [1, 0], { verified: 0.85, flagged: 0.4 });
  ok(sm.a.n === 2 && sm.a.verifiedRecall === 1 && sm.a.flaggedRecall === 1, 'slice metrics count verified and flagged');
  const em = examMetrics([{ slice: 'usmle-step2-3', mgmt: true }, { slice: 'usmle-step2-3', mgmt: true }], [0.9, 0.95], [1, 0], { verified: 0.85, flagged: 0.4 }, [exam('step2ck')]);
  ok(em.step2ck.shared.verified === 2 && em.step2ck.own.verified === 1 && em.step2ck.own.precision === 0, 'at 0.92 the 0.9 item is no longer verified');
}

console.log(failures ? `${failures} FAILED` : 'all passed');
process.exit(failures ? 1 : 0);
