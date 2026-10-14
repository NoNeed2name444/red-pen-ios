// The vignette route: a proof-carrying clinical vignette, checked by a small
// deterministic program (docs/verification/vignette-proof-research.md §4).
//
// proof.js proves a statement a source states word for word; a vignette is a
// deduction (findings + published rule => the key, and every other option
// ruled out), which no source states. So the item carries a proof packet,
// written by anyone (a model, a person: untrusted, its errors cost coverage
// only), and this checker accepts it only when every part is mechanical:
//
//   1. the packet is for this exact item (stem, options and key unchanged)
//   2. every finding is an exact span of the stem, read through the lexicon
//      (server/lexicon.js) in exactly one of its written forms, in a sentence
//      with no negation, hedge, other person, past time or condition cue, and
//      no other mention of that slot is left out of the proof
//   3. every rule is in the reviewed registry (server/criteria), unchanged
//      since its review, from a source whose licence allows commercial use
//      and of the top grade (a guideline or a label; oath items need it)
//   4. the rule fires on those findings by plain evaluation; a criterion that
//      needs judgment never fires
//   5. the question asks what the rule concludes, and the key is the rule's
//      conclusion word for word (a registered alias)
//   6. every other option is ruled out: by an outcome the rule itself
//      excludes, or by a registry rule that denies it on the stem's findings;
//      a finding not mentioned never rules anything out
//   7. an explanation says nothing but the rules' own quotes
//
// Anything else returns a typed `why` and the item stays at Check this (la
// adri: not established is an honest answer). Every rule and quoted lexicon
// entry the proof used signed off by the owner (bound to its content hash):
// tier 'proven', which may back Verified; otherwise tier 'checked', which
// may back only the Checked tier. Nothing here is a model or a guess, and it
// is pure: the same item and packet always give the same answer.

import { normalize, unreadableNumber } from './proof.js';
import { SLOTS, UNITS, readSpan, mentions } from './lexicon.js';
import REGISTRY from './criteria/registry.js';

export const VIGNETTE_PROOF_VERSION = 1;
/// The most work one check does, in characters read: far under proof.js's
/// PROOF_CHARS. Running out is 'budget', never a pass.
export const VIGNETTE_WORK = 40000;
const MAX_PACKET_CHARS = 16000;
const MAX_FINDINGS = 24;

// MARK: hashing (sign-off and staleness are bound to exact content)

const K = new Uint32Array([
  0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5, 0xd807aa98, 0x12835b01,
  0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc,
  0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da, 0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147,
  0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
  0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070, 0x19a4c116, 0x1e376c08,
  0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3, 0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
  0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2]);

/// SHA-256 of a string's UTF-8 bytes, as hex: synchronous and the same in
/// the Worker, Node and the build script.
export function sha256(text) {
  const bytes = new TextEncoder().encode(String(text));
  const n = bytes.length;
  const blocks = Math.ceil((n + 9) / 64);
  const m = new Uint8Array(blocks * 64);
  m.set(bytes);
  m[n] = 0x80;
  const bits = n * 8;
  const dv = new DataView(m.buffer);
  dv.setUint32(m.length - 8, Math.floor(bits / 2 ** 32));
  dv.setUint32(m.length - 4, bits >>> 0);
  const h = new Uint32Array([0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19]);
  const w = new Uint32Array(64);
  const rot = (x, r) => (x >>> r) | (x << (32 - r));
  for (let b = 0; b < blocks; b++) {
    for (let i = 0; i < 16; i++) w[i] = dv.getUint32(b * 64 + i * 4);
    for (let i = 16; i < 64; i++) {
      const s0 = rot(w[i - 15], 7) ^ rot(w[i - 15], 18) ^ (w[i - 15] >>> 3);
      const s1 = rot(w[i - 2], 17) ^ rot(w[i - 2], 19) ^ (w[i - 2] >>> 10);
      w[i] = (w[i - 16] + s0 + w[i - 7] + s1) >>> 0;
    }
    let [a, bb, c, d, e, f, g, hh] = h;
    for (let i = 0; i < 64; i++) {
      const t1 = (hh + (rot(e, 6) ^ rot(e, 11) ^ rot(e, 25)) + ((e & f) ^ (~e & g)) + K[i] + w[i]) >>> 0;
      const t2 = ((rot(a, 2) ^ rot(a, 13) ^ rot(a, 22)) + ((a & bb) ^ (a & c) ^ (bb & c))) >>> 0;
      hh = g; g = f; f = e; e = (d + t1) >>> 0; d = c; c = bb; bb = a; a = (t1 + t2) >>> 0;
    }
    h[0] += a; h[1] += bb; h[2] += c; h[3] += d; h[4] += e; h[5] += f; h[6] += g; h[7] += hh;
  }
  return [...h].map(x => x.toString(16).padStart(8, '0')).join('');
}

/// JSON with every object's keys in order: one text per value.
export function canonical(v) {
  if (Array.isArray(v)) return `[${v.map(canonical).join(',')}]`;
  if (v && typeof v === 'object') return `{${Object.keys(v).sort().filter(k => v[k] !== undefined).map(k => `${JSON.stringify(k)}:${canonical(v[k])}`).join(',')}}`;
  return JSON.stringify(v === undefined ? null : v);
}

const UNSIGNED = new Set(['signedOffAt', 'signedOffBy', 'signedOffHash', 'hash']);
const strip = x => Object.fromEntries(Object.entries(x || {}).filter(([k]) => !UNSIGNED.has(k)));

/// A rule's content hash: everything the review read and the owner signs,
/// so a rule changed after either is no longer the rule they passed.
export const ruleHash = rule => sha256(canonical(strip(rule)));
/// A quoted lexicon entry's content hash, the same way.
export const lexiconHash = entry => sha256(canonical(strip({ slot: entry.slot, form: entry.form, value: entry.value, backing: entry.backing })));
/// The item a packet is for: its stem, options and key, exactly.
export const itemDigest = item => sha256(canonical(['vignette-v1', String(item?.stem ?? ''), Array.isArray(item?.options) ? item.options.map(String) : [], item?.key]));

// MARK: sources (licence and grade, in code)

/// Licences that allow commercial use. Anything else, and any licence that
/// names non-commercial or no-derivatives terms, is refused.
export const COMMERCIAL_LICENCES = Object.freeze(['us-federal-public-domain', 'cc0-1.0', 'cc-by-4.0', 'commercial-grant']);
const NOT_COMMERCIAL = /(?:^|[^a-z])(?:nc|nd|non-?commercial|no-?deriv\w*)(?:[^a-z]|$)/i;
// StatPearls is CC BY-NC-ND (the owner, 14 Oct: never StatPearls), under
// any of its names or its NCBI Bookshelf id
const STATPEARLS = /stat\s*pearls|nbk430685/i;
/// The source types a rule may rest on: provenance.js grade 5 (a guideline,
/// a systematic review, a label), the grade a diagnosis or treatment needs.
export const RULE_SOURCE_TYPES = Object.freeze(['guideline', 'systematic-review', 'label']);

/// Whether a source may be quoted at all: a recorded licence that allows
/// commercial use, its terms and grant recorded, never StatPearls.
export function licenceAllows(src) {
  if (!src || typeof src !== 'object') return false;
  if (STATPEARLS.test([src.id, src.title, src.publisher, src.url].map(x => String(x ?? '')).join(' '))) return false;
  const l = src.licence;
  if (!l || typeof l !== 'object' || l.commercialUse !== true) return false;
  if (typeof l.id !== 'string' || !COMMERCIAL_LICENCES.includes(l.id) || NOT_COMMERCIAL.test(l.id)) return false;
  if (typeof l.url !== 'string' || !/^https:\/\/\S+$/.test(l.url)) return false;
  if (typeof l.grant !== 'string' || !l.grant.trim()) return false;
  // a society's or a publisher's own grant must name commercial use itself
  if (l.id === 'commercial-grant' && !/commercial/i.test(l.grant)) return false;
  return true;
}

/// Whether a source may back a rule: allowed, top grade, current.
export function ruleSourceAllows(src) {
  return licenceAllows(src) && RULE_SOURCE_TYPES.includes(src.type) && src.status === 'current' && src.retracted !== true;
}

const ISO_DATE = /^\d{4}-\d{2}-\d{2}(?:T\d{2}:\d{2}(?::\d{2}(?:\.\d+)?)?(?:Z|[+-]\d{2}:\d{2}))?$/;
/// Whether the owner has signed this rule or lexicon entry off as it is now:
/// a date, a name, and the hash of exactly this content (an edit after the
/// sign-off undoes it). `signoffs`: sign-offs kept elsewhere (id -> hash).
export function signedOff(x, hash, signoffs = null) {
  if (!x || typeof hash !== 'string') return false;
  if (signoffs instanceof Map && signoffs.get(x.id) === hash) return true;
  return typeof x.signedOffAt === 'string' && ISO_DATE.test(x.signedOffAt) && !Number.isNaN(Date.parse(x.signedOffAt))
    && typeof x.signedOffBy === 'string' && x.signedOffBy.trim().length > 0 && x.signedOffHash === hash;
}

// MARK: reading numbers a criterion is written with

const unitOf = word => Object.keys(UNITS).find(u => UNITS[u].includes(String(word).toLowerCase())) || null;
const SAYS = [
  [/^(\d+(?:\.\d+)?) or more (\w+)$/i, m => ({ op: '>=', value: +m[1], unit: unitOf(m[2]) })],
  [/^(\d+(?:\.\d+)?) (\w+) or more$/i, m => ({ op: '>=', value: +m[1], unit: unitOf(m[2]) })],
  [/^(\d+(?:\.\d+)?) (\w+) or greater$/i, m => ({ op: '>=', value: +m[1], unit: unitOf(m[2]) })],
  [/^between (\d+(?:\.\d+)?) and (\d+(?:\.\d+)?) (\w+)$/i, m => ({ op: 'between', value: [+m[1], +m[2]], unit: unitOf(m[3]) })],
  [/^less than (\d+(?:\.\d+)?) (\w+)$/i, m => ({ op: '<', value: +m[1], unit: unitOf(m[2]) })],
  [/^more than (\d+(?:\.\d+)?) (\w+)$/i, m => ({ op: '>', value: +m[1], unit: unitOf(m[2]) })],
];

/// What a criterion's own words say about a number ("5 or more
/// millimeters"): {op, value, unit}, or null when they cannot be read for
/// certain. The registry review holds every numeric criterion to this.
export function readSays(says) {
  const t = String(says ?? '').trim().replace(/\s+/g, ' ');
  for (const [re, f] of SAYS) {
    const m = re.exec(t);
    if (m) {
      const r = f(m);
      return r.unit ? r : null;
    }
  }
  return null;
}

// MARK: evaluating a rule

const NUMERIC = new Set(['>=', '>', '<=', '<', 'between']);
const compare = (op, x, v) => (op === '>=' ? x >= v : op === '>' ? x > v : op === '<=' ? x <= v : op === '<' ? x < v
  : op === 'between' ? Array.isArray(v) && x >= v[0] && x <= v[1] : false);

/// Whether a rule fires on facts ([{slot, value}]): every criterion met,
/// none by judgment. {fires, missing: criterion ids not met, judgment, used:
/// for each criterion the facts that met it}. Two facts that give one numeric
/// slot different values never meet it.
export function evaluateRule(rule, facts) {
  const crit = rule?.formal?.criteria;
  if (!Array.isArray(crit) || !crit.length) return { fires: false, missing: ['criteria'], judgment: false, used: {} };
  const missing = [];
  const used = {};
  let judgment = false;
  for (const c of crit) {
    if (c.judgment === true || c.op === 'judgment') { judgment = true; missing.push(c.id); continue; }
    const mine = facts.filter(f => f.slot === c.slot);
    let met = [];
    if (c.op === 'present') met = mine.filter(f => f.value === true);
    else if (c.op === 'anyOf') met = mine.filter(f => Array.isArray(c.values) && c.values.includes(f.value));
    else if (NUMERIC.has(c.op)) {
      const values = new Set(mine.map(f => f.value));
      if (values.size === 1 && mine.every(f => typeof f.value === 'number' && compare(c.op, f.value, c.value))) met = mine;
    }
    if (met.length) used[c.id] = met;
    else missing.push(c.id);
  }
  return { fires: missing.length === 0, missing, judgment, used };
}

// MARK: the stem, read

/// The stem's sentences as [start, end) spans: split after . ! ? or ; when
/// a capital, a digit, a bracket or the end follows (so "7.5 mm" and
/// "e.g. nursing homes" stay whole).
export function sentenceSpans(text) {
  const out = [];
  let start = 0;
  const re = /[.!?;]+["')\]]*(?=\s+["'(\[]?[A-Z0-9]|\s*$)/g;
  for (const m of text.matchAll(re)) {
    const end = m.index + m[0].length;
    if (end > start) out.push([start, end]);
    start = end;
    while (start < text.length && /\s/.test(text[start])) start++;
  }
  if (start < text.length && text.slice(start).trim()) out.push([start, text.length]);
  return out;
}

/// Words that may change what a finding means, by kind. A finding's sentence
/// holding any of them (outside the findings' own spans) refuses the proof,
/// unless the finding's slot allows that kind.
export const CUES = Object.freeze({
  negation: /\b(?:no|not|nor|neither|none|never|denies|denied|deny|denying|without|negative|absent|absence|unremarkable|free of|ruled out|rule out|rules out|excluded|excludes?|lacks?|lacking|nonreactive|non-reactive)\b|n['’]t\b/i,
  hedge: /\?|\b(?:possible|possibly|probable|probably|suspect\w*|suspicion|suspicious|may|might|could|likely|unlikely|questionabl\w*|query|consider\w*|concern\w*|versus|vs|presum\w*|apparent\w*|equivocal|borderline|indeterminate|uncertain|unclear|reported\w*|unknown|approximately|about|around|roughly|nearly|almost|over|under|less than|more than|at least|up to|estimated|or so)\b/i,
  other: /\b(?:mother|father|parents?|sisters?|brothers?|siblings?|sons?|daughters?|wife|husband|partner|spouse|boyfriend|girlfriend|roommates?|friends?|family|relatives?|grand\w+|aunts?|uncles?|cousins?|nieces?|nephews?|co-?workers?|colleagues?|neighbou?rs?|classmates?|bab(?:y|ies)|infants?|newborns?|fetus|twins?|child(?:ren)?|someone|others?)\b/i,
  past: /\b(?:history|previous\w*|prior|former\w*|ago|past|childhood|once|earlier|last (?:year|month|week)|used to|had been|was treated|recovered|resolved|remote)\b/i,
  condition: /\b(?:if|unless|whether|would|should|will|plans?|planned|planning|scheduled|expect\w*|in case|wants?|hopes?|asks? (?:about|for)|requests?|awaiting|waiting|pending|candidate|referred|referral|evaluat\w* for|tested for|testing for|screen\w* for|test for)\b/i,
});

function cueIn(text, allows) {
  for (const [kind, re] of Object.entries(CUES)) if (!allows.includes(kind) && re.test(text)) return kind;
  return null;
}

const optionsOf = options => {
  let opts = options.map(o => String(o).trim());
  if (opts.every((o, i) => new RegExp(`^\\(?${'abcdefghij'[i]}[.)]\\s+`, 'i').test(o))) opts = opts.map(o => o.replace(/^\(?[a-j][.)]\s+/i, ''));
  return opts;
};
const tokens = t => {
  const n = normalize(String(t ?? ''));
  return n ? n.join(' ') : null;
};
const contains = (hay, needle) => !!hay && !!needle && (` ${hay} `).includes(` ${needle} `);

// MARK: the checker

const fail = (why, detail) => ({ v: VIGNETTE_PROOF_VERSION, ok: false, tier: null, why, ...(detail ? { detail: String(detail).slice(0, 200) } : {}) });

/// Every quote a rule rests on: criteria, their list items and lead-ins, and
/// its conclusion's (what an explanation may say).
export function ruleQuotes(rule) {
  const out = [];
  const f = rule?.formal || {};
  for (const c of f.criteria || []) {
    if (c.quote) out.push(c.quote);
    if (c.leadIn) out.push(c.leadIn);
    for (const q of Object.values(c.items || {})) out.push(q);
  }
  if (f.conclusion?.quote) out.push(f.conclusion.quote);
  return out;
}

/// The words a criterion is written in, for a literal lexicon form: its
/// quote, the lead-in of its list and, for a set, the item naming the value.
function criterionWords(c, value) {
  return [c.quote, c.leadIn, c.items?.[value]].filter(Boolean).map(tokens).filter(Boolean);
}

/// Check one vignette's proof packet. `registry`: the reviewed rules,
/// sources and quoted lexicon entries (criteria/registry.js); `signoffs`:
/// owner sign-offs kept outside the registry (id -> content hash).
/// {v, ok, tier: 'proven'|'checked', why, rules, findings, eliminated,
/// chains} - `chains`, for provenance.js, every finding's span, every quote
/// and the deduction - or {v, ok: false, why}.
export function checkVignette(item, packet, { registry = REGISTRY, slots = SLOTS, signoffs = null, work = VIGNETTE_WORK } = {}) {
  try {
    return check(item, packet, registry, slots, signoffs, work);
  } catch (e) {
    if (e === OVER) return fail('budget');
    return fail('error', e?.message);
  }
}

const OVER = Symbol('over');

function check(item, packet, registry, slots, signoffs, work) {
  let left = work;
  const spend = n => { if ((left -= n) < 0) throw OVER; };
  // 1. the packet, for this item
  if (!packet || typeof packet !== 'object' || Array.isArray(packet)) return fail('packet');
  let size;
  try { size = JSON.stringify(packet).length; } catch { return fail('packet'); }
  if (size > MAX_PACKET_CHARS || packet.v !== VIGNETTE_PROOF_VERSION) return fail('packet');
  if (!item || item.kind !== 'mcq' || typeof item.stem !== 'string' || !Array.isArray(item.options) || item.options.length < 2
    || !Number.isInteger(item.key) || item.key < 0 || item.key >= item.options.length) return fail('mcq');
  const stem = item.stem;
  spend(stem.length + item.options.join('').length + size);
  if (packet.item !== itemDigest(item) || packet.key !== item.key) return fail('stale');
  const findings = packet.findings;
  if (!Array.isArray(findings) || !findings.length || findings.length > MAX_FINDINGS) return fail('packet');
  const sentences = sentenceSpans(stem);
  const question = sentences[sentences.length - 1];
  if (!question || !stem.slice(question[0], question[1]).trim().endsWith('?')) return fail('asks', 'the stem does not end in a question');
  const sentenceOf = (s, e) => sentences.findIndex(([a, b]) => s >= a && e <= b);

  // 2. every finding an exact span, read through the lexicon
  const byId = new Map();
  for (const f of findings) {
    if (!f || typeof f !== 'object' || typeof f.id !== 'string' || !f.id || byId.has(f.id)) return fail('packet');
    const [s, e] = Array.isArray(f.at) ? f.at : [];
    if (!Number.isInteger(s) || !Number.isInteger(e) || s < 0 || e <= s || e > stem.length) return fail('span', f.id);
    if (stem.slice(s, e) !== f.text) return fail('span', f.id);
    if (unreadableNumber(f.text) || !normalize(f.text)) return fail('unreadable', f.id);
    spend(f.text.length * 4);
    const read = readSpan(f.slot, f.text, slots);
    if (!read) return fail('lexicon', f.id);
    if ('value' in f && f.value !== read.value) return fail('lexicon', `${f.id}: the span reads ${read.value}`);
    const sentence = sentenceOf(s, e);
    if (sentence < 0) return fail('span', `${f.id} crosses a sentence`);
    if (sentence === sentences.length - 1) return fail('span', `${f.id} is in the question`);
    byId.set(f.id, { ...f, s, e, value: read.value, entry: read.entry, sentence });
  }
  // cues: each finding's sentence, the findings' own spans blanked out
  for (const f of byId.values()) {
    const [a, b] = sentences[f.sentence];
    let text = stem.slice(a, b);
    const inside = [...byId.values()].filter(g => g.sentence === f.sentence).sort((x, y) => y.s - x.s);
    for (const g of inside) text = text.slice(0, g.s - a) + ' '.repeat(g.e - g.s) + text.slice(g.e - a);
    spend(text.length * 2);
    const cue = cueIn(text, slots[f.slot]?.allows || []);
    if (cue) return fail('cue', `${f.id}: ${cue}`);
  }
  // no other mention of a slot the proof reads may be left out of it
  for (const slot of new Set([...byId.values()].map(f => f.slot))) {
    spend(stem.length * 2);
    const listed = [...byId.values()].filter(f => f.slot === slot);
    for (const [s, e] of mentions(slot, stem, slots)) {
      if (!listed.some(f => f.s <= s && f.e >= e)) return fail('conflict', `another mention of ${slot} at ${s}`);
    }
    if (slots[slot]?.type === 'number' && new Set(listed.map(f => f.value)).size > 1) return fail('conflict', `${slot} has two values`);
  }

  // 3. the rule, reviewed and unchanged, on an allowed source
  const rulesUsed = [];
  const lexUsed = new Map();
  const ruleOf = (id, ver) => {
    const r = (registry?.rules || []).find(x => x.id === id);
    if (!r) return [null, fail('rule', `${id} is not in the reviewed registry`)];
    if (ver !== undefined && ver !== r.version) return [null, fail('stale', `${id} is now version ${r.version}`)];
    spend(2000);
    if (typeof r.hash !== 'string' || ruleHash(r) !== r.hash) return [null, fail('rule', `${id} changed since its review`)];
    const src = registry.sources?.[r.source];
    if (!licenceAllows(src)) return [null, fail('licence', r.source)];
    if (!ruleSourceAllows(src)) return [null, fail('grade', r.source)];
    return [r, null];
  };
  /// the facts a rule reads, checked against the words it is written in
  const factsFor = (rule, ids) => {
    if (!Array.isArray(ids) || !ids.length) return [null, fail('packet', 'a rule uses no finding')];
    const facts = [];
    for (const id of ids) {
      const f = byId.get(id);
      if (!f) return [null, fail('packet', `unknown finding ${id}`)];
      facts.push(f);
    }
    const ev = evaluateRule(rule, facts);
    if (ev.judgment) return [null, fail('judgment', rule.id)];
    if (!ev.fires) return [null, fail('fires', `${rule.id}: ${ev.missing.join(', ')}`)];
    // every finding it uses meets a criterion, through a backed form
    for (const f of facts) {
      const crits = rule.formal.criteria.filter(c => ev.used[c.id]?.includes(f));
      if (!crits.length) return [null, fail('packet', `${f.id} meets no criterion of ${rule.id}`)];
      const entry = f.entry;
      if (entry.backing?.kind === 'literal') {
        const need = slots[f.slot]?.type === 'number' ? (entry.words || []).map(tokens) : [tokens(entry.form)];
        const ok = crits.some(c => criterionWords(c, f.value).some(w => need.every(n => contains(w, n))))
          && (slots[f.slot]?.type !== 'number' || crits.every(c => !c.unit || c.unit === entry.unit));
        if (!ok) return [null, fail('lexicon', `${f.id}: its words are not ${rule.id}'s own`)];
      } else if (entry.backing?.kind === 'quoted') {
        const hash = lexiconHash({ slot: f.slot, ...entry });
        const admitted = (registry?.lexicon || []).find(x => x.id === entry.id);
        if (!admitted || admitted.hash !== hash) return [null, fail('lexicon', `${f.id}: ${entry.id || entry.form} is not reviewed`)];
        const canon = tokens(entry.backing.canonical);
        if (!crits.some(c => criterionWords(c, f.value).some(w => contains(w, canon)))) return [null, fail('lexicon', `${f.id}: ${entry.backing.canonical} is not ${rule.id}'s word`)];
        lexUsed.set(entry.id, { entry, hash });
      } else return [null, fail('lexicon', f.id)];
    }
    // findings the rule needs side by side
    for (const group of rule.formal.together || []) {
      const at = new Set(facts.filter(f => group.includes(f.slot)).map(f => f.sentence));
      if (at.size > 1) return [null, fail('together', `${rule.id}: ${group.join(', ')}`)];
    }
    return [facts, null];
  };

  const proves = packet.proves;
  if (!proves || typeof proves !== 'object') return fail('packet');
  const [rule, bad] = ruleOf(proves.rule, proves.ver);
  if (bad) return bad;
  if (rule.kind !== 'criteria') return fail('rule', `${rule.id} does not conclude`);
  const [facts, unmet] = factsFor(rule, proves.uses);
  if (unmet) return unmet;
  rulesUsed.push(rule);

  // 5. the question asks what the rule concludes, and the key is it
  const conclusion = rule.formal.conclusion;
  const ask = tokens(stem.slice(question[0], question[1]));
  if (!(conclusion.asks || []).some(a => contains(ask, tokens(a)))) return fail('asks');
  const opts = optionsOf(item.options);
  const optTokens = opts.map(tokens);
  spend(opts.join('').length * 4);
  if (optTokens.some(o => !o)) return fail('options');
  const says = (aliases, o) => (aliases || []).some(a => tokens(a) === o);
  if (!says(conclusion.aliases, optTokens[item.key])) return fail('conclusion');
  if (optTokens.some((o, i) => i !== item.key && says(conclusion.aliases, o))) return fail('options', 'two options say the conclusion');

  // 6. every other option ruled out
  const eliminations = Array.isArray(packet.eliminates) ? packet.eliminates : [];
  let eliminated = 0;
  const denials = [];
  for (let i = 0; i < opts.length; i++) {
    if (i === item.key) continue;
    const el = eliminations.find(x => x && x.option === i);
    if (!el) return fail('distractor', `option ${i} is not ruled out`);
    if (el.by === 'exclusive') {
      const out = (rule.formal.exclusive || []).find(x => says(x.aliases, optTokens[i]));
      if (!out) return fail('distractor', `option ${i} is not an outcome ${rule.id} excludes`);
    } else if (el.by === 'denies') {
      const [deny, badRule] = ruleOf(el.rule, el.ver);
      if (badRule) return badRule;
      if (deny.kind !== 'denial') return fail('distractor', `${deny.id} denies nothing`);
      const [dfacts, dunmet] = factsFor(deny, el.uses);
      if (dunmet) return dunmet;
      if (!says(deny.formal.conclusion.aliases, optTokens[i])) return fail('distractor', `${deny.id} does not deny option ${i}`);
      if (!rulesUsed.includes(deny)) rulesUsed.push(deny);
      denials.push({ rule: deny, facts: dfacts, option: i });
    } else return fail('distractor', `option ${i}: no way to rule it out`);
    eliminated++;
  }

  // 7. an explanation says only what the rules say
  const explanation = String(item.explanation ?? '').trim();
  if (explanation) {
    spend(explanation.length * 4);
    const allowed = new Set(rulesUsed.flatMap(ruleQuotes).map(tokens).filter(Boolean));
    for (const [a, b] of sentenceSpans(explanation)) {
      const t = tokens(explanation.slice(a, b));
      if (!t || !allowed.has(t)) return fail('explanation', explanation.slice(a, b));
    }
  }

  // proven only when the owner signed off every rule and quoted entry it used
  const signed = rulesUsed.every(r => signedOff(r, r.hash, signoffs))
    && [...lexUsed.values()].every(({ entry, hash }) => signedOff(entry, hash, signoffs));
  const sourceOf = r => {
    const src = registry.sources[r.source];
    return { id: src.id, url: src.url, title: src.title, type: src.type, publisher: src.publisher, date: src.date,
      edition: src.edition, status: src.status, licence: src.licence?.id };
  };
  const chains = [
    ...[...byId.values()].map(f => ({ claim: f.text, passage: f.text, retrieval: 'verbatim-span', source: null, slot: f.slot })),
    ...rulesUsed.flatMap(r => ruleQuotes(r).map(q => ({ claim: q, passage: q, retrieval: 'quoted', source: sourceOf(r), rule: r.id }))),
    { claim: opts[item.key], passage: null, retrieval: 'deduction', source: null, rule: rule.id, synthesis: true },
  ];
  return {
    v: VIGNETTE_PROOF_VERSION, ok: true, tier: signed ? 'proven' : 'checked', why: null,
    rules: rulesUsed.map(r => r.id), findings: byId.size, eliminated, chains, facts: facts.length + denials.length,
  };
}

/// Whether a check (as checkVignette gives it) proves the item: every step
/// mechanical and every rule signed off. Only this may back Verified.
export const vignetteProven = r => !!r && r.v === VIGNETTE_PROOF_VERSION && r.ok === true && r.tier === 'proven';
/// Whether it passed every check but rests on a rule not yet signed off:
/// the Checked tier at most.
export const vignetteChecked = r => !!r && r.v === VIGNETTE_PROOF_VERSION && r.ok === true && r.tier === 'checked';

/// What each refusal means, for the student (accuracy.js reasons).
export const VIGNETTE_REASONS = Object.freeze({
  packet: 'Its step-by-step proof could not be read.',
  mcq: 'Its step-by-step proof could not be read.',
  stale: 'Its step-by-step proof was written for another version of it.',
  span: 'A finding its proof names is not written that way in the question.',
  unreadable: 'A finding its proof names could not be read for certain.',
  cue: 'A finding its proof names is negated, hedged, about someone else, in the past or only planned.',
  lexicon: 'A finding is not worded the way a published rule words it.',
  conflict: 'The question mentions a finding its proof leaves out.',
  rule: 'Its proof uses a rule that has not passed review.',
  licence: "Its proof rests on a source whose licence doesn't allow commercial use.",
  grade: 'Its proof rests on a source below a published guideline or label.',
  judgment: 'A published rule needs a clinical judgment here, which a proof cannot make.',
  fires: 'The findings do not meet every criterion of the published rule.',
  together: 'The findings the rule needs are not stated together.',
  asks: 'The question does not ask what the published rule decides.',
  conclusion: "The published rule's conclusion is not its keyed answer.",
  options: 'Its options cannot each be read for certain.',
  distractor: 'An option could not be ruled out by a published rule.',
  explanation: 'Its explanation says more than the published rules do.',
  budget: 'Its step-by-step proof was too long to check.',
  error: 'Its step-by-step proof could not be checked.',
});
