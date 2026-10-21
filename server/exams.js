// The exams a student can prepare for, as far as the server needs them: the
// format rules a question is written to and the style exemplars shown to the
// writer. The full catalogue - blueprints, papers, pass marks and the sources
// they come from - is the app's (ios/RedPen/Shared/Exam/ExamCatalog.swift);
// tests/exams.test.mjs checks the two agree on every id, option count,
// exemplar source and accuracy strictness.
//
// "Training" on an exam, honestly: no model is fine-tuned (that cannot be done
// for free). The writer is shown two or three real, openly licensed exam
// items in the exam's style for the topic at hand (few-shot), told the exam's
// format rules, and a generated set is weighted by the exam's blueprint. The
// accuracy engine's weekly-trained scorer is reported per exam slice and is
// stricter on management questions for the exams that are mostly management.
//
// Exemplars come from server/bench/exam-exemplars.mjs, which pulls MedQA
// (MIT) and MedMCQA (Apache-2.0) from Hugging Face and keeps a few short
// stems per exam style and topic (server/exam-exemplars.js). Nothing is taken
// from a copyrighted question bank.

import { EXEMPLARS } from './exam-exemplars.js';

const json = (body, status = 200) => new Response(JSON.stringify(body), {
  status, headers: { 'content-type': 'application/json' },
});
const fail = (status, message) => json({ error: message, message }, status);

/// The topic areas a blueprint is written in. The same raw values as the
/// app's ExamDomain.
export const DOMAINS = [
  'anatomy', 'physiology', 'biochemistry', 'pathology', 'pharmacology', 'microbiology', 'immunology',
  'genetics', 'multisystem', 'biostatistics', 'ethics', 'forensic', 'community',
  'cardio', 'resp', 'gi', 'endocrine', 'renal', 'neuro', 'msk', 'heme', 'id', 'derm', 'psychiatry',
  'peds', 'obstetrics', 'gynaecology', 'ent', 'ophthalmology', 'oncology', 'surgery', 'orthopaedics',
  'anaesthesia', 'radiology', 'emergency', 'geriatrics', 'palliative', 'sexualHealth', 'omm',
];

// The prompt-relevant half of each exam. words: the usual stem length;
// recall: the share of pure recall questions; strict: how much stricter the
// accuracy engine is on this exam's management questions (0-1).
const usmle = 'US conventional units (mg/dL, with °F alongside °C), US generic drug names and current US guidelines';
const uk = 'SI units (mmol/L), UK drug names and current NICE / BNF guidance; where UK and US practice differ, the UK answer is correct';
const intl = 'SI units, international generic drug names and current international guidelines (WHO and the major specialty societies)';
export const EXAMS = [
  { id: 'step1', name: 'USMLE Step 1', options: 5, words: [90, 200], recall: 0.1, exemplars: 'medqa-step1', strict: 0,
    leadIns: 'mechanism, most likely cause, underlying pathophysiology, the drug\'s mechanism or adverse effect, the expected finding', conventions: usmle },
  { id: 'step2ck', name: 'USMLE Step 2 CK', options: 5, words: [100, 220], recall: 0.05, exemplars: 'medqa-step23', strict: 0.5,
    leadIns: 'most likely diagnosis, next best step in management, most appropriate pharmacotherapy, most appropriate initial investigation', conventions: usmle },
  { id: 'step3', name: 'USMLE Step 3', options: 5, words: [100, 230], recall: 0.05, exemplars: 'medqa-step23', strict: 0.6,
    leadIns: 'most appropriate next step, screening and prevention, long-term and ambulatory management, prognosis, interpreting a study', conventions: usmle },
  { id: 'comlex1', name: 'COMLEX-USA Level 1', options: 5, words: [80, 200], recall: 0.1, exemplars: 'medqa-step1', strict: 0,
    leadIns: 'mechanism, most likely cause, osteopathic structural finding, most appropriate osteopathic manipulative treatment', conventions: usmle },
  { id: 'comlex2', name: 'COMLEX-USA Level 2-CE', options: 5, words: [90, 220], recall: 0.05, exemplars: 'medqa-step23', strict: 0.5,
    leadIns: 'most likely diagnosis, next best step, most appropriate management including osteopathic treatment', conventions: usmle },
  { id: 'plab1', name: 'PLAB 1', options: 5, words: [50, 120], recall: 0.1, exemplars: 'medqa-step23', strict: 0.3,
    leadIns: 'most likely diagnosis, most appropriate initial / immediate management, most appropriate investigation, what should be done next', conventions: uk },
  { id: 'mrcp1', name: 'MRCP(UK) Part 1', options: 5, words: [80, 200], recall: 0.15, exemplars: 'medqa-step23', strict: 0.2,
    leadIns: 'most likely diagnosis, underlying mechanism, most likely explanation for the results, most appropriate investigation', conventions: uk },
  { id: 'mrcsA', name: 'MRCS Part A', options: 5, words: [30, 110], recall: 0.3, exemplars: 'medmcqa', strict: 0.2,
    leadIns: 'which structure is most likely injured, the nerve or vessel at risk, the physiological change, the most appropriate perioperative step', conventions: uk },
  { id: 'mccqe1', name: 'MCCQE Part I', options: 5, words: [60, 150], recall: 0.05, exemplars: 'medqa-step23', strict: 0.4,
    leadIns: 'most likely diagnosis, most appropriate next step, most appropriate management, counselling and prevention', conventions: 'SI units, Canadian drug names and current Canadian guidelines' },
  { id: 'amc', name: 'AMC CAT MCQ', options: 5, words: [60, 150], recall: 0.05, exemplars: 'medqa-step23', strict: 0.3,
    leadIns: 'most likely diagnosis, most appropriate next step, most appropriate management', conventions: 'SI units, Australian drug names and current Australian guidelines (Therapeutic Guidelines, RACGP)' },
  { id: 'neetpg', name: 'NEET-PG', options: 4, words: [8, 60], recall: 0.6, exemplars: 'medmcqa', strict: 0.1,
    leadIns: 'direct one-line recall ("drug of choice for...", "most common site of...", "all of the following are true EXCEPT"), short clinical one-liners, investigation of choice', conventions: 'SI units, and the standard Indian postgraduate textbooks\' answers' },
  { id: 'inicet', name: 'INI-CET', options: 4, words: [10, 80], recall: 0.5, exemplars: 'medmcqa', strict: 0.1,
    leadIns: 'short clinical one-liners and direct recall, drug of choice, investigation of choice, next step', conventions: 'SI units, and the standard Indian postgraduate textbooks\' answers' },
  { id: 'fmge', name: 'FMGE', options: 4, words: [8, 50], recall: 0.6, exemplars: 'medmcqa', strict: 0.1,
    leadIns: 'direct one-line recall, drug of choice, most common cause, investigation of choice', conventions: 'SI units, and the standard Indian textbooks\' answers' },
  { id: 'smle', name: 'SMLE (Saudi)', options: 4, words: [30, 100], recall: 0.2, exemplars: 'medqa-step23', strict: 0.2,
    leadIns: 'most likely diagnosis, most appropriate next step, most appropriate management, best initial investigation', conventions: intl },
  { id: 'dha', name: 'DHA (Dubai)', options: 4, words: [30, 100], recall: 0.2, exemplars: 'medqa-step23', strict: 0.2,
    leadIns: 'most likely diagnosis, most appropriate next step, most appropriate management', conventions: intl },
  { id: 'doh', name: 'DOH (Abu Dhabi)', options: 4, words: [30, 100], recall: 0.2, exemplars: 'medqa-step23', strict: 0.2,
    leadIns: 'most likely diagnosis, most appropriate next step, most appropriate management', conventions: intl },
  { id: 'mohap', name: 'MOHAP (UAE)', options: 4, words: [30, 100], recall: 0.2, exemplars: 'medqa-step23', strict: 0.2,
    leadIns: 'most likely diagnosis, most appropriate next step, most appropriate management', conventions: intl },
  { id: 'qchp', name: 'QCHP / DHP (Qatar)', options: 4, words: [30, 100], recall: 0.2, exemplars: 'medqa-step23', strict: 0.2,
    leadIns: 'most likely diagnosis, most appropriate next step, most appropriate management', conventions: intl },
  { id: 'omsb', name: 'OMSB (Oman)', options: 4, words: [30, 100], recall: 0.2, exemplars: 'medqa-step23', strict: 0.2,
    leadIns: 'most likely diagnosis, most appropriate next step, most appropriate management', conventions: intl },
  { id: 'emle', name: 'Egyptian Medical Licensing Exam', options: 4, words: [20, 90], recall: 0.3, exemplars: 'medqa-step23', strict: 0.2,
    leadIns: 'most likely diagnosis, most appropriate next step, most appropriate management, direct recall', conventions: 'SI units, international generic drug names, and current guidelines as taught in Egyptian faculties of medicine' },
  { id: 'ifom', name: 'IFOM Clinical Science', options: 5, words: [90, 200], recall: 0.05, exemplars: 'medqa-step23', strict: 0.4,
    leadIns: 'most likely diagnosis, next best step in management, most appropriate pharmacotherapy', conventions: 'SI units with conventional units alongside, and current international guidelines' },
];

const byId = new Map(EXAMS.map(e => [e.id, e]));
export const exam = id => byId.get(String(id || '')) || null;

// MARK: topic

/// Words that give a topic away, per domain. Used to file an exemplar under a
/// topic and to guess a job's topic from its subject line; the app has its own
/// (the syllabus keywords), since it reads the student's library.
export const DOMAIN_WORDS = {
  anatomy: ['nerve supply', 'artery', 'muscle', 'foramen', 'plexus', 'ligament', 'embryolog', 'histolog', 'derived from', 'develops from', 'anatomical'],
  physiology: ['physiolog', 'cardiac output', 'compliance', 'action potential', 'receptor potential', 'clearance', 'hormone secretion'],
  biochemistry: ['enzyme', 'vitamin', 'glycolysis', 'metabolism', 'deficiency of', 'amino acid', 'lysosomal', 'glycogen', 'dna', 'rna', 'lipoprotein'],
  pathology: ['necrosis', 'apoptosis', 'biopsy', 'histopatholog', 'inflammation', 'granuloma', 'amyloid', 'neoplasia'],
  pharmacology: ['drug of choice', 'mechanism of action', 'adverse effect', 'side effect', 'inhibitor', 'antagonist', 'agonist', 'toxicity', 'dose'],
  microbiology: ['bacteria', 'virus', 'gram', 'culture', 'organism', 'fungal', 'parasite', 'protozoa', 'staphylococc', 'streptococc'],
  immunology: ['immunodeficien', 'antibody', 'complement', 'hypersensitivity', 't cell', 'b cell', 'transplant', 'vaccine'],
  genetics: ['autosomal', 'x-linked', 'chromosom', 'karyotype', 'trisomy', 'mutation', 'inheritance', 'genetic'],
  multisystem: ['nutrition', 'sepsis', 'fever of unknown', 'amyloidosis', 'sarcoidosis', 'multisystem', 'toxicolog'],
  biostatistics: ['sensitivity', 'specificity', 'predictive value', 'odds ratio', 'relative risk', 'confidence interval', 'study design', 'bias', 'p value', 'incidence', 'prevalence'],
  ethics: ['consent', 'confidential', 'capacity', 'ethic', 'autonomy', 'disclose', 'surrogate', 'advance directive', 'malpractice'],
  forensic: ['forensic', 'post-mortem', 'postmortem', 'autopsy', 'rigor mortis', 'livor mortis', 'medicolegal', 'ipc', 'dying declaration', 'inquest'],
  community: ['epidemic', 'screening programme', 'immunization schedule', 'national programme', 'public health', 'vector', 'sanitation', 'occupational'],
  cardio: ['heart', 'cardiac', 'myocardial', 'murmur', 'atrial', 'ventricular', 'coronary', 'hypertension', 'aortic', 'mitral', 'ecg', 'endocarditis', 'pericardi'],
  resp: ['lung', 'pulmonary', 'asthma', 'copd', 'pneumonia', 'pleural', 'bronch', 'dyspnea', 'dyspnoea', 'respiratory', 'wheez'],
  gi: ['liver', 'hepat', 'bowel', 'colon', 'gastric', 'pancrea', 'bile', 'biliary', 'esophag', 'oesophag', 'diarrh', 'abdominal pain', 'jaundice', 'cirrhosis'],
  endocrine: ['thyroid', 'diabetes', 'insulin', 'adrenal', 'cortisol', 'pituitary', 'parathyroid', 'calcium', 'prolactin', 'glucose'],
  renal: ['kidney', 'renal', 'glomerul', 'urine', 'urinary', 'nephr', 'creatinine', 'potassium', 'sodium', 'prostate', 'bladder'],
  neuro: ['brain', 'stroke', 'seizure', 'headache', 'neurolog', 'spinal cord', 'cranial nerve', 'dementia', 'parkinson', 'meningitis', 'weakness'],
  msk: ['joint', 'arthritis', 'rheumat', 'lupus', 'gout', 'back pain', 'myositis', 'vasculitis'],
  heme: ['anemia', 'anaemia', 'platelet', 'coagul', 'bleeding', 'leukemia', 'leukaemia', 'lymphoma', 'hemoglobin', 'haemoglobin', 'thrombo', 'sickle'],
  id: ['infection', 'antibiotic', 'hiv', 'tuberculosis', 'malaria', 'fever', 'sepsis', 'hepatitis b', 'hepatitis c'],
  derm: ['skin', 'rash', 'lesion', 'dermat', 'psoriasis', 'eczema', 'melanoma', 'pruritus', 'vesicle', 'papule'],
  psychiatry: ['depress', 'anxiety', 'schizophren', 'bipolar', 'psychiatr', 'suicid', 'hallucinat', 'delusion', 'personality disorder', 'alcohol use', 'substance'],
  peds: ['newborn', 'neonat', 'infant', 'child', 'toddler', 'year-old boy', 'year-old girl', 'month-old', 'pediatric', 'paediatric', 'milestone'],
  obstetrics: ['pregnan', 'gestation', 'labor', 'labour', 'postpartum', 'fetal', 'placenta', 'antenatal', 'prenatal', 'preeclampsia', 'pre-eclampsia'],
  gynaecology: ['menstrua', 'ovar', 'uter', 'cervi', 'vagina', 'amenorrh', 'menopaus', 'endometri', 'contracept', 'infertil', 'breast'],
  ent: ['ear', 'hearing', 'tonsil', 'sinus', 'larynx', 'nasal', 'epistaxis', 'otitis', 'vertigo'],
  ophthalmology: ['eye', 'vision', 'visual', 'retina', 'glaucoma', 'cataract', 'cornea', 'conjunctiv', 'uveitis', 'pupil'],
  oncology: ['cancer', 'carcinoma', 'tumor', 'tumour', 'metasta', 'chemotherapy', 'malignan', 'sarcoma'],
  surgery: ['appendic', 'hernia', 'laparotomy', 'postoperative', 'surgical', 'obstruction', 'perforat', 'cholecyst', 'surgery'],
  orthopaedics: ['fracture', 'dislocation', 'orthop', 'osteomyelitis', 'bone tumor', 'bone tumour', 'cast', 'splint'],
  anaesthesia: ['anesthe', 'anaesthe', 'intubation', 'muscle relaxant', 'local anesthetic', 'local anaesthetic', 'airway'],
  radiology: ['x-ray', 'radiograph', 'ct scan', 'mri', 'ultrasound', 'radiolog', 'imaging'],
  emergency: ['emergency department', 'trauma', 'resuscitation', 'shock', 'overdose', 'unconscious', 'collapse', 'motor vehicle'],
  geriatrics: ['elderly', 'older adult', 'falls', 'frailty', 'nursing home', 'polypharmacy'],
  palliative: ['palliative', 'end of life', 'hospice', 'terminal'],
  sexualHealth: ['sexually transmitted', 'urethral discharge', 'syphilis', 'gonorrh', 'chlamydia', 'genital'],
  omm: ['osteopathic', 'somatic dysfunction', 'counterstrain', 'muscle energy', 'hvla', 'chapman'],
};

/// The domain a piece of text is most about, or null when nothing matches.
/// A word of three letters or fewer must stand alone ("ear" is not "year");
/// a longer one is a word's beginning ("pregnan" finds "pregnancy").
const wordPatterns = new Map();
const patternFor = w => {
  if (!wordPatterns.has(w)) {
    const escaped = w.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    wordPatterns.set(w, new RegExp(w.length <= 3 ? `\\b${escaped}\\b` : `\\b${escaped}`));
  }
  return wordPatterns.get(w);
};

export function classifyDomain(text) {
  const t = String(text || '').toLowerCase();
  let best = null, bestScore = 0;
  for (const d of DOMAINS) {
    const score = (DOMAIN_WORDS[d] || []).reduce((n, w) => n + (patternFor(w).test(t) ? 1 : 0), 0);
    if (score > bestScore) { best = d; bestScore = score; }
  }
  return best;
}

// MARK: exemplars

/// Up to `n` exemplars for an exam and topic, different ones each round: the
/// exam's own source, the topic's list first, then the rest of the source, so
/// a topic with no exemplar of its own still gets the exam's style.
export function exemplarsFor(examId, domain, n = 2, round = 0, index = EXEMPLARS) {
  const e = exam(examId);
  if (!e || !index?.sources) return [];
  const bank = index.sources[e.exemplars] || {};
  const own = bank[domain] || [];
  const rest = Object.keys(bank).sort().filter(d => d !== domain).flatMap(d => bank[d]);
  if (!own.length && !rest.length) return [];
  const want = Math.min(Math.max(1, n | 0), 3, own.length + rest.length);
  // the topic's own come first each round, rotating; the rest fill in
  const out = [];
  const seen = new Set();
  const take = (list, start) => {
    for (let k = 0; k < list.length && out.length < want; k++) {
      const item = list[(start + k) % list.length];
      if (!seen.has(item.id)) { seen.add(item.id); out.push(item); }
    }
  };
  const r = Math.max(0, round | 0);
  if (own.length) take(own, (r * want) % own.length);
  if (rest.length) take(rest, (r * want) % rest.length);
  return out;
}

const letter = i => String.fromCharCode(65 + i);

/// The exemplars as the writer is shown them, with the warning that they are
/// for style only.
export function exemplarBlock(examId, domain, n = 2, round = 0, index = EXEMPLARS) {
  const items = exemplarsFor(examId, domain, n, round, index);
  if (!items.length) return '';
  const e = exam(examId);
  const lines = [
    `STYLE EXAMPLES - real ${e.name}-style items from openly licensed question banks (MedQA, MIT licence; MedMCQA, Apache-2.0), shown ONLY for tone, length and the way the question is asked. Never copy their patients, numbers, wording or answers, and take every fact from the source material:`,
  ];
  items.forEach((item, k) => {
    lines.push(`Example ${k + 1}: ${item.s}`);
    item.o.forEach((o, i) => lines.push(`  ${letter(i)}. ${o}`));
    lines.push(`  Answer: ${letter(item.a)}`);
  });
  return lines.join('\n');
}

/// A job's prompt with its {{EXEMPLARS:<exam>:<domain>:<n>}} placeholders
/// filled for this round, so each batch sees different examples. Unknown
/// exams, or none to show, leave nothing behind.
export function fillExemplars(text, round = 0, index = EXEMPLARS) {
  if (!String(text).includes('{{EXEMPLARS')) return text;
  return String(text).replace(/\{\{EXEMPLARS:([A-Za-z0-9]+):([A-Za-z]*):?(\d)?\}\}/g,
    (_, id, domain, n) => exemplarBlock(id, domain || '', Number(n || 2), round, index));
}

/// The exam's format rules, for a prompt the server writes itself.
export function formatRules(examId) {
  const e = exam(examId);
  if (!e) return '';
  const recall = Math.round(e.recall * 100);
  return [
    `EXAM FORMAT - ${e.name}:`,
    `- Exactly ${e.options} options per question.`,
    `- Stems of about ${e.words[0]}-${e.words[1]} words.`,
    `- Ask the way this exam asks: ${e.leadIns}.`,
    `- About ${recall}% pure recall questions; the rest clinical.`,
    `- Use ${e.conventions}.`,
  ].join('\n');
}

// MARK: the route

/// POST /exams/catalogue and /exams/exemplars: public, since everything in
/// them is openly licensed or published by the exams themselves.
export function examsRoute(path, body = {}) {
  if (path === '/exams/catalogue') {
    return json({ exams: EXAMS.map(({ id, name, options, words, exemplars }) => ({ id, name, options, words, exemplars })),
                  exemplarsVersion: EXEMPLARS?.version || null });
  }
  if (path === '/exams/exemplars') {
    const e = exam(body.exam);
    if (!e) return fail(400, 'Unknown exam.');
    const domain = DOMAINS.includes(body.domain) ? body.domain : (classifyDomain(body.topic) || '');
    const items = exemplarsFor(e.id, domain, Number(body.n) || 2, Number(body.round) || 0);
    return json({ exam: e.id, domain, items, licences: EXEMPLARS?.licences || [] });
  }
  return fail(404, 'No such endpoint.');
}
