// The public exam questions the verification bench runs on, read from the
// Hugging Face datasets-server pages fetch.sh saves, into one shape:
// { id, source, kind: 'mcq', stem, options, key, explanation }.
import { readFileSync } from 'node:fs';

export function loadQuestions(files) {
  const items = [];
  for (const f of files) {
    const rows = JSON.parse(readFileSync(f, 'utf8')).rows || [];
    for (const { row } of rows) {
      const q = questionOf(row, items.length);
      if (q) items.push(q);
    }
  }
  return items.filter(valid);
}

const valid = q => Number.isInteger(q.key) && q.key >= 0 && q.key < q.options.length && q.stem;

/// One datasets-server row as a question, by its shape; null for a row the
/// bench does not take (and a question whose key does not fit its options
/// is left out by the caller, after numbering, as before). `n`: a running
/// number, for sets with no id of their own.
export function questionOf(row, n = 0) {
  let q = null;
  if ('opa' in row) {
    if (row.choice_type && row.choice_type !== 'single') return null;
    q = { id: `medmcqa:${row.id}`, source: 'MedMCQA', kind: 'mcq', stem: row.question,
      options: [row.opa, row.opb, row.opc, row.opd], key: row.cop, explanation: row.exp || '' };
  } else if (row.options && row.medical_task) {
    // MedXpertQA (expert level, specialty boards, ten options): the stem
    // carries its own "Answer Choices:" copy, cut off here
    const letters = Object.keys(row.options).sort();
    q = { id: `medxpertqa:${row.id}`, source: 'MedXpertQA', kind: 'mcq',
      stem: row.question.split(/\nAnswer Choices:/)[0], options: letters.map(l => row.options[l]),
      key: letters.indexOf(row.label), explanation: '', system: row.body_system, task: row.medical_task };
  } else if (row.options) {
    const letters = Object.keys(row.options).sort();
    q = { id: `medqa:${n}`, source: 'MedQA', kind: 'mcq', stem: row.question,
      options: letters.map(l => row.options[l]), key: letters.indexOf(row.answer_idx), explanation: '' };
  } else if ('op1' in row) {
    // CareQA: Spain's specialist-training entrance exams, in English
    if (!['Medicine', 'Pharmacology', 'Nursing'].includes(row.category)) return null;
    const options = ['op1', 'op2', 'op3', 'op4', 'op5'].map(k => row[k]).filter(o => o !== undefined && o !== null && o !== '');
    q = { id: `careqa:${row.unique_id}`, source: `CareQA ${row.category}`, kind: 'mcq', stem: row.question,
      options, key: Number(row.cop) - 1, explanation: '' };
  }
  return q;
}

/// questionOf, keeping only a question whose key fits its options.
export const validQuestionOf = (row, n = 0) => { const q = questionOf(row, n); return q && valid(q) ? q : null; };

/// A seeded shuffle, so a run can be repeated exactly.
export function seeded(seed) {
  let s = seed >>> 0 || 1;
  return () => ((s = (s * 1664525 + 1013904223) >>> 0) / 4294967296);
}

/// The bench's checks, in a seeded order: `perSource` questions from each
/// source, each once with its true key and once with a distractor keyed
/// instead. layer.mjs runs them; policy.mjs rebuilds them to know each
/// check's keyed letter.
export function benchCases(all, { wanted, perSource, seed }) {
  const rand = seeded(seed);
  const chosen = [];
  for (const src of wanted) {
    const pool = all.filter(q => q.source === src);
    for (let i = pool.length - 1; i > 0; i--) { const j = Math.floor(rand() * (i + 1)); [pool[i], pool[j]] = [pool[j], pool[i]]; }
    chosen.push(...pool.slice(0, perSource));
  }
  const cases = [];
  for (const q of chosen) {
    cases.push({ truth: 'right', item: { ...q, id: `${q.id}#right` } });
    const others = q.options.map((_, i) => i).filter(i => i !== q.key);
    const wrong = others[Math.floor(rand() * others.length)];
    cases.push({ truth: 'wrong', item: { ...q, id: `${q.id}#wrong`, key: wrong } });
  }
  for (let i = cases.length - 1; i > 0; i--) { const j = Math.floor(rand() * (i + 1)); [cases[i], cases[j]] = [cases[j], cases[i]]; }
  return { chosen, cases };
}
