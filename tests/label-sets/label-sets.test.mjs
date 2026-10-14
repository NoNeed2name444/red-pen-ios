// The label sets (tools/label-sets): every set's licence allows commercial
// use, every label is the set's own, and the builder's transforms keep each
// item's gold answer. No network: the rows below are made-up shapes, not
// data from the sets.
//
// Run: node tests/label-sets/label-sets.test.mjs
import { registry, questionPairs, cardPairs, pubmedqaItems, pubhealthItems, labelSentences, oathFromLabels, reduxItems } from '../../tools/label-sets/build.mjs';
import { lowerBound, measure } from '../../tools/jev-standin/oath-bench.mjs';

let failures = 0;
const ok = (cond, what) => { console.log((cond ? 'ok   ' : 'FAIL ') + what); if (!cond) failures++; };

// MARK: the registry
{
  const commercial = new Set(['CC-BY-4.0', 'CC-BY-3.0', 'Apache-2.0', 'MIT', 'CC0-1.0']);
  ok(registry.sets.length >= 5 && registry.sets.every(s => commercial.has(s.licence)), 'every set used is under a licence that allows commercial use');
  ok(registry.sets.every(s => /^\d{4}-\d{2}-\d{2}$/.test(s.licenceRead) && s.attribution && s.label && s.gates.length), 'and names when its licence was read, its attribution, whose label it is, and its gates');
  ok(!registry.sets.some(s => /-(NC|ND|SA)\b/.test(s.licence)), 'no NC, ND or SA licence is used');
  ok(['scifact', 'healthver', 'mednli'].every(id => registry.refused.some(r => r.id === id && r.why)), 'the sets refused say why (non-commercial, no licence, a use agreement)');
  ok(registry.noPublicGold.length >= 1 && registry.noPublicGold.every(g => g.why && g.how), 'a gate with no public gold set says so, and how to get one');
  ok(!registry.sets.some(s => /\bmodels?\b|\bLLM|\bAI\b/i.test(s.label)), 'no label comes from a model');
}

// MARK: the transforms keep the gold answer
{
  const q = { id: 'x:1', source: 'S', stem: 'Which?', options: ['a', 'b', 'c', 'd'], key: 2 };
  const pairs = questionPairs([q], 'mcq', 1);
  ok(pairs.length === 2 && pairs[0].truth === 'right' && pairs[0].key === 2 && pairs[1].truth === 'wrong' && pairs[1].key !== 2, 'a question twice: its key is right, a distractor keyed is wrong');
  const cards = cardPairs([q], 1);
  ok(cards[0].back === 'c' && cards[0].truth === 'right' && cards[1].back !== 'c' && cards[1].truth === 'wrong', 'a short question as cards: the key on the back is right');
  const pq = pubmedqaItems([{ row: { pubid: 1, question: 'Q?', context: { contexts: ['A.', 'B.'] }, final_decision: 'no' } },
                            { row: { pubid: 2, question: 'Q?', context: { contexts: ['A.'] }, final_decision: 'maybe' } }]);
  ok(pq.length === 1 && pq[0].key === 1 && pq[0].options.join() === 'yes,no', 'PubMedQA: the experts\' no is the key; maybe is left out');
  const ph = pubhealthItems([{ row: { claim_id: 'a', claim: 'C', main_text: 'T', label: 0, subjects: 'Health News' } },
                             { row: { claim_id: 'b', claim: 'C', main_text: 'T', label: 1, subjects: 'Health' } },
                             { row: { claim_id: 'c', claim: 'C', main_text: 'T', label: 3, subjects: 'Health' } },
                             { row: { claim_id: 'd', claim: 'C', main_text: 'T', label: 0, subjects: 'Politics' } }]);
  ok(ph.length === 2 && ph[0].truth === 'right' && ph[1].truth === 'wrong', 'PUBHEALTH: true is right, false is wrong; mixture, unproven and non-health claims are left out');
  const rx = reduxItems([{ row: { question: 'Q', choices: ['a', 'b', 'c', 'd'], answer: 0, error_type: 'wrong_groundtruth', correct_answer: 'B' } },
                         { row: { question: 'Q', choices: ['a', 'b'], answer: 0, error_type: 'ok', correct_answer: null } }], 'virology');
  ok(rx.length === 2 && rx.find(r => r.truth === 'wrong').key === 0 && rx.find(r => r.truth === 'right').key === 1, 'MMLU-Redux: the published key the re-annotators rejected is wrong, theirs is right');
}

// MARK: FDA label sentences as oath claims
{
  const s = labelSentences('2 DOSAGE AND ADMINISTRATION Take one tablet by mouth twice daily with food. ( 2.1 ) See full prescribing information. Short one.');
  ok(s.length === 1 && s[0] === 'Take one tablet by mouth twice daily with food.', 'a label section is cut into whole sentences, without its heading or cross-references');
  const rows = oathFromLabels([{ set_id: 'z', dosage_and_administration: ['Take two tablets by mouth every morning with water.'], description: ['A white tablet that is round and scored on one side.'] }]);
  ok(rows.length === 1 && rows[0].oath === true && rows[0].section === 'dosage_and_administration', 'only the dosing and safety sections give oath claims');
}

// MARK: the bound on recall
{
  ok(Math.abs(lowerBound(30, 30) - Math.pow(0.05, 1 / 30)) < 1e-12, 'with no miss the bound is 0.05^(1/n)');
  ok(Math.abs(lowerBound(9, 10) - 0.6058) < 1e-3, 'with misses it is the exact (Clopper-Pearson) one: 9 of 10 gives 60.6%');
  const m = measure([{ text: 'Give amoxicillin 500 mg three times daily.', oath: true }, { text: 'The femoral nerve arises from L2 to L4.', oath: false }]);
  ok(m.tp === 1 && m.tn === 1 && m.lower !== null, 'measure counts and bounds');
}

console.log(failures ? `\n${failures} failed` : '\nall passed');
process.exit(failures ? 1 : 0);
