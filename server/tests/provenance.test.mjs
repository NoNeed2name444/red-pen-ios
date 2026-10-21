// Provenance (provenance.js): the Islamic (§17) and DNA (§16a) briefs as
// working checks - each claim's chain (isnad), the source registry (rijal),
// the common link, shadh and tafarrud, the conflict-of-interest rule and
// dabt - and that, wired into the verdict (accuracy.js describe), they only
// ever hold an item back: never a Verified that was not Verified without them.
//
// Run: node server/tests/provenance.test.mjs

import {
  registryEntry, registryOf, originGroups, typeOfPub, trialIds, dabt, quantitiesOf, hazardsOf, populationsOf,
  selfInterested, favours, chainsFor, gapOf, provenance, GRADES, HOLD_REASONS,
} from '../provenance.js';
import { describe } from '../accuracy.js';
import { DEFAULT_WEIGHTS, features, predict, verdict } from '../accuracy-model.js';
import { PROOF_VERSION } from '../proof.js';
import { pmcMeta } from '../evidence.js';

let failures = 0;
const ok = (cond, what) => { console.log((cond ? 'ok   ' : 'FAIL ') + what); if (!cond) failures++; };

// MARK: rijal, the registry
{
  const label = registryEntry({ source: 'openFDA label', title: 'warfarin (FDA label, effective 20250101)', url: 'https://dailymed/w',
    meta: { manufacturer: 'Acme Pharmaceuticals Inc', date: '20250101', edition: '7', setId: 'abc' } });
  ok(label.type === 'label' && label.grade === GRADES.label && label.publisher === 'Acme Pharmaceuticals Inc' && label.edition === '7'
     && label.sponsors.includes('Acme Pharmaceuticals Inc') && label.origin.includes('setid:abc'),
     'a label: its maker, date, edition, and its maker as its sponsor');
  const bare = registryEntry({ source: 'openFDA label', title: 'x', url: 'u' });
  ok(bare.sponsors.length === 1 && bare.retracted === null, 'a label with no facts is still its maker\'s, and its retraction is unknown, not "no"');
  const mlp = registryEntry({ source: 'MedlinePlus', title: 'Asthma', url: 'https://medlineplus.gov/asthma.html' });
  ok(mlp.type === 'reviewed-summary' && mlp.grade === 4 && !mlp.sponsors.length, 'MedlinePlus: a reviewed summary, one grade under a label');
  ok(typeOfPub(['Review', 'Practice Guideline']) === 'guideline' && typeOfPub(['Meta-Analysis', 'Review']) === 'systematic-review'
     && typeOfPub(['Randomized Controlled Trial']) === 'rct' && typeOfPub(['Case Reports']) === 'case-report'
     && typeOfPub(['Review']) === 'review' && typeOfPub([]) === 'unknown',
     'a Europe PMC record\'s type, the strongest of its publication types');
  const meta = pmcMeta({ pubTypeList: { pubType: ['Review', 'Retracted Publication'] }, doi: '10.1/X', pmid: '123', pubYear: 2022,
    grantsList: { grant: [{ agency: 'Novartis Pharma AG' }, { agency: 'NIH' }] },
    commentCorrectionList: { commentCorrection: [{ type: 'Erratum in' }] },
    abstractText: 'In NCT01234567 and again in nct01234567 we found...', title: 'A <i>review</i>' });
  const pmc = registryEntry({ source: 'Europe PMC', title: 'A review (J, 2022)', url: 'https://doi.org/10.1/X', meta });
  ok(meta.trials.join() === 'NCT01234567' && meta.funders.length === 2 && meta.corrections[0] === 'Erratum in' && meta.pmid === '123',
     'Europe PMC\'s registry facts: trials named, funders, corrections, identifiers');
  ok(pmc.retracted === true && pmc.sponsors.includes('Novartis Pharma AG') && !pmc.sponsors.includes('NIH')
     && pmc.origin.includes('doi:10.1/x') && pmc.origin.includes('trial:NCT01234567'),
     'a retracted record is known as retracted; a company funder is a sponsor, a public one is not');
  ok(registryEntry({ source: 'Europe PMC', title: 't', url: 'u', meta: pmcMeta({ pubTypeList: { pubType: 'Review' } }) }).retracted === false
     && registryEntry({ source: 'Europe PMC', title: 't', url: 'u', meta: { pubTypes: ['Review'], corrections: ['Expression of concern in'] } }).retracted === true,
     'one publication type given alone is read; an expression of concern counts as a retraction');
  ok(registryOf([{ source: 'MedlinePlus', url: 'a' }, { source: 'MedlinePlus', url: 'a' }, null]).length === 1, 'one entry per address');
  ok(trialIds('NCT00000001; ISRCTN12345678; 2004-000123-45').length === 3, 'ClinicalTrials.gov, ISRCTN and EudraCT ids');
}

// MARK: the common link
{
  const a = registryEntry({ source: 'Europe PMC', url: 'u1', title: 'a', meta: { doi: '10.1/a', trials: ['NCT1'] } });
  const b = registryEntry({ source: 'Europe PMC', url: 'u2', title: 'b', meta: { trials: ['NCT1'], pmid: '9' } });
  const c = registryEntry({ source: 'Europe PMC', url: 'u3', title: 'c', meta: { pmid: '9' } });
  const d = registryEntry({ source: 'Europe PMC', url: 'u4', title: 'd', meta: { doi: '10.1/d' } });
  const groups = originGroups([a, b, c, d]);
  ok(groups.length === 2 && groups.some(g => g.length === 3), 'reports sharing a trial or a record are one witness, through a chain of them (a~b~c), apart from an unrelated one');
  ok(originGroups([]).length === 0, 'no sources, no witnesses');
}

// MARK: dabt
{
  const s = 'The recommended dose is 500 mg orally twice daily in adults.';
  ok(dabt(s, s).length === 0, 'a claim that is its passage copies it faithfully');
  ok(dabt('The recommended dose is 0.5 g orally twice daily in adults.', s).length === 0, '0.5 g is 500 mg: a unit said another way is the same number');
  const what = (c, p) => dabt(c, p).map(d => d.what);
  ok(what('The recommended dose is 50 mg orally twice daily in adults.', s).includes('number'), 'another number is caught');
  ok(what('The recommended dose is 500 mcg orally twice daily in adults.', s).includes('number'), 'another unit is caught (mcg for mg)');
  ok(what('The recommended dose is 500 mg orally three times daily in adults.', s).includes('frequency'), 'another frequency is caught');
  ok(what('The recommended dose is 500 mg orally twice daily in children.', s).includes('population'), 'another population is caught');
  ok(what('The recommended dose is 500 mg orally twice daily.', s).includes('population'), 'a population left out (a narrower passage for a general claim) is caught');
  ok(what('Warfarin is not contraindicated in pregnancy.', 'Warfarin is contraindicated in pregnancy.').includes('negation'), 'a "not" put in is caught');
  ok(what('Give 1.0 mg of it.', 'Give 1 mg of it.').includes('hazard') && hazardsOf('Give .5 mg').includes('naked decimal')
     && hazardsOf('Give 10 U').includes('"U" for units') && hazardsOf('Take it QD').length === 1 && !hazardsOf('Give 0.5 mg').length,
     'the Joint Commission\'s "Do Not Use" writing is caught (trailing zero, naked decimal, U, QD); 0.5 mg is fine');
  ok(quantitiesOf('two tablets of 1,000 mg every 12 hours').join() === '1000 mg,12 h' && quantitiesOf('one of the causes').length === 0,
     'quantities: thousands and hours read, a number word with no unit is a word');
  ok(populationsOf('Use in older adults and in kidney disease').join() === 'adults,older adults,renal' && !populationsOf('women').includes('men'), 'populations by their words (older adults are adults too; women are not men)');
  // mutations of real label sentences: every change of meaning is caught
  const corpus = [
    'The usual adult dose is 5 mg once daily.',
    'Do not exceed 4 g in 24 hours in adults.',
    'Children: 15 mg/kg every 6 hours, not more than 5 doses a day.',
    'Metformin is contraindicated in severe renal impairment.',
    'The maximum recommended dose is 2550 mg per day.',
    'Administer 0.3 mg intramuscularly in adults.',
    'Insulin glargine is given once daily at the same time each day.',
    'Reduce the dose by 50% in hepatic impairment.',
    'Heparin should not be given to patients with thrombocytopenia.',
    'Take 81 mg daily for prevention in adults over 50 years.',
  ];
  const changes = [
    t => t.replace(/\d+(?:\.\d+)?/, n => String(Number(n) * 10)),
    t => t.replace(/\d+(?:\.\d+)?/, n => String(Number(n) + 1)),
    t => t.replace(/\bmg\b/, 'mcg'),
    t => t.replace(/\bg\b/, 'mg'),
    t => t.replace(/\bonce daily\b/, 'twice daily').replace(/\bdaily\b(?! at)/, 'weekly'),
    t => t.replace(/\badults\b/, 'children').replace(/\bChildren\b/, 'Adults'),
    t => (/\bnot\b/.test(t) ? t.replace(/\bnot /, '') : t.replace(/\b(is|should|be) /, '$1 not ')),
    t => t.replace(/\b(renal|hepatic)\b/, m => (m === 'renal' ? 'hepatic' : 'renal')),
    t => t.replace(/\bhours\b/, 'days'),
  ];
  let tried = 0, missed = [];
  for (const s of corpus) for (const change of changes) {
    const c = change(s);
    if (c === s) continue;
    tried++;
    if (!dabt(c, s).length) missed.push(c);
  }
  ok(tried >= 35 && !missed.length, `every change of a number, unit, frequency, population or negation is caught (${tried} changes${missed.length ? '; missed: ' + missed.join(' | ') : ''})`);
}

// MARK: the conflict-of-interest rule
{
  const lab = registryEntry({ source: 'openFDA label', title: 'apixaban label', url: 'L', meta: { manufacturer: 'Acme Inc' } });
  ok(favours('Apixaban is the drug of choice for X.') && !favours('Apixaban is a factor Xa inhibitor.'), 'a claim in a product\'s favour, told apart');
  ok(selfInterested('Apixaban is preferred over warfarin.', lab) && !selfInterested('Apixaban is a factor Xa inhibitor.', lab),
     'a label speaking in its own product\'s favour is self-interested; stating what it is, is not');
  const funded = registryEntry({ source: 'Europe PMC', title: 't', url: 'P', meta: { pubTypes: ['Review'], funders: ['Pfizer Inc'] } });
  const free = registryEntry({ source: 'Europe PMC', title: 't', url: 'Q', meta: { pubTypes: ['Review'], funders: ['NIH'] } });
  ok(selfInterested('Atorvastatin reduces mortality in adults.', funded) && !selfInterested('Atorvastatin reduces mortality in adults.', free),
     'a company-funded study\'s claim in a drug\'s favour is self-interested; a publicly funded one is not');
}

// MARK: the five conditions, on an item's signals
const G = 'gemini-x', O = 'gpt-oss-x', N = 'nemotron-x', A = 'claude-x';
const blind = key => [G, O, N].map(m => ({ model: m, risk: 1, answer: key, evidence: 'none', blind: true, cites: [] }));
const passing = (cites = []) => [G, O, N].map(m => ({ model: m, risk: 1, evidence: cites.length ? 'supports' : 'none', cites }));
const quote = (claim, url, source = 'MedlinePlus', section = 'summary', quoteText = claim) => ({ claim, quote: quoteText, source, title: url, url, section });
const proofOf = (...quotes) => ({ v: PROOF_VERSION, claims: quotes.length, proven: quotes.length, quotes });
const card = text => ({ id: 'c', kind: 'card', text, source: '' });
{
  const claim = 'Asthma attacks can be triggered by smoke.';
  const one = provenance(card(claim), { votes: passing(), evidence: [], proof: proofOf(quote(claim, 'https://medlineplus.gov/asthma.html')) });
  ok(one.chains[0].retrieval === 'quoted' && one.chains[0].passage === claim && one.chains[0].source.type === 'reviewed-summary'
     && one.chains[0].checkers.length === 3 && one.chains[0].gap === null,
     'isnad: claim -> passage -> source -> quoted -> three checkers, nothing missing');
  ok(Object.values(one.gates).every(Boolean) && one.tier === 'single' && one.witnesses === 1 && !one.holds.length
     && one.flags.some(f => f.code === 'tafarrud' && !f.hold),
     'one reviewed source: all five conditions hold; tafarrud is flagged, and the tier says single source');
  const oath = provenance(card(claim), { votes: passing(), evidence: [], proof: proofOf(quote(claim, 'https://medlineplus.gov/asthma.html')) }, { oath: true });
  ok(oath.holds.some(h => h.code === 'tafarrud') && !oath.gates.hiddenDefect, 'for a dose, diagnosis or treatment, one reviewed summary alone is not enough (§17 §2 L)');
  const labelled = provenance(card(claim), { votes: passing(), evidence: [], proof: proofOf(quote(claim, 'L', 'openFDA label', 'dosage_and_administration')) }, { oath: true });
  ok(!labelled.holds.length && labelled.tier === 'single', 'and a label alone is: the top grade');
  const two = provenance(card(claim), { votes: passing(['S1']), evidence: [{ id: 'S1', source: 'Europe PMC', title: 'g', url: 'G1' }],
    sources: [registryEntry({ id: 'S1', source: 'Europe PMC', title: 'g', url: 'G1', meta: { pubTypes: ['Practice Guideline'] } })],
    proof: proofOf(quote(claim, 'https://medlineplus.gov/asthma.html')) });
  ok(two.tier === 'strong' && two.witnesses === 2 && two.chains.some(c => c.retrieval === 'summary'),
     'a guideline a checker cited beside the proof: two independent witnesses, Verified strong');
  const same = provenance(card(claim), { votes: passing(['S1']), evidence: [],
    sources: [registryEntry({ id: 'S1', source: 'Europe PMC', title: 'g', url: 'https://medlineplus.gov/asthma.html', meta: { pubTypes: ['Review'] } })],
    proof: proofOf(quote(claim, 'https://medlineplus.gov/asthma.html')) });
  ok(same.witnesses === 1, 'the same source by another route is one witness');
  const unknown = provenance(card(claim), { votes: passing(), evidence: [], proof: proofOf(quote(claim, 'X', 'somewhere')) });
  ok(unknown.holds.some(h => h.code === 'tafarrud'), 'majhul: one source nobody can identify holds it');
  const retracted = provenance(card(claim), { votes: passing(['S1']), evidence: [],
    sources: [registryEntry({ id: 'S1', source: 'Europe PMC', title: 'r', url: 'R', meta: { pubTypes: ['Review', 'Retracted Publication'] } })],
    proof: proofOf(quote(claim, 'https://medlineplus.gov/asthma.html')) });
  ok(retracted.holds.some(h => h.code === 'retracted') && !retracted.gates.integrity, 'a retracted source a checker leaned on holds it');
  const contra = provenance(card(claim), { votes: [...passing().slice(0, 2), { model: A, risk: 2, evidence: 'contradicts', cites: ['S1'] }], evidence: [],
    sources: [registryEntry({ id: 'S1', source: 'Europe PMC', title: 'sr', url: 'SR', meta: { pubTypes: ['Systematic Review'] } })],
    proof: proofOf(quote(claim, 'https://medlineplus.gov/asthma.html')) });
  ok(contra.holds.some(h => h.code === 'shadh') && !contra.gates.conformity, 'shadh: a systematic review read against a summary\'s support holds it');
  const weak = provenance(card(claim), { votes: [...passing().slice(0, 2), { model: A, risk: 2, evidence: 'contradicts', cites: ['S1'] }], evidence: [],
    sources: [registryEntry({ id: 'S1', source: 'Europe PMC', title: 'cr', url: 'CR', meta: { pubTypes: ['Case Reports'] } })],
    proof: proofOf(quote(claim, 'L', 'openFDA label')) });
  ok(!weak.holds.some(h => h.code === 'shadh') && weak.flags.some(f => f.code === 'munkar'), 'munkar: a case report against a label is reported, not adopted');
  const pref = 'Apixaban is preferred over warfarin in atrial fibrillation.';
  const coi = provenance(card(pref), { votes: passing(), evidence: [], proof: proofOf(quote(pref, 'L', 'openFDA label', 'indications_and_usage')) });
  ok(coi.holds.some(h => h.code === 'conflict') && !coi.gates.integrity, 'the maker\'s own label alone, in its product\'s favour, holds it');
  const coi2 = provenance(card(pref), { votes: passing(), evidence: [],
    proof: proofOf(quote(pref, 'L', 'openFDA label'), quote(pref, 'https://medlineplus.gov/afib.html')) });
  ok(!coi2.holds.some(h => h.code === 'conflict'), 'with an independent, unsponsored source beside it, it may stand');
  const slip = provenance(card('Give 1.0 mg of adrenaline IM.'), { votes: passing(), evidence: [],
    proof: proofOf(quote('Give 1.0 mg of adrenaline IM.', 'L', 'openFDA label', 'dosage_and_administration', 'Give 1 mg of adrenaline IM.')) });
  ok(slip.holds.some(h => h.code === 'dabt' && /hazard/.test(h.source)) && !slip.gates.accuracy, 'dabt: a trailing zero the proof\'s reader let through is caught');
  ok(gapOf('no-source') === 'muallaq' && gapOf('unproven') === 'munqati' && gapOf('stem') === 'unprovable' && gapOf('budget') === 'unread' && gapOf(undefined) === null,
     'a missing link is named by where it is missing');
  const vignette = chainsFor({ kind: 'mcq', key: 0 }, { votes: blind('A'), proof: { v: PROOF_VERSION, claims: 0, proven: 0, quotes: [], why: 'stem' } }, []);
  ok(vignette.length === 1 && vignette[0].gap === 'unprovable' && vignette[0].checkers.length === 3, 'a vignette: its checkers, and the gap where its source should be');
  ok(provenance(card(claim), null) === null, 'an item nobody checked has no provenance');
}

// MARK: wired into the verdict, and never making anything better
{
  const claim = 'Asthma attacks can be triggered by smoke.';
  const base = { votes: passing(), sourceMatch: 0, evidence: [], proof: proofOf(quote(claim, 'https://medlineplus.gov/asthma.html')) };
  const good = describe(card(claim), 'h', base, DEFAULT_WEIGHTS);
  ok(good.verdict === 'verified' && good.provenance.tier === 'single' && good.provenance.chains[0].passage === claim
     && good.provenance.sources[0].type === 'reviewed-summary', 'a proven card passed by three families: Verified, single source, its chain sent with it');
  const slip = 'Give 1.0 mg of adrenaline IM.';
  const bad = describe(card(slip), 'h', { ...base, proof: proofOf(quote(slip, 'L', 'openFDA label', 'dosage_and_administration', 'Give 1 mg of adrenaline IM.')) }, DEFAULT_WEIGHTS);
  ok(bad.verdict === 'check' && bad.claims.hard.some(h => h.code === 'dabt') && bad.reasons.includes(HOLD_REASONS.dabt) && bad.provenance.tier === null,
     'a hold keeps it from Verified, goes back with the lecture\'s findings (so the app holds it too), and is said in words');
  const lecture = describe(card(slip), 'h', { ...base, proof: proofOf(quote(slip, 'L', 'openFDA label', 'dosage_and_administration', 'Give 1 mg of adrenaline IM.')) },
    DEFAULT_WEIGHTS, 0, undefined, { hard: [{ code: 'dose', claim: 'a', source: 'b' }], soft: [], complete: true });
  ok(lecture.claims.hard.map(h => h.code).join() === 'dose,dabt' && lecture.reasons.includes('It contradicts its own lecture.'),
     'the lecture\'s findings and provenance\'s holds, side by side');
  // fuzz: many signal shapes; Verified with provenance only where Verified without it
  let seed = 7;
  const rnd = n => { seed = (seed * 1103515245 + 12345) % 2147483648; return seed % n; };
  const pick = list => list[rnd(list.length)];
  let worse = 0, held = 0, verifiedN = 0, n = 0;
  const texts = [claim, slip, 'Apixaban is preferred over warfarin.', 'Give 500 mg twice daily in adults.', 'Smoke triggers asthma in children.'];
  const urls = [['https://medlineplus.gov/a.html', 'MedlinePlus'], ['L', 'openFDA label'], ['X', 'somewhere']];
  const metas = [{ pubTypes: ['Review'] }, { pubTypes: ['Practice Guideline'] }, { pubTypes: ['Case Reports'] }, { pubTypes: ['Review', 'Retracted Publication'] }, { pubTypes: ['Review'], funders: ['Acme Pharma Ltd'] }];
  for (let i = 0; i < 3000; i++) {
    const text = pick(texts);
    const [url, source] = pick(urls);
    const passage = rnd(4) ? text : text.replace(/\d+/, d => String(+d + 1));
    const votes = [G, O, N, A].slice(0, 2 + rnd(3)).map(m => ({ model: m, risk: 1 + rnd(2), evidence: pick(['supports', 'none', 'contradicts', 'none']), cites: rnd(2) ? ['S1'] : [] }));
    const signals = { votes, sourceMatch: 0, evidence: [{ id: 'S1', source: 'Europe PMC', title: 't', url: 'E' }],
      sources: rnd(2) ? [registryEntry({ id: 'S1', source: 'Europe PMC', title: 't', url: 'E', meta: pick(metas) })] : [],
      proof: rnd(5) ? proofOf(quote(text, url, source, pick(['summary', 'dosage_and_administration', 'indications_and_usage']), passage)) : { v: PROOF_VERSION, claims: 1, proven: 0, quotes: [], why: 'unproven' } };
    const item = card(text);
    const d = describe(item, 'h', signals, DEFAULT_WEIGHTS);
    // the verdict as it was before provenance: the model's grade, with the lecture's findings (none here)
    const f = d.features;
    const before = verdict(predict(f, DEFAULT_WEIGHTS), f, DEFAULT_WEIGHTS);
    n++;
    if (d.verdict === 'verified') verifiedN++;
    if (d.verdict === 'verified' && before !== 'verified') worse++;
    if (before === 'verified' && d.verdict !== 'verified') held++;
  }
  ok(worse === 0 && held > 0 && verifiedN > 0, `over ${n} fuzzed checks, provenance never made one Verified that was not (${held} held back, ${verifiedN} still Verified)`);
}

console.log(failures ? `\n${failures} FAILED` : '\nall passed');
process.exit(failures ? 1 : 0);
