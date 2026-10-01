// The claim gate (claims.js, plan Task 5d step 3): the Chat-me medical
// verifier's deterministic guards in JavaScript, and what the gate makes of
// them on Stethoscore items against their own lectures.
//
// 1. Conformance: on every pair in claim-vectors.json (the verifier's 35
//    shared conformance vectors and Stethoscore-shaped pairs), each guard
//    gives exactly what the Python gave (bench/claim-vectors.py made it).
// 2. The gate: hard findings only where an item restates its lecture and
//    contradicts it (a flipped negation, another dose, frequency or
//    percentage); paraphrases, extra detail and other sentences pass.
// 3. Its work budget: a long page stops at MAX_CHECKS, saying so.
//
// Run: node server/tests/claims.test.mjs

import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import * as C from '../claims.js';

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
}

// MARK: 3. the work budget

{
  const long = { kind: 'note', text: 'Metformin is not first-line in type 2 diabetes. Amoxicillin 500 mg twice daily for otitis media. '.repeat(40),
    source: 'Metformin is first-line in type 2 diabetes. Amoxicillin 500 mg three times daily for otitis media. '.repeat(20) };
  const full = C.claimGate(long);
  ok(full.checks <= C.MAX_CHECKS, `never more than MAX_CHECKS (${C.MAX_CHECKS}) judgements an item (${full.checks})`);
  const cut = C.claimGate(long, 2);
  ok(cut.checks <= 2 && cut.complete === false, 'cut short at its budget, it says so');
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

console.log(failures ? `\n${failures} CLAIM GATE FAILURE(S)` : '\nALL CLAIM GATE TESTS PASS');
process.exit(failures ? 1 : 0);
