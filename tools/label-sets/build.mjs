// The label sets each verification gate is measured and tuned on, built from
// public gold-labelled data whose licence allows commercial use
// (registry.json). Every label is the set's own: an exam's answer key, an
// expert fact-checker's verdict, the heading an FDA label files a sentence
// under. None comes from a model that does the checking (that would grade the
// checkers with their own answers).
//
//   tools/verification-bench/fetch.sh data            (MedQA, MedMCQA pages)
//   node tools/label-sets/build.mjs --bench data --out out/labels [--per-gate 400] [--oath 400]
//
// Writes, as JSON lines, for Layer 6 (tools/jev-standin):
//   items.jsonl  every gate's items (mcq, card, research, claim, natural) { id, gate, source, kind, stem, options, key, truth } or a card
//                { id, gate, kind: 'card', front, back, truth }, `truth` 'right' or 'wrong'
// and for Layer 7:
//   oath.jsonl   { id, text, oath: true, source, section } sentences the label files under dosing or safety
// plus sets.json: what came from where, with each set's licence.
import { readdirSync, mkdirSync, writeFileSync, readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { loadQuestions, seeded } from '../verification-bench/datasets.mjs';

const here = dirname(fileURLToPath(import.meta.url));
export const registry = JSON.parse(readFileSync(join(here, 'registry.json'), 'utf8'));

function shuffle(list, seed) {
  const rand = seeded(seed);
  const a = [...list];
  for (let i = a.length - 1; i > 0; i--) { const j = Math.floor(rand() * (i + 1)); [a[i], a[j]] = [a[j], a[i]]; }
  return a;
}

/// A question twice: with its own key ('right') and with a distractor keyed
/// ('wrong'). The wrong label is gold too: the exam's key says it is wrong.
export function questionPairs(questions, gate, seed) {
  const rand = seeded(seed);
  const out = [];
  for (const q of questions) {
    const base = { gate, source: q.source, kind: 'mcq', stem: q.stem, options: q.options };
    out.push({ ...base, id: `${q.id}#right`, key: q.key, truth: 'right' });
    const others = q.options.map((_, i) => i).filter(i => i !== q.key);
    out.push({ ...base, id: `${q.id}#wrong`, key: others[Math.floor(rand() * others.length)], truth: 'wrong' });
  }
  return out;
}

/// A short exam question as a card: its stem on the front, an option on the
/// back; the key's card is right, a distractor's is wrong.
export function cardPairs(questions, seed) {
  const rand = seeded(seed);
  const out = [];
  for (const q of questions) {
    const others = q.options.map((_, i) => i).filter(i => i !== q.key);
    const w = others[Math.floor(rand() * others.length)];
    out.push({ id: `${q.id}#right`, gate: 'card', source: q.source, kind: 'card', front: q.stem, back: q.options[q.key], truth: 'right' });
    out.push({ id: `${q.id}#wrong`, gate: 'card', source: q.source, kind: 'card', front: q.stem, back: q.options[w], truth: 'wrong' });
  }
  return out;
}

/// PubMedQA's expert-labelled questions with a yes or no decision, as
/// two-option questions read against their abstract.
export function pubmedqaItems(rows) {
  const qs = [];
  for (const { row } of rows) {
    const d = String(row.final_decision || '').toLowerCase();
    if (d !== 'yes' && d !== 'no') continue;
    const ctx = Array.isArray(row.context?.contexts) ? row.context.contexts.join(' ') : '';
    if (!ctx || !row.question) continue;
    qs.push({ id: `pubmedqa:${row.pubid}`, source: 'PubMedQA', stem: `${ctx}\n${row.question}`, options: ['yes', 'no'], key: d === 'yes' ? 0 : 1 });
  }
  return qs;
}

/// PUBHEALTH's health claims the fact-checkers called true or false, read
/// against the article: a card whose back is the claim.
const HEALTHY = /health|medic|disease|drug|vaccin|cancer|nutrition|diet|virus|infect|pregnan|heart|diabet|mental/i;
export function pubhealthItems(rows) {
  const out = [];
  for (const { row } of rows) {
    // label names, from the set's own ClassLabel: true, false, unproven, mixture
    const label = Number(row.label);
    if (label !== 0 && label !== 1) continue;
    if (!HEALTHY.test(`${row.subjects || ''} ${row.claim || ''}`)) continue;
    if (!row.main_text || !row.claim) continue;
    out.push({ id: `pubhealth:${row.claim_id}`, gate: 'claim', source: 'PUBHEALTH', kind: 'card', front: row.main_text, back: row.claim, truth: label === 0 ? 'right' : 'wrong' });
  }
  return out;
}

/// Sentences an FDA label files under a dosing or safety heading, as oath
/// claims (the source's own label). A sentence is a whole one: 6 to 60
/// words, ending in a full stop, not a heading or a cross-reference alone.
export const OATH_GOLD_SECTIONS = ['dosage_and_administration', 'contraindications', 'boxed_warning'];
export function labelSentences(text) {
  const clean = String(text || '')
    .replace(/^\s*(?:\d+(?:\.\d+)*\s+)?[A-Z][A-Z &,/-]{3,}\s+/, '')    // a section heading
    .replace(/\(\s*\d+(?:\.\d+)*(?:\s*,\s*\d+(?:\.\d+)*)*\s*\)/g, '')  // "( 2.1 )"
    .replace(/\s+/g, ' ');
  return clean.split(/(?<=[.])\s+(?=[A-Z])/)
    .map(s => s.trim())
    .filter(s => /\.$/.test(s) && !/^see\b/i.test(s))
    .filter(s => { const n = s.split(/\s+/).length; return n >= 6 && n <= 60; })
    .filter(s => !/^[^a-z]*$/.test(s));
}
export function oathFromLabels(results, perLabel = 2) {
  const out = [];
  for (const r of results) {
    for (const section of OATH_GOLD_SECTIONS) {
      const text = Array.isArray(r[section]) ? r[section].join(' ') : '';
      labelSentences(text).slice(0, perLabel).forEach((s, i) => {
        out.push({ id: `openfda:${r.set_id || r.id}:${section}:${i}`, text: s, oath: true, source: 'openFDA', section });
      });
    }
  }
  return out;
}

/// MMLU-Redux's medical subjects, where people re-checked every published
/// key: a key they found wrong ('wrong_groundtruth') is a real error, not a
/// planted one. Each such question twice: its published key ('wrong') and
/// the key the re-annotators gave ('right').
export const REDUX_SUBJECTS = ['anatomy', 'clinical_knowledge', 'college_medicine', 'professional_medicine', 'medical_genetics',
  'nutrition', 'virology', 'human_aging', 'college_biology'];
export function reduxItems(rows, subject) {
  const out = [];
  rows.forEach(({ row }, n) => {
    if (row.error_type !== 'wrong_groundtruth') return;
    const fixed = 'ABCDEFGHIJ'.indexOf(String(row.correct_answer || '').trim().toUpperCase());
    if (!Array.isArray(row.choices) || fixed < 0 || fixed >= row.choices.length || fixed === row.answer) return;
    const base = { gate: 'natural', source: `MMLU-Redux ${subject}`, kind: 'mcq', stem: row.question, options: row.choices };
    out.push({ ...base, id: `redux:${subject}:${n}#wrong`, key: row.answer, truth: 'wrong' });
    out.push({ ...base, id: `redux:${subject}:${n}#right`, key: fixed, truth: 'right' });
  });
  return out;
}

async function getJSON(url, tries = 3) {
  for (let t = 0; ; t++) {
    try {
      const r = await fetch(url, { headers: { 'user-agent': 'StethoscoreLabelSets/0.1 (+https://github.com/NoNeed2name444/red-pen-ios)' } });
      if (r.ok) return await r.json();
      if (t >= tries - 1 || (r.status < 500 && r.status !== 429)) throw new Error(`${url}: ${r.status}`);
    } catch (e) { if (t >= tries - 1) throw e; }
    await new Promise(res => setTimeout(res, 1500 * (t + 1)));
  }
}
async function hfRows(dataset, config, split, total) {
  const rows = [];
  for (let off = 0; off < total; off += 100) {
    const page = await getJSON(`https://datasets-server.huggingface.co/rows?dataset=${encodeURIComponent(dataset)}&config=${config}&split=${split}&offset=${off}&length=100`);
    rows.push(...(page.rows || []));
    if (!page.rows?.length) break;
  }
  return rows;
}

async function main() {
  const arg = (name, fallback = null) => { const i = process.argv.indexOf(`--${name}`); return i > 0 ? process.argv[i + 1] : fallback; };
  const out = arg('out', 'out/labels');
  const per = Number(arg('per-gate', '400'));       // items per gate: per/2 questions, each right and wrong
  const oathWanted = Number(arg('oath', '400'));
  mkdirSync(out, { recursive: true });
  const items = [];
  const counts = {};

  // MedQA and MedMCQA, from fetch.sh's pages: disjoint questions for each gate
  const dir = arg('bench');
  const all = dir ? loadQuestions(readdirSync(dir).filter(f => f.endsWith('.json')).map(f => join(dir, f))) : [];
  const medqa = shuffle(all.filter(q => q.source === 'MedQA'), 21);
  const medmcqa = shuffle(all.filter(q => q.source === 'MedMCQA'), 22);
  const half = Math.floor(per / 4);
  items.push(...questionPairs([...medqa.slice(0, half), ...medmcqa.slice(0, half)], 'mcq', 23));
  // short stems make cards; a stem of at most 25 words
  const short = medmcqa.slice(half).filter(q => q.stem.split(/\s+/).length <= 25 && q.options.every(o => String(o).trim()));
  items.push(...cardPairs(short.slice(0, Math.floor(per / 2)), 24));

  const pqa = shuffle(pubmedqaItems(await hfRows('qiaojin/PubMedQA', 'pqa_labeled', 'train', 1000)), 25);
  // balanced: as many yes as no keys
  const yes = pqa.filter(q => q.key === 0), no = pqa.filter(q => q.key === 1);
  const n = Math.min(Math.floor(per / 4), yes.length, no.length);
  items.push(...questionPairs([...yes.slice(0, n), ...no.slice(0, n)], 'research', 26));

  const ph = shuffle(pubhealthItems(await hfRows('bigbio/pubhealth', 'pubhealth_source', 'test', 1300)), 27);
  const t = ph.filter(r => r.truth === 'right'), f = ph.filter(r => r.truth === 'wrong');
  const m = Math.min(Math.floor(per / 2), t.length, f.length);
  items.push(...t.slice(0, m), ...f.slice(0, m));

  for (const subject of REDUX_SUBJECTS) items.push(...reduxItems(await hfRows('edinburgh-dawg/mmlu-redux-2.0', subject, 'test', 100), subject));

  for (const it of items) counts[it.gate] = counts[it.gate] || { items: 0, wrong: 0 }, counts[it.gate].items++, it.truth === 'wrong' && counts[it.gate].wrong++;

  // openFDA: prescription labels with a dosing section, a few sentences from
  // each (over-the-counter "Directions" are not clinical claims)
  const oath = [];
  for (let skip = 0; oath.length < oathWanted && skip < 2000; skip += 100) {
    const page = await getJSON(`https://api.fda.gov/drug/label.json?search=_exists_:dosage_and_administration+AND+openfda.product_type:%22HUMAN+PRESCRIPTION+DRUG%22&limit=100&skip=${skip}`);
    oath.push(...oathFromLabels(page.results || []));
  }
  const oathRows = shuffle(oath, 28).slice(0, oathWanted);

  writeFileSync(join(out, 'items.jsonl'), items.map(r => JSON.stringify(r)).join('\n') + '\n');
  writeFileSync(join(out, 'oath.jsonl'), oathRows.map(r => JSON.stringify(r)).join('\n') + '\n');
  const sets = { built: new Date().toISOString(), gates: counts, oath: oathRows.length,
                 licences: registry.sets.map(s => ({ id: s.id, licence: s.licence, gates: s.gates })) };
  writeFileSync(join(out, 'sets.json'), JSON.stringify(sets, null, 1) + '\n');
  console.log(JSON.stringify(sets));
}

if (import.meta.url === `file://${process.argv[1]}`) main().catch(e => { console.error(e.message); process.exit(1); });
