// The proof ladder (tools/proof-ladder): the rungs' counts, the bound, the
// pacing inside the cloud checker's cap, and that each question is used
// once with a gold or a planted key. No network.
//
// Run: node tests/proof-ladder/ladder.test.mjs
import { readFileSync } from 'node:fs';
import { RUNGS, needed, emptyState, addResults, addFamilyVotes, addRunnerVotes, runnerSeated, addHeld, standing, paceLimit, mayContinue, progressMarkdown } from '../../tools/proof-ladder/ladder-lib.mjs';
import { itemOf, readable, SOURCES, pick, runnerFor } from '../../tools/proof-ladder/ladder.mjs';
import { requestFor, answersOf } from '../../tools/runner-voter/vote.mjs';
import { runnerVoters, DEFAULT_RUNNER_VOTERS } from '../../server/runner-voters.js';
import { familyOf } from '../../server/accuracy-model.js';
import { validQuestionOf as validQ } from '../../tools/verification-bench/datasets.mjs';

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

// MARK: the gold key stays here; the ledger counts each family once
{
  const q = { id: 'medmcqa-train:g', source: 'MedMCQA', kind: 'mcq', stem: 'Drug of choice for absence seizures is', options: ['Ethosuximide', 'Phenytoin', 'Carbamazepine', 'Gabapentin'], key: 0 };
  const x = itemOf(q);
  ok(x.gold === 'A' && !('gold' in x.item), 'each item keeps its gold letter, which is never sent');
  const s = emptyState();
  addFamilyVotes(s, 'A', [{ model: 'gemini-3.5-flash-lite', answer: 'A', blind: true }, { model: 'gemma-4-31b-it', answer: 'B', blind: true },
                          { model: 'phi-4-mini-instruct', answer: 'C', blind: true, runner: true }, { model: 'claude-opus-5-5', answer: 'A', blind: false }]);
  ok(s.families.google.answered === 1 && s.families.google.right === 1 && s.families.microsoft.right === 0 && s.families.microsoft.runner && !s.families.anthropic,
     "the ledger: one blind answer per family per question, a voter shown the key not counted");
  ok(/microsoft \(runner\) \| 1 \| 0/.test(progressMarkdown({ ...s, updated: 'now' })), 'and the progress page shows it');
}

// MARK: picking the day's questions, page by page, from where it stopped
{
  const row = (i, stem) => ({ row: { id: `r${i}`, question: stem, opa: 'Ethosuximide', opb: 'Phenytoin', opc: 'Carbamazepine', opd: 'Gabapentin', cop: 0, choice_type: 'single', exp: '' } });
  const short = 'Drug of choice for absence seizures is';
  const vignette = 'A 45-year-old man presents with chest pain. He is sweating. Which of the following is the next step?';
  const pages = { 0: Array.from({ length: 100 }, (_, i) => row(i, i % 2 ? vignette : short)), 100: Array.from({ length: 100 }, (_, i) => row(100 + i, short)) };
  const page = async url => ({ rows: pages[Number(new URL(url).searchParams.get('offset'))] || [] });
  const ready = readable(validQ(pages[0][0].row));
  const a = await pick({ cursor: {} }, 3, { page });
  ok(!ready || (a.picked.length === 3 && a.picked.every(p => p.src === 'medmcqa-train') && a.scanned['medmcqa-train'] === a.picked[2].at),
     'it stops reading where the third question was, so the next day starts after it');
  const b = await pick({ cursor: { 'medmcqa-train': a.scanned['medmcqa-train'] } }, 3, { page });
  ok(!ready || !b.picked.some(p => a.picked.some(q => q.item.id === p.item.id)), 'and the next day never takes the same question again');
  const c = await pick({ cursor: {} }, 50, { page });
  ok(!ready || (c.picked.length === 50 && c.scanned['medmcqa-train'] === c.picked[49].at), 'across a page edge too');
}

// MARK: runner voters
{
  const cfg = JSON.parse(readFileSync(new URL('../../tools/runner-voter/models.json', import.meta.url)));
  ok(cfg.models.map(m => m.name).join() === DEFAULT_RUNNER_VOTERS && runnerVoters({}).join() === DEFAULT_RUNNER_VOTERS, 'the Worker takes ballots from exactly the models the runners run');
  ok(cfg.models.every(m => ['MIT', 'Apache-2.0'].includes(m.licence) && /^\d{4}-\d{2}-\d{2}$/.test(m.licenceRead) && familyOf(m.name) === m.family) && cfg.engine.licence === 'MIT',
     'each under a licence that allows commercial use, read on a date, and the family it says it is');
  ok(new Set(cfg.models.map(m => m.family)).size === cfg.models.length && cfg.models.every(m => m.bytes < 5e9), 'one family each, small enough for a free runner');
  ok(/^b\d+$/.test(cfg.engine.tag) && cfg.engine.tagDate <= '2026-10-01', 'the engine is pinned to a tagged release at least two weeks old');
  const items = [{ id: 'a#ladder', kind: 'mcq', stem: 'Drug of choice for absence seizures is', options: ['Ethosuximide', 'Phenytoin'], key: 1, explanation: 'Because.', source: '' }];
  const req = requestFor(items, 'm');
  const prompt = JSON.stringify(req.messages);
  ok(prompt.includes('Keyed answer and explanation withheld') && !prompt.includes('Because.') && req.temperature === 0 && req.response_format?.type === 'json_object',
     'a runner answers blind, with the Worker\'s own blind prompt, held to JSON');
  const got = answersOf([...items, { ...items[0], id: 'b#ladder' }], '{"items":[{"i":1,"answer":"A","risk":1},{"i":2,"answer":"D","risk":1}]}');
  ok(got['a#ladder']?.answer === 'A' && !got['b#ladder'], 'its answers are read as the Worker reads a vote; a letter beyond the options is none');
  const batch = [{ item: { id: 'a#ladder' } }, { item: { id: 'b#ladder' } }];
  const r = runnerFor(batch, [{ model: 'x', votes: { 'a#ladder': { answer: 'A', risk: 1 }, 'b#ladder': { answer: 'B', risk: 2 } } }, { model: 'y', votes: { 'a#ladder': { answer: 'A' } } }]);
  ok(r.length === 1 && r[0].model === 'x' && r[0].votes[1].answer === 'B', 'a batch carries only the runners that answered every question in it, in its order');
}

// MARK: a runner earns its seat; why items were held
{
  const s = emptyState();
  const sent = Array.from({ length: 300 }, (_, i) => ({ item: { id: `q${i}` }, gold: 'A' }));
  const answers = Object.fromEntries(sent.map((x, i) => [x.item.id, { answer: i % 10 < 9 ? 'A' : 'B' }]));
  addRunnerVotes(s, 'good', sent, answers);
  addRunnerVotes(s, 'weak', sent, Object.fromEntries(sent.map((x, i) => [x.item.id, { answer: i % 2 ? 'A' : 'C' }])));
  ok(s.runners.good.answered === 300 && s.runners.good.right === 270, 'every blind answer of a runner is counted against the gold key, seated or not');
  ok(runnerSeated(s, 'good') && !runnerSeated(s, 'weak') && !runnerSeated(s, 'unknown'), 'a seat only at 80% or more by the lower bound (90% of 300 earns it, 50% does not)');
  addRunnerVotes(s, 'new', sent.slice(0, 50), answers);
  ok(!runnerSeated(s, 'new'), 'and not before 200 answers');
  addHeld(s, 'check', ['Fewer than three independent blind solves reached the key.', 'No official source states it word for word yet.']);
  addHeld(s, 'flagged', ['Checkers from 2 different model families, solving it without the key, chose another answer (B, C).']);
  addHeld(s, 'verified', ['anything']);
  ok(s.held['No official source states it word for word yet.'] === 1 && s.held['Checkers from 2 different model families, solving it without the key, chose another answer.'] === 1 && !s.held.anything,
     'why items were held is counted by reason, letters cut, Verified ones not');
  s.spend = { month: '2026-10', start: 1, end: 11.5, cap: 90 };
  const md = progressMarkdown({ ...s, updated: 'now' });
  ok(md.includes('$11.50 of the $90 cap') && md.includes('| good | 300 | 270 |') && md.includes('No official source'), 'the page shows the spend, the runners and the reasons');
}

console.log(failures ? `\n${failures} failed` : '\nall passed');
process.exit(failures ? 1 : 0);
