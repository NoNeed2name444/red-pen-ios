// The verification layer's sensors (server/accuracy-rules.js, mirrored on the
// phone in AccuracyRules.swift) measured on real exam questions:
//   clean    - real MedMCQA and MedQA questions as published: every hit is a
//              false alarm unless the published item really is wrong
//   planted  - the same questions with one known error put in, of a kind a
//              sensor is meant to catch: a hit of the expected rule is a catch
//   outdated - retired practice in wordings the sensor was not written from,
//              and the modern statements it must leave alone
// Writes a report and cases.json (every case with the server's hits) for the
// app-side parity run (parity.swift).
//
// Run: node tools/verification-bench/sensors.mjs <rows.json ...> [--out dir]
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { ruleHits, doses, labValues, explainedAnswer, DRUGS, LABS } from '../../server/accuracy-rules.js';

const args = process.argv.slice(2);
const outAt = args.indexOf('--out');
const out = outAt >= 0 ? args[outAt + 1] : 'verification-bench-out';
const files = args.filter((a, i) => a.endsWith('.json') && i !== outAt + 1);
mkdirSync(out, { recursive: true });

// MARK: the real questions

const items = [];
for (const f of files) {
  const rows = JSON.parse(readFileSync(f, 'utf8')).rows || [];
  for (const { row } of rows) {
    if ('opa' in row) {
      if (row.choice_type && row.choice_type !== 'single') continue;
      items.push({ id: `medmcqa:${row.id}`, source: 'MedMCQA', kind: 'mcq', stem: row.question,
        options: [row.opa, row.opb, row.opc, row.opd], key: row.cop, explanation: row.exp || '' });
    } else if (row.options && row.medical_task) {
      // MedXpertQA (expert level, specialty boards, ten options): the stem
      // carries its own "Answer Choices:" copy, cut off here
      const letters = Object.keys(row.options).sort();
      items.push({ id: `medxpertqa:${row.id}`, source: 'MedXpertQA', kind: 'mcq',
        stem: row.question.split(/\nAnswer Choices:/)[0], options: letters.map(l => row.options[l]),
        key: letters.indexOf(row.label), explanation: '', system: row.body_system, task: row.medical_task });
    } else if (row.options) {
      const letters = Object.keys(row.options).sort();
      items.push({ id: `medqa:${items.length}`, source: 'MedQA', kind: 'mcq', stem: row.question,
        options: letters.map(l => row.options[l]), key: letters.indexOf(row.answer_idx), explanation: '' });
    } else if ('op1' in row) {
      // CareQA: Spain's specialist-training entrance exam (MIR and others), in English
      if (!['Medicine', 'Pharmacology', 'Nursing'].includes(row.category)) continue;
      const options = ['op1', 'op2', 'op3', 'op4', 'op5'].map(k => row[k]).filter(o => o !== undefined && o !== null && o !== '');
      items.push({ id: `careqa:${row.unique_id}`, source: `CareQA ${row.category}`, kind: 'mcq', stem: row.question,
        options, key: Number(row.cop) - 1, explanation: '' });
    }
  }
}

const names = hits => hits.map(h => `${h.rule}:${h.severity}`);
const cases = [];
const record = (group, type, item, expect) => {
  const hits = ruleHits(item);
  const caught = expect ? hits.some(h => expect.includes(h.rule)) : null;
  cases.push({ group, type, id: item.id, item, expect: expect || null, hits: names(hits), caught,
    details: hits.map(h => h.detail) });
  return hits;
};

// MARK: clean
for (const item of items) record('clean', item.source, item, null);

// MARK: planted errors, one per copy
const lastNumber = said => (said.match(/\d+(?:[.,]\d+)?/g) || []).at(-1) || null;
const swapLast = (said, from, to) => { const i = said.lastIndexOf(from); return said.slice(0, i) + to + said.slice(i + from.length); };
let seed = 7;
const rand = () => ((seed = (seed * 1103515245 + 12345) % 2147483648) / 2147483648);
// the readers report what they matched in lower case; the change is made in
// the text as written
const replaceOnce = (text, from, to) => {
  const i = text.toLowerCase().indexOf(from.toLowerCase());
  return i < 0 ? null : text.slice(0, i) + to + text.slice(i + from.length);
};

for (const item of items) {
  const clean = names(ruleHits(item));
  const quiet = rule => !clean.some(h => h.startsWith(rule + ':'));
  // 1. the key moved to another option while the explanation still argues for the first
  if (item.explanation && quiet('key-explanation-conflict') && explainedAnswer(item.explanation, item.options) === item.key) {
    record('planted', 'wrong-key', { ...item, id: item.id + '#wrong-key', key: (item.key + 1 + Math.floor(rand() * 3)) % item.options.length },
      ['key-explanation-conflict', 'key-called-wrong']);
  }
  // 2. a distractor made a copy of the keyed answer
  if (quiet('duplicate-option') && item.options[item.key]) {
    const other = (item.key + 1) % item.options.length;
    const options = item.options.slice(); options[other] = item.options[item.key];
    record('planted', 'duplicate-key', { ...item, id: item.id + '#duplicate-key', options }, ['duplicate-option']);
  }
  // 3. a dose ten times too high, in the explanation or an option
  // only what the question asserts: the stem, the explanation and the keyed
  // option (a distractor is wrong on purpose and is not judged)
  const optionFields = item.options[item.key] !== undefined ? [`option${item.key}`] : [];
  const fieldText = f => (f.startsWith('option') ? item.options[Number(f.slice(6))] : item[f]);
  const withField = (f, text) => {
    if (!f.startsWith('option')) return { [f]: text };
    const options = item.options.slice(); options[Number(f.slice(6))] = text; return { options };
  };
  for (const field of ['explanation', 'stem', ...optionFields]) {
    const found = doses(fieldText(field)).find(d => { const r = DRUGS[d.drug]; return r && d.mg >= r[0] && d.mg <= r[1]; });
    if (!found) continue;
    const num = lastNumber(found.said);
    if (!num) continue;
    const bigger = String(Number(num.replace(',', '.')) * 10);
    const said10 = swapLast(found.said, num, bigger);
    const text = replaceOnce(fieldText(field), found.said, said10);
    if (text) {
      const c = { ...item, id: item.id + '#tenfold-' + field, ...withField(field, text) };
      record('planted', found.mg * 10 > DRUGS[found.drug][1] ? 'tenfold-dose (leaves the usual range)' : 'tenfold-dose (still inside the usual range)', c, ['dose-range']);
    }
    break;
  }
  // 4. a lab result given in a unit it is never reported in, or off by ten
  for (const field of ['stem', 'explanation']) {
    const lab = labValues(item[field]).find(v => v.unit && LABS[v.analyte]?.[v.unit]);
    if (!lab) continue;
    const r = LABS[lab.analyte][lab.unit];
    if (lab.value < r[0] || lab.value > r[1]) continue;
    const num = lastNumber(lab.said);
    if (!num) continue;
    const off = String(Number(num) * (lab.value * 10 > r[1] ? 10 : 100));
    const text = replaceOnce(item[field], lab.said, swapLast(lab.said, num, off));
    if (text) record('planted', 'lab-off-scale', { ...item, id: item.id + '#lab-' + field, [field]: text }, ['lab-implausible']);
    break;
  }
  // 5. the explanation quoting the stem's result with a different number
  if (item.explanation) {
    const stemLabs = labValues(item.stem);
    const expLabs = labValues(item.explanation);
    const pair = stemLabs.find(a => expLabs.some(b => b.analyte === a.analyte && b.unit === a.unit && b.value === a.value));
    if (pair) {
      const b = expLabs.find(x => x.analyte === pair.analyte && x.unit === pair.unit);
      const num = lastNumber(b.said);
      const changed = String(Math.round(Number(num) * 1.5 * 10) / 10);
      const text = replaceOnce(item.explanation, b.said, swapLast(b.said, num, changed));
      if (text) record('planted', 'numbers-disagree', { ...item, id: item.id + '#numbers', explanation: text }, ['numbers-disagree']);
    }
  }
}

// MARK: retired practice in new wordings, and the modern statements to leave alone
const OUTDATED = [
  'Management of asystole includes adrenaline 1 mg every 3-5 minutes and atropine 3 mg once.',
  'For pulseless electrical activity, give atropine if the rate is slow.',
  'Low dose dopamine infusion (2-5 mcg/kg/min) is given to improve renal perfusion and prevent acute renal failure in shock.',
  'Renal dose dopamine is indicated in oliguric patients after surgery.',
  'Gastric emptying with syrup of ipecac is indicated within one hour of ingestion of a toxic dose.',
  'Ipecacuanha is used to induce emesis in children who have swallowed tablets.',
  'In ventilated ICU patients, blood glucose should be kept between 80 and 110 mg/dl with intensive insulin.',
  'Critically ill patients should have glucose maintained at 4.4-6.1 mmol/L.',
  'Prophylactic lignocaine is given to all patients with acute MI to prevent ventricular fibrillation.',
  'The ratio of chest compressions to ventilations in adults is 15:2 for one or two rescuers.',
  'Hetastarch is the preferred colloid for resuscitation of septic shock.',
  'Tetrastarch is used for volume expansion in hypovolaemic shock.',
  'Treatment of acute MI: MONA - morphine, oxygen, nitrates, aspirin.',
  'All patients with suspected acute coronary syndrome should receive high-flow oxygen routinely.',
  'Strict bed rest for 2 weeks is advised for acute lumbar disc prolapse with sciatica.',
  'Ranitidine 150 mg twice daily is the drug of choice for duodenal ulcer.',
  'Co-proxamol is prescribed for moderate musculoskeletal pain in the elderly.',
  'Dextropropoxyphene is a useful analgesic for mild to moderate pain.',
  'All meconium-stained babies who are not vigorous should be intubated immediately and suctioned below the cords.',
  'Hydroxyethyl starch is a first-line fluid for sepsis-induced hypotension.',
];
const MODERN = [
  'Atropine is no longer recommended for PEA or asystole.',
  'In asystole give adrenaline 1 mg every 3-5 minutes and continue CPR.',
  'Atropine 500 micrograms is given for symptomatic bradycardia.',
  'Low-dose dopamine does not prevent acute kidney injury.',
  'Dopamine stimulates D1 receptors in the renal vasculature at low infusion rates.',
  'Activated charcoal is preferred to ipecac for gastric decontamination.',
  'In the ICU, glucose is kept between 140 and 180 mg/dl.',
  'Normal fasting plasma glucose is 70-100 mg/dl.',
  'Lidocaine is a class Ib antiarrhythmic used for ventricular arrhythmias.',
  'Adult CPR uses 30 compressions to 2 breaths.',
  'For two-rescuer infant CPR the ratio is 15:2.',
  'Starches are avoided in sepsis because they increase kidney injury.',
  'Give oxygen in ACS only if saturation is below 90%.',
  'Morphine may be given for severe ischaemic chest pain.',
  'Patients with low back pain should stay active.',
  'Famotidine is an H2 receptor antagonist.',
  'Ranitidine was withdrawn because of NDMA contamination.',
  'Co-proxamol overdose causes fatal arrhythmias.',
  'Non-vigorous meconium-stained newborns should receive ventilation without routine tracheal suction.',
  'Crystalloids are the first-line fluid for sepsis-induced hypotension.',
];
OUTDATED.forEach((text, i) => record('outdated', 'retired', { id: `outdated:${i}`, kind: 'card', text }, ['outdated-practice']));
MODERN.forEach((text, i) => record('outdated', 'modern', { id: `modern:${i}`, kind: 'card', text }, null));

// MARK: the report
const pct = (a, b) => (b ? `${(100 * a / b).toFixed(1)}%` : 'n/a');
const lines = [];
const clean = cases.filter(c => c.group === 'clean');
const anyHit = clean.filter(c => c.hits.length);
const severe = clean.filter(c => c.hits.some(h => h.endsWith(':severe')));
lines.push(`# Verification sensors on real exam questions`, '');
const sources = [...new Set(clean.map(c => c.type))];
lines.push(`Questions: ${clean.length} - ` + sources.map(src => `${src} ${clean.filter(c => c.type === src).length}`).join(', '), '');
lines.push(`| source | questions | any hit | severe hit |`, `|---|---|---|---|`);
for (const src of sources) {
  const g = clean.filter(c => c.type === src);
  lines.push(`| ${src} | ${g.length} | ${g.filter(c => c.hits.length).length} | ${g.filter(c => c.hits.some(h => h.endsWith(':severe'))).length} |`);
}
lines.push('');
lines.push(`## Clean questions (as published)`, '');
lines.push(`| | count | share |`, `|---|---|---|`);
lines.push(`| any sensor hit | ${anyHit.length} | ${pct(anyHit.length, clean.length)} |`);
lines.push(`| a severe hit (blocks Verified) | ${severe.length} | ${pct(severe.length, clean.length)} |`, '');
const byRule = {};
for (const c of clean) for (const h of c.hits) byRule[h] = (byRule[h] || 0) + 1;
lines.push(`| rule:severity | clean questions hit |`, `|---|---|`);
for (const [r, n] of Object.entries(byRule).sort((a, b) => b[1] - a[1])) lines.push(`| ${r} | ${n} |`);
lines.push('', `## Planted errors (one per copy)`, '');
lines.push(`| error planted | copies | caught | catch rate |`, `|---|---|---|---|`);
for (const type of ['wrong-key', 'duplicate-key', 'tenfold-dose (leaves the usual range)', 'tenfold-dose (still inside the usual range)', 'lab-off-scale', 'numbers-disagree']) {
  const g = cases.filter(c => c.group === 'planted' && c.type === type);
  lines.push(`| ${type} | ${g.length} | ${g.filter(c => c.caught).length} | ${pct(g.filter(c => c.caught).length, g.length)} |`);
}
const retired = cases.filter(c => c.type === 'retired'), modern = cases.filter(c => c.type === 'modern');
const flaggedModern = modern.filter(c => c.hits.some(h => h.startsWith('outdated-practice:')));
lines.push('', `## Retired practice, new wordings`, '');
lines.push(`| | statements | flagged |`, `|---|---|---|`);
lines.push(`| retired practice | ${retired.length} | ${retired.filter(c => c.caught).length} (${pct(retired.filter(c => c.caught).length, retired.length)}) |`);
lines.push(`| modern statements | ${modern.length} | ${flaggedModern.length} (${pct(flaggedModern.length, modern.length)} false alarms) |`);
const missed = retired.filter(c => !c.caught).map(c => c.item.text);
if (missed.length) lines.push('', 'Missed:', ...missed.map(t => `- ${t}`));
if (flaggedModern.length) lines.push('', 'False alarms:', ...flaggedModern.map(c => `- ${c.item.text}`));
lines.push('', `## Clean questions with a severe hit (to read by hand)`, '');
for (const c of severe.slice(0, 80)) lines.push(`- ${c.id}: ${c.hits.filter(h => h.endsWith(':severe')).join(', ')} - ${c.details[0]}`);
writeFileSync(`${out}/report.md`, lines.join('\n') + '\n');
writeFileSync(`${out}/cases.json`, JSON.stringify(cases.map(({ id, item, hits }) => ({ id, item, hits }))));
console.log(lines.join('\n'));
