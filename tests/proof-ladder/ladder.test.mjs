// The proof ladder (tools/proof-ladder): the rungs' counts, the bound, the
// pacing inside the cloud checker's cap, and that each question is used
// once with a gold or a planted key. No network.
//
// Run: node tests/proof-ladder/ladder.test.mjs
import { readFileSync } from 'node:fs';
import { RUNGS, needed, emptyState, addResults, standing, paceLimit, mayContinue, progressMarkdown } from '../../tools/proof-ladder/ladder-lib.mjs';
import { itemOf, readable, SOURCES } from '../../tools/proof-ladder/ladder.mjs';

let failures = 0;
const ok = (cond, what) => { console.log((cond ? 'ok   ' : 'FAIL ') + what); if (!cond) failures++; };

ok(needed(1e-3) === 2995 && needed(1e-4) === 29956 && needed(1e-5) === 299572, 'the rungs: 2,995, 29,956 and 299,572 Verified with no error');
ok(RUNGS.map(r => r.name).join() === '99.9%,99.99%,99.999%', 'climbed in order');

{
  const s = emptyState();
  addResults(s, [{ truth: 'right', verdict: 'verified' }, { truth: 'wrong', verdict: 'check' }, { truth: 'wrong', verdict: 'flagged' }, { truth: 'right', verdict: 'unchecked' }], '2026-10-14');
  ok(s.checked === 3 && s.verified === 1 && s.errors === 0 && s.unchecked === 1 && s.days[0].checked === 3, 'results are counted, an unanswered item is not a check');
  addResults(s, [{ truth: 'wrong', verdict: 'verified' }], '2026-10-15');
  ok(s.errors === 1 && s.days.length === 2, 'a Verified distractor is an error');
}
{
  const s = emptyState();
  s.verified = 2995; s.checked = 6000;
  const st = standing(s);
  ok(st.proven.includes('99.9%') && st.rung === '99.99%' && st.moreVerified === 29956 - 2995, `2,995 with no error proves 99.9% (bound ${st.bound.toFixed(5)}), next 99.99%`);
  s.errors = 1;
  const one = standing(s);
  ok(!one.proven.includes('99.9%') && one.rung === '99.9%' && one.moreVerified > 1500, `one error takes it back below, and needs about ${one.moreVerified} more`);
  ok(standing(emptyState()).bound === null && standing(emptyState()).moreVerified === 2995, 'nothing yet: nothing proven');
}
{
  const mid = new Date(Date.UTC(2026, 9, 16, 0, 0));          // 15 of 31 days gone
  ok(Math.abs(paceLimit(60, mid) - 60 * 15 / 31) < 1e-9, 'the share is spread evenly over the month');
  ok(mayContinue({ spent: 10, cap: 90, share: 60, now: mid }) && !mayContinue({ spent: 40, cap: 90, share: 60, now: mid }), 'ahead of the pace it waits for the next day');
  ok(!mayContinue({ spent: 89.9, cap: 90, share: 200, now: new Date(Date.UTC(2026, 9, 31, 23)) }), 'never within one batch of the cap, whatever the share');
  ok(!mayContinue({ spent: NaN, cap: 90, share: 60, now: mid }) && !mayContinue({ spent: 0, cap: 0, share: 60, now: mid }), 'no spend known, or a cap of 0: it stops');
}
{
  const q = { id: 'medmcqa-train:abc', source: 'MedMCQA', kind: 'mcq', stem: 'Drug of choice for absence seizures is', options: ['Ethosuximide', 'Phenytoin', 'Carbamazepine', 'Gabapentin'], key: 0 };
  const a = itemOf(q), b = itemOf(q);
  ok(JSON.stringify(a) === JSON.stringify(b), 'a question becomes the same item every time');
  const many = Array.from({ length: 400 }, (_, i) => itemOf({ ...q, id: `medmcqa-train:${i}` }));
  const wrong = many.filter(x => x.truth === 'wrong');
  ok(wrong.length > 150 && wrong.length < 250 && wrong.every(x => x.item.key !== 0) && many.filter(x => x.truth === 'right').every(x => x.item.key === 0),
     `about half get a distractor keyed (${wrong.length} of 400), the rest their gold key`);
  ok(typeof readable(q) === 'boolean' && readable({ ...q, stem: 'A 45-year-old man presents with chest pain. He is sweating. Which of the following is the next step?' }) === false,
     'a vignette is not readable by the proof, so it is not sent');
}
{
  const cfg = JSON.parse(readFileSync(new URL('../../tools/proof-ladder/config.json', import.meta.url)));
  ok(cfg.share > 0 && cfg.share <= 90 && cfg.maxItems <= 2500, 'the ladder takes at most its share of the 90-dollar cap and less than the bench\'s daily allowance');
  ok(SOURCES.every(s => ['Apache-2.0', 'CC-BY-4.0', 'MIT', 'CC0-1.0'].includes(s.licence)) && SOURCES.every(s => s.split === 'train'),
     'its questions are under commercial-use licences, from splits neither the triage nor the bench uses');
  ok(/progress\.json/.test(progressMarkdown(emptyState())) === false && progressMarkdown(emptyState()).includes('99.999%'), 'the progress page names every rung');
}

console.log(failures ? `\n${failures} failed` : '\nall passed');
process.exit(failures ? 1 : 0);
