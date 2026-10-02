// The public exam questions the verification bench runs on, read from the
// Hugging Face datasets-server pages fetch.sh saves, into one shape:
// { id, source, kind: 'mcq', stem, options, key, explanation }.
import { readFileSync } from 'node:fs';

export function loadQuestions(files) {
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
        // CareQA: Spain's specialist-training entrance exams, in English
        if (!['Medicine', 'Pharmacology', 'Nursing'].includes(row.category)) continue;
        const options = ['op1', 'op2', 'op3', 'op4', 'op5'].map(k => row[k]).filter(o => o !== undefined && o !== null && o !== '');
        items.push({ id: `careqa:${row.unique_id}`, source: `CareQA ${row.category}`, kind: 'mcq', stem: row.question,
          options, key: Number(row.cop) - 1, explanation: '' });
      }
    }
  }
  return items.filter(q => Number.isInteger(q.key) && q.key >= 0 && q.key < q.options.length && q.stem);
}

/// A seeded shuffle, so a run can be repeated exactly.
export function seeded(seed) {
  let s = seed >>> 0 || 1;
  return () => ((s = (s * 1664525 + 1013904223) >>> 0) / 4294967296);
}
