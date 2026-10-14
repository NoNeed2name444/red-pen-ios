// The vignette route's switch (switches.js VIGNETTE_ROUTE) and its hooks in
// the verdict (accuracy-model.js, accuracy.js, provenance.js).
//
// 1. The switch: on only when VIGNETTE_ROUTE is "on"; off by default.
// 2. Off, nothing changed: today's features, verdict and reasons equal the
//    model as it was before the route (a frozen copy), over a fuzz of
//    hundreds of thousands of feature shapes; and describe gives the same
//    reply for an item whether or not it carries a proof packet.
// 3. On, nothing loosened: Verified still needs every condition it needed,
//    with an owner-signed vignette proof standing only where a source proof
//    stood; Checked needs all of those but the sign-off; a flagged item stays
//    flagged.
// 4. On, end to end through describe: the seed item at Checked with its
//    chains; a refused proof says why; a hold drops Checked to Check this.
//
// Run: node server/tests/vignette-route.test.mjs

import * as NOW from '../accuracy-model.js';
import * as BEFORE from './fixtures/accuracy-model-before-vignette.js';
import { describe, cleanItem } from '../accuracy.js';
import { vignetteRoute } from '../switches.js';
import { VIGNETTE_REASONS } from '../vignette-proof.js';
import { HOLD_REASONS } from '../provenance.js';
import { seedItem } from '../../tools/criteria/stub-proposer.mjs';

let failures = 0;
const ok = (cond, what) => { console.log((cond ? 'ok   ' : 'FAIL ') + what); if (!cond) failures++; };
const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);

// a seeded generator, so every run fuzzes the same shapes
function rng(seed) {
  let a = seed >>> 0;
  return () => { a = (a + 0x6d2b79f5) >>> 0; let t = a; t = Math.imul(t ^ (t >>> 15), t | 1); t ^= t + Math.imul(t ^ (t >>> 7), t | 61); return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
}
const rand = rng(20261014);
const pick = xs => xs[Math.floor(rand() * xs.length)];
const maybe = (x, q = 0.5) => (rand() < q ? x : undefined);

// MARK: 1. the switch

const table = [[{}, false], [{ VIGNETTE_ROUTE: '' }, false], [{ VIGNETTE_ROUTE: 'off' }, false], [{ VIGNETTE_ROUTE: 'true' }, false],
  [{ VIGNETTE_ROUTE: '1' }, false], [{ VIGNETTE_ROUTE: 'yes' }, false], [{ VIGNETTE_ROUTE: 'onn' }, false], [undefined, false], [null, false],
  [{ VIGNETTE_ROUTE: 'on' }, true], [{ VIGNETTE_ROUTE: ' ON ' }, true]];
ok(table.every(([env, want]) => vignetteRoute(env) === want), `VIGNETTE_ROUTE: on only for "on" (${table.length} settings), off by default`);

// MARK: 2. off: exactly as before

const FAMS = ['bench:family-a', 'bench:family-b', 'bench:family-c', 'bench:family-d'];
function randomF() {
  const f = {
    bias: 1, no_models: pick([0, 0, 0, 1]), rule_severe: pick([0, 0, 0, 1, 2]), rule_minor: pick([0, 0, 1, 3]),
    kind_mcq: pick([0, 1]), voters: pick([0, 1 / 3, 2 / 3, 1, 1]), families: pick([0, 1, 2, 3, 3, 4]),
    flag_frac: pick([0, 0, 0, 0.5, 1]), flag_families: pick([0, 0, 1, 3]), ev_contradict: pick([0, 0, 0, 0.5]),
    source_proof: pick([0, 0, 1]), blind_agree: pick([0, 1, 2, 3, 3, 4]), blind_against: pick([0, 0, 1, 3]),
    blind_dissent: pick([0, 0, 0, 1]), blind_split: pick([0, 0, 1]),
  };
  const vp = maybe(pick([0, 1]), 0.6);
  const vc = maybe(pick([0, 1]), 0.6);
  if (vp !== undefined) f.vignette_proof = vp;
  if (vc !== undefined) f.vignette_checked = vc;
  return f;
}
const randomP = () => pick([rand(), 0.85, 0.849, 0.4, 0.399, 0.99, 0.1]);
const strictModel = { ...NOW.DEFAULT_WEIGHTS, thresholds: { verified: 0.9, flagged: 0.45 } };
{
  const N = 300000;
  let differ = 0;
  const seen = {};
  let example = null;
  for (let i = 0; i < N; i++) {
    const f = randomF();
    const p = randomP();
    const model = pick([NOW.DEFAULT_WEIGHTS, strictModel]);
    const oath = rand() < 0.3;
    const before = BEFORE.verdict(p, f, model, oath);
    seen[before] = (seen[before] || 0) + 1;
    const a = NOW.verdict(p, f, model, oath);
    const b = NOW.verdict(p, f, model, oath, { vignetteRoute: false });
    const c = NOW.verdict(p, f, model, oath, {});
    const r1 = NOW.reasonsFor(a, p, f, model, oath, null, rand() < 0.2);
    if (a !== before || b !== before || c !== before) { differ++; example = example || { p, f, before, a, b, c }; }
    else {
      const stated = rand() < 0.2;
      if (!same(NOW.reasonsFor(a, p, f, model, oath, 'A', stated), BEFORE.reasonsFor(before, p, f, model, oath, 'A', stated))) { differ++; example = example || { p, f, reasons: r1 }; }
    }
  }
  if (example) console.log('     ', JSON.stringify(example).slice(0, 400));
  ok(differ === 0, `off: verdict and reasons equal the model before the route on ${N} fuzzed shapes (${Object.entries(seen).map(([k, v]) => `${k} ${v}`).join(', ')})`);
  ok(Object.keys(seen).length === 4, 'the fuzz reaches every verdict the model gives');
}
{
  const N = 20000;
  let differ = 0;
  for (let i = 0; i < N; i++) {
    const kind = pick(NOW.KINDS);
    const votes = Array.from({ length: pick([0, 1, 2, 3, 4]) }, () => ({ model: pick(FAMS), risk: pick([1, 2, 3, 4, null]), answer: pick(['A', 'B', 'C', null]),
      evidence: pick(['supports', 'contradicts', 'none']), blind: rand() < 0.5 }));
    const args = { kind, rules: rand() < 0.2 ? [{ severity: pick(['severe', 'minor']) }] : [], votes, evidenceCount: pick([0, 1, 3, 7]),
      sourceMatch: pick([null, 0, 0.4, 1]), keyLetter: kind === 'mcq' ? pick(['A', 'B', null]) : null, sourceProof: rand() < 0.3 };
    if (!same(NOW.features(args), BEFORE.features(args)) || !same(NOW.features({ ...args, vignette: null }), BEFORE.features(args))) differ++;
  }
  ok(differ === 0, `off: features equal the model before the route on ${N} fuzzed inputs, no new field among them`);
}

// describe: a packet changes nothing while the route is off
const { item: seed, packet } = seedItem();
const WEIGHTS = NOW.DEFAULT_WEIGHTS;
const blind = key => FAMS.slice(0, 3).map(model => ({ model, risk: 1, answer: key, blind: true, evidence: 'supports', cites: [] }));
function randomSignals() {
  if (rand() < 0.1) return null;
  const n = pick([0, 1, 3, 4]);
  return {
    votes: Array.from({ length: n }, (_, i) => ({ model: FAMS[i % 4], risk: pick([1, 1, 2, 3, 4]), answer: pick(['A', 'A', 'B']), blind: rand() < 0.7,
      evidence: pick(['supports', 'none', 'contradicts']), cites: [] })),
    evidence: [],
    sourceMatch: pick([null, 0.5]),
    ...(rand() < 0.5 ? { proof: { v: 1, why: pick(['stem', 'unproven', null]), claims: 1, proven: pick([0, 1]), quotes: [] } } : {}),
  };
}
{
  const N = 4000;
  let differ = 0;
  let leaked = 0;
  const items = [seed, { ...seed, stem: seed.stem.replace('6 mm', '4 mm') }, { ...seed, options: ['Negative', 'Positive'], key: 1 },
    { id: 'q', kind: 'mcq', stem: 'Which drug reverses warfarin?', options: ['Vitamin K', 'Heparin'], key: 0, explanation: '', source: '' }];
  for (let i = 0; i < N; i++) {
    const base = pick(items);
    const signals = randomSignals();
    const claims = rand() < 0.1 ? { hard: [{ code: 'contradiction', claim: 'x' }], soft: [] } : null;
    const without = describe({ ...base }, 'h', signals, WEIGHTS, 0, undefined, claims);
    const withPacket = describe({ ...base, vignette: packet }, 'h', signals, WEIGHTS, 0, undefined, claims);
    const offOpt = describe({ ...base, vignette: packet }, 'h', signals, WEIGHTS, 0, undefined, claims, { vignetteRoute: false });
    if (!same(without, withPacket) || !same(without, offOpt)) differ++;
    if ('vignette' in withPacket || withPacket.verdict === 'checked') leaked++;
  }
  ok(differ === 0 && leaked === 0, `off: describe gives the same reply with or without a proof packet (${N} items and signals)`);
  const raw = { ...seed, id: 'x', source: '', explanation: '', vignette: packet };
  ok(same(cleanItem(raw), cleanItem({ ...raw, vignette: undefined })) && !('vignette' in cleanItem(raw)) && !('vignette' in cleanItem(raw, 1)),
    'off: the packet is dropped when an item is cleaned');
  ok(same(cleanItem(raw, { packets: true }).vignette, packet), 'on: the packet is kept');
}

// MARK: 3. on: nothing loosened

{
  const N = 300000;
  let bad = 0;
  let checked = 0;
  let viaVignette = 0;
  let example = null;
  for (let i = 0; i < N; i++) {
    const f = randomF();
    const p = randomP();
    const model = pick([WEIGHTS, strictModel]);
    const oath = rand() < 0.3;
    const before = BEFORE.verdict(p, f, model, oath);
    const on = NOW.verdict(p, f, model, oath, { vignetteRoute: true });
    // what Verified would be with a source proof in its place
    const backedBefore = BEFORE.verdict(p, { ...f, source_proof: 1 }, model, oath);
    const fail = (on === 'verified' && !(before === 'verified' || (f.vignette_proof === 1 && backedBefore === 'verified')))
      || (on === 'checked' && !(f.vignette_checked === 1 && backedBefore === 'verified' && before !== 'verified'))
      || (before === 'flagged' && on !== 'flagged')
      || (before === 'unchecked' && on !== 'unchecked')
      || (before === 'verified' && on !== 'verified')
      || (on === 'check' && before !== 'check')
      || (f.vignette_proof === 1 && backedBefore === 'verified' && on !== 'verified');
    if (fail) { bad++; example = example || { p, f, before, on, backedBefore }; }
    if (on === 'checked') checked++;
    if (on === 'verified' && before !== 'verified') viaVignette++;
  }
  if (example) console.log('     ', JSON.stringify(example).slice(0, 400));
  ok(bad === 0, `on: Verified only where it was, or where a signed-off vignette proof stands for the source proof; Checked only one sign-off short; flagged stays flagged (${N} shapes: ${checked} checked, ${viaVignette} verified by a vignette proof)`);
}
ok(NOW.GRADE_ORDER.join() === 'verified,checked,check,flagged,unchecked', 'Checked sits between Verified and Check this');
ok(NOW.TIER_MEANINGS.verified.startsWith('Verified means every fact was matched word for word to an open source')
  && NOW.TIER_MEANINGS.checked.startsWith('Checked means it passed our checks and agreement tests'), 'what Verified and Checked mean, in plain words');

// MARK: 4. on, end to end

{
  const signals = { votes: blind('A'), evidence: [], sourceMatch: null, proof: { v: 1, why: 'stem', claims: 0, proven: 0, quotes: [] } };
  const on = describe({ ...seed, id: 's', vignette: packet }, 'h', signals, WEIGHTS, 0, undefined, null, { vignetteRoute: true });
  ok(on.verdict === 'checked' && on.vignette?.ok === true && on.vignette.tier === 'checked', 'on: the seed item, passed blind by three families, is Checked');
  ok(on.reasons.includes(NOW.TIER_MEANINGS.checked) && !on.reasons.some(r => /clinical vignette, not a statement/.test(r)), 'its reasons say what Checked means, and no longer that no proof is possible');
  ok(on.provenance.chains.some(c => c.retrieval === 'verbatim-span') && on.provenance.chains.some(c => c.retrieval === 'deduction')
    && on.provenance.chains.some(c => c.retrieval === 'quoted' && /cdc\.gov/.test(c.source || '')), 'its provenance carries the findings, the CDC quotes and the deduction');
  ok(on.provenance.tier === null && on.features.vignette_checked === 1 && on.features.vignette_proof === 0, 'no provenance tier and no proven flag below Verified');
  const off = describe({ ...seed, id: 's', vignette: packet }, 'h', signals, WEIGHTS, 0, undefined, null);
  ok(off.verdict === 'check', 'the same item with the route off: Check this');
  const two = describe({ ...seed, id: 's', vignette: packet }, 'h', { ...signals, votes: blind('A').slice(0, 2) }, WEIGHTS, 0, undefined, null, { vignetteRoute: true });
  ok(two.verdict === 'check', 'on: two blind families are still not enough');
  const wrong = describe({ ...seed, id: 's', vignette: packet }, 'h', { ...signals, votes: blind('B') }, WEIGHTS, 0, undefined, null, { vignetteRoute: true });
  ok(wrong.verdict !== 'checked' && wrong.verdict !== 'verified', 'on: blind solves away from the key still hold it');
  const stale = describe({ ...seed, id: 's', stem: seed.stem.replace('34', '35'), vignette: packet }, 'h', signals, WEIGHTS, 0, undefined, null, { vignetteRoute: true });
  ok(stale.verdict === 'check' && stale.vignette.why === 'stale' && stale.reasons.includes(VIGNETTE_REASONS.stale), 'on: a stale proof is refused and says why');
  const held = describe({ ...seed, id: 's', vignette: packet }, 'h', signals, WEIGHTS, 0, undefined, { hard: [{ code: 'contradiction', claim: 'x' }], soft: [] }, { vignetteRoute: true });
  ok(held.verdict === 'check', 'on: an item that contradicts its lecture drops from Checked to Check this');
  ok(typeof HOLD_REASONS.naskh === 'string', 'a rule replaced by a newer one is a hold (naskh)');
}

if (failures) { console.error(`${failures} failed`); process.exit(1); }
console.log('all passed');
