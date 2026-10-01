// The question bank's rules and pipeline (plan Task 5b steps 3 to 5), with a
// fake Worker: no network, no key.
//
// Run: node tests/question-bank/bank.test.mjs
import { mkdtempSync, writeFileSync, readFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { buildPrompt, parseItems, qualityProblems, novelty, publicItems, blueprintTag, decide, metrics, highStakes, NOVELTY_LIMIT } from '../../tools/question-bank/bank.mjs';
import { generate, validate } from '../../tools/question-bank/pipeline.mjs';

let failures = 0;
const ok = (cond, what, detail = '') => { console.log((cond ? 'ok   ' : 'FAIL ') + what + (cond ? '' : `  | ${detail}`)); if (!cond) failures++; };

const passage = {
  source: 'medlineplus-health-topics', url: 'https://medlineplus.gov/asthma.html', licence: 'US-GOV-PD-MEDLINEPLUS',
  title: 'Asthma', attribution: 'Asthma. MedlinePlus.', topic: 'asthma',
  text: 'Asthma is a chronic disease that affects your airways. During an asthma attack the lining of the airways swells and the muscles around them tighten. Quick-relief medicines such as short-acting inhaled bronchodilators relax the muscles around the airways within minutes. Long-term control medicines such as inhaled corticosteroids reduce airway inflammation over time.',
};
const good = {
  stem: 'A 24-year-old woman with known asthma has sudden wheeze and chest tightness while running. Which medicine relaxes the muscles around her airways within minutes?',
  options: ['Short-acting inhaled bronchodilator', 'Inhaled corticosteroid', 'Oral antihistamine', 'Leukotriene receptor antagonist', 'Oral antibiotic'],
  key: 0,
  explanation: 'Quick relief comes from a short-acting inhaled bronchodilator, which relaxes the airway muscles within minutes; an inhaled corticosteroid reduces inflammation only over time, and the others are not quick relief.',
  quote: 'short-acting inhaled bronchodilators relax the muscles around the airways within minutes',
};

// the prompt
const prompt = buildPrompt(passage, 3);
ok(prompt.includes(passage.text) && prompt.includes('Write 3 single-best-answer'), 'the prompt carries the passage and the count');
ok(!prompt.includes('{{'), 'every placeholder is filled');
ok(/Answer: /.test(prompt), 'two public exemplars, for style');

// reading the reply
ok(parseItems('```json\n' + JSON.stringify([good]) + '\n```').length === 1, 'a fenced reply is read');
ok(parseItems('Sure! Here they are: ' + JSON.stringify([good, { stem: 'x' }])).length === 1, 'words around it and a malformed item are left out');
ok(parseItems('not json').length === 0 && parseItems('').length === 0, 'no JSON: no items');

// quality
ok(qualityProblems(good, passage).length === 0, 'a good item passes', qualityProblems(good, passage).join('; '));
const four = { ...good, options: good.options.slice(0, 4) };
ok(qualityProblems(four, passage).some(p => p.includes('4 options')), 'four options fail');
ok(qualityProblems({ ...good, key: 7 }, passage).some(p => p.includes('key')), 'a key off the end fails');
ok(qualityProblems({ ...good, options: [...good.options.slice(0, 4), 'All of the above'] }, passage).some(p => p.includes('all/none')), '"all of the above" fails');
ok(qualityProblems({ ...good, stem: 'Which of these does NOT relax the airways in an asthma attack within minutes?' }, passage).some(p => p.includes('negatively')), 'a NOT stem fails');
ok(qualityProblems({ ...good, quote: 'asthma is caused by cats in every case' }, passage).some(p => p.includes('quote')), 'a quote the passage does not hold fails');
ok(qualityProblems({ ...good, stem: 'During an asthma attack the lining of the airways swells and the muscles around them tighten. What happens?' }, passage).some(p => p.includes('copies')), 'a stem copied from the passage fails');
ok(qualityProblems({ ...good, explanation: good.explanation + ' Option B is wrong.' }, passage).some(p => p.includes('letter')), 'an explanation naming option B fails');

// novelty
const pub = publicItems()[0];
ok(novelty(good) < NOVELTY_LIMIT, 'a new item is novel', String(novelty(good)));
ok(novelty({ stem: pub.stem, options: pub.options, key: pub.options.indexOf(pub.answer) }) > 0.9, 'a public item is not');

// tags, stakes, the decision
ok(blueprintTag(passage, []) === 'asthma', 'the topic it was fetched for is its tag');
ok(blueprintTag({ ...passage, topic: undefined }, ['heart failure', 'asthma']) === 'asthma', 'else the first topic it names');
ok(highStakes({ ...good, stem: 'What dose of insulin...' }) && !highStakes(good), 'dosing is high stakes; this is not');
const keep = decide(good, passage, { verdict: 'verified', novelty: 0 });
ok(keep.keep && keep.reasons.length === 0 && keep.review.startsWith('required'), 'verified, novel and clean: kept, for review');
const drop = decide(good, { ...passage, licence: 'CC-BY-NC-4.0', source: 'pmc-open-access', url: 'https://pmc.ncbi.nlm.nih.gov/articles/PMC1/' }, { verdict: 'check', novelty: 0.5 });
ok(!drop.keep && drop.reasons.some(r => r.startsWith('licence')) && drop.reasons.some(r => r.startsWith('novelty')) && drop.reasons.some(r => r.startsWith('accuracy')),
   'an NC licence, a copy and an unsure check: dropped with every reason', drop.reasons.join('; '));
const m = metrics([{ ...keep, tag: 'asthma' }, { ...drop, tag: 'asthma' }]);
ok(m.generated === 2 && m.kept === 1 && m.droppedFor.licence === 1 && m.byTag.asthma === 1, 'metrics count it', JSON.stringify(m));

// the pipeline against a fake Worker
const dir = mkdtempSync(join(tmpdir(), 'qbank-'));
writeFileSync(join(dir, 'p.jsonl'), JSON.stringify(passage) + '\n');
const calls = [];
const worker = async (url, init) => {
  const body = JSON.parse(init.body);
  calls.push(url.split('.dev')[1]);
  if (url.endsWith('/v1/chat/completions')) return new Response(JSON.stringify({ model: 'gemma-4-31b-it', choices: [{ message: { content: JSON.stringify([good, { ...good, options: good.options.slice(0, 3) }]) } }] }));
  return new Response(JSON.stringify({ items: body.items.map(i => ({ id: i.id, verdict: 'verified', p: 0.93 })) }));
};
await generate(['--passages', join(dir, 'p.jsonl'), '--out', join(dir, 'c.jsonl')], 'key', worker);
const cands = readFileSync(join(dir, 'c.jsonl'), 'utf8').trim().split('\n');
ok(cands.length === 2 && calls[0] === '/v1/chat/completions', 'generate: two candidates from one passage, through the Worker');
await validate(['--candidates', join(dir, 'c.jsonl'), '--out', join(dir, 'pilot'), '--topics-file', '/nonexistent'], 'key', worker);
const pilot = readFileSync(join(dir, 'pilot.jsonl'), 'utf8').trim().split('\n').map(l => JSON.parse(l));
const dropped = readFileSync(join(dir, 'pilot.dropped.jsonl'), 'utf8').trim().split('\n').map(l => JSON.parse(l));
ok(pilot.length === 1 && pilot[0].source.licence === 'US-GOV-PD-MEDLINEPLUS' && pilot[0].source.attribution, 'validate: the good one kept, with its licence and attribution');
ok(dropped.length === 1 && dropped[0].reasons.some(r => r.includes('3 options')), 'the three-option one dropped with its reason');
ok(calls.includes('/accuracy/check'), 'every item went through the accuracy engine');
const offline = async () => { throw new TypeError('fetch failed'); };
let threw = false;
try { await validate(['--candidates', join(dir, 'c.jsonl'), '--out', join(dir, 'p2'), '--topics-file', '/x'], 'key', async (u, i) => u.endsWith('/accuracy/check') ? new Response('nope', { status: 503 }) : offline()); } catch { threw = true; }
const p2 = readFileSync(join(dir, 'p2.jsonl'), 'utf8').trim();
ok(!threw && p2 === '', 'checkers down: nothing kept (never kept unchecked)');

console.log(failures ? `\n${failures} QUESTION BANK TEST FAILURE(S)` : '\nall question bank tests pass');
process.exit(failures ? 1 : 0);
