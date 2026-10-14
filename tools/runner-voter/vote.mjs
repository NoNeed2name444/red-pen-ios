// A runner voter: one open-weight model (models.json), served on this
// machine's CPU by the engine models.json pins, solves the day's ladder
// questions blind, with the very prompt the Worker's own blind voters get
// (votePrompt, blind) and read the same way (parseVotes). No key, no network
// beyond this machine. Run by .github/workflows/proof-ladder.yml.
//
//   node tools/runner-voter/vote.mjs --items items.json --model NAME --out ballots.json \
//     [--server http://127.0.0.1:8080] [--hours 4] [--batch 4]
import { readFileSync, writeFileSync } from 'node:fs';
import { request } from 'node:http';
import { votePrompt, parseVotes } from '../../server/accuracy.js';

/// One batch's chat request for the local server: blind, deterministic, and
/// held to JSON, with room for one short answer per question.
export function requestFor(items, model) {
  return {
    model,
    messages: votePrompt(items.map(item => ({ item, evidence: [] })), { blind: true }),
    temperature: 0,
    max_tokens: 96 * items.length + 64,
    response_format: { type: 'json_object' },
  };
}

/// A batch's answers by item id: { id: { answer, risk } }, only the
/// questions answered with a letter among the options.
export function answersOf(items, content) {
  const out = {};
  parseVotes(content, items.length).forEach((v, n) => {
    if (v?.answer && v.answer.charCodeAt(0) - 65 < items[n].options.length) out[items[n].id] = { answer: v.answer, risk: v.risk };
  });
  return out;
}

/// A POST to the local server with no time limit of its own (fetch gives up
/// waiting for headers after five minutes; a CPU batch can take longer).
function post(url, body) {
  return new Promise((resolve, reject) => {
    const req = request(url, { method: 'POST', headers: { 'content-type': 'application/json' } }, res => {
      let text = '';
      res.setEncoding('utf8');
      res.on('data', c => { text += c; });
      res.on('end', () => resolve({ ok: res.statusCode === 200, status: res.statusCode, text }));
    });
    req.on('error', reject);
    req.end(JSON.stringify(body));
  });
}

async function main() {
  const arg = (name, fallback = null) => { const i = process.argv.indexOf(`--${name}`); return i > 0 ? process.argv[i + 1] : fallback; };
  const model = arg('model');
  const server = String(arg('server', 'http://127.0.0.1:8080')).replace(/\/+$/, '');
  const until = Date.now() + Number(arg('hours', '4')) * 3600_000;
  const size = Number(arg('batch', '4'));
  const { picked } = JSON.parse(readFileSync(arg('items'), 'utf8'));
  const items = picked.map(p => p.item);
  const votes = {};
  const started = Date.now();
  let asked = 0, failed = 0;
  for (let i = 0; i < items.length && Date.now() < until; i += size) {
    const batch = items.slice(i, i + size);
    asked += batch.length;
    try {
      const res = await post(`${server}/v1/chat/completions`, requestFor(batch, model));
      if (!res.ok) { failed += batch.length; console.error(`\nthe server answered ${res.status}`); continue; }
      const body = JSON.parse(res.text);
      Object.assign(votes, answersOf(batch, body.choices?.[0]?.message?.content));
    } catch (e) { failed += batch.length; console.error(`\n${e.message}`); }
    process.stdout.write(`\r${asked} of ${items.length} asked, ${Object.keys(votes).length} answered`);
  }
  console.log('');
  const seconds = Math.round((Date.now() - started) / 1000);
  // against the gold keys the ladder keeps (never sent anywhere): how often
  // this family's blind answer is right, for the run's log
  const right = picked.filter(p => votes[p.item.id]?.answer === p.gold).length;
  writeFileSync(arg('out'), JSON.stringify({ model, votes, asked, answered: Object.keys(votes).length, right, failed, seconds }) + '\n');
  console.log(`${model}: ${Object.keys(votes).length} of ${items.length} answered in ${seconds} s; ${right} right by the gold key`);
}

if (import.meta.url === `file://${process.argv[1]}`) main().catch(e => { console.error(e.message); process.exit(1); });
