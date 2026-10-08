// Source proof (proof.js, plan SP1): an item is Verified only when an
// official source - an openFDA label, a MedlinePlus summary - states each of
// its claims word for word. Models agreeing never make it so; Europe PMC is
// no proof either.
//
// 1. Reading words: a claim and a source are compared as the same words,
//    spelled one way (numbers, doses, units, frequencies, signs, Greek
//    letters, marks); what cannot be read for certain is never read.
// 2. Heft: normalizing a text is paid for by what it takes, not its length.
// 3. Statements: a label section's and a MedlinePlus summary's, each with
//    the heading words a claim needs; lead-ins, qualified and taken-back
//    sentences never prove alone; a list nested past 8 levels is unreadable.
// 4. Claims: what an item states (a fact, a card, a cloze, a question, a
//    note), and the wordings a source may state it in.
// 5. Proof: every verdict; quotes stating each claim word for word; near
//    misses (another dose, a negation, a population) unproven.
// 6. The purse: reading stops at its budget, saying so ('budget'), never
//    another verdict; a batch pays for a section once; the same answers cold
//    and warm, whatever ran before.
// 7. CPU guards: inputs that once took a second or more are read in a few ms.
// 8. CPU budget: the worst batch the server takes, cold and warm (the free
//    plan gives a request about 10 ms).
//
// Run: node server/tests/proof.test.mjs

import { execFileSync } from 'node:child_process';
import * as P from '../proof.js';

let failures = 0;
const ok = (cond, what) => { console.log((cond ? 'ok   ' : 'FAIL ') + what); if (!cond) failures++; };
const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);
/// `got` is `want`; when not, what it was is shown under the line.
const eq = (got, want) => { const s = same(got, want); if (!s) console.log(`     got ${JSON.stringify(got).slice(0, 300)}`); return s; };
/// Each row's [input, answer]: f(input) is the answer.
const table = (f, rows, what) => {
  const bad = rows.filter(([x, want]) => !same(f(x), want));
  for (const [x, want] of bad.slice(0, 6)) console.log(`     ${JSON.stringify(x).slice(0, 60)}: ${JSON.stringify(f(x))}, not ${JSON.stringify(want)}`);
  ok(!bad.length, `${what} (${rows.length - bad.length} of ${rows.length})`);
};
// the meter's stop (OVER) is a symbol, so nothing else can be taken for it
const throwsOver = f => { try { f(); return false; } catch (e) { return typeof e === 'symbol'; } };
const sameSegs = (a, b) => same(a, b) && a.work === b.work && a.cut === b.cut && a.folded === b.folded;
const statements = segs => segs.map(s => [s.usable, s.text]);

// MARK: the sources

const LABEL = { source: 'openFDA label', title: 'Metformin hydrochloride tablets', url: 'https://example.org/label/metformin', official: { drug: 'Metformin Hydrochloride', sections: {
  indications_and_usage: '1 INDICATIONS AND USAGE Metformin is indicated as an adjunct to diet and exercise to improve glycemic control in adults with type 2 diabetes mellitus.',
  dosage_and_administration: '2 DOSAGE AND ADMINISTRATION 2.1 Adult Dosage The recommended starting dose of metformin is 500 mg twice a day with meals. 2.2 Pediatric Dosage The recommended starting dose of metformin is 500 mg once a day with meals.',
  contraindications: ['4 CONTRAINDICATIONS Metformin is contraindicated in patients with: • Severe renal impairment (eGFR below 30 mL/min/1.73 m2) [see Warnings and Precautions ( 5.1 )] • Hypersensitivity to metformin'],
  adverse_reactions: '6 ADVERSE REACTIONS The most common adverse reaction of metformin is diarrhea.',
  mechanism_of_action: '12.1 Mechanism of Action Metformin decreases hepatic glucose production. Metformin decreases intestinal absorption of glucose. However, metformin does not cause hypoglycemia in most patients.',
} } };
// another maker's label, which says otherwise
const LABEL2 = { source: 'openFDA label', title: 'Metformin extended-release', url: 'https://example.org/label/metformin-er', official: { drug: 'Metformin', sections: {
  adverse_reactions: '6 ADVERSE REACTIONS The most common adverse reaction of metformin is nausea.' } } };
const HTML = '<p>Asthma is a chronic disease that affects your airways.</p><h3>What are the symptoms of asthma?</h3><p>The symptoms of asthma include:</p>'
  + '<ul><li>Wheezing</li><li>Coughing, especially early in the morning or at night</li><li>Chest tightness</li></ul><h3>What causes asthma?</h3>'
  + '<p>Asthma attacks can be triggered by allergens.</p><p>CHILDREN with asthma often have allergies.</p><p>Asthma attacks can be triggered by smoke.</p>';
const HTML2 = HTML.replace('<p>CHILDREN with asthma often have allergies.</p>', '');
const MLP = { source: 'MedlinePlus', title: 'Asthma', url: 'https://medlineplus.gov/asthma.html', full: P.structuredText(HTML) };
const SRC = [LABEL, MLP];
const W = '5 WARNINGS AND PRECAUTIONS 5.1 Lactic Acidosis There have been postmarketing cases of metformin-associated lactic acidosis, including fatal cases. '
  + 'Metformin decreases the liver uptake of lactate. 5.2 Vitamin B12 Deficiency Metformin may lower vitamin B12 levels. Measure hematologic parameters annually.';
const WL = { source: 'openFDA label', title: 'Metformin hydrochloride tablets', url: 'u', official: { drug: 'Metformin Hydrochloride', sections: { warnings_and_cautions: W } } };
const METFORMIN = new Set(['metformin']);
const ASTHMA = new Set(['asthma']);
const section = name => [].concat(LABEL.official.sections[name]).join('\n');
const fact = text => ({ kind: 'fact', text });

// a quote states its claim word for word: the same words, but for the salt
// a label names its drug with ("metformin hydrochloride" is metformin)
const SALT = new Set(['hydrochloride', 'hcl', 'mesylate', 'besylate', 'maleate']);
const plainKey = t => (P.normalize(t) || []).filter(w => !SALT.has(w)).join(' ');
const statementsOf = src => src.official
  ? Object.values(src.official.sections).flatMap(t => P.fdaSegments([].concat(t).join('\n'), METFORMIN).map(s => s.text))
  : P.mlpSegments(src.full, ASTHMA).map(s => s.text);
/// Every claim proven, each by a quote that states it word for word and is
/// one of the statements of the source it names.
const quoted = (r, srcs) => r.proven === r.claims && r.quotes.length === r.claims && r.quotes.every(q => {
  const src = srcs.find(s => s.source === q.source && s.title === q.title && s.url === q.url);
  return src && statementsOf(src).includes(q.quote) && plainKey(q.claim) !== '' && plainKey(q.quote) === plainKey(q.claim);
});

// MARK: 1. reading words

{
  table(P.normalize, [
    ['2 mg or more', ['gte', '2', 'mg']], ['2 mg or more than', ['2', 'mg', 'or', 'more', 'than']], ['10 or greater', ['gte', '10']],
    ['or more', ['or', 'more']], ['a >= b', ['a', 'gte', 'b']], ['a ≥ b', ['a', 'gte', 'b']], ['+/- 2', ['plusminus', '2']], ['± 2', ['plusminus', '2']],
    ['and/or', ['andor']], ['per cent', ['percent']], ['50%', ['50', 'percent']], ['every 4 to 6 hours', ['q', '4', 'to', '6', 'hour']],
    ['twice daily', ['freq2d']], ['2 times a day', ['freq2d']], ['as needed', ['prn']], ['by mouth', ['po']], ['5 mcg/kg', ['5', 'mcg', 'per', 'kg']],
    ['in patients with asthma', ['in', 'asthma']], ['Do not crush', ['do', 'not', 'crush']], ['1st', ['first']], ['21st', ['21', 'ordinal']],
    ['E. coli', ['e', 'coli']], ['U.S.', ['us']],
  ], 'doses, frequencies, comparisons and signs, each spelled one way');
  table(P.normalize, [
    ['1,000', ['1000']], ['12,345', ['12345']], ['1,000,000', ['1000000']], ['1,000,000,000', ['1000000000']],
    ['1,000,000,000,000,000', ['1000000000000000']], ['1,0000', ['1', '0000']], ['1.50', ['1.5']], ['2.0', ['2']], ['10.000', ['10']],
    ['1.0501', ['1.0501']], ['0.50', ['0.5']], ['.5', ['0.5']], ['1.' + '0'.repeat(20) + '1', ['1.' + '0'.repeat(20) + '1']], ['1.' + '0'.repeat(20), ['1']],
  ], 'numbers: thousands commas and trailing zeros off, never another number');
  table(P.normalize, [
    ['café', ['cafe']], ['αβ', ['alpha', 'beta']], ['ὖ', ['upsilon']], ['H₂O', ['h', '2', 'o']], ['a\u0301', ['a']], ['a' + '\u0301'.repeat(8), ['a']],
  ], 'letters past ASCII: marks off, Greek letters named');
  table(P.normalize, [
    ['Metformin 中', null], ["he'd", null], ['x10^9/L', null], ['10(9)', null], ['take 2²', null], ['a' + '\u0301'.repeat(9), null], ['a\u0000', null],
  ], 'what cannot be read for certain is not read: a letter not known, a contraction, a power, more than 8 marks, a cut');
  table(s => P.plainUnicode(s), [
    ['Café', 'cafe'], ['ﬁ ① Ⅳ ℃ ½', 'fi 1 iv °c 1⁄2'], ['a' + '\u0301'.repeat(16), 'a\u0000'],
  ], 'plainUnicode: wide and joined forms made plain, a run of more than 8 marks cut');
  // the short way (most of a label's signs) reads as the long way does
  const signs = [...P.KEPT_SIGNS].map(c => 'Take ' + c + ' 2 mg' + c);
  const fixed = '®™©℠\u00ad\u200b\u200c\u200d\u2060\ufeff\u00a0‑\u202f\u205f\u3000' + Array.from({ length: 11 }, (_, i) => String.fromCharCode(0x2000 + i)).join('');
  for (const c of fixed) signs.push('Take' + c + '2 mg' + c + 'Daily');
  signs.push('Metformin — 500 mg • twice daily ≥ 2 “meals” ±1 °C', 'non‑breaking\u00a0space');
  const differ = signs.filter(s => P.plainUnicode(s) !== P.plainUnicode(s, true));
  for (const s of differ.slice(0, 4)) console.log(`     ${JSON.stringify(s)}: ${JSON.stringify(P.plainUnicode(s))}, the long way ${JSON.stringify(P.plainUnicode(s, true))}`);
  ok(!differ.length, `the short way reads the signs it takes (${signs.length}: dashes, quotes, bullets, spaces, hidden characters) as the long way does`);
  table(P.splitSentences, [
    ['Metformin lowers glucose. It is taken with meals; it is cheap. See e.g. the label. Dr. Smith said so!',
      ['Metformin lowers glucose.', 'It is taken with meals;', 'it is cheap.', 'See e.g. the label.', 'Dr. Smith said so!']],
    ['', []], [' ', []],
  ], 'sentences: split at their ends, not at an abbreviation');
  table(P.isNum, [['12', true], ['1.5', true], ['1.', false], ['.5', false], ['1e3', false], ['', false]], 'a number is digits, and a fraction after a point');
}

// MARK: 2. heft

{
  table(P.heft, [
    ['', 0], ['abc', 3], ['a=b', 5], ['a-b', 5], ["a'b", 5], ['a•b', 5], ['10mg', 5], ['mg10mg', 8],
    ['é', 14], ['ὖ', 14], ['a\u0301', 15], ['é'.repeat(10), 135],
  ], "heft: a character's worth each, more for a sign, letters meeting digits and what only the full passes read");
  // a claim made of what is slow to read pays for it
  const plain = 'Metformin lowers glucose ' + 'u'.repeat(10) + '.';
  const greek = 'Metformin lowers glucose ' + 'ὖ'.repeat(10) + '.';
  const a = P.claimsFor(fact(plain)).work, g = P.claimsFor(fact(greek)).work;
  ok(g - a >= 3 * (P.heft(greek) - P.heft(plain)), `a claim of Greek letters with their marks pays its heft (${g}, ${a} for one of ASCII letters)`);
}

// MARK: 3. statements

{
  const expect = {
    indications_and_usage: [[true, 'Metformin is indicated as an adjunct to diet and exercise to improve glycemic control in adults with type 2 diabetes mellitus.']],
    dosage_and_administration: [
      [true, 'Adult Dosage The recommended starting dose of metformin is 500 mg twice a day with meals.'],
      [true, 'Dosage The recommended starting dose of metformin is 500 mg twice a day with meals.'],
      [true, 'The recommended starting dose of metformin is 500 mg twice a day with meals.'],
      [false, 'The recommended starting dose of metformin is 500 mg once a day with meals.']],
    contraindications: [
      [true, 'Metformin is contraindicated in patients with Severe renal impairment (eGFR below 30 mL/min/1.73 m2)'],
      [true, 'Metformin is contraindicated in patients with Hypersensitivity to metformin']],
    adverse_reactions: [[true, 'The most common adverse reaction of metformin is diarrhea.']],
    mechanism_of_action: [
      [true, 'Mechanism of Action Metformin decreases hepatic glucose production.'],
      [true, 'Action Metformin decreases hepatic glucose production.'],
      [true, 'Metformin decreases hepatic glucose production.'],
      [false, 'Metformin decreases intestinal absorption of glucose.'],
      [false, 'However, metformin does not cause hypoglycemia in most patients.']],
  };
  for (const [name, want] of Object.entries(expect)) {
    const segs = P.fdaSegments(section(name), METFORMIN);
    ok(eq(statements(segs), want) && !segs.cut, `${name}: each statement, under its heading's words; a statement after the first about the drug, qualified, never proves (work ${segs.work})`);
  }
  // the heading words a statement needs: from its subsection's title on
  const w = P.fdaSegments(W, METFORMIN);
  ok(eq(w.map(s => [s.text, s.req]), [
    ['Lactic Acidosis There have been postmarketing cases of metformin-associated lactic acidosis, including fatal cases.', []],
    ['Acidosis There have been postmarketing cases of metformin-associated lactic acidosis, including fatal cases.', ['lactic']],
    ['There have been postmarketing cases of metformin-associated lactic acidosis, including fatal cases.', ['lactic', 'acidosis']],
    ['Metformin decreases the liver uptake of lactate.', ['lactic', 'acidosis']],
    ['Vitamin B12 Deficiency Metformin may lower vitamin B12 levels.', []],
    ['B12 Deficiency Metformin may lower vitamin B12 levels.', ['vitamin']],
    ['Deficiency Metformin may lower vitamin B12 levels.', ['vitamin', 'b', '12']],
    ['Metformin may lower vitamin B12 levels.', ['vitamin', 'b', '12', 'deficiency']],
    ['Measure hematologic parameters annually.', ['vitamin', 'b', '12', 'deficiency']],
  ]) && w.every(s => s.usable) && !w.cut, `subsection titles: a statement under one needs its words, but those already in it (work ${w.work})`);
  // MedlinePlus: a list item only with its lead-in; a population named in
  // capitals qualifies what follows it
  const m = P.mlpSegments(MLP.full, ASTHMA);
  const listed = [
    [true, 'Asthma is a chronic disease that affects your airways.'],
    [false, 'The symptoms of asthma include:'],
    [true, 'The symptoms of asthma include Wheezing'],
    [true, 'The symptoms of asthma include Coughing, especially early in the morning or at night'],
    [true, 'The symptoms of asthma include Chest tightness'],
    [true, 'Asthma attacks can be triggered by allergens.'],
    [true, 'CHILDREN with asthma often have allergies.'],
    [false, 'Asthma attacks can be triggered by smoke.']];
  ok(eq(statements(m), listed), `MedlinePlus: each list item with its lead-in, the lead-in alone not; after "CHILDREN with asthma", qualified (work ${m.work})`);
  const m2 = P.mlpSegments(P.structuredText(HTML2), ASTHMA);
  ok(eq(statements(m2), listed.filter(([, t]) => !t.startsWith('CHILDREN')).map(([u, t]) => [u || t.endsWith('smoke.'), t])),
    'and without it, the statement after it stands alone');
  // stopped at the purse: a symbol thrown, the same statements at the work's end
  const d = P.fdaSegments(section('dosage_and_administration'), METFORMIN);
  ok(throwsOver(() => P.fdaSegments(section('dosage_and_administration'), METFORMIN, d.work - 1))
    && sameSegs(P.fdaSegments(section('dosage_and_administration'), METFORMIN, d.work), d), `a label section stops a unit short of its work (${d.work}), and reads the same with it`);
  const short = P.structuredText(HTML.slice(0, HTML.indexOf('<h3>What causes')));
  const ms = P.mlpSegments(short, ASTHMA);
  ok(throwsOver(() => P.mlpSegments(short, ASTHMA, ms.work - 1)) && sameSegs(P.mlpSegments(short, ASTHMA, ms.work), ms),
    `a MedlinePlus summary too (${ms.work})`);
  // MedlinePlus' HTML as lines
  table(P.structuredText, [
    [HTML, 'Asthma is a chronic disease that affects your airways.\nWhat are the symptoms of asthma?\nThe symptoms of asthma include:\n• Wheezing\n'
      + '• Coughing, especially early in the morning or at night\n• Chest tightness\nWhat causes asthma?\nAsthma attacks can be triggered by allergens.\n'
      + 'CHILDREN with asthma often have allergies.\nAsthma attacks can be triggered by smoke.'],
    ['<p>Asthma is a chronic disease.</p><ul><li>A</li><ul><li>B</li></ul></ul><!-- x --> tail  \n  end', 'Asthma is a chronic disease.\n• A\n•• B\ntail end'],
    ['<p>A <!-- never closed <p>B</p>', 'A <!-- never closed\nB'],
    ['&lt;p&gt;Escaped&lt;/p&gt;&lt;p&gt;Twice &amp;amp; more&lt;/p&gt;', 'Escaped\nTwice & more'],
    ['<p>10<sup>9</sup> cells</p><p>&foo; and &#x3b1; and &#99999999;</p>', '10\u00009 cells\n\u0000 and α and \u0000'],
  ], 'MedlinePlus HTML as lines: a paragraph or heading each, list items led by a "•" a level, comments out; 10<sup>9</sup> and an entity not known unreadable');
  ok(P.structuredText('<p>a &#x110000; b &#1114112; c &#x10FFFF;</p>') === 'a \u0000 b \u0000 c \u{10FFFF}', 'a character reference past the last code point is unreadable, not a throw');
  // a list nested past LIST_DEPTH (8): its items cannot be read for certain
  const nested = n => {
    let h = '<p>Asthma symptoms include:</p>';
    for (let i = 1; i <= n; i++) h += '<ul><li>Asthma level ' + i + ' wheezing';
    for (let i = 1; i <= n; i++) h += '</li></ul>';
    return h + '<p>Asthma attacks can be triggered by allergens.</p>';
  };
  const said = n => 'Asthma symptoms include ' + Array.from({ length: n }, (_, i) => 'Asthma level ' + (i + 1) + ' wheezing').join(' ') + '.';
  const deep = n => {
    const full = P.structuredText(nested(n));
    const src = [{ source: 'MedlinePlus', title: 'Asthma', url: 'm', full }];
    const why = k => P.prove(fact(k), src).why || 'proven';
    return { lines: full.split('\n'), why, said: k => why(said(k)), after: why('Asthma attacks can be triggered by allergens.') };
  };
  const d8 = deep(8), d9 = deep(9), d10 = deep(10);
  ok(d8.said(8) === 'proven' && d8.said(7) === 'unproven' && d8.after === 'proven', 'a list 8 levels deep: its last item, with every lead-in to it, proven (not short of one)');
  ok(eq(d9.lines.slice(-3), ['•••••••• Asthma level 8 wheezing', '•••••••• \u0000Asthma level 9 wheezing', 'Asthma attacks can be triggered by allergens.'])
    && d9.said(8) === 'unproven' && d9.said(9) === 'unproven' && d9.after === 'proven',
    '9 deep: the ninth level cut, taking back the list it is in; what follows the list still proves');
  ok(d10.lines.includes('•••••••• \u0000Asthma level 9 wheezing') && d10.lines.includes('•••••••• \u0000Asthma level 10 wheezing')
    && d10.said(9) === 'unproven' && d10.said(10) === 'unproven' && d10.after === 'proven', '10 deep: every level past 8 cut');
}

// MARK: 4. claims

{
  table(([q, a, mcq, n]) => P.declaratives(q, a, mcq, n), [
    [['', 'Metformin'], null], [['   ', 'Metformin'], null], [['What is the drug of choice for type 2 diabetes?', ''], null],
    [['___ is the first-line drug for type 2 diabetes.', '$& metformin'], ['$& metformin is the first-line drug for type 2 diabetes.']],
    [['Metformin is ___ for type 2 diabetes.', "$1 $' first-line"], ["Metformin is $1 $' first-line for type 2 diabetes."]],
    [['What is the drug of choice for type 2 diabetes?', 'Metformin'],
      ['the drug of choice for type 2 diabetes is Metformin', 'Metformin is the drug of choice for type 2 diabetes', 'the drug of choice for type 2 diabetes is a Metformin']],
    [['Which drug is first-line for type 2 diabetes?', 'Metformin', true], ['Metformin is first-line for type 2 diabetes']],
    [['Which of the following is the first-line drug for type 2 diabetes?', 'Metformin', true], ['Metformin is the first-line drug for type 2 diabetes']],
    [['What are the symptoms of asthma?', 'Wheezing', false, 3], ['the symptoms of asthma include Wheezing']],
    [['Which drug is not first-line for type 2 diabetes?', 'Insulin', true], null],
    [['___ treats ___.', 'Metformin'], null],
    [['The first-line drug for type 2 diabetes is:', 'metformin', true], ['The first-line drug for type 2 diabetes is metformin']],
  ], 'a question and its answer as the statements a source would make ("$&" and the like as written; a negated question or two blanks, none)');
  const card = P.claimsFor({ kind: 'card', text: 'Q: What are the symptoms of asthma?\nA: Wheezing; Chest tightness' });
  ok(eq(card.claims, [
    { text: 'What are the symptoms of asthma? Wheezing', alts: ['the symptoms of asthma include Wheezing'] },
    { text: 'What are the symptoms of asthma? Chest tightness', alts: ['the symptoms of asthma include Chest tightness'] }]),
  `a card: a claim for each of its answers (work ${card.work})`);
  const mcq = P.claimsFor({ kind: 'mcq', stem: 'The most common adverse reaction of metformin is:', options: ['Diarrhea', 'Nausea', 'Rash'], key: 0, explanation: '' });
  ok(eq(mcq.claims, [{ text: 'The most common adverse reaction of metformin is: Diarrhea', alts: ['The most common adverse reaction of metformin is Diarrhea'] }])
    && eq(mcq.distractors, [['The most common adverse reaction of metformin is Nausea'], ['The most common adverse reaction of metformin is Rash']]),
  `a question: its key a claim, each distractor what a source must not state (work ${mcq.work})`);
  const many = P.claimsFor(fact(Array.from({ length: 10 }, (_, i) => `Metformin lowers glucose in group ${i + 1}`).join('. ') + '.'));
  ok(many.claims.length === P.MAX_CLAIMS + 2, `ten claims: read no further than ${P.MAX_CLAIMS + 2}, enough to say there are too many (MAX_CLAIMS ${P.MAX_CLAIMS})`);
  for (const item of [fact('Metformin decreases hepatic glucose production.'), { kind: 'card', text: 'Q: What are the symptoms of asthma?\nA: Wheezing; Chest tightness' },
    { kind: 'mcq', stem: 'The most common adverse reaction of metformin is:', options: ['Diarrhea', 'Nausea', 'Rash'], key: 0, explanation: '' },
    { kind: 'note', text: 'Metformin hydrochloride\nMetformin decreases hepatic glucose production.\n- Metformin is contraindicated in patients with hypersensitivity to metformin.' }]) {
    const c = P.claimsFor(item);
    const at = P.claimsFor(item, c.work);
    ok(throwsOver(() => P.claimsFor(item, c.work - 1)) && same(at, c) && at.work === c.work && same(P.claimsFor(item), c),
      `a ${item.kind}'s claims stop a unit short of their work (${c.work}), and are the same with it and again`);
  }
}

// MARK: 5. proof

{
  const verdicts = [
    ['item', null, 0], ['kind', { kind: 'page', text: 'Metformin lowers glucose.' }, 0], ['empty', { kind: 'note', text: 'Metformin hydrochloride' }, 0],
    ['many', fact(Array.from({ length: 10 }, (_, i) => `Metformin lowers glucose in group ${i + 1}`).join('. ') + '.'), 8],
    ['claim', fact('Is metformin first-line.'), 1], ['unproven', fact('Metformin cures asthma in older adults.'), 1],
    ['split', fact('Metformin 2. 5 mg daily.'), 0], ['cut', { kind: 'note', text: 'Metformin\n' + 'Metformin lowers glucose. '.repeat(140) }, 0],
    ['structure', { kind: 'note', text: 'Metformin\n# Dosing\nTake with meals.' }, 0], ['card', { kind: 'card', text: 'Metformin lowers glucose.' }, 0],
    ['mcq', { kind: 'mcq', stem: 'Which drug is first-line?', options: ['Metformin'], key: 0 }, 0],
    ['stem', { kind: 'mcq', stem: 'Which drug lowers glucose?', options: ['Metformin', 'Insulin'], key: 0 }, 0],
    ['options', { kind: 'mcq', stem: 'Which drug is first-line?', options: ['Metformin', 'All of the above'], key: 0 }, 0],
  ];
  const bad = [];
  for (const [why, item, claims] of verdicts) {
    const r = P.prove(item, SRC);
    if (r.v !== P.PROOF_VERSION || r.why !== why || r.claims !== claims || r.proven !== 0 || r.quotes.length || (why === 'item' && r.read !== 0)) bad.push([why, r]);
  }
  for (const [why, r] of bad) console.log(`     ${why}: ${JSON.stringify(r)}`);
  ok(!bad.length, `each item it cannot prove says why: ${verdicts.map(v => v[0]).join(', ')}`);
  const proven = fact('Metformin decreases hepatic glucose production.');
  const none = [[{ source: 'Europe PMC', title: 'x', full: 'Metformin decreases hepatic glucose production.' }], [], null]
    .map(o => P.prove(proven, o));
  ok(none.every(r => r.why === 'no-source' && r.proven === 0 && r.claims === 1), 'no openFDA label or MedlinePlus summary, nothing proven: Europe PMC stating it word for word is no proof');
  const broke = P.prove(proven, SRC, { chars: 0 });
  ok(broke.why === 'budget' && broke.read === 0 && broke.claims === 0, "no budget: 'budget', nothing read");
  // proven: each claim by a quote of an official source, word for word
  const items = {
    'a fact': [fact('Metformin decreases hepatic glucose production.'), 1],
    'a MedlinePlus fact': [fact('Asthma is a chronic disease that affects your airways.'), 1],
    'a list item with its lead-in': [fact('The symptoms of asthma include wheezing.'), 1, 'The symptoms of asthma include Wheezing'],
    'a card of two answers': [{ kind: 'card', text: 'Q: What are the symptoms of asthma?\nA: Wheezing; Chest tightness' }, 2],
    'a cloze': [{ kind: 'card', text: 'Cloze: Metformin decreases {{c1::hepatic glucose production}}.' }, 1],
    'a question': [{ kind: 'mcq', stem: 'The most common adverse reaction of metformin is:', options: ['Diarrhea', 'Nausea', 'Rash'], key: 0, explanation: '' }, 1,
      'The most common adverse reaction of metformin is diarrhea.'],
    'a question with lettered options and an explanation': [{ kind: 'mcq', stem: 'The most common adverse reaction of metformin is:', options: ['A. Diarrhea', 'B. Nausea', 'C. Rash'],
      key: 0, explanation: 'Answer: A. Metformin decreases hepatic glucose production.' }, 2],
    'a contraindication from a bulleted list': [fact('Metformin is contraindicated in patients with hypersensitivity to metformin.'), 1,
      'Metformin is contraindicated in patients with Hypersensitivity to metformin'],
    'the drug named with its salt': [fact('Metformin hydrochloride is contraindicated in patients with hypersensitivity to metformin.'), 1],
    'a dose under its subsection': [fact('The recommended starting dose of metformin is 500 mg twice a day with meals.'), 1],
    '"twice daily" for "twice a day"': [fact('The recommended starting dose of metformin is 500 mg twice daily with meals.'), 1,
      'The recommended starting dose of metformin is 500 mg twice a day with meals.'],
    'an indication': [fact('Metformin is indicated as an adjunct to diet and exercise to improve glycemic control in adults with type 2 diabetes mellitus.'), 1],
    'a trigger': [fact('Asthma attacks can be triggered by allergens.'), 1],
    'a note of two': [{ kind: 'note', text: 'Metformin hydrochloride\nMetformin decreases hepatic glucose production.\n- Metformin is contraindicated in patients with hypersensitivity to metformin.' }, 2],
  };
  for (const [what, [item, claims, quote]] of Object.entries(items)) {
    const r = P.prove(item, SRC);
    ok(r.v === P.PROOF_VERSION && r.why === undefined && r.claims === claims && quoted(r, SRC) && (!quote || r.quotes[0].quote === quote),
      `proven, ${what}: ${r.quotes.map(q => JSON.stringify(q.quote)).join(', ')} (read ${r.read})`);
  }
  // unproven: no statement says it word for word
  const unproven = {
    'a statement qualified by the one before it': [fact('Metformin decreases intestinal absorption of glucose.'), 1, 0],
    'a list item without its lead-in': [fact('Asthma causes chest tightness.'), 1, 0],
    'a dose for adults where the label says "Adult Dosage" before it': [fact('The recommended adult starting dose of metformin is 500 mg twice a day with meals.'), 1, 0],
    "the children's dose, under its heading": [fact('The recommended starting dose of metformin is 500 mg once a day with meals.'), 1, 0],
    'a statement after a population in capitals': [fact('Asthma attacks can be triggered by smoke.'), 1, 0],
    'a note one claim of which is not stated': [{ kind: 'note', text: 'Metformin\nMetformin decreases hepatic glucose production.\nMetformin cures asthma.' }, 2, 1],
    "a note whose title is a claim not stated": [{ kind: 'note', text: 'Metformin lowers weight\nMetformin decreases hepatic glucose production.' }, 2, 0],
  };
  for (const [what, [item, claims, provenN]] of Object.entries(unproven)) {
    const r = P.prove(item, SRC);
    ok(r.why === 'unproven' && r.claims === claims && r.proven === provenN && r.quotes.length === provenN, `unproven, ${what} (read ${r.read})`);
  }
  const smoke = P.prove(fact('Asthma attacks can be triggered by smoke.'), [LABEL, { ...MLP, full: P.structuredText(HTML2) }]);
  ok(smoke.why === undefined && smoke.quotes[0]?.quote === 'Asthma attacks can be triggered by smoke.', 'and proven where the population is not named before it');
  // a question whose distractor another label states
  const q = items['a question'][0];
  const both = P.prove(q, [LABEL, LABEL2]), other = P.prove(q, [LABEL2]);
  ok(both.why === 'distractor' && both.claims === 1 && both.proven === 1 && both.quotes.length === 1 && other.why === 'unproven',
    "a question's key stated by one label, a distractor by another: 'distractor', never proven");
  // a summary as MedlinePlus sends it (escaped HTML), made text only when a
  // claim asks: the same proofs as from its text
  const SENT = HTML.replace(/</g, '&lt;').replace(/>/g, '&gt;');
  const asSent = () => ({ source: 'MedlinePlus', title: 'Asthma', url: MLP.url, html: SENT });
  const differ = Object.entries(items).filter(([, [item]]) => {
    const a = P.prove(item, [LABEL, MLP]), b = P.prove(item, [LABEL, asSent()]);
    return a.why !== b.why || a.proven !== b.proven || !same(a.quotes, b.quotes);
  });
  for (const [what] of differ) console.log(`     ${what}`);
  ok(!differ.length, 'a summary as sent proves what its text does');
  const fromSent = Object.entries(unproven).every(([, [item]]) => P.prove(item, [LABEL, asSent()]).why === 'unproven');
  ok(fromSent, 'and proves nothing its text does not');
  {
    const a = fact('Asthma is a chronic disease that affects your airways.'), b = fact('Asthma attacks can be triggered by allergens.');
    const entry = asSent();
    const alone = P.prove(b, [asSent()]);
    const paid = new Map();
    const first = P.prove(a, [entry], { paid }), second = P.prove(b, [entry], { paid });
    ok(first.why === undefined && second.why === undefined && alone.why === undefined && alone.read - second.read >= P.htmlWork(SENT),
      `made text once a batch, paid for by the first item that asks (${alone.read} alone, ${second.read} after another)`);
    const poor = P.prove(b, [asSent()], { chars: alone.read - 1 });
    ok(poor.why === 'budget', "a summary it cannot afford to read: 'budget', never 'unproven'");
  }
  ok(P.htmlWork('a&b<c\nd') === 7 + 3 * 2, 'the work of making HTML text: a character each, more for each "&", "<" and line break');
  ok(same(P.drugTokens('Metformin Hydrochloride'), ['metformin']) && same(P.drugTokens('metformin'), ['metformin']),
    'a drug named with its salt is the drug');
  // a lookup that failed: what was not read might have proven it
  {
    const p = fact('Metformin decreases hepatic glucose production.'), u = fact('Metformin cures asthma.');
    ok(P.prove(p, [], { unread: 1 }).why === 'lookup' && P.prove(p, []).why === 'no-source', "no source read because a lookup failed: 'lookup', not 'no-source'");
    ok(P.prove(u, SRC, { unread: 1 }).why === 'lookup' && P.prove(u, SRC).why === 'unproven', "a claim not proven while a lookup failed: 'lookup', not 'unproven'");
    ok(P.prove(p, SRC, { unread: 1 }).why === undefined, 'a fact proven stays proven');
    ok(P.prove(q, [LABEL], { unread: 1 }).why === 'lookup' && P.prove(q, [LABEL]).why === undefined,
      "a question proven while a lookup failed: 'lookup', as the source not read might state another option");
    ok(P.prove(p, SRC, { chars: 0, unread: 1 }).why === 'budget', "and 'budget' stays 'budget'");
    const proof = P.prove(p, SRC);
    ok(P.fullyProven(proof) && !P.fullyProven(P.prove(u, SRC)) && !P.fullyProven({ ...proof, v: P.PROOF_VERSION + 1 })
      && !P.fullyProven({ ...proof, claims: 0, proven: 0 }) && !P.fullyProven({ ...proof, proven: 0 }) && !P.fullyProven(null) && !P.fullyProven('x'),
      'fully proven: this version, no why, every claim of at least one proven');
  }
  // near misses
  const near = [
    ['The most common adverse reaction is diarrhea.', 'unproven'], ['Decreases hepatic glucose production.', 'unproven'],
    ['The recommended starting dose of metformin is 850 mg twice a day with meals.', 'unproven'],
    ['The recommended starting dose of metformin is 5000 mg twice a day with meals.', 'unproven'],
    ['The recommended starting dose of metformin is 500 mcg twice a day with meals.', 'unproven'],
    ['The recommended starting dose of metformin is 500 mg three times a day with meals.', 'unproven'],
    ['The recommended starting dose of metformin is 500 mg twice a day without meals.', 'unproven'],
    ['Metformin does not decrease hepatic glucose production.', 'unproven'], ['Metformin increases hepatic glucose production.', 'unproven'],
    ['Metformin decreases hepatic glucose production in children.', 'unproven'],
    ['Metformin is not contraindicated in patients with hypersensitivity to metformin.', 'unproven'],
    ['Insulin decreases hepatic glucose production.', 'unproven'],
    ['The recommended starting dose of metformin is 0.5 g twice a day with meals.', 'unproven'],
    ['Asthma attacks can be triggered by allergens and smoke.', 'unproven'], ['Asthma is a chronic disease that affects your lungs.', 'unproven'],
    ['It decreases hepatic glucose production.', 'claim'], ['Metformin decreases hepatic glucose production 中.', 'claim'],
  ];
  table(t => P.prove(fact(t), SRC).why || 'proven', near,
    'near misses unproven: another dose, unit, frequency or drug, a negation, a population, one word more or another; a pronoun or a letter not known, no claim');
  const close = ['Metformin decreases hepatic glucose production', 'metformin decreases HEPATIC glucose production!', 'Metformin decreases hepatic glucose-production.',
    'Metformin hydrochloride decreases hepatic glucose production.', 'Metformin HCl decreases hepatic glucose production.',
    'The recommended starting dose of metformin is 500 milligrams twice daily with meals.'];
  const notQuoted = close.filter(t => !quoted(P.prove(fact(t), SRC), SRC));
  for (const t of notQuoted) console.log(`     ${t}: ${JSON.stringify(P.prove(fact(t), SRC))}`);
  ok(!notQuoted.length, 'and proven, written another way: case, a stop, a hyphen, a salt, "milligrams" and "twice daily"');
  // heading words a claim needs
  const heading = [
    ['There have been postmarketing cases of metformin-associated lactic acidosis, including fatal cases.', 'proven'],
    ['Metformin decreases the liver uptake of lactate.', 'unproven'], ['Lactic acidosis: metformin decreases the liver uptake of lactate.', 'unproven'],
    ['Metformin may lower vitamin B12 levels.', 'unproven'], ['Vitamin B12 deficiency: metformin may lower vitamin B12 levels.', 'proven'],
    ['Vitamin B12 Deficiency Metformin may lower vitamin B12 levels.', 'proven'],
  ];
  table(t => P.prove(fact(t), [WL]).why || 'proven', heading, "a statement under a subsection's title: proven only with the title's words");
  ok(heading.filter(([, v]) => v === 'proven').every(([t]) => quoted(P.prove(fact(t), [WL]), [WL])), 'each by its quote, word for word');
  const U = { source: 'openFDA label', title: 'U', url: 'u', official: { drug: 'Metformin', sections: { mechanism_of_action: 'Metformin decreases hepatic glucose production 中.' } } };
  ok(P.prove(proven, [U]).why === 'unproven', 'a source statement that cannot be read for certain proves nothing');
}

// MARK: 6. the purse

const PURSE_ITEMS = [fact('Metformin decreases hepatic glucose production.'), fact('Metformin decreases intestinal absorption of glucose.'),
  fact('Asthma attacks can be triggered by allergens.'), { kind: 'card', text: 'Q: What are the symptoms of asthma?\nA: Wheezing; Chest tightness' },
  { kind: 'mcq', stem: 'The most common adverse reaction of metformin is:', options: ['Diarrhea', 'Nausea', 'Rash'], key: 0, explanation: '' },
  { kind: 'note', text: 'Metformin hydrochloride\nMetformin decreases hepatic glucose production.\n- Metformin is contraindicated in patients with hypersensitivity to metformin.' },
  fact('The recommended starting dose of metformin is 500 mg twice a day with meals.'), fact('Asthma attacks can be triggered by smoke.')];

{
  const [fda, fda2] = PURSE_ITEMS;
  // a batch pays for a section once
  const paid = new Map();
  const a = P.prove(fda, SRC, { paid }), b = P.prove(fda, SRC, { paid }), c = P.prove(fda2, SRC, { paid });
  const alone = P.prove(fda2, SRC);
  ok(same(b, { ...a, read: b.read }) && b.read < a.read && c.why === alone.why && c.read < alone.read,
    `a section is paid for once a batch: the same item again reads ${b.read} (${a.read} the first time), another ${c.read} (${alone.read} alone), the same verdicts`);
  // a long title: read to its end, or the section cut and the verdict 'budget'
  const NATO = 'Alpha Bravo Charlie Delta Echo Foxtrot Golf Hotel India Juliett Kilo Lima Mike November Oscar Papa Quebec Romeo Sierra Tango Uniform Victor Whiskey Xray Yankee Zulu'.split(' ');
  const pad = ' Metformin is taken by mouth.'.repeat(30);
  const lab = n => ({ source: 'openFDA label', title: 'T', url: 'u', official: { drug: 'Metformin Hydrochloride', sections: {
    mechanism_of_action: '12.1 ' + NATO.slice(0, n).join(' ') + ' metformin decreases hepatic glucose production.' + pad } } });
  const titled = n => [P.prove(fda, [lab(n)]).why, P.fdaSegments(lab(n).official.sections.mechanism_of_action, METFORMIN).cut, P.prove(fact('Metformin is taken by mouth.'), [lab(n)]).why];
  ok(eq([3, 24, 25, 26].map(titled), [['unproven', false, 'unproven'], ['unproven', false, 'unproven'], ['unproven', false, 'unproven'], ['budget', true, 'budget']]),
    "a subsection's title of up to 25 words read, its words needed; past that, the section cut: 'budget', never unproven or proven");
  // the sections kept between batches: a capped few, the answers the same
  const r1 = P.prove(fda, SRC);
  for (let i = 0; i < 70; i++) {
    const L = structuredClone(LABEL);
    L.official.sections.mechanism_of_action += ' Variant ' + i + '.';
    P.prove(fda, [L, MLP]);
  }
  ok(same(P.prove(fda, SRC), r1) && same(P.prove(fda, SRC), r1), 'the same answer after 70 other labels were read, and again');
  // every purse short of what an item reads: its verdict or 'budget', never
  // another; and never read past the purse
  let checks = 0;
  const wrong = [];
  for (const it of PURSE_ITEMS) {
    const full = P.prove(it, SRC);
    for (let chars = 0; chars <= full.read + 50; chars++) {
      const r = P.prove(it, SRC, { chars });
      checks++;
      const right = r.read <= chars && (chars >= full.read ? same(r, full) : same(r, full) || r.why === 'budget');
      if (!right && wrong.length < 6) wrong.push([it.kind, it.text || it.stem, chars, r.why, r.read, full.why, full.read]);
    }
  }
  for (const w of wrong) console.log(`     ${JSON.stringify(w)}`);
  ok(!wrong.length, `every purse from 0 to past what ${PURSE_ITEMS.length} items read (${checks}): the verdict or 'budget', never another, never read past it`);
  // cold, in a fresh isolate, the same answers as warm
  const url = new URL('../proof.js', import.meta.url).href;
  const cold = execFileSync(process.execPath, ['--input-type=module', '-e', `const P = await import(${JSON.stringify(url)});
const MLP = { source: 'MedlinePlus', title: 'Asthma', url: 'https://medlineplus.gov/asthma.html', full: P.structuredText(${JSON.stringify(HTML)}) };
const SRC = [${JSON.stringify(LABEL)}, MLP];
const paid = new Map();
console.log(JSON.stringify(${JSON.stringify(PURSE_ITEMS)}.map(it => P.prove(it, SRC, { paid }))));`], { encoding: 'utf8' }).trim();
  const paid2 = new Map();
  ok(cold === JSON.stringify(PURSE_ITEMS.map(it => P.prove(it, SRC, { paid: paid2 }))), 'cold, in a fresh isolate, the same answers as warm');
}

// MARK: 7. CPU guards

// the fastest of three runs, in ms
const fastest = (f, x) => { let t = Infinity; for (let i = 0; i < 3; i++) { const a = performance.now(); f(x); t = Math.min(t, performance.now() - a); } return t; };

{
  // marks NFKC must put in order (two classes, alternating or one after the
  // other; a letter's two vowel signs), once a second or more a section
  const GUARDS = [
    ['16,000 marks of two classes, alternating', 'a' + '\u0316\u0301'.repeat(8000), null],
    ['8,000 marks above, then 8,000 below', 'a' + '\u0301'.repeat(8000) + '\u0316'.repeat(8000), null],
    ['16,000 Tibetan vowel signs', 'a' + '\u0f73'.repeat(16000), null],
    ['16,000 half-width sound marks and marks', 'a' + '\uff9e\u0301'.repeat(8000), null],
    ['16,000 marks between hidden spaces', 'a' + '\u0301\u200b\u0316\u200b'.repeat(4000), null],
    ['16,000 marks between trademarks', 'a' + '\u0301\u00ae\u0316\u2122'.repeat(4000), null],
    ['1,600 words of 8 marks', ('a' + '\u0316\u0301'.repeat(4) + ' ').repeat(1600), Array(1600).fill('a')],
    ['32,000 zeros, then a digit', '1.' + '0'.repeat(32000) + '1', ['1.' + '0'.repeat(32000) + '1']],
    ['32,000 trailing zeros', '1.' + '0'.repeat(32000), ['1']],
    ['8,000 thousands commas', '1' + ',000'.repeat(8000), ['1' + '000'.repeat(8000)]],
  ];
  for (const [what, s, want] of GUARDS) {
    const ms = Math.max(fastest(P.normalize, s), fastest(P.normalizeWords, s));
    ok(eq(P.normalize(s), want) && eq(P.normalizeWords(s), want) && ms < 25, `${what} read in ${ms.toFixed(1)} ms`);
  }
  const marks = 'a' + '\u0f73'.repeat(16000);
  const pms = fastest(s => P.plainUnicode(s), marks);
  ok(P.plainUnicode(marks) === 'a\u0000' && pms < 25, `plainUnicode cuts a run of 16,000 Tibetan vowel signs in ${pms.toFixed(1)} ms`);
  const lists = Array.from({ length: 3555 }, (_, i) => (i < 8 ? '•'.repeat(i + 1) + ' ' : '•'.repeat(8) + ' \u0000') + 'a').join('\n');
  const ST = [
    ['32,000 spaces', 'a' + ' '.repeat(32000) + 'b', 'a b'],
    ['32,000 tabs', 'a' + '\t'.repeat(32000) + 'b', 'a b'],
    ['32,000 wide spaces', 'a' + '\u3000'.repeat(32000) + 'b', 'a b'],
    ['32,000 no-break spaces', 'a' + '\u00a0'.repeat(32000) + 'b', 'a b'],
    ['16,000 spaces each side of a line break', 'a' + ' '.repeat(16000) + '\n' + ' '.repeat(16000) + 'b', 'a b'],
    ['8,000 comments never closed', '<!--'.repeat(8000), '<!--'.repeat(8000)],
    ['8,000 comments, closed once', '<!--'.repeat(8000) + '-->', ''],
    ['16,000 tags never closed', '<a'.repeat(16000), '<a'.repeat(16000)],
    ['3,555 lists, each in the one before', '<ul><li>a'.repeat(3555), lists],
  ];
  for (const [what, s, want] of ST) {
    const ms = fastest(P.structuredText, s);
    ok(eq(P.structuredText(s), want) && ms < 25, `MedlinePlus HTML, ${what}: ${ms.toFixed(1)} ms`);
  }
}

// MARK: 8. CPU budget

// the costliest sources to read that the server takes - every section a shape
// slow to read, each with the claims' words in it - n characters a section,
// a nonce so no batch reads one already read
function worstSources(n, nonce) {
  const caps = k => Array.from({ length: k }, (_, i) => 'Word' + (i % 97)).join(' ');
  const words = k => Array.from({ length: k }, (_, i) => 'word' + (i % 97)).join(' ');
  const rep = s => s.repeat(Math.max(1, Math.floor(n / s.length)));
  const fda = {
    boxed_warning: () => rep('5.1 ' + caps(24) + ' metformin lowers glucose.\n'),
    indications_and_usage: () => rep('WARNINGS ABOUT X metformin lowers glucose.\n'),
    dosage_and_administration: () => 'Metformin lowers glucose.\n' + rep('Ab: cd ef.\n'),
    dosage_forms_and_strengths: () => 'Metformin lowers glucose ' + rep('a: '),
    contraindications: () => 'Metformin lowers glucose in patients ' + words(n / 12) + ':\n' + Array.from({ length: n / 8 }, () => '• word').join('\n'),
    warnings_and_cautions: () => Array.from({ length: Math.floor(n / 120) }, (_, i) => '5.' + (i + 1) + ' ' + caps(14) + ' metformin lowers glucose.').join('\n'),
    warnings: () => 'Metformin lowers glucose.\n' + rep('5.1 Ab cd ef.\n'),
    adverse_reactions: () => 'Metformin lowers glucose:\n' + rep('• Ab\n'),
    mechanism_of_action: () => 'Metformin lowers glucose. ' + rep('Ab cd. '),
  };
  const mlps = [() => 'Metformin lowers glucose.' + rep('\n'), () => 'Metformin lowers glucose.\n' + rep('Ab cd.\n')];
  const z = ' z' + nonce + '.';
  const out = [];
  for (let l = 0; l < 2; l++) {
    const sections = {};
    for (const [k, f] of Object.entries(fda)) sections[k] = f() + z + l;
    out.push({ source: 'openFDA label', title: 'Metformin ' + l, url: 'u', official: { drug: 'Metformin Hydrochloride', sections } });
  }
  mlps.forEach((f, i) => out.push({ source: 'MedlinePlus', title: 'Metformin', url: 'm' + i, full: f() + z + i }));
  return out;
}
// a batch as the server proves it: one purse of `per` an item, a section paid
// for once
function runBatch(P, srcs, per, items) {
  const paid = new Map();
  let read = 0;
  const whys = [];
  for (const it of items) {
    const r = P.prove(it, srcs, { chars: per, paid });
    read += r.read;
    whys.push(r.why || 'proven');
  }
  return { read, whys };
}
// items whose claims every source nearly states, so that each is read to its end
const WORST_ITEMS = [
  { kind: 'fact', text: 'Metformin lowers glucose.' }, { kind: 'fact', text: 'Metformin lowers the glucose.' },
  { kind: 'card', text: 'Q: Which drug lowers glucose?\nA: Metformin' }, { kind: 'card', text: 'Cloze: Metformin lowers {{c1::glucose}}.' },
  { kind: 'note', text: 'Metformin\nMetformin lowers glucose.\nMetformin lowers glucose a lot.' }, { kind: 'fact', text: 'Metformin lowers glucose in all.' },
  { kind: 'card', text: 'Q: What are the effects of metformin?\nA: Lowers glucose; Lowers glucose a lot' }, { kind: 'fact', text: 'Metformin lowers glucose at all.' },
];

{
  const url = new URL('../proof.js', import.meta.url).href;
  let nonce = 0;
  for (const [what, per, items, n] of [
    ['8 items of 6,000', P.PROOF_CHARS / 8, WORST_ITEMS, 3000],
    ['8 items of 6,000, longer sections', P.PROOF_CHARS / 8, WORST_ITEMS, 12000],
    ['1 item of 48,000', P.PROOF_CHARS, WORST_ITEMS.slice(0, 1), 3000],
  ]) {
    for (let i = 0; i < 20; i++) runBatch(P, worstSources(n, nonce++), per, items);
    const t = [];
    let last;
    for (let i = 0; i < 30; i++) {
      const srcs = worstSources(n, nonce++);
      const a = performance.now();
      last = runBatch(P, srcs, per, items);
      t.push(performance.now() - a);
    }
    const ms = t.sort((x, y) => x - y)[15];
    console.log(`     warm, ${what}: ${ms.toFixed(2)} ms, read ${last.read} (${(ms * 1e6 / last.read).toFixed(0)} ns a unit): ${last.whys.join(', ')}`);
    ok(last.read <= P.PROOF_CHARS && !last.whys.includes('claim') && ms < 8, `warm, ${what}: never more than PROOF_CHARS read, within a few ms of CPU (about 3 here)`);
    const cold = Number(execFileSync(process.execPath, ['--input-type=module', '-e', `const P = await import(${JSON.stringify(url)});
${worstSources}
${runBatch}
const srcs = worstSources(${n}, 0);
const a = performance.now();
runBatch(P, srcs, ${per}, ${JSON.stringify(items)});
console.log(performance.now() - a);`]).toString().trim());
    console.log(`     cold, ${what}: ${cold.toFixed(1)} ms`);
    ok(cold < 50, `cold, ${what}: a few tens of ms at most, in a fresh isolate`);
  }
}

console.log(failures ? `\n${failures} SOURCE PROOF FAILURE(S)` : '\nALL SOURCE PROOF TESTS PASS');
process.exit(failures ? 1 : 0);
