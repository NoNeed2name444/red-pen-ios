#!/usr/bin/env node
// The question bank pilot (plan Task 5b steps 3 to 5), through the Worker:
// questions are written on the free chain (/v1/chat/completions, the owner's
// key, so no Google key leaves GitHub's secrets) and checked by the accuracy
// engine with the oath check (/accuracy/check). The rules are bank.mjs.
//
//   node tools/question-bank/pipeline.mjs generate --passages out/passages.jsonl --out out/candidates.jsonl [--per 3] [--limit 40]
//   node tools/question-bank/pipeline.mjs validate --candidates out/candidates.jsonl --out out/pilot [--topics-file tools/question-bank/topics.txt]
//
// Environment: QBANK_KEY (the owner key, made in the workflow from
// AI_API_KEY as the ASR bench makes it); WORKER (default the live Worker).
// validate writes <out>.jsonl (kept, every one marked for review: nothing is
// student-facing until a person has read it), <out>.dropped.jsonl (each with
// its reasons) and <out>.metrics.json.
import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { buildPrompt, parseItems, novelty, blueprintTag, accuracyItem, decide, metrics, fnv, PIPELINE_VERSION } from './bank.mjs';

const WORKER = (process.env.WORKER || 'https://redpen-auth.vv7sh4rnnw.workers.dev').replace(/\/$/, '');
const arg = (argv, name, fallback = null) => { const i = argv.indexOf(name); return i >= 0 ? argv[i + 1] : fallback; };
const readJsonl = p => readFileSync(p, 'utf8').split('\n').filter(Boolean).map(l => JSON.parse(l));

async function post(path, body, key, fetcher = fetch) {
  const r = await fetcher(`${WORKER}${path}`, {
    method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${key}` },
    body: JSON.stringify(body), signal: AbortSignal.timeout(180_000),
  });
  let json = null;
  try { json = await r.json(); } catch { /* reported below */ }
  return { status: r.status, json };
}

export async function generate(argv, key = process.env.QBANK_KEY, fetcher = fetch) {
  const passages = readJsonl(arg(argv, '--passages'));
  const per = Number(arg(argv, '--per', '3'));
  const limit = Number(arg(argv, '--limit', '40'));
  const out = [];
  let failed = 0;
  for (const passage of passages.slice(0, limit)) {
    const { status, json } = await post('/v1/chat/completions', {
      model: 'cramdown-writer', temperature: 0.4, max_tokens: 3000,
      messages: [{ role: 'user', content: buildPrompt(passage, per) }],
    }, key, fetcher);
    const items = status === 200 ? parseItems(json?.choices?.[0]?.message?.content) : [];
    if (status !== 200) { failed++; console.error(`generate: ${status} for ${passage.url}: ${json?.message ?? ''}`); }
    for (const item of items) out.push({ item, passage, model: json?.model ?? null });
  }
  writeFileSync(arg(argv, '--out'), out.map(x => JSON.stringify(x)).join('\n') + (out.length ? '\n' : ''));
  console.log(`generate: ${out.length} items from ${Math.min(limit, passages.length)} passages (${failed} requests failed)`);
  return out.length ? 0 : 1;
}

export async function validate(argv, key = process.env.QBANK_KEY, fetcher = fetch) {
  const candidates = readJsonl(arg(argv, '--candidates'));
  const topicsFile = arg(argv, '--topics-file', 'tools/question-bank/topics.txt');
  const topics = existsSync(topicsFile) ? readFileSync(topicsFile, 'utf8').split('\n').map(s => s.trim()).filter(s => s && !s.startsWith('#')) : [];
  const results = [];
  // the accuracy engine in batches of four, as the app sends them: it refuses
  // more (server/accuracy.js's BATCH, which the bank test holds this to)
  const batchSize = 4;
  for (let i = 0; i < candidates.length; i += batchSize) {
    const batch = candidates.slice(i, i + batchSize).map((c, j) => ({ ...c, id: `q${fnv(c.item.stem).toString(16)}-${i + j}` }));
    const { status, json } = await post('/accuracy/check', { items: batch.map(c => accuracyItem(c.item, c.passage, c.id)), priority: 'background' }, key, fetcher);
    const verdicts = new Map((status === 200 ? json?.items || json?.results || [] : []).map(v => [v.id, v]));
    for (const c of batch) {
      const v = verdicts.get(c.id);
      const checks = { verdict: v?.verdict ?? (status === 200 ? 'no verdict' : `not checked (${status})`), novelty: novelty(c.item) };
      const d = decide(c.item, c.passage, checks);
      results.push({ id: c.id, ...d, tag: blueprintTag(c.passage, topics), novelty: Math.round(checks.novelty * 100) / 100,
        p: v?.p ?? null, item: c.item, model: c.model,
        source: { url: c.passage.url, licence: c.passage.licence, attribution: c.passage.attribution }, version: PIPELINE_VERSION });
    }
  }
  const out = arg(argv, '--out');
  const kept = results.filter(r => r.keep).slice(0, 100);
  writeFileSync(`${out}.jsonl`, kept.map(r => JSON.stringify(r)).join('\n') + (kept.length ? '\n' : ''));
  const dropped = results.filter(r => !r.keep);
  writeFileSync(`${out}.dropped.jsonl`, dropped.map(r => JSON.stringify(r)).join('\n') + (dropped.length ? '\n' : ''));
  const m = metrics(results);
  writeFileSync(`${out}.metrics.json`, JSON.stringify(m, null, 2) + '\n');
  console.log(`validate: kept ${m.kept} of ${m.generated}; dropped for ${JSON.stringify(m.droppedFor)}`);
  return 0;
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const [cmd, ...rest] = process.argv.slice(2);
  if (!process.env.QBANK_KEY) { console.error('QBANK_KEY is not set (the owner key; see the workflow)'); process.exit(2); }
  const run = cmd === 'generate' ? generate : cmd === 'validate' ? validate : null;
  if (!run) { console.error('usage: pipeline.mjs generate|validate ...'); process.exit(2); }
  process.exit(await run(rest));
}
