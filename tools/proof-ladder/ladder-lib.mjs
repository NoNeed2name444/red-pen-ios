// The proof ladder (docs/verification/proof-plan.md): Verified measured on
// the live Worker, a little every day, until it is proven 99.9%, then 99.99%,
// then 99.999% right at 95% confidence. Pure, so it is tested
// (tests/proof-ladder/ladder.test.mjs); ladder.mjs does the fetching.
//
// What counts: every item is checked once (the Worker caches a verdict, so
// a repeat would be no new witness), each with its gold key or with a
// distractor keyed instead. A Verified verdict on a distractor is an error.
// The bound is on the error rate among Verified verdicts: n Verified with k
// errors proves accuracy of at least the exact one-sided 95% lower bound.
import { lowerBound } from '../jev-standin/oath-bench.mjs';
import { familyOf } from '../../server/accuracy-model.js';

export const RUNGS = [
  { name: '99.9%', rate: 1e-3 },
  { name: '99.99%', rate: 1e-4 },
  { name: '99.999%', rate: 1e-5 },
];

/// Verified verdicts needed with no error for accuracy >= 1 - rate at 95%.
export const needed = rate => Math.ceil(Math.log(0.05) / Math.log(1 - rate));

export function emptyState() {
  return { v: 1, started: null, updated: null, checked: 0, right: 0, wrong: 0, verified: 0, errors: 0, flagged: 0, check: 0,
           unchecked: 0, rightVerified: 0, cursor: {}, days: [], spentByLadder: 0, families: {}, runners: {}, held: {}, spend: null };
}

/// The ledger of each family's blind answers against the gold key: one
/// item's votes (as the Worker returns them, runner ballots among them),
/// counted once per family, in place. `gold` the gold option's letter.
export function addFamilyVotes(state, gold, votes) {
  state.families ||= {};
  const seen = new Set();
  for (const v of votes || []) {
    if (!v?.blind || !v.answer) continue;
    const family = familyOf(v.model);
    if (seen.has(family)) continue;
    seen.add(family);
    const f = state.families[family] ||= { answered: 0, right: 0, runner: false };
    f.answered++;
    if (v.answer === gold) f.right++;
    if (v.runner) f.runner = true;
  }
  return state;
}

/// Adds one batch's results ({ truth, verdict }) to the state, in place.
export function addResults(state, results, day) {
  let d = state.days.find(x => x.day === day);
  if (!d) { d = { day, checked: 0, verified: 0, errors: 0 }; state.days.push(d); }
  for (const r of results) {
    const v = r.verdict || 'unchecked';
    if (v === 'unchecked') { state.unchecked++; continue; }
    state.checked++; d.checked++;
    state[r.truth === 'wrong' ? 'wrong' : 'right']++;
    if (v === 'verified') {
      state.verified++; d.verified++;
      if (r.truth === 'wrong') { state.errors++; d.errors++; } else state.rightVerified++;
    } else if (v === 'flagged') state.flagged++;
    else state.check++;
  }
  return state;
}

/// Each runner model's blind answers against the gold key, from its whole
/// ballot (seated or not), for the items sent: what decides whether it may
/// hold a seat (runnerSeated). `answers` { id: { answer } }.
export function addRunnerVotes(state, model, sentItems, answers) {
  state.runners ||= {};
  const r = state.runners[model] ||= { answered: 0, right: 0 };
  for (const x of sentItems) {
    const a = answers?.[x.item.id];
    if (!a?.answer) continue;
    r.answered++;
    if (a.answer === x.gold) r.right++;
  }
  return state;
}

/// Whether a runner model may hold a seat: once its blind answers, by the
/// 95% lower bound, are at least `bar` right on at least `least` questions
/// (a weak witness in a seat stops the others' agreement from counting).
export function runnerSeated(state, model, bar = 0.8, least = 200) {
  const r = state.runners?.[model];
  return !!r && r.answered >= least && lowerBound(r.right, r.answered) >= bar;
}

/// Why the items not Verified were held, counted by reason (letters cut, so
/// the same reason counts once).
export function addHeld(state, verdict, reasons) {
  if (verdict === 'verified' || !Array.isArray(reasons)) return state;
  state.held ||= {};
  for (const r of new Set(reasons.map(x => String(x).replace(/\s*\([A-J](?:, [A-J])*\)/g, '').slice(0, 160)))) state.held[r] = (state.held[r] || 0) + 1;
  return state;
}

/// Where the ladder stands: the bound proven so far, the rung being climbed,
/// and how many more Verified verdicts it needs (with no further error).
export function standing(state) {
  const n = state.verified, k = state.errors;
  const bound = n ? lowerBound(n - k, n) : null;
  const rung = RUNGS.find(r => bound === null || bound < 1 - r.rate) || null;
  let more = null;
  if (rung) {
    // the smallest n' >= n with (n' - k) of n' proving the rung
    if (!k) more = Math.max(0, needed(rung.rate) - n);
    else { let m = n; while (lowerBound(m - k, m) < 1 - rung.rate && m < n + 5e7) m = Math.ceil(m * 1.05) + 1; more = m - n; }
  }
  const reach = state.checked ? state.verified / state.checked : null;
  return { bound, proven: RUNGS.filter(r => bound !== null && bound >= 1 - r.rate).map(r => r.name), rung: rung?.name || null,
           moreVerified: more, verifiedPerChecked: reach, moreChecks: reach ? Math.ceil(more / reach) : null };
}

/// How much of the cloud checker's month the ladder may have spent by now:
/// its share of the cap, spread evenly over the month, so it never uses a
/// month's dollars in its first days and always leaves the owner's own
/// checks the rest of the cap. `now` a Date.
export function paceLimit(share, now) {
  const days = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth() + 1, 0)).getUTCDate();
  const elapsed = (now.getUTCDate() - 1 + (now.getUTCHours() + now.getUTCMinutes() / 60) / 24) / days;
  return share * Math.min(1, Math.max(0, elapsed));
}

/// Whether the ladder may send another batch: the month's spend (all of it,
/// the owner's own checks too) under the paced share, and under the cap
/// with room for one more batch's worst case.
export function mayContinue({ spent, cap, share, now, batchWorst = 0.25 }) {
  if (!Number.isFinite(spent) || !Number.isFinite(cap)) return false;
  return spent + batchWorst <= cap && spent <= paceLimit(Math.min(share, cap), now);
}

/// The progress page, for people.
export function progressMarkdown(state) {
  const s = standing(state);
  const pct = x => (x === null || x === undefined ? 'n/a' : `${(100 * x).toFixed(4)}%`);
  const lines = [
    '# The proof ladder',
    '',
    `Updated ${state.updated}. Live Worker, every item checked once, half with a distractor keyed (a Verified distractor is an error).`,
    '',
    '| checked | Verified | errors among Verified | proven accuracy of Verified (95%, one-sided) |',
    '|---|---|---|---|',
    `| ${state.checked} | ${state.verified} | ${state.errors} | ${pct(s.bound)} |`,
    '',
    '| rung | Verified needed with no error | status |',
    '|---|---|---|',
    ...RUNGS.map(r => `| ${r.name} | ${needed(r.rate).toLocaleString('en-GB')} | ${s.proven.includes(r.name) ? 'proven' : r.name === s.rung ? `climbing: ${s.moreVerified?.toLocaleString('en-GB')} more Verified${s.moreChecks ? ` (about ${s.moreChecks.toLocaleString('en-GB')} more checks at today's rate)` : ''}` : 'waiting'} |`),
    '',
    `Verified per check so far: ${s.verifiedPerChecked === null ? 'n/a' : `${(100 * s.verifiedPerChecked).toFixed(2)}%`}. Flagged ${state.flagged}, Check this ${state.check}, not checked ${state.unchecked}.`,
    '',
    '| day | checked | Verified | errors |',
    '|---|---|---|---|',
    ...state.days.slice(-14).map(d => `| ${d.day} | ${d.checked} | ${d.verified} | ${d.errors} |`),
  ];
  if (state.spend) lines.push('', `The cloud checker this month (${state.spend.month}): $${state.spend.end.toFixed(2)} of the $${state.spend.cap} cap at the end of the last run, $${(state.spend.end - state.spend.start).toFixed(2)} of it during that run.`);
  const runners = Object.entries(state.runners || {});
  if (runners.length) lines.push('', 'Runner voters, every blind answer for the items sent (a runner holds a seat only at 80% or more by the lower bound, on 200 or more):', '',
    '| runner | answered | right | right, 95% lower bound | seated |', '|---|---|---|---|---|',
    ...runners.map(([m, c]) => `| ${m} | ${c.answered} | ${c.right} | ${c.answered ? pct(lowerBound(c.right, c.answered)) : 'n/a'} | ${runnerSeated(state, m) ? 'yes' : 'no'} |`));
  const held = Object.entries(state.held || {}).sort((a, b) => b[1] - a[1]).slice(0, 8);
  if (held.length) lines.push('', 'Why items were not Verified (each reason counted once per item):', '', '| reason | items |', '|---|---|', ...held.map(([r, n]) => `| ${r} | ${n} |`));
  const fams = Object.entries(state.families || {}).sort((a, b) => b[1].answered - a[1].answered);
  if (fams.length) lines.push('', 'Each family\'s blind answers against the gold key (one witness per family per question; "runner": run on GitHub\'s CPU with no key):', '',
    '| family | answered | right | right, 95% lower bound |', '|---|---|---|---|',
    ...fams.map(([f, c]) => `| ${f}${c.runner ? ' (runner)' : ''} | ${c.answered} | ${c.right} | ${c.answered ? pct(lowerBound(c.right, c.answered)) : 'n/a'} |`));
  return lines.join('\n') + '\n';
}
