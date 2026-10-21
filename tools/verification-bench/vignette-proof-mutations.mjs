#!/usr/bin/env node
// B1, mutation soundness of the vignette checker (server/vignette-proof.js;
// docs/verification/vignette-proof-research.md, the benches table).
//
// Every accepted seed item is mutated in ways that make its keyed answer
// wrong or no longer decided - a finding negated, hedged, moved to someone
// else or into the past; a number across the cut-off or out of the reading
// window; a criterion dropped; the key or the options changed; the question
// turned around; a second, conflicting reading; an older rule edition; a
// stale packet - and the proposer (tools/criteria/stub-proposer.mjs) writes
// the proof again for the mutated item wherever it still can. The checker
// must accept none of them. Neutral edits (age, sex, pregnancy, which the
// rule does not read) are run too, to show the bench is not passing by
// refusing everything.
//
//   node tools/verification-bench/vignette-proof-mutations.mjs [--n 300000] [--seconds 0] [--seed 1] [--out file.json]
//
// --seconds stops early at a time budget (CI runs as many as it allows).
// Exit 1 if any wrong item is accepted. Deterministic for a seed; no
// network, no model.

import { writeFileSync } from 'node:fs';
import { checkVignette } from '../../server/vignette-proof.js';
import { propose } from '../criteria/stub-proposer.mjs';

const arg = (name, d) => { const i = process.argv.indexOf(`--${name}`); return i > 0 ? process.argv[i + 1] : d; };
const N = Number(arg('n', 300000));
const SECONDS = Number(arg('seconds', 0));
const SEED = Number(arg('seed', 1));
const OUT = arg('out', null);

function rng(seed) {
  let a = seed >>> 0;
  return () => { a = (a + 0x6d2b79f5) >>> 0; let t = a; t = Math.imul(t ^ (t >>> 15), t | 1); t ^= t + Math.imul(t ^ (t >>> 7), t | 61); return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
}
const rand = rng(SEED);
const pick = xs => xs[Math.floor(rand() * xs.length)];
const int = (a, b) => a + Math.floor(rand() * (b - a + 1));

// MARK: seed items the checker accepts (the 5 mm rule, every written form)

const PEOPLE = [['man', 'His'], ['woman', 'Her'], ['patient', 'The patient\'s']];
const GROUPS = [
  { slot: 'tst_group', text: 'with HIV', line: (age, who) => `A ${age}-year-old ${who} with HIV attends clinic.` },
  { slot: 'tst_group', text: 'chest x-ray findings suggestive of previous TB disease', line: (age, who) => `A ${age}-year-old ${who} has chest x-ray findings suggestive of previous TB disease.` },
  { slot: 'tst_group', text: 'organ transplant', line: (age, who) => `A ${age}-year-old ${who} is an organ transplant recipient.` },
];
const TESTS = ['TB skin test', 'tuberculin skin test', 'Mantoux tuberculin skin test', 'TST'];
const READS = [h => `${h} hours after placement`, h => `${h} hours after administration`, h => `${h} hours later`];
const SIZES = [mm => `${mm} mm of induration`, mm => `induration of ${mm} mm`, mm => `${mm} mm induration`, mm => `${mm}-mm area of induration`];
const QUESTION = 'What is the most appropriate interpretation of this result?';

function seed() {
  const age = int(18, 80);
  const [who, pron] = pick(PEOPLE);
  const g = pick(GROUPS);
  const tst = pick(TESTS);
  const hours = int(48, 72);
  const mm = int(5, 25);
  const read = pick(READS)(hours);
  const size = pick(SIZES)(mm);
  const s1 = g.line(age, who);
  const s2 = `${pron} ${tst}, read ${read}, shows ${size}.`;
  const findings = [{ slot: g.slot, text: g.text }, { slot: 'tst', text: tst }, { slot: 'read_hours', text: read }, { slot: 'induration_mm', text: size }];
  return { age, who, pron, g, tst, hours, mm, read, size, s1, s2, q: QUESTION, findings, options: ['Positive', 'Negative'], key: 0, extra: '', explanation: '' };
}
const plan = s => ({ rule: 'cdc-tst-5mm', ver: s.ver ?? '1', findings: s.findings, eliminates: s.eliminates ?? [{ option: s.key === 0 ? 1 : 0, by: 'exclusive' }] });
const build = s => {
  const item = { kind: 'mcq', stem: [s.s1, s.extra, s.s2, s.q].filter(Boolean).join(' '), options: s.options, key: s.key, ...(s.explanation ? { explanation: s.explanation } : {}) };
  return [item, propose(item, plan(s))];
};

// MARK: mutations: each makes the key wrong or undecided (wrong: true) or
// leaves it right (wrong: false)

const swapIn = (s, field, from, to) => ({ ...s, [field]: s[field].replace(from, to), findings: s.findings });
const MUTATIONS = {
  negate: s => {
    const where = pick(['s1', 's2']);
    const forms = where === 's1'
      ? [[s.g.text, `no ${s.g.text}`], [s.g.text, `not ${s.g.text}`], ['attends', 'denies having HIV and attends'], [s.who, `${s.who} without`]]
      : [['shows', 'does not show'], ['shows', 'never shows'], ['shows', 'shows no'], [', read', ', not read']];
    const [a, b] = pick(forms);
    return swapIn(s, where, a, b);
  },
  hedge: s => {
    const w = pick(['possibly ', 'probably ', 'about ', 'approximately ', 'maybe ', 'may have ', 'reportedly ']);
    return pick([() => swapIn(s, 's2', 'shows ', `shows ${w}`), () => swapIn(s, 's1', `${s.age}-year-old`, `${s.age}-year-old ${w.trim()}`)])();
  },
  other_person: s => {
    const rel = pick(['wife', 'husband', 'brother', 'mother', 'partner', 'roommate', 'child']);
    return pick([
      () => swapIn(s, 's1', `${s.who} `, `${s.who} whose ${rel} is `),
      () => ({ ...s, s2: s.s2.replace(`${s.pron} `, `${s.pron} ${rel}'s `) }),
    ])();
  },
  past: s => {
    const w = pick(['previously ', 'last year ', 'in childhood ', 'formerly ']);
    return pick([() => swapIn(s, 's2', 'shows', `${w}showed`), () => swapIn(s, 's1', `${s.age}-year-old`, `${s.age}-year-old ${w.trim()}`)])();
  },
  under_cutoff: s => {
    const mm = int(0, 4);
    const size = s.size.replace(String(s.mm), String(mm));
    return { ...s, s2: s.s2.replace(s.size, size), findings: s.findings.map(f => (f.slot === 'induration_mm' ? { ...f, text: size } : f)) };
  },
  outside_window: s => {
    const h = pick([int(0, 47), int(73, 400)]);
    const read = s.read.replace(String(s.hours), String(h));
    return { ...s, s2: s.s2.replace(s.read, read), findings: s.findings.map(f => (f.slot === 'read_hours' ? { ...f, text: read } : f)) };
  },
  wrong_unit: s => {
    const size = pick([s.size.replace('mm', 'cm'), s.size.replace('induration', 'erythema'), s.size.replace('induration', 'redness')]);
    return { ...s, s2: s.s2.replace(s.size, size), findings: s.findings.map(f => (f.slot === 'induration_mm' ? { ...f, text: size } : f)) };
  },
  other_group: s => {
    const line = pick([`A ${s.age}-year-old mycobacteriology laboratory worker attends clinic.`, `A ${s.age}-year-old ${s.who} with diabetes attends clinic.`,
      `A ${s.age}-year-old ${s.who} with no known risk factors attends clinic.`, `A ${s.age}-year-old ${s.who} attends clinic.`]);
    const text = line.includes('mycobacteriology') ? 'mycobacteriology laboratory worker' : null;
    return { ...s, s1: line, findings: s.findings.map(f => (f.slot === 'tst_group' ? (text ? { ...f, text } : null) : f)).filter(Boolean) };
  },
  drop_criterion: s => {
    const slot = pick(['read_hours', 'tst_group', 'induration_mm']);
    if (slot === 'read_hours') return { ...s, s2: s.s2.replace(`, read ${s.read},`, ''), findings: s.findings.filter(f => f.slot !== slot) };
    if (slot === 'tst_group') return { ...s, s1: `A ${s.age}-year-old ${s.who} attends clinic.`, findings: s.findings.filter(f => f.slot !== slot) };
    return { ...s, s2: s.s2.replace(` shows ${s.size}`, ' is read'), findings: s.findings.filter(f => f.slot !== slot) };
  },
  conflicting_reading: s => {
    const extra = pick([`A repeat test read 72 hours later shows ${int(0, 4)} mm of induration.`, `It was also read at ${int(73, 200)} hours after placement.`,
      'An HIV test is due.', `A second TB skin test shows ${int(0, 30)} mm of induration.`]);
    return { ...s, extra };
  },
  key_swap: s => ({ ...s, key: 1, eliminates: [{ option: 0, by: 'exclusive' }] }),
  options_reordered: s => ({ ...s, options: ['Negative', 'Positive'], key: 0, eliminates: [{ option: 1, by: 'exclusive' }] }),
  option_added: s => ({ ...s, options: [...s.options, pick(['Indeterminate', 'Repeat the test in 1 week', 'Boosted reaction', 'Latent TB infection'])],
    eliminates: [{ option: 1, by: 'exclusive' }, { option: 2, by: 'exclusive' }] }),
  question_turned: s => ({ ...s, q: pick(['What is NOT the most appropriate interpretation of this result?', 'What is the least appropriate interpretation of this result?',
    'Which is an incorrect interpretation of this result?', 'What is the most inappropriate interpretation of this result?',
    'What is possibly the most appropriate interpretation of this result?', 'What is the next best step?', 'What is the most likely diagnosis?',
    'What would be the interpretation of this result if he had no risk factors?']) }),
  older_edition: s => ({ ...s, ver: pick(['0', '2', '1.0']) }),
  false_explanation: s => ({ ...s, explanation: pick(['He has latent TB infection.', 'A reaction of 5 mm is always positive.', 'Treat with isoniazid for 9 months.',
    'An induration of 5 or more millimeters is considered positive in: everyone.']) }),
  stale_packet: null,
};
const NEUTRAL = {
  age: s => { const age = int(18, 80); return { ...s, age, s1: s.s1.replace(`${s.age}-year-old`, `${age}-year-old`) }; },
  sex: s => ({ ...s, s1: s.s1.replace(` ${s.who} `, s.who === 'man' ? ' woman ' : ' man '), s2: s.s2.replace(`${s.pron} `, s.pron === 'His' ? 'Her ' : 'His ') }),
  pregnancy: s => ({ ...s, s1: s.s1.replace(` ${s.who} `, ' pregnant woman ') }),
};

// MARK: the run

const counts = {};
const tally = (name, wrong, accepted, why) => {
  const c = counts[name] ||= { wrong, run: 0, accepted: 0, why: {} };
  c.run++;
  if (accepted) c.accepted++;
  else c.why[why] = (c.why[why] || 0) + 1;
};
const names = Object.keys(MUTATIONS);
const neutral = Object.keys(NEUTRAL);
const started = Date.now();
let seeds = 0;
let seedsAccepted = 0;
let run = 0;
let wrongAccepted = 0;
const examples = [];
while (run < N && (!SECONDS || (Date.now() - started) / 1000 < SECONDS)) {
  const s = seed();
  seeds++;
  const [item, packet] = build(s);
  const base = checkVignette(item, packet);
  if (!base.ok) { tally('seed-refused', false, false, base.why); continue; }
  seedsAccepted++;
  for (let k = 0; k < 24 && run < N; k++) {
    run++;
    if (rand() < 0.1) {
      const name = pick(neutral);
      const [mi, mp] = build(NEUTRAL[name](s));
      const r = checkVignette(mi, mp);
      tally(`neutral:${name}`, false, r.ok, r.why);
      continue;
    }
    const name = pick(names);
    let mi;
    let mp;
    if (name === 'stale_packet') {
      // the item edited after its proof was written, one character
      const i = int(0, item.stem.length - 1);
      const ch = pick(['x', '9', ' ', '', 'n', '.']);
      mi = { ...item, stem: item.stem.slice(0, i) + ch + item.stem.slice(i + 1) };
      if (mi.stem === item.stem) { run--; continue; }
      mp = packet;
    } else {
      [mi, mp] = build(MUTATIONS[name](s));
      if (mi.stem === item.stem && mi.key === item.key && JSON.stringify(mi.options) === JSON.stringify(item.options)
        && (mi.explanation || '') === (item.explanation || '') && mp.proves.ver === packet.proves.ver) { run--; continue; }
    }
    const r = checkVignette(mi, mp);
    tally(name, true, r.ok, r.why);
    if (r.ok) { wrongAccepted++; if (examples.length < 10) examples.push({ name, stem: mi.stem, options: mi.options, key: mi.key }); }
  }
}
const seconds = (Date.now() - started) / 1000;
const wrongRun = Object.values(counts).filter(c => c.wrong).reduce((a, c) => a + c.run, 0);
const neutralRun = Object.entries(counts).filter(([k]) => k.startsWith('neutral:')).reduce((a, [, c]) => a + c.run, 0);
const neutralOk = Object.entries(counts).filter(([k]) => k.startsWith('neutral:')).reduce((a, [, c]) => a + c.accepted, 0);
// with none accepted, the 95% upper bound on the false-acceptance rate is
// about 3/n (the rule of three); with k accepted it is reported as k/n
const bound = wrongAccepted === 0 ? 3 / Math.max(1, wrongRun) : null;
const summary = {
  bench: 'B1 vignette proof mutations', seed: SEED, seconds: Math.round(seconds * 10) / 10,
  seeds, seedsAccepted, mutations: wrongRun, wrongAccepted, upperBound95: bound,
  neutral: { run: neutralRun, accepted: neutralOk }, byKind: counts, examples,
};
console.log(`B1: ${wrongRun} wrong-making mutations of ${seedsAccepted} accepted seed items, ${wrongAccepted} accepted`
  + (bound ? ` (95% upper bound ${bound.toExponential(1)})` : '') + `; neutral edits ${neutralOk} of ${neutralRun} still accepted; ${summary.seconds} s`);
for (const [k, c] of Object.entries(counts).sort()) {
  console.log(`  ${k.padEnd(22)} ${String(c.run).padStart(7)} run  ${String(c.accepted).padStart(6)} accepted  ${Object.entries(c.why).sort((a, b) => b[1] - a[1]).slice(0, 3).map(([w, n]) => `${w} ${n}`).join(', ')}`);
}
for (const e of examples) console.log('  ACCEPTED', e.name, JSON.stringify(e).slice(0, 300));
if (OUT) writeFileSync(OUT, `${JSON.stringify(summary, null, 1)}\n`);
process.exit(wrongAccepted ? 1 : 0);
