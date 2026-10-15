// One day's climb of the proof ladder (ladder-lib.mjs) against the live
// Worker, as the owner's bench (x-bench: its own daily allowance, never the
// owner's app's). Run by .github/workflows/proof-ladder.yml once a day.
//
//   node tools/proof-ladder/ladder.mjs --state progress.json --pick items.json [--max-items 600] [--all]
//   WORKER=https://... KEY=<owner key> node tools/proof-ladder/ladder.mjs \
//     --state progress.json --out DIR [--items items.json] [--ballots DIR] [--runner-seats 1] [--runner-bar 0.8] [--pool-batches 15] [--max-items 600] [--hours 5] [--share 60] [--all]
//
// --pick chooses the day's questions only; the runner voters answer them
// blind on GitHub's CPU (tools/runner-voter), and the climb sends each batch
// with their answers (--ballots), so one family's seat costs no live call.
//
// Items: public exam questions with gold keys whose licences allow
// commercial use (SOURCES), never the ones the triage is tuned on or the
// verification bench is measured on (other splits). Each question is used
// once, with its own key or (for half, chosen by its id) a distractor keyed.
// By default only questions the source proof can read (a one-sentence
// question asking for the best answer): no other can reach Verified today,
// so checking them would spend the free tiers for nothing. --all takes
// every question (for when the vignette route is live).
//
// Spend: the free families answer first; the cloud checker only where they
// fail, and the Worker holds it to CLAUDE_MONTHLY_USD. The ladder also paces
// itself inside its own share (--share dollars a month, spread evenly over
// the month), reading the month's spend from the Worker's /costs; when the
// Worker does not report it, the ladder stops.
import { readFileSync, writeFileSync, mkdirSync, existsSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import { validQuestionOf } from '../verification-bench/datasets.mjs';
import { claimsFor } from '../../server/proof.js';
import { half } from '../jev-standin/triage-lib.mjs';
import { familyOf } from '../../server/accuracy-model.js';
import { emptyState, addResults, addFamilyVotes, addRunnerVotes, runnerSeated, addHeld, standing, mayContinue, progressMarkdown } from './ladder-lib.mjs';

/// Where the questions come from: split and licence (each read 14 Oct 2026).
export const SOURCES = [
  { id: 'medmcqa-train', dataset: 'openlifescienceai/medmcqa', config: 'default', split: 'train', total: 182822, licence: 'Apache-2.0' },
  { id: 'medqa-train', dataset: 'GBaker/MedQA-USMLE-4-options', config: 'default', split: 'train', total: 10178, licence: 'CC-BY-4.0' },
];

/// Whether the source proof can read a question at all (proof.js: a
/// vignette, a negation or a stem with no "best answer" cue it cannot).
export function readable(q) {
  try { return !claimsFor({ ...q, kind: 'mcq' }, 5e6).why; } catch { return false; }
}

/// The item a question becomes: its own key ('right'), or for half of the
/// questions, chosen by id, a distractor keyed ('wrong'). `gold` is the gold
/// key's letter, kept here and never sent: the ledger of each family's blind
/// answers is counted against it.
export function itemOf(q) {
  const wrong = half(q.id) === 1;
  const gold = String.fromCharCode(65 + q.key);
  if (!wrong) return { truth: 'right', gold, item: { ...q, id: `${q.id}#ladder` } };
  const others = q.options.map((_, i) => i).filter(i => i !== q.key);
  let h = 0;
  for (const c of q.id) h = (h * 31 + c.charCodeAt(0)) >>> 0;
  return { truth: 'wrong', gold, item: { ...q, id: `${q.id}#ladder`, key: others[h % others.length] } };
}

/// The runner ballots for one batch, as /accuracy/check takes them: each
/// runner model that answered every item in the batch, its answers in the
/// batch's order (server/runner-voters.js). `ballots`: [{ model, votes: { id:
/// { answer, risk } } }], one per runner model.
export function runnerFor(batch, ballots) {
  return ballots
    .map(b => ({ model: b.model, votes: batch.map(x => b.votes?.[x.item.id] || null) }))
    .filter(b => b.votes.every(v => v && /^[A-J]$/.test(v.answer)));
}

const sleep = ms => new Promise(r => setTimeout(r, ms));
async function getJSON(url, init = {}, tries = 8) {
  for (let t = 0; ; t++) {
    let res = null;
    try { res = await fetch(url, init); } catch { /* network: retried */ }
    if (res?.ok) return res.json();
    if (t >= tries - 1 || (res && res.status < 500 && res.status !== 429)) throw new Error(`${url.split('?')[0]}: ${res?.status ?? 'unreachable'}`);
    const after = Number(res?.headers.get('retry-after'));
    await sleep(Math.min(60_000, Math.max(2000 * 2 ** t, after > 0 ? after * 1000 : 0)));
  }
}

/// The next `count` questions from where the ladder stopped (state.cursor),
/// page by page: [{ ...itemOf(q), at, src }], and how far each source was
/// read (`scanned`), so a question read but not sent is read again next time.
export async function pick(state, count, { all = false, page = getJSON } = {}) {
  const picked = [];
  const scanned = {};
  for (const src of SOURCES) {
    let at = state.cursor?.[src.id] ?? 0;
    while (picked.length < count && at < src.total) {
      const got = await page(`https://datasets-server.huggingface.co/rows?dataset=${encodeURIComponent(src.dataset)}&config=${src.config}&split=${src.split}&offset=${at}&length=100`);
      const rows = got.rows || [];
      let read = 0;
      for (const { row } of rows) {
        if (picked.length >= count) break;
        const q = validQuestionOf(row, at + read);
        if (q && (all || readable(q))) picked.push({ ...itemOf({ ...q, id: `${src.id}:${q.id.split(':').pop()}` }), at: at + read + 1, src: src.id });
        read++;
      }
      if (read < rows.length) { at += read; scanned[src.id] = at; break; }
      at += rows.length || 100;
      if (!rows.length) at = src.total;
      scanned[src.id] = Math.min(at, src.total);
      await sleep(page === getJSON ? 400 : 0);
    }
    if (picked.length >= count) break;
  }
  return { picked, scanned };
}

async function main() {
  const arg = (name, fallback = null) => { const i = process.argv.indexOf(`--${name}`); return i > 0 ? process.argv[i + 1] : fallback; };
  const statePath = arg('state', 'progress.json');
  const outDir = arg('out', 'out/ladder');
  const maxItems = Number(arg('max-items', '600'));
  const all = process.argv.includes('--all');
  mkdirSync(outDir, { recursive: true });
  // an older state gains the fields added since, empty
  const state = { ...emptyState(), ...(existsSync(statePath) ? JSON.parse(readFileSync(statePath, 'utf8')) : {}) };

  // --pick FILE: only choose the day's questions (no Worker), for the runner
  // voters to answer before the climb sends them
  if (arg('pick')) {
    const chosen = await pick(state, maxItems, { all });
    writeFileSync(arg('pick'), JSON.stringify(chosen) + '\n');
    console.log(`${chosen.picked.length} questions picked`);
    return;
  }

  const until = Date.now() + Number(arg('hours', '5')) * 3600_000;
  const share = Number(arg('share', '60'));
  const worker = String(process.env.WORKER || '').replace(/\/+$/, '');
  const auth = { authorization: `Bearer ${process.env.KEY}` };
  if (!worker || !process.env.KEY) { console.error('WORKER and KEY are needed (the live Worker, the owner key).'); process.exit(2); }
  const day = new Date().toISOString().slice(0, 10);
  state.started ||= day;
  let sent = 0, stopped = 'the day\'s item limit';

  const { picked: queue, scanned } = arg('items') ? JSON.parse(readFileSync(arg('items'), 'utf8')) : await pick(state, maxItems, { all });
  // the runner voters' answers (tools/runner-voter), when they ran
  const dir = arg('ballots');
  // in models.json's order, the most accurate first, and only as many as
  // the seats the ladder may fill (config.json runnerSeats), so the Worker
  // seats the runner the ledger trusts most
  const order = JSON.parse(readFileSync(new URL('../runner-voter/models.json', import.meta.url), 'utf8')).models.map(m => m.name);
  const seats = Number(arg('runner-seats', '1'));
  const bar = Number(arg('runner-bar', '0.8'));
  // the owner's bench is not held to an account's share of the Workers AI
  // pool, so the ladder holds itself: at most this many batches a day that a
  // Workers AI voter answered (about half the day's pool), leaving the rest
  // for students
  const poolBatches = Number(arg('pool-batches', '15'));
  let pooled = 0;
  const ballots = (dir && existsSync(dir) ? readdirSync(dir).filter(f => f.endsWith('.json')).map(f => JSON.parse(readFileSync(join(dir, f), 'utf8'))) : [])
    .filter(b => order.includes(b.model)).sort((a, b) => order.indexOf(a.model) - order.indexOf(b.model));
  // a runner's record before it was kept by model: its seated answers in
  // the family ledger (day one), so its seat is judged on what it has done
  state.runners ||= {};
  for (const b of ballots) {
    const fam = state.families?.[familyOf(b.model)];
    if (!state.runners[b.model] && fam?.runner) state.runners[b.model] = { answered: fam.answered, right: fam.right };
  }
  console.log(`${queue.length} questions; runner ballots from ${ballots.map(b => `${b.model} (${Object.keys(b.votes || {}).length})`).join(', ') || 'none'}`);

  const spend = async () => {
    const c = await getJSON(`${worker}/costs`, { method: 'POST', headers: { ...auth, 'content-type': 'application/json' }, body: '{}' }).catch(() => null);
    return c?.claude && Number.isFinite(c.claude.spent) ? c.claude : null;
  };
  const unsent = [...queue];
  while (sent < maxItems && Date.now() < until && unsent.length) {
    const c = await spend();
    if (c) {
      const month = new Date().toISOString().slice(0, 7);
      if (!state.spend || state.spend.month !== month || state.spend.day !== day) state.spend = { month, day, start: c.spent, end: c.spent, cap: c.cap };
      state.spend.end = c.spent;
    }
    if (!c) { stopped = 'the Worker did not report the cloud checker\'s spend (/costs)'; break; }
    if (!mayContinue({ spent: c.spent, cap: c.cap, share, now: new Date() })) { stopped = `the paced share of the cloud checker (spent ${c.spent.toFixed(2)} of ${c.cap} this month)`; break; }
    if (pooled >= poolBatches) { stopped = `the ladder's half of the Workers AI pool (${pooled} batches)`; break; }
    const batch = unsent.slice(0, 4);
    // a runner holds a seat only once its own record earns it; until then
    // its answers are counted in the ledger and not sent
    const runner = runnerFor(batch, ballots.filter(b => runnerSeated(state, b.model, bar))).slice(0, seats);
    let res = null;
    for (let attempt = 0; attempt < 5; attempt++) {
      res = await fetch(`${worker}/accuracy/check`, { method: 'POST', headers: { ...auth, 'content-type': 'application/json', 'x-bench': '1' },
        body: JSON.stringify({ items: batch.map(b => b.item), ...(runner.length ? { runner } : {}) }) }).catch(() => null);
      if (res && res.status !== 429 && res.status !== 503) break;
      await sleep(30_000 * (attempt + 1));
    }
    if (!res?.ok) { stopped = `the Worker answered ${res?.status ?? 'nothing'}`; break; }
    const body = await res.json();
    const results = batch.map((b, n) => ({ truth: b.truth, verdict: body.items?.[n]?.verdict || 'unchecked' }));
    addResults(state, results, day);
    batch.forEach((b, n) => { addFamilyVotes(state, b.gold, body.items?.[n]?.votes); addHeld(state, body.items?.[n]?.verdict, body.items?.[n]?.reasons); });
    for (const b of ballots) addRunnerVotes(state, b.model, batch, b.votes);
    if ((body.items || []).some(it => (it.votes || []).some(v => /^@cf\//.test(String(v.model))))) pooled++;
    unsent.splice(0, batch.length);
    for (const b of batch) state.cursor[b.src] = Math.max(state.cursor[b.src] || 0, b.at);
    sent += batch.length;
    process.stdout.write(`\r${sent} sent, ${state.verified} Verified in all, ${state.errors} errors`);
  }
  if (!unsent.length && sent) stopped = 'the day\'s questions, all sent';
  const last = await spend();
  if (last && state.spend) state.spend.end = last.spent;
  console.log('');
  // what was read but not sent is read again next time; what was read and
  // held nothing the proof can read is not
  for (const src of SOURCES) {
    if (scanned[src.id] === undefined) continue;
    const left = unsent.filter(b => b.src === src.id).map(b => b.at - 1);
    state.cursor[src.id] = left.length ? Math.min(...left) : scanned[src.id];
  }
  state.updated = new Date().toISOString();
  const s = standing(state);
  state.last = { day, sent, stopped, runners: ballots.map(b => b.model), standing: s };
  writeFileSync(statePath, JSON.stringify(state, null, 1) + '\n');
  writeFileSync(join(outDir, 'progress.md'), progressMarkdown(state) + `\nToday: ${sent} sent; stopped at ${stopped}.\n`);
  console.log(`stopped at ${stopped}; proven so far: ${s.proven.join(', ') || 'none'}; bound ${s.bound}`);
}

if (import.meta.url === `file://${process.argv[1]}`) main().catch(e => { console.error(e.message); process.exit(1); });
