// How well does the app's cloud transcription hear a lecture? The benchmark
// window of the SLE lecture (90 s + 30 s of the red-pen-transcribe release),
// sent through the Worker with the app's own CloudTranscript prompt, and
// scored two ways against the checked reference (Gemini 3.5 Flash with the
// Step 1 prompt, red-pen-transcribe/reference/gemini-3.5-flash-step1.txt):
//
//   - the 8 key terms of the window, written in English letters
//   - the word error rate against the reference
//
// The reference is Flash's own earlier output, checked, not a hand-written
// ground truth: WER here measures agreement with that run.
//
// The scoring and the prompt-building are plain functions with no network,
// tested by tests/asr/asr-bench.test.mjs on every server-tests run. The live
// part (`run`) is used only by .github/workflows/asr-bench.yml, started by hand.
//
//   node tools/asr_bench.mjs prompt                 the app's prompt, as the app builds it
//   node tools/asr_bench.mjs score REF HYP          score a transcript file against a reference file
//   node tools/asr_bench.mjs run --audio A --reference R [--url U] [--summary S] [--show-text]
//                                                   one chunk through /transcribe/chunk
//                                                   (owner key in ASR_BENCH_KEY, never printed)
import { readFileSync, appendFileSync, existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const SHARED = join(ROOT, 'ios/RedPen/Shared');
export const WORKER = 'https://redpen-auth.vv7sh4rnnw.workers.dev';

/// The window's 8 key terms, the same patterns red-pen-transcribe scores
/// every engine with (tests/test_repair_window.py, local-pipeline.yml).
export const TERMS = {
  'mucocutaneous': /muco\s*-?\s*cutaneous/,
  'malar rash': /malar\s+rash/,
  'acute': /\bacute\b/,
  'reversible': /\breversible\b/,
  'anti-inflammatory': /anti[\s-]*inflammatory/,
  'immunosuppressive': /immuno[\s-]*suppress/,
  'chronic': /\bchronic\b/,
  'discoid rash': /discoid(\s+rash)?/,
};

// MARK: scoring

/// Words for the word error rate. As in red-pen-transcribe's nw(): lower
/// case, harakat and tatweel dropped, punctuation made a space. One
/// difference on purpose: Arabic punctuation (، ؛ ؟ ٪ ۔) also separates, where
/// the Python keeps "mucocutaneous،" as one word because ، is inside the
/// Arabic block - so the same word next to a comma was counted as an error.
export function words(text) {
  return String(text)
    .replace(/\[\d+:\d\d\]/g, ' ')                       // [01:30] timestamps, if any
    .replace(/[\u064B-\u0652\u0640]/g, '')               // harakat, tatweel
    .toLowerCase()
    .replace(/[\u060C\u061B\u061F\u066A-\u066D\u06D4]/g, ' ')
    .replace(/[^\p{L}\p{N}_\s\u0600-\u06FF'-]/gu, ' ')
    .split(/\s+/)
    .filter(Boolean);
}

/// Word error rate: word-level edit distance over the reference's length.
export function wer(reference, hypothesis) {
  const r = words(reference), h = words(hypothesis);
  let prev = Array.from({ length: h.length + 1 }, (_, j) => j);
  for (let i = 1; i <= r.length; i++) {
    const row = [i];
    for (let j = 1; j <= h.length; j++) {
      row[j] = Math.min(prev[j] + 1, row[j - 1] + 1, prev[j - 1] + (r[i - 1] === h[j - 1] ? 0 : 1));
    }
    prev = row;
  }
  return prev[h.length] / Math.max(r.length, 1);
}

/// Which of the 8 terms a transcript writes in English letters.
export function termsIn(text) {
  const t = String(text).toLowerCase();
  return Object.keys(TERMS).filter(k => TERMS[k].test(t));
}

export function score(reference, hypothesis) {
  const hits = termsIn(hypothesis);
  return {
    terms: hits.length,
    of: Object.keys(TERMS).length,
    hits,
    missed: Object.keys(TERMS).filter(k => !hits.includes(k)),
    wer: wer(reference, hypothesis),
    englishWords: (String(hypothesis).match(/[A-Za-z][A-Za-z\-']+/g) || []).length,
    arabicWords: (String(hypothesis).match(/[\u0600-\u06FF]+/g) || []).length,
  };
}

// MARK: the app's prompt, read out of its Swift

/// A Swift string literal's escapes, the ones a prompt uses.
function unescapeSwift(s) {
  return s.replace(/\\(["\\nt])/g, (_, c) => ({ n: '\n', t: '\t' }[c] ?? c));
}

/// CloudTranscript.prompt(vocabulary:language:), rebuilt from
/// CloudTranscript.swift by translating its body to JavaScript: string
/// literals, `rules` built with = [...], += [...] and append, a switch and an
/// if on the language, joined(separator:). Anything else in it (an
/// interpolation, a call this does not know) throws, so a change there stops
/// the benchmark rather than sending a prompt the app does not send.
export function promptFromSwift(source, vocabulary, language = 'mixed') {
  const head = source.match(/static func prompt\(vocabulary: \[String\](?:, language: LectureLanguage = \.mixed)?\) -> String \{\n/);
  if (!head) throw new Error('CloudTranscript.prompt(vocabulary:) not found');
  // the body: up to the brace that closes the function, skipping strings
  const from = head.index + head[0].length;
  let depth = 1, i = from, inStr = false;
  for (; i < source.length && depth; i++) {
    const c = source[i];
    if (inStr) { if (c === '\\') i++; else if (c === '"') inStr = false; }
    else if (c === '"') inStr = true;
    else if (c === '{') depth++;
    else if (c === '}') depth--;
  }
  const body = source.slice(from, i - 1);
  if (/\\\(/.test(body)) throw new Error('the prompt now interpolates; teach asr_bench.mjs');
  if (body.includes('"""')) throw new Error('the prompt uses a multi-line literal; teach asr_bench.mjs');
  const arrays = [], cases = [];
  const js = body.split('\n').map(line => {
    const code = line.replace(/"(?:[^"\\]|\\.)*"/g, '""');   // strings blanked for matching
    let m;
    if (/^\s*var rules: \[String\]\s*$/.test(code)) return 'let rules;';
    if ((m = code.match(/^(\s*)(?:var )?rules (\+?)= \[\s*$/))) {
      arrays.push(m[2]); return line.replace(/(?:var )?rules \+?= \[/, m[2] ? 'rules.push(...[' : 'rules = [');
    }
    if ((m = code.match(/^\s*(?:var )?rules (\+?)= \[[",\s]*\]\s*$/)))
      return line.replace(/(?:var )?rules \+?= \[(.*)\]\s*$/, m[1] ? 'rules.push(...[$1]);' : 'rules = [$1];');
    if (/^\s*\]\s*$/.test(code)) {
      if (!arrays.length) throw new Error('an unexpected ] in the prompt');
      return line.replace(']', arrays.pop() ? ']);' : '];');
    }
    if (/^\s*switch language \{\s*$/.test(code)) { cases.push(0); return 'switch (language) {'; }
    if ((m = code.match(/^\s*case \.(\w+):\s*$/))) return (cases[cases.length - 1]++ ? 'break; ' : '') + `case '${m[1]}':`;
    if (/^\s*if language == \.\w+ \{\s*$/.test(code)) return line.replace(/if language == \.(\w+) \{/, "if (language === '$1') {");
    if (/^\s*if !vocabulary\.isEmpty \{\s*$/.test(code)) return 'if (vocabulary.length) {';
    if (/^\s*\}\s*$/.test(code)) return '}';
    if (/^\s*return text\s*$/.test(code)) return 'return text;';
    if (/^\s*(?:\/\/.*)?$/.test(code)) return '';
    // a string, an append, an assignment or a continuation made only of
    // strings, +, joined(separator:) and the two names
    const rest = code.replace(/rules\.append\(|rules\.joined\(separator: ""\)|vocabulary\.joined\(separator: ""\)|var text \+?=|text \+=|""|\+|,|\)|\s/g, '');
    if (rest) throw new Error(`a line of the prompt this cannot read: ${line.trim()}`);
    return line.replace(/rules\.append\(/, 'rules.push(').replace(/\.joined\(separator: /g, '.join(').replace(/var text/, 'let text');
  }).join('\n');
  if (arrays.length) throw new Error('an unclosed [ in the prompt');
  return new Function('vocabulary', 'language', js)(vocabulary, language);
}

/// MedicalTerms.common from LectureTranscriber.swift, in order.
export function commonTerms(source) {
  const block = source.split('enum MedicalTerms')[1]?.match(/static let common = \[([\s\S]*?)\]/);
  if (!block) throw new Error('MedicalTerms.common not found');
  return [...block[1].matchAll(/"((?:[^"\\]|\\.)*)"/g)].map(m => unescapeSwift(m[1]));
}

/// What the app sends for a lecture with no slides: LectureImporter's
/// CloudTranscript.vocabulary(from: [], extra: MedicalTerms.common), which is
/// the common list with duplicates dropped, at most 80.
export function appPrompt(shared = SHARED) {
  const terms = commonTerms(readFileSync(join(shared, 'LectureTranscriber.swift'), 'utf8'));
  const vocab = [];
  for (const t of terms) if (!vocab.some(v => v.toLowerCase() === t.toLowerCase())) vocab.push(t);
  return promptFromSwift(readFileSync(join(shared, 'CloudTranscript.swift'), 'utf8'), vocab.slice(0, 80));
}

// MARK: the reply

/// The transcript in a /transcribe/chunk answer ({text, model}, text being
/// the phrases as JSON), one phrase a line - or null when it is not that.
/// Like CloudTranscript.phrases(fromReply:), a fenced answer still counts.
export function transcriptFromReply(reply) {
  let body = String(reply?.text ?? '').trim();
  if (body.startsWith('```')) {
    body = body.split('\n').slice(1).join('\n');
    const end = body.lastIndexOf('```');
    if (end >= 0) body = body.slice(0, end);
  }
  let phrases;
  try { phrases = JSON.parse(body); } catch { return null; }
  if (!Array.isArray(phrases)) return null;
  return phrases.map(p => String(p?.text ?? '').split(/\s+/).filter(Boolean).join(' ')).filter(Boolean).join('\n');
}

// MARK: the run page

const pct = x => `${(x * 100).toFixed(1)}%`;

/// The summary for the run page. Scores only, unless asked: the repository
/// is public, and the lecture's words are not this repository's to publish.
export function summary({ status, model, result, reference, transcript, note, showText = false, window = '' }) {
  const out = ['# Transcription benchmark', ''];
  if (window) out.push(`Window: ${window}. Prompt: the app's CloudTranscript prompt with MedicalTerms.common (no slides).`, '');
  if (status === 'skipped') { out.push(`**Skipped:** ${note}`); return out.join('\n') + '\n'; }
  if (status === 'failed') { out.push(`**Failed:** ${note}`); return out.join('\n') + '\n'; }
  const ref = score(reference, reference);
  out.push(`Model: \`${model || 'unknown'}\``, '',
    `| | Key terms | WER vs reference | English words | Arabic words |`,
    `|---|---|---|---|---|`,
    `| App prompt | **${result.terms}/${result.of}** | **${pct(result.wer)}** | ${result.englishWords} | ${result.arabicWords} |`,
    `| Reference (Flash, Step 1) | ${ref.terms}/${ref.of} | 0% | ${ref.englishWords} | ${ref.arabicWords} |`,
    '', '| Term | Reference | App prompt |', '|---|---|---|');
  for (const k of Object.keys(TERMS)) out.push(`| ${k} | ${ref.hits.includes(k) ? 'yes' : 'no'} | ${result.hits.includes(k) ? 'yes' : '**no**'} |`);
  out.push('', 'The reference is Gemini 3.5 Flash\'s own earlier transcript of this window (Step 1 prompt), checked: ' +
    'WER is agreement with that run, not with a hand transcript.');
  if (showText) out.push('', '<details><summary>Transcript</summary>', '', '```', transcript, '```', '', '</details>');
  return out.join('\n') + '\n';
}

// MARK: command line

function arg(argv, name) {
  const i = argv.indexOf(name);
  return i >= 0 ? argv[i + 1] : undefined;
}

async function run(argv) {
  const audioPath = arg(argv, '--audio'), refPath = arg(argv, '--reference');
  const url = (arg(argv, '--url') || WORKER).replace(/\/$/, '') + '/transcribe/chunk';
  const summaryPath = arg(argv, '--summary') || process.env.GITHUB_STEP_SUMMARY;
  const window = arg(argv, '--window') || '';
  const showText = argv.includes('--show-text');
  const key = process.env.ASR_BENCH_KEY || '';
  const write = text => { process.stdout.write(text); if (summaryPath) appendFileSync(summaryPath, text); };
  if (!key) { write(summary({ status: 'skipped', window, note: 'no owner key (secret AI_API_KEY) in this run.' })); return 0; }
  if (!audioPath || !existsSync(audioPath) || !refPath || !existsSync(refPath)) throw new Error('--audio and --reference must be files');
  const reference = readFileSync(refPath, 'utf8').trim();
  const audio = readFileSync(audioPath).toString('base64');
  const prompt = appPrompt();
  let response;
  try {
    response = await fetch(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${key}` },
      body: JSON.stringify({ audio, prompt }),
      signal: AbortSignal.timeout(300_000),
    });
  } catch (e) {
    write(summary({ status: 'failed', window, note: `the Worker could not be reached (${e.name}).` }));
    return 1;
  }
  const reply = await response.json().catch(() => null);
  if (response.status === 429) {
    // busy, out of quota, or the owner's 200 chunks a day used: not a result
    write(summary({ status: 'skipped', window, note: `the Worker said 429: ${reply?.message || 'busy or out of quota'}. Run it again later.` }));
    return 0;
  }
  if (response.status !== 200) {
    write(summary({ status: 'failed', window, note: `the Worker answered ${response.status}: ${reply?.message || 'no message'}.` }));
    return 1;
  }
  const transcript = transcriptFromReply(reply);
  if (transcript === null) {
    write(summary({ status: 'failed', window, note: `the reply was not the phrases JSON asked for (model ${reply?.model || 'unknown'}).` }));
    return 1;
  }
  const result = score(reference, transcript);
  write(summary({ status: 'ok', model: reply.model, result, reference, transcript, showText, window }));
  return 0;
}

async function main(argv) {
  const [cmd] = argv;
  if (cmd === 'prompt') { process.stdout.write(appPrompt() + '\n'); return 0; }
  if (cmd === 'score') {
    const [, refPath, hypPath] = argv;
    const s = score(readFileSync(refPath, 'utf8'), readFileSync(hypPath, 'utf8'));
    process.stdout.write(JSON.stringify(s, null, 2) + '\n');
    return 0;
  }
  if (cmd === 'run') return run(argv.slice(1));
  process.stderr.write('usage: asr_bench.mjs prompt | score REF HYP | run --audio A --reference R\n');
  return 2;
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  main(process.argv.slice(2)).then(code => process.exit(code), e => { console.error(e.message); process.exit(1); });
}
