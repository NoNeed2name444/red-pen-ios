// Source proof, for the accuracy checker's Verified grade.
//
// The owner's rule: an item is Verified only when an official source states
// each of its facts word for word. Models agreeing is never proof. So this
// file proves by text, not by meaning: a claim is proven when, after the same
// normalization on both sides, its whole token sequence equals one statement
// in a current FDA label (openFDA) or a MedlinePlus topic page.
//
// A statement only counts when it stands on its own:
//   - a list item counts only with its lead-in ("contraindicated in patients
//     with: ... severe renal impairment"), never alone
//   - the words of the heading it sits under must be in the claim, so a dose
//     under "Pediatric Dosage" never proves an adult dose
//   - a population heading or sentence (renal, hepatic, children, older
//     adults, pregnancy...) cuts off what follows it
//   - a sentence followed by "However", "Except", "This does not ..." and the
//     like is qualified, so it proves nothing
// The claim must name the drug (FDA) or the topic (MedlinePlus). Anything that
// cannot be read for certain (superscripts, unknown symbols, cut text) is
// unprovable, never proven. Europe PMC is evidence for the models, not proof.
//
// A question is proven only when, besides its key, no source may state
// another of its options. That check is loose where proof is strict: a
// source may put an option in its own words, so any sentence with each word
// that tells the option apart, in any order, may state it.

export const PROOF_VERSION = 2;

// Normalization ---------------------------------------------------------------

// a superscript or subscript sign, or a digit run into a superscript digit
// (10⁹ is not 109): the text cannot be read for certain
const UNSAFE = /[⁺-⁾₊-₎]|\d[²³¹⁰-⁹₀-₉]/;
// a power of ten whose superscript was lost or spelled out: "× 10(9)/L",
// "x 109/L", "10 9/L", "10[-3]", "2e-3" (109 is not 10⁹): unreadable for certain
const POWER = /(?<![a-z])[x×*]\s*10\s*(?:[([]\s*[-\u2010-\u2015\u2212]?\d{1,2}\s*[)\]]|[-\u2010-\u2015\u2212]?\d{1,2}\s*(?=\/)|[-\u2010-\u2015\u2212]\s*\d)|\b10\s+[-\u2010-\u2015\u2212]?\d{1,2}\s*\/|\b10\s*[([]\s*[-\u2010-\u2015\u2212]?\d{1,2}\s*[)\]]|\d\s?e[+\-\u2212]?\d/i;

// lookups by a text's word: with no prototype, "constructor" is no key
const dict = o => Object.freeze(Object.assign(Object.create(null), o));

const GREEK = dict({
  α: 'alpha', β: 'beta', γ: 'gamma', δ: 'delta', ε: 'epsilon', ζ: 'zeta', η: 'eta', θ: 'theta',
  ι: 'iota', κ: 'kappa', λ: 'lambda', μ: 'mu', ν: 'nu', ξ: 'xi', ο: 'omicron', π: 'pi', ρ: 'rho',
  σ: 'sigma', ς: 'sigma', τ: 'tau', υ: 'upsilon', φ: 'phi', χ: 'chi', ψ: 'psi', ω: 'omega',
});
const LIGATURES = dict({ ß: 'ss', æ: 'ae', œ: 'oe', ø: 'o', ł: 'l', ı: 'i', đ: 'd', ð: 'd', þ: 'th' });

const CONTRACTIONS = [
  [/\bcan't\b|\bcannot\b/g, 'can not'],
  [/\bwon't\b/g, 'will not'],
  [/\bshan't\b/g, 'shall not'],
  [/n't\b/g, ' not'],
  [/'re\b/g, ' are'],
  [/'ve\b/g, ' have'],
  [/'ll\b/g, ' will'],
  [/\bi'm\b/g, 'i am'],
  [/\b(it|that|there|what|here|who|where|he|she)'s\b/g, '$1 is'],
  [/\blet's\b/g, 'let us'],
  [/'s\b/g, ''],
  [/s'(?![a-z])/g, 's'],
];

// signs read as words, in one pass: where two can match at one place the
// longer is tried first (">=" before ">"), and no word put in has a sign
const SYMBOL = /\band\/or\b|\bper\s+cent\b|>=|<=|\+\/?-|[&%≥⩾≤⩽±<>~≈=×+/°]/g;
const SYMBOL_WORDS = dict({
  'and/or': ' andor ', '&': ' and ', '%': ' percent ', '≥': ' gte ', '⩾': ' gte ', '>=': ' gte ',
  '≤': ' lte ', '⩽': ' lte ', '<=': ' lte ', '±': ' plusminus ', '+/-': ' plusminus ', '+-': ' plusminus ',
  '<': ' lt ', '>': ' gt ', '~': ' approx ', '≈': ' approx ', '=': ' equals ', '×': ' times ', '+': ' plus ',
  '/': ' per ', '°': '',
});
// "per cent", with whatever space between, is the one match not listed
const symbolWord = m => SYMBOL_WORDS[m] ?? ' percent ';

const DASHES = /[‐-―−⁃﹘﹣－]/g;
// a character (or "cent") SYMBOL needs
const MAY_SYMBOL = /[/&%≥⩾>≤⩽<±+~≈=×°]|cent/;
const ORDINALS = ['first', 'second', 'third', 'fourth', 'fifth', 'sixth', 'seventh', 'eighth',
  'ninth', 'tenth', 'eleventh', 'twelfth'];
const NUMBER_WORDS = dict({ one: '1', two: '2', three: '3', four: '4', five: '5', six: '6', seven: '7',
  eight: '8', nine: '9', ten: '10', eleven: '11', twelve: '12' });

const BRITISH_WORDS = dict({
  ageing: 'aging', programme: 'program', catalogue: 'catalog', dialogue: 'dialog', analogue: 'analog',
  grey: 'gray', aluminium: 'aluminum', manoeuvre: 'maneuver', licence: 'license', defence: 'defense',
  offence: 'offense', judgement: 'judgment', enrolment: 'enrollment', fulfil: 'fulfill', instil: 'instill',
});
const BRITISH_PARTS = [['aemi', 'emi'], ['haem', 'hem'], ['oesophag', 'esophag'], ['oedem', 'edem'],
  ['oestr', 'estr'], ['paed', 'ped'], ['gynaec', 'gynec'], ['rhoe', 'rhe'], ['pnoe', 'pne'],
  ['anaesth', 'anesth'], ['leuc', 'leuk'], ['sulph', 'sulf'], ['faec', 'fec']];
const BRITISH_STARTS = [['foet', 'fet'], ['coeliac', 'celiac'], ['aetio', 'etio'], ['caesar', 'cesar']];
// the stems british() respells: -our to -or, -re to -er, a doubled l to one
const OUR = 'tum|col|behavi|lab|od|hum|vap|fav';
const RE = 'lit|millilit|cent|fib|met|centimet|millimet';
const LLED = 'label|model|cancel|counsel|signal|travel|fuel|total|channel|tunnel|level|equal';
const OUR_AT = new RegExp(`^(${OUR})our`);
const RE_AT = new RegExp(`^(${RE})re$`);
const LLED_AT = new RegExp(`^(${LLED})l(ed|ing)$`);

export const isNum = w => /^\d+(?:\.\d+)?$/.test(w);
const NON_ASCII = /[^\x00-\x7f]/;
// past ASCII, what normalizeWords reads once the text is plain (plainUnicode):
// spaces, Greek letters, the LIGATURES, quotes, the SYMBOL signs and dashes.
// Any other sign stays to the end, where the text is found unreadable
const UNREAD = /[^\x00-\x7f\s\u0370-\u03ffßæœøłıđðþ‘’‚‛′ʼ“”„‟″≥⩾≤⩽±≈×°‐-―−⁃﹘﹣－]/;
// a letter a Greek letter's name would run into (NaN past either end)
const wordy = c => (c >= 0x61 && c <= 0x7a) || (c >= 0x370 && c <= 0x3ff);

function plural(w) {
  if (w === 'days') return 'day';
  if (w.length > 5 && w.endsWith('ies')) return w.slice(0, -3) + 'y';
  if (w.length > 4 && w.endsWith('s') && !/(?:ss|us|is)$/.test(w)) return w.slice(0, -1);
  return w;
}

function british(w) {
  if (BRITISH_WORDS[w]) return BRITISH_WORDS[w];
  for (const [a, b] of BRITISH_PARTS) if (w.includes(a)) w = w.split(a).join(b);
  for (const [a, b] of BRITISH_STARTS) if (w.startsWith(a)) w = b + w.slice(a.length);
  w = w.replace(OUR_AT, '$1or').replace(RE_AT, '$1er').replace(LLED_AT, '$1$2');
  if (w.length > 5) w = w.replace(/is(e|ed|ing|ation|er)$/, 'iz$1').replace(/ys(e|ed|ing)$/, 'yz$1');
  return w;
}

// Phrases that say the same thing in other words ------------------------------

const COMPARE = [
  ['greater than or equal to', 'gte'], ['more than or equal to', 'gte'],
  ['equal to or greater than', 'gte'], ['equal to or more than', 'gte'], ['at least', 'gte'],
  ['no less than', 'gte'], ['not less than', 'gte'], ['no fewer than', 'gte'], ['not fewer than', 'gte'],
  ['less than or equal to', 'lte'], ['fewer than or equal to', 'lte'], ['equal to or less than', 'lte'],
  ['no more than', 'lte'], ['not more than', 'lte'], ['at most', 'lte'], ['not exceeding', 'lte'],
  ['not to exceed', 'lte'], ['no greater than', 'lte'], ['not greater than', 'lte'],
  ['in excess of', 'gt'], ['greater than', 'gt'], ['more than', 'gt'], ['higher than', 'gt'],
  ['exceeding', 'gt'], ['above', 'gt'],
  ['less than', 'lt'], ['lower than', 'lt'], ['fewer than', 'lt'], ['below', 'lt'], ['under', 'lt'],
  ['approximately', 'approx'], ['about', 'approx'], ['around', 'approx'], ['roughly', 'approx'],
  ['approx', 'approx'], ['circa', 'approx'],
].map(([p, op]) => [p.split(' '), op]).sort((a, b) => b[0].length - a[0].length);
// by first word, each list still longest first
const COMPARE_AT = new Map();
for (const c of COMPARE) COMPARE_AT.set(c[0][0], [...(COMPARE_AT.get(c[0][0]) || []), c]);

const OR_MORE = dict({ more: 'gte', greater: 'gte', higher: 'gte', above: 'gte',
  less: 'lte', fewer: 'lte', lower: 'lte', below: 'lte' });
const TIMES = dict({ once: '1', twice: '2', thrice: '3' });
const UNIT_ALIAS = dict({
  milligram: 'mg', ug: 'mcg', microgram: 'mcg', gram: 'g', gm: 'g', kilogram: 'kg',
  milliliter: 'ml', liter: 'l', mcl: 'ul', microliter: 'ul', milliequivalent: 'meq',
  millimole: 'mmol', micromole: 'umol', u: 'unit', hr: 'hour', hrs: 'hour', h: 'hour',
  min: 'minute', mins: 'minute', sec: 'second', secs: 'second', d: 'day', wk: 'week', wks: 'week',
  mo: 'month', mos: 'month', yr: 'year', yrs: 'year',
});
const TIME_UNITS = new Set(['hour', 'minute', 'second', 'day', 'week', 'month', 'year']);
const UNITS = new Set(['mg', 'mcg', 'g', 'kg', 'ml', 'l', 'ul', 'meq', 'mmol', 'umol', 'unit', 'iu',
  ...TIME_UNITS, 'tablet', 'capsule', 'puff', 'drop', 'spray', 'patch', 'vial', 'sachet', 'dose']);
const ROUTES = dict({
  po: 'po', oral: 'po', orally: 'po', iv: 'iv', intravenou: 'iv', intravenous: 'iv', intravenously: 'iv',
  im: 'im', intramuscular: 'im', intramuscularly: 'im', sc: 'sc', subcutaneou: 'sc', subcutaneous: 'sc',
  subcutaneously: 'sc', subcut: 'sc', subq: 'sc', sq: 'sc', sl: 'sl', sublingual: 'sl', sublingually: 'sl',
});
const ROUTE_SET = new Set(Object.values(ROUTES));
const ABBREV_FREQ = dict({ od: 'freq1d', qd: 'freq1d', bid: 'freq2d', bd: 'freq2d', tid: 'freq3d',
  tds: 'freq3d', qid: 'freq4d', qds: 'freq4d' });
const WHO = new Set(['patient', 'people', 'person', 'individual', 'those', 'anyone']);
const INERT = new Set(['the', 'is', 'are', 'of', 'also', 'patient', 'usp']);

const unitOf = w => UNIT_ALIAS[w] || w;
// a number, of the words compared (a number or letters, never empty)
const num = w => w !== undefined && w.charCodeAt(0) < 0x3a;
// the words phrases may read as more than themselves: any other word is kept
// as it is (an INERT one dropped), and so is a number not followed by "time"
const PHRASE_WORDS = new Set([...COMPARE_AT.keys(), 'or', ...Object.keys(TIMES), 'every', 'as', 'by', 'per',
  ...Object.keys(ROUTES), ...Object.keys(ABBREV_FREQ), 'daily', 'weekly', 'a', 'each', 'international',
  ...Object.keys(UNIT_ALIAS), 'in', 'for']);

/// daily / weekly / a, per, each or every day / week at i: [d|w, tokens used]
function period(t, i) {
  if (t[i] === 'daily') return ['d', 1];
  if (t[i] === 'weekly') return ['w', 1];
  const w = t[i];
  if ((w === 'a' || w === 'per' || w === 'each' || w === 'every') && (t[i + 1] === 'day' || t[i + 1] === 'week')) {
    return [t[i + 1][0], 2];
  }
  return null;
}

function phrases(t) {
  const out = [];
  const last = () => out[out.length - 1];
  const doseBefore = () => out.length > 0 && (num(last()) || UNITS.has(last()) || ROUTE_SET.has(last()));
  for (let i = 0; i < t.length;) {
    const w = t[i];
    if (num(w) ? t[i + 1] !== 'time' : !PHRASE_WORDS.has(w)) {
      if (!INERT.has(w)) out.push(w);
      i++;
      continue;
    }
    const at = COMPARE_AT.get(w);
    const cmp = at && at.find(([p]) => p.every((x, k) => t[i + k] === x));
    if (cmp && (num(t[i + cmp[0].length]) || TIMES[t[i + cmp[0].length]])) {
      out.push(cmp[1]);
      i += cmp[0].length;
      continue;
    }
    if (w === 'or' && OR_MORE[t[i + 1]] && t[i + 2] !== 'than') {
      // the number it is about: last, or before its unit
      const j = num(last()) ? out.length - 1 : num(out[out.length - 2]) && UNITS.has(last()) ? out.length - 2 : -1;
      if (j >= 0) {
        out.splice(j, 0, OR_MORE[t[i + 1]]);
        i += 2;
        continue;
      }
    }
    const n = TIMES[w] ? [TIMES[w], 1] : num(w) && t[i + 1] === 'time' ? [w, 2] : null;
    const p = n && period(t, i + n[1]);
    if (p) {
      out.push(`freq${n[0]}${p[0]}`);
      i += n[1] + p[1];
      continue;
    }
    if (w === 'every' && num(t[i + 1])) {
      let j = i + 2;
      const range = t[j] === 'to' && num(t[j + 1]) ? ['to', t[j + 1]] : [];
      j += range.length;
      if (TIME_UNITS.has(unitOf(t[j]))) {
        out.push('q', t[i + 1], ...range, unitOf(t[j]));
        i = j + 1;
        continue;
      }
    }
    if (w === 'as' && (t[i + 1] === 'needed' || t[i + 1] === 'required')) {
      out.push('prn');
      i += 2;
      continue;
    }
    if ((w === 'by' && t[i + 1] === 'mouth') || (w === 'per' && t[i + 1] === 'os')) {
      out.push('po');
      i += 2;
      continue;
    }
    if (ROUTES[w]) {
      out.push(ROUTES[w]);
      i++;
      continue;
    }
    if (ABBREV_FREQ[w] && doseBefore()) {
      out.push(ABBREV_FREQ[w]);
      i++;
      continue;
    }
    const pd = out.length > 0 && (UNITS.has(last()) || ROUTE_SET.has(last())) && period(t, i);
    if (pd) {
      out.push('per', pd[0] === 'd' ? 'day' : 'week');
      i += pd[1];
      continue;
    }
    if (out.length > 0 && (num(last()) || last() === 'per')) {
      if (w === 'international' && t[i + 1] === 'unit') {
        out.push('iu');
        i += 2;
        continue;
      }
      if (UNIT_ALIAS[w]) {
        out.push(UNIT_ALIAS[w]);
        i++;
        continue;
      }
    }
    if ((w === 'in' || w === 'for')) {
      let j = i + 1;
      if (t[j] === 'a') j++;
      if (WHO.has(t[j])) {
        const k = j + 1;
        const end = t[k] === 'with' || t[k] === 'having' ? k + 1
          : t[k] === 'who' && (t[k + 1] === 'have' || t[k + 1] === 'has') ? k + 2 : 0;
        if (end) {
          out.push(w);
          i = end;
          continue;
        }
      }
    }
    if (!INERT.has(w)) out.push(w);
    i++;
  }
  return out;
}

/// The token sequence two texts are compared by, or null when the text cannot
/// be read for certain. Both the claim and the source go through this.
export function normalize(text) {
  const w = normalizeWords(text);
  return w && phrases(w);
}

// letters joined by dots, read as one word ("e.g." is eg, "b.i.d." bid)
const DOT_JOIN = /\b[a-z](?:\.[a-z])+\.?(?![a-z])/g;

/// The words of a text, spelled one way, before the phrase pass.
export function normalizeWords(text) {
  if (typeof text !== 'string' || UNSAFE.test(text) || POWER.test(text)) return null;
  let s = text.toLowerCase();
  // the Unicode passes change nothing in plain ASCII
  if (NON_ASCII.test(text)) {
    s = plainUnicode(text);
    // again once wide digits and hidden marks are plain
    if (UNSAFE.test(s) || POWER.test(s) || UNREAD.test(s)) return null;
    s = s.replace(/[Ͱ-Ͽ]/g, (c, i, all) => {
      const name = GREEK[c];
      if (!name) return '\u0000';
      const before = wordy(all.charCodeAt(i - 1)) ? ' ' : '';
      const after = wordy(all.charCodeAt(i + 1)) ? ' ' : '';
      return before + name + after;
    });
    s = s.replace(/[ßæœøłıđðþ]/g, c => LIGATURES[c]);
  }
  s = s.replace(/[‘’‚‛′ʼ`]/g, "'").replace(/[“”„‟″]/g, '"');
  // "he'd" is "he had" or "he would": unreadable for certain
  if (/[a-z]'d\b/.test(s)) return null;
  // each group of passes only where one of them can match
  if (s.includes("'") || s.includes('cannot')) for (const [re, to] of CONTRACTIONS) s = s.replace(re, to);
  if (MAY_SYMBOL.test(s)) s = s.replace(SYMBOL, symbolWord);
  s = s.replace(DASHES, '-');
  if (s.includes('-')) {
    s = s.replace(/(\d)\s*-\s*(?=\d)/g, '$1 to ')
      .replace(/(^|[\s([])-(?=\d)/g, '$1minus ')
      .replace(/\b([a-z0-9]+)-(?=[\s)\],.;:!?]|$)/g, '$1 minus ').replace(/-/g, ' ');
  }
  // anything left that is not a letter, digit, space or plain punctuation is
  // a sign this file does not know
  if (/[^a-z0-9\s.,;:!?()[\]"']/.test(s)) return null;
  if (s.includes('.')) s = s.replace(DOT_JOIN, m => m.replace(/\./g, ''));
  if (/\d/.test(s)) {
    s = s.replace(/\b(\d+)(?:st|nd|rd|th)\b/g, (_, n) => ' ' + (ORDINALS[+n - 1] || n + ' ordinal') + ' ');
    // thousands commas, every one at once ("1,000,000,000")
    s = s.replace(/(?<=\d),(?=\d{3}(?!\d))/g, '');
    s = s.replace(/(^|[^\d])\.(\d)/g, (_, a, d) => a + '0.' + d);
    // (what is kept of the fraction ends in a digit not 0: "\d*?0+" tried every
    // way to split a long run of zeros, in time growing with its square)
    s = s.replace(/(?<![\d.])(\d+)\.(\d*[1-9])?0+(?!\d)/g, (_, a, b) => (b ? a + '.' + b : a));
    s = s.replace(/([a-z])(?=\d)/g, '$1 ').replace(/(\d)(?=[a-z])/g, '$1 ');
  }
  const raw = s.match(/\d+(?:\.\d+)?|[a-z]+/g) || [];
  return raw.map(spelled);
}

// signs the Unicode passes below leave as they are (no wide or joined form,
// no case, no mark): dashes, quotes, bullets, arrows, shapes, ≤ ≥ ± × °
export const KEPT_SIGNS = '§°±¶·×÷‐‒–—―‖‘’‚‛“”„‟†‡•‣‧‰′‵←↑→↓↔−∙≤≥■□▪▫▲►▼◄◆◇○●◦✓✔✗✘';
// what they drop (trademarks, hidden characters), and the spaces and the
// hyphen they make plain
const FIXED = /[®™©℠\u00ad\u200b-\u200d\u2060\ufeff\u00a0\u2000-\u200a\u2011\u202f\u205f\u3000]/g;
const DROP = '®™©℠\u00ad\u200b\u200c\u200d\u2060\ufeff';
const fixed = c => (c === '\u2011' ? '\u2010' : DROP.includes(c) ? '' : ' ');
// past ASCII: 0 a kept sign, 1 one to fix
const SHORT_WAY = new Map([...KEPT_SIGNS].map(c => [c.charCodeAt(0), 0]));
for (const c of DROP + '\u00a0\u2011\u202f\u205f\u3000') SHORT_WAY.set(c.charCodeAt(0), 1);
for (let c = 0x2000; c <= 0x200a; c++) SHORT_WAY.set(c, 1);

/// How the short way reads a text: 0 plainly, 1 with signs to fix first, -1
/// not at all (a character only the full passes read right).
function shortWay(text) {
  let way = 0;
  for (let i = 0; i < text.length; i++) {
    const c = text.charCodeAt(i);
    if (c < 0x80) continue;
    const w = SHORT_WAY.get(c);
    if (w === undefined) return -1;
    way |= w;
  }
  return way;
}

// a mark on a mark on a mark ("Zalgo" text): normalize puts a run of marks in
// order in time that grows with the square of its length. A run is of marks
// and of the two half-width sound marks that become marks, and the signs
// dropped on the way (FIXED's) do not end one.
const MARK_RUN = /[\p{M}\uff9e\uff9f](?:[®™©℠\u00ad\u200b-\u200d\u2060\ufeff]*[\p{M}\uff9e\uff9f]){8,}/gu;

/// Lower case with the marks, hidden characters and wide forms made plain
/// (normalizeWords names the Greek letters and spells out ligatures after).
/// Text with no other sign past ASCII than those above takes the short way
/// to the same result: most of a label's are bullets, dashes and quotes
/// (`full` takes the long way, for the tests). A run of more than eight marks
/// is cut ('\u0000', which normalizeWords cannot read).
export function plainUnicode(text, full = false) {
  const way = full ? -1 : shortWay(text);
  if (way >= 0) return (way ? text.replace(FIXED, fixed) : text).toLowerCase();
  return text.replace(MARK_RUN, '\u0000').replace(/[®™©℠]/g, '').normalize('NFKC').toLowerCase()
    .replace(/[\u00ad\u200b-\u200d\u2060\ufeff]/g, '')
    .replace(/μg/g, 'mcg').replace(/μ(?=[a-z])/g, 'u').replace(/μ/g, ' mu ')
    .normalize('NFKD').replace(/\p{M}/gu, '');
}

// a word as compared, kept: the same words come back sentence after sentence
const SPELLED = new Map();
function spelled(w) {
  if (w.charCodeAt(0) < 0x3a) return w;
  let v = SPELLED.get(w);
  if (v === undefined) {
    v = NUMBER_WORDS[w] || (w === 'an' ? 'a' : british(plural(w)));
    if (SPELLED.size >= 8192) SPELLED.clear();
    SPELLED.set(w, v);
  }
  return v;
}

// Word sets, compared with normalized words -----------------------------------

const words = s => new Set(s.split(' '));

const FUNCTION = words('a an the and or andor nor of in on at to for with by from as into onto than that '
  + 'which who whom whose is are was were be been being am has have had do does did may might can could will '
  + 'would shall should must if so per via also there');
// a word that points outside the sentence: the claim cannot stand alone
const PRONOUN = words('it its they them their this these those such he she his her former latter therefore '
  + 'thus hence however otherwise instead then consequently accordingly similarly likewise');
const DEICTIC = words('here shown pictured labelled labeled image picture diagram figure arrow');
const THOSE_NEXT = words('with who whose whom which that at in on aged taking receiving having over under');
const SALTS = words('hydrochloride hcl mesylate besylate maleate');
// heading words that never change what a statement under them means
const GENERIC = words('recommended recommendation dosage dose dosing general important administration '
  + 'instruction information adult usual and for in of use the warning precaution boxed indication usage '
  + 'contraindication adverse reaction highlight concomitant concurrent risk mechanism action form strength');
const SMALL = words('and or of for in with to the a an on by at from per vs versus without after before during not');
const LABEL_WORDS = words('key fact summary overview note review basic essential introduction intro definition '
  + 'main point important high yield revision quick lecture chapter topic part section module lesson guide '
  + 'cheat sheet mnemonic pearl clinical management treatment diagnosis pathophysiology pharmacology dosing dose '
  + 'outline recap study exam unit week feature sign symptom cause complication investigation therapy drug '
  + 'medicine medication physiology anatomy pathology epidemiology etiology presentation approach');
const GENERIC_NOUNS = words('drug medication medicine agent treatment therapy test investigation organism '
  + 'bacterium bacteria virus condition disease disorder diagnosis finding sign symptom structure nerve artery '
  + 'vein muscle bone hormone enzyme cell vitamin antibiotic option intervention procedure imaging modality '
  + 'class type factor complication cause feature organ gland receptor electrolyte lab value scan study dose '
  + 'route step management approach antibody mineral gene chromosome');
// words a subsection's body starts with, so the title ends before them
const STARTERS = words('swallow assess discontinue measure administer take give initiate start begin monitor use '
  + 'consider reduce increase decrease avoid obtain evaluate check titrate adjust instruct inform advise counsel '
  + 'withhold stop continue restart resume dilute reconstitute inject infuse apply store shake mix prepare '
  + 'inspect re the a in for if when patient there this these it treatment therapy before after during prior '
  + 'all each most some many based because although while as at on with no do not case postmarketing');

// who a statement is about: a statement under one of these is about them only
const POPULATION = /\b(?:pa?ediatric|child|children|adolescents?|infants?|neonat\w*|newborns?|geriatric|elderly|older|aged?|ages|renal|hepatic|kidneys?|liver|crcl|creatinine|e?gfr|pregnan\w*|lactation|lactating|breast\w*|nursing|dialysis|ha?emodialysis|weighing|weight|wom[ae]n|men|females?|males?|asians?|japanese|chinese|black|genotypes?|metaboli[sz]ers?|teens?|teenagers?|kids?|boys?|girls?|bab(?:y|ies)|toddlers?|youth|young|seniors?|smokers?)\b/gi;
const QUALIFIES = /^\W*(?:however|but|except|unless|although|though|only|nevertheless|nonetheless|yet|whereas|conversely|otherwise|exceptions?)\b/i;
const RESTRICT_START = /^\W*(?:this|these|that|those|such|it|they)\b/i;
const RESTRICT_WORD = /\b(?:not|no|never|only|except|unless|cannot|without)\b|n['’]t\b/i;

/// Whether the text names a population the anchor (the drug or the topic)
/// does not already name.
function popIn(text, anchor) {
  POPULATION.lastIndex = 0;
  for (let m; (m = POPULATION.exec(text));) {
    // the match is plain ASCII, which normalizes the same in any case
    const w = m[0].toLowerCase();
    let toks = POP_WORDS.get(w);
    if (toks === undefined) {
      toks = normalize(w);
      if (POP_WORDS.size >= 1024) POP_WORDS.clear();
      POP_WORDS.set(w, toks);
    }
    if (!toks || !toks.every(t => anchor.has(t))) return true;
  }
  return false;
}
const POP_WORDS = new Map();

/// Whether a sentence qualifies the one before it ("However, ...", "This
/// does not apply to ...", "These are not ...", "This is for children").
function qualifies(text, anchor) {
  return QUALIFIES.test(text) || (RESTRICT_START.test(text) && (RESTRICT_WORD.test(text) || popIn(text, anchor)));
}

/// A word in the claim points outside it ("it", "this drug", "shown here").
function anaphoric(w) {
  // an "if" or "when" before: "then" is that one's
  let cond = false;
  for (let i = 0; i < w.length; i++) {
    const x = w[i];
    if (x === 'if' || x === 'when') cond = true;
    if (!PRONOUN.has(x) && !DEICTIC.has(x)) continue;
    if (x === 'such' && w[i + 1] === 'as') continue;
    if (x === 'those' && THOSE_NEXT.has(w[i + 1])) continue;
    if (x === 'then' && cond) continue;
    if (x === 'shown' && w[i + 1] === 'to') continue;
    return true;
  }
  return false;
}

const content = toks => toks.filter(t => !FUNCTION.has(t));
/// The text as normalizeWords reads its letters and digits, for the cheap
/// checks before a full compare: whatever a word or number comes to there,
/// it is spelled the same here (the Greek letters stay, as separators).
const fold = s => (NON_ASCII.test(s) ? plainUnicode(s).replace(/[ßæœøłıđðþ]/g, c => LIGATURES[c]) : s.toLowerCase());
/// A whole section as a wrong option is looked for in it: folded, without
/// the degree signs, letters joined by dots run together. Each word
/// normalizeWords reads from it, but for the words it makes (MADE), is a run
/// of letters here, spelled the same up to british and plural.
const viewOf = t => fold(t).replace(/°/g, '').replace(DOT_JOIN, m => m.replace(/\./g, ''));

/// What a heading asks of a claim: its words, less the generic ones, the
/// anchor and salt names. null when the heading cannot be read.
function reqOf(text, anchor) {
  const toks = normalize(text);
  if (!toks) return null;
  return content(toks).filter(t => !GENERIC.has(t) && !anchor.has(t) && !SALTS.has(t));
}

// Sentences and markup --------------------------------------------------------

// a stop run is only ever taken whole, from its start: the lookbehind keeps a
// long run of dots from being tried at every one of them
const SENTENCE_END = /(?<![.!?])[.!?]+["')\]]*(?=\s+["'(\[]?[A-Z0-9•◦▪●]|\s*$)|;/g;
// the same, without the split at a semicolon: a sentence as a reader takes it
const STOP_END = /(?<![.!?])[.!?]+["')\]]*(?=\s+["'(\[]?[A-Z0-9•◦▪●]|\s*$)/g;
const NO_SPLIT = /(?:\b(?:e\.g|i\.e|vs|approx|yrs|hrs|dr|fig|al|no)|(?:^|[\s(.])[a-z])$/i;

/// A text's sentences, one at a time: a section is read only as far as its
/// purse goes.
function* sentences(text, ends = SENTENCE_END) {
  let from = 0;
  for (const m of text.matchAll(ends)) {
    // NO_SPLIT reads at most the last 7 characters ("approx" and the one before)
    if (m[0] !== ';' && NO_SPLIT.test(text.slice(Math.max(from, m.index - 9), m.index))) continue;
    const end = m.index + m[0].length;
    const piece = text.slice(from, end).trim();
    if (piece) yield piece;
    from = end;
  }
  const rest = text.slice(from).trim();
  if (rest) yield rest;
}

export function splitSentences(text) {
  return [...sentences(text)];
}

const BLOCK = words('p br div h1 h2 h3 h4 h5 h6 tr table dl dt dd blockquote section');
const INLINE = words('a b i em strong span u abbr small font cite code');
// a list nested deeper is not read: each item's bullets, one per level, would
// grow with the square of the nesting
const LIST_DEPTH = 8;
const ENTITIES = dict({ nbsp: ' ', amp: '&', lt: '<', gt: '>', quot: '"', apos: "'", mdash: '—', ndash: '–',
  hellip: '…', lsquo: '‘', rsquo: '’', ldquo: '“', rdquo: '”', deg: '°', micro: 'µ', plusmn: '±', ge: '≥',
  le: '≤', times: '×', reg: '', trade: '', copy: '', shy: '' });

/// The text less its comments, each "<!--" to the next "-->"; from one never
/// closed, the rest is left as it is.
function dropComments(s) {
  let out = '';
  let from = 0;
  for (let at; (at = s.indexOf('<!--', from)) >= 0;) {
    const end = s.indexOf('-->', at + 4);
    if (end < 0) break;
    out += s.slice(from, at);
    from = end + 3;
  }
  return out + s.slice(from);
}

/// MedlinePlus' summary (HTML, escaped once more inside the XML) as lines:
/// one per paragraph or heading, list items led by one "•" per level (a list
/// nested past LIST_DEPTH unreadable).
export function structuredText(html) {
  let s = String(html || '').replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"')
    .replace(/&apos;/g, "'").replace(/&amp;/g, '&');
  // a line break and the spaces around it: tried from the start of a run of
  // spaces only, not again from each of them
  s = dropComments(s).replace(/(?<!\s)\s*\n\s*/g, ' ');
  let depth = 0;
  // a tag ends at a ">": none starts past the last, and the text after it is
  // not read to its end from each "<" in it
  const tagged = s.lastIndexOf('>') + 1;
  s = s.slice(0, tagged).replace(/<(\/?)([a-z][a-z0-9]*)\b[^>]*>/gi, (_, close, tag) => {
    tag = tag.toLowerCase();
    if (tag === 'ul' || tag === 'ol') {
      depth = Math.max(0, depth + (close ? -1 : 1));
      return '\n';
    }
    if (tag === 'li') {
      if (close) return '\n';
      return depth > LIST_DEPTH ? '\n' + '•'.repeat(LIST_DEPTH) + ' \u0000' : '\n' + '•'.repeat(Math.max(1, depth)) + ' ';
    }
    if (BLOCK.has(tag)) return '\n';
    // 10<sup>9</sup> would read as 109: a line with a superscript or
    // subscript cannot be read for certain
    if (tag === 'sup' || tag === 'sub') return close ? '' : '\u0000';
    if (INLINE.has(tag)) return '';
    return ' ';
  }) + s.slice(tagged);
  s = s.replace(/&(#x[0-9a-f]+|#\d+|[a-z]+);/gi, (_, e) => {
    if (e[0] === '#') {
      // past the last code point, unreadable: tested here rather than caught
      // from fromCodePoint, which takes some microseconds a throw
      const at = e[1] === 'x' || e[1] === 'X' ? parseInt(e.slice(2), 16) : +e.slice(1);
      return at <= 0x10ffff ? String.fromCodePoint(at) : '\u0000';
    }
    const v = ENTITIES[e.toLowerCase()];
    return v === undefined ? '\u0000' : v;
  });
  return s.split('\n').map(l => l.replace(/\s+/g, ' ').trim()).filter(Boolean).join('\n');
}

// what a mark structuredText rewrites takes past its one character's worth: a
// tag's or an entity's "&" or "<", a line break
const HTML_MARK = 2;

/// What structuredText(html) takes, in characters' worth (see PROOF_CHARS):
/// one for each character, HTML_MARK more for each "&", "<" and line break
/// (at most about 0.057 microseconds a character's worth, lists the slowest).
export function htmlWork(html) {
  let n = html.length;
  for (let i = 0; i < html.length; i++) {
    const c = html.charCodeAt(i);
    if (c === 38 || c === 60 || c === 10) n += HTML_MARK;
  }
  return n;
}

// openFDA labels: statements, each with the heading words it needs ------------

export const FDA_SECTIONS = ['boxed_warning', 'indications_and_usage', 'dosage_and_administration',
  'dosage_forms_and_strengths', 'contraindications', 'warnings_and_cautions', 'warnings',
  'adverse_reactions', 'mechanism_of_action'];
export const SECTION_CAP = 12000;

const SEE_BRACKET = /\[\s*see\b(?:[^[\]]|\[[^[\]]*\])*\]/gi;
const SEE_PAREN = /\(\s*see\b(?:[^()]|\([^()]*\))*\)/gi;
const NUMBER_REF = /[([]\s*\d+(?:\.\d+)*(?:\s*[,;]\s*\d+(?:\.\d+)*)*\s*[)\]]/g;
const AFTER_REF_BREAK = /^\s{0,8}(?:[A-Z•◦▪●]|\d+\.\d+(?:\.\d+)*\s+[A-Z]|$)/;
const SECTION_HEAD = /^\s*(?:\d+(?:\.\d+)*\s+)?((?:(?:[A-Z][A-Z0-9&,:'()/-]+|&)(?:\s+|$))+)/;
const SUBSECTION = /^(\d+\.\d+(?:\.\d+)*)\s+(?=[A-Z])/;
const CAPS_HEAD = /^((?:(?:[A-Z][A-Z0-9&,:'()/-]+|&)(?:\s+|$))+)/;
// the spaces before a marker are taken from their start only, so a long run
// of spaces is not tried at each of them (a split never resumes inside one)
const BULLET = /((?:(?<!\s)\s+)?[•◦▪●]\s*|(?<!\s)\s+o\s+(?=[A-Z]))/;
// read against the end of the text before a colon, its spaces trimmed
const COLON_BEFORE = /\b(?:with|includes?|including|following|are|is|of|for|to|as|by|from|such as)$/i;

/// Cross-references are not content: "[see Warnings (5.1)]" and "( 2.1 )" go,
/// and a section number before a capital ends the line it closes.
function dropRefs(text) {
  return text.replace(SEE_BRACKET, ' ').replace(SEE_PAREN, ' ').replace(/\bN\/A\b/g, ' ')
    .replace(NUMBER_REF, (m, at, all) => (AFTER_REF_BREAK.test(all.slice(at + m.length, at + m.length + 40)) ? '\n' : ' '));
}

/// An all-capitals run that is a heading, not an acronym starting a sentence.
function capsHeading(run) {
  const caps = run.trim().split(/\s+/).map(w => (w.match(/[A-Z]/g) || []).length);
  return /^WARNING/.test(run) || (caps.filter(n => n >= 3).length >= 2 && caps.some(n => n >= 5));
}

/// Where a lead-in or a label ends: the first colon at the end, before a
/// capital, a number or a bullet, or after "with", "includes", "are"...
function structuralColon(t) {
  for (let i = t.indexOf(':'); i >= 0; i = t.indexOf(':', i + 1)) {
    const after = t.slice(i + 1);
    if (!after.trim() || /^\s+[A-Z0-9•"'([]/.test(after) || COLON_BEFORE.test(t.slice(0, i).trimEnd().slice(-12))) return i;
  }
  return -1;
}

/// The section as pieces, one at a time: one per sentence, knowing whether it
/// starts a line, starts a bullet (a sub-bullet: sub), or continues one (cont).
/// Each line and each bullet is paid for (`spend`), a sentence or none in it.
function* pieces(text, spend) {
  for (const line of text.split('\n')) {
    spend(PIECE_WORK);
    const parts = /[•◦▪●]|\so\s/.test(line) ? line.split(BULLET) : [line];
    for (let j = 0; j < parts.length; j += 2) {
      if (j > 0) spend(PIECE_WORK);
      const marker = j > 0 ? parts[j - 1].trim() : '';
      let k = 0;
      for (const s of sentences(parts[j])) {
        yield {
          text: s, newline: j === 0 && k === 0, bullet: marker !== '' && k === 0, cont: marker !== '' && k > 0,
          sub: marker === '◦' || marker === 'o',
        };
        k++;
      }
    }
  }
}

const POWER_ALL = new RegExp(POWER.source, 'gi');

// What reading a section takes, in characters' worth (see PROOF_CHARS): one
// for each of its characters, for the passes over the whole text; PIECE_WORK
// more for each line, bullet and sentence; a heading or a word normalized,
// NORM_WORK and its heft (see heft); and a statement that can prove, its text
// and the heading words it needs once more. Paid as the reading goes, so a
// section is never read past what the purse holds.
const PIECE_WORK = 24;
const NORM_WORK = 43;
const normWork = n => NORM_WORK + n;
// a wording's or a statement's key (normalize, its numbers, doses and units
// read too) takes about three times a heading's words
const keyWork = n => 3 * normWork(n);

// what a character takes past its one character's worth, normalized: an ASCII
// sign spelled out or read around ("=", "%", "/", a dash, an apostrophe) or a
// sign past ASCII the short way reads (plainUnicode)
const HEFT_SIGN = 2;
// letters meeting digits, split apart ("10mg")
const HEFT_TURN = 1;
// a character past ASCII the full passes read: the slowest, a Greek letter
// with its marks, named, takes about thirteen characters' time
const HEFT_WIDE = 12;
// with one such, the whole text is read the long way: one more for every
// LONG_SHARE of its characters
const LONG_SHARE = 2;
const SIGNS = new Uint8Array(128);
for (const c of "&%<>+~=/-'`") SIGNS[c.charCodeAt(0)] = 1;

/// What normalizing `s` takes, in characters' worth: its length, and more for
/// what is slower to read (HEFT_SIGN, HEFT_TURN, HEFT_WIDE and LONG_SHARE).
export function heft(s) {
  let n = s.length;
  let prev = 0; // 1 a letter, 2 a digit, 0 anything else
  let long = false;
  for (let i = 0; i < s.length; i++) {
    const c = s.charCodeAt(i);
    let kind = 0;
    if (c < 0x80) {
      if ((c | 0x20) >= 0x61 && (c | 0x20) <= 0x7a) kind = 1;
      else if (c >= 0x30 && c <= 0x39) kind = 2;
      else if (SIGNS[c]) n += HEFT_SIGN;
    } else if (SHORT_WAY.has(c)) {
      n += HEFT_SIGN;
    } else {
      n += HEFT_WIDE;
      long = true;
    }
    if (kind && prev && kind !== prev) n += HEFT_TURN;
    prev = kind;
  }
  return long ? n + Math.ceil(s.length / LONG_SHARE) : n;
}
// the text of the statements that can prove, at most this many times the
// section's (the labels and summaries read come to 6 at most): past it the
// section is cut, and what more it states is unknown
const EMIT_ROOM = 8;
// the longest subsection title read in other places (the labels read have
// 19 words at most): past it the section is cut
const MAX_TITLE = 24;
// thrown when reading a section would take more than the purse holds
const OVER = Symbol('over');

/// The work of reading one section of `size` characters: `spend` adds to it
/// (OVER past `limit`); `fits` makes room for a statement's text (false once
/// EMIT_ROOM is spent, the section cut) and pays for its folding, none when
/// the section is read lightly (`light`, fdaSegments); `skip` cuts the
/// section; `words` and `asks` are normalizeWords and reqOf, paid for. `done`
/// marks the statements with the work, the text of those that can prove
/// (folded) and whether the section was cut.
function meter(size, limit, anchor, light) {
  let work = 0;
  let room = EMIT_ROOM * size;
  let folded = 0;
  let skipped = false;
  const spend = n => {
    if ((work += n) > limit) throw OVER;
  };
  spend(size);
  return {
    spend,
    fits: n => {
      if (n > room) {
        room = -1;
        return false;
      }
      room -= n;
      if (!light) {
        folded += n;
        spend(n);
      }
      return true;
    },
    roomy: () => room >= 0,
    skip: () => {
      skipped = true;
    },
    words: s => (spend(normWork(heft(s))), normalizeWords(s)),
    asks: s => (spend(normWork(heft(s))), reqOf(s, anchor)),
    done: segs => Object.assign(segs, { work, folded, cut: room < 0 || skipped }),
  };
}

/// Statements a later sentence takes back: none can prove. Each is marked
/// once, however often its list (growing between) is dropped.
function drop(xs) {
  for (let i = xs.dropped || 0; i < xs.length; i++) xs[i].usable = false;
  xs.dropped = xs.length;
}

/// A label section's statements, each with the heading words a claim needs to
/// be proven by it. Its reading is paid for as it goes (meter): past `limit`
/// it stops (OVER). Read lightly (`light`), for what the section may state
/// (statedIn), no statement is folded and a subsection title's other endings
/// are left out: its whole line, kept then, has their words.
export function fdaSegments(raw, anchor, limit = Infinity, light = false) {
  const { spend, fits, roomy, skip, words, asks, done } = meter(Math.min(raw.length, SECTION_CAP), limit, anchor, light);
  const segs = [];
  let text = raw.length > SECTION_CAP
    ? raw.slice(0, Math.max(0, raw.lastIndexOf(' ', SECTION_CAP))) + ' \u0000' : raw;
  // before dropRefs, which would take the "(9)" of "10(9)/L" for a reference
  text = text.replace(POWER_ALL, ' \u0000 ');
  text = dropRefs(text);
  let sectionReq = [];
  let sectionCut = false;
  const head = SECTION_HEAD.exec(text);
  if (head) {
    sectionReq = asks(head[1]);
    sectionCut = sectionReq === null || popIn(head[1], anchor);
    text = text.slice(head[0].length);
  }
  let cut = false;
  let subReq = [];
  let capsReq = [];
  let labelReq = [];
  let list = null;
  let last = [];
  let prevSemi = false;
  const add = seg => {
    segs.push(seg);
    return seg;
  };
  // one that can prove: its text folded (unless read lightly) and its
  // heading words, paid for
  const statement = (t, req) => {
    let n = sectionReq.length;
    for (const r of req) n += r.length;
    spend(n);
    return add({ text: t, lower: light ? '' : fold(t), usable: true, req: [...sectionReq, ...req.flat()] });
  };
  const emit = (t, usable, req = [subReq, capsReq, labelReq]) => (
    usable && !sectionCut && sectionReq !== null && req.every(r => r !== null) && fits(t.length)
      ? statement(t, req)
      : add({ text: t, lower: '', usable: false, req: [], heads: sectionReq === null || req.some(r => r === null) ? null : [...sectionReq, ...req.flat()] }));
  const closeList = () => {
    if (list && list.pop) cut = true;
    list = null;
  };
  const openList = lead => {
    closeList();
    labelReq = [];
    list = { lead, bullets: undefined, pop: false, tainted: false, items: [] };
    if (popIn(lead, anchor)) cut = true;
    last = list.items;
  };
  const item = (t, p) => {
    list.items.push(emit(list.lead + ' ' + t, !cut && !list.tainted && !p.sub));
    if (/:\s*$/.test(t)) list.tainted = true;
    if (popIn(t, anchor)) {
      list.pop = true;
      if (t.split(/\s+/).length <= 4) list.tainted = true;
    }
  };
  for (const p of pieces(text, spend)) {
    spend(PIECE_WORK);
    let t = p.text;
    // the other readings of a subsection's title: they stand or fall with its body
    const vars = [];
    if (p.newline) labelReq = [];
    // a cut piece cannot be read: it may qualify what came before it
    if (qualifies(t, anchor) || (prevSemi && popIn(t, anchor)) || t.includes('\u0000')) drop(last);
    prevSemi = /;$/.test(t);
    let m = SUBSECTION.exec(t);
    if (m) {
      closeList();
      const ws = t.slice(m[0].length).split(/\s+/);
      let k = 0;
      while (k < ws.length && (/^[A-Z(]/.test(ws[k]) || SMALL.has(ws[k].toLowerCase()) || /^\d/.test(ws[k]))) k++;
      const run = ws.slice(0, k).join(' ');
      const caps = [];
      for (let i = 0; i < k; i++) if (/^[A-Z]/.test(ws[i])) caps.push(i);
      const split = k < ws.length && /^[a-z]/.test(ws[k]) ? caps[caps.length - 1] : ws.length;
      const first = split < ws.length ? words(ws[split]) : null;
      const starts = first && first.length > 0 && (STARTERS.has(first[0]) || anchor.has(first[0]));
      cut = popIn(run, anchor);
      subReq = asks(starts ? ws.slice(0, split).join(' ') : run);
      capsReq = [];
      labelReq = [];
      // a title on its own line states nothing
      if (split >= ws.length) continue;
      // the title may end elsewhere: every other place it could, on its own,
      // needing the title words before it (only when they could prove). The
      // whole line has the words of each of those, for what the section may
      // state (statedIn): kept, unable to prove, when read lightly (it is all
      // of them) or when none of them is the whole line
      if (!cut && !sectionCut) {
        let whole = caps.some(c => c !== split);
        if (!light) {
          for (const c of caps) {
            if (c > MAX_TITLE || !roomy()) {
              skip();
              break;
            }
            if (c === split) continue;
            const v = ws.slice(c).join(' ');
            spend(v.length);
            if (structuralColon(v) >= 0) continue;
            const r = asks(ws.slice(0, c).join(' '));
            if (r !== null && fits(v.length)) {
              vars.push(statement(v, [r]));
              if (c === 0) whole = false;
            }
          }
        }
        if (whole) {
          const line = ws.join(' ');
          spend(line.length);
          add({ text: line, lower: '', usable: false, req: [], heads: sectionReq });
        }
      }
      t = ws.slice(split).join(' ');
    }
    m = CAPS_HEAD.exec(t);
    if (m && capsHeading(m[1])) {
      closeList();
      labelReq = [];
      capsReq = asks(m[1]);
      if (capsReq === null || popIn(m[1], anchor)) cut = true;
      t = t.slice(m[0].length);
      drop(vars);
      if (!t.trim()) continue;
    }
    if (list) {
      if (list.bullets === undefined) list.bullets = p.bullet;
      if (list.bullets) {
        if (p.bullet) {
          item(t, p);
          continue;
        }
        if (p.cont) {
          emit(t, false);
          continue;
        }
        closeList();
      } else if (!p.bullet && !p.cont && structuralColon(t) < 0) {
        item(t, p);
        continue;
      } else closeList();
    }
    const ci = structuralColon(t);
    if (ci >= 0) {
      const before = t.slice(0, ci).trim();
      const after = t.slice(ci + 1).trim();
      const bw = words(before) || [];
      if (!after || before.split(/\s+/).length >= 4 || FUNCTION.has(bw[bw.length - 1])) {
        drop(vars);
        openList(before);
        if (after) item(after, p);
        continue;
      }
      closeList();
      if (popIn(before, anchor)) cut = true;
      labelReq = asks(before);
      t = before + ' ' + after;
    } else if (/\b(?:following|follows|below)\W*$/i.test(t)) {
      drop(vars);
      openList(t);
      continue;
    }
    last = [emit(t, !cut), ...vars];
    if (popIn(t, anchor)) cut = true;
  }
  closeList();
  return done(segs);
}

// MedlinePlus summaries: statements, and list items after their lead-ins -----

// a MedlinePlus heading's question words and the parts every topic has: they
// narrow nothing ("What are the symptoms of asthma?")
const QUESTION = words('what which who whom whose how why when where cause symptom sign treat treated treatment '
  + 'diagnose diagnosed diagnosis test prevent prevented prevention risk likely more develop get happen outlook '
  + 'prognosis complication other problem mean know need i me my you your');

/// A summary's lines (structuredText) as statements: a paragraph's sentences,
/// and a list item's first sentence after its lead-ins, never alone. A list
/// item's later sentences never count (as with an FDA bullet's). The summary's
/// headings are bare lines: a question starts a part, and its words, less the
/// ones every part has, must be in the claim ("How is severe asthma treated?"
/// asks for "severe"), as must a plain heading's. Its reading is paid for as
/// it goes, and may be light, as a label section's is (fdaSegments).
export function mlpSegments(full, anchor, limit = Infinity, light = false) {
  const { spend, fits, asks, done } = meter(Math.min(full.length, SECTION_CAP), limit, anchor, light);
  const segs = [];
  let text = full;
  // cut at a line; the unreadable last line takes back what precedes it
  if (text.length > SECTION_CAP) text = text.slice(0, Math.max(0, text.lastIndexOf('\n', SECTION_CAP))) + '\n\u0000';
  const lines = text.split('\n');
  let cut = false; // a population named: the rest of this part is about them
  let stuck = false; // a population named in a plain heading: the rest of the summary
  let req = []; // what the latest heading asks of a claim; null: unreadable
  let listPop = false;
  let taint = false;
  let leads = []; // leads[d]: the lead-in a depth d+1 item continues; undefined: unusable
  let last = [];
  let list = []; // every item of the list being read
  const emit = (t, usable) => {
    const seg = usable && !stuck && req !== null && fits(t.length)
      ? { text: t, lower: light ? '' : fold(t), usable: true, req }
      : { text: t, lower: '', usable: false, req: [], heads: req };
    segs.push(seg);
    return seg;
  };
  // a line's sentences, each paid for as it is read
  const sentencesOf = s => {
    const out = [];
    for (const x of sentences(s)) {
      spend(PIECE_WORK);
      out.push(x);
    }
    return out;
  };
  const takesBack = s => qualifies(s, anchor) || s.includes('\u0000');
  for (let li = 0; li < lines.length; li++) {
    spend(PIECE_WORK);
    const line = lines[li];
    const bm = /^(•+)\s*/.exec(line);
    const nextDepth = (/^•+/.exec(lines[li + 1] || '') || [''])[0].length;
    if (!bm) {
      if (list.length) {
        if (listPop) cut = true;
        last = list;
        list = [];
        listPop = false;
        taint = false;
      }
      const sents = sentencesOf(line);
      const question = /\?["')\]]*$/.test(line);
      if (question || (sents.length === 1 && nextDepth === 0 && !/[.!]["')\]]*$/.test(line))) {
        // a heading states nothing; a question starts a new part
        if (takesBack(line)) drop(last);
        const r = asks(line);
        req = r && (question ? r.filter(t => !QUESTION.has(t)) : r);
        if (question) cut = popIn(line, anchor);
        else if (popIn(line, anchor)) stuck = true;
        leads = [];
        last = [];
        continue;
      }
      sents.forEach((s, k) => {
        if (takesBack(s)) drop(last);
        const isLast = k === sents.length - 1;
        const isLead = isLast && (nextDepth > 0 || !/[.!]["')\]]*$/.test(s));
        last = [emit(s, !cut && !isLead)];
        if (popIn(s, anchor)) cut = true;
        if (isLast) leads = [isLead && !cut ? s.replace(/:\s*$/, '') : undefined];
      });
      continue;
    }
    const d = bm[1].length;
    const L = leads[d - 1];
    const sents = sentencesOf(line.slice(bm[0].length));
    sents.forEach((s, k) => {
      if (takesBack(s)) {
        drop(list);
        drop(last);
      }
      const isLast = k === sents.length - 1;
      const isLead = isLast && (nextDepth > d || /:["')\]]*$/.test(s));
      const seg = emit(k === 0 && L ? L + ' ' + s : s, k === 0 && L !== undefined && !cut && !taint && !isLead);
      list.push(seg);
      last = [seg];
      if (popIn(s, anchor)) {
        listPop = true;
        // a short population item heads the items after it
        if (k === 0 && s.split(/\s+/).length <= 4) taint = true;
      }
      if (isLast) {
        leads[d] = k === 0 && L !== undefined && isLead ? L + ' ' + s.replace(/:\s*$/, '') : undefined;
        leads.length = d + 1;
      }
    });
  }
  return done(segs);
}

// Sources: the official texts a claim can be proven by ------------------------

// tokens normalization makes up or respells: never a word to look for
const SYNTHETIC = words('percent minus plusminus equals times andor approx ordinal gte lte gt lt plus prn per');
const GREEK_NAMES = new Set(Object.values(GREEK));
const ORDINAL_WORDS = new Set(ORDINALS);
const UNIT_WORDS = new Set([...UNITS, ...Object.keys(UNIT_ALIAS), ...Object.values(UNIT_ALIAS)]);
const sourceCache = new WeakMap();

// A section's statements, kept for the next item and request that reads the
// same text for the same drug or topic (a batch's items often share a label):
// the last SEGMENT_KEEP sections read. The anchor is the sequence's words, so
// the sequence settles the statements, and a statement's key (keyOf) too.
// Kept or not, they are paid for the same (read).
const SEGMENTS = new Map();
const SEGMENT_KEEP = 64;

/// A section as read: `text` is as much of it as its statements can come
/// from (the first SECTION_CAP characters, and one more to know it goes on),
/// `id` names that text for its kind and anchor, `cost` is the least reading
/// it takes (each of those characters once), `lower` its folded text, once a
/// claim asks. `full` is all of it, past the cap too, where a wrong option
/// may still be stated (statedBy).
const sectionOf = (kind, seq, name, full) => {
  const text = full.slice(0, SECTION_CAP + 1);
  return {
    name, text, full, lower: null, id: `${kind}\u0001${seq.join(' ')}\u0001${text}`,
    cost: Math.min(text.length, SECTION_CAP),
  };
};

/// A drug's name as the words that name it: normalized, without function
/// words or the salt names after it ("Metformin Hydrochloride" is metformin).
export function drugTokens(name) {
  return (normalize(String(name || '')) || []).filter(t => !FUNCTION.has(t) && !SALTS.has(t));
}

/// An evidence entry as a source to prove by: its anchor (the drug's or the
/// topic's words, which a claim must name) and its sections, read into
/// statements only when a claim needs them. null for anything else (Europe
/// PMC is evidence for the models, not proof).
function sourceOf(entry) {
  if (!entry || typeof entry !== 'object') return null;
  if (sourceCache.has(entry)) return sourceCache.get(entry);
  let src = null;
  const official = entry.official;
  if (entry.source === 'openFDA label' && official && official.sections && typeof official.sections === 'object') {
    const seq = drugTokens(official.drug);
    const sections = [];
    for (const name of FDA_SECTIONS) {
      const v = official.sections[name];
      const text = Array.isArray(v) ? v.filter(x => typeof x === 'string').join('\n') : typeof v === 'string' ? v : '';
      if (text) sections.push(sectionOf('fda', seq, name, text));
    }
    const anchor = new Set(seq);
    if (seq.length) {
      const name = String(official.drug || '');
      src = { entry, name, topic: new Set(normalizeWords(name) || []), seq, anchor, sections,
        segment: (text, limit, light) => fdaSegments(text, anchor, limit, light) };
    }
  } else if (entry.source === 'MedlinePlus' && ((typeof entry.full === 'string' && entry.full) || (typeof entry.html === 'string' && entry.html))) {
    const seq = content(normalize(structuredText(entry.title)) || []);
    const anchor = new Set(seq);
    if (seq.length) {
      const name = structuredText(entry.title);
      // the summary as text (`full`), or as MedlinePlus sends it (`html`),
      // made text only when a claim asks (ready)
      const section = typeof entry.full === 'string' && entry.full
        ? sectionOf('mlp', seq, 'summary', entry.full)
        : { name: 'summary', html: entry.html, seq, text: null, full: null, lower: null, id: null, cost: 0 };
      src = { entry, name, topic: new Set(normalizeWords(name) || []), seq, anchor, sections: [section],
        segment: (text, limit, light) => mlpSegments(text, anchor, limit, light) };
    }
  }
  sourceCache.set(entry, src);
  return src;
}

/// The tokens with salt names after the drug's name left out: "metformin
/// hydrochloride" is metformin.
function dropSalts(toks, seq) {
  const out = [];
  for (let i = 0; i < toks.length;) {
    if (seq.every((x, k) => toks[i + k] === x)) {
      out.push(...seq);
      i += seq.length;
      while (i < toks.length && SALTS.has(toks[i])) i++;
      continue;
    }
    out.push(toks[i]);
    i++;
  }
  return out;
}

function keyOf(text, seq) {
  const toks = normalize(text);
  return toks ? dropSalts(toks, seq).join(' ') : '';
}

/// What the folded text of a statement proving the claim must hold, to skip
/// the sections and statements that cannot: for each plain word of 5+
/// letters normalization did not make up, the word less its last three
/// letters (at least four; endings are what normalization changes), or its
/// first four when the claim spells it another way; for each number past
/// twelve (a number word is twelve at most), its last three digits (a
/// thousands comma is optional), and for a decimal, its point on. Each only
/// when the claim's own text holds it. Only a shortcut: text skipped here
/// could never have proven the claim, or (rarely) spells a word another way,
/// which loses a proof but never makes one.
function probesOf(toks, folded) {
  const out = new Set();
  const take = p => folded.includes(p) && (out.add(p), true);
  for (const t of toks) {
    if (isNum(t)) {
      const [whole, part] = t.split('.');
      if (part) take((whole === '0' ? '' : whole.slice(-3)) + '.' + part);
      else if (+whole > 12) take(whole.slice(-3));
      continue;
    }
    if (t.length < 5 || !/^[a-z]+$/.test(t) || FUNCTION.has(t)) continue;
    if (SYNTHETIC.has(t) || /^freq/.test(t) || UNIT_WORDS.has(t) || GREEK_NAMES.has(t) || ORDINAL_WORDS.has(t)) continue;
    take(t.slice(0, Math.max(4, t.length - 3))) || take(t.slice(0, 4));
  }
  return [...out];
}

// what the purse pays for besides reading, in parts of a character's worth:
// a section's text folded (once a batch, at most 11 nanoseconds a character)
// and a scan of it for one probe (at most half a nanosecond), against a
// character's worth of 65; a pass over a section's statements for one
// wording, SEG_STEP for each and a scan of the text of those that can prove
// for each probe and the question mark; a whole section made a view (viewOf,
// once a batch, at most 12 nanoseconds a character), and its sentences, or
// its statements, made units with views of their own (once a batch, at most
// 24 nanoseconds a character)
const FOLD_SHARE = 8;
const SCAN_SHARE = 128;
const SEG_STEP = 8;
const VIEW_SHARE = 5;
const UNIT_SHARE = 2;

// Summaries made text, kept for the next request with the same summary: the
// last TEXT_KEEP. Kept or not, they are paid for the same (ready).
const TEXTS = new Map();
const TEXT_KEEP = 16;

/// Whether a section is text to read: one sent as HTML is made text once a
/// batch, paid for by the work that takes (htmlWork); false when the purse
/// cannot pay.
function ready(sec, purse) {
  if (sec.html === undefined) return true;
  if (!pay(purse, sec.html, (sec.work ??= htmlWork(sec.html)))) return false;
  if (sec.text === null) {
    let text = TEXTS.get(sec.html);
    if (text === undefined) {
      text = structuredText(sec.html);
      if (TEXTS.size >= TEXT_KEEP) TEXTS.delete(TEXTS.keys().next().value);
    } else {
      TEXTS.delete(sec.html);
    }
    TEXTS.set(sec.html, text);
    Object.assign(sec, sectionOf('mlp', sec.seq, 'summary', text));
  }
  return true;
}

/// Pays for `what` once a batch (`paid` is what the batch has paid for);
/// false when the purse cannot.
function pay(purse, what, cost) {
  if (purse.paid.has(what)) return true;
  if (cost > purse.left) return false;
  purse.left -= cost;
  purse.paid.set(what, true);
  return true;
}

/// A section's statements, read once a batch: from SEGMENTS when kept, and
/// paid for the same either way (the work their reading took), so what an
/// item comes to never depends on what ran before its batch. null when the
/// purse cannot pay; a reading stopped part way (OVER), or a kept one that
/// would have been, empties the purse, as the reading did. Read lightly
/// (`light`, for what the section may state), they are kept and paid for
/// apart from its full reading, which stands in for them once the batch has
/// paid for it: it has all they have (fdaSegments).
function read(src, sec, purse, light = false) {
  const id = light ? (sec.lightId ??= `light\u0001${sec.id}`) : sec.id;
  const got = purse.paid.get(sec.id) || (light && purse.paid.get(id));
  if (got) return got;
  if (sec.cost > purse.left) return null;
  let segs = SEGMENTS.get(id);
  if (segs) {
    SEGMENTS.delete(id);
  } else {
    try {
      segs = src.segment(sec.text, purse.left, light);
    } catch (e) {
      if (e !== OVER) throw e;
      purse.left = 0;
      return null;
    }
    if (SEGMENTS.size >= SEGMENT_KEEP) SEGMENTS.delete(SEGMENTS.keys().next().value);
  }
  SEGMENTS.set(id, segs);
  if (segs.work > purse.left) {
    purse.left = 0;
    return null;
  }
  purse.left -= segs.work;
  purse.paid.set(id, segs);
  return segs;
}

/// Whether a section's folded text holds every probe: its fold paid for once
/// a batch (by the section), each probe's scan once an item; null when the
/// purse cannot pay.
function holdsAll(sec, probes, purse) {
  if (!probes.length) return true;
  if (!pay(purse, sec, Math.ceil(sec.cost / FOLD_SHARE))) return null;
  sec.lower ??= fold(sec.text.slice(0, SECTION_CAP));
  let seen = purse.seen.get(sec);
  if (!seen) purse.seen.set(sec, (seen = new Map()));
  const scan = Math.ceil(sec.cost / SCAN_SHARE);
  for (const p of probes) {
    let has = seen.get(p);
    if (has === undefined) {
      if (scan > purse.left) return null;
      purse.left -= scan;
      seen.set(p, (has = sec.lower.includes(p)));
    }
    if (!has) return false;
  }
  return true;
}

/// The quote that proves one wording of a claim, or null. Proof is the whole
/// normalized token sequence equal to one usable statement, with the words of
/// the headings above that statement in it. All the work is paid for from
/// `purse`: the wording's key; folding and reading a section once a batch,
/// scanning it for a probe once an item, a pass over its statements each
/// wording, a statement's key once a batch, and a summary sent as HTML made
/// text once a batch. A wording or a section it
/// cannot pay for, or a section cut before its end, is counted in
/// `purse.short`.
function provenBy(alt, srcs, purse) {
  // the wording itself, normalized
  const cost = keyWork(heft(alt));
  if (cost > purse.left) {
    purse.short++;
    return null;
  }
  purse.left -= cost;
  const toks = normalize(alt);
  if (!toks) return null;
  const folded = fold(alt);
  for (const src of srcs) {
    // the claim names the drug or the topic
    if (!src.seq.every(t => toks.includes(t))) continue;
    const claimToks = dropSalts(toks, src.seq);
    const key = claimToks.join(' ');
    const tokSet = new Set(claimToks);
    // the drug's or topic's own words are in nearly every section
    const probes = probesOf(claimToks.filter(t => !src.anchor.has(t)), folded);
    const holds = lower => probes.every(p => lower.includes(p));
    for (const sec of src.sections) {
      if (!ready(sec, purse)) {
        purse.short++;
        continue;
      }
      const ok = holdsAll(sec, probes, purse);
      if (ok === false) continue;
      const segs = ok && read(src, sec, purse);
      const pass = segs && Math.ceil((segs.length * SEG_STEP + segs.folded * (probes.length + 1)) / SCAN_SHARE);
      if (!segs || pass > purse.left) {
        purse.short++;
        continue;
      }
      purse.left -= pass;
      for (const seg of segs) {
        if (!seg.usable || seg.text.length < 0.4 * alt.length || seg.text.length > 2.5 * alt.length) continue;
        if (!holds(seg.lower) || /\?["')\]]*$/.test(seg.text)) continue;
        // its key, normalized once a batch
        if (!pay(purse, seg, keyWork(seg.heft ??= heft(seg.text)))) {
          purse.short++;
          break;
        }
        if (seg.key === undefined) seg.key = keyOf(seg.text, src.seq);
        if (!seg.key || seg.key !== key || !seg.req.every(r => tokSet.has(r))) continue;
        return { claim: alt, quote: seg.text, source: src.entry.source, title: src.entry.title, url: src.entry.url };
      }
      // a section cut before its end may state it further on
      if (segs.cut) purse.short++;
    }
  }
  return null;
}

// Distractors: what a source may state ---------------------------------------

// A question's key is one answer among two when a source states another of
// its options, in any words. Not knowing every way a source may put it, the
// check is loose where proof is strict: an option is stated by any sentence,
// line or statement (a unit) that has each word of it that tells it apart
// (not a function word, a negation, a heading's word, the source's own name),
// with the sentence before when it leans on that one, or a list's lead-in.
// A word of five letters or more is had by any word starting as it does,
// less its last three letters; any other, as it is. Past SECTION_CAP a
// section is read in sentences only: one that may state an option there, its
// headings unread, counts as unread (purse.short).

// the words normalization makes up or respells (a sign's, a Greek letter's or
// an ordinal's name, a unit's, a contraction's): never in a source as they are
const MADE = new Set([...SYNTHETIC, ...GREEK_NAMES, ...ORDINALS, ...Object.values(UNIT_ALIAS),
  'freq', 'will', 'shall', 'have'].filter(w => w.length >= 4));
const NEGATIONS = words('not no never nor');
// "daily", "once daily" and "a day" are the same period
const PERIOD = dict({ daily: 'day', weekly: 'week', freq1d: 'day', freq1w: 'week' });
const canon = t => {
  const c = UNIT_ALIAS[t] || ABBREV_FREQ[t] || t;
  return PERIOD[c] || c;
};
// the words that never tell options apart, and those starting as one does
const LOOSE_GENERIC = words('side effect event');
const GENERICS = [...GENERIC, ...GENERIC_NOUNS, ...LOOSE_GENERIC];
const stemOf = t => t.slice(0, Math.max(4, t.length - 3));
const isGeneric = t => GENERIC.has(t) || GENERIC_NOUNS.has(t) || LOOSE_GENERIC.has(t) || /^us(?:e|ed|es|ing)$/.test(t)
  || (t.length >= 5 && GENERICS.some(g => g.startsWith(stemOf(t))));
// a word had by its stem
const isLoose = t => t.length >= 5 && /^[a-z]+$/.test(t) && !MADE.has(t);

/// The words of an option (its tokens, normalized) that tell it apart, each
/// once, as canon makes it.
const looseOf = toks => [...new Set(toks.filter(t => !FUNCTION.has(t) && !SALTS.has(t) && !NEGATIONS.has(t)
  && !QUESTION.has(t) && !isGeneric(t)).map(canon))];

// how long two spellings are the same from their start
const lcp = (a, b) => {
  let k = 0;
  while (k < a.length && a[k] === b[k]) k++;
  return k;
};
const OUR_OR = new RegExp(`^(?:${OUR})or`);
const RE_ER = new RegExp(`^(?:${RE})er?$`);
const LLED_ED = new RegExp(`^(?:${LLED})(?:e|ed|i|in|ing)$`);

/// Whether the start of a word as compared (spelled) may be spelled another
/// way in a source's text: where british() or plural() may have changed it.
function respelt(q) {
  for (const [a, b] of BRITISH_PARTS) {
    if (q.includes(b)) return true;
    for (let j = lcp(a, b) + 1; j < b.length; j++) if (q.endsWith(b.slice(0, j))) return true;
  }
  for (const [a, b] of BRITISH_STARTS) if (q.length > lcp(a, b) && (q.startsWith(b) || b.startsWith(q))) return true;
  for (const a in BRITISH_WORDS) {
    const b = BRITISH_WORDS[a];
    if (q.length > lcp(a, b) && b.startsWith(q)) return true;
  }
  return OUR_OR.test(q) || RE_ER.test(q) || LLED_ED.test(q) || /iz|yz|y$/.test(q);
}

/// What a source's text holds, as it is, wherever it has a word of an option:
/// the word's start (its stem for a loose one), short of where it may be
/// spelled another way, four letters at least; '' when there is none.
function plainPart(t) {
  let p = isLoose(t) ? stemOf(t) : t;
  if (isLoose(t) && [...MADE].some(w => w.startsWith(p))) return '';
  for (; p.length >= 4; p = p.slice(0, -1)) if (!respelt(p)) return p;
  return '';
}

/// What the view (viewOf) of a text stating an option must hold: for each
/// number past twelve its last three digits, for a decimal its point on (as
/// probesOf), and for each word of four letters or more its plainPart.
function probesFor(r) {
  const out = new Set();
  for (const t of r) {
    if (isNum(t)) {
      const [whole, part] = t.split('.');
      if (part) out.add((whole === '0' ? '' : whole.slice(-3)) + '.' + part);
      else if (+whole > 12) out.add(whole.slice(-3));
    } else if (/^[a-z]{4,}$/.test(t) && !MADE.has(t)) {
      const p = plainPart(t);
      if (p) out.add(p);
    }
  }
  return [...out];
}

/// Whether a section's view (viewOf: all of it, past the cap too) holds every
/// probe: the view made once a batch (by the section), each probe's scan once
/// an item, as holdsAll; null when the purse cannot pay.
function viewHolds(sec, probes, purse) {
  if (!probes.length) return true;
  const may = (sec.may ??= { view: null, plain: { units: null } });
  if (!pay(purse, may, Math.ceil(sec.full.length / VIEW_SHARE))) return null;
  may.view ??= viewOf(sec.full);
  let seen = purse.seen.get(may);
  if (!seen) purse.seen.set(may, (seen = new Map()));
  const scan = Math.ceil(sec.full.length / SCAN_SHARE);
  for (const p of probes) {
    let has = seen.get(p);
    if (has === undefined) {
      if (scan > purse.left) return null;
      purse.left -= scan;
      seen.set(p, (has = may.view.includes(p)));
    }
    if (!has) return false;
  }
  return true;
}

/// A unit's words, by their first four letters: its normalized words (a list
/// item's mark read as a space), their phrases and its headings' words, each
/// also as canon makes it. null when it cannot be read, or its headings
/// cannot (req null).
function tokensOf(text, req) {
  if (req === null) return null;
  const w = normalizeWords(text.replace(ITEM_MARKS, ' '));
  if (!w) return null;
  const by = new Map();
  const put = t => {
    const k = t.slice(0, 4);
    const at = by.get(k);
    if (!at) by.set(k, [t]);
    else if (!at.includes(t)) at.push(t);
  };
  const add = t => {
    put(t);
    const c = canon(t);
    if (c !== t) put(c);
  };
  for (const t of req) add(t);
  for (const t of w) add(t);
  for (const t of phrases(w)) add(t);
  return by;
}

// whether units' words (tokensOf) have each word of an option, a loose one
// (isLoose) by its stem
const holdsR = (sets, r) => r.every(t => sets.some(s => {
  const at = s.get(t.slice(0, 4));
  return !!at && (isLoose(t) ? at.some(u => u.startsWith(stemOf(t))) : at.includes(t));
}));

// a list item's mark; a sentence's stop, before its closing quotes
const ITEM_MARK = /^[•◦▪●]/;
const ITEM_MARKS = /[•◦▪●]/g;
const STOPPED = /[.!]["')\]]*$/;
// a word that points back at what was said before it
const PRONOUN_AT = new RegExp(`\\b(?:${[...PRONOUN].join('|')})\\b`);
// a title: its words of four letters or more (one at least) capitalized
const LOWER_WORD = /(?<![A-Za-z])[a-z][A-Za-z]{3}/;
const titleLike = t => !LOWER_WORD.test(t) && /[A-Za-z]{4}/.test(t);

/// A section's statements as units (unitsState): each with its headings'
/// words, in its view too (one taken back keeps them; an unusable one's are
/// `heads`, null when unreadable), leaning on the statement before when it
/// points back at it. Made once and paid for once a batch; null when the
/// purse cannot pay.
function segUnits(segs, purse) {
  const may = (segs.may ??= { units: null, chars: segs.reduce((n, s) => n + s.text.length, 0) });
  if (!pay(purse, may, Math.ceil(may.chars / UNIT_SHARE))) return null;
  if (!may.units) {
    let prev = null;
    may.units = segs.map((s, at) => {
      const heads = s.heads === undefined ? s.req : s.heads;
      const own = viewOf(s.text);
      const u = { text: s.text, req: heads, view: heads && heads.length ? own + ' ' + heads.join(' ') : own, at, toks: undefined, lean: [] };
      if (prev && PRONOUN_AT.test(own)) u.lean.push(prev);
      prev = u;
      return u;
    });
    may.units.chars = may.units.reduce((n, u) => n + u.view.length, 0);
  }
  return may.units;
}

/// All of a section's text, past the cap too, as units (unitsState): each
/// sentence of each line, leaning on the one before when that one is not
/// stopped, is a title or is pointed back at, and a list item on its list's
/// lead-in. Made once and paid for once a batch; null when the purse cannot
/// pay.
function plainUnits(sec, purse) {
  const plain = (sec.may ??= { view: null, plain: { units: null } }).plain;
  if (!pay(purse, plain, Math.ceil(sec.full.length / UNIT_SHARE))) return null;
  if (!plain.units) {
    const units = [];
    let prev = null;
    let lead = null;
    for (const line of sec.full.split('\n')) {
      for (const text of sentences(line, STOP_END)) {
        const u = { text, req: [], view: viewOf(text), at: units.length, toks: undefined, lean: [] };
        const item = ITEM_MARK.test(text);
        if (prev && (!STOPPED.test(prev.text) || titleLike(prev.text) || PRONOUN_AT.test(u.view))) u.lean.push(prev);
        if (item && lead && lead !== prev) u.lean.push(lead);
        units.push(u);
        if (/:["')\]]*$/.test(text) || (!item && (!STOPPED.test(text) || text.includes(':')))) lead = u;
        prev = u;
      }
    }
    units.chars = units.reduce((n, u) => n + u.view.length, 0);
    plain.units = units;
  }
  return plain.units;
}

/// Whether a unit, with those it leans on, has each word of an option (r):
/// each unit's view scanned for the probes (the first 30) once a call, and
/// the words of a unit that may have them all made once a batch (by the
/// unit, as a statement's key is). true when such a unit cannot be read: it
/// may say anything. null when the purse cannot pay.
function unitsState(units, r, probes, purse) {
  const ps = probes.slice(0, 30);
  const full = (1 << ps.length) - 1;
  const pass = Math.ceil((units.length * SEG_STEP + units.chars * (ps.length + 1)) / SCAN_SHARE);
  if (pass > purse.left) return null;
  purse.left -= pass;
  // each unit's probes, by its place (`at`): those it leans on come before it
  const masks = new Int32Array(units.length);
  for (const u of units) {
    let m = 0;
    for (let i = 0; i < ps.length; i++) if (u.view.includes(ps[i])) m |= 1 << i;
    masks[u.at] = m;
    for (const l of u.lean) m |= masks[l.at];
    if (m !== full) continue;
    const group = [u, ...u.lean];
    const look = r.length * group.length;
    if (look > purse.left) return null;
    purse.left -= look;
    const sets = [];
    for (const g of group) {
      if (!pay(purse, g, keyWork(g.heft ??= heft(g.text)))) return null;
      if (g.toks === undefined) g.toks = tokensOf(g.text, g.req);
      if (!g.toks) return true;
      sets.push(g.toks);
    }
    if (holdsR(sets, r)) return true;
  }
  return false;
}

// an option that cannot be read: it may say anything
const UNREADABLE = Symbol('unreadable');

/// Whether a section may state an option: one of its sentences or
/// statements (units) has each word of it. Its sentences are tried first, the
/// cheaper reading, then its statements with their headings, read lightly
/// (fdaSegments). What the purse cannot pay for is counted in purse.short, as
/// is a section that may state it (its view has every probe) past what its
/// statements are read from: there a sentence's headings are unread.
function statedIn(src, sec, r, probes, purse) {
  if (!ready(sec, purse)) {
    purse.short++;
    return false;
  }
  const holds = viewHolds(sec, probes, purse);
  if (!holds) {
    if (holds === null) purse.short++;
    return false;
  }
  const pu = plainUnits(sec, purse);
  const byLines = pu ? unitsState(pu, r, probes, purse) : null;
  if (byLines) return true;
  if (byLines === null || sec.full.length > SECTION_CAP) {
    purse.short++;
    return false;
  }
  const segs = read(src, sec, purse, true);
  const su = segs && segUnits(segs, purse);
  const bySegs = su ? unitsState(su, r, probes, purse) : null;
  if (bySegs) return true;
  if (bySegs === null || segs.cut) purse.short++;
  return false;
}

/// Whether a source may state an option (one wording of it): true when one
/// of its sections may (statedIn), or the wording has no word that tells it
/// apart from the source's own name; UNREADABLE when it cannot be read.
/// Words already tried (`tried`, the same words in another order) are not
/// tried again. The wording's normalizing is paid for as provenBy's is; what
/// the purse cannot pay for is counted in purse.short.
function statedBy(alt, srcs, purse, tried) {
  const cost = keyWork(heft(alt));
  if (cost > purse.left) {
    purse.short++;
    return false;
  }
  purse.left -= cost;
  const toks = normalize(alt);
  if (!toks) return UNREADABLE;
  const all = looseOf(toks);
  const key = [...all].sort().join(' ');
  if (tried.has(key)) return false;
  tried.add(key);
  for (const src of srcs) {
    const r = all.filter(t => !src.anchor.has(t));
    if (!r.length) return true;
    const probes = probesFor(r);
    for (const sec of src.sections) if (statedIn(src, sec, r, probes, purse)) return true;
  }
  return false;
}

// Claims: what an item states, as the sentences a source would have to state -

// a question whose key is what is not so, or the least: the key is no fact
const NEGATED = /\b(?:not|never|except|least|false|incorrect|untrue|wrong|cannot)\b|n['’]t\b/i;
// a stem asking for the one best answer, so a proven key leaves no other
// option right (and a source stating a distractor stops the proof)
const CUE = /\b(?:most|first[- ]line|of choice|only|gold standard)\b/i;
// an option about the other options ("All of the above", "A and C")
const META_OPTION = /\b(?:all|none|both|neither)\s+of\s+(?:the\s+)?(?:above|below|following|these|them)\b|^\W*(?:both|neither)\b/i;
const LETTER_OPTION = /\b(?:[A-E]|I{1,3}|IV|V|[1-5])\s*(?:and|AND|or|OR|&|\+|,)\s*(?:[A-E]|I{1,3}|IV|V|[1-5])\b/;
const LINE_BULLET = /^(?:[-*•◦▪●]|\d+[.)])\s+/;
// the most claims one item is proven by: more is a page, not a fact
export const MAX_CLAIMS = 6;
// the app sends a note's first 3,400 characters: at that length it was cut
const NOTE_CAP = 3400;

// an item's field as text: anything else is not read (nor paid for)
const str = v => (typeof v === 'string' ? v : '');

/// An item's text as a claim reads it: cross-references out, emphasis marks off.
function clean(text) {
  return String(text).replace(SEE_BRACKET, ' ').replace(SEE_PAREN, ' ')
    .replace(/\*\*(?=\S)([^*\n]*?\S)\*\*/g, '$1').replace(/\*(?=\S)([^*\n]*?\S)\*/g, '$1')
    .replace(/[ \t]+/g, ' ').replace(/ ?\n ?/g, '\n').trim();
}

// a question with its mark lost: "Is X Y" reads as "X is Y" once "is" is
// dropped, so a sentence led by a verb that asks (or by one after a comma)
// or by a question word is never a claim; "Do not crush" still is
const LEAD = '^\\W*(?:(?:so|and|but|then|now|or|well|okay|ok)\\b\\W*)*';
const ASKS = new RegExp(`(?:${LEAD}|,\\s*)(?:is|are|was|were|am|do|does|did|can|could|should|would|will|shall|may|might|must|has|have|had)\\b(?!\\s+not\\b)|${LEAD}(?:what|which|who|whom|whose|how|why|where)\\b`, 'i');

/// Whether a sentence can be proven on its own: no question, nothing that
/// qualifies what came before it or points outside it, and at least three
/// words that say something.
function validClaim(text) {
  if (typeof text !== 'string' || text.includes('?') || QUALIFIES.test(text) || ASKS.test(text)) return false;
  const w = normalizeWords(text);
  return !!w && !anaphoric(w) && content(phrases(w)).length >= 3;
}

// claims enough to tell what an item comes to: one more than MAX_CLAIMS, and
// a note's title, which may only label it (prove leaves such a title out);
// reading an item into claims stops there
const ENOUGH = MAX_CLAIMS + 2;
// reading an item into claims, in characters' worth (see PROOF_CHARS):
// ITEM_WORK for each of its characters, for the passes over all of it (lines,
// card and answer marks, cleaning); PIECE_WORK for each line, sentence, answer
// and option read; a question and one of its answers or options put together,
// normWork of the two; and each wording tested, keyWork of its heft
const ITEM_WORK = 2;

/// The sentences of `text` as claims, each its own wording, added to `claims`
/// until there are ENOUGH.
function addSentences(claims, text, spend) {
  if (claims.length >= ENOUGH) return;
  for (const s of sentences(clean(text))) {
    spend(PIECE_WORK);
    claims.push({ text: s, cands: [s] });
    if (claims.length >= ENOUGH) return;
  }
}

/// The wordings of a found claim that can be proven on their own: its own
/// text, or what its question and answer state together (declaratives).
function wordings(cl, spend) {
  let cands = cl.cands;
  if (!Array.isArray(cands)) {
    const { q, ans, mcq, n } = cands;
    spend(normWork(q.length + ans.length));
    cands = declaratives(q, ans, mcq, n) || [];
  }
  return cands.filter(c => (spend(keyWork(heft(c))), validClaim(c)));
}

const AUX = words('are were have do can may should must will would could might');

/// The text less the full stops and exclamation marks it ends in, walked back
/// one by one (/[.!]+$/ tries a long run of dots from every one of them).
function stopsOff(s) {
  let end = s.length;
  while (end > 0 && (s[end - 1] === '.' || s[end - 1] === '!')) end--;
  return s.slice(0, end).trim();
}

// a line ends at any of these, as a pattern's "." does not cross them
const LINE_END = /[\n\r\u2028\u2029]/;

/// A cloze with each deletion's answer in its place ("{{c1::metformin::drug}}"
/// is "metformin": its answer up to the first "::", the hint after it), or
/// null when a deletion is not closed on its line or is not one at all. Read
/// in one pass; a left "{{" or "}}" is the caller's to refuse.
function fillCloze(s) {
  let out = '';
  let from = 0;
  for (let st; (st = s.indexOf('{{c', from)) >= 0;) {
    let j = st + 3;
    while (j < s.length && s.charCodeAt(j) >= 48 && s.charCodeAt(j) <= 57) j++;
    if (j === st + 3 || !s.startsWith('::', j)) return null;
    const i = j + 2;
    // the answer is at least one character, so its end is looked for after it
    const close = s.indexOf('}}', i + 1);
    if (close < 0 || LINE_END.test(s.slice(i, close))) return null;
    const hint = s.slice(i + 1, close).indexOf('::');
    out += s.slice(from, st) + s.slice(i, hint < 0 ? close : i + 1 + hint);
    from = close + 2;
  }
  return out + s.slice(from);
}

/// "drug", "classes": a word that only names what kind of thing the answer
/// is. A plural counts only where it cannot be a verb: after "which of the
/// following", or before "are", "can"... ("What causes asthma?" asks no kind).
function genericNoun(w, next, listed) {
  const x = w.toLowerCase();
  if (GENERIC_NOUNS.has(x)) return true;
  const sing = [plural(x), x.replace(/es$/, '')].find(y => y !== x && GENERIC_NOUNS.has(y));
  return !!sing && (listed || AUX.has(String(next || '').toLowerCase()));
}

/// What a question and one of its answers state together, as the sentences a
/// source would say it in, or null when they cannot be put as one statement.
/// "What is the drug of choice for X?" and "Y" state "The drug of choice for X
/// is Y", or "Y is the drug of choice for X". n is how many answers the
/// question has: "What are the symptoms of X?" with several states "The
/// symptoms of X include Y" for each one.
export function declaratives(q, ans, mcq = false, n = 1) {
  // a run of spaces as one, so the patterns below never try a long run every
  // way it can be split (a question padded with spaces took seconds); a line
  // break stays one, as "." does not cross it, and a hidden mark stays hidden
  q = String(q).replace(/\s+/g, run => (LINE_END.test(run) ? '\n' : /[^\ufeff]/.test(run) ? ' ' : '\ufeff')).trim();
  ans = String(ans).trim();
  if (!q || !ans || splitSentences(ans).length !== 1) return null;
  ans = stopsOff(ans);
  if (!ans) return null;
  // a blank is filled; the sentence then says what it says, "not" and all
  const blanks = q.match(/_{3,}/g) || [];
  if (blanks.length > 1) return null;
  // (the answer as it is: a "$&" in it is not the blank)
  if (blanks.length === 1) return [q.replace(/_{3,}/, () => ans)];
  if (splitSentences(q).length !== 1 || NEGATED.test(q)) return null;
  let m = /^(?:what|which)\s+(is|are)\s+(.+?)\s*\?$/i.exec(q);
  if (m) {
    const verb = m[1].toLowerCase();
    const x = m[2];
    if (verb === 'are' && n > 1) return [`${x} include ${ans}`];
    const out = [`${x} ${verb} ${ans}`];
    // "the X" names one thing, so it reads both ways; "a beta blocker is
    // metoprolol" would not
    if (/^the\b/i.test(x)) out.push(`${ans} ${verb} ${x}`);
    if (verb === 'is' && !/^(?:a|an|the)\b/i.test(ans)) out.push(`${x} is a ${ans}`);
    return out;
  }
  const listed = /^which\s+of\s+the\s+following\s+(.+?)\s*\?$/i.exec(q);
  m = listed || /^(?:which|what)\s+(.+?)\s*\?$/i.exec(q);
  if (m) {
    const ws = m[1].split(/\s+/);
    let k = 0;
    while (k < 2 && k < ws.length - 1 && genericNoun(ws[k], ws[k + 1], !!listed)) k++;
    return k > 0 || listed ? [`${ans} ${ws.slice(k).join(' ')}`] : null;
  }
  // "The drug of choice for X is:" and its option
  if (mcq && /(?::|\b(?:is|are))$/i.test(q)) return [`${q.replace(/:$/, '')} ${ans}`];
  return null;
}

// an exam bank's "Ans-a." or "Answer: (c)." before the explanation: which
// option it names, not a fact
// (each run of spaces is taken by one part only: two that could share it
// tried every way to split a long run, and took seconds)
const ANSWER_MARK = /^\W*(?:correct\s+)?ans(?:wer)?\b\s*(?:is\b\s*)?(?:[-.:]+\s*)?(?:\(([a-e])\)|([a-e])(?=[.:)-]|\s*$))[\s.:)-]*/i;
// a markdown heading, or a line ending in a colon: what follows depends on it
const HEADING = /^#|:["')\]]*$/;
const ENDS_SENTENCE = /[.!?]["')\]]*$/;
const CARD_LINE = /^(Cloze|Q|A|Why): ?(.*)$/;

/// A text's lines as claims, added to `claims` until there are ENOUGH: each
/// line's sentences, its bullet mark off. A heading, a lead-in, a bare line
/// over a list or a nested list makes later lines depend on earlier ones, so
/// they cannot be proven one by one: 'structure', else null.
function lineClaims(claims, text, spend) {
  const lines = text.split('\n').filter(l => l.trim());
  for (let i = 0; i < lines.length && claims.length < ENOUGH; i++) {
    spend(PIECE_WORK);
    const line = lines[i].trim();
    const bullet = LINE_BULLET.test(line);
    if (HEADING.test(line) || (bullet && /^\s/.test(lines[i]))) return 'structure';
    if (!bullet && !ENDS_SENTENCE.test(line) && i + 1 < lines.length && LINE_BULLET.test(lines[i + 1].trim())) {
      return 'structure';
    }
    addSentences(claims, bullet ? line.replace(LINE_BULLET, '') : line, spend);
  }
  return null;
}

/// A narrated lecture's facts: the app split the lecture at every full stop,
/// question mark and line break, and joined the pieces it kept with ". ".
function factClaims(text, spend) {
  // "2.5 mg" was split into "2. 5 mg": the number cannot be read back
  if (/\d\.\s+\d/.test(text)) return { why: 'split' };
  const claims = [];
  for (const part of text.trim().replace(/\.$/, '').split(/\.\s+/)) {
    const s = part.trim();
    if (!s) continue;
    spend(PIECE_WORK);
    if (claims.push({ text: s + '.', cands: [s + '.'] }) >= ENOUGH) break;
  }
  return { claims };
}

/// A note: its title (a claim unless it only labels the note, see prove) and
/// its body's lines. At the app's length cap it may have been cut mid-fact.
function noteClaims(text, spend) {
  if (text.length >= NOTE_CAP) return { why: 'cut' };
  const nl = text.indexOf('\n');
  const title = clean((nl < 0 ? text : text.slice(0, nl)).replace(/^\s*#+\s*/, ''));
  const claims = title ? [{ text: title, cands: [title], title: true }] : [];
  const why = lineClaims(claims, nl < 0 ? '' : text.slice(nl + 1), spend);
  return why ? { why } : { claims };
}

/// A card as the app sends it: "Cloze: ..." or "Q: ..." and "A: ..." (its
/// bullets joined by "; "), then "Why: ...". Anything else, a line break
/// inside a part included, cannot be told apart for certain.
function cardClaims(text, spend) {
  let cloze = null;
  let q = null;
  let a = null;
  const why = [];
  for (const line of text.split('\n')) {
    const m = CARD_LINE.exec(line);
    if (!m) return { why: 'card' };
    const [, tag, part] = m;
    if (tag === 'Why') why.push(part);
    else if (why.length) return { why: 'card' };
    else if (tag === 'Cloze' && cloze === null && q === null) cloze = part;
    else if (tag === 'Q' && q === null && cloze === null) q = part;
    else if (tag === 'A' && q !== null && a === null) a = part;
    else return { why: 'card' };
  }
  const claims = [];
  if (cloze !== null) {
    const filled = fillCloze(cloze);
    if (filled === null || /\{\{|\}\}/.test(filled)) return { why: 'card' };
    addSentences(claims, filled, spend);
  } else if (q !== null && a !== null) {
    // the answers up to ENOUGH: past that, how many there are matters only
    // as more than one
    const answers = [];
    for (const piece of a.split('; ')) {
      if (!piece.trim()) continue;
      spend(PIECE_WORK);
      const ans = clean(piece);
      if (ans && answers.push(ans) >= ENOUGH) break;
    }
    if (!answers.length) return { why: 'card' };
    const front = clean(q);
    for (const ans of answers) {
      claims.push({ text: front + ' ' + ans, cands: { q: front, ans, mcq: false, n: answers.length } });
    }
  } else return { why: 'card' };
  for (const w of why) if (w.trim()) addSentences(claims, w, spend);
  return { claims };
}

// an option's own letter: "A. Metformin", "(b) Insulin"
const OPTION_LETTER = /^\(?([a-h])[.)]\s+\S/i;

/// A one-best-answer question: the stem with its key is the claim, the
/// explanation's sentences are claims too, and each other option, put the
/// same way, must not be what a source states.
function mcqClaims(item, spend) {
  const { options, key } = item;
  if (!Array.isArray(options) || options.length < 2 || !Number.isInteger(key) || key < 0 || key >= options.length) {
    return { why: 'mcq' };
  }
  spend(PIECE_WORK * options.length);
  if (options.some(o => typeof o !== 'string' || !o.trim())) return { why: 'mcq' };
  const stem = clean(str(item.stem));
  if (!stem || splitSentences(stem).length !== 1 || stem.split(/\s+/).length > 30 || !CUE.test(stem) || NEGATED.test(stem)) {
    return { why: 'stem' };
  }
  let opts = options.map(clean);
  // "A. Metformin", "B. Insulin": the letters go only when every option has its own
  if (opts.every((o, i) => OPTION_LETTER.exec(o)?.[1].toLowerCase() === 'abcdefgh'[i])) {
    opts = opts.map(o => o.replace(/^\(?[a-h][.)]\s+/i, ''));
  }
  if (opts.some(o => META_OPTION.test(o) || LETTER_OPTION.test(o))) return { why: 'options' };
  const ans = opts[key];
  const claims = [{ text: stem + ' ' + ans, cands: { q: stem, ans, mcq: true, n: 1 } }];
  let exp = str(item.explanation).trim();
  const mark = ANSWER_MARK.exec(exp);
  if (mark) {
    // the mark must name the key: anything else is a question at odds with itself
    if ((mark[1] || mark[2]).toLowerCase().charCodeAt(0) - 97 !== key) return { why: 'mcq' };
    exp = exp.slice(mark[0].length);
  }
  if (exp.trim()) {
    const why = lineClaims(claims, exp, spend);
    if (why) return { why };
  }
  // with ENOUGH claims it is too much to prove, whatever its other options
  if (claims.length >= ENOUGH) return { claims };
  const distractors = [];
  for (let i = 0; i < opts.length; i++) {
    if (i === key) continue;
    spend(normWork(stem.length + opts[i].length));
    const d = declaratives(stem, opts[i], true);
    if (!d) return { why: 'options' };
    distractors.push(d);
  }
  return { claims, distractors };
}

/// What an item states, found: its claims ({text, cands: its wordings, or the
/// question and answer they come from}, a note's title marked) up to ENOUGH,
/// and a question's distractors; or {why} when it cannot be read as claims
/// for certain. Paid for as it reads (`spend`).
function discover(item, spend) {
  if (!item || typeof item !== 'object') return { why: 'item' };
  spend(NORM_WORK + ITEM_WORK * itemChars(item));
  switch (item.kind) {
    case 'mcq': return mcqClaims(item, spend);
    case 'card': return cardClaims(str(item.text), spend);
    case 'note': return noteClaims(str(item.text), spend);
    case 'fact': return factClaims(str(item.text), spend);
    // a checklist's steps, a page and a case say more than one source states
    default: return { why: 'kind' };
  }
}

/// What an item states, as claims ({text, alts: the wordings a source may
/// state it in, empty when none can stand alone}), or {why} when it cannot be
/// read as claims for certain. Questions also give their distractors. Read
/// only until there are more claims than MAX_CLAIMS and a title; `work` is
/// what the reading took (see PROOF_CHARS), and past `limit` it stops (OVER).
export function claimsFor(item, limit = Infinity) {
  let work = 0;
  const spend = n => {
    if ((work += n) > limit) throw OVER;
  };
  const found = discover(item, spend);
  if (found.why) return { why: found.why, work };
  const claims = found.claims.map(cl => ({ text: cl.text, alts: wordings(cl, spend), ...(cl.title ? { title: true } : {}) }));
  return { claims, ...(found.distractors ? { distractors: found.distractors } : {}), work };
}

// Proof: every claim stated word for word by an official source -------------

// the words a title's labels are joined by: "Treatment of asthma"
const LABEL_JOIN = words('a the and of in on for to with');
// a numbered part of a course: "Lecture 3", "Week 2"
const ORDERED = words('chapter part section module lesson lecture unit week topic');

/// Whether a note's title (its words, `w`) only names what the note is
/// about: one source's drug or topic, heading words and a part's number
/// ("Asthma: key facts", "Lecture 3: metformin hydrochloride"). Such a title
/// states nothing; any other word, a verb included ("Asthma is a drug"),
/// makes it a claim.
function labelOnly(w, src) {
  if (!w || !w.length) return false;
  return w.every((t, i) => src.topic.has(t) || LABEL_WORDS.has(t) || LABEL_JOIN.has(t) || SALTS.has(t)
    || (isNum(t) && i > 0 && ORDERED.has(w[i - 1])));
}

/// How much section text prove() reads for a batch, in characters' worth (a
/// text normalized, its heft), not read off a clock (a Worker's clock stands
/// still while it computes), as with the claim gate's MAX_WORK: reading is at
/// most about 0.065 microseconds a character's worth, so this is about 3 ms,
/// the free plan's 10 ms of CPU being mostly the rest of the check's. A
/// section is paid for once a batch, however many of its items read it, and
/// whether or not it was read for an earlier request: what an item comes to
/// never depends on what ran before it but its own batch.
export const PROOF_CHARS = 48000;

/// How many characters of text an item has: its own, a question's options
/// and explanation too.
function itemChars(item) {
  if (!item || typeof item !== 'object') return 0;
  let n = 0;
  for (const v of [item.text, item.stem, item.explanation, ...(Array.isArray(item.options) ? item.options : [])]) {
    if (typeof v === 'string') n += v.length;
  }
  return n;
}

/// Whether an item is proven: {v, claims, proven, quotes, read} when every
/// claim it makes is stated word for word by one of the official sources
/// (openFDA labels, MedlinePlus summaries; anything else in `officials` is
/// ignored) and, for a question, no source may state one of its other
/// options, in any words (statedBy): 'distractor' when one may, 'options' when
/// one cannot be read; with `why` when it is not. Proven is the only way to
/// Verified: models agreeing never are. It reads at most `chars` characters
/// of the sections not in `paid` (the batch's, shared), and `read` is how
/// many it did; 'budget' when a section it could not pay for might have
/// changed the answer. `unread` is how many of the item's official lookups
/// failed (a source down, not one with nothing on it): 'lookup' when what was
/// not read could have proven a claim, or stated another option. A
/// MedlinePlus entry is read from `full` (its summary as text) or else `html`
/// (as MedlinePlus sends it).
export function prove(item, officials, { chars = PROOF_CHARS, paid = new Map(), unread = 0 } = {}) {
  const srcs = (Array.isArray(officials) ? officials : []).map(sourceOf).filter(Boolean);
  const out = { v: PROOF_VERSION, claims: 0, proven: 0, quotes: [], read: 0 };
  const purse = { left: Math.max(0, chars), paid, short: 0, seen: new Map() };
  const done = why => ({ ...out, read: Math.max(0, chars) - purse.left, ...(why ? { why } : {}) });
  // the item's own text, read into claims and their wordings as far as the
  // purse goes
  const spend = n => {
    if (n > purse.left) throw OVER;
    purse.left -= n;
  };
  let found;
  let claims;
  try {
    found = discover(item, spend);
    if (found.why) return done(found.why);
    // a title that only names a source's drug or topic states nothing
    const title = found.claims.find(cl => cl.title);
    let words = null;
    if (title && srcs.length) {
      spend(normWork(heft(title.text)));
      words = normalizeWords(title.text);
    }
    claims = found.claims.filter(cl => !(cl.title && srcs.some(src => labelOnly(words, src))));
    out.claims = claims.length;
    if (!srcs.length) return done(unread ? 'lookup' : 'no-source');
    if (!claims.length) return done('empty');
    if (claims.length > MAX_CLAIMS) return done('many');
    for (const cl of claims) cl.alts = wordings(cl, spend);
  } catch (e) {
    if (e !== OVER) throw e;
    return done('budget');
  }
  if (claims.some(cl => !cl.alts.length)) return done('claim');
  for (const cl of claims) {
    let q = null;
    const short = purse.short;
    for (const alt of cl.alts) if ((q = provenBy(alt, srcs, purse))) break;
    if (!q) return done(purse.short > short ? 'budget' : unread ? 'lookup' : 'unproven');
    out.proven++;
    out.quotes.push(q);
  }
  // a source that may state another option makes the key one answer among
  // two; an option that cannot be read may say anything
  const short = purse.short;
  const tried = new Set();
  for (const alts of found.distractors || []) {
    for (const a of alts) {
      const stated = statedBy(a, srcs, purse, tried);
      if (stated === UNREADABLE) return done('options');
      if (stated) return done('distractor');
    }
  }
  return done(purse.short > short ? 'budget' : unread && found.distractors?.length ? 'lookup' : null);
}

/// Whether a proof (as prove gives it, kept or sent) says every claim of the
/// item is stated word for word by an official source: the only way to
/// Verified.
export function fullyProven(p) {
  return !!p && typeof p === 'object' && p.v === PROOF_VERSION && !p.why && p.claims > 0 && p.proven === p.claims;
}
