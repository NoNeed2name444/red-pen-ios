// The registry review: whether a rule (or a quoted lexicon entry) may enter
// server/criteria/registry.js and so be used by the vignette checker
// (vignette-proof.js). The owner's rule, 14 Oct, in code:
//
//   a  two independent transcriptions of the rule agree exactly (their
//      formal parts compared as canonical JSON), and the rule is that
//   b  every quote it rests on - each criterion, each list item with its
//      lead-in, its conclusion, its worked examples - is in its source word
//      for word: character for character once whitespace is collapsed, and
//      as proof.js normalizes it, in the snapshot whose SHA-256 the source
//      registry pins
//   c  the source's own worked examples pass: each example's question,
//      option and answer-key entry are quoted from the source, the answer key
//      gives the option's letter, and the rule evaluates every case the
//      example sets as the example says
//
// plus: a source whose licence allows commercial use and is not StatPearls
// (licenceAllows), of the top grade, current; numbers read back from the
// criterion's own words ("5 or more millimeters" is >= 5 mm); a conclusion's
// aliases in the rule's own words, and an excluded outcome only as its plain
// opposite ("negative" for "positive").
//
// A rule that passes enters as reviewed: it may back the Checked tier. It
// backs Verified only once the owner signs it off (signedOffHash: the hash
// this review stamps). A rule that fails stays out, with its reason, in the
// registry's `pending` list. Pure: the snapshots are passed in.

import { normalize } from '../proof.js';
import { SLOTS, ASKS } from '../lexicon.js';
import { sha256, canonical, ruleHash, lexiconHash, licenceAllows, ruleSourceAllows, readSays, evaluateRule } from '../vignette-proof.js';

const collapse = t => String(t ?? '').replace(/\s+/g, ' ').trim();
// a bullet proof.js cannot read; a numbered item's number it can, and a
// quote may hold it ("3. For the following groups")
const MARKER = /^\s*(?:[•◦▪●‣∙·*]|-(?=\s))?\s*/;

/// The snapshot's words as proof.js reads them: line by line, list markers
/// off, a line it cannot read a break no quote may cross.
function streamOf(text) {
  const out = [];
  for (const line of String(text).split('\n')) {
    const n = normalize(line.replace(MARKER, ''));
    if (n) out.push(...n);
    else out.push('\u0000');
  }
  return out;
}
const streams = new WeakMap();
const streamFor = snap => {
  if (!streams.has(snap)) streams.set(snap, ` ${streamOf(snap.text).join(' ')} `);
  return streams.get(snap);
};

/// Whether `quote` is in a snapshot word for word: the same characters once
/// whitespace is collapsed, and the same proof.js tokens in a row.
export function quotedIn(quote, snap) {
  const q = collapse(quote);
  if (!q || !snap || typeof snap.text !== 'string') return false;
  if (!collapse(snap.text).includes(q)) return false;
  const n = normalize(q);
  return !!n && n.length > 0 && streamFor(snap).includes(` ${n.join(' ')} `);
}

/// Whether `quote` is whole where it stands: a whole line of the snapshot,
/// or whole sentences of one (from a line's start or after a sentence's end,
/// to a sentence's end) - never cut short, where a cut could drop a "not" or
/// a qualifier.
export function wholeIn(quote, snap) {
  const q = collapse(quote);
  if (!q || !snap) return false;
  for (const raw of String(snap.text).split('\n')) {
    const line = collapse(raw);
    for (let at = line.indexOf(q); at >= 0; at = line.indexOf(q, at + 1)) {
      const end = at + q.length;
      const starts = at === 0 || /[.:;?!)]\s$/.test(line.slice(0, at));
      const ends = end === line.length || (/[.:;?!]\)?$/.test(q) && /^\s/.test(line.slice(end)));
      if (starts && ends) return true;
    }
  }
  return false;
}

/// Whether `item` is a whole element of a list written inline in `quote`
/// ("necrosis, blistering, anaphylactic shock, or ulcerations"): not part of
/// one ("shock" of "anaphylactic shock").
export function inlineItem(item, quote) {
  const q = collapse(quote);
  const it = collapse(item);
  if (!it) return false;
  for (let at = q.indexOf(it); at >= 0; at = q.indexOf(it, at + 1)) {
    const before = q.slice(0, at);
    const after = q.slice(at + it.length);
    if ((at === 0 || /(?:\(e\.g\.,? |\(|, |\bor |\band )$/.test(before)) && (!after || /^(?:,|\)|\.| or\b| and\b| to\b)/.test(after))) return true;
  }
  return false;
}

/// Whether `quote` is a whole line of the snapshot.
export const lineIn = (quote, snap) => !!snap && String(snap.text).split('\n').some(l => l.trim() === collapse(quote));

/// Whether list item `item` comes under `leadIn` (both whole lines, the item
/// after the lead-in, and no other lead-in - a line ending in a colon -
/// between them).
export function underLeadIn(item, leadIn, snap) {
  if (!snap) return false;
  const lines = String(snap.text).split('\n').map(l => l.trim());
  for (let i = 0; i < lines.length; i++) {
    if (lines[i] !== collapse(leadIn)) continue;
    for (let j = i + 1; j < lines.length; j++) {
      if (lines[j] === collapse(item)) return true;
      if (lines[j].endsWith(':')) break;
    }
  }
  return false;
}

const tok = t => {
  const n = normalize(String(t ?? ''));
  return n ? n.join(' ') : null;
};
const within = (hay, needle) => !!hay && !!needle && ` ${hay} `.includes(` ${needle} `);

/// Plain opposites an excluded outcome may be: not a medical fact, only the
/// other side of the conclusion's own word.
export const OPPOSITES = Object.freeze({ positive: 'negative', present: 'absent', reactive: 'nonreactive', indicated: 'not indicated' });

const OPS = new Set(['present', 'anyOf', '>=', '>', '<=', '<', 'between', 'judgment']);
const NUMERIC_OPS = ['>=', '>', '<=', '<', 'between'];
/// The forms of conclusion a rule's `says` may take, each giving the answer
/// it names.
export const CONCLUDES = Object.freeze([/^(?:is|are) considered (.+)$/i, /^(.+?) should be used$/i, /^(.+?) (?:is|are) contraindicated$/i, /^confirms the diagnosis of (.+)$/i]);
const ANSWER_KEY = /^Chapter (\d+): ((?:\d+\. [A-E](?:, [A-E])* ?)+)$/;

const no = (why, detail) => ({ ok: false, why, detail: String(detail ?? '').slice(0, 300) });

/// Whether `rule` passes review. `ctx`: {sources: id -> source entry,
/// snapshots: id -> {text}}. {ok, hash} or {ok: false, why, detail}.
export function reviewRule(rule, ctx) {
  const { sources = {}, snapshots = {} } = ctx || {};
  // shape
  if (!rule || typeof rule !== 'object' || !/^[a-z0-9-]{3,80}$/.test(rule.id || '')) return no('shape', 'id');
  if (!['criteria', 'denial'].includes(rule.kind)) return no('shape', 'kind');
  if (typeof rule.version !== 'string' || !rule.version) return no('shape', 'version');
  const f = rule.formal;
  if (!f || !Array.isArray(f.criteria) || !f.criteria.length || !f.conclusion) return no('shape', 'formal');
  const ids = new Set();
  for (const c of f.criteria) {
    if (!c || typeof c.id !== 'string' || ids.has(c.id) || typeof c.slot !== 'string' || !OPS.has(c.op) || typeof c.quote !== 'string') return no('shape', `criterion ${c?.id}`);
    ids.add(c.id);
  }
  // the source: licence, grade, edition
  const src = sources[rule.source];
  if (!src) return no('source', rule.source);
  if (!licenceAllows(src)) return no('licence', `${src.id}: no licence on record that allows commercial use`);
  if (!ruleSourceAllows(src)) return no('grade', `${src.id} is a ${src.type}${src.status !== 'current' ? `, ${src.status}` : ''}: a rule rests only on a current guideline, systematic review or label`);
  const snapOf = id => {
    const s = sources[id];
    const snap = snapshots[id];
    if (!s?.snapshot || !snap || sha256(snap.text) !== s.snapshot.sha256) return null;
    return snap;
  };
  const snap = snapOf(rule.source);
  if (!snap) return no('snapshot', `${rule.source}: no snapshot, or not the pinned one`);
  // each criterion reads a lexicon slot of its kind, in the slot's unit
  for (const c of f.criteria) {
    const slot = SLOTS[c.slot];
    if (c.op === 'judgment') continue;
    if (!slot) return no('slot', `${c.id}: no lexicon slot ${c.slot}`);
    const fits = slot.type === 'flag' ? c.op === 'present' : slot.type === 'set' ? c.op === 'anyOf' : NUMERIC_OPS.includes(c.op) && c.unit === slot.unit;
    if (!fits) return no('slot', `${c.id}: ${c.op}${c.unit ? ` ${c.unit}` : ''} does not read a ${slot.type} slot (${c.slot})`);
  }
  const used = new Set(f.criteria.map(c => c.slot));
  for (const g of f.together || []) {
    if (!Array.isArray(g) || g.length < 2 || g.some(x => !used.has(x))) return no('shape', 'together: slots the rule reads');
  }
  // b: every quote word for word, and whole (a sentence or a line)
  const quote = (q, where, s = snap) => (quotedIn(q, s) ? null : no('quote', `${where}: "${collapse(q).slice(0, 120)}" is not in ${rule.source} word for word`));
  const whole = (q, where) => (wholeIn(q, snap) ? null : no('quote', `${where}: "${collapse(q).slice(0, 120)}" is cut short of its sentence`));
  for (const c of f.criteria) {
    const bad = quote(c.quote, c.id) || whole(c.quote, c.id) || (c.leadIn ? whole(c.leadIn, `${c.id} lead-in`) : null);
    if (bad) return bad;
    if (c.op === 'anyOf') {
      if (!Array.isArray(c.values) || !c.values.length || !c.items || c.values.some(v => typeof c.items[v] !== 'string')) return no('shape', `${c.id}: every value needs its item`);
      for (const v of c.values) {
        if (c.leadIn) {
          if (!underLeadIn(c.items[v], c.leadIn, snap)) return no('quote', `${c.id}: "${c.items[v]}" is not a line under "${c.leadIn}"`);
        } else if (!within(tok(c.quote), tok(c.items[v])) || !inlineItem(c.items[v], c.quote)) return no('quote', `${c.id}: "${c.items[v]}" is not an item of its quote`);
      }
    }
    if (['>=', '>', '<=', '<', 'between'].includes(c.op)) {
      // the number from the criterion's own words, never typed in alone
      const said = readSays(c.says);
      if (!said || !within(tok(c.quote), tok(c.says)) || !collapse(c.quote).includes(collapse(c.says))) return no('number', `${c.id}: "${c.says}" is not read from its quote`);
      if (said.op !== c.op || canonical(said.value) !== canonical(c.value) || said.unit !== c.unit) return no('number', `${c.id}: its words say ${said.op} ${canonical(said.value)} ${said.unit}`);
    }
  }
  const con = f.conclusion;
  if (typeof con.quote !== 'string' || !Array.isArray(con.aliases) || !con.aliases.length) return no('shape', 'conclusion');
  const badCon = quote(con.quote, 'conclusion') || whole(con.quote, 'conclusion');
  if (badCon) return badCon;
  if (typeof con.says !== 'string' || !collapse(con.quote).includes(collapse(con.says)) || !within(tok(con.quote), tok(con.says))) return no('quote', 'conclusion: its words are not in its quote');
  // the answer it gives is read from those words by their grammar, never
  // typed in alone: "is considered positive" gives "Positive"
  const form = CONCLUDES.map(re => re.exec(collapse(con.says))).find(Boolean);
  if (!form || !tok(form[1])) return no('alias', `conclusion: "${con.says}" is not a form of conclusion the review reads`);
  for (const a of con.aliases) if (tok(a) !== tok(form[1])) return no('alias', `"${a}" is not what "${con.says}" concludes`);
  if (rule.kind === 'criteria' && (!Array.isArray(con.asks) || !con.asks.length || con.asks.some(a => !tok(a)))) return no('shape', 'conclusion: what question it answers');
  // what a question may ask is the lexicon's fixed list, not a rule's own
  for (const a of con.asks || []) if (!ASKS.includes(a)) return no('asks', `"${a}" is not a question the lexicon knows`);
  // an option it names must be in the rule's own words
  const words = [con.quote, ...f.criteria.flatMap(c => [c.quote, ...Object.values(c.items || {})])].map(tok).filter(Boolean);
  for (const a of con.aliases) if (!tok(a) || !words.some(w => within(w, tok(a)))) return no('alias', `"${a}" is not in the rule's own words`);
  for (const x of f.exclusive || []) {
    if (!Array.isArray(x.aliases) || !x.aliases.length) return no('shape', 'exclusive');
    for (const a of x.aliases) {
      const opposite = con.aliases.some(c => OPPOSITES[tok(c)] === tok(a));
      if (!opposite) return no('alias', `"${a}" is not the plain opposite of the conclusion`);
    }
  }
  // a: two independent transcriptions, exactly the same
  const ts = rule.transcriptions;
  if (!Array.isArray(ts) || ts.length < 2) return no('transcription', 'two transcriptions are needed');
  const by = new Set(ts.map(t => String(t?.by || '').trim()));
  if (by.size < ts.length || by.has('')) return no('transcription', 'each transcription needs its own transcriber');
  const want = canonical(f);
  for (const [i, t] of ts.entries()) {
    if (canonical(t.formal) !== want) return no('transcription', `transcription ${i + 1} (${t.by}) differs from the rule`);
  }
  // c: the source's worked examples
  const ex = rule.examples;
  if (!Array.isArray(ex) || !ex.length) return no('example', 'the source gives no worked example of it');
  for (const [i, e] of ex.entries()) {
    const esrc = sources[e.source];
    if (!licenceAllows(esrc)) return no('licence', `example ${i + 1}: ${e.source}`);
    const esnap = snapOf(e.source);
    if (!esnap) return no('snapshot', `example ${i + 1}: ${e.source}`);
    for (const q of [e.question, e.option, e.answer, ...(e.givens || [])]) {
      const bad = quote(q, `example ${i + 1}`, esnap);
      if (bad) return bad;
    }
    if (e.format !== 'answer-key') return no('example', `example ${i + 1}: unknown format`);
    const m = ANSWER_KEY.exec(collapse(e.answer));
    const last = m ? /(\d+)\. ([A-E](?:, [A-E])*) ?$/.exec(m[2]) : null;
    if (!m || +m[1] !== e.chapter || !last || +last[1] !== e.number || last[2] !== e.key) return no('example', `example ${i + 1}: the answer key does not give ${e.key} for ${e.chapter}.${e.number}`);
    if (!collapse(e.question).startsWith(`${e.number}. `) || !collapse(e.option).startsWith(`${e.key}. `)) return no('example', `example ${i + 1}: question or option misnumbered`);
    if (!Array.isArray(e.cases) || !e.cases.length) return no('example', `example ${i + 1}: no case`);
    for (const [j, c] of e.cases.entries()) {
      const got = evaluateRule(rule, (c.facts || []).map(x => ({ slot: x.slot, value: x.value }))).fires;
      if (got !== c.fires) return no('example', `example ${i + 1}, case ${j + 1}: the rule ${got ? 'fires' : 'does not fire'}, the source says it ${c.fires ? 'does' : "doesn't"}`);
    }
  }
  return { ok: true, hash: ruleHash(rule) };
}

/// Whether a quoted lexicon entry passes review: its source allowed, its
/// quote word for word in the pinned snapshot, holding both the form and the
/// rule word it stands for.
export function reviewLexicon(entry, ctx) {
  const { sources = {}, snapshots = {} } = ctx || {};
  const b = entry?.backing;
  if (!entry?.id || b?.kind !== 'quoted') return no('shape', entry?.form);
  const src = sources[b.source];
  if (!licenceAllows(src)) return no('licence', b.source);
  const snap = snapshots[b.source];
  if (!snap || sha256(snap.text) !== src.snapshot?.sha256) return no('snapshot', b.source);
  if (!quotedIn(b.quote, snap)) return no('quote', `"${collapse(b.quote).slice(0, 120)}" is not in ${b.source} word for word`);
  const q = tok(b.quote);
  if (!within(q, tok(entry.form)) || !within(q, tok(b.canonical))) return no('backing', `its quote does not name both "${entry.form}" and "${b.canonical}"`);
  return { ok: true, hash: lexiconHash(entry) };
}
