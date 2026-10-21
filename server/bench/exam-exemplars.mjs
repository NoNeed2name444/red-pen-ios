// Builds the exam-style exemplar index: a few short, real exam items per exam
// style and topic, shown to the question writer as few-shot examples of how
// that exam asks (server/exams.js, ios/RedPen/Shared/Exam/ExamExemplars.swift).
//
//   node server/bench/exam-exemplars.mjs            # writes both outputs
//   PER_DOMAIN=3 PAGES=20 node server/bench/exam-exemplars.mjs
//
// Sources - openly licensed only, loaded from Hugging Face's dataset server at
// build time, nothing but the chosen items committed:
//   MedQA (Jin et al. 2020, github.com/jind11/MedQA, MIT licence), US
//     questions via the GBaker/MedQA-USMLE-4-options mirror (CC-BY-4.0), TRAIN
//     split only - the accuracy engine trains and is tested on the test
//     split, so an exemplar is never also an item it is scored on. Its
//     meta_info splits Step 1 from Step 2&3 items.
//   MedMCQA (Pal et al. 2022, openlifescienceai/medmcqa, Apache-2.0): AIIMS
//     and NEET-PG entrance questions, TRAIN split, the style of NEET-PG,
//     INI-CET and FMGE (and the short anatomy / physiology recall of MRCS A).
// Checked and NOT used: UWorld, Amboss, PassMedicine, Pastest, BMJ OnExamination,
// Kaplan, NBME / MCC / AMC / Prometric practice forms (all copyrighted, no
// licence to reuse), Medbullets and JAMA Clinical Challenge sets (copyrighted
// sources even where a research copy exists), HEAD-QA (Spanish MIR, not an
// exam we list). PLAB, MRCP, MRCS, SMLE, the Gulf exams and the Egyptian exam
// publish no openly licensed items, so they borrow the nearest open style and
// their format rules do the rest.
//
// Each item is kept whole or not at all (a vignette cut in half teaches the
// wrong length): stems outside the length window are skipped, as are items
// that need a picture, "all of the above" options, or long options. Every
// kept item carries a short hash of its original stem, so it can be traced
// back to its source row and never collides with another.
//
// Env: OUT_JS, OUT_SWIFT (paths), PER_DOMAIN (per source and topic), PAGES
//      (pages of 100 rows per source), SEED, ROWS_BASE (the dataset server)

import { writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { classifyDomain, DOMAINS } from '../exams.js';

const here = dirname(fileURLToPath(import.meta.url));
const ROWS = (process.env.ROWS_BASE || 'https://datasets-server.huggingface.co').replace(/\/+$/, '');
const OUT_JS = process.env.OUT_JS || join(here, '..', 'exam-exemplars.js');
const OUT_SWIFT = process.env.OUT_SWIFT || join(here, '..', '..', 'ios', 'RedPen', 'Shared', 'Exam', 'ExamExemplarData.swift');
const PER_DOMAIN = Number(process.env.PER_DOMAIN || 2);
const PAGES = Number(process.env.PAGES || 16);
const SEED = Number(process.env.SEED || 20260925);

export const DATASETS = {
  medqa: { path: 'GBaker%2FMedQA-USMLE-4-options', config: 'default', split: 'train', rows: 10178 },
  medmcqa: { path: 'openlifescienceai%2Fmedmcqa', config: 'default', split: 'train', rows: 182822 },
};

export const LICENCES = [
  'MedQA (Jin et al. 2020, https://github.com/jind11/MedQA) - MIT licence; mirror GBaker/MedQA-USMLE-4-options, CC-BY-4.0',
  'MedMCQA (Pal et al. 2022, https://huggingface.co/datasets/openlifescienceai/medmcqa) - Apache-2.0',
];

/// FNV-1a, 32-bit, as 8 hex digits.
export function fnv(text) {
  let h = 0x811c9dc5;
  for (const byte of new TextEncoder().encode(String(text))) {
    h ^= byte;
    h = Math.imul(h, 0x01000193) >>> 0;
  }
  return h.toString(16).padStart(8, '0');
}

const tidy = s => String(s ?? '').replace(/\s+/g, ' ').trim();
const NEEDS_PICTURE = /\b(image|figure|photograph|picture|shown (below|above|here)|diagram|marked (as|with)|x-ray shown|graph (below|above))\b/i;
const NON_ANSWER = /^(all|none|both) (of the )?(above|these)|^all$|^none$/i;

/// Limits per style: MedQA's vignettes are long by nature, MedMCQA's short.
export const LIMITS = {
  medqa: { minStem: 200, maxStem: 720, maxOption: 70 },
  medmcqa: { minStem: 15, maxStem: 240, maxOption: 60 },
};

/// A MedQA row as an exemplar, or null when it cannot be one.
export function fromMedQA(row) {
  const letters = Object.keys(row?.options || {}).sort();
  const o = letters.map(l => tidy(row.options[l]));
  const a = letters.indexOf(tidy(row.answer_idx));
  const s = tidy(row.question);
  const lim = LIMITS.medqa;
  if (o.length < 4 || a < 0 || s.length < lim.minStem || s.length > lim.maxStem) return null;
  if (NEEDS_PICTURE.test(s) || o.some(x => !x || x.length > lim.maxOption || NON_ANSWER.test(x))) return null;
  const meta = tidy(row.meta_info).toLowerCase();
  const source = meta === 'step1' ? 'medqa-step1' : meta.startsWith('step2') ? 'medqa-step23' : null;
  if (!source) return null;
  return { source, domain: classifyDomain(s), item: { id: fnv(s), s, o, a } };
}

// MedMCQA's subjects, as our topics. Medicine, surgery and paediatrics are
// split further by what the question is about.
const SUBJECTS = {
  Anatomy: 'anatomy', Physiology: 'physiology', Biochemistry: 'biochemistry', Pathology: 'pathology',
  Pharmacology: 'pharmacology', Microbiology: 'microbiology', 'Forensic Medicine': 'forensic',
  'Social & Preventive Medicine': 'community', 'Gynaecology & Obstetrics': null, Pediatrics: 'peds',
  ENT: 'ent', Ophthalmology: 'ophthalmology', Orthopaedics: 'orthopaedics',
  Anaesthesia: 'anaesthesia', Radiology: 'radiology', 'Skin': 'derm', Psychiatry: 'psychiatry',
  Medicine: null, Surgery: 'surgery',
};

/// A MedMCQA row as an exemplar, or null.
export function fromMedMCQA(row) {
  if (row?.choice_type && row.choice_type !== 'single') return null;
  if (!(row.subject_name in SUBJECTS)) return null;   // Dental and anything unknown
  const o = [row.opa, row.opb, row.opc, row.opd].map(tidy);
  const a = Number(row.cop);
  const s = tidy(row.question);
  const lim = LIMITS.medmcqa;
  if (!(a >= 0 && a < 4) || s.length < lim.minStem || s.length > lim.maxStem) return null;
  if (NEEDS_PICTURE.test(s) || o.some(x => !x || x.length > lim.maxOption || NON_ANSWER.test(x))) return null;
  let domain = SUBJECTS[row.subject_name];
  if (row.subject_name === 'Gynaecology & Obstetrics') {
    domain = classifyDomain(`${s} ${tidy(row.topic_name)}`) === 'obstetrics' ? 'obstetrics' : 'gynaecology';
  } else if (!domain || row.subject_name === 'Surgery') {
    domain = classifyDomain(`${s} ${tidy(row.topic_name)}`) || domain || 'multisystem';
  }
  return { source: 'medmcqa', domain, item: { id: fnv(s), s, o, a } };
}

/// The index: per source and topic, up to `perDomain` items, chosen by hash
/// (so a rebuild from the same rows picks the same ones) and never two with
/// the same stem.
export function buildIndex(candidates, { perDomain = PER_DOMAIN, version = 'test' } = {}) {
  const sources = {};
  const seen = new Set();
  const sorted = candidates.filter(c => c && c.domain && DOMAINS.includes(c.domain))
    .sort((x, y) => (x.item.id < y.item.id ? -1 : x.item.id > y.item.id ? 1 : 0));
  for (const c of sorted) {
    if (seen.has(c.item.id)) continue;
    const bank = sources[c.source] ||= {};
    const list = bank[c.domain] ||= [];
    if (list.length >= perDomain) continue;
    list.push(c.item);
    seen.add(c.item.id);
  }
  // stable output: sources and topics in order
  const ordered = {};
  for (const s of Object.keys(sources).sort()) {
    ordered[s] = {};
    for (const d of Object.keys(sources[s]).sort()) ordered[s][d] = sources[s][d];
  }
  return { version, licences: LICENCES, sources: ordered };
}

export const jsSource = index =>
  '// Generated by server/bench/exam-exemplars.mjs - do not edit by hand.\n' +
  '// Openly licensed exam items (see LICENCES), for style only.\n' +
  `export const EXEMPLARS = ${JSON.stringify(index)};\n`;

export function swiftSource(index) {
  const body = JSON.stringify(index);
  if (body.includes('"""#')) throw new Error('the index cannot be put in a Swift raw string');
  // one item per line keeps the Swift file diffable and the lines short
  const pretty = JSON.stringify(index, null, 0).replace(/\},\{"id"/g, '},\n{"id"');
  return [
    '// Generated by server/bench/exam-exemplars.mjs - do not edit by hand.',
    '// Openly licensed exam items, for style only: MedQA (MIT licence, via the',
    '// CC-BY-4.0 GBaker/MedQA-USMLE-4-options mirror) and MedMCQA (Apache-2.0).',
    '// Read by ExamExemplars.swift.',
    '',
    'enum ExamExemplarData {',
    '    static let json: String = #"""',
    pretty,
    '"""#',
    '}',
    '',
  ].join('\n');
}

// MARK: the run

/// Deterministic page offsets spread over a dataset.
export function offsets(rows, pages, seed) {
  const out = new Set();
  let x = seed >>> 0;
  while (out.size < Math.min(pages, Math.floor(rows / 100))) {
    x = (Math.imul(x, 1664525) + 1013904223) >>> 0;
    out.add((x % Math.floor(rows / 100)) * 100);
  }
  return [...out].sort((a, b) => a - b);
}

async function page(set, offset) {
  const d = DATASETS[set];
  const url = `${ROWS}/rows?dataset=${d.path}&config=${d.config}&split=${d.split}&offset=${offset}&length=100`;
  for (let attempt = 0; attempt < 4; attempt++) {
    const r = await fetch(url).catch(() => null);
    if (r?.ok) return ((await r.json()).rows || []).map(x => x.row);
    await new Promise(res => setTimeout(res, 1500 * (attempt + 1)));
  }
  console.error(`could not read ${set} at ${offset}`);
  return [];
}

async function main() {
  const candidates = [];
  for (const offset of offsets(DATASETS.medqa.rows, PAGES, SEED)) {
    candidates.push(...(await page('medqa', offset)).map(fromMedQA));
    process.stdout.write('q');
  }
  for (const offset of offsets(DATASETS.medmcqa.rows, PAGES, SEED + 1)) {
    candidates.push(...(await page('medmcqa', offset)).map(fromMedMCQA));
    process.stdout.write('m');
  }
  const index = buildIndex(candidates, { perDomain: PER_DOMAIN, version: `exemplars-${new Date().toISOString().slice(0, 10)}` });
  writeFileSync(OUT_JS, jsSource(index));
  writeFileSync(OUT_SWIFT, swiftSource(index));
  const count = Object.values(index.sources).flatMap(s => Object.values(s)).reduce((n, l) => n + l.length, 0);
  console.log(`\n${count} exemplars: ` + Object.entries(index.sources).map(([s, b]) => `${s} ${Object.keys(b).length} topics`).join(', '));
}

if (import.meta.url === `file://${process.argv[1]}`) main();
