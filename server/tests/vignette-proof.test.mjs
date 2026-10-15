// The vignette route (vignette-proof.js, lexicon.js, criteria/): a clinical
// vignette's answer is proven only when an untrusted proof packet survives a
// deterministic checker, every rule it uses passed the registry review, and
// every source it rests on is licensed for commercial use.
//
// 1. Hashing: SHA-256 vectors (sign-off and staleness are bound to it).
// 2. Sources: a licence that allows commercial use, recorded; never
//    StatPearls; a rule only on a current guideline, review or label.
// 3. Numbers: a criterion's number read from its own words.
// 4. The registry: current, the seeded rules admitted, the rest pending with
//    their reason; each way a rule fails review (the owner's a, b and c).
// 5. The checker: a seed item accepted at Checked; Proven only when the
//    owner signed off every rule and quoted lexicon entry it used, bound to
//    the content; every refusal typed.
// 6. Ruling a distractor out by a denial rule (a fixture registry).
// 7. Mutations: an edited stem never keeps a proof, and a re-proposed proof
//    of a stem whose truth changed is never accepted.
//
// Run: node server/tests/vignette-proof.test.mjs

import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import * as V from '../vignette-proof.js';
import REGISTRY from '../criteria/registry.js';
import { reviewRule, reviewLexicon, quotedIn } from '../criteria/review.js';
import { SLOTS, readSpan, mentions, quotedEntries } from '../lexicon.js';
import { build } from '../../tools/criteria/build-registry.mjs';
import { propose, seedItem } from '../../tools/criteria/stub-proposer.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const crit = join(here, '..', 'criteria');
let failures = 0;
const ok = (cond, what) => { console.log((cond ? 'ok   ' : 'FAIL ') + what); if (!cond) failures++; };
const clone = x => JSON.parse(JSON.stringify(x));
const why = (r, want, what) => { const s = r && r.ok === false && r.why === want; if (!s) console.log(`     got ${JSON.stringify(r).slice(0, 240)}`); ok(s, what); };

// MARK: 1. hashing

ok(V.sha256('') === 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855', 'sha256 of the empty string');
ok(V.sha256('abc') === 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad', 'sha256 of "abc"');
{
  let bad = 0;
  for (let n = 0; n < 300; n++) {
    const s = Array.from({ length: n }, (_, i) => String.fromCodePoint(32 + ((i * 7919 + n) % 300))).join('');
    if (V.sha256(s) !== createHash('sha256').update(s, 'utf8').digest('hex')) bad++;
  }
  ok(bad === 0, 'sha256 matches node:crypto on 300 strings of every length to 299, multi-byte included');
}
ok(V.canonical({ b: 1, a: [2, { d: 3, c: 4 }] }) === '{"a":[2,{"c":4,"d":3}],"b":1}', 'canonical JSON: keys in order at every depth');

// MARK: 2. sources

const sources = JSON.parse(readFileSync(join(crit, 'sources.json'), 'utf8')).sources;
const cdc = sources.find(s => s.id === 'cdc-tst-2025');
ok(V.licenceAllows(cdc) && V.ruleSourceAllows(cdc), 'the CDC guideline: public domain, commercial use allowed, a current guideline');
ok(V.licenceAllows(sources[1]) && !V.ruleSourceAllows(sources[1]), 'the CDC Core Curriculum: may be quoted (examples), but a textbook backs no rule');
ok(sources.every(s => V.licenceAllows(s) && s.licence.url && s.licence.grant && Array.isArray(s.licence.conditions)), 'every registered source records its licence, its grant and its terms');
const lic = patch => ({ ...cdc, licence: { ...cdc.licence, ...patch } });
const refused = [
  ['no licence', { ...cdc, licence: undefined }],
  ['commercial use not recorded', lic({ commercialUse: undefined })],
  ['commercial use false', lic({ commercialUse: false })],
  ['CC BY-NC 4.0', lic({ id: 'cc-by-nc-4.0' })],
  ['CC BY-NC-ND 4.0', lic({ id: 'cc-by-nc-nd-4.0' })],
  ['CC BY-ND', lic({ id: 'cc-by-nd-4.0' })],
  ['an unknown licence', lic({ id: 'all-rights-reserved' })],
  ['no grant quoted', lic({ grant: ' ' })],
  ['no licence url', lic({ url: 'cdc.gov' })],
  ['a commercial grant that does not name commercial use', lic({ id: 'commercial-grant', grant: 'You may use this freely.' })],
  ['StatPearls by title', { ...cdc, title: 'StatPearls: Tuberculin Skin Test' }],
  ['StatPearls by publisher', { ...cdc, publisher: 'Stat Pearls Publishing' }],
  ['StatPearls by its Bookshelf id', { ...cdc, url: 'https://www.ncbi.nlm.nih.gov/books/NBK430685/' }],
];
for (const [what, src] of refused) ok(!V.licenceAllows(src), `licence refused: ${what}`);
ok(V.licenceAllows(lic({ id: 'commercial-grant', grant: 'Permission is granted for commercial use with attribution.' })), 'a society grant that names commercial use is allowed');
for (const [what, src] of [['a textbook', { ...cdc, type: 'textbook' }], ['a review article', { ...cdc, type: 'review' }], ['superseded', { ...cdc, status: 'superseded' }], ['retracted', { ...cdc, retracted: true }]]) {
  ok(!V.ruleSourceAllows(src), `no rule rests on ${what}`);
}

// MARK: 3. numbers in a criterion's own words

const says = [
  ['5 or more millimeters', { op: '>=', value: 5, unit: 'mm' }],
  ['10 mm or more', { op: '>=', value: 10, unit: 'mm' }],
  ['15 millimeters or greater', { op: '>=', value: 15, unit: 'mm' }],
  ['between 48 and 72 hours', { op: 'between', value: [48, 72], unit: 'hours' }],
  ['less than 5 mm', { op: '<', value: 5, unit: 'mm' }],
  ['5 or more inches', null],
  ['about 5 mm', null],
  ['5', null],
];
ok(says.every(([t, want]) => V.canonical(V.readSays(t)) === V.canonical(want)), `readSays reads ${says.length} criterion wordings, refusing an unknown unit or a hedge`);
const r5 = REGISTRY.rules.find(r => r.id === 'cdc-tst-5mm');
ok(V.evaluateRule(r5, [{ slot: 'tst', value: true }, { slot: 'read_hours', value: 48 }, { slot: 'induration_mm', value: 5 }, { slot: 'induration_mm', value: 3 }, { slot: 'tst_group', value: 'hiv' }]).fires === false,
  'two readings of one number never meet its criterion');
ok(V.evaluateRule({ formal: { criteria: [{ id: 'x', slot: 'a', op: 'judgment' }] } }, [{ slot: 'a', value: true }]).judgment, 'a criterion that needs judgment never fires');

// MARK: 4. the registry

{
  const built = build();
  ok(built.text === readFileSync(join(crit, 'registry.js'), 'utf8'), 'server/criteria/registry.js is current (node tools/criteria/build-registry.mjs)');
}
ok(V.canonical(REGISTRY.rules.map(r => r.id).sort()) === V.canonical(['cdc-tst-5mm', 'cdc-tst-contraindication', 'cdc-tst-two-step']), 'admitted: the 5 mm cut-off, two-step testing, the contraindication');
const pend = Object.fromEntries(REGISTRY.pending.map(p => [p.id, p.why]));
ok(pend['cdc-tst-10mm'] === 'example' && pend['cdc-tst-15mm'] === 'example', 'pending: the 10 and 15 mm cut-offs (no worked example in the source)');
ok(pend['cdc-tb-culture-confirms'] === 'grade', 'pending: culture confirms TB disease (its source is a textbook)');
ok(REGISTRY.rules.every(r => r.hash === V.ruleHash(r) && r.signedOffAt === null && r.signedOffHash === null), 'every admitted rule stamped with its hash, none signed off yet');
ok(REGISTRY.rules.every(r => V.ruleSourceAllows(REGISTRY.sources[r.source])), 'every admitted rule rests on a licensed, current guideline');
ok(REGISTRY.lexicon.map(e => e.id).sort().join() === 'lex-tst-abbrev,lex-tst-mantoux,lex-tst-tuberculin', 'admitted lexicon: tuberculin skin test, Mantoux, TST (quoted by the CDC)');
ok(!JSON.stringify(REGISTRY.sources).includes('Classification of TB skin test reactions'), 'the registry carries no snapshot text');

const ctx = { sources: Object.fromEntries(sources.map(s => [s.id, s])), snapshots: Object.fromEntries(sources.map(s => [s.id, { text: readFileSync(join(crit, s.snapshot.file), 'utf8') }])) };
const raw = id => JSON.parse(readFileSync(join(crit, 'rules', `${id}.json`), 'utf8'));
const base = raw('cdc-tst-5mm');
ok(reviewRule(base, ctx).ok, 'the 5 mm rule passes review from its files');
ok(reviewRule(raw('cdc-tst-two-step'), ctx).ok && reviewRule(raw('cdc-tst-contraindication'), ctx).ok, 'two-step and the contraindication pass review');
const both = (r, f) => { f(r.formal); for (const t of r.transcriptions) f(t.formal); return r; };
const mutated = [
  ['quote', 'a criterion quote one word off', r => both(r, f => { f.criteria[0].quote = 'Classification of TB skin tests reactions'; })],
  ['quote', 'a list item from another list', r => both(r, f => { f.criteria[3].values.push('myco_lab'); f.criteria[3].items.myco_lab = 'Mycobacteriology laboratory workers'; })],
  ['quote', 'a list item that is only part of a line', r => both(r, f => { f.criteria[3].items.hiv = 'People with'; })],
  ['number', 'a cut-off typed in, not read from the words', r => both(r, f => { f.criteria[2].value = 4; })],
  ['slot', 'a cut-off in the wrong unit', r => both(r, f => { f.criteria[2].unit = 'hours'; })],
  ['slot', 'a criterion reading a slot of another kind', r => both(r, f => { f.criteria[0].slot = 'tst_group'; })],
  ['quote', 'a quote cut short of its sentence (found by the B6 bench)', r => both(r, f => { f.criteria[1].quote = f.criteria[1].quote.replace(/ by a health care worker.*$/, ''); })],
  ['quote', 'a conclusion cut short of its line', r => both(r, f => { f.conclusion.quote = 'An induration of 5 or more millimeters is considered positive'; })],
  ['shape', 'findings held together that the rule does not read', r => both(r, f => { f.together = [['tst', 'prior_tst']]; })],
  ['asks', 'a question the lexicon does not know', r => both(r, f => { f.conclusion.asks = ['of this result']; })],
  ['alias', 'an answer not what its words conclude', r => both(r, f => { f.conclusion.says = 'is considered'; })],
  ['number', 'words the quote does not hold', r => both(r, f => { f.criteria[2].says = '6 or more millimeters'; })],
  ['alias', 'an answer not in the rule\'s words', r => both(r, f => { f.conclusion.aliases = ['Latent TB infection'] ; })],
  ['alias', 'an excluded answer that is not the plain opposite', r => both(r, f => { f.exclusive = [{ aliases: ['Indeterminate'] }]; })],
  ['transcription', 'one transcription', r => { r.transcriptions = r.transcriptions.slice(0, 1); return r; }],
  ['transcription', 'two transcriptions by one transcriber', r => { r.transcriptions[1].by = r.transcriptions[0].by; return r; }],
  ['transcription', 'the second transcription disagrees', r => { r.transcriptions[1].formal.criteria[2].value = 6; return r; }],
  ['transcription', 'the second transcription disagrees on an alias only', r => { r.transcriptions[1].formal.conclusion.aliases = ['positive']; return r; }],
  ['example', 'no worked example', r => { r.examples = []; return r; }],
  ['example', 'the answer key read for the wrong question', r => { r.examples[0].number = 2; return r; }],
  ['example', 'the wrong key', r => { r.examples[0].key = 'B'; r.examples[0].option = 'B. 10 millimeters or greater'; return r; }],
  ['example', 'a case the rule gets wrong', r => { r.examples[0].cases[0].fires = false; return r; }],
  ['quote', 'an example question not in the source', r => { r.examples[0].question = '3. For the following groups, what induration size is a positive reaction?'; return r; }],
  ['grade', 'a rule on a textbook', r => { r.source = 'cdc-tb-core-curriculum-2021'; return r; }],
  ['source', 'a rule on an unregistered source', r => { r.source = 'statpearls-tst'; return r; }],
  ['shape', 'an unknown criterion operator', r => both(r, f => { f.criteria[0].op = 'roughly'; })],
];
for (const [want, what, f] of mutated) why(reviewRule(f(clone(base)), ctx), want, `review refuses ${what} (${want})`);
{
  const c = raw('cdc-tst-contraindication');
  for (const f of [c.formal, ...c.transcriptions.map(t => t.formal)]) f.criteria[1].items.anaphylactic_shock = 'shock';
  why(reviewRule(c, ctx), 'quote', 'review refuses part of an inline list item ("shock" of "anaphylactic shock") (quote)');
}
{
  const nc = clone(ctx);
  nc.sources['cdc-tst-2025'].licence.id = 'cc-by-nc-4.0';
  why(reviewRule(clone(base), nc), 'licence', 'review refuses a rule whose source turned non-commercial (licence)');
  const sp = clone(ctx);
  sp.sources['cdc-tst-2025'].title = 'StatPearls: TB skin test';
  why(reviewRule(clone(base), sp), 'licence', 'review refuses StatPearls under any title (licence)');
  const drift = clone(ctx);
  drift.snapshots['cdc-tst-2025'].text = drift.snapshots['cdc-tst-2025'].text.replace('5 or more', '5 or more ');
  why(reviewRule(clone(base), drift), 'snapshot', 'review refuses a snapshot that is not the pinned one (snapshot)');
}
const lexOk = quotedEntries().every(e => reviewLexicon(e, ctx).ok);
ok(lexOk, 'the quoted lexicon entries pass review');
why(reviewLexicon({ ...quotedEntries()[0], form: 'PPD test' }, ctx), 'backing', 'a lexicon entry whose quote does not name its form (backing)');
why(reviewLexicon({ ...quotedEntries()[0], backing: { ...quotedEntries()[0].backing, quote: 'The TB skin test (also called the PPD test) is one method.' } }, ctx), 'quote', 'a lexicon quote not in the source (quote)');
ok(!quotedIn('•', ctx.snapshots['cdc-tst-2025']) && !quotedIn('', ctx.snapshots['cdc-tst-2025']), 'an empty or unreadable quote proves nothing');

// MARK: 5. the checker

const { item, packet } = seedItem();
const good = V.checkVignette(item, packet);
ok(good.ok && good.tier === 'checked' && good.why === null, 'the seed item: accepted, tier checked (no rule signed off yet)');
ok(V.vignetteChecked(good) && !V.vignetteProven(good), 'checked is not proven');
ok(good.chains.filter(c => c.retrieval === 'verbatim-span').length === 4 && good.chains.some(c => c.synthesis === true && c.claim === 'Positive'),
  'its chains: every finding a verbatim span, the conclusion marked as a deduction');
ok(good.chains.filter(c => c.retrieval === 'quoted').every(c => c.source.licence === 'us-federal-public-domain' && quotedIn(c.passage, ctx.snapshots[c.source.id])),
  'every quote in its chains is in its licensed source word for word');
ok(V.canonical(V.checkVignette(item, packet)) === V.canonical(good), 'the same item and packet, the same answer');
ok(V.checkVignette(...Object.values(seedItem(5, 72))).ok, 'the cut-off itself (5 mm) and the window\'s end (72 hours) are positive');

// sign-off: bound to the exact content
const signed = (reg, patch) => ({ ...reg, rules: reg.rules.map(r => (r.id === 'cdc-tst-5mm' ? { ...r, ...patch(r) } : r)) });
const SIGN = r => ({ signedOffAt: '2026-10-15T09:00:00Z', signedOffBy: 'owner', signedOffHash: r.hash });
ok(V.checkVignette(item, packet, { registry: signed(REGISTRY, SIGN) }).tier === 'proven', 'the rule signed off: proven');
ok(V.checkVignette(item, packet, { registry: signed(REGISTRY, r => ({ ...SIGN(r), signedOffHash: '0'.repeat(64) })) }).tier === 'checked', 'a sign-off of other content: still checked');
ok(V.checkVignette(item, packet, { registry: signed(REGISTRY, r => ({ ...SIGN(r), signedOffAt: 'yesterday' })) }).tier === 'checked', 'a sign-off without a date: still checked');
ok(V.checkVignette(item, packet, { registry: signed(REGISTRY, r => ({ ...SIGN(r), signedOffBy: ' ' })) }).tier === 'checked', 'a sign-off without a name: still checked');
why(V.checkVignette(item, packet, { registry: signed(REGISTRY, r => ({ ...SIGN(r), summary: `${r.summary} Also 4 mm.` })) }), 'rule', 'a rule edited after its review and sign-off is refused (rule)');
ok(V.checkVignette(item, packet, { signoffs: new Map([['cdc-tst-5mm', r5.hash]]) }).tier === 'proven', 'a sign-off kept outside the registry, by hash: proven');
ok(V.checkVignette(item, packet, { signoffs: new Map([['cdc-tst-5mm', 'x']]) }).tier === 'checked', 'an outside sign-off of another hash: still checked');

// a quoted lexicon form needs its own sign-off
{
  const it = { ...item, stem: item.stem.replace('TB skin test', 'tuberculin skin test') };
  const pk = propose(it, { rule: 'cdc-tst-5mm', ver: '1', findings: [
    { slot: 'tst_group', text: 'with HIV' }, { slot: 'tst', text: 'tuberculin skin test' },
    { slot: 'read_hours', text: '48 hours after placement' }, { slot: 'induration_mm', text: '6 mm of induration' }], eliminates: [{ option: 1, by: 'exclusive' }] });
  const a = V.checkVignette(it, pk, { registry: signed(REGISTRY, SIGN) });
  ok(a.ok && a.tier === 'checked', 'a quoted form ("tuberculin skin test") unsigned keeps a signed rule at checked');
  const lexHash = REGISTRY.lexicon.find(e => e.id === 'lex-tst-tuberculin').hash;
  ok(V.checkVignette(it, pk, { registry: signed(REGISTRY, SIGN), signoffs: new Map([['lex-tst-tuberculin', lexHash]]) }).tier === 'proven', 'both signed off: proven');
  why(V.checkVignette(it, pk, { registry: { ...REGISTRY, lexicon: [] } }), 'lexicon', 'a quoted form not in the reviewed lexicon is refused (lexicon)');
}

// refusals, each typed
const variant = (edit, plan = {}) => {
  const it = { ...item, ...edit(item) };
  const findings = plan.findings || [
    { slot: 'tst_group', text: 'with HIV' }, { slot: 'tst', text: 'TB skin test' },
    { slot: 'read_hours', text: '48 hours after placement' }, { slot: 'induration_mm', text: '6 mm of induration' }];
  return [it, propose(it, { rule: 'cdc-tst-5mm', ver: '1', eliminates: [{ option: 1, by: 'exclusive' }], ...plan, findings })];
};
const stem = s => () => ({ stem: s });
const S = item.stem;
const cases = [
  ['stale', 'the stem edited after the proof', () => [{ ...item, stem: S.replace('34', '35') }, packet]],
  ['stale', 'the key moved after the proof', () => [{ ...item, key: 1 }, packet]],
  ['stale', 'the options edited after the proof', () => [{ ...item, options: ['Positive', 'Negative', 'Indeterminate'] }, packet]],
  ['packet', 'no packet', () => [item, null]],
  ['packet', 'a packet of another version', () => [item, { ...packet, v: 2 }]],
  ['packet', 'two findings with one id', () => [item, { ...packet, findings: [packet.findings[0], packet.findings[0]] }]],
  ['mcq', 'not a question with a key', () => [{ ...item, key: 5 }, packet]],
  ['span', 'a span that is not the text it claims', () => [item, { ...packet, findings: packet.findings.map((f, i) => (i ? f : { ...f, at: [f.at[0] + 1, f.at[1] + 1] })) }]],
  ['lexicon', 'a span the lexicon does not read', () => variant(stem(S.replace('with HIV', 'with an organ transplant')), { findings: [{ slot: 'tst_group', text: 'with an organ transplant' }, { slot: 'tst', text: 'TB skin test' }, { slot: 'read_hours', text: '48 hours after placement' }, { slot: 'induration_mm', text: '6 mm of induration' }] })],
  ['lexicon', 'a finding claiming another value than it reads', () => [item, { ...packet, findings: packet.findings.map(f => (f.slot === 'induration_mm' ? { ...f, value: 16 } : f)) }]],
  ['cue', 'a negated finding', () => variant(stem(S.replace('man with HIV attends clinic', 'man not with HIV attends clinic')))],
  ['cue', 'someone else\'s finding', () => variant(stem(S.replace('34-year-old man with HIV attends clinic', '34-year-old man whose partner lives with HIV attends clinic')))],
  ['cue', 'a hedged finding', () => variant(stem(S.replace('shows 6 mm', 'possibly shows 6 mm')))],
  ['cue', 'a finding still to come', () => variant(stem(S.replace('man with HIV attends clinic', 'man with HIV is awaiting results')))],
  ['cue', 'an estimated reading', () => variant(stem(S.replace('shows 6 mm', 'shows about 6 mm')))],
  ['cue', 'a reading hedged with "maybe" (found by the B1 bench)', () => variant(stem(S.replace('shows 6 mm', 'shows maybe 6 mm')))],
  ['cue', 'a person hedged with "perhaps"', () => variant(stem(S.replace('34-year-old man', '34-year-old perhaps man')))],
  ['conflict', 'a second induration left out of the proof', () => variant(stem(S.replace('attends clinic.', 'attends clinic. A repeat test shows 2 mm of induration.')))],
  ['conflict', 'an HIV mention the lexicon cannot read', () => variant(stem(S.replace('attends clinic.', 'attends clinic. An HIV test is due.')))],
  ['fires', 'under the cut-off', () => [seedItem(4).item, seedItem(4).packet]],
  ['fires', 'read outside the window', () => [seedItem(6, 96).item, seedItem(6, 96).packet]],
  ['fires', 'a finding the rule needs, missing', () => variant(stem(S), { findings: [{ slot: 'tst', text: 'TB skin test' }, { slot: 'read_hours', text: '48 hours after placement' }, { slot: 'induration_mm', text: '6 mm of induration' }], uses: undefined })],
  ['together', 'the reading and the test in different sentences', () => variant(stem('A 34-year-old man with HIV attends clinic. His TB skin test is read. At 48 hours after placement it shows 6 mm of induration. What is the most appropriate interpretation of this result?'))],
  ['span', 'a finding in the question', () => variant(stem('A 34-year-old man with HIV attends clinic. His TB skin test, read 48 hours after placement, shows 6 mm of induration. What is the most appropriate interpretation of this result with HIV?'), { findings: [{ slot: 'tst_group', text: 'with HIV', nth: 1 }, { slot: 'tst', text: 'TB skin test' }, { slot: 'read_hours', text: '48 hours after placement' }, { slot: 'induration_mm', text: '6 mm of induration' }] })],
  ['asks', 'a question the rule does not answer', () => variant(stem(S.replace('What is the most appropriate interpretation of this result?', 'What is the next best step?')))],
  ['asks', 'a question turned around (NOT)', () => variant(stem(S.replace('What is the most', 'What is NOT the most')))],
  ['asks', 'a question turned around (least)', () => variant(stem(S.replace('most appropriate', 'least appropriate')))],
  ['asks', 'a question turned around (inappropriate)', () => variant(stem(S.replace('most appropriate', 'most inappropriate')))],
  ['asks', 'a hedged question', () => variant(stem(S.replace('What is the', 'What is possibly the')))],
  ['asks', 'no question at all', () => variant(stem(S.replace('What is the most appropriate interpretation of this result?', 'Interpret this result.')))],
  ['conclusion', 'a keyed answer not in the rule\'s words', () => variant(() => ({ options: ['Latent TB infection', 'Negative'] }))],
  ['distractor', 'an option nothing rules out', () => variant(() => ({ options: ['Positive', 'Negative', 'Indeterminate'] }), { eliminates: [{ option: 1, by: 'exclusive' }, { option: 2, by: 'exclusive' }] })],
  ['distractor', 'an option left unaddressed', () => variant(() => ({}), { eliminates: [] })],
  ['options', 'two options both the conclusion', () => variant(() => ({ options: ['Positive', 'positive'] }))],
  ['explanation', 'an explanation that says more than the rule', () => variant(() => ({ explanation: 'He has latent TB infection and needs treatment.' }))],
  ['rule', 'a rule still pending review', () => variant(stem(S), { rule: 'cdc-tst-10mm' })],
  ['rule', 'a rule that does not conclude (a denial)', () => variant(stem(S), { rule: 'cdc-tst-contraindication' })],
  ['stale', 'a proof for an older version of the rule', () => variant(stem(S), { ver: '0' })],
];
for (const [want, what, make] of cases) why(V.checkVignette(...make()), want, `refused: ${what} (${want})`);
{
  const [it, pk] = variant(() => ({ explanation: 'An induration of 5 or more millimeters is considered positive in: People with HIV' }));
  why(V.checkVignette(it, pk), 'explanation', 'an explanation that joins two quotes into one sentence is refused');
  const [it2, pk2] = variant(() => ({ explanation: 'An induration of 5 or more millimeters is considered positive in: Classification of TB skin test reactions. The skin test reaction should be read between 48 and 72 hours after administration by a health care worker trained to read TB skin results.' }));
  ok(V.checkVignette(it2, pk2).why === 'explanation', 'sentences are judged one by one');
  const [it3, pk3] = variant(() => ({ explanation: 'The skin test reaction should be read between 48 and 72 hours after administration by a health care worker trained to read TB skin results.' }));
  ok(V.checkVignette(it3, pk3).ok, 'an explanation that is the rule\'s own quote is allowed');
}
{
  const tampered = clone(REGISTRY);
  tampered.rules.find(r => r.id === 'cdc-tst-5mm').formal.criteria[2].value = 4;
  why(V.checkVignette(item, packet, { registry: tampered }), 'rule', 'a registry rule edited since review is refused (rule)');
  const nc = clone(REGISTRY);
  nc.sources['cdc-tst-2025'].licence.id = 'cc-by-nc-4.0';
  why(V.checkVignette(item, packet, { registry: nc }), 'licence', 'a source turned non-commercial is refused (licence)');
  const sp = clone(REGISTRY);
  sp.sources['cdc-tst-2025'].publisher = 'StatPearls Publishing';
  why(V.checkVignette(item, packet, { registry: sp }), 'licence', 'a StatPearls source is refused at check time too (licence)');
  const tb = clone(REGISTRY);
  tb.sources['cdc-tst-2025'].type = 'textbook';
  why(V.checkVignette(item, packet, { registry: tb }), 'grade', 'a rule whose source is below a guideline is refused (grade)');
  why(V.checkVignette(item, packet, { work: 200 }), 'budget', 'a check over its budget stops, never passes (budget)');
  why(V.checkVignette(item, { ...packet, pad: 'x'.repeat(20000) }), 'packet', 'an oversized packet is refused (packet)');
}

// the lexicon reads only whole spans in its own words
ok(readSpan('induration_mm', '6 mm of induration').value === 6 && readSpan('induration_mm', ' 6 mm of induration') === null && readSpan('induration_mm', '6 cm of induration') === null,
  'a number read only from a whole span, in its unit');
ok(readSpan('tst_group', 'HIV') === null && readSpan('tst_group', 'with HIV').value === 'hiv', '"HIV" alone is never a group, "with HIV" is');
ok(mentions('tst_group', 'An HIV test is due.').length === 1, 'every bare mention of a slot is found');
ok(Object.values(SLOTS).every(s => (s.forms || []).every(f => f.backing?.kind === 'literal' || f.backing?.kind === 'quoted')), 'every lexicon form is backed');

// MARK: 6. a distractor ruled out by a denial rule (fixture registry)

{
  // FIXTURE: a made-up concluding rule, so the denial path can be exercised;
  // it is not in the registry and quotes nothing real
  const fixture = {
    id: 'fixture-which-test', kind: 'criteria', version: '1', source: 'cdc-tst-2025',
    formal: { criteria: [{ id: 'g', slot: 'tst_group', op: 'anyOf', values: ['hiv'], quote: 'People with HIV', items: { hiv: 'People with HIV' } }],
      conclusion: { quote: 'TB blood test', aliases: ['TB blood test'], asks: ['which test'] } },
  };
  fixture.hash = V.ruleHash(fixture);
  const reg = { ...REGISTRY, rules: [...REGISTRY.rules, fixture] };
  const it = { kind: 'mcq', stem: 'A woman with HIV had blistering after her previous TB skin test. Which test is most appropriate now?', options: ['TB blood test', 'TB skin test'], key: 0 };
  const pk = propose(it, { rule: 'fixture-which-test', ver: '1', findings: [
    { id: 'g', slot: 'tst_group', text: 'with HIV' }, { id: 'p', slot: 'prior_tst', text: 'previous TB skin test' }, { id: 'r', slot: 'prior_tst_reaction', text: 'blistering' }],
  uses: ['g'], eliminates: [{ option: 1, by: 'denies', rule: 'cdc-tst-contraindication', ver: '1', uses: ['p', 'r'] }] });
  const r = V.checkVignette(it, pk, { registry: reg });
  ok(r.ok && r.rules.includes('cdc-tst-contraindication') && r.eliminated === 1, 'a TB skin test ruled out by the contraindication after blistering');
  const it2 = { ...it, stem: it.stem.replace('blistering', 'redness') };
  const pk2 = propose(it2, { rule: 'fixture-which-test', ver: '1', findings: [
    { id: 'g', slot: 'tst_group', text: 'with HIV' }, { id: 'p', slot: 'prior_tst', text: 'previous TB skin test' }],
  uses: ['g'], eliminates: [{ option: 1, by: 'denies', rule: 'cdc-tst-contraindication', ver: '1', uses: ['p'] }] });
  why(V.checkVignette(it2, pk2, { registry: reg }), 'fires', 'redness is not a severe reaction: the skin test is not ruled out (fires)');
}

// MARK: 7. mutations (a few here; tools/verification-bench/vignette-proof-mutations.mjs runs many)

{
  let kept = 0;
  let n = 0;
  for (let i = 0; i < S.length; i++) {
    for (const ch of ['x', '9', ' not', '']) {
      const it = { ...item, stem: S.slice(0, i) + ch + S.slice(i + 1) };
      if (it.stem === S) continue;
      n++;
      if (V.checkVignette(it, packet).ok) kept++;
    }
  }
  ok(kept === 0, `an edited stem never keeps its proof (${n} single-character edits, ${kept} accepted)`);
}

if (failures) { console.error(`${failures} failed`); process.exit(1); }
console.log('all passed');
