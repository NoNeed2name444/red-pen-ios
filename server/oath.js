// The oath check, built from our own rules and the source proof: the open
// stand-in for Jev's Layer 7 (§22a: "Adopt, regex first, fail-closed";
// recall >= 0.99 on labelled claims, any miss blocks launch).
//
// An oath item gives a dose, names a diagnosis or a diagnostic criterion,
// recommends a treatment, or says what must not be given. Such an item is
// held to more than the models' word: provenance.js lets its lone source be
// only of the top grade (a label, a guideline or a systematic review; §17 §2
// L: "a dose never rests on weak evidence").
//
// Fail-closed: any rule that fires makes it an oath item, and so does a
// number that cannot be read for certain (a superscript, a lost power of
// ten: proof.js's reader refuses it), and so does any error here. Only a text every rule reads and none fires on is not one.
// Jev, when its key and Pro money are both there (jev.js), can still only
// add the oath check, never take it away.

import { oathClaims } from './accuracy-model.js';
import { DRUGS } from './accuracy-rules.js';
import { unreadableNumber } from './proof.js';

/// The label sections that are about dosing or safety: a claim proven from
/// one of them is an oath claim, whatever its words (the source itself files
/// it there).
export const OATH_SECTIONS = new Set(['boxed_warning', 'dosage_and_administration', 'dosage_forms_and_strengths',
  'contraindications', 'warnings_and_cautions', 'warnings', 'use_in_specific_populations', 'pregnancy', 'overdosage']);

// what must not be given, or how much at most
const SAFETY = /\b(?:contraindicat\w*|do not (?:give|use|prescribe|start|administer|exceed)|must not be (?:given|used)|should not be (?:given|used)|avoid(?:ed|ing)?|boxed warning|black[- ]box|maximum (?:daily |single )?dose|loading dose|titrat\w*|dose (?:adjust|reduc|escalat)\w*|overdose|antidote|reversal agent)\b/i;
// a diagnostic criterion or cut-off
const CRITERION = /\b(?:diagnostic criteri\w*|criteria for (?:the )?diagnosis|is diagnosed (?:when|if|by)|diagnosis (?:requires|is made)|cut-?off|threshold for (?:diagnos|treat)\w*|defined as)\b/i;
// an act on a patient
const ACT = /\b(?:give|giving|administer\w*|start(?:ing)?|initiat\w*|prescrib\w*|treat(?:ed|ing)? with|switch(?:ed|ing)? to|stop(?:ping)?|discontinu\w*|withhold\w*|commence\w*|add(?:ing)?|increase the dose|reduce the dose)\b/i;
const DRUG_SUFFIX = /\b[a-z]{3,}(?:olol|pril|sartan|statin|dipine|mab|cillin|mycin|floxacin|azole|prazole|tidine|parin|gliptin|gliflozin|glutide|triptan|setron|lukast|olone|asone|tinib|vir|xaban|gatran|cycline|sone|pam|lam)\b/i;
const DRUG_NAMES = new RegExp(`\\b(?:${Object.keys(DRUGS).map(d => d.replace(/[-]/g, '\\-')).join('|')}|insulin|heparin|warfarin|adrenaline|epinephrine|morphine|digoxin|lithium|methotrexate)\\b`, 'i');
// harm a drug can do: the words a boxed warning or a contraindication uses
// (measured on FDA label sentences, tools/label-sets: developed on one half,
// reported on the other)
const RISK = /\b(?:increase[sd]? (?:the )?risk|risk of|mortality|fatal|death|life-threatening|toxicity|hypersensitivity|anaphyla\w*|suicid\w*|lactic acidosis|stevens-johnson|serious (?:adverse|cardiovascular|infections?|reactions?)|concomitant(?:ly)? (?:use|administ\w*|prescrib\w*)|risks?|hazards?|abuse|misuse|addiction|(?:renal|hepatic) impairment|pregnan\w*|while taking|should (?:generally )?not (?:be used|be given|exceed)|not approved|is indicated|are indicated|indicated for)\b/i;
// how a drug is given: route, timing, frequency, the dose itself
const DOSING = /\b(?:dose|doses|dosage|dosages|dosing|q\.?i\.?d|b\.?i\.?d|t\.?i\.?d|once (?:daily|weekly|a day)|twice (?:daily|a day)|(?:two|three|four) times (?:daily|a day)|times (?:a|per) day|with (?:or without )?(?:food|meals?)|empty stomach|orally|by mouth|intravenous(?:ly)?|infusion|subcutaneous(?:ly)?|intramuscular(?:ly)?|intrathecal|instill\w*|inhal(?:ed|ation)|sublingual(?:ly)?|swallow\w*|administered|before breakfast|at bedtime)\b/i;
// watching a treated patient, or stopping the treatment
const MONITOR = /\b(?:monitor(?:ed|ing)?|assess(?:ed)? (?:serum|renal|hepatic|liver|kidney|therapeutic)|therapy should be|treatment should be|should be discontinued|withdraw\w*)\b/i;
const DRUG_AMOUNT = /\b\d+(?:\.\d+)?\s?(?:mg|mcg|µg|μg|micrograms?|milligrams?|g|grams?|units?|iu|ml)\b(?!\s?\/\s?(?:dl|l)\b)/i;
export const namesDrug = text => DRUG_SUFFIX.test(String(text || '')) || DRUG_NAMES.test(String(text || ''));

/// The text the oath check reads: a question's stem, options and
/// explanation; anything else's text.
export function oathText(item) {
  if (typeof item === 'string') return item;
  if (!item || typeof item !== 'object') return '';
  if (item.kind === 'mcq') return [item.stem, ...(Array.isArray(item.options) ? item.options : []), item.explanation].filter(v => typeof v === 'string').join('\n');
  return typeof item.text === 'string' ? item.text : '';
}

/// Whether an item is an oath item, and why: {oath, why: [...]}. `proof`:
/// its source proof, when there is one (a claim proven from a dosing or
/// safety section of a label is an oath claim).
export function oathCheck(item, proof = null) {
  try {
    const text = oathText(item);
    const why = [];
    const c = oathClaims(text);
    if (c.dose) why.push('dose');
    if (c.diagnosis) why.push('diagnosis');
    if (c.treatment) why.push('treatment');
    if (SAFETY.test(text)) why.push('safety');
    if (CRITERION.test(text)) why.push('criterion');
    if (RISK.test(text)) why.push('risk');
    if (DOSING.test(text)) why.push('dosing');
    if (MONITOR.test(text)) why.push('monitor');
    if (ACT.test(text) && namesDrug(text)) why.push('act');
    // a drug named beside an amount in a dose unit, however it is timed
    if (namesDrug(text) && DRUG_AMOUNT.test(text)) why.push('amount');
    for (const q of Array.isArray(proof?.quotes) ? proof.quotes : []) {
      if (q && OATH_SECTIONS.has(q.section)) { why.push('label section'); break; }
    }
    // a number in a text that cannot be read for certain may be a dose
    if (unreadableNumber(text)) why.push('unreadable');
    return { oath: why.length > 0, why };
  } catch {
    return { oath: true, why: ['error'] };
  }
}
