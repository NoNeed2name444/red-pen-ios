// The claim gate: the Chat-me medical verifier's deterministic guards, run on
// every item before the votes (plan Task 5d step 3; the Task 4 audit's
// section 10, integration step 2).
//
// The guards are ported from Python, Chat-me's medical verifier at 746a7d7
// (branch personal, MIT, the same owner): in
// agents/specialists/verification_agent/, claim_reasoning.py,
// independent_entailment.py and its _base, direction.py, semantic_guard.py,
// consistency.py, entity_normalization.py and temporal_normalization.py.
// The functions keep the Python's names (in camelCase) and its behaviour,
// quirks included - "reduce" read as "reduces", a "%" only seen before a
// letter, "tds" unknown - so the two can be held to the same answers:
// tests/claims.test.mjs checks them against what the Python itself said
// (tests/claim-vectors.json, made by bench/claim-vectors.py) on the
// verifier's 41 shared conformance vectors and on Stethoscore-shaped pairs.
// One known difference: Python's \d also matches other scripts' digits;
// here it is 0-9 only.
//
// Not ported: temporal_guard.py (it needs the evidence's date, which a
// lecture does not have) and the question-side gates (adversarial.py,
// risk.py, rules.py: a student's "should I stop my warfarin?" is not a
// study item).
//
// What the gate does with them (claimGate): it compares what an item says
// with its own lecture, sentence by sentence. Where the item restates one of
// its lecture's sentences - nearly the same words - but
//   - flips its negation ("negation"),
//   - gives a different dose or unit ("dose"), or a different frequency
//     ("frequency"), or a different percentage ("percentage"),
//   - or turns it around: the same words but for one that goes the other
//     way, higher for lower, rare for common ("direction"; after the
//     direction axis of Chat-me's evidence model, though not a port of it:
//     see turnedAround()),
// that is a hard finding: the item contradicts what it was written from, and
// it is never Verified - it stays Check this (the lecture may be the one
// that is wrong, which is for the votes and the student to settle). What
// else the guards notice about such a restated sentence - a wider scope, a
// population or a condition the lecture does not give, a cause read from an
// association, another drug or outcome in one place, a way (higher, rarer)
// the lecture's words do not give or turn - is a soft finding:
// reported beside the verdict and changing nothing, until labelled
// Stethoscore items show how far it can be trusted.
// Sentences that are not restatements are left to the votes: a paraphrase is
// not a contradiction.

// MARK: Python's regular expressions in JavaScript

// Python's \b and \w know every script's letters and digits, JavaScript's
// only ASCII's: py() gives a pattern Python's meaning of them.
const WORD = '[\\p{L}\\p{N}_]';
const BOUNDARY = `(?:(?<=${WORD})(?!${WORD})|(?<!${WORD})(?=${WORD}))`;
// Unicode \b and \w cost V8 about 2 ms each to compile, on first use, in
// every fresh isolate - some 100 ms for the gate's patterns, ten times the
// free plan's CPU for a request. Where a text has no letter or digit outside
// ASCII (and no astral character) the ASCII meanings are the same as the
// Unicode ones, and cost nothing to compile; so each pattern is kept both
// ways, and the Unicode one is only built for a text that needs it.
const UNICODE_WORDY = /[^\x00-\x7f\P{L}]|[^\x00-\x7f\P{N}]|[\u{10000}-\u{10ffff}]/u;
const asciiWords = text => !/[^\x00-\x7f]/.test(text) || !UNICODE_WORDY.test(text);
class PyRegExp extends RegExp {
  constructor(source, flags = '') {
    // matchAll and split make copies through this constructor, with the copy's flags
    const plain = source instanceof PyRegExp ? source.plain.source : String(source);
    const bare = flags.replace('u', '');
    super(plain, bare);
    this.plain = new RegExp(plain, bare);
    this.full = null;
    this.bare = bare;
  }
  exec(text) {
    const s = String(text);
    const regex = asciiWords(s) ? this.plain
      : (this.full ||= new RegExp(this.plain.source.replaceAll('\\b', BOUNDARY).replaceAll('\\w', WORD), `${this.bare}u`));
    regex.lastIndex = this.lastIndex;
    const found = regex.exec(s);
    this.lastIndex = regex.lastIndex;
    return found;
  }
}
const py = (source, flags = '') => new PyRegExp(source, flags);
const r = String.raw;

// str.split()'s whitespace, and " ".join(text.split())
const PY_SPACE = /[\t\n\v\f\r \x1c-\x1f\x85\xa0\u1680\u2000-\u200a\u2028\u2029\u202f\u205f\u3000]+/u;
const squash = text => String(text).split(PY_SPACE).filter(Boolean).join(' ');
/// [...text.matchAll(regex)] for a global regex, without the copy of the
/// regex matchAll makes each time.
const allOf = (text, regex) => {
  const s = String(text), out = [];
  regex.lastIndex = 0;
  for (let m = regex.exec(s); m; m = regex.exec(s)) {
    out.push(m);
    if (!m[0]) regex.lastIndex += s.codePointAt(regex.lastIndex) > 0xffff ? 2 : 1;
  }
  return out;
};
/// re.sub(regex, replace, text) for a global regex, `replace` a function of
/// each match.
const sub = (text, regex, replace) => {
  const s = String(text);
  let out = '', last = 0;
  for (const m of allOf(s, regex)) {
    out += s.slice(last, m.index) + replace(m);
    last = m.index + m[0].length;
  }
  return out + s.slice(last);
};
const unique = list => [...new Set(list)];
const sorted = list => [...list].sort();
const subset = (a, b) => [...a].every(x => b.has(x));
const meets = (a, b) => [...a].some(w => b.has(w));
/// round(x, 9)
const round9 = x => Number(x.toFixed(9));
const ASCII_TOKEN = /[a-z0-9'-]+/g;

// While the gate runs, each text's facts are worked out once: the functions
// marked remembered() are pure, and the gate asks about the same sentences
// over and over (a question's explanation against every sentence of its
// lecture). Outside the gate they work as they are.
let memo = null;
const remembered = (name, fn) => text => {
  if (!memo) return fn(text);
  let known = memo.get(name);
  if (!known) memo.set(name, known = new Map());
  if (!known.has(text)) known.set(text, fn(text));
  return known.get(text);
};

// MARK: entity_normalization.py

export const DEFAULT_ALIASES = { acetaminophen: 'acetaminophen', paracetamol: 'acetaminophen', ibuprofen: 'ibuprofen' };

export function entitiesEquivalent(left, right, aliases = DEFAULT_ALIASES) {
  const canonical = name => { const key = squash(String(name).toLowerCase()); return Object.hasOwn(aliases, key) ? aliases[key] : undefined; };
  const a = canonical(left), b = canonical(right);
  return a !== undefined && b !== undefined && a === b;
}

// MARK: temporal_normalization.py

const DATE = py(r`\b\d{4}(?:-|/)\d{2}(?:-|/)\d{2}\b`, 'g');

/// Explicit yyyy-mm-dd and yyyy/mm/dd dates that exist, sorted, as ISO text.
export const extractExplicitDates = remembered('dates', text => {
  const out = new Set();
  for (const m of allOf(text, DATE)) {
    const parts = m[0].match(/^(\d{4})-(\d{2})-(\d{2})$/) || m[0].match(/^(\d{4})\/(\d{2})\/(\d{2})$/);
    if (!parts) continue;
    const [y, mo, d] = parts.slice(1).map(Number);
    const leap = (y % 4 === 0 && y % 100 !== 0) || y % 400 === 0;
    const days = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][mo - 1];
    if (y >= 1 && mo >= 1 && mo <= 12 && d >= 1 && d <= days) out.add(`${parts[1]}-${parts[2]}-${parts[3]}`);
  }
  return sorted(out);
});

// MARK: claim_reasoning.py

export const RELATION_PHRASES = {
  causal: ['cause', 'causes', 'caused', 'lead to', 'leads to', 'result in', 'results in', 'prevent', 'prevents'],
  risk_increase: ['increase', 'increases', 'increased', 'raises', 'elevates'],
  risk_decrease: ['reduce', 'reduces', 'reduced', 'lowers', 'decrease', 'decreases'],
  association: ['associated with', 'correlated with', 'linked to', 'association between'],
  effectiveness: ['effective', 'efficacy', 'works'],
  contraindication: ['contraindicated', 'contraindication', 'should not use', 'do not use', 'avoid'],
  interaction: ['interacts with', 'interaction', 'interactions', 'do not combine', 'should not be combined', 'concomitant use'],
};

const CLAIM_NEGATION = py(r`\b(no|not|never|without|does not|doesn't|cannot|can't)\b`, 'i');

const TEMPORAL_PATTERNS = [
  ['past', py(r`\b(previously|previous|prior|history of|in the past|was|were)\b`, 'i')],
  ['current', py(r`\b(currently|at present|now|is taking|are taking|currently taking)\b`, 'i')],
  ['future', py(r`\b(will|planned|plan to|expected to|intends to|future)\b`, 'i')],
  ['before_event', py(r`\b(before|prior to)\b`, 'i')],
  ['after_event', py(r`\b(after|following)\b`, 'i')],
  ['duration', py(r`\b(?:for|within)\s+\d+(?:\.\d+)?\s*(?:hours?|days?|weeks?|months?|years?)\b`, 'i')],
];

const ANCHOR_STOPWORDS = new Set([
  'a', 'an', 'the', 'and', 'or', 'but', 'for', 'with', 'in', 'on', 'to', 'of', 'is', 'are', 'was', 'were',
  'that', 'this', 'these', 'those', 'patients', 'patient', 'all', 'selected', 'every', 'everyone', 'regardless', 'only',
  'exclusively', 'previously', 'previous', 'prior', 'currently', 'current', 'now', 'at', 'present', 'will', 'planned', 'plan',
  'expected', 'future', 'no', 'not', 'never', 'without', 'does', "doesn't", 'cannot', "can't", 'has', 'have', 'had',
]);

/// The (at most two) substantive words just before or after the item's
/// first relation phrase: who does it, and to what.
function anchorTokens(text, relation, before) {
  if (relation === 'unclassified' || relation === 'mixed') return [];
  const lower = text.toLowerCase();
  const matches = (RELATION_PHRASES[relation] || []).map(p => [lower.indexOf(p), p]).filter(([at]) => at >= 0);
  matches.sort((a, b) => a[0] - b[0] || b[1].length - a[1].length);
  if (!matches.length) return [];
  const [start, phrase] = matches[0];
  const fragment = before ? lower.slice(0, start) : lower.slice(start + phrase.length);
  const raw = fragment.match(ASCII_TOKEN) || [];
  const candidates = before ? [...raw].reverse() : raw;
  const selected = [];
  let seenSubstantive = false;
  for (const token of candidates) {
    if (ANCHOR_STOPWORDS.has(token) && token.length !== 1) {
      if (seenSubstantive) break;
      continue;
    }
    selected.push(token);
    seenSubstantive = true;
    if (selected.length >= 2) break;
  }
  if (!selected.length) return [];
  if (before) selected.reverse();
  return [selected.join(' ')];
}

export const relationTypes = remembered('relations', text => {
  const lower = String(text).toLowerCase();
  return Object.entries(RELATION_PHRASES).filter(([, phrases]) => phrases.some(p => lower.includes(p))).map(([relation]) => relation);
});

export const polarity = text => (CLAIM_NEGATION.test(text) ? 'negative' : 'positive');

export const temporalSignature = remembered('temporal', text => TEMPORAL_PATTERNS.filter(([, pattern]) => pattern.test(text)).map(([label]) => label));

export function safetyRelation(text) {
  const relations = new Set(relationTypes(text));
  if (relations.has('interaction')) return 'interaction';
  if (relations.has('contraindication')) return 'contraindication';
  return null;
}

/** @typedef {{ text: string, relation: string, polarity: 'positive'|'negative', temporal: string[], safety: string|null, subject: string[], object: string[] }} AtomicClaim */

/// A claim as its atomic statements: split at sentence ends, and at "and",
/// "but" or "while" where both sides carry a relation of their own.
/** @returns {AtomicClaim[]} */
export const decomposeClaim = remembered('atoms', text => {
  const normalized = squash(text);
  if (!normalized) return [];
  const strip = s => s.replace(/^[ ,]+|[ ,]+$/g, '');
  const fragments = normalized.split(/[.;!?]+/).map(strip).filter(Boolean);
  const expanded = [];
  for (const fragment of fragments) {
    if (relationTypes(fragment).length <= 1) { expanded.push(fragment); continue; }
    const pieces = fragment.split(/\s+(?:and|but|while)\s+/i);
    if (pieces.length === 1) { expanded.push(fragment); continue; }
    // only where every side has a relation: "increases bleeding and
    // mortality" is one claim, not a relation-less second fragment
    const relationful = pieces.filter(p => relationTypes(p).length > 0).map(strip);
    if (relationful.length === pieces.length) expanded.push(...relationful);
    else expanded.push(fragment);
  }
  return expanded.map(fragment => {
    const relations = relationTypes(fragment);
    const relation = !relations.length ? 'unclassified' : relations.length === 1 ? relations[0] : 'mixed';
    return {
      text: fragment, relation, polarity: polarity(fragment), temporal: temporalSignature(fragment), safety: safetyRelation(fragment),
      subject: anchorTokens(fragment, relation, true), object: anchorTokens(fragment, relation, false),
    };
  });
});

/// [ok, reason]: explicit dates and temporal scope must match.
export function temporalEntailed(claim, evidence) {
  const claimDates = extractExplicitDates(claim.text);
  const evidenceDates = new Set(extractExplicitDates(evidence.text));
  if (claimDates.length) {
    if (!evidenceDates.size) return [false, 'temporal_date_missing'];
    if (!subset(claimDates, evidenceDates)) return [false, 'temporal_date_mismatch'];
  }
  if (!claim.temporal.length) return [true, null];
  if (!evidence.temporal.length) return [false, 'temporal_scope_missing'];
  const a = new Set(claim.temporal), b = new Set(evidence.temporal);
  if (a.size !== b.size || !subset(a, b)) return [false, 'temporal_scope_mismatch'];
  return [true, null];
}

export function safetyRelationEntailed(claim, evidence) {
  if (claim.safety === null) return [true, null];
  if (evidence.safety !== claim.safety) return [false, 'safety_relation_mismatch'];
  if (claim.polarity !== evidence.polarity) return [false, 'safety_polarity_mismatch'];
  return [true, null];
}

function termSetsOverlap(left, right) {
  if (left.some(t => right.includes(t))) return true;
  return left.some(l => right.some(r2 => entitiesEquivalent(l, r2)));
}

export function relationEntailed(claim, evidence) {
  if (claim.subject.length && evidence.subject.length && !termSetsOverlap(claim.subject, evidence.subject)) return [false, 'atomic_subject_mismatch'];
  if (claim.object.length && evidence.object.length && !termSetsOverlap(claim.object, evidence.object)) return [false, 'atomic_object_mismatch'];
  if (claim.relation === 'causal') {
    if (evidence.relation !== 'causal') return [false, 'causal_claim_requires_causal_evidence'];
  } else if (claim.relation === 'interaction') {
    if (evidence.relation !== 'interaction') return [false, 'interaction_claim_requires_interaction_evidence'];
  } else if (claim.relation === 'contraindication') {
    if (evidence.relation !== 'contraindication') return [false, 'contraindication_claim_requires_contraindication_evidence'];
  } else if (claim.relation !== 'mixed' && claim.relation !== 'unclassified') {
    if (evidence.relation !== claim.relation && evidence.relation !== 'mixed') return [false, 'atomic_relation_mismatch'];
  }
  return [true, null];
}

/// A structurally matching atomic statement with the opposite polarity.
export function oppositePolarityEntailed(claim, evidence) {
  const longTokens = text => new Set((text.toLowerCase().match(ASCII_TOKEN) || []).filter(t => t.length >= 4));
  const evidenceAtoms = decomposeClaim(evidence);
  for (const c of decomposeClaim(claim)) {
    const claimTokens = longTokens(c.text);
    if (!claimTokens.size) continue;
    for (const e of evidenceAtoms) {
      const evidenceTokens = longTokens(e.text);
      const overlap = [...claimTokens].filter(t => evidenceTokens.has(t)).length / Math.max(1, claimTokens.size);
      if (overlap < 0.45) continue;
      if (!relationEntailed(c, e)[0]) continue;
      if (!temporalEntailed(c, e)[0]) continue;
      if (c.safety !== e.safety) continue;
      if (c.polarity !== e.polarity) return true;
    }
  }
  return false;
}

// MARK: direction.py

// Which way a statement goes, and whether its evidence goes the same way: one
// atom of a claim against one atom of its evidence, on the two axes the gate's
// turnedAround() reads (below): which way something moves or compares
// (increases, reduces; higher, lower) and how much or how often it is (high,
// low; common, rare). A negated statement says no way here: the negation
// checks own it.

/// A cheap first look: no word that could say which way, nothing to read.
const WAY_HINT = py(r`increas|high|great|more|strong|rais|elevat|above|decreas|reduc|low|less|fewer|weak|below|common|frequent|minimal|negligible|rare|seldom`, 'i');
/// Never the first half of a hyphenated name ("low-dose", "high-density");
/// the second half still says a way ("glucose-lowering").
const way = words => py(r`\b(?:${words})\b(?!-)`, 'i');
const CHANGE = 0, AMOUNT = 1;
const DIRECTION_AXES = [
  [way('increas(?:e|es|ed|ing)|higher|greater|more|stronger|rais(?:e|es|ed|ing)|elevat(?:e|es|ed|ing)|above'),
    way('decreas(?:e|es|ed|ing)|reduc(?:e|es|ed|ing|tion)|lower(?:s|ed|ing)?|less|fewer|weaker|below')],
  [way('high(?:est)?|common(?:ly|est)?|frequent(?:ly)?'),
    way('low(?:est)?|minimal|negligible|rare(?:ly)?|uncommon|infrequent(?:ly)?|seldom')],
];
/// Where those words name a part or a thing, not a way: the lower limb and
/// the lower oesophageal sphincter, the greater trochanter, higher centres,
/// the common bile duct, minimal change disease, "see below".
const NOT_A_WAY = py(r`\b(?:lower\s+(?:limbs?|lobes?|motor|o?esophag\w*|urinary|respiratory|gi|gastrointestinal|abdom\w*|back|quadrants?|segment|uterine|chest|ribs?|half|third|parts?|extremit\w*|legs?|airways?|poles?|borders?|eyelids?|lips?|jaws?|limits?)|greater\s+(?:trochanter|tuberc\w*|tuberos\w*|curvature|omentum|sciatic|saphenous|petrosal|palatine|occipital|splanchnic|auricular|wings?|sac)|higher\s+(?:centres?|centers?|cortical|mental)|common\s+(?:bile|carotid|iliac|peroneal|fibular|femoral|hepatic|cold|variable|pathway)|minimal\s+change|(?:as|see|described|shown|listed|discussed|mentioned|noted|outlined)\s+(?:above|below))\b`, 'gi');
/// A cut-off, not a way: "below 30", "more than 50%". The evidence may write
/// it another way ("< 30"), so a claim's cut-off asks nothing of its words.
const THRESHOLD = py(r`\b(?:(?:more|less|greater|fewer|higher|lower)\s+than|above|below|over|under)\s+(?=\d)`, 'gi');
/// What a comparison is against: "than warfarin", "compared with placebo".
const AGAINST = py(r`\b(?:than|compared (?:with|to)|in comparison (?:with|to)|versus|vs|relative to)\b`, 'i');
const blank = (pattern, text) => sub(text, pattern, m => ' '.repeat(m[0].length));

function readWays(text, cutOffs) {
  if (CLAIM_NEGATION.test(text)) return null;
  if (!WAY_HINT.test(text)) return [null, null];
  let read = blank(NOT_A_WAY, text);
  if (!cutOffs) read = blank(THRESHOLD, read);
  return DIRECTION_AXES.map(([up, down]) => {
    const ups = up.test(read), downs = down.test(read);
    return ups && downs ? 0 : ups ? 1 : downs ? -1 : null;
  });
}
const waysOf = remembered('ways', text => readWays(text, true));
const statedWaysOf = remembered('stated ways', text => readWays(text, false));
/// Each axis's way: 1 up, -1 down, 0 both ways, null no way; null for a
/// negated statement. Without `cutOffs`, a cut-off ("below 30") is no way.
export const directions = (text, cutOffs = true) => (cutOffs ? waysOf : statedWaysOf)(String(text));

/// The words (as tokens()) before what a comparison is against, and after.
function sides(text) {
  const marker = AGAINST.exec(text);
  return marker && [tokens(text.slice(0, marker.index)), tokens(text.slice(marker.index + marker[0].length))];
}

/// "warfarin has a higher risk than DOACs" says what "DOACs have a lower risk
/// than warfarin" says.
function comparisonSwapped(claim, evidence) {
  const claimSides = sides(claim), evidenceSides = sides(evidence);
  if (!claimSides || !evidenceSides) return false;
  const [claimSubject, claimAgainst] = claimSides, [evidenceSubject, evidenceAgainst] = evidenceSides;
  return meets(claimAgainst, evidenceSubject) && meets(evidenceAgainst, claimSubject) && !meets(claimAgainst, evidenceAgainst);
}

/// [ok, reason]: does evidence that otherwise matches the claim go the
/// claim's way? A claim that goes one way is not supported by evidence that
/// goes the other ("a reduced risk" for "an increased risk"), nor by evidence
/// that says no way at all ("a stronger effect" for "interacts with").
export function directionEntailed(claim, evidence) {
  const claimWays = directions(claim), evidenceWays = directions(evidence);
  if (!claimWays || !evidenceWays) return [true, null];
  let change = evidenceWays[CHANGE];
  if (change && comparisonSwapped(claim, evidence)) change = -change;
  const evidenceGoes = [change, evidenceWays[AMOUNT]];
  if (claimWays.some((w, axis) => w && evidenceGoes[axis] && w === -evidenceGoes[axis])) return [false, 'atomic_direction_mismatch'];
  if (directions(claim, false).some(Boolean) && evidenceGoes.every(w => w === null)) return [false, 'atomic_direction_not_entailed'];
  return [true, null];
}

// MARK: independent_entailment_base.py

export const RELATION_CLASSES = {
  causal: ['cause', 'causes', 'caused', 'leads to', 'result in', 'results in', 'prevent', 'prevents'],
  risk_increase: ['increase', 'increases', 'increased', 'raises', 'elevates', 'higher'],
  risk_decrease: ['reduce', 'reduces', 'reduced', 'lowers', 'decrease', 'decreases', 'decreased'],
  association: ['associated with', 'association', 'correlated with', 'linked to'],
  safety: ['safe', 'safely', 'dangerous', 'harmful', 'harm', 'adverse', 'contraindicated', 'contraindication'],
  effectiveness: ['effective', 'effectiveness', 'efficacy', 'works'],
};

export const POPULATION_TERMS = ['adult', 'adults', 'child', 'children', 'pediatric', 'elderly', 'pregnancy', 'pregnant', 'breastfeeding', 'renal', 'kidney', 'hepatic', 'liver'];

export const NEGATION = py(r`\b(no|not|never|without|does not|doesn't|cannot|can't)\b`, 'i');

const DOUBLE_NEGATION_EQUIVALENTS = [['not uncommon', 'common'], ['not unlikely', 'likely'], ['not impossible', 'possible']];

/// The verifier's narrow Spanish and French map, in its order: each
/// replacement applies to what the ones before it left, and to whole words
/// only (Spanish "reduce" leaves English "reduced" as it is, "causa" leaves
/// "causal").
const MULTILINGUAL = [
  ['no aumenta', 'does not increase'], ['ne augmente pas', 'does not increase'], ["n'augmente pas", 'does not increase'],
  ['no causa', 'does not cause'], ['ne cause pas', 'does not cause'], ["n'est pas sûr", 'is not safe'], ['no es seguro', 'is not safe'],
  ['aumenta', 'increases'], ['augmente', 'increases'], ['reduce', 'reduces'], ['réduit', 'reduces'], ['causa', 'causes'],
  ['causado', 'caused'], ['asociado con', 'associated with'], ['associé à', 'associated with'], ['asociado a', 'associated with'],
  ['seguro', 'safe'], ['sûr', 'safe'], ['efectivo', 'effective'], ['efficace', 'effective'], ['pacientes', 'patients'],
  ['patients', 'patients'], ['niños', 'children'], ['enfants', 'children'], ['adultos', 'adults'], ['adultes', 'adults'],
  ['glucosa', 'glucose'], ['glucose', 'glucose'],
].map(([from, to]) => [from, py(r`(?<!\w)${from.replace(/[\\^$.*+?()[\]{}|/]/g, '\\$&')}(?!\w)`, 'g'), to]);

const replaceAll = (text, pairs) => pairs.reduce((t, [from, to]) => t.split(from).join(to), text);

export const normalizeMultilingual = remembered('multilingual', text => MULTILINGUAL.reduce(
  (t, [from, whole, to]) => (t.includes(from) ? sub(t, whole, () => to) : t), String(text).toLowerCase()));
export const normalizeDoubleNegation = remembered('logic', text => replaceAll(normalizeMultilingual(text), DOUBLE_NEGATION_EQUIVALENTS));

/// The words of four letters or more.
export const tokens = remembered('tokens', text => new Set((String(text).toLowerCase().match(ASCII_TOKEN) || []).filter(t => t.length >= 4)));

export const relationClass = remembered('class', text => {
  const lower = normalizeDoubleNegation(text);
  const matches = Object.entries(RELATION_CLASSES).filter(([, words]) => words.some(w => lower.includes(w))).map(([c]) => c);
  return matches.length === 1 ? matches[0] : 'mixed';
});

const NUMBER = py(r`\b\d+(?:\.\d+)?\b`, 'g');
export const numbers = remembered('numbers', text => new Set(allOf(String(text).toLowerCase(), NUMBER).map(m => m[0])));

/// A value in the verifier's base units: mg, ml, percent.
export function normalizeMeasurement(value, unit) {
  const u = unit.toLowerCase();
  const v = Number(value);
  if (u === 'mcg' || u === 'ug') return [v * 0.001, 'mg'];
  if (u === 'g') return [v * 1000.0, 'mg'];
  if (u === 'kg') return [v * 1000000.0, 'mg'];
  if (u === 'l') return [v * 1000.0, 'ml'];
  if (u === '%' || u === 'percent') return [v, 'percent'];
  return [v, u];
}

const MEASURED = py(r`\b(\d+(?:\.\d+)?)\s*(mg|g|mcg|ug|kg|ml|l|mmol|mmhg|%|percent)\b`, 'g');

/// Every measurement, as "value unit" (a set of the verifier's (value, unit)).
export const measurements = remembered('measurements', text => {
  const found = allOf(String(text).toLowerCase(), MEASURED);
  return new Set(found.map(m => { const [v, u] = normalizeMeasurement(m[1], m[2]); return `${round9(v)} ${u}`; }));
});

const FREQUENCIES = [
  [py(r`\b(twice|2\s+times)(?:\s+a)?\s+(?:day|daily)\b|\bbid\b`), 2.0],
  [py(r`\bthree\s+times(?:\s+a)?\s+(?:day|daily)\b|\btid\b`), 3.0],
  [py(r`\bfour\s+times(?:\s+a)?\s+(?:day|daily)\b|\bqid\b`), 4.0],
  [py(r`\bonce(?:\s+a)?\s+(?:day|daily)\b|\bdaily\b|\bqd\b`), 1.0],
];
const EVERY_HOURS = py(r`\bevery\s+(\d+)\s*(?:hours?|h)\b|\bq(\d+)h\b`);
const WEEKLY = py(r`\b(?:once\s+a\s+week|weekly)\b`);
const TWICE_WEEKLY = py(r`\btwice\s+(?:a\s+)?week\b`);

/// Doses a day (1/7 for weekly), or null. `twiceWeekly`: the base module
/// knows "twice a week"; semantic_guard's own copy does not.
function frequencyOf(text, twiceWeekly) {
  const lower = String(text).toLowerCase();
  for (const [pattern, times] of FREQUENCIES) if (pattern.test(lower)) return times;
  const every = lower.match(EVERY_HOURS);
  if (every) {
    const hours = parseInt(every[1] ?? every[2], 10);
    if (hours > 0 && hours <= 24) return 24.0 / hours;
  }
  if (WEEKLY.test(lower)) return 1.0 / 7.0;
  if (twiceWeekly && TWICE_WEEKLY.test(lower)) return 2.0 / 7.0;
  return null;
}
export const frequencyMultiplier = remembered('frequency', text => frequencyOf(text, true));

const PER_VOLUME = py(r`\b\d+(?:\.\d+)?\s*(?:mg|g|mcg|ug)\s*(?:/|per)\s*(?:ml|l)\b`);
const PER_KG = py(r`\b\d+(?:\.\d+)?\s*(?:mg|g|mcg|ug)\s*/\s*kg\b`);
const MASS = py(r`\b(\d+(?:\.\d+)?)\s*(mg|g|mcg|ug)\b`, 'g');
const CONCENTRATION = py(r`\b(\d+(?:\.\d+)?)\s*(mg|g|mcg|ug)\s*(?:/|per)\s*(ml|l)\b`, 'g');
const VOLUME = py(r`\b(\d+(?:\.\d+)?)\s*(ml|l)\b`, 'g');
const WEIGHT_DOSE = py(r`\b(\d+(?:\.\d+)?)\s*(mg|g|mcg|ug)\s*/\s*kg(\s*/\s*day)?\b`, 'g');
const WEIGHT = py(r`\b(\d+(?:\.\d+)?)\s*kg\b`, 'g');

function dailyMassDose(text) {
  const lower = String(text).toLowerCase();
  if (PER_VOLUME.test(lower)) return null;
  if (PER_KG.test(lower)) return null;
  const values = allOf(lower, MASS);
  const multiplier = frequencyMultiplier(text);
  if (values.length !== 1 || multiplier === null) return null;
  const [value, unit] = normalizeMeasurement(values[0][1], values[0][2]);
  if (unit !== 'mg') return null;
  return round9(value * multiplier);
}

function concentrationDailyDose(text) {
  const lower = String(text).toLowerCase();
  const concentration = allOf(lower, CONCENTRATION);
  const volume = allOf(lower, VOLUME);
  const multiplier = frequencyMultiplier(text);
  if (concentration.length !== 1 || volume.length !== 1 || multiplier === null) return null;
  const [mass, massUnit] = normalizeMeasurement(concentration[0][1], concentration[0][2]);
  const [vol, volUnit] = normalizeMeasurement(volume[0][1], volume[0][2]);
  if (massUnit !== 'mg' || volUnit !== 'ml') return null;
  return round9(mass * vol * multiplier);
}

function weightBasedDailyDose(text) {
  const lower = String(text).toLowerCase();
  const dose = allOf(lower, WEIGHT_DOSE);
  const weights = allOf(lower, WEIGHT);
  if (dose.length !== 1 || weights.length !== 1) return null;
  const [value, unit] = normalizeMeasurement(dose[0][1], dose[0][2]);
  const weight = Number(weights[0][1]);
  if (unit !== 'mg') return null;
  const perDay = dose[0][3] ? 1.0 : frequencyMultiplier(text);
  if (perDay === null) return null;
  return round9(value * weight * perDay);
}

/// The total mg a day the text gives - one dose times its frequency, a
/// concentration times a volume, or mg/kg times a weight - or null.
export const dailyDoseEquivalent = remembered('daily', text => {
  for (const calculate of [dailyMassDose, concentrationDailyDose, weightBasedDailyDose]) {
    const value = calculate(text);
    if (value !== null) return value;
  }
  return null;
});

/// Words that only say how much, how often or how a dose is given: a
/// reworded daily dose may change these, never the drug, the patient or
/// anything else (Chat-me a4152d5).
const DOSE_WORDS = new Set([
  'dose', 'doses', 'dosed', 'dosing', 'dosage', 'dosages',
  'total', 'amount', 'divided',
  'milligram', 'milligrams', 'gram', 'grams', 'microgram', 'micrograms',
  'millilitre', 'millilitres', 'milliliter', 'milliliters',
  'litre', 'litres', 'liter', 'liters', 'kilogram', 'kilograms',
  'daily', 'once', 'twice', 'three', 'four', 'times', 'every',
  'hour', 'hours', 'hourly', 'week', 'weekly',
  'take', 'takes', 'taken', 'taking', 'give', 'gives', 'given', 'giving',
  'administer', 'administers', 'administered', 'administering',
  'used', 'uses', 'using',
  'should', 'must', 'will', 'with', 'each', 'that', 'this', 'from', 'into',
]);
const LETTERS = /[a-z]+/g;
const letterWords = text => String(text).toLowerCase().match(LETTERS) || [];

/// Does a daily dose written another way keep the rest of the claim: each
/// of its words of four letters or more, dose words aside, in the evidence.
export function doseRewordingKeepsTerms(claim, evidence) {
  const evidenceWords = new Set(letterWords(evidence));
  return letterWords(claim).every(w => w.length < 4 || DOSE_WORDS.has(w) || evidenceWords.has(w));
}

export const measurementKind = remembered('kind', text => {
  const lower = String(text).toLowerCase();
  if (lower.includes('percentage point')) return 'percentage_points';
  if (lower.includes('%') || lower.includes('percent')) return 'percent';
  if (lower.includes('odds ratio')) return 'odds_ratio';
  if (lower.includes('hazard ratio')) return 'hazard_ratio';
  if (lower.includes('relative risk')) return 'relative_risk';
  if (lower.includes('absolute risk')) return 'absolute_risk';
  return null;
});

export const populations = remembered('populations', text => new Set(POPULATION_TERMS.filter(t => String(text).toLowerCase().includes(t))));

const CONDITION_PATTERNS = [
  r`\bif\s+([^,.;:]+)`, r`\bonly if\s+([^,.;:]+)`, r`\bunless\s+([^,.;:]+)`, r`\bwhen\s+([^,.;:]+)`,
  r`\bprovided that\s+([^,.;:]+)`, r`\bin patients with\s+([^,.;:]+)`, r`\bfor patients with\s+([^,.;:]+)`,
].map(p => py(p, 'g'));

/// The words (four letters or more) of each condition the text sets.
export const conditionSignatures = remembered('conditions', text => {
  const lower = squash(String(text).toLowerCase());
  const out = [];
  for (const pattern of CONDITION_PATTERNS) {
    for (const m of allOf(lower, pattern)) {
      const signature = new Set((m[1].match(ASCII_TOKEN) || []).filter(t => t.length >= 4));
      if (signature.size) out.push(signature);
    }
  }
  return out;
});

export const scopeStrength = remembered('scope', text => {
  const lower = String(text).toLowerCase();
  return {
    universal: ['all patients', 'all people', 'everyone', 'every patient', 'always', 'never', 'regardless of'].some(m => lower.includes(m)),
    exclusive: ['only', 'exclusively', 'only if'].some(m => lower.includes(m)),
  };
});

export function conditionSupported(claim, evidence) {
  const claimConditions = conditionSignatures(claim);
  const evidenceConditions = conditionSignatures(evidence);
  if (!evidenceConditions.length) return [true, null];
  if (!claimConditions.length) return [false, 'conditional_scope_missing'];
  for (const source of evidenceConditions) {
    const best = Math.max(0, ...claimConditions.map(c => [...source].filter(t => c.has(t)).length / Math.max(1, source.size)));
    if (best < 0.70) return [false, 'condition_not_entrailed'];
  }
  return [true, null];
}

/// Does an evidence atom carry a claim atom: most of its words (0.45), and
/// the same relation, timing, safety relation and direction; or the reason
/// it does not.
function atomPairCheck(c, e) {
  const claimTokens = tokens(c.text), evidenceTokens = tokens(e.text);
  const overlap = [...claimTokens].filter(t => evidenceTokens.has(t)).length / Math.max(1, claimTokens.size);
  if (overlap < 0.45) return [false, null];
  const failed = [relationEntailed(c, e), temporalEntailed(c, e), safetyRelationEntailed(c, e)].find(([ok]) => !ok);
  return failed || directionEntailed(c.text, e.text);
}

/// Every atomic claim matched by an evidence atom that shares its words,
/// relation, timing, safety relation and direction; or the first reason one
/// is not.
export function atomicAlignment(claim, evidence) {
  const claimAtoms = decomposeClaim(claim);
  let evidenceAtoms = decomposeClaim(evidence);
  if (!claimAtoms.length) return [true, null];
  if (!evidenceAtoms.length) return [false, 'no_atomic_evidence_claim'];
  evidenceAtoms = evidenceAtoms.filter(a => a.text);
  for (const c of claimAtoms) {
    let matched = false;
    const failures = [];
    for (const e of evidenceAtoms) {
      const [ok, reason] = atomPairCheck(c, e);
      if (ok) { matched = true; break; }
      if (reason) failures.push(reason);
    }
    if (!matched) return [false, failures.length ? failures[0] : 'atomic_claim_not_entailed'];
  }
  return [true, null];
}

/// Words that join or qualify a phrase rather than name a drug, a condition
/// or an outcome ("after", "before", "more", "less" and the like carry
/// meaning).
const FUNCTION_WORDS = new Set([
  'about', 'across', 'along', 'also', 'although', 'among', 'because', 'been',
  'being', 'between', 'could', 'from', 'however', 'into', 'might', 'onto',
  'shall', 'such', 'than', 'their', 'them', 'then', 'there', 'therefore',
  'they', 'though', 'through', 'throughout', 'thus', 'toward', 'towards',
  'upon', 'very', 'what', 'when', 'where', 'whereas', 'whether', 'which',
  'while', 'whom', 'whose', 'would',
]);
const ARTICLES = new Set(['a', 'an', 'the']);
/// Endings cut so another form of the same word still lines up; there is no
/// "-ate" or "-ic" rule, which would make nitrate and nitrite one word.
const STEM_RULES = [
  ['isations', ''], ['izations', ''], ['isation', ''], ['ization', ''],
  ['ising', ''], ['izing', ''], ['ised', ''], ['ized', ''],
  ['ises', ''], ['izes', ''], ['ise', ''], ['ize', ''],
  ['ations', 'at'], ['ation', 'at'], ['ites', ''], ['ite', ''],
  ['isms', ''], ['ism', ''], ['ies', 'y'], ['ied', 'y'], ['ing', ''],
  ['eed', 'eed'], ['ed', ''], ['sses', 'ss'], ['ss', 'ss'], ['us', 'us'],
  ['is', 'is'], ['es', ''], ['s', ''], ['e', ''],
];

function stem(word) {
  const w = (word.endsWith("'s") ? word.slice(0, -2) : word).replaceAll('ae', 'e').replaceAll('oe', 'e');
  const rule = STEM_RULES.find(([suffix]) => w.endsWith(suffix) && w.length - suffix.length >= 3);
  return rule ? w.slice(0, w.length - rule[0].length) + rule[1] : w;
}

const contentWord = word => word.length >= 4 && !ANCHOR_STOPWORDS.has(word) && !FUNCTION_WORDS.has(word)
  && !DOSE_WORDS.has(word) && !/[0-9]/.test(word);

/// The stretches of two word lists left over by their longest common
/// subsequence, as pairs of index ranges; at least one side has words.
function unmatchedRuns(left, right) {
  const table = Array.from({ length: left.length + 1 }, () => new Array(right.length + 1).fill(0));
  for (let i = left.length - 1; i >= 0; i--) {
    for (let j = right.length - 1; j >= 0; j--) {
      table[i][j] = left[i] === right[j] ? table[i + 1][j + 1] + 1 : Math.max(table[i + 1][j], table[i][j + 1]);
    }
  }
  const runs = [];
  let i = 0, j = 0, startI = 0, startJ = 0;
  while (i < left.length && j < right.length) {
    if (left[i] === right[j]) {
      if (startI !== i || startJ !== j) runs.push([[startI, i], [startJ, j]]);
      i++; j++;
      startI = i; startJ = j;
    } else if (table[i + 1][j] >= table[i][j + 1]) i++;
    else j++;
  }
  if (startI !== left.length || startJ !== right.length) runs.push([[startI, left.length], [startJ, right.length]]);
  return runs;
}

/// One or two words on each side, every one a term, none said elsewhere in
/// the other sentence and no pair a known alias (paracetamol, acetaminophen).
function isSwap(claimGap, evidenceGap, claimStems, evidenceStems) {
  if (claimGap.length < 1 || claimGap.length > 2 || evidenceGap.length < 1 || evidenceGap.length > 2) return false;
  if (![...claimGap, ...evidenceGap].every(contentWord)) return false;
  if (claimGap.some(w => evidenceStems.has(stem(w))) || evidenceGap.some(w => claimStems.has(stem(w)))) return false;
  const pairs = [[claimGap.join(' '), evidenceGap.join(' ')], ...claimGap.flatMap(l => evidenceGap.map(r => [l, r]))];
  return !pairs.some(([l, r]) => entitiesEquivalent(l, r));
}

/// A text's words in order, with their stems.
const stemmed = remembered('stems', text => {
  const words = text.toLowerCase().match(ASCII_TOKEN) || [];
  const stems = words.map(stem);
  return { words, stems, set: new Set(stems) };
});

function swapsATerm(claimText, evidenceText) {
  const claim = stemmed(claimText), evidence = stemmed(evidenceText);
  // a swap needs a term on each side that the other does not say; most
  // pairs that get this far have none, and need no alignment
  const unsaid = (side, other) => side.words.some((w, i) => !other.set.has(side.stems[i]) && contentWord(w));
  if (!unsaid(claim, evidence) || !unsaid(evidence, claim)) return false;
  return unmatchedRuns(claim.stems, evidence.stems).some(([[i1, i2], [j1, j2]]) => isSwap(
    claim.words.slice(i1, i2).filter(w => !ARTICLES.has(w)), evidence.words.slice(j1, j2).filter(w => !ARTICLES.has(w)),
    claim.set, evidence.set));
}

/// Does a claim sentence line up with the evidence only by putting another
/// drug, condition or outcome in one place: every evidence atom that carries
/// one of its atoms differs from it by a swapped term (Chat-me 746a7d7).
export function termSubstituted(claim, evidence) {
  const evidenceAtoms = decomposeClaim(evidence).filter(a => a.text);
  return decomposeClaim(claim).some(c => {
    const carriers = evidenceAtoms.filter(e => atomPairCheck(c, e)[0]);
    return carriers.length > 0 && carriers.every(e => swapsATerm(c.text, e.text));
  });
}

// MARK: independent_entailment.py

/** @typedef {{ label: 'SUPPORTS'|'CONTRADICTS'|'UNKNOWN', reasons: string[] }} Entailment */

/// Does the evidence state the claim? SUPPORTS only when every structured
/// check passes; CONTRADICTS when it does but the claim is negated and the
/// evidence is not; otherwise UNKNOWN with the first check that failed.
/** @returns {Entailment} */
export function verify(claim, evidence) {
  const unknown = reason => ({ label: 'UNKNOWN', reasons: [reason] });
  const claimLogic = normalizeDoubleNegation(claim);
  const evidenceLogic = normalizeDoubleNegation(evidence);
  const claimTokens = tokens(claimLogic);
  const evidenceTokens = tokens(evidenceLogic);
  if (!claimTokens.size) return unknown('empty_claim_tokens');

  const claimDaily = dailyDoseEquivalent(claimLogic);
  const evidenceDaily = dailyDoseEquivalent(evidenceLogic);
  const dailyEquivalent = claimDaily !== null && evidenceDaily !== null && Math.abs(claimDaily - evidenceDaily) < 1e-9
    && doseRewordingKeepsTerms(claimLogic, evidenceLogic);

  const shared = [...claimTokens].filter(t => evidenceTokens.has(t));
  if (shared.length / claimTokens.size < 0.50) {
    if (!dailyEquivalent) return unknown('insufficient_semantic_overlap');
    const claimNumbers = numbers(claimLogic);
    if (!shared.some(t => !claimNumbers.has(t))) return unknown('insufficient_semantic_overlap');
  }

  const [aligned, alignmentReason] = atomicAlignment(claimLogic, evidenceLogic);
  if (!aligned) {
    const bypass = ['atomic_claim_not_entailed', 'atomic_object_mismatch', 'atomic_relation_mismatch'];
    if (!(dailyEquivalent && bypass.includes(alignmentReason))) return unknown(alignmentReason);
  }

  const claimRelation = relationClass(claimLogic);
  const evidenceRelation = relationClass(evidenceLogic);
  if (claimRelation === 'causal' && evidenceRelation === 'association') return unknown('causal_vs_associative_mismatch');
  if (claimRelation !== 'mixed' && evidenceRelation !== claimRelation && evidenceRelation !== 'mixed') return unknown('relation_class_mismatch');

  const [conditionOk, conditionReason] = conditionSupported(claimLogic, evidenceLogic);
  if (!conditionOk) return unknown(conditionReason);

  const claimScope = scopeStrength(claimLogic), evidenceScope = scopeStrength(evidenceLogic);
  if (claimScope.universal && !evidenceScope.universal) return unknown('universal_scope_not_entrailed');
  if (claimScope.exclusive && !evidenceScope.exclusive) return unknown('exclusive_scope_not_entrailed');

  const claimMeasure = measurementKind(claimLogic), evidenceMeasure = measurementKind(evidenceLogic);
  const claimMeasurements = measurements(claimLogic), evidenceMeasurements = measurements(evidenceLogic);
  if (claimMeasurements.size && !subset(claimMeasurements, evidenceMeasurements) && !dailyEquivalent) return unknown('measurement_unit_or_value_mismatch');

  const claimFrequency = frequencyMultiplier(claimLogic), evidenceFrequency = frequencyMultiplier(evidenceLogic);
  if (claimFrequency !== null && evidenceFrequency !== null && Math.abs(claimFrequency - evidenceFrequency) > 1e-9 && !dailyEquivalent) {
    return unknown('dose_frequency_mismatch');
  }
  if (claimMeasure && evidenceMeasure && claimMeasure !== evidenceMeasure) return unknown('risk_measurement_type_mismatch');

  const claimNumbers = numbers(claimLogic);
  if (claimNumbers.size && !subset(claimNumbers, numbers(evidenceLogic)) && !dailyEquivalent) return unknown('numeric_values_not_entrailed');

  if (!subset(populations(claimLogic), populations(evidenceLogic))) return unknown('population_not_entrailed');

  const claimNegated = NEGATION.test(claimLogic), evidenceNegated = NEGATION.test(evidenceLogic);
  if (claimNegated !== evidenceNegated) {
    return { label: claimNegated ? 'CONTRADICTS' : 'UNKNOWN', reasons: ['claim_evidence_polarity_mismatch'] };
  }
  if (termSubstituted(claimLogic, evidenceLogic)) return unknown('atomic_term_substituted');
  return { label: 'SUPPORTS', reasons: ['independent_structured_checks_passed'] };
}

// MARK: semantic_guard.py

const CAUSAL_WORDS = ['cause', 'causes', 'caused', 'leads to', 'result in', 'results in', 'prevent', 'prevents',
  'reduce', 'reduces', 'increase', 'increases', 'decrease', 'decreases'];
const ASSOCIATION_WORDS = ['associated with', 'association', 'correlated with', 'correlation', 'linked to', 'observational'];
const UNIT_SCALE = { mg: 1.0, g: 1000.0, mcg: 0.001, ug: 0.001, ml: 1.0, l: 1000.0 };

/// Doses as [value, unit] in mg, g, mcg, ug, ml or l.
const QUANTITY = py(r`\b(\d+(?:\.\d+)?)\s*(mg|mcg|ug|g|ml|l)\b`, 'gi');
const PERCENT = py(r`\b(\d+(?:\.\d+)?)\s*(?:%|percent)\b`, 'gi');
export const quantities = remembered('quantities', text => allOf(text, QUANTITY).map(m => [Number(m[1]), m[2].toLowerCase()]));
export const percents = remembered('percents', text => allOf(text, PERCENT).map(m => Number(m[1])));
export const frequencyMultiplierGuard = remembered('frequency-guard', text => frequencyOf(text, false));

const NEAR_NEGATION = py(r`\b(no|not|never|without|doesn't|does not|cannot|can't)\b`);

function negationNearRelation(text, relationWords) {
  const lower = String(text).toLowerCase();
  const near = NEAR_NEGATION;
  for (const relation of relationWords) {
    for (let at = lower.indexOf(relation); at >= 0; at = lower.indexOf(relation, at + Math.max(1, relation.length))) {
      if (near.test(lower.slice(Math.max(0, at - 35), at))) return true;
    }
  }
  return false;
}

function claimReasoningWarnings(claim, evidence) {
  const claimAtoms = decomposeClaim(claim);
  const evidenceAtoms = decomposeClaim(evidence);
  const warnings = [];
  for (const c of claimAtoms) {
    let matched = false;
    let reason = 'atomic_claim_not_entailed';
    const claimTokens = tokens(c.text);
    for (const e of evidenceAtoms) {
      const evidenceTokens = tokens(e.text);
      const overlap = [...claimTokens].filter(t => evidenceTokens.has(t)).length / Math.max(1, claimTokens.size);
      if (overlap < 0.45) continue;
      const failed = [relationEntailed(c, e), temporalEntailed(c, e), safetyRelationEntailed(c, e)].find(([ok]) => !ok);
      if (failed) { reason = failed[1] || reason; continue; }
      matched = true;
      break;
    }
    if (!matched) warnings.push(reason);
  }
  return sorted(unique(warnings));
}

/// semantic_guard's warnings about a claim and a passage (with its title):
/// every way the passage does not back the claim, not only the first.
export function semanticWarnings(claim, passage, title = '') {
  const evidence = `${title} ${passage}`.toLowerCase();
  const claimL = String(claim).toLowerCase();
  const warnings = claimReasoningWarnings(claimL, evidence);
  const claimCausal = CAUSAL_WORDS.some(w => claimL.includes(w));
  const evidenceAssociation = ASSOCIATION_WORDS.some(w => evidence.includes(w));
  const evidenceCausal = CAUSAL_WORDS.some(w => evidence.includes(w));
  if (claimCausal && evidenceAssociation && !evidenceCausal) warnings.push('causal_claim_only_associative_evidence');
  const relationWords = [...CAUSAL_WORDS, ...ASSOCIATION_WORDS];
  if (claimCausal && negationNearRelation(claimL, relationWords) !== negationNearRelation(evidence, relationWords)) warnings.push('negation_scope_mismatch');

  const claimDaily = dailyDoseEquivalent(claimL), evidenceDaily = dailyDoseEquivalent(evidence);
  const dailyEquivalent = claimDaily !== null && evidenceDaily !== null && Math.abs(claimDaily - evidenceDaily) < 1e-9
    && doseRewordingKeepsTerms(claimL, evidence);
  if (!dailyEquivalent) {
    const evidenceQ = quantities(evidence);
    for (const [value, unit] of quantities(claimL)) {
      if (!evidenceQ.some(([ev, eu]) => Math.abs(value * UNIT_SCALE[unit] - ev * UNIT_SCALE[eu]) < 1e-9)) {
        warnings.push('dose_or_unit_not_matched');
        break;
      }
    }
    const claimFrequency = frequencyMultiplierGuard(claimL), evidenceFrequency = frequencyMultiplierGuard(evidence);
    if (claimFrequency !== null && evidenceFrequency !== null && Math.abs(claimFrequency - evidenceFrequency) > 1e-9) warnings.push('dose_frequency_mismatch');
  }
  const claimP = percents(claimL), evidenceP = percents(evidence);
  if (claimP.length && !claimP.some(x => evidenceP.some(y => Math.abs(x - y) < 1e-9))) warnings.push('percentage_not_matched');
  const claimScope = scopeStrength(claimL), evidenceScope = scopeStrength(evidence);
  if (claimScope.universal && !evidenceScope.universal) warnings.push('universal_scope_not_supported');
  if (claimScope.exclusive && !evidenceScope.exclusive) warnings.push('exclusive_scope_not_supported');
  const [conditionOk, conditionReason] = conditionSupported(claimL, evidence);
  if (!conditionOk) warnings.push(conditionReason);
  return warnings;
}

// MARK: consistency.py

const CONSISTENCY_POPULATIONS = ['adult', 'adults', 'child', 'children', 'pediatric', 'elderly', 'pregnancy', 'pregnant',
  'breastfeeding', 'renal', 'kidney', 'hepatic', 'liver', 'male', 'female'];
const STRONG_QUALIFIERS = ['always', 'never', 'only', 'all', 'none', 'must', 'guaranteed', '100%', 'definitively'];

/// guard_specificity's warnings: numbers, populations and absolutes in the
/// claim that the passage does not have word for word.
export function specificityWarnings(claim, passage, title = '') {
  const claimL = String(claim).toLowerCase();
  const evidenceL = `${title} ${passage}`.toLowerCase();
  const warnings = [];
  const claimNumbers = numbers(claimL);
  if (claimNumbers.size && !subset(claimNumbers, numbers(evidenceL))) warnings.push('numeric_claim_not_supported_verbatim');
  if (CONSISTENCY_POPULATIONS.some(x => claimL.includes(x) && !evidenceL.includes(x))) warnings.push('population_qualifier_not_matched');
  if (STRONG_QUALIFIERS.some(x => claimL.includes(x) && !evidenceL.includes(x))) warnings.push('absolute_claim_not_matched');
  return warnings;
}

// MARK: the gate

const MU = String.fromCodePoint(0x3bc);
const QUOTES = new RegExp(`[${String.fromCodePoint(0x2018, 0x2019, 0x2032)}]`, 'g');

/// Before the guards: Unicode folded (NFKC: full-width letters and digits,
/// the micro sign), invisible format characters dropped (zero-width spaces
/// and joiners, soft hyphens, direction marks: a word split by one is a word
/// no check sees), curly apostrophes made straight and "isn't" read as "is
/// not", and dose writing the guards do not read put the way they do: "25%"
/// as "25 percent" (they only see a "%" before a letter), micrograms,
/// milligrams, grams and millilitres as mcg, mg, g and ml, and the British
/// tds, qds, bd and "8-hourly" as tid, qid, bid and "every 8 hours".
export function clean(text) {
  return String(text || '').normalize('NFKC').replace(/\p{Cf}/gu, '').replace(QUOTES, "'")
    .replace(/\b(is|are|was|were|do|did|has|have|had|should|would|could|must|need)n't\b/gi, '$1 not')
    .replace(/\bwon't\b/gi, 'will not')
    .replace(/(\d)\s*%/g, '$1 percent')
    .replace(new RegExp(`(\\d)\\s*(?:micrograms?|mcgs?|${MU}g)(?![a-z])`, 'gi'), '$1 mcg')
    .replace(/(\d)\s*milligrams?(?![a-z])/gi, '$1 mg')
    .replace(/(\d)\s*grams?(?![a-z])/gi, '$1 g')
    .replace(/(\d)\s*(?:millilit(?:re|er)s?|mls)(?![a-z])/gi, '$1 ml')
    .replace(/\btds\b/gi, 'tid').replace(/\bqds\b/gi, 'qid').replace(/\bbd\b/gi, 'bid')
    .replace(/\b(\d+)[\s-]*hourly\b/gi, 'every $1 hours')
    .replace(/[^\S\n]+/g, ' ');
}

/// A text as sentences: its lines, and within a line, after a full stop,
/// question or exclamation mark or semicolon and a space (so a decimal point
/// never splits one).
export function sentences(text) {
  return String(text).split(/\n+/).flatMap(line => line.split(/(?<=[.!?;])\s+/)).map(s => s.trim()).filter(Boolean);
}

/// What an item says, sentence by sentence: a question's keyed answer and
/// its explanation (the stem asks, and the other options are wrong on
/// purpose); a card's question and answer read as one statement; anything
/// else, its text - without its labels ("Q:", "Why:"), list marks and cloze
/// brackets.
export function itemClaims(item) {
  let text;
  if (item?.kind === 'mcq') {
    const options = Array.isArray(item.options) ? item.options : [];
    const keyed = Number.isInteger(item.key) && item.key >= 0 && item.key < options.length ? options[item.key] : '';
    text = `${keyed}\n${item.explanation || ''}`;
  } else {
    text = String(item?.text || '')
      .replace(/^[ \t]*Q:[ \t]*(.*?)[ \t]*\?*[ \t]*\n[ \t]*A:[ \t]*/gim, '$1: ')
      .replace(/^[ \t]*(?:Q|A|Why|Cloze|Case|Answer points)[ \t]*:[ \t]*/gim, '')
      .replace(new RegExp(`^[ \\t]*[-*${String.fromCodePoint(0x2022)}][ \\t]+`, 'gm'), '')
      .replace(/\{\{c\d+::(.*?)(?:::[^}]*)?\}\}/g, '$1');
  }
  return sentences(clean(text));
}

const FILLER = new Set(['with', 'that', 'this', 'from', 'have', 'been', 'were', 'which', 'what', 'there', 'their', 'these',
  'those', 'also', 'into', 'than', 'then', 'when', 'will', 'would', 'should', 'could', 'does', 'after', 'before', 'about',
  'other', 'over', 'under', 'they', 'them', 'your', 'more', 'most', 'some', 'such', 'each', 'very']);
const NEGATING = new Set(['never', 'without', 'cannot', 'none', 'neither', 'doesn']);
/// The details the gate compares - how much, how often, by which route -
/// are not what makes two sentences the same sentence.
const DETAIL = new Set(['once', 'twice', 'three', 'four', 'time', 'daily', 'every', 'hour', 'hourly', 'week', 'weekly', 'days',
  'dose', 'dosing', 'dosage', 'oral', 'orally', 'given', 'give', 'take', 'taken', 'percent', 'percentage', 'point']);

/// A sentence's content words: four letters or more, a plural's "s"
/// dropped, and no bare numbers, filler, negation or dose details.
const content = remembered('content', text => {
  const out = new Set();
  for (const word of String(text).toLowerCase().split(/[^\p{L}\p{N}]+/u)) {
    if (word.length < 4 || /^\d+$/.test(word) || FILLER.has(word) || NEGATING.has(word)) continue;
    const stem = word.length > 4 && word.endsWith('s') && !word.endsWith('ss') ? word.slice(0, -1) : word;
    if (!DETAIL.has(stem)) out.add(stem);
  }
  return out;
});

const DIMENSION = { mg: 'mass', g: 'mass', mcg: 'mass', ug: 'mass', ml: 'volume', l: 'volume' };
const doseCount = text => quantities(String(text).toLowerCase()).filter(([, u]) => DIMENSION[u] === 'mass').length;

/// Is `b` nearly the same statement as `a`: three content words or more in
/// common and at least three in five of all either has - or, for a terse
/// dose ("Paracetamol 1 g every 6 hours"), the very same content words and a
/// dose on both sides.
export function restates(a, b) {
  const x = content(a), y = content(b);
  const shared = [...x].filter(w => y.has(w)).length;
  const similar = shared / Math.max(1, x.size + y.size - shared);
  return (shared >= 3 && similar >= 0.6) || (shared >= 1 && similar === 1 && doseCount(a) > 0 && doseCount(b) > 0);
}

const clauses = text => String(text).split(/[,;:()]|\s(?:and|but|while|whereas|although|though|however|because|unless|except)\s/i)
  .map(s => s.trim()).filter(Boolean);
/// The statements of a text: each sentence, and each clause of a sentence
/// that has more than one - with the sentence it is from.
export function statements(text) {
  return sentences(text).flatMap(sentence => {
    const parts = clauses(sentence);
    return (parts.length > 1 ? [sentence, ...parts] : [sentence]).map(part => ({ text: part, sentence }));
  });
}

const negated = text => NEGATION.test(normalizeDoubleNegation(text));
const sameSet = (a, b) => a.size === b.size && subset(a, b);
const FLIPPED = ['claim_evidence_polarity_mismatch', 'safety_polarity_mismatch'];
/// What the guards say that is no finding: "not the same words", which a
/// paraphrase always is, and a negation the clauses do not bear out.
const NOT_FINDINGS = new Set(['insufficient_semantic_overlap', 'atomic_claim_not_entailed', 'no_atomic_evidence_claim',
  'empty_claim_tokens', 'claim_evidence_polarity_mismatch', 'independent_structured_checks_passed']);
const NUMERIC = ['numeric_values_not_entrailed', 'numeric_claim_not_supported_verbatim'];
const COVERED = {
  negation: ['negation_scope_mismatch', 'safety_polarity_mismatch'],
  dose: ['dose_or_unit_not_matched', 'measurement_unit_or_value_mismatch', ...NUMERIC],
  frequency: ['dose_frequency_mismatch', ...NUMERIC],
  percentage: ['percentage_not_matched', 'measurement_unit_or_value_mismatch', ...NUMERIC],
};
/// Every number of the claim is in the lecture's sentence, word for word or
/// as the same measurement in another unit (500 micrograms is 0.5 mg).
function numbersAccountedFor(claim, source) {
  const sourceNumbers = numbers(source), sourceMeasurements = measurements(source);
  const measured = new Set();
  for (const m of allOf(String(claim).toLowerCase(), MEASURED)) {
    const [v, u] = normalizeMeasurement(m[1], m[2]);
    if (sourceMeasurements.has(`${round9(v)} ${u}`)) measured.add(m[1]);
  }
  return [...numbers(claim)].every(n => sourceNumbers.has(n) || measured.has(n));
}

/// Where an item's statement restates one of its lecture's and the lecture
/// does not back it, how the two differ: hard (the item contradicts the
/// lecture) and soft (it says more than, or otherwise from, the lecture), as
/// the guards' codes. `judged`: verify(claim, source), when known.
export function conflicts(claim, source, judged = verify(claim, source)) {
  if (judged.label === 'SUPPORTS') return { hard: [], soft: [] };
  const semantic = semanticWarnings(claim, source);
  const hard = [];
  // the lecture says the opposite: the guards find nothing else between the
  // two but the negation (of a contraindication or interaction too), and a
  // clause of each bears it out
  if (FLIPPED.includes(judged.reasons[0])
      && clauses(claim).some(c => clauses(source).some(s => restates(c, s) && negated(c) !== negated(s)))) hard.push('negation');
  // a different dose, frequency or percentage, for the same people
  if (sameSet(populations(claim), populations(source))) {
    const lowerClaim = claim.toLowerCase(), lowerSource = source.toLowerCase();
    const sourceDoses = quantities(lowerSource);
    if (semantic.includes('dose_or_unit_not_matched')) {
      const unmatched = quantities(lowerClaim).filter(([v, u]) => !sourceDoses.some(([w, s]) => Math.abs(v * UNIT_SCALE[u] - w * UNIT_SCALE[s]) < 1e-9));
      if (unmatched.some(([, u]) => sourceDoses.some(([, s]) => DIMENSION[s] === DIMENSION[u]))) hard.push('dose');
    }
    // one dose each: "500 mg every 8 hours or 875 mg every 12 hours" has two frequencies
    if (semantic.includes('dose_frequency_mismatch') && doseCount(claim) <= 1 && doseCount(source) <= 1) hard.push('frequency');
    if (semantic.includes('percentage_not_matched') && percents(lowerSource).length) hard.push('percentage');
  }
  const covered = new Set(hard.flatMap(code => COVERED[code]));
  if (numbersAccountedFor(claim, source)) for (const code of NUMERIC) covered.add(code);
  const soft = unique([...judged.reasons, ...semantic, ...specificityWarnings(claim, source)])
    .filter(code => !NOT_FINDINGS.has(code) && !covered.has(code));
  return { hard, soft };
}

// MARK: which way it goes

/// The two ways a sentence can go, as Chat-me's evidence model reads them
/// (its DIRECTION: increase or decrease), on two axes: which way something
/// moves or compares (raises, reduces; higher, lower; above, below), and how
/// much or how often it is (high, low; common, rare; minimal). Never half of
/// a hyphenated word: "low-density" is a name, not a way. (The verifier's
/// own, under direction.py above, also reads "stronger" and "weaker", and
/// the second half of a hyphenated word: "glucose-lowering". The parts and
/// things that are no way, and what a comparison is against, are its.)
const AXES = [
  [py(r`(?<!-)\b(?:increas(?:e|es|ed|ing)|higher|greater|more|rais(?:e|es|ed|ing)|elevat(?:e|es|ed|ing)|above)\b(?!-)`, 'g'),
    py(r`(?<!-)\b(?:decreas(?:e|es|ed|ing)|reduc(?:e|es|ed|ing|tion)|lower(?:s|ed|ing)?|less|fewer|below)\b(?!-)`, 'g')],
  [py(r`(?<!-)\b(?:high(?:est)?|common(?:ly|est)?|frequent(?:ly)?)\b(?!-)`, 'g'),
    py(r`(?<!-)\b(?:low(?:est)?|minimal|negligible|rare(?:ly)?|uncommon|infrequent(?:ly)?|seldom)\b(?!-)`, 'g')],
];
/// Words for a measure of how likely: "a higher rate" and "a lower risk" are
/// about the same thing.
const MEASURE = new Set(['risk', 'rate', 'incidence', 'prevalence', 'odds', 'likelihood', 'chance', 'probability', 'hazard']);
const SHORT_STOP = new Set(['is', 'in', 'of', 'to', 'on', 'at', 'by', 'be', 'as', 'or', 'if', 'it', 'an', 'no', 'so', 'do', 'up', 'we',
  'he', 'me', 'my', 'us', 'am', 'go', 'vs', 'ie', 'eg', 'mg', 'ml', 'kg', 'the', 'and', 'for', 'are', 'was', 'has', 'had', 'can', 'may',
  'its', 'his', 'her', 'our', 'but', 'nor', 'yet', 'any', 'all', 'who', 'how', 'why', 'per', 'via', 'did', 'not', 'too', 'out', 'off',
  'own', 'she', 'him', 'you', 'one', 'use', 'due', 'get', 'got', 'let', 'way', 'etc', 'day', 'mcg']);
/// The words that must stay the same for two sentences to be one sentence
/// turned around: its content words, and its short names too (LDL is not
/// HDL, men are not women) and its numbers; a measure is any measure.
const steadyWords = text => {
  const out = new Set(content(text));
  for (const word of String(text).toLowerCase().split(/[^\p{L}\p{N}]+/u)) {
    if (word.length >= 2 && word.length <= 3 && !/^\d+$/.test(word) && !SHORT_STOP.has(word)) out.add(word);
  }
  for (const n of numbers(text)) out.add(n);
  for (const w of MEASURE) out.delete(w);
  return out;
};
/// Which way a sentence goes, axis by axis: on an axis where it has one such
/// word - and only one: "increase the dose to reduce side effects" says
/// nothing of which way the sentence goes - its sign, the rest of its words
/// and, where it compares, what with. Null where it says no way, and where
/// it is negated (a flipped negation is a check of its own).
const turnOf = remembered('turn', text => {
  if (!WAY_HINT.test(text) || negated(text)) return null;
  const plain = replaceAll(String(text).toLowerCase(), DOUBLE_NEGATION_EQUIVALENTS);
  // the parts and things blanked out for finding the way, kept for the words
  const read = blank(NOT_A_WAY, plain);
  const ways = AXES.map(([up, down]) => {
    const ups = allOf(read, up), downs = allOf(read, down);
    if (ups.length + downs.length !== 1) return null;
    const [m] = ups.length ? ups : downs;
    const rest = `${plain.slice(0, m.index)} ${plain.slice(m.index + m[0].length)}`;
    const marker = AGAINST.exec(rest);
    return {
      sign: ups.length ? 1 : -1, words: steadyWords(rest),
      subject: marker ? steadyWords(rest.slice(0, marker.index)) : null,
      against: marker ? steadyWords(rest.slice(marker.index + marker[0].length)) : null,
    };
  });
  return ways.some(Boolean) ? ways : null;
});

/// Does `claim` say what `source` says, turned around: on one axis the two
/// go opposite ways - higher for lower, rare for common - and all their
/// other words are nearly the same (three or more in common, and three in
/// five of all either has, as restates() counts them), with none changed
/// for another (upper for lower motor neuron, LDL for HDL: two facts, not
/// one turned). Where both say what they compare against, it must be the
/// same thing on the same side - "more common in men than in women" turned
/// is "less common in men than in women", but "less common in women than in
/// men" says the same - and where only one does, the other must not name it
/// ("warfarin has a higher risk than DOACs" and "DOACs have a lower risk"
/// agree). After the direction axis of Chat-me's evidence model
/// (evidence_model.py on verification-layer-commercial-accuracy-v1, at
/// 030ed8c); not a port of it: that reads any two passages' words for a way,
/// this only a sentence against its own lecture's, word for word.
export function turnedAround(claim, source) {
  const a = turnOf(claim), b = a && turnOf(source);
  if (!b) return false;
  return a.some((x, axis) => {
    const y = b[axis];
    if (!x || !y || x.sign === y.sign) return false;
    const shared = [...x.words].filter(w => y.words.has(w)).length;
    if (shared < 3 || shared / (x.words.size + y.words.size - shared) < 0.6) return false;
    // a word changed for another
    if (shared !== x.words.size && shared !== y.words.size) return false;
    if (x.against && y.against) {
      return (meets(x.against, y.against) || (!x.against.size && !y.against.size))
        && !meets(x.against, y.subject) && !meets(y.against, x.subject);
    }
    if (x.against) return !meets(x.against, y.words);
    if (y.against) return !meets(y.against, x.words);
    return true;
  });
}

/** @typedef {{ code: string, claim: string, source: string }} ClaimFinding */
/** @typedef {{ hard: ClaimFinding[], soft: ClaimFinding[], checks: number, work: number, complete: boolean }} ClaimFindings */

const LIMIT = 5;
/// The gate's budget for a batch, counted in work, not read off a clock: a
/// Worker's clock stands still while it computes, and the free plan gives a
/// request about 10 ms of CPU, most of it for the rest of the check. A
/// statement of the item looked at, and each statement of the lecture it is
/// compared with (whether it restates it or turns it around), is a unit of
/// work (about 5 microseconds); a judgement (verify(), about 120) is
/// VERIFY_WORK units. The worst batch the server takes - four items of
/// MAX_ITEM_CHARS, every sentence a dose, against lectures of
/// MAX_SOURCE_CHARS - comes to about 3 ms warm, and a batch of ordinary cards
/// and questions is done well within it (tests/claims.test.mjs holds it to
/// both). A long page stops at its share, with what it found so far (never
/// more than the votes would have had without it) and `complete` false.
export const MAX_WORK = 1200;
export const VERIFY_WORK = 30;
/// How many sentences of an item, and of its lecture, the gate reads: the
/// first so many. Each is worked out (split into clauses and words, its
/// doses read) before any pair is compared.
export const MAX_SENTENCES = 20;
const excerpt = s => (s.length > 160 ? `${s.slice(0, 157)}...` : s);

/// What mayBack() needs of a statement, worked out once: its words and its
/// daily dose.
function backing(text) {
  const logic = normalizeDoubleNegation(text);
  return { tokens: tokens(logic), daily: dailyDoseEquivalent(logic) };
}

/// Could verify() say SUPPORTS at all: half the claim's words in the
/// statement, or the same daily dose (its own first test, done cheaply).
function mayBack(claim, statement) {
  const a = claim.tokens, b = statement.tokens;
  if (a.size && [...a].filter(t => b.has(t)).length / a.size >= 0.5) return true;
  const x = claim.daily, y = statement.daily;
  return x !== null && y !== null && Math.abs(x - y) < 1e-9;
}

/// Run `fn` with each text's facts worked out once throughout - a batch's
/// items often share their lecture. Nested calls share the outer memo.
export function remembering(fn) {
  if (memo) return fn();
  memo = new Map();
  try {
    return fn();
  } finally {
    memo = null;
  }
}

/// The claim gate for one item: each of its statements against those of its
/// lecture that it restates or turns around - unless any other statement of
/// the lecture backs it as it is (a lecture can give a loading dose and a
/// daily one). Nothing to say without a lecture, or where nothing is
/// restated or turned. Each finding once a sentence; at most `maxWork` units
/// of work (`complete` false when it stopped there, or when the item or its
/// lecture had more than MAX_SENTENCES sentences). `work` is what it used,
/// `checks` how many judgements it made.
/** @returns {ClaimFindings} */
export function claimGate(item, maxWork = MAX_WORK) {
  return remembering(() => gate(item, maxWork));
}

/// A lecture's statements (its first MAX_SENTENCES sentences), each with its
/// content words; once a batch, when the batch's items share it.
const lectureOf = remembered('lecture', source => {
  const read = sentences(clean(source));
  const lecture = statements(read.slice(0, MAX_SENTENCES).join('\n')).map(s => ({ ...s, words: content(s.text) }));
  return { lecture, cut: read.length > MAX_SENTENCES };
});

function gate(item, maxWork) {
  const out = { hard: [], soft: [], checks: 0, work: 0, complete: true };
  const { lecture, cut } = lectureOf(String(item?.source || ''));
  if (!lecture.length) return out;
  const claims = itemClaims(item);
  const said = statements(claims.slice(0, MAX_SENTENCES).join('\n'));
  if (cut || claims.length > MAX_SENTENCES) out.complete = false;
  const judge = (claim, source) => { out.checks++; out.work += VERIFY_WORK; return verify(claim, source); };
  const seen = new Set();
  const note = (list, code, claim, source, sentence) => {
    const key = `${code}|${sentence}`;
    if (seen.has(key) || list.length >= LIMIT) return;
    seen.add(key);
    list.push({ code, claim: excerpt(claim), source: excerpt(source) });
  };
  for (const { text: claim, sentence } of said) {
    // each step's work is counted before it is done, so an item never uses
    // more than it was given
    const words = content(claim);
    const near = lecture.filter(s => [...words].some(w => s.words.has(w)));
    if (out.work + 1 + near.length > maxWork) { out.complete = false; break; }
    out.work += 1 + near.length;
    const restated = near.filter(s => restates(claim, s.text));
    const turned = turnOf(claim) ? near.filter(s => turnedAround(claim, s.text)) : [];
    if (!restated.length && !turned.length) continue;
    if (out.work + near.length > maxWork) { out.complete = false; break; }
    out.work += near.length;
    const facts = backing(claim);
    // the lecture's sentence turned around never backs the item it
    // contradicts, whatever verify() makes of it (verify() reads which way a
    // sentence goes too, but not as turnedAround() does)
    const away = new Set(turned.map(s => s.sentence));
    const backers = near.filter(s => !away.has(s.sentence) && mayBack(facts, s.backing ||= backing(s.text)));
    if (out.work + (backers.length + restated.length) * VERIFY_WORK > maxWork) { out.complete = false; break; }
    if (backers.some(s => judge(claim, s.text).label === 'SUPPORTS')) continue;
    for (const { text: source } of turned) note(out.hard, 'direction', claim, source, sentence);
    for (const { text: source, sentence: from } of restated) {
      const found = conflicts(claim, source, judge(claim, source));
      for (const code of found.hard) note(out.hard, code, claim, source, sentence);
      for (const code of found.soft) {
        // a sentence turned around is the hard finding above already
        if (code !== 'atomic_direction_mismatch' || !away.has(from)) note(out.soft, code, claim, source, sentence);
      }
    }
  }
  return out;
}
