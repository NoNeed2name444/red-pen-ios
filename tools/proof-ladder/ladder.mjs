// One day's climb of the proof ladder (ladder-lib.mjs) against the live
// Worker, as the owner's bench (x-bench: its own daily allowance, never the
// owner's app's). Run by .github/workflows/proof-ladder.yml once a day.
//
//   WORKER=https://... KEY=<owner key> node tools/proof-ladder/ladder.mjs \
//     --state progress.json --out DIR [--max-items 600] [--hours 5] [--share 60] [--all]
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
import { readFileSync, writeFileSync, mkdirSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { validQuestionOf } from '../verification-bench/datasets.mjs';
import { claimsFor } from '../../server/proof.js';
import { half } from '../jev-standin/triage-lib.mjs';
import { emptyState, addResults, standing, mayContinue, progressMarkdown } from './ladder-lib.mjs';

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
/// questions, chosen by id, a distractor keyed ('wrong').
export function itemOf(q) {
  const wrong = half(q.id) === 1;
  if (!wrong) return { truth: 'right', item: { ...q, id: `${q.id}#ladder` } };
  const others = q.options.map((_, i) => i).filter(i => i !== q.key);
  let h = 0;
  for (const c of q.id) h = (h * 31 + c.charCodeAt(0)) >>> 0;
  return { truth: 'wrong', item: { ...q, id: `${q.id}#ladder`, key: others[h % others.length] } };
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

async function main() {
  const arg = (name, fallback = null) => { const i = process.argv.indexOf(`--${name}`); return i > 0 ? process.argv[i + 1] : fallback; };
  const statePath = arg('state', 'progress.json');
  const outDir = arg('out', 'out/ladder');
  const maxItems = Number(arg('max-items', '600'));
  const until = Date.now() + Number(arg('hours', '5')) * 3600_000;
  const share = Number(arg('share', '60'));
  const all = process.argv.includes('--all');
  const worker = String(process.env.WORKER || '').replace(/\/+$/, '');
  const auth = { authorization: `Bearer ${process.env.KEY}` };
  if (!worker || !process.env.KEY) { console.error('WORKER and KEY are needed (the live Worker, the owner key).'); process.exit(2); }
  mkdirSync(outDir, { recursive: true });
  const state = existsSync(statePath) ? JSON.parse(readFileSync(statePath, 'utf8')) : emptyState();
  const day = new Date().toISOString().slice(0, 10);
  state.started ||= day;
  let sent = 0, stopped = 'the day\'s item limit';

  const spend = async () => {
    const c = await getJSON(`${worker}/costs`, { method: 'POST', headers: { ...auth, 'content-type': 'application/json' }, body: '{}' }).catch(() => null);
    return c?.claude && Number.isFinite(c.claude.spent) ? c.claude : null;
  };
  // the questions, page by page from where the last day stopped; `scan` is
  // how far this run has read, state.cursor how far it has sent
  const queue = [];
  const scan = {};
  const refill = async () => {
    for (const src of SOURCES) {
      let at = scan[src.id] ?? state.cursor[src.id] ?? 0;
      while (queue.length < 8 && at < src.total) {
        const page = await getJSON(`https://datasets-server.huggingface.co/rows?dataset=${encodeURIComponent(src.dataset)}&config=${src.config}&split=${src.split}&offset=${at}&length=100`);
        const rows = page.rows || [];
        rows.forEach(({ row }, i) => {
          const q = validQuestionOf(row, at + i);
          if (q && (all || readable(q))) queue.push({ ...itemOf({ ...q, id: `${src.id}:${q.id.split(':').pop()}` }), at: at + i + 1, src: src.id });
        });
        at += rows.length || 100;
        if (!rows.length) at = src.total;
        scan[src.id] = at;
        await sleep(400);
      }
      if (queue.length >= 8) break;
    }
  };

  while (sent < maxItems && Date.now() < until) {
    const c = await spend();
    if (!c) { stopped = 'the Worker did not report the cloud checker\'s spend (/costs)'; break; }
    if (!mayContinue({ spent: c.spent, cap: c.cap, share, now: new Date() })) { stopped = `the paced share of the cloud checker (spent ${c.spent.toFixed(2)} of ${c.cap} this month)`; break; }
    if (queue.length < 4) await refill();
    if (!queue.length) { stopped = 'no questions left in the sources'; break; }
    const batch = queue.splice(0, 4);
    let res = null;
    for (let attempt = 0; attempt < 5; attempt++) {
      res = await fetch(`${worker}/accuracy/check`, { method: 'POST', headers: { ...auth, 'content-type': 'application/json', 'x-bench': '1' },
        body: JSON.stringify({ items: batch.map(b => b.item) }) }).catch(() => null);
      if (res && res.status !== 429 && res.status !== 503) break;
      await sleep(30_000 * (attempt + 1));
    }
    if (!res?.ok) { stopped = `the Worker answered ${res?.status ?? 'nothing'}`; queue.unshift(...batch); break; }
    const body = await res.json();
    const results = batch.map((b, n) => ({ truth: b.truth, verdict: body.items?.[n]?.verdict || 'unchecked' }));
    addResults(state, results, day);
    for (const b of batch) state.cursor[b.src] = Math.max(state.cursor[b.src] || 0, b.at);
    sent += batch.length;
    process.stdout.write(`\r${sent} sent, ${state.verified} Verified in all, ${state.errors} errors`);
  }
  console.log('');
  // what was read but not sent is read again next time; what was read and
  // held nothing the proof can read is not
  for (const src of SOURCES) {
    if (scan[src.id] === undefined) continue;
    const unsent = queue.filter(b => b.src === src.id).map(b => b.at - 1);
    state.cursor[src.id] = unsent.length ? Math.min(...unsent) : scan[src.id];
  }
  state.updated = new Date().toISOString();
  const s = standing(state);
  state.last = { day, sent, stopped, standing: s };
  writeFileSync(statePath, JSON.stringify(state, null, 1) + '\n');
  writeFileSync(join(outDir, 'progress.md'), progressMarkdown(state) + `\nToday: ${sent} sent; stopped at ${stopped}.\n`);
  console.log(`stopped at ${stopped}; proven so far: ${s.proven.join(', ') || 'none'}; bound ${s.bound}`);
}

if (import.meta.url === `file://${process.argv[1]}`) main().catch(e => { console.error(e.message); process.exit(1); });
