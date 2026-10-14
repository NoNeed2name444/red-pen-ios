// The items Layer 6 scores, as JSON lines: { id, kind, stem, options, key,
// truth } for a question, { id, kind: 'card', front, back, truth } for a
// card. `truth` ('right' or 'wrong') is the label the thresholds are tuned
// on; an item without one is triaged, not tuned on.
//
//   node tools/jev-standin/items.mjs --labels own.jsonl > items.jsonl
//     our own labelled items (the ones §22a asks for), passed through
//   node tools/jev-standin/items.mjs --bench DIR [--per-source 100] > items.jsonl
//     a stand-in until those exist: public exam questions (fetch.sh's
//     folder), each with its true key ('right') and a distractor keyed
//     ('wrong'). Not our own items, so thresholds from them are a start.
import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import { loadQuestions, benchCases } from '../verification-bench/datasets.mjs';

const arg = (name, fallback = null) => { const i = process.argv.indexOf(`--${name}`); return i > 0 ? process.argv[i + 1] : fallback; };
const out = [];
if (arg('labels')) {
  for (const line of readFileSync(arg('labels'), 'utf8').split('\n')) {
    if (!line.trim()) continue;
    const r = JSON.parse(line);
    if (r.kind === 'card' ? typeof r.front === 'string' && typeof r.back === 'string' : Array.isArray(r.options) && Number.isInteger(r.key)) out.push(r);
  }
} else if (arg('bench')) {
  const dir = arg('bench');
  const all = loadQuestions(readdirSync(dir).filter(f => f.endsWith('.json')).map(f => join(dir, f)));
  const wanted = (arg('sources', 'MedQA,MedMCQA,CareQA Medicine')).split(',');
  const { cases } = benchCases(all, { wanted, perSource: Number(arg('per-source', '100')), seed: Number(arg('seed', '11')) });
  for (const c of cases) out.push({ id: c.item.id, source: c.item.source, kind: 'mcq', stem: c.item.stem, options: c.item.options, key: c.item.key, truth: c.truth });
} else {
  console.error('Give --labels FILE (our own labelled items) or --bench DIR (public questions, a stand-in).');
  process.exit(2);
}
process.stdout.write(out.map(r => JSON.stringify(r)).join('\n') + '\n');
