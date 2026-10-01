// The question bank's pipeline rules (plan Task 5b steps 3 to 5): the
// prompt, reading the model's reply, the quality rules, novelty against the
// public sets, the blueprint tag, and the keep-or-drop decision with its
// reason. Pure functions; pipeline.mjs does the network. Tested by
// tests/question-bank/bank.test.mjs.
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { licenceVerdict } from '../../governance/licences/licences.mjs';
import { EXEMPLARS } from '../../server/exam-exemplars.js';

const here = dirname(fileURLToPath(import.meta.url));
export const PROMPT = readFileSync(join(here, '../../prompts/question-bank/generate.md'), 'utf8');
export const PIPELINE_VERSION = 'qbank-1';

/// Every public exam stem the bank can be compared with (MedQA and MedMCQA,
/// as server/exam-exemplars.js carries them).
export function publicItems(exemplars = EXEMPLARS) {
  const out = [];
  for (const bySubject of Object.values(exemplars.sources || {})) {
    for (const list of Object.values(bySubject)) for (const x of list) out.push({ stem: x.s, options: x.o, answer: x.o?.[x.a] });
  }
  return out;
}

/// Two USMLE-style exemplars, chosen by the passage so prompts vary.
export function exemplarsFor(passage, pool = publicItems().filter(x => x.stem.length > 160)) {
  if (!pool.length) return '';
  const h = fnv(passage.url || passage.title || '');
  const pick = [pool[h % pool.length], pool[(h >>> 7) % pool.length]];
  return pick.map((x, i) => `${i + 1}. ${x.stem}\n${x.options.map(o => `   - ${o}`).join('\n')}\n   Answer: ${x.answer}`).join('\n');
}

export function buildPrompt(passage, count = 3) {
  return PROMPT.replace('{{count}}', String(count))
    .replace('{{exemplars}}', exemplarsFor(passage))
    .replace('{{title}}', passage.title || passage.source)
    .replace('{{passage}}', passage.text.slice(0, 6000));
}

/// The items in a model's reply: JSON, possibly fenced or with words around
/// it. Anything not shaped like an item is left out.
export function parseItems(reply) {
  const text = String(reply || '');
  const start = text.indexOf('['), end = text.lastIndexOf(']');
  if (start < 0 || end <= start) return [];
  let list;
  try { list = JSON.parse(text.slice(start, end + 1)); } catch { return []; }
  if (!Array.isArray(list)) return [];
  return list.filter(x => x && typeof x.stem === 'string' && Array.isArray(x.options) && Number.isInteger(x.key))
    .map(x => ({ stem: x.stem.trim(), options: x.options.map(o => String(o).trim()), key: x.key,
                 explanation: String(x.explanation || '').trim(), quote: String(x.quote || '').trim() }));
}

const words = s => String(s).toLowerCase().normalize('NFKD').replace(/[^\p{L}\p{N}\s]/gu, ' ').split(/\s+/).filter(Boolean);
const shingles = (s, n = 5) => { const w = words(s); const out = new Set(); for (let i = 0; i + n <= w.length; i++) out.add(w.slice(i, i + n).join(' ')); return out; };

/// What is wrong with an item, as reasons; empty when it passes.
export function qualityProblems(item, passage) {
  const problems = [];
  if (item.options.length !== 5) problems.push(`${item.options.length} options, not 5`);
  if (item.key < 0 || item.key >= item.options.length) problems.push('the key is not one of the options');
  const lower = item.options.map(o => o.toLowerCase());
  if (new Set(lower).size !== lower.length) problems.push('two options are the same');
  if (lower.some(o => !o)) problems.push('an empty option');
  if (lower.some(o => /\b(all|none) of the above\b|\bboth [a-e] and [a-e]\b/.test(o))) problems.push('an "all/none of the above" option');
  if (/\b(not|except)\b[^.?]*\?\s*$/i.test(item.stem) || /\bNOT\b|\bEXCEPT\b/.test(item.stem)) problems.push('a negatively worded stem');
  if (item.stem.length < 40) problems.push('the stem is too short to be a question');
  if (item.stem.length > 1200) problems.push('the stem is too long');
  if (!item.stem.includes('?') && !/:\s*$/.test(item.stem)) problems.push('the stem asks nothing');
  if (!item.explanation || item.explanation.length < 40) problems.push('no real explanation');
  if (/\boption [a-e]\b|\b\(?[a-e]\)\s/i.test(item.explanation)) problems.push('the explanation names options by letter (they are shown shuffled)');
  // grounded: the quoted words are in the passage, and the stem is not one of its sentences
  const text = words(passage.text).join(' ');
  const quote = words(item.quote).join(' ');
  if (!quote || quote.split(' ').length < 4 || !text.includes(quote)) problems.push('its quote is not in the passage');
  const passageShingles = shingles(passage.text, 8);
  if ([...shingles(item.stem, 8)].some(s => passageShingles.has(s))) problems.push('the stem copies the passage');
  return problems;
}

/// The highest share of the item's 5-word shingles found in any public
/// stem: 0 is new, 1 is a copy.
export function novelty(item, publics = publicItems()) {
  const mine = shingles(`${item.stem} ${item.options[item.key] || ''}`);
  if (!mine.size) return 0;
  let worst = 0;
  for (const p of publics) {
    const theirs = shingles(`${p.stem} ${p.answer || ''}`);
    let shared = 0;
    for (const s of mine) if (theirs.has(s)) shared++;
    worst = Math.max(worst, shared / mine.size);
  }
  return worst;
}
export const NOVELTY_LIMIT = 0.3;

/// The blueprint tag: the topic the passage was fetched for, else the
/// topic list's first that its title or text names.
export function blueprintTag(passage, topics) {
  if (passage.topic) return passage.topic;
  const hay = `${passage.title} ${passage.text.slice(0, 2000)}`.toLowerCase();
  return topics.find(t => hay.includes(t.toLowerCase())) || 'untagged';
}

/// Topics where a wrong item could hurt someone: always for a human, even
/// when every check passes.
const HIGH_STAKES = /\b(dose|dosage|mg\/kg|mg|units?\/kg|overdose|pregnan|paediatric|pediatric|neonat|infant|contraindicat|anticoagul|insulin|chemotherap|toxic)/i;
export const highStakes = item => HIGH_STAKES.test(`${item.stem} ${item.options.join(' ')} ${item.explanation}`);

/// The accuracy engine's item for /accuracy/check.
export const accuracyItem = (item, passage, id) => ({ id, kind: 'mcq', stem: item.stem, options: item.options,
  key: item.key, explanation: item.explanation, source: passage.text.slice(0, 20000) });

/// Keep or drop, with every reason. `checks` = { verdict, novelty }.
export function decide(item, passage, checks) {
  const reasons = [];
  const licence = licenceVerdict({ source: passage.source, licence: passage.licence, url: passage.url });
  if (!licence.ok) reasons.push(`licence: ${licence.reason}`);
  reasons.push(...qualityProblems(item, passage).map(p => `quality: ${p}`));
  if (checks.novelty > NOVELTY_LIMIT) reasons.push(`novelty: ${Math.round(checks.novelty * 100)}% of it is in a public set`);
  if (checks.verdict !== 'verified') reasons.push(`accuracy: ${checks.verdict || 'not checked'}`);
  return { keep: reasons.length === 0, reasons, review: highStakes(item) ? 'required (high stakes)' : 'required' };
}

/// The pilot's numbers.
export function metrics(results) {
  const kept = results.filter(r => r.keep);
  const why = {};
  for (const r of results) for (const reason of r.reasons) { const k = reason.split(':')[0]; why[k] = (why[k] || 0) + 1; }
  const tags = {};
  for (const r of kept) tags[r.tag] = (tags[r.tag] || 0) + 1;
  return { version: PIPELINE_VERSION, generated: results.length, kept: kept.length,
           keptShare: results.length ? Math.round(kept.length / results.length * 1000) / 1000 : 0,
           droppedFor: why, highStakes: kept.filter(r => r.review.startsWith('required (high')).length, byTag: tags };
}

export function fnv(s) {
  let h = 0x811c9dc5;
  for (let i = 0; i < s.length; i++) { h ^= s.charCodeAt(i); h = Math.imul(h, 0x01000193) >>> 0; }
  return h >>> 0;
}
