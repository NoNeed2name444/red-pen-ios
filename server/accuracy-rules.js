// The accuracy engine's rule checks: deterministic, free, instant.
//
// A model can miss a wrong dose; a table cannot. These are the errors that
// can be caught without judgement - a dose far outside what the drug is ever
// given at, a lab value that cannot exist in the unit it is written in, an
// explanation that names a different answer from the key - and they are
// signals for the accuracy model (accuracy-model.js), never verdicts on their
// own: a severe hit keeps an item from being Verified, and the model weighs
// the rest.
//
// This is a port of ios/RedPen/Shared/Accuracy/AccuracyRules.swift and must
// agree with it: the phone runs these offline, the server runs them for the
// training set, and the same item has to get the same hits in both places.
// The tables are deliberately broad (single dose OR daily total, adult, any
// common route): a rule that cries wolf trains the student to ignore it.

/// mg ranges: [lowest dose ever sensible, highest single dose or daily total].
export const DRUGS = {
  paracetamol: [325, 4000], acetaminophen: [325, 4000], ibuprofen: [200, 3200], aspirin: [75, 4000],
  naproxen: [220, 1500], amoxicillin: [125, 6000], 'co-amoxiclav': [250, 3600], ceftriaxone: [250, 4000],
  vancomycin: [125, 4000], ciprofloxacin: [100, 1500], doxycycline: [50, 200], azithromycin: [250, 2000],
  clarithromycin: [250, 1000], metronidazole: [200, 4000], nitrofurantoin: [50, 400], trimethoprim: [100, 400],
  benzylpenicillin: [300, 14400], flucloxacillin: [250, 8000], metformin: [250, 3000], gliclazide: [30, 320],
  atorvastatin: [10, 80], simvastatin: [5, 80], rosuvastatin: [5, 40], pravastatin: [10, 80],
  lisinopril: [2.5, 80], ramipril: [1.25, 10], enalapril: [2.5, 40], losartan: [12.5, 150], candesartan: [2, 32],
  amlodipine: [2.5, 10], nifedipine: [5, 120], bisoprolol: [1.25, 20], metoprolol: [5, 400], atenolol: [25, 100],
  propranolol: [10, 320], furosemide: [10, 1000], bumetanide: [0.5, 10], spironolactone: [12.5, 400],
  bendroflumethiazide: [1.25, 5], hydrochlorothiazide: [6.25, 100], warfarin: [0.5, 15], apixaban: [2.5, 20],
  rivaroxaban: [2.5, 30], dabigatran: [75, 300], clopidogrel: [75, 600], ticagrelor: [60, 180], digoxin: [0.0625, 1.5],
  levothyroxine: [0.0125, 0.3], carbimazole: [5, 60], propylthiouracil: [50, 1200], morphine: [1, 200],
  oxycodone: [2.5, 160], codeine: [15, 240], tramadol: [50, 400], fentanyl: [0.012, 0.2], naloxone: [0.04, 10],
  adrenaline: [0.01, 1], epinephrine: [0.01, 1], atropine: [0.1, 5], adenosine: [3, 18], amiodarone: [50, 1200],
  prednisolone: [1, 100], prednisone: [1, 100], methylprednisolone: [4, 1000], dexamethasone: [0.5, 40],
  hydrocortisone: [5, 500], diazepam: [1, 40], lorazepam: [0.25, 10], midazolam: [0.5, 20], haloperidol: [0.5, 20],
  olanzapine: [2.5, 20], quetiapine: [25, 800], sertraline: [25, 200], fluoxetine: [10, 80], citalopram: [10, 40],
  amitriptyline: [10, 150], lithium: [100, 2400], phenytoin: [50, 2000], 'sodium valproate': [100, 2500],
  levetiracetam: [250, 3000], carbamazepine: [100, 1600], lamotrigine: [25, 500], ondansetron: [2, 32],
  metoclopramide: [5, 30], omeprazole: [10, 80], lansoprazole: [15, 60], allopurinol: [50, 900], colchicine: [0.3, 2],
  alteplase: [0.5, 100], 'tranexamic acid': [250, 4000], enoxaparin: [20, 200], salbutamol: [0.1, 10], albuterol: [0.1, 10],
  ipratropium: [0.02, 0.5], 'magnesium sulfate': [1000, 6000], 'magnesium sulphate': [1000, 6000],
  'calcium gluconate': [500, 3000], acetazolamide: [125, 1000], mannitol: [12500, 100000], sildenafil: [20, 100],
  finasteride: [1, 5], tamsulosin: [0.4, 0.8], methotrexate: [2.5, 30],
};

/// Lab analytes: unit -> [plausible low, plausible high, reference low, reference high].
/// Plausible means "can be measured in a living patient"; outside it the
/// number is almost always written in the wrong unit.
export const LABS = {
  sodium: { 'mmol/l': [95, 195, 135, 145], 'meq/l': [95, 195, 135, 145] },
  potassium: { 'mmol/l': [1.2, 10, 3.5, 5.3], 'meq/l': [1.2, 10, 3.5, 5.3] },
  chloride: { 'mmol/l': [60, 150, 96, 107], 'meq/l': [60, 150, 96, 107] },
  bicarbonate: { 'mmol/l': [2, 55, 22, 29], 'meq/l': [2, 55, 22, 29] },
  calcium: { 'mg/dl': [3, 20, 8.5, 10.5], 'mmol/l': [0.8, 5, 2.1, 2.6] },
  magnesium: { 'mg/dl': [0.4, 12, 1.7, 2.4], 'mmol/l': [0.15, 5, 0.7, 1.05], 'meq/l': [0.3, 10, 1.4, 2.1] },
  glucose: { 'mg/dl': [10, 2500, 70, 100], 'mmol/l': [0.5, 140, 3.9, 5.6] },
  creatinine: { 'mg/dl': [0.1, 30, 0.6, 1.3], 'µmol/l': [10, 2700, 50, 115] },
  urea: { 'mmol/l': [0.5, 120, 2.5, 7.8], 'mg/dl': [1, 350, 7, 20] },
  bun: { 'mg/dl': [1, 350, 7, 20] },
  haemoglobin: { 'g/dl': [1.5, 26, 12, 17.5], 'g/l': [15, 260, 120, 175] },
  hemoglobin: { 'g/dl': [1.5, 26, 12, 17.5], 'g/l': [15, 260, 120, 175] },
  albumin: { 'g/dl': [0.5, 7, 3.5, 5], 'g/l': [5, 70, 35, 50] },
  bilirubin: { 'mg/dl': [0.05, 60, 0.1, 1.2], 'µmol/l': [1, 1000, 3, 21] },
  lactate: { 'mmol/l': [0.1, 35, 0.5, 2.2] },
  tsh: { 'miu/l': [0.001, 1000, 0.4, 4.5], 'mu/l': [0.001, 1000, 0.4, 4.5] },
  hba1c: { '%': [3, 20, 4, 5.6], 'mmol/mol': [10, 200, 20, 38] },
  paco2: { mmhg: [8, 160, 35, 45], kpa: [1, 21, 4.7, 6] },
  pao2: { mmhg: [15, 700, 75, 100], kpa: [2, 95, 10, 13.3] },
  ph: { '': [6.5, 7.9, 7.35, 7.45] },
  inr: { '': [0.5, 20, 0.8, 1.2] },
};

const UNIT_ALIASES = {
  'mmol/l': 'mmol/l', 'mmol/litre': 'mmol/l', 'mmol/liter': 'mmol/l', 'meq/l': 'meq/l', 'mg/dl': 'mg/dl',
  'µmol/l': 'µmol/l', 'umol/l': 'µmol/l', 'μmol/l': 'µmol/l', 'micromol/l': 'µmol/l', 'g/dl': 'g/dl', 'g/l': 'g/l',
  'miu/l': 'miu/l', 'mu/l': 'mu/l', 'µiu/ml': 'miu/l', 'uiu/ml': 'miu/l', '%': '%', 'mmol/mol': 'mmol/mol',
  mmhg: 'mmhg', 'mm hg': 'mmhg', kpa: 'kpa', 'mg/l': 'mg/l', 'ng/ml': 'ng/ml', 'iu/l': 'iu/l', 'u/l': 'u/l',
};

const LAB_NAMES = {
  sodium: 'sodium', na: 'sodium', 'na+': 'sodium', potassium: 'potassium', k: 'potassium', 'k+': 'potassium',
  chloride: 'chloride', bicarbonate: 'bicarbonate', hco3: 'bicarbonate', calcium: 'calcium', magnesium: 'magnesium',
  glucose: 'glucose', 'blood glucose': 'glucose', 'blood sugar': 'glucose', creatinine: 'creatinine', urea: 'urea',
  bun: 'bun', 'blood urea nitrogen': 'bun', haemoglobin: 'haemoglobin', hemoglobin: 'hemoglobin', hb: 'haemoglobin',
  albumin: 'albumin', bilirubin: 'bilirubin', lactate: 'lactate', tsh: 'tsh', hba1c: 'hba1c', paco2: 'paco2',
  pco2: 'paco2', pao2: 'pao2', po2: 'pao2', ph: 'ph', inr: 'inr',
};

const MASS = { g: 1000, mg: 1, mcg: 0.001, µg: 0.001, μg: 0.001, ug: 0.001, microgram: 0.001, micrograms: 0.001, ng: 0.000001,
  gram: 1000, grams: 1000, milligram: 1, milligrams: 1 };

const esc = s => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
const lower = s => String(s || '').toLowerCase();
const num = s => Number(String(s).replace(/,/g, ''));

/// Doses named in the text: "paracetamol 1 g", "500 mg of amoxicillin".
/// A dose per kilogram, per minute or per hour is left alone (the tables
/// are absolute doses), as is a dose with no unit.
export function doses(text) {
  const t = lower(text);
  const out = [];
  const unit = '(g|mg|mcg|µg|μg|ug|ng|micrograms?|milligrams?|grams?)';
  const perRate = /^\s*(\/|per\s+)(kg|min|minute|h|hr|hour|m2|m²)/;
  for (const drug of Object.keys(DRUGS)) {
    if (!t.includes(drug)) continue;
    const after = new RegExp(`\\b${esc(drug)}\\b[^.;\\n\\d]{0,25}?(\\d+(?:[.,]\\d+)?)\\s*${unit}\\b`, 'g');
    const before = new RegExp(`(\\d+(?:[.,]\\d+)?)\\s*${unit}\\b\\s+(?:of\\s+)?(?:iv\\s+|oral\\s+|im\\s+)?${esc(drug)}\\b`, 'g');
    for (const re of [after, before]) {
      for (const m of t.matchAll(re)) {
        const rest = t.slice(m.index + m[0].length);
        if (re === after && perRate.test(rest)) continue;
        const factor = MASS[m[2]];
        if (!factor) continue;
        out.push({ drug, mg: num(m[1]) * factor, said: m[0].trim() });
      }
    }
  }
  return out;
}

/// Lab values: "sodium 128 mmol/L", "K+ of 7.9 mEq/L", "pH 7.21".
export function labValues(text) {
  const t = lower(text).replace(/μ/g, 'µ');
  const out = [];
  const names = Object.keys(LAB_NAMES).sort((a, b) => b.length - a.length).map(esc).join('|');
  const units = Object.keys(UNIT_ALIASES).sort((a, b) => b.length - a.length).map(esc).join('|');
  const re = new RegExp(`(?:^|[^a-z0-9])(${names})(?![a-z0-9])\\s*(?:level|concentration|of|is|was|:|=|\\s)*\\s*(\\d+(?:\\.\\d+)?)\\s*(${units})?(?![a-z0-9/])`, 'g');
  for (const m of t.matchAll(re)) {
    const analyte = LAB_NAMES[m[1]];
    const unit = m[3] ? UNIT_ALIASES[m[3]] : '';
    // a bare "K 4" or "Na 140" with no unit is too ambiguous unless the
    // analyte has no unit at all (pH, INR)
    if (!unit && !LABS[analyte]['']) continue;
    if (unit === '' && m[1].length <= 2 && analyte !== 'ph') continue;
    out.push({ analyte, name: m[1], value: num(m[2]), unit, said: m[0].trim() });
  }
  return out;
}

/// "normal sodium is 125-135 mmol/L": a stated reference range to compare.
function statedRanges(text) {
  const t = lower(text).replace(/μ/g, 'µ').replace(/[–—]/g, '-');
  const out = [];
  const names = Object.keys(LAB_NAMES).sort((a, b) => b.length - a.length).map(esc).join('|');
  const units = Object.keys(UNIT_ALIASES).sort((a, b) => b.length - a.length).map(esc).join('|');
  const re = new RegExp(`(?:normal|reference)\\s+(?:serum\\s+|plasma\\s+|blood\\s+)?(${names})(?![a-z0-9])[^\\d\\n]{0,25}?(\\d+(?:\\.\\d+)?)\\s*(?:-|to)\\s*(\\d+(?:\\.\\d+)?)\\s*(${units})?`, 'g');
  for (const m of t.matchAll(re)) {
    out.push({ analyte: LAB_NAMES[m[1]], lo: num(m[2]), hi: num(m[3]), unit: m[4] ? UNIT_ALIASES[m[4]] : '' });
  }
  return out;
}

export const NON_ANSWERS = ['all of the above', 'none of the above', 'all of these', 'none of these'];
const norm = s => lower(s).replace(/[^a-z0-9%]+/g, ' ').trim();
const letter = i => String.fromCharCode(65 + i);

/// Which option the explanation says is right, if it says so plainly:
/// "the answer is C", "Correct answer: (B)", "Option D is correct".
export function explainedAnswer(explanation, options) {
  const e = String(explanation || '');
  const byLetter = [...e.matchAll(/\b(?:correct\s+(?:answer|option|choice)|the\s+answer|answer)\s*(?:is|:)\s*(?:option\s*)?\(?([A-J])\)?(?![A-Za-z0-9])/g),
                    ...e.matchAll(/\b(?:option|choice)\s*\(?([A-J])\)?\s+is\s+(?:the\s+)?(?:correct|right|best)\b/gi)];
  if (byLetter.length) {
    const l = byLetter.at(-1)[1].toUpperCase();
    const i = l.charCodeAt(0) - 65;
    if (i >= 0 && i < options.length) return i;
  }
  const le = lower(e);
  for (let i = 0; i < options.length; i++) {
    const o = lower(options[i]).trim();
    if (o.length < 4 || NON_ANSWERS.includes(o)) continue;
    const eo = esc(o);
    if (new RegExp(`(?:correct|right|best)\\s+(?:answer|option|choice)\\s+is\\s+${eo}(?![a-z])|(?:^|[^a-z])${eo}\\s+is\\s+(?:the\\s+)?(?:correct|right|best)\\s+(?:answer|option|choice)`).test(le)) return i;
  }
  return null;
}

const NEGATED_STEM = /\b(?:NOT|EXCEPT)\b|\bleast\s+likely\b|\bis\s+false\b|\bincorrect\s+statement\b|\bfalse\s+statement\b/;

/// Every rule hit for one item: { rule, severity: 'severe' | 'minor', detail }.
export function ruleHits(item) {
  const hits = [];
  const add = (rule, severity, detail) => hits.push({ rule, severity, detail: String(detail).slice(0, 160) });
  const text = itemText(item);

  if (item.kind === 'mcq') {
    const options = (item.options || []).map(o => String(o).trim());
    const key = Number.isInteger(item.key) ? item.key : -1;
    if (key < 0 || key >= options.length) add('no-key', 'severe', 'The keyed answer is not one of the options.');
    const seen = new Map();
    options.forEach((o, i) => {
      const n = norm(o);
      if (!n) return;
      if (seen.has(n)) {
        const both = [seen.get(n), i];
        add('duplicate-option', both.includes(key) ? 'severe' : 'minor', `Options ${letter(both[0])} and ${letter(i)} say the same thing.`);
      } else seen.set(n, i);
    });
    const kinds = options.map(o => NON_ANSWERS.indexOf(lower(o).replace(/[.\s]+$/, '')));
    const nonIdx = kinds.map((k, i) => (k >= 0 ? i : -1)).filter(i => i >= 0);
    if (nonIdx.some(i => i !== options.length - 1)) add('non-answer-position', 'minor', '"All/none of the above" is not the last option.');
    const hasAll = kinds.some(k => k === 0 || k === 2), hasNone = kinds.some(k => k === 1 || k === 3);
    if (hasAll && hasNone) add('all-and-none', 'minor', 'Both "all of the above" and "none of the above" are options.');
    if (key >= 0 && key < options.length) {
      const keyText = lower(options[key]);
      const said = explainedAnswer(item.explanation, options);
      if (said !== null && said !== key) {
        add('key-explanation-conflict', 'severe', `The key is ${letter(key)} but the explanation says ${letter(said)}.`);
      }
      if (keyText.length >= 4 && !NON_ANSWERS.includes(keyText)) {
        const kt = esc(keyText);
        if (new RegExp(`(?:^|[^a-z])${kt}\\s+is\\s+(?:not\\s+(?:the\\s+)?(?:correct|right|answer)|incorrect|wrong)`).test(lower(item.explanation))) {
          add('key-called-wrong', 'severe', 'The explanation calls the keyed answer wrong.');
        }
      }
      const negated = NEGATED_STEM.test(String(item.stem || ''));
      if (negated && keyText.length >= 4 && new RegExp(`${esc(keyText)}\\s+is\\s+(?:a\\s+)?(?:true|correct|recognised|recognized|typical|characteristic)\\b`).test(lower(item.explanation))) {
        add('negation-mismatch', 'minor', 'The stem asks for the exception, but the explanation calls the key true.');
      }
      // "all of the above" keyed while one option is "none of the above"
      if (kinds[key] === 0 && hasNone) add('all-above-contradiction', 'severe', '"All of the above" is keyed although "none of the above" is an option.');
      // numbers: the stem's lab values quoted differently in the explanation
      const stemLabs = labValues(item.stem), expLabs = labValues(item.explanation);
      for (const a of stemLabs) {
        const b = expLabs.find(x => x.analyte === a.analyte && x.unit === a.unit);
        if (b && Math.abs(a.value - b.value) > Math.max(0.05 * Math.abs(a.value), 1e-9)) {
          add('numbers-disagree', 'minor', `The stem gives ${a.analyte} ${a.value} but the explanation says ${b.value}.`);
          break;
        }
      }
      const keyDose = doses(options[key]);
      if (keyDose.length === 0) {
        const keyNum = String(options[key]).match(/^\s*(\d+(?:\.\d+)?)\s*(mg|g|mcg|ml|units?|%)\b/i);
        if (keyNum) {
          const u = lower(keyNum[2]);
          const inExp = [...lower(item.explanation).matchAll(new RegExp(`(\\d+(?:\\.\\d+)?)\\s*${esc(u)}\\b`, 'g'))].map(m => num(m[1]));
          if (inExp.length && !inExp.includes(num(keyNum[1]))) add('numbers-disagree', 'minor', `The key says ${keyNum[0].trim()} but the explanation gives ${inExp[0]} ${u}.`);
        }
      }
    }
  }

  for (const d of doses(text)) {
    const [lo, hi] = DRUGS[d.drug];
    if (d.mg > hi * 2 || d.mg < lo / 5) add('dose-range', 'severe', `${d.said}: outside any usual dose of ${d.drug} (${fmt(lo)}–${fmt(hi)} mg).`);
    else if (d.mg > hi || d.mg < lo) add('dose-range', 'minor', `${d.said}: unusual for ${d.drug} (${fmt(lo)}–${fmt(hi)} mg).`);
  }
  for (const v of labValues(text)) {
    const ranges = LABS[v.analyte];
    const r = ranges[v.unit];
    if (!r) {
      if (v.unit.includes('/') && v.name.length > 2) add('lab-unit', 'minor', `${v.said}: ${v.analyte} is not reported in ${v.unit}.`);
      continue;
    }
    if (v.value < r[0] || v.value > r[1]) add('lab-implausible', 'severe', `${v.said}: not a possible ${v.analyte} in ${v.unit || 'these units'} (wrong unit?).`);
  }
  for (const s of statedRanges(text)) {
    const r = LABS[s.analyte]?.[s.unit] || (!s.unit ? Object.values(LABS[s.analyte] || {})[0] : null);
    if (!r) continue;
    const off = (x, y) => Math.abs(x - y) > Math.max(0.2 * Math.abs(y), 1e-9);
    if (off(s.lo, r[2]) || off(s.hi, r[3])) add('reference-range', 'severe', `Normal ${s.analyte} is about ${r[2]}–${r[3]}${s.unit ? ' ' + s.unit : ''}, not ${s.lo}–${s.hi}.`);
  }
  // one analyte said to go both up and down
  const t = lower(text);
  for (const name of new Set(Object.values(LAB_NAMES))) {
    const up = new RegExp(`\\b${esc(name)}\\s+(?:is\\s+|are\\s+|level\\s+is\\s+)?(?:increased|elevated|raised|high)\\b`).test(t);
    const down = new RegExp(`\\b${esc(name)}\\s+(?:is\\s+|are\\s+|level\\s+is\\s+)?(?:decreased|reduced|low|lowered)\\b`).test(t);
    if (up && down) add('direction-conflict', 'minor', `${name} is said to be both raised and lowered.`);
  }
  return hits;
}

const fmt = x => (x >= 1 ? String(Math.round(x * 100) / 100) : String(x));

/// The words the checker, the cache and the rules see for an item.
export function itemText(item) {
  if (item.kind === 'mcq') {
    const options = (item.options || []).map((o, i) => `${letter(i)}. ${o}`).join('\n');
    const key = Number.isInteger(item.key) && item.key >= 0 && item.key < (item.options || []).length
      ? `${letter(item.key)}. ${item.options[item.key]}` : 'none';
    return `${item.stem || ''}\n${options}\nKeyed answer: ${key}\nExplanation: ${item.explanation || ''}`.trim();
  }
  return String(item.text || '').trim();
}

const STOP = new Set(['the', 'and', 'with', 'for', 'that', 'this', 'which', 'what', 'most', 'best', 'following', 'patient',
  'next', 'step', 'from', 'into', 'than', 'then', 'there', 'their', 'have', 'been', 'were', 'will', 'would', 'should',
  'these', 'those', 'also', 'over', 'under', 'about', 'after', 'before', 'other', 'answer', 'explanation', 'keyed']);

export function terms(text) {
  return new Set(lower(text).split(/[^a-z]+/).filter(w => w.length >= 4 && !STOP.has(w)));
}

/// How much of the item's own vocabulary its source contains, 0-1. Null
/// when there is no source.
export function sourceMatch(item, source) {
  if (!source || !String(source).trim()) return null;
  const mine = terms(itemText(item)), theirs = terms(source);
  if (!mine.size) return 0;
  let shared = 0;
  for (const w of mine) if (theirs.has(w)) shared++;
  return shared / mine.size;
}
