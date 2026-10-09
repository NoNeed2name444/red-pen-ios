// The claim gate (claims.js, plan Task 5d step 3): the Chat-me medical
// verifier's deterministic guards in JavaScript, and what the gate makes of
// them on Stethoscore items against their own lectures.
//
// 1. Conformance: on every pair in claim-vectors.json (the verifier's 35
//    shared conformance vectors and Stethoscore-shaped pairs), each guard
//    gives exactly what the Python gave (bench/claim-vectors.py made it).
// 2. The gate: hard findings only where an item restates its lecture and
//    contradicts it (a flipped negation, another dose, frequency or
//    percentage) or turns it around (higher for lower, rare for common);
//    paraphrases, extra detail and other sentences pass.
// 3. Its work budget: a long page stops at its share of MAX_WORK, saying
//    so; a batch of ordinary items is done well within it; and the worst
//    batch the server takes stays within a few ms of CPU, cold and warm (the
//    Worker's free plan gives a request about 10 ms).
// 4. Python's \b and \w: the cheap ASCII patterns where a text has no other
//    letters, the Unicode ones where it does, with the same answers.
//
// Run: node server/tests/claims.test.mjs

import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { execFileSync } from 'node:child_process';
import * as C from '../claims.js';
import { claimsStage } from '../accuracy.js';

const here = dirname(fileURLToPath(import.meta.url));
let failures = 0;
const ok = (cond, what) => { console.log((cond ? 'ok   ' : 'FAIL ') + what); if (!cond) failures++; };

// MARK: 1. the same answers as the Python

const fx = JSON.parse(readFileSync(join(here, 'claim-vectors.json'), 'utf8'));
const num = (a, b) => (a === null && b === null) || (typeof a === 'number' && typeof b === 'number' && Math.abs(a - b) < 1e-9);
const eq = (a, b) => {
  if (typeof a === 'number' || typeof b === 'number') return num(a, b);
  if (Array.isArray(a) && Array.isArray(b)) return a.length === b.length && a.every((x, i) => eq(x, b[i]));
  if (a && b && typeof a === 'object' && typeof b === 'object') return [...new Set([...Object.keys(a), ...Object.keys(b)])].every(k => eq(a[k], b[k]));
  return a === b;
};
const byValue = (a, b) => a[0] - b[0] || (a[1] < b[1] ? -1 : a[1] > b[1] ? 1 : 0);
/// What bench/claim-vectors.py records about one text, the same way.
const facts = t => ({
  double_negation: C.normalizeDoubleNegation(t), tokens: [...C.tokens(t)].sort(), relation_class: C.relationClass(t),
  numbers: [...C.numbers(t)].sort(), measurements: [...C.measurements(t)].map(s => { const [v, u] = s.split(' '); return [Number(v), u]; }).sort(byValue),
  frequency: C.frequencyMultiplier(t), frequency_guard: C.frequencyMultiplierGuard(t), daily_dose: C.dailyDoseEquivalent(t),
  measurement_kind: C.measurementKind(t), populations: [...C.populations(t)].sort(), conditions: C.conditionSignatures(t).map(s => [...s].sort()),
  scope: C.scopeStrength(t), quantities: C.quantities(t.toLowerCase()), percents: C.percents(t.toLowerCase()),
  dates: C.extractExplicitDates(t), temporal: C.temporalSignature(t), safety: C.safetyRelation(t), atoms: C.decomposeClaim(t),
});
{
  ok(/2f4fd4e/.test(fx.verifier) && fx.pairs.length >= 100, `the vectors: ${fx.pairs.length} pairs from ${fx.verifier}`);
  ok(fx.pairs.filter(p => p.source.startsWith('conformance:')).length === 35, 'all 35 of the verifier\'s shared conformance vectors among them');
  const differences = [];
  for (const p of fx.pairs) {
    const got = {
      verify: C.verify(p.claim, p.evidence), opposite: C.oppositePolarityEntailed(p.claim, p.evidence),
      condition: C.conditionSupported(p.claim, p.evidence), semantic: C.semanticWarnings(p.claim, p.evidence),
      specificity: C.specificityWarnings(p.claim, p.evidence), claim_facts: facts(p.claim), evidence_facts: facts(p.evidence),
    };
    for (const k of Object.keys(got)) {
      if (k.endsWith('facts')) {
        for (const f of Object.keys(got[k])) if (!eq(got[k][f], p[k][f])) differences.push(`${p.source} ${k}.${f}: py ${JSON.stringify(p[k][f])} js ${JSON.stringify(got[k][f])}`);
      } else if (!eq(got[k], p[k])) differences.push(`${p.source} ${k}: py ${JSON.stringify(p[k])} js ${JSON.stringify(got[k])}`);
    }
  }
  for (const d of differences.slice(0, 10)) console.log('     ', d);
  ok(differences.length === 0, `every guard gives the Python's answer on every pair (${differences.length} differences)`);
  ok(fx.entities.every(([a, b, want]) => C.entitiesEquivalent(a, b) === want), 'entity aliases as the Python reads them');
  const labels = new Set(fx.pairs.map(p => p.verify.label));
  ok(labels.has('SUPPORTS') && labels.size >= 2, `the pairs cover more than one verdict (${[...labels].join(', ')})`);
}

// MARK: 2. the gate on items against their own lectures

/// hard: the codes it must find; 'none': no hard finding (soft ones are
/// only reported); 'clean': nothing at all; 'soft': soft findings only.
const CASES = [
  ['negation', 'Metformin is first-line in type 2 diabetes.', { kind: 'card', text: 'Q: Is metformin first-line in type 2 diabetes?\nA: Metformin is not first-line in type 2 diabetes.' }],
  ['dose', 'Amoxicillin 500 mg orally three times daily for otitis media.', { kind: 'card', text: 'Q: Dose of amoxicillin for otitis media?\nA: Amoxicillin 500 micrograms orally tds for otitis media' }],
  ['dose', 'Digoxin 125 micrograms once daily for rate control in AF.', { kind: 'card', text: 'Digoxin 125 mg once daily for rate control in AF.' }],
  ['frequency', 'Amoxicillin 500 mg three times daily for otitis media.', { kind: 'card', text: 'Amoxicillin 500 mg twice daily for otitis media.' }],
  ['percentage', 'Aspirin reduces mortality after myocardial infarction by 23%.', { kind: 'fact', text: 'Aspirin reduces mortality after myocardial infarction by 50%.' }],
  ['negation', 'Insulin lowers blood glucose and raises intracellular potassium uptake.', { kind: 'fact', text: 'Insulin does not lower blood glucose.' }],
  ['negation', 'ACE inhibitors are contraindicated in pregnancy.', { kind: 'mcq', stem: 'Which drug class must be avoided in pregnancy?', options: ['ACE inhibitors', 'Labetalol'], key: 1, explanation: 'ACE inhibitors are not contraindicated in pregnancy.' }],
  ['negation', 'Metformin is first-line in type 2 diabetes.', { kind: 'card', text: 'Metformin isn’t first-line in type 2 diabetes.' }],
  ['negation', 'Metformin is first-line in type 2 diabetes.', { kind: 'card', text: 'Metfor​min is not first-line in type ２ diabetes.' }],
  ['dose', 'Adrenaline 0.5 mg IM is given for anaphylaxis in adults.', { kind: 'card', text: 'Adrenaline 5 mg IM is given for anaphylaxis in adults.' }],
  ['dose', 'Paracetamol 500 mg every 6 hours, maximum 4 g daily.', { kind: 'card', text: 'Paracetamol 500 mcg every 6 hours.' }],
  ['negation', 'Trimethoprim is contraindicated in the first trimester of pregnancy.', { kind: 'card', text: 'Trimethoprim is not contraindicated in the first trimester of pregnancy.' }],
  ['clean', 'Insulin lowers blood glucose, with no effect on potassium.', { kind: 'fact', text: 'Insulin lowers blood glucose.' }],
  ['none', 'Amoxicillin 500 mg every 8 hours or 875 mg every 12 hours.', { kind: 'card', text: 'Amoxicillin 875 mg every 12 hours.' }],
  ['clean', 'Amoxicillin is first-line for acute otitis media.', { kind: 'card', text: 'Q: Dose of amoxicillin for otitis media?\nA: 500 mg PO three times a day' }],
  ['soft', 'Amoxicillin 250 mg three times daily for otitis media in children.', { kind: 'card', text: 'Amoxicillin 500 mg three times daily for otitis media in adults.' }],
  ['clean', 'Hypoglycaemia is common with sulfonylureas.', { kind: 'fact', text: 'Hypoglycaemia is not uncommon with sulfonylureas.' }],
  ['clean', 'Digoxin 0.125 mg once daily for rate control.', { kind: 'card', text: 'Digoxin 125 mcg once daily for rate control.' }],
  ['clean', 'Metformin 500 mg twice daily with meals.', { kind: 'card', text: 'Metformin 1000 mg once daily with meals.' }],
  ['clean', 'Aspirin should be given to children with Kawasaki disease.', { kind: 'fact', text: 'Aspirin should not be given to children under 16.' }],
  ['clean', 'PCC reverses warfarin within minutes.', { kind: 'mcq', stem: 'A patient on warfarin bleeds. Best immediate reversal?', options: ['Vitamin K', 'Prothrombin complex concentrate'], key: 1, explanation: 'PCC works fastest.' }],
  ['clean', 'Vancomycin 15 mg/kg every 12 hours for MRSA bacteraemia.', { kind: 'card', text: 'Ceftriaxone 2 g every 12 hours for meningitis.' }],
  ['clean', 'Beta blockers reduce mortality in heart failure with reduced ejection fraction.', { kind: 'fact', text: 'Beta blockers reduce mortality in heart failure with reduced ejection fraction.' }],
  ['clean', '', { kind: 'card', text: 'Metformin is not first-line.' }],
  ['clean', 'Adrenaline 0.5 mg IM is given for anaphylaxis in adults.', { kind: 'card', text: 'Adrenaline 500 micrograms IM is given for anaphylaxis in adults.' }],
  ['clean', 'Give 1 g of paracetamol every 6 hours; maximum 4 g in 24 hours.', { kind: 'card', text: 'Paracetamol 1000 mg every 6 hours.' }],
  ['soft', 'Warfarin is safe in selected patients with atrial fibrillation.', { kind: 'fact', text: 'Warfarin is safe in all patients with atrial fibrillation.' }],
  ['soft', 'Smoking is associated with bladder cancer in observational studies.', { kind: 'fact', text: 'Smoking causes bladder cancer in observational studies.' }],
  ['clean', 'Warfarin 10 mg on day 1. Warfarin 5 mg daily thereafter.', { kind: 'card', text: 'Warfarin 5 mg daily.' }],
  ['clean', 'Metformin is first-line in type 2 diabetes. Metformin is not first-line in pregnancy.', { kind: 'card', text: 'Metformin is not first-line in pregnancy.' }],
  ['none', 'Avoid NSAIDs in renal impairment, but paracetamol is safe.', { kind: 'fact', text: 'NSAIDs should be avoided in renal impairment.' }],
  ['clean', 'Ceftriaxone is not used in neonates with jaundice.', { kind: 'fact', text: 'Ceftriaxone is used for meningitis in adults.' }],
  ['none', 'Thiazides cause hyponatraemia, hypokalaemia and hypercalcaemia.', { kind: 'fact', text: 'Thiazides cause hypokalaemia.' }],
  ['clean', 'Loop diuretics do not cause hypercalcaemia; thiazides do.', { kind: 'fact', text: 'Thiazides cause hypercalcaemia.' }],
  ['clean', 'Metformin is first-line in type 2 diabetes.', { kind: 'cloze', text: '{{c1::Metformin}} is first-line in type 2 diabetes.' }],
  // which way it goes: the lecture's sentence turned around
  ['direction', 'Statin therapy is associated with a modestly increased risk of new-onset diabetes.', { kind: 'fact', text: 'Statin therapy is associated with a reduced risk of new-onset diabetes.' }],
  ['direction', 'The risk of genital infection was higher in the SGLT2 inhibitor group.', { kind: 'card', text: 'Q: SGLT2 inhibitors and genital infection?\nA: SGLT2 inhibitors have a lower risk of genital infection.' }],
  ['direction', 'In atrial fibrillation patients with prior intracranial haemorrhage, DOACs had a lower risk of recurrent intracranial haemorrhage than warfarin.', { kind: 'fact', text: 'DOACs have a higher rate of recurrent intracranial haemorrhage than warfarin.' }],
  ['direction', 'Metformin monotherapy has minimal hypoglycaemia risk.', { kind: 'card', text: 'Metformin monotherapy has a high hypoglycaemia risk.' }],
  ['direction', 'Clinically apparent drug-induced liver injury attributed to statins is rare.', { kind: 'fact', text: 'Statins have a high incidence of clinically apparent liver injury.' }],
  ['direction', 'Metformin is contraindicated when the eGFR is below 30.', { kind: 'card', text: 'Metformin is contraindicated when the eGFR is above 30.' }],
  ['direction', 'Metoclopramide increases lower oesophageal sphincter pressure.', { kind: 'fact', text: 'Metoclopramide reduces lower oesophageal sphincter pressure.' }],
  ['direction', 'Minimal change disease is the commonest cause of nephrotic syndrome in children.', { kind: 'card', text: 'Minimal change disease is a rare cause of nephrotic syndrome in children.' }],
  ['direction', 'Gout is more common in men than in women.', { kind: 'fact', text: 'Gout is less common in men than in women.' }],
  // and what is not: the same fact the other way round, another thing
  // compared, a word changed for another, two ways in one sentence
  ['none', 'Gout is more common in men than in women.', { kind: 'fact', text: 'Gout is less common in women than in men.' }],
  ['none', 'Warfarin has a higher risk of intracranial bleeding than DOACs.', { kind: 'fact', text: 'DOACs have a lower risk of intracranial bleeding.' }],
  ['none', 'Higher doses increase the risk of bleeding.', { kind: 'fact', text: 'Lower doses reduce the risk of bleeding.' }],
  ['none', 'Statins raise HDL cholesterol levels.', { kind: 'fact', text: 'Statins lower LDL cholesterol levels.' }],
  ['none', 'Statins raise high-density lipoprotein cholesterol.', { kind: 'fact', text: 'Statins lower low-density lipoprotein cholesterol.' }],
  ['none', 'Lower motor neuron lesions cause decreased tone.', { kind: 'fact', text: 'Upper motor neuron lesions cause increased tone.' }],
  ['clean', 'The risk of genital infection was significantly higher in the SGLT2 inhibitor group.', { kind: 'fact', text: 'SGLT2 inhibitors are associated with an increased risk of genital infection.' }],
  ['clean', 'Myositis and myopathy are listed as rare adverse effects of high-intensity statin therapy.', { kind: 'fact', text: 'Statin-associated myopathy is an uncommon adverse effect.' }],
  ['clean', 'ACE inhibitors decrease bradykinin degradation, increasing bradykinin concentration and contributing to dry cough.', { kind: 'fact', text: 'ACE inhibitor cough has been linked to increased bradykinin.' }],
];
{
  for (const [want, source, item] of CASES) {
    const g = C.claimGate({ source, ...item });
    const hard = g.hard.map(f => f.code).join('+');
    const pass = want === 'clean' ? !g.hard.length && !g.soft.length
      : want === 'none' ? !g.hard.length
      : want === 'soft' ? !g.hard.length && g.soft.length > 0
      : hard === want;
    const said = (item.text || item.explanation).replace(/\s+/g, ' ').slice(0, 60);
    ok(pass && g.complete, `${want.padEnd(10)} ${said}${pass ? '' : `  (hard: ${hard || '-'}, soft: ${g.soft.map(f => f.code).join(',') || '-'})`}`);
  }
  const g = C.claimGate({ kind: 'card', text: 'Metformin is not first-line in type 2 diabetes.', source: 'Metformin is first-line in type 2 diabetes.' });
  ok(g.hard[0]?.claim === 'Metformin is not first-line in type 2 diabetes.' && g.hard[0]?.source === 'Metformin is first-line in type 2 diabetes.',
     'a finding names the item\'s sentence and the lecture\'s');
  const twice = C.claimGate({ kind: 'note', text: 'Metformin is not first-line in type 2 diabetes. Metformin is not first-line in type 2 diabetes.', source: 'Metformin is first-line in type 2 diabetes.' });
  ok(twice.hard.length === 1, 'each finding once a sentence');
  ok(C.claimGate(null).hard.length === 0 && C.claimGate({}).complete, 'no item, no lecture: nothing to say');
  ok(!C.turnedAround('Metformin does not increase the risk of lactic acidosis.', 'Metformin increases the risk of lactic acidosis.'),
     'a negated sentence is left to the negation check, not read for a way');
}

// MARK: 3. the work budget

{
  const long = { kind: 'note', text: 'Metformin is not first-line in type 2 diabetes. Amoxicillin 500 mg twice daily for otitis media. '.repeat(40),
    source: 'Metformin is first-line in type 2 diabetes. Amoxicillin 500 mg three times daily for otitis media. '.repeat(20) };
  const full = C.claimGate(long);
  ok(full.work <= C.MAX_WORK && full.complete === false, `never more work than MAX_WORK (${C.MAX_WORK}) an item (${full.work}, ${full.checks} judgements)`);
  const cut = C.claimGate(long, 2 * C.VERIFY_WORK);
  ok(cut.checks <= 2 && cut.work <= 2 * C.VERIFY_WORK && cut.complete === false, 'cut short at its budget, it says so');
  const none = C.claimGate(long, 0);
  ok(none.checks === 0 && !none.hard.length && none.complete === false, 'no budget at all: nothing judged, nothing found, and not complete');
  let started = performance.now();
  for (let i = 0; i < 5; i++) C.claimGate(long);
  const ms = (performance.now() - started) / 5;
  ok(ms < 100, `a long page against its lecture: ${ms.toFixed(1)} ms`);
  // the gate keeps no state between items
  const before = JSON.stringify(C.claimGate(CASES[0][2] && { source: CASES[0][1], ...CASES[0][2] }));
  C.claimGate(long);
  ok(JSON.stringify(C.claimGate({ source: CASES[0][1], ...CASES[0][2] })) === before, 'the same item, the same findings, whatever ran before');
}

// the worst batch the server takes: four notes of MAX_ITEM_CHARS (3,500),
// every sentence a dose that restates one of its lecture's (MAX_SOURCE_CHARS,
// 1,400) with another dose and frequency - and an ordinary batch: a
// question, two cards and a note against one full lecture
const WORST = `
const drugs = ['amoxicillin', 'paracetamol', 'ibuprofen', 'metformin', 'gentamicin', 'vancomycin', 'ceftriaxone', 'furosemide', 'digoxin', 'warfarin',
  'heparin', 'insulin', 'lithium', 'phenytoin', 'morphine', 'codeine', 'aspirin', 'clopidogrel', 'atenolol', 'ramipril'];
const conds = ['pneumonia', 'cellulitis', 'meningitis', 'pyelonephritis', 'osteomyelitis', 'endocarditis', 'sepsis', 'cholangitis', 'peritonitis', 'arthritis',
  'gastritis', 'pancreatitis', 'bronchitis', 'sinusitis', 'otitis', 'mastitis', 'prostatitis', 'colitis', 'hepatitis', 'nephritis'];
const line = (i, dose, h) => 'For ' + conds[i % 20] + ' in elderly adults, ' + drugs[i % 20] + ' ' + dose + ' mg every ' + h + ' hours, and ' + (10 + i) + '% improve.';
const fill = (k, max, dose, h) => { let t = '', i = 0; while ((t + line(i + k, dose, h)).length < max) t += line(i++ + k, dose, h) + ' '; return t; };
const worst = [0, 1, 2, 3].map(k => ({ id: 'w' + k, kind: 'note', text: fill(k * 5, 3500, 250, 6), source: fill(k * 5, 1400, 500, 8) }));`;
const lecture = 'Metformin is first-line in type 2 diabetes. Start metformin 500 mg once daily with food and increase the dose every week to reduce gastrointestinal side effects. The usual maximum dose of metformin is 2 g daily in divided doses. Metformin is contraindicated when the eGFR is below 30. Lactic acidosis is a rare but serious adverse effect of metformin. Sulfonylureas such as gliclazide cause hypoglycaemia and weight gain. Gliclazide 40 mg once daily is the usual starting dose in adults. SGLT2 inhibitors reduce cardiovascular events in patients with established heart failure. Pioglitazone causes fluid retention and is avoided in heart failure. DPP-4 inhibitors are weight neutral. HbA1c should be checked every 3 months until stable. Insulin is started when HbA1c stays above target despite oral therapy.';
const ordinary = [
  { id: 'a', kind: 'mcq', stem: 'First-line drug in type 2 diabetes?', options: ['Gliclazide', 'Metformin', 'Insulin', 'Pioglitazone'], key: 1,
    explanation: 'Metformin is first-line in type 2 diabetes. Start metformin 500 mg twice daily with food and increase the dose every week to reduce gastrointestinal side effects.', source: lecture },
  { id: 'b', kind: 'card', text: 'Q: Usual starting dose of gliclazide in adults?\nA: Gliclazide 80 mg once daily is the usual starting dose in adults.', source: lecture },
  { id: 'c', kind: 'card', text: 'Q: Metformin and renal function?\nA: Metformin is contraindicated when the eGFR is below 30.', source: lecture },
  { id: 'd', kind: 'note', text: 'Pioglitazone causes fluid retention and is avoided in heart failure. SGLT2 inhibitors reduce cardiovascular events in patients with established heart failure. HbA1c should be checked every 6 months until stable. DPP-4 inhibitors are weight neutral.', source: lecture },
];
{
  const worst = new Function(`${WORST}\nreturn worst;`)();
  ok(worst.every(i => i.text.length <= 3500 && i.text.length > 3400 && i.source.length <= 1400 && i.source.length > 1300), 'the worst batch is as long as the server lets it be');
  const w = claimsStage(worst).value;
  ok(w.reduce((n, g) => n + g.work, 0) <= C.MAX_WORK, `the worst batch shares MAX_WORK (${w.map(g => g.work).join('+')} units, ${w.map(g => g.checks).join('+')} judgements)`);
  ok(w.some(g => g.hard.length) && w.every(g => !g.complete), 'and finds what it reaches, saying it stopped short');
  const o = claimsStage(ordinary).value;
  ok(o.every(g => g.complete), `an ordinary batch is gated to the end within the budget (${o.map(g => g.work).join('+')} units of ${C.MAX_WORK})`);
  ok(o.map(g => g.hard.map(f => f.code).join('+')).join() === 'frequency,dose,,', `and finds the changed dose and dose frequency, and nothing in the rest (${o.map(g => g.hard.map(f => f.code).join('+') || '-').join(', ')})`);
  // CPU, warm: the median of 30 runs
  const warm = batch => { const t = []; for (let i = 0; i < 30; i++) { const a = performance.now(); claimsStage(batch); t.push(performance.now() - a); } return t.sort((x, y) => x - y)[15]; };
  for (let i = 0; i < 20; i++) claimsStage(worst);
  const wms = warm(worst), oms = warm(ordinary);
  console.log(`     warm: the worst batch ${wms.toFixed(1)} ms, an ordinary one ${oms.toFixed(1)} ms`);
  ok(wms < 8 && oms < 8, 'warm, a batch takes a few ms of CPU at most (about 3 here; generous for a slow runner)');
  // CPU, cold: the first batch of a fresh isolate, the gate's patterns and
  // code compiled on the way (Unicode \b alone was about 100 ms of it); the
  // least of three fresh isolates, as one can be held up by whatever else
  // the machine is doing (a clock, not CPU time)
  const accuracy = new URL('../accuracy.js', import.meta.url).href;
  const coldOnce = () => Number(execFileSync(process.execPath, ['--input-type=module', '-e',
    `const { claimsStage } = await import(${JSON.stringify(accuracy)});${WORST}\nconst a = performance.now(); claimsStage(worst); console.log(performance.now() - a);`]).toString().trim());
  const cold = Math.min(coldOnce(), coldOnce(), coldOnce());
  console.log(`     cold: the worst batch ${cold.toFixed(1)} ms`);
  ok(cold < 50, 'cold, the worst batch is a few tens of ms at most, not the 130 it was (about 15 here)');
}

// MARK: 4. Python's \b and \w, cheaply

{
  // ASCII text, and text whose only other characters are not letters or
  // digits, read with the ASCII patterns; letters beyond ASCII with the Unicode ones
  ok(C.frequencyMultiplier('take it daily') === 1 && C.frequencyMultiplier('take it daily – ≥ 2') === 1, 'ASCII, and symbols beyond it: a word ends where a symbol starts');
  ok(C.frequencyMultiplier('take it dailyé') === null, 'a letter beyond ASCII is part of the word, as in Python: "dailyé" is not "daily"');
  ok(C.frequencyMultiplier('é bid') === 2 && C.frequencyMultiplier('ébid') === null, 'and before it too');
  ok(JSON.stringify(C.quantities('5 mgé then 10 mg')) === '[[10,"mg"]]' && JSON.stringify(C.quantities('5 mg then 10 mg')) === '[[5,"mg"],[10,"mg"]]',
     'every match in a text, either way');
  ok(C.NEGATION.test('NOT given') && !C.NEGATION.test('nothing given') && C.NEGATION.test('été not given'), 'a case-blind pattern either way');
  const astral = 'daily \u{1F48A}';
  ok(C.frequencyMultiplier(astral) === 1, 'a character beyond the Basic Multilingual Plane takes the Unicode path, and the same answer');
}

console.log(failures ? `\n${failures} CLAIM GATE FAILURE(S)` : '\nALL CLAIM GATE TESTS PASS');
process.exit(failures ? 1 : 0);
