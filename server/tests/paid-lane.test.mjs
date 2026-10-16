// Claude in the Worker's paid lane: it answers only while Pro itself pays
// (PRO_PAYS "on"), and what the lane holds back for it covers what it can be
// asked for.
//
// The paid lane also opens on GEMINI_BILLING "on" or a bill having been seen
// (ai.js proPays, paysNow), which are about Google's bill, not Pro's income. The
// owner's wallet in that lane is OWNER_MONTHLY_USD, not the limit set on the
// Anthropic key (CLAUDE_MONTHLY_USD), so Claude must not join it there. And the
// hold has to cover the tokens Claude is really asked for - the reply and its
// thinking room - or calls running together pass the cap by the difference.
//
// Run: node server/tests/paid-lane.test.mjs

import { DatabaseSync } from 'node:sqlite';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { chat, routeFor, costOf, paysNow, canPay, askModel, claudeVoterSpent } from '../ai.js';

const here = dirname(fileURLToPath(import.meta.url));
let failures = 0;
const ok = (cond, what) => { console.log((cond ? 'ok   ' : 'FAIL ') + what); if (!cond) failures++; };

// a real SQLite behind the D1 calls, as in ai.test.mjs
function d1(db) {
  return {
    prepare(sql) {
      const stmt = db.prepare(sql);
      let args = [];
      const api = {
        bind(...a) { args = a; return api; },
        first() { return stmt.get(...args) ?? null; },
        run() { const r = stmt.run(...args); return { meta: { changes: Number(r.changes) } }; },
      };
      return api;
    },
  };
}

function freshEnv(extra = {}) {
  const db = new DatabaseSync(':memory:');
  // comments out first: they contain example statements with semicolons
  const sql = readFileSync(join(here, '..', 'schema.sql'), 'utf8')
    .split('\n').map(line => line.replace(/--.*$/, '')).join('\n');
  for (const statement of sql.split(';')) if (statement.trim()) db.exec(statement);
  db.prepare(`INSERT INTO accounts (id, provider, subject, created_at) VALUES ('a1', 'apple', 's1', 0)`).run();
  return { DB: d1(db), db, AI_API_KEY: 'k', APPLE_BUNDLE_ID: 'com.cramdown.app', ...extra };
}

// Both hosts answer; the log says who was asked, in order, and what Claude was
// sent. `onClaude` runs as Claude's request arrives, to look at the database
// while the call is out.
const claudeReply = { model: 'claude-opus-5-5', stop_reason: 'end_turn', content: [{ type: 'text', text: 'claude' }],
                      usage: { input_tokens: 100, output_tokens: 50 } };
function upstream(onClaude = () => {}) {
  const log = { asked: [], sent: null };
  log.fetcher = async (url, init) => {
    if (url.includes('anthropic')) {
      log.asked.push('claude');
      log.sent = JSON.parse(init.body);
      onClaude();
      return new Response(JSON.stringify(claudeReply), { status: 200 });
    }
    log.asked.push('gemini');
    return new Response(JSON.stringify({ candidates: [{ content: { parts: [{ text: 'gemini' }] } }] }), { status: 200 });
  };
  return log;
}

const firebase = { FIREBASE_API_KEY: 'fk', FIREBASE_PROJECT_ID: 'p' };
// Pro paying is off, Claude's key is set, and there is room in a five-dollar
// wallet: for the owner's own key, and for a Pro account (a1 is on
// OWNER_ACCOUNT_IDS) with a budget of its own
const lane = { ...firebase, OWNER_ACCOUNT_IDS: 'a1', ANTHROPIC_API_KEY: 'ak', PRO_PAYS: 'off',
               OWNER_MONTHLY_USD: '5', PRO_MONTHLY_BUDGET_USD: '5' };

const writer = { model: 'cramdown-writer', messages: [{ role: 'user', content: 'hi' }], max_tokens: 800 };
// every way a request reaches chat(): the owner's, a Pro account's, and the two
// calls a background job makes (jobs.js) with its own options
const calls = [
  ["the owner's chat", writer, { owner: true }],
  ["a Pro account's chat", writer, {}],
  ["a background job's step", { ...writer, max_tokens: 3800 }, { owner: true, maxTokensCap: 8000, rounds: 1 }],
  ["a background job's check", { ...writer, model: 'cramdown-checker', max_tokens: 900, temperature: 0.1 }, { owner: true, rounds: 1 }],
];

// the route itself: Claude is in it only when PRO_PAYS is "on"
{
  const claudeIn = env => routeFor(env, 'cramdown-writer').sources.some(s => s.kind === 'anthropic');
  ok(!claudeIn({ ...lane }) && !claudeIn({ ...lane, PRO_PAYS: undefined }),
     'PRO_PAYS off or unset: Claude is not a source of the route, key or no key');
  ok(!claudeIn({ ...lane, GEMINI_BILLING: 'on' }) && !claudeIn({ ...lane, PRO_PAYS: undefined, GEMINI_BILLING: 'on' }),
     'and GEMINI_BILLING on does not bring it in');
  const on = routeFor({ ...lane, PRO_PAYS: 'on', AI: {}, AI_WRITER_URL: 'https://api.novita.ai/openai', AI_WRITER_KEY: 'nk' }, 'cramdown-writer');
  ok(on.sources.map(s => s.kind).join('>') === 'anthropic>openai>gemini>workers-ai' && on.sources[0].paid === true,
     'PRO_PAYS on: Claude is the first source and a paid one, ahead of the rest as before');
  ok(!routeFor({ ...lane, PRO_PAYS: 'on', ANTHROPIC_API_KEY: undefined }, 'cramdown-writer').sources.some(s => s.kind === 'anthropic'),
     'and still only with its key');
}

// PRO_PAYS off, the paid lane opened another way: nothing reaches Anthropic
const opened = {
  'GEMINI_BILLING on': () => freshEnv({ ...lane, GEMINI_BILLING: 'on' }),
  'a bill having been seen': () => {
    const env = freshEnv(lane);
    env.db.prepare("INSERT INTO ai_usage (account_id, day, requests) VALUES ('gemini:billed', 'seen', 1)").run();
    return env;
  },
};
for (const [how, make] of Object.entries(opened)) {
  const env = make();
  ok(await paysNow(env) && await canPay(env, 'a1', true) && await canPay(env, 'a1', false),
     `${how}: the paid lane is open, and the owner's wallet and a Pro account's both have room`);
  for (const [who, body, options] of calls) {
    const log = upstream();
    const r = await chat(make(), 'a1', body, log.fetcher, options);
    const said = await r.json();
    ok(r.status === 200 && !log.asked.includes('claude') && said.choices[0].message.content === 'gemini',
       `PRO_PAYS off, ${how}: ${who} never reaches Anthropic, the Gemini chain answers`);
  }
}

// PRO_PAYS on with room in the wallet: Claude is asked first, as before
for (const [who, body, options] of calls) {
  const log = upstream();
  const r = await chat(freshEnv({ ...lane, PRO_PAYS: 'on' }), 'a1', body, log.fetcher, options);
  const said = await r.json();
  ok(r.status === 200 && log.asked[0] === 'claude' && said.choices[0].message.content === 'claude' && said.source === 'claude-opus-5-5',
     `PRO_PAYS on: Claude is asked first for ${who}, and answers`);
}

// the hold: what is taken from the wallet while Claude's request is out
{
  const prices = 'claude-opus-5-5:4.00/20.00';
  // 3,000 characters are 1,000 input tokens to the hold (a third of a token each)
  const prompt = { ...writer, messages: [{ role: 'user', content: 'x'.repeat(3000) }] };
  const heldBy = (env, key = 'owner') => env.db.prepare('SELECT micro_usd AS m FROM ai_cost WHERE account_id = ?').get(key)?.m ?? 0;
  // 1,000 input tokens at $4 a million, and the 800-token reply with 4,000 tokens
  // of room to think at $20 a million, in millionths of a dollar
  const worst = 1000 * 4 + 4800 * 20;

  const env = freshEnv({ ...lane, PRO_PAYS: 'on', GEMINI_PRICES: prices });
  ok(costOf(env, 'claude-opus-5-5', { input_tokens: 1000, output_tokens: 4800 }) === worst,
     "Claude's entry in GEMINI_PRICES prices 4,800 output tokens and 1,000 input tokens at 100,000 millionths of a dollar");
  let held = null;
  const log = upstream(() => { held = heldBy(env); });
  await chat(env, 'a1', prompt, log.fetcher, { owner: true });
  ok(log.sent.max_tokens === 4800, 'Claude is asked for 4,800 tokens: the 800-token reply and 4,000 to think in');
  ok(held >= worst, `the hold covers that worst case: ${held} held, ${worst} needed`);
  ok(heldBy(env) === 1400, "and it is settled to what the call cost (100 input and 50 output tokens), not left held");

  // a wallet with room for the old hold (36,000) but not for Claude's worst case: Claude is not asked
  const thin = freshEnv({ ...lane, PRO_PAYS: 'on', GEMINI_PRICES: prices, OWNER_MONTHLY_USD: '0.05' });
  const thinLog = upstream();
  const r = await chat(thin, 'a1', prompt, thinLog.fetcher, { owner: true });
  ok(r.status === 200 && !thinLog.asked.includes('claude') && (await r.json()).choices[0].message.content === 'gemini',
     'a wallet that could not cover Claude at its 4,800 tokens is not spent on it: the free model answers');

  // every other model is held as before, at twice the reply
  const mixed = freshEnv({ ...lane, PRO_PAYS: 'on', GEMINI_PRICES: 'claude-opus-5-5:1/1,gemini-3.5-flash:100/100' });
  let heldMixed = null;
  await chat(mixed, 'a1', prompt, upstream(() => { heldMixed = heldBy(mixed); }).fetcher, { owner: true });
  ok(heldMixed === 1000 * 100 + 1600 * 100, `a costlier Google model still sets the hold at twice the reply, 1,600 tokens (${heldMixed})`);
}

// Claude as the checker's voter is not the paid lane: its own cap, whatever PRO_PAYS says
{
  const env = freshEnv({ ...lane, GEMINI_BILLING: 'on' });
  const log = upstream();
  const vote = await askModel(env, 'owner', true, 'claude:claude-opus-5-5', [{ role: 'user', content: 'Solve it blind.' }], 600, log.fetcher);
  ok(vote.ok && vote.content === 'claude' && log.asked.join() === 'claude', "PRO_PAYS off: the owner's checker still gets Claude's vote");
  ok(Math.abs(await claudeVoterSpent(env) - (100 * 4 + 50 * 20) / 1e6) < 1e-9
     && env.db.prepare("SELECT 1 AS x FROM ai_cost WHERE account_id = 'owner'").get() === undefined,
     "counted under claude:owner, and not in the owner's wallet");
}

if (failures) { console.error(`${failures} failed`); process.exit(1); }
console.log('all passed');
