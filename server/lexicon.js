// The vignette route's lexicon: the exact words a vignette may use for each
// slot a registry rule reads (server/criteria, vignette-proof.js). No fuzzy
// matching and no model: a finding is read only when its whole span is one of
// these forms, and a form not here means the item stays unproven.
//
// Every form is backed, because the step from a patient's words to a rule's
// criterion is a medical fact too (the owner, 14 Oct: every finding-to-rule
// step backed word for word):
//   literal  the form's words are the rule's own words: its tokens (proof.js
//            normalize) run inside the quote of the criterion that reads it,
//            checked by the checker on every proof
//   quoted   a source sentence states the form and the rule's own word side
//            by side ("The TB skin test (also known as the Mantoux
//            tuberculin skin test or TST)"); the quote is proven verbatim
//            against the source's pinned snapshot by the registry review
//            (server/criteria/review.js), and the entry backs Verified only
//            once the owner signs it off (signedOffHash, as for rules)
// A number is read only through a pattern that takes the whole span, in the
// unit its criterion is written in ("mm" and "millimeters" are one unit).
//
// scan: words that mean a slot is mentioned at all; every place one is
// written must lie inside one of the proof's findings for that slot, so a
// mention the lexicon cannot read ("HIV test pending") stops the proof.
//
// cues: the finding's sentence may hold no negation, hedge, other person,
// past time or condition (vignette-proof.js CUES) unless its slot `allows`
// that kind: a slot about a previous test allows the past.

export const LEXICON_VERSION = 1;

/// Units and their written forms: the one table numbers are read through.
export const UNITS = Object.freeze({
  mm: ['mm', 'millimeter', 'millimeters', 'millimetre', 'millimetres'],
  hours: ['hours', 'hour', 'h', 'hrs'],
});

const NUM = '(\\d{1,3}(?:\\.\\d{1,2})?)';
const unit = u => `(?:${UNITS[u].join('|')})`;

/// The slots. `type`: 'flag' (present or not), 'set' (one of named values)
/// or 'number' (a value in `unit`). `forms`: for flag and set slots, each
/// written form with its value and backing; for number slots, whole-span
/// patterns with one number in them.
export const SLOTS = Object.freeze({
  // a tuberculin skin test was done (CDC TB skin test guidance, 2025)
  tst: {
    type: 'flag',
    scan: ['skin test', 'TST', 'tuberculin', 'Mantoux', 'PPD'],
    forms: [
      { form: 'TB skin test', value: true, backing: { kind: 'literal' } },
      {
        form: 'tuberculin skin test', value: true, id: 'lex-tst-tuberculin',
        backing: { kind: 'quoted', source: 'cdc-tst-2025', canonical: 'TB skin test',
          quote: 'The TB skin test (also known as the Mantoux tuberculin skin test or TST) is one method of determining whether a person is infected with TB bacteria.' },
        signedOffAt: null, signedOffBy: null, signedOffHash: null,
      },
      {
        form: 'Mantoux tuberculin skin test', value: true, id: 'lex-tst-mantoux',
        backing: { kind: 'quoted', source: 'cdc-tst-2025', canonical: 'TB skin test',
          quote: 'The TB skin test (also known as the Mantoux tuberculin skin test or TST) is one method of determining whether a person is infected with TB bacteria.' },
        signedOffAt: null, signedOffBy: null, signedOffHash: null,
      },
      {
        form: 'TST', value: true, id: 'lex-tst-abbrev',
        backing: { kind: 'quoted', source: 'cdc-tst-2025', canonical: 'TB skin test',
          quote: 'The TB skin test (also known as the Mantoux tuberculin skin test or TST) is one method of determining whether a person is infected with TB bacteria.' },
        signedOffAt: null, signedOffBy: null, signedOffHash: null,
      },
    ],
  },
  // a skin test done before this one, for what happened after it
  prior_tst: {
    type: 'flag',
    allows: ['past'],
    forms: [
      { form: 'previous TB skin test', value: true, backing: { kind: 'literal' } },
    ],
  },
  // the reaction measured, in millimetres of induration (never erythema:
  // "The reader should not measure erythema (redness).")
  induration_mm: {
    type: 'number',
    unit: 'mm',
    words: ['induration'],
    scan: ['induration'],
    patterns: [
      `^${NUM} ?-?${unit('mm')} of induration$`,
      `^induration of ${NUM} ?-?${unit('mm')}$`,
      `^${NUM} ?-?${unit('mm')} induration$`,
      `^${NUM} ?-?${unit('mm')} area of induration$`,
    ],
  },
  // when the reaction was read, in hours after the test was placed
  read_hours: {
    type: 'number',
    unit: 'hours',
    words: ['hours'],
    scan: ['hours later', 'hours after'],
    patterns: [
      `^${NUM} ${unit('hours')} later$`,
      `^${NUM} ${unit('hours')} after placement$`,
      `^${NUM} ${unit('hours')} after administration$`,
      `^after ${NUM} ${unit('hours')}$`,
    ],
  },
  // who the person is, for the cut-off their reaction is read against
  tst_group: {
    type: 'set',
    scan: ['HIV', 'transplant', 'x-ray', 'mycobacteriology'],
    forms: [
      // "with HIV", never bare "HIV": "tested for HIV" is not having it
      { form: 'with HIV', value: 'hiv', backing: { kind: 'literal' } },
      { form: 'organ transplant', value: 'organ_transplant', backing: { kind: 'literal' } },
      { form: 'chest x-ray findings suggestive of previous TB disease', value: 'cxr_prior_tb', backing: { kind: 'literal' } },
      { form: 'mycobacteriology laboratory worker', value: 'myco_lab', backing: { kind: 'literal' } },
    ],
  },
  // the testing being asked about is a first, baseline test
  baseline: {
    type: 'flag',
    forms: [
      { form: 'baseline skin testing', value: true, backing: { kind: 'literal' } },
      { form: 'initial (baseline) skin testing', value: true, backing: { kind: 'literal' } },
    ],
  },
  // the person will be tested again at intervals
  periodic: {
    type: 'flag',
    // "will be retested" is a plan, which is what the rule asks about
    allows: ['condition'],
    forms: [
      { form: 'will be retested periodically', value: true, backing: { kind: 'literal' } },
      { form: 'retested periodically', value: true, backing: { kind: 'literal' } },
    ],
  },
  // what a previous skin test did
  prior_tst_reaction: {
    type: 'set',
    allows: ['past'],
    forms: [
      { form: 'necrosis', value: 'necrosis', backing: { kind: 'literal' } },
      { form: 'blistering', value: 'blistering', backing: { kind: 'literal' } },
      { form: 'anaphylactic shock', value: 'anaphylactic_shock', backing: { kind: 'literal' } },
      { form: 'ulcerations', value: 'ulceration', backing: { kind: 'literal' } },
    ],
  },
});

/// Every lexicon entry that is quoted, with an id: what the review proves and
/// what the owner signs off.
export function quotedEntries(slots = SLOTS) {
  const out = [];
  for (const [slot, def] of Object.entries(slots)) {
    for (const f of def.forms || []) if (f.backing?.kind === 'quoted') out.push({ slot, ...f });
  }
  return out;
}

const escape = s => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
const compiled = new Map();
function patternsOf(slot, def) {
  if (!compiled.has(slot)) {
    compiled.set(slot, (def.patterns || []).map(p => ({ whole: new RegExp(p, 'i'),
      // the same pattern anywhere in a text, for the scan for other mentions
      anywhere: new RegExp(`(?<![A-Za-z0-9.])${p.slice(1, -1)}(?![A-Za-z0-9])`, 'gi') })));
  }
  return compiled.get(slot);
}

/// What a whole span says for a slot: {value, entry} when the span is
/// exactly one of the slot's forms (case aside), else null. A number is read
/// as written, never rounded.
export function readSpan(slot, text, slots = SLOTS) {
  const def = slots[slot];
  if (!def || typeof text !== 'string') return null;
  const t = text.trim();
  if (t !== text || !t) return null;
  if (def.type === 'number') {
    for (const p of patternsOf(slot, def)) {
      const m = p.whole.exec(t);
      if (m) {
        const value = Number(m[1]);
        return Number.isFinite(value) ? { value, entry: { form: p.whole.source, backing: { kind: 'literal' }, words: def.words, unit: def.unit } } : null;
      }
    }
    return null;
  }
  const entry = (def.forms || []).find(f => f.form.toLowerCase() === t.toLowerCase());
  return entry ? { value: entry.value, entry } : null;
}

/// Every place in `stem` that any form of `slot` is written, as [start, end):
/// the checker requires each to be one of the proof's own findings, so a
/// second reading, or a mention in a negated sentence, cannot be left out.
export function mentions(slot, stem, slots = SLOTS) {
  const def = slots[slot];
  const out = [];
  if (!def || typeof stem !== 'string') return out;
  if (def.type === 'number') {
    for (const p of patternsOf(slot, def)) {
      p.anywhere.lastIndex = 0;
      for (const m of stem.matchAll(p.anywhere)) out.push([m.index, m.index + m[0].length]);
    }
  } else {
    for (const f of def.forms || []) {
      const re = new RegExp(`(?<![A-Za-z0-9])${escape(f.form)}(?![A-Za-z0-9])`, 'gi');
      for (const m of stem.matchAll(re)) out.push([m.index, m.index + m[0].length]);
    }
  }
  for (const w of def.scan || []) {
    const re = new RegExp(`(?<![A-Za-z0-9])${escape(w)}(?![A-Za-z0-9])`, 'gi');
    for (const m of stem.matchAll(re)) out.push([m.index, m.index + m[0].length]);
  }
  return out;
}
