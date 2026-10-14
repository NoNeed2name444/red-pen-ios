// Provenance: where each claim of an item comes from, and whether that chain
// can be trusted. The Islamic (§17) and DNA (§16a) research briefs, turned
// from cited principles into the checks the verdict runs:
//
//   isnad      each claim carries its chain: claim -> exact passage -> source
//              -> how it was retrieved -> who checked it; a missing link is
//              named by where it is missing (§17 §1 rows 1, 19; §2 A)
//   rijal      a registry entry for every source: its type, publisher, date,
//              edition, retraction, corrections, funding and grade (§17 §1
//              row 3; §2 B)
//   common     sources that share an origin (one DOI, one PubMed record, one
//   link       trial, one work under two titles) are one witness, not several
//              (§17 §1 row 10, i'tibar; §2 F)
//   tafarrud   a claim only one origin supports is flagged; it may still be
//              Verified ("single source"), but never on an unidentified or
//              weak source, and a dose, diagnosis or treatment (the oath
//              items, P0) only on a guideline, systematic review or label
//              (§17 §1 rows 3, 9, 11; §2 L)
//   shadh      a claim whose support is weaker than a source read against it
//              is held, not adopted (§17 §1 row 8)
//   conflict   a sponsor's source that favours its own product is never
//   of interest accepted alone: it needs an independent, unsponsored source
//              beside it (§17 §1 row 5, the innovator rule; [S67])
//   dabt       the claim reproduces its passage faithfully: numbers, units,
//              frequency, population and negation, read here independently
//              of proof.js's normalizer (§17 §1 row 6; §16a §2 rule 1: a
//              second check different in mechanism), and the Joint
//              Commission's "Do Not Use" dose writing (§16a improvement 2)
//   'ilal      a source with a retraction or an expression of concern
//              supports nothing; an erratum or an update is reported (§17 §1
//              row 9; §2 G)
//
// They are reported as the five conditions of sahih (§17 §1 row 7; §2 D):
// continuity, integrity, accuracy, conformity and no hidden defect. Any
// condition that fails is a hold: the item is never Verified (Check this at
// best). A hold never makes anything better than it was, so the verdict's
// 0-false-Verified property can only be kept, never lost, by this file.
//
// Pure: everything here is worked out from the signals a check already has
// (the proof's quotes, the evidence and its registry entries, the votes), so
// a cached verdict is re-read the same way without a new lookup.

import { familyOf, MIN_VERIFY_VOTERS } from './accuracy-model.js';

// MARK: rijal, the source registry

/// Every type a source can be, and its grade: 5 strongest, 1 weakest. A
/// regulator-approved label and a guideline or systematic review are the
/// sahih grade a dose may rest on (§17 §2 L); a reviewed summary (NLM's
/// MedlinePlus) and a narrative review or a trial are one step down; a
/// source nobody can identify (majhul) or a model's memory are the weakest.
export const GRADES = Object.freeze({
  guideline: 5, 'systematic-review': 5, label: 5,
  'reviewed-summary': 4, review: 4, rct: 4,
  cohort: 3, textbook: 3,
  lecture: 2, 'case-report': 2,
  'model-memory': 1, unknown: 1,
});
/// The grade an oath item's (dose, diagnosis, treatment) lone source needs.
export const OATH_GRADE = 5;
/// The grade any lone source needs (below it, majhul or weak).
export const SINGLE_GRADE = 4;

// a company: a funder whose name says it sells something
const INDUSTRY = /\b(?:inc|ltd|llc|plc|gmbh|ag|s\.?a|corp(?:oration)?|co\.?\s*kg|pharma\w*|laborator(?:y|ies)|therapeutics|biotech\w*|biosciences|pfizer|novartis|roche|merck|msd|sanofi|astra\s?zeneca|glaxo\w*|gsk|bayer|abbvie|lilly|boehringer|takeda|novo nordisk|janssen|johnson\s*&\s*johnson|bristol[- ]myers|amgen|gilead|biogen|teva|servier|viatris|mylan|sandoz)\b/i;

const PUB_TYPES = [
  [/practice guideline|^guideline$|consensus development/i, 'guideline'],
  [/systematic review|meta-analysis/i, 'systematic-review'],
  [/randomi[sz]ed controlled trial|clinical trial, phase iii/i, 'rct'],
  [/case reports?/i, 'case-report'],
  [/observational study|cohort|comparative study/i, 'cohort'],
  [/review/i, 'review'],
];

/// The type of a Europe PMC record, from its publication types, strongest first.
export function typeOfPub(pubTypes) {
  const types = (Array.isArray(pubTypes) ? pubTypes : []).map(String);
  for (const [pattern, type] of PUB_TYPES) if (types.some(t => pattern.test(t))) return type;
  return 'unknown';
}

const lower = s => String(s || '').toLowerCase();
/// Trial registrations a text names (ClinicalTrials.gov, ISRCTN, EudraCT):
/// two reports of one trial are one witness.
export const trialIds = text => [...new Set((String(text || '').match(/\b(?:NCT\d{8}|ISRCTN\d{8}|\d{4}-\d{6}-\d{2})\b/gi) || []).map(t => t.toUpperCase()))];

/// One source's registry entry (rijal): what it is, who published it and
/// when, whether it was retracted or corrected, who paid for it, its grade,
/// and the keys its origin is known by (for the common link). `e` is an
/// evidence entry (evidence.js) with its `meta` when the lookup gave one; a
/// source with none is registered as far as its name allows.
export function registryEntry(e) {
  if (!e || typeof e !== 'object') return null;
  const m = e.meta && typeof e.meta === 'object' ? e.meta : {};
  const source = String(e.source || '');
  let type = 'unknown', publisher = m.publisher || null, sponsors = [];
  if (source === 'openFDA label') {
    type = 'label';
    publisher = m.manufacturer || publisher;
    // a label is its maker's own document, approved by the regulator: the
    // maker is its sponsor, named or not
    sponsors = [m.manufacturer || 'the manufacturer'];
  } else if (source === 'MedlinePlus') {
    type = 'reviewed-summary';
    publisher = publisher || 'U.S. National Library of Medicine';
  } else if (source === 'Europe PMC') {
    type = typeOfPub(m.pubTypes);
  } else if (source === 'lecture') {
    type = 'lecture';
  }
  const funders = (Array.isArray(m.funders) ? m.funders : []).map(String).filter(Boolean);
  for (const f of funders) if (INDUSTRY.test(f) && !sponsors.includes(f)) sponsors.push(f);
  const corrections = (Array.isArray(m.corrections) ? m.corrections : []).map(String).filter(Boolean);
  const retracted = (Array.isArray(m.pubTypes) && m.pubTypes.some(t => /retract/i.test(String(t))))
    || corrections.some(c => /retraction in|expression of concern/i.test(c))
    ? true : source === 'Europe PMC' && Array.isArray(m.pubTypes) ? false : null;
  const origin = [];
  if (m.doi) origin.push(`doi:${lower(m.doi)}`);
  if (m.pmid) origin.push(`pmid:${m.pmid}`);
  for (const t of Array.isArray(m.trials) ? m.trials : []) origin.push(`trial:${String(t).toUpperCase()}`);
  if (m.setId) origin.push(`setid:${m.setId}`);
  if (m.work) origin.push(m.work);
  if (e.url) origin.push(`url:${e.url}`);
  return {
    id: e.id || null, url: e.url || null, source, title: String(e.title || '').slice(0, 300), type,
    grade: GRADES[type] || 1, publisher, date: m.date || null, edition: m.edition || null,
    retracted, corrections, funders, sponsors, origin: [...new Set(origin)],
  };
}

/// Registry entries for a list of sources, one per address.
export function registryOf(entries) {
  const out = [];
  const urls = new Set();
  for (const e of Array.isArray(entries) ? entries : []) {
    const r = registryEntry(e);
    if (!r || (r.url && urls.has(r.url))) continue;
    if (r.url) urls.add(r.url);
    out.push(r);
  }
  return out;
}

// MARK: the common link

/// Sources grouped by origin: two that share any origin key (a DOI, a PubMed
/// id, a trial, one work's title, an address) are one witness, and so is any
/// chain of them (A shares with B, B with C). Each group is a list of
/// registry entries; the number of groups is the number of independent
/// witnesses.
export function originGroups(registry) {
  const list = (Array.isArray(registry) ? registry : []).filter(Boolean);
  const parent = list.map((_, i) => i);
  const find = i => (parent[i] === i ? i : (parent[i] = find(parent[i])));
  const owner = new Map();
  list.forEach((r, i) => {
    for (const key of r.origin || []) {
      if (owner.has(key)) parent[find(i)] = find(owner.get(key));
      else owner.set(key, i);
    }
  });
  const groups = new Map();
  list.forEach((r, i) => {
    const root = find(i);
    if (!groups.has(root)) groups.set(root, []);
    groups.get(root).push(r);
  });
  return [...groups.values()];
}

// MARK: dabt, a claim copied faithfully

const NUMBER_WORDS = { one: 1, two: 2, three: 3, four: 4, five: 5, six: 6, seven: 7, eight: 8, nine: 9, ten: 10, eleven: 11, twelve: 12 };
// a unit and what one of it is in its base: mass in mg, volume in ml, time in hours
const UNITS = [
  [/^(?:mg|milligrams?)$/, 'mg', 1], [/^(?:mcg|µg|μg|ug|micrograms?)$/, 'mg', 0.001], [/^(?:g|grams?)$/, 'mg', 1000],
  [/^(?:kg|kilograms?)$/, 'kg', 1], [/^(?:ml|millilit(?:re|er)s?)$/, 'ml', 1], [/^(?:l|lit(?:re|er)s?)$/, 'ml', 1000],
  [/^(?:mmol|millimoles?)$/, 'mmol', 1], [/^(?:meq)$/, 'meq', 1], [/^(?:mmhg)$/, 'mmhg', 1],
  [/^(?:units?|iu)$/, 'unit', 1], [/^(?:%|percent|per\s?cent)$/, 'percent', 1],
  [/^(?:h|hrs?|hours?)$/, 'h', 1], [/^(?:min|minutes?)$/, 'h', 1 / 60], [/^(?:days?)$/, 'h', 24], [/^(?:weeks?)$/, 'h', 168],
  [/^(?:years?)$/, 'year', 1], [/^(?:months?)$/, 'year', 1 / 12],
];
const QUANTITY = /(?<![\w.])(\d+(?:,\d{3})*(?:\.\d+)?|\.\d+|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve)\s*(%|mg|mcg|µg|μg|ug|g|kg|ml|l|mmol|meq|mmhg|units?|iu|h|hrs?|hours?|min|minutes?|days?|weeks?|months?|years?|milligrams?|micrograms?|grams?|kilograms?|millilit(?:re|er)s?|lit(?:re|er)s?|millimoles?|percent|per\s?cent)?(?![\w])/gi;

/// Every number of a text, each with its unit in base terms when it has one:
/// "500 mg" and "0.5 g" are both "500 mg". A number with no unit stays bare.
export function quantitiesOf(text) {
  const out = [];
  for (const m of String(text || '').matchAll(QUANTITY)) {
    const raw = m[1].toLowerCase().replace(/,/g, '');
    const value = raw in NUMBER_WORDS ? NUMBER_WORDS[raw] : Number(raw);
    if (!Number.isFinite(value)) continue;
    const unit = (m[2] || '').toLowerCase();
    // a number word with no unit ("one of the") is a word, not a quantity
    if (!unit && raw in NUMBER_WORDS) continue;
    const u = unit && UNITS.find(([p]) => p.test(unit));
    out.push(u ? `${+(value * u[2]).toPrecision(9)} ${u[1]}` : `${+value.toPrecision(9)}`);
  }
  return out;
}

const POPULATIONS = [
  ['children', /\b(?:child(?:ren)?|paediatric|pediatric|infants?|neonates?|newborns?|adolescents?|kids?)\b/i],
  ['adults', /\badults?\b/i],
  ['older adults', /\b(?:elderly|older (?:adults|patients|people)|geriatric)\b/i],
  ['pregnancy', /\b(?:pregnan(?:t|cy)|lactat\w*|breast-?feeding)\b/i],
  ['renal', /\b(?:renal|kidney)\b/i],
  ['hepatic', /\b(?:hepatic|liver)\b/i],
  ['women', /\b(?:women|female)\b/i],
  ['men', /\b(?:men|male)\b/i],
];
export const populationsOf = text => POPULATIONS.filter(([, p]) => p.test(String(text || ''))).map(([name]) => name);

const NEGATORS = /\b(?:not|no|never|none|neither|nor|without|cannot|avoid|contraindicated)\b|n['’]t\b/gi;
export const negationsOf = text => (String(text || '').match(NEGATORS) || []).length;

const FREQUENCY = [
  [/\b(?:once (?:a |per )?day|once daily|daily|qd|od)\b/i, 1], [/\b(?:twice (?:a |per )?day|twice daily|bid|bd|b\.i\.d\.)\b/i, 2],
  [/\b(?:three times (?:a |per )?day|three times daily|tid|tds|t\.i\.d\.)\b/i, 3], [/\b(?:four times (?:a |per )?day|four times daily|qid|qds|q\.i\.d\.)\b/i, 4],
  [/\b(?:once (?:a |per )?week|weekly)\b/i, 1 / 7],
];
export function frequenciesOf(text) {
  const t = String(text || '');
  return FREQUENCY.filter(([p]) => p.test(t)).map(([, n]) => n);
}

// the Joint Commission's "Do Not Use" list [§16a S69]: a trailing zero
// ("1.0 mg" read as 10 mg), a naked decimal (".5 mg" read as 5 mg), "U" and
// "IU" for units, and QD / QOD
const HAZARDS = [
  ['trailing zero', /(?<![\d.])\d+\.0+\s?(?:mg|mcg|µg|μg|g|ml|units?)\b/i],
  ['naked decimal', /(?<![\d\w])\.\d+\s?(?:mg|mcg|µg|μg|g|ml|units?)\b/i],
  ['"U" for units', /\b\d+(?:\.\d+)?\s?U\b(?!\/)/],
  ['"IU" for units', /\b\d+(?:\.\d+)?\s?IU\b/],
  ['"QD" or "QOD"', /\bQO?D\b/],
];
export const hazardsOf = text => HAZARDS.filter(([, p]) => p.test(String(text || ''))).map(([name]) => name);

const sorted = list => [...list].sort();
const sameBag = (a, b) => JSON.stringify(sorted(a)) === JSON.stringify(sorted(b));

/// What a claim did not copy faithfully from its passage: [{what, detail}],
/// empty when it reproduces it. The claim and the passage must give the same
/// numbers with the same units (both ways), the same dosing frequency, the
/// same populations and the same negation; and the claim must not write a
/// dose in a way the Joint Commission bans.
export function dabt(claim, passage) {
  const out = [];
  const cq = quantitiesOf(claim), pq = quantitiesOf(passage);
  const withUnit = q => q.filter(x => x.includes(' '));
  if (!sameBag(withUnit(cq), withUnit(pq))) out.push({ what: 'number', detail: `${withUnit(cq).join(', ') || 'none'} against ${withUnit(pq).join(', ') || 'none'}` });
  else {
    // bare numbers the claim gives must be in the passage
    const bare = new Set(pq.filter(x => !x.includes(' ')));
    const missing = cq.filter(x => !x.includes(' ') && !bare.has(x));
    if (missing.length) out.push({ what: 'number', detail: `${missing.join(', ')} not in the passage` });
  }
  if (!sameBag(frequenciesOf(claim), frequenciesOf(passage))) out.push({ what: 'frequency', detail: 'another dosing frequency' });
  const cp = populationsOf(claim), pp = populationsOf(passage);
  if (!sameBag(cp, pp)) out.push({ what: 'population', detail: `${cp.join(', ') || 'anyone'} against ${pp.join(', ') || 'anyone'}` });
  if ((negationsOf(claim) % 2) !== (negationsOf(passage) % 2)) out.push({ what: 'negation', detail: 'one says not, the other does not' });
  for (const h of hazardsOf(claim)) out.push({ what: 'hazard', detail: h });
  return out;
}

// MARK: conflict of interest

// a claim in a product's favour: it works, it is better, it is the one to use
const FAVOURS = /\b(?:more effective|most effective|superior|better than|safer than|preferred|of choice|first[- ]line|recommended|reduces? (?:the )?(?:risk|mortality|death)|improves? (?:survival|outcomes?)|well tolerated|effective (?:in|for))\b/i;
export const favours = text => FAVOURS.test(String(text || ''));

/// Whether a source's support for `claim` is its sponsor speaking for its
/// own product: the source has a sponsor (an industry funder, or a label's
/// maker), and the claim favours a product the source is about or names.
export function selfInterested(claim, entry) {
  if (!entry || !entry.sponsors?.length || !favours(claim)) return false;
  if (entry.type === 'label') return true;
  // a funded study: its claim in a drug's favour
  return /\b[a-z]{3,}(?:olol|pril|sartan|statin|dipine|mab|cillin|mycin|floxacin|azole|prazole|tidine|parin|gliptin|gliflozin|glutide|triptan|setron|lukast|olone|asone|tinib|vir|xaban|gatran)\b/i.test(String(claim));
}

// MARK: isnad, a chain for each claim

/// How a passage reached the check (§17 §1 row 19, tahammul): quoted from
/// the source's own text (sama', the strongest), summarized in a record the
/// checkers were shown (ijaza), or a checker's memory (wijada, the weakest).
export const RETRIEVAL = Object.freeze({ quoted: 3, summary: 2, memory: 1 });

/// Why a claim has no connected chain, by where the link is missing (§17 §1
/// row 1): no source at all (mu'allaq), a source read that does not contain
/// it (munqati'), or an item that cannot be read into claims a source could
/// state (unprovable). proof.js's reasons, sorted.
export function gapOf(why) {
  if (!why) return null;
  if (why === 'no-source') return 'muallaq';
  if (why === 'unproven' || why === 'distractor') return 'munqati';
  if (['lookup', 'timeout', 'error', 'budget'].includes(why)) return 'unread';
  return 'unprovable';
}

/// The families that checked an item and passed it: for a question, those
/// that solved it blind and reached its key; else those that judged it with
/// no error that could mislead.
export function checkersOf(item, votes) {
  const read = (Array.isArray(votes) ? votes : []).filter(v => v && Number.isFinite(v.risk));
  const key = item?.kind === 'mcq' && Number.isInteger(item.key) && item.key >= 0 ? String.fromCharCode(65 + item.key) : null;
  const passing = key ? read.filter(v => v.blind && v.answer === key) : read.filter(v => v.risk < 3);
  return [...new Set(passing.map(v => familyOf(v.model)))];
}

/// Each claim's chain: the claim, the passage that states it, its source's
/// registry entry, how it was retrieved and who checked it, with `gap` naming
/// a missing link. Proven claims are quoted; literature a checker cited as
/// supporting the item is a summary chain for the item as a whole; a checker
/// that supported it citing nothing is memory.
export function chainsFor(item, signals, registry) {
  const byUrl = new Map(registry.filter(r => r.url).map(r => [r.url, r]));
  const byId = new Map(registry.filter(r => r.id).map(r => [r.id, r]));
  const checkers = checkersOf(item, signals?.votes);
  const proof = signals?.proof;
  const chains = [];
  for (const q of Array.isArray(proof?.quotes) ? proof.quotes : []) {
    const source = byUrl.get(q.url) || registryEntry({ source: q.source, title: q.title, url: q.url });
    chains.push({ claim: q.claim, passage: q.quote, section: q.section || null, source, retrieval: 'quoted', checkers, gap: null });
  }
  const gap = proof && typeof proof === 'object' ? gapOf(proof.why) || (proof.claims > (proof.quotes?.length || 0) ? 'munqati' : null) : 'muallaq';
  if (gap) chains.push({ claim: null, passage: null, source: null, retrieval: null, checkers, gap });
  const cited = new Set();
  let memory = false;
  for (const v of Array.isArray(signals?.votes) ? signals.votes : []) {
    if (!v || v.evidence !== 'supports') continue;
    const ids = (Array.isArray(v.cites) ? v.cites : []).filter(id => byId.has(id));
    if (!ids.length) memory = true;
    for (const id of ids) cited.add(id);
  }
  for (const id of cited) chains.push({ claim: null, passage: null, source: byId.get(id), retrieval: 'summary', checkers, gap: null });
  if (memory && !chains.some(c => c.retrieval)) chains.push({ claim: null, passage: null, source: null, retrieval: 'memory', checkers, gap: null });
  return chains;
}

// MARK: the five conditions

/// Everything provenance says about one checked item: its registry, its
/// chains, its flags, the five conditions, the holds that keep it from
/// Verified, and its tier when nothing holds it ('strong': two independent
/// witnesses of good grade; 'single': one). `oath`: the item gives a dose, a
/// diagnosis or a treatment (oath.js). Null for an item no check has read.
export function provenance(item, signals, { oath = false } = {}) {
  if (!signals || typeof signals !== 'object') return null;
  const stored = Array.isArray(signals.sources) ? signals.sources.filter(r => r && typeof r === 'object' && Array.isArray(r.origin)) : [];
  // older checks kept no registry: their evidence and quotes, as far as
  // their names allow
  const known = new Set(stored.map(r => r.url));
  const extra = [
    ...(Array.isArray(signals.evidence) ? signals.evidence : []),
    ...((signals.proof?.quotes || []).map(q => ({ source: q.source, title: q.title, url: q.url }))),
  ].filter(e => e && !known.has(e.url));
  const registry = [...stored, ...registryOf(extra)];
  // an id from the evidence ([S1]) given to a stored entry that has none
  for (const e of Array.isArray(signals.evidence) ? signals.evidence : []) {
    const r = registry.find(x => x.url === e.url);
    if (r && !r.id && e.id) r.id = e.id;
  }
  const chains = chainsFor(item, signals, registry);
  const flags = [];
  const hold = (code, claim, detail) => flags.push({ code, claim: claim || '', detail, hold: true });
  const note = (code, claim, detail) => flags.push({ code, claim: claim || '', detail, hold: false });
  const supporting = chains.filter(c => c.source);
  const quoted = chains.filter(c => c.retrieval === 'quoted');

  // integrity: no retracted source, no source of concern; no sponsor alone
  for (const c of supporting) {
    if (c.source.retracted) hold('retracted', c.claim, `${c.source.title || c.source.url} was retracted or is under an expression of concern.`);
    else if (c.source.corrections?.some(x => /erratum|update|corrected/i.test(x))) note('revised', c.claim, `${c.source.title || c.source.url} has a later correction or update.`);
  }
  const groups = originGroups(supporting.map(c => c.source));
  const groupOf = entry => groups.findIndex(g => g.includes(entry));
  for (const c of quoted) {
    if (!selfInterested(c.claim, c.source)) continue;
    const mine = groupOf(c.source);
    const independent = supporting.some(o => groupOf(o.source) !== mine && !o.source.sponsors?.length && o.source.grade >= SINGLE_GRADE);
    if (!independent) hold('conflict', c.claim, `Only its sponsor's own source (${c.source.sponsors.join(', ')}) says this in its favour.`);
  }

  // accuracy (dabt): every quoted claim copies its passage faithfully
  for (const c of quoted) {
    for (const d of dabt(c.claim, c.passage)) hold('dabt', c.claim, `${d.what}: ${d.detail}`);
  }

  // conformity: no source of higher grade read against the item (shadh); a
  // weaker one against stronger support is reported (munkar), never let
  // drop a concern
  const against = new Set();
  for (const v of Array.isArray(signals.votes) ? signals.votes : []) {
    if (v?.evidence === 'contradicts') for (const id of Array.isArray(v.cites) ? v.cites : []) against.add(id);
  }
  const contra = registry.filter(r => r.id && against.has(r.id) && !supporting.some(c => c.source === r));
  const best = list => Math.max(0, ...list.map(r => r.grade || 0));
  const support = best(supporting.map(c => c.source));
  if (contra.length && best(contra) > support) hold('shadh', '', `Its support (grade ${support}) is weaker than a source read against it (grade ${best(contra)}).`);
  else if (contra.length) note('munkar', '', 'A weaker source was read against it.');

  // no hidden defect: one origin only (tafarrud), and then it must be known
  // and strong enough; an oath item's lone source must be of the top grade
  const witnesses = groups.length;
  const top = best(groups.flat());
  if (witnesses === 1 && quoted.length) {
    const need = oath ? OATH_GRADE : SINGLE_GRADE;
    if (top < need) hold('tafarrud', '', `Only one source supports it, and it is ${top <= 1 ? 'unidentified' : 'not strong enough'} for ${oath ? 'a dose, diagnosis or treatment' : 'a single source'}.`);
    else note('tafarrud', '', 'Only one independent source supports it.');
  }
  // continuity: a connected chain for every claim, checked by enough families
  const gaps = chains.filter(c => c.gap).map(c => c.gap);
  const families = chains[0]?.checkers?.length || 0;

  const holds = flags.filter(f => f.hold);
  const failed = code => holds.some(h => h.code === code);
  const gates = {
    continuity: !gaps.length && quoted.length > 0 && families >= MIN_VERIFY_VOTERS,
    integrity: !failed('retracted') && !failed('conflict'),
    accuracy: !failed('dabt'),
    conformity: !failed('shadh'),
    hiddenDefect: !failed('tafarrud'),
  };
  const strong = groups.filter(g => best(g) >= SINGLE_GRADE).length >= 2;
  return {
    sources: registry, chains, flags, gates, gaps, witnesses,
    tier: holds.length ? null : strong ? 'strong' : witnesses ? 'single' : null,
    holds: holds.map(({ code, claim, detail }) => ({ code, claim, source: detail })),
  };
}

/// What each hold means, in words the student can read.
export const HOLD_REASONS = Object.freeze({
  retracted: 'A source it rests on was retracted or is under an expression of concern.',
  conflict: "Only its sponsor's own source says this in its favour; it needs an independent source.",
  dabt: 'It does not copy its source faithfully (a number, unit, frequency, population or "not" differs, or a dose is written unsafely).',
  shadh: 'A stronger source was read against it.',
  tafarrud: 'Only one source supports it, and that source is not strong enough on its own.',
});
