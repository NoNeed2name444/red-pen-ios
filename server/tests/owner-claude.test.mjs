// The owner's own key writes with Claude whatever PRO_PAYS says (the owner,
// 22 Oct: "Claude for my key only"), paid from the owner's wallet
// (OWNER_MONTHLY_USD) and nothing else; every other caller routes exactly as
// before, with PRO_PAYS "off" and "on".
//
// The table below was taken from ai.js at 36167f28, the commit before this
// change, and only the owner's writer with PRO_PAYS "off" is meant to differ.
//
// Run: node server/tests/owner-claude.test.mjs

import { DatabaseSync } from 'node:sqlite';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { chat, routeFor } from '../ai.js';

const here = dirname(fileURLToPath(import.meta.url));
let failures = 0;
const ok = (cond, what) => { console.log((cond ? 'ok   ' : 'FAIL ') + what); if (!cond) failures++; };

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

// a1 is a free account (no subscription), p1 a confirmed Pro subscriber
function freshEnv(extra = {}) {
  const db = new DatabaseSync(':memory:');
  const sql = readFileSync(join(here, '..', 'schema.sql'), 'utf8')
    .split('\n').map(line => line.replace(/--.*$/, '')).join('\n');
  for (const statement of sql.split(';')) if (statement.trim()) db.exec(statement);
  const now = Math.floor(Date.now() / 1000);
  db.prepare(`INSERT INTO accounts (id, provider, subject, created_at) VALUES ('a1', 'apple', 's1', 0)`).run();
  db.prepare(`INSERT INTO accounts (id, provider, subject, created_at, verified_until, checked_at) VALUES ('p1', 'apple', 's2', 0, ?, ?)`)
    .run(now + 86400, now);
  return { DB: d1(db), db, APPLE_BUNDLE_ID: 'com.cramdown.app', ...extra };
}

const claudeReply = { model: 'claude-opus-5-5', stop_reason: 'end_turn', content: [{ type: 'text', text: 'claude' }],
                      usage: { input_tokens: 100, output_tokens: 50 } };
const geminiReply = { candidates: [{ content: { parts: [{ text: 'gemini' }] } }], usageMetadata: { promptTokenCount: 100, candidatesTokenCount: 50 } };
function upstream() {
  const log = { asked: [] };
  log.fetcher = async url => {
    if (url.includes('storekit')) return new Response('{}', { status: 404 });
    if (url.includes('anthropic')) { log.asked.push('claude'); return new Response(JSON.stringify(claudeReply), { status: 200 }); }
    log.asked.push('gemini');
    return new Response(JSON.stringify(geminiReply), { status: 200 });
  };
  return log;
}

// as deployed (wrangler.toml prices the hosted writer and lists the free models), with the key set and room in every wallet
const base = { FIREBASE_API_KEY: 'fk', FIREBASE_PROJECT_ID: 'p', ANTHROPIC_API_KEY: 'ak',
               CLOUD_MODELS: 'gemini-3.1-pro-preview,gemini-3.8-flash,gemini-3.5-flash-lite,gemma-4-31b-it',
               GEMINI_PRICES: 'gemini-3.8-flash:0.30/2.50,claude-opus-5-5:4.00/20.00',
               OWNER_MONTHLY_USD: '5', PRO_MONTHLY_BUDGET_USD: '5' };
const writer = { model: 'cramdown-writer', messages: [{ role: 'user', content: 'hi' }], max_tokens: 800 };
const checker = { ...writer, model: 'cramdown-checker' };

// who: [account id, chat options] as worker.js and jobs.js call chat()
const callers = {
  anonymous: ['nobody', {}],
  free: ['a1', {}],
  pro: ['p1', {}],
  owner: ['owner', { owner: true }],
  'owner job': ['owner', { owner: true, maxTokensCap: 8000, rounds: 1 }],
};

async function observe(who, pays, body, extra = {}) {
  const [account, options] = callers[who];
  const env = freshEnv({ ...base, PRO_PAYS: pays, ...extra });
  const log = upstream();
  const r = await chat(env, account, body, log.fetcher, options);
  const said = await r.json();
  return { status: r.status, asked: log.asked.join('>'), answer: said.choices?.[0]?.message?.content ?? null,
           source: said.source ?? null, notice: said.notice ?? null, env };
}
const row = o => `${o.status} ${o.asked || '-'} ${o.answer ?? '-'} ${o.source ?? '-'}${o.notice ? ' ' + o.notice : ''}`;

// what 36167f28 answered, for every caller, job and PRO_PAYS setting
const before = {
  'anonymous writer off': '401 - - -', 'anonymous writer on': '401 - - -',
  'anonymous checker off': '401 - - -', 'anonymous checker on': '401 - - -',
  'free writer off': '402 - - -', 'free writer on': '402 - - -',
  'free checker off': '402 - - -', 'free checker on': '402 - - -',
  'pro writer off': '200 gemini gemini gemini-3.8-flash', 'pro writer on': '200 claude claude claude-opus-5-5',
  'pro checker off': '200 gemini gemini gemini-3.8-flash', 'pro checker on': '200 claude claude claude-opus-5-5',
  'owner writer off': '200 gemini gemini gemini-3.1-pro-preview', 'owner writer on': '200 claude claude claude-opus-5-5',
  'owner checker off': '200 gemini gemini gemini-3.8-flash', 'owner checker on': '200 claude claude claude-opus-5-5',
  'owner job writer off': '200 gemini gemini gemini-3.1-pro-preview', 'owner job writer on': '200 claude claude claude-opus-5-5',
  'owner job checker off': '200 gemini gemini gemini-3.8-flash', 'owner job checker on': '200 claude claude claude-opus-5-5',
};
// the change: the owner's writing, chat and jobs, with PRO_PAYS off
const meant = new Set(['owner writer off', 'owner job writer off']);
// and later (the owner, 23 Oct: "Lock it"): only the hosted writer answers an account,
// so with PRO_PAYS off a Pro account no longer falls to the free chain
// and then (the owner, 23 Oct: "only me"): no account but the owner's is
// answered at all, Pro or not, PRO_PAYS on or off
const locked = { 'pro writer off': '402 - - -', 'pro checker off': '402 - - -',
                 'pro writer on': '402 - - -', 'pro checker on': '402 - - -' };

// A1: the owner key with PRO_PAYS off writes with Claude first, chat and jobs
{
  const route = routeFor({ ...base, PRO_PAYS: 'off' }, 'cramdown-writer', { owner: true });
  const kinds = route.sources.map(s => `${s.kind}${s.model ? ':' + s.model : ''}`).join('>');
  console.log(`     owner writer route, PRO_PAYS off: ${kinds}`);
  ok(kinds === 'anthropic:claude-opus-5-5>gemini' && route.sources[0].paid === true,
     'A1 owner key, PRO_PAYS off: cramdown-writer routes to Anthropic claude-opus-5-5 first, a paid source');
  for (const who of ['owner', 'owner job']) {
    const o = await observe(who, 'off', writer);
    console.log(`     ${who} writer off: ${row(o)}`);
    ok(row(o) === '200 claude claude claude-opus-5-5', `A1 ${who}, PRO_PAYS off: Claude is asked first and answers`);
    const held = o.env.db.prepare("SELECT micro_usd AS m FROM ai_cost WHERE account_id = 'owner'").get()?.m;
    ok(held === 100 * 4 + 50 * 20, `A1 ${who}: Claude's cost (${held} millionths) is counted in the owner's wallet`);
    ok(!o.env.db.prepare("SELECT 1 AS x FROM ai_cost WHERE account_id = 'claude:owner'").get(),
       `A1 ${who}: not in the checker votes' Claude cap (claude:owner)`);
  }
  const unset = await observe('owner', undefined, writer);
  ok(row(unset) === '200 claude claude claude-opus-5-5', 'A1 owner key, PRO_PAYS unset: the same');
}

// A2: everything else answers exactly as at 36167f28
{
  const now = {};
  for (const who of Object.keys(callers)) {
    for (const [job, body] of [['writer', writer], ['checker', checker]]) {
      for (const pays of ['off', 'on']) now[`${who} ${job} ${pays}`] = row(await observe(who, pays, body));
    }
  }
  for (const [name, was] of Object.entries(before)) {
    if (name in locked) {
      ok(now[name] === locked[name], `A2 ${name}: locked, the free chain is not asked (${now[name]}, was ${was})`);
    } else if (meant.has(name)) {
      console.log(`     ${name}: before ${was} | now ${now[name]}`);
      ok(now[name] !== was, `A2 ${name}: changed, as meant`);
    } else {
      ok(now[name] === was, `A2 ${name}: unchanged (${now[name]})`);
    }
  }
  // the routes themselves, for every non-owner caller (routeFor never sees an
  // account; only the owner's flag can change it)
  for (const pays of ['off', 'on', undefined]) {
    for (const name of ['cramdown-writer', 'cramdown-checker']) {
      const env = { ...base, PRO_PAYS: pays };
      const plain = JSON.stringify(routeFor(env, name));
      ok(plain === JSON.stringify(routeFor(env, name, {})) && plain === JSON.stringify(routeFor(env, name, { owner: false })),
         `A2 non-owner route for ${name}, PRO_PAYS ${pays}: the same with or without the new option`);
    }
  }
  ok(JSON.stringify(routeFor({ ...base, PRO_PAYS: 'on' }, 'cramdown-writer', { owner: true }))
     === JSON.stringify(routeFor({ ...base, PRO_PAYS: 'on' }, 'cramdown-writer')),
     'A2 owner writer, PRO_PAYS on: the same route as before');
  ok(!routeFor({ ...base, PRO_PAYS: 'off' }, 'cramdown-checker', { owner: true }).sources.some(s => s.kind === 'anthropic'),
     "A2 owner checker, PRO_PAYS off: no Claude (only the owner's writing changes)");
  // the owner's benchmarks stay off Claude
  const env = freshEnv({ ...base, PRO_PAYS: 'off' });
  const log = upstream();
  const r = await chat(env, 'owner', writer, log.fetcher, { owner: true, bench: true });
  ok(r.status === 200 && log.asked.join('>') === 'gemini', "A2 owner benchmarks, PRO_PAYS off: Gemini, as before");
}

// A3: the caps
{
  // the owner's month already spent: Claude is not asked, the free chain answers, and the reply says why
  const spent = freshEnv({ ...base, PRO_PAYS: 'off' });
  const month = new Date().toISOString().slice(0, 7);
  spent.db.prepare('INSERT INTO ai_cost (account_id, month, micro_usd) VALUES (?, ?, ?)').run('owner', month, 5_000_000);
  const log = upstream();
  const r = await chat(spent, 'owner', writer, log.fetcher, { owner: true });
  const said = await r.json();
  console.log(`     owner over OWNER_MONTHLY_USD: ${r.status} ${log.asked.join('>')} notice="${said.notice}"`);
  ok(r.status === 200 && log.asked.join('>') === 'gemini' && said.choices[0].message.content === 'gemini',
     "A3 owner's OWNER_MONTHLY_USD reached: Claude is not asked, the Gemini chain answers (as with PRO_PAYS on)");
  ok(said.notice === "Claude has spent this month's 5 dollars.", "A3 and the reply says so, in the Claude cap's words");
  ok(spent.db.prepare("SELECT micro_usd AS m FROM ai_cost WHERE account_id = 'owner'").get().m === 5_000_000,
     'A3 and nothing more is counted');

  // room left, but not for Claude's worst case: the same
  const thin = await observe('owner', 'off', writer, { OWNER_MONTHLY_USD: '0.05' });
  ok(thin.asked === 'gemini' && thin.notice === "Claude has spent this month's 0.05 dollars.",
     "A3 a wallet that cannot hold Claude's worst case: not asked, Gemini answers, and the reply says so");

  // the cap left at its default: 20 dollars
  const deflt = await observe('owner', 'off', writer, { OWNER_MONTHLY_USD: undefined });
  ok(deflt.asked === 'claude', 'A3 OWNER_MONTHLY_USD unset: Claude, within the default 20 dollars');

  // with PRO_PAYS on the owner's cap behaves as it already did: the free chain answers
  const onSpent = freshEnv({ ...base, PRO_PAYS: 'on' });
  onSpent.db.prepare('INSERT INTO ai_cost (account_id, month, micro_usd) VALUES (?, ?, ?)').run('owner', month, 5_000_000);
  const onLog = upstream();
  const onR = await chat(onSpent, 'owner', writer, onLog.fetcher, { owner: true });
  ok(onR.status === 200 && !onLog.asked.includes('claude'), 'A3 PRO_PAYS on, owner cap reached: no Claude, as before');

  // no key, or no price: Gemini, the same as today, and no wallet is touched
  for (const [what, extra] of [['no ANTHROPIC_API_KEY', { ANTHROPIC_API_KEY: undefined }],
                               ['no price for Claude', { GEMINI_PRICES: 'gemini-3.8-flash:0.30/2.50' }]]) {
    const o = await observe('owner', 'off', writer, extra);
    ok(row(o) === '200 gemini gemini gemini-3.1-pro-preview' && !o.env.db.prepare('SELECT 1 AS x FROM ai_cost').get(),
       `A3 ${what}: the owner falls back to the Gemini chain, nothing counted`);
  }

  // the owner's daily allowance still holds
  const daily = freshEnv({ ...base, PRO_PAYS: 'off', OWNER_DAILY_LIMIT: '1' });
  const dLog = upstream();
  await chat(daily, 'owner', writer, dLog.fetcher, { owner: true });
  const second = await chat(daily, 'owner', writer, dLog.fetcher, { owner: true });
  ok(second.status === 429 && dLog.asked.join('>') === 'claude', 'A3 OWNER_DAILY_LIMIT still caps the owner');

  // Claude failing: the free chain answers and only Claude's own call is counted
  const down = freshEnv({ ...base, PRO_PAYS: 'off' });
  const asked = [];
  const r2 = await chat(down, 'owner', writer, async url => {
    if (url.includes('anthropic')) { asked.push('claude'); return new Response('{}', { status: 529 }); }
    asked.push('gemini');
    return new Response(JSON.stringify(geminiReply), { status: 200 });
  }, { owner: true });
  ok(r2.status === 200 && asked.join('>') === 'claude>gemini'
     && (down.db.prepare("SELECT micro_usd AS m FROM ai_cost WHERE account_id = 'owner'").get()?.m ?? 0) === 0,
     "A3 Claude down: Gemini answers, its free call is not charged to the owner's wallet, the hold is given back");
}

// A4: "Lock it" - an account is never answered by the free chain
{
  // R6 "only me": a Pro account that is not the owner's, PRO_PAYS on and the
  // hosted writer set up, is refused before any model is asked
  for (const [job, body] of [['writer', writer], ['checker', checker]]) {
    const env = freshEnv({ ...base, PRO_PAYS: 'on' });
    const asked = [];
    const r = await chat(env, 'p1', body, async url => {
      if (url.includes('storekit')) return new Response('{}', { status: 404 });
      asked.push(url.includes('anthropic') ? 'claude' : 'gemini');
      return new Response(JSON.stringify(url.includes('anthropic') ? claudeReply : geminiReply), { status: 200 });
    });
    const said = await r.json();
    ok(r.status === 402 && said.message === 'Stethoscore Cloud is part of Pro.' && asked.length === 0
       && !env.db.prepare('SELECT 1 AS x FROM ai_usage WHERE account_id = ?').get('p1'),
       `A4 a Pro account (not the owner), PRO_PAYS on, ${job}: 402 (See Pro), no model asked, nothing counted`);
  }
  // no hosted writer on the route (no key, or no price): the See Pro answer, nothing asked
  for (const [what, extra] of [['no ANTHROPIC_API_KEY', { ANTHROPIC_API_KEY: undefined }],
                               ['no price for Claude', { GEMINI_PRICES: 'gemini-3.8-flash:0.30/2.50' }]]) {
    for (const [job, body] of [['writer', writer], ['checker', checker]]) {
      const o = await observe('pro', 'on', body, extra);
      ok(row(o) === '402 - - -', `A4 a Pro account, PRO_PAYS on, ${what}, ${job}: 402 (See Pro), nothing asked`);
    }
  }
  // the owner key keeps its chain and its caps (A1-A3 above)
}

// A5: the owner signed in. The app sends the session before the owner key,
// so an owner account (accounts.owner = 1, or listed in OWNER_ACCOUNT_IDS)
// is the owner here too: the key's route, gates and one wallet. o1 is marked
// in the table and has no subscription; o2 is only listed.
{
  // as the owner key answers (A1, and the checker as at 36167f28)
  const answers = { writer: '200 claude claude claude-opus-5-5', checker: before['owner checker off'] };
  for (const [who, extra] of [['o1 (marked owner)', {}], ['o2 (in OWNER_ACCOUNT_IDS)', { OWNER_ACCOUNT_IDS: 'x9, o2' }]]) {
    const id = who.slice(0, 2);
    for (const [job, body] of [['writer', writer], ['checker', checker]]) {
      const env = freshEnv({ ...base, PRO_PAYS: 'off', ...extra });
      env.db.prepare(`INSERT INTO accounts (id, provider, subject, created_at, owner) VALUES (?, 'apple', ?, 0, ?)`)
        .run(id, `s-${id}`, id === 'o1' ? 1 : 0);
      const log = upstream();
      const r = await chat(env, id, body, log.fetcher);
      const said = await r.json();
      const o = { status: r.status, asked: log.asked.join('>'), answer: said.choices?.[0]?.message?.content ?? null, source: said.source ?? null };
      console.log(`     owner account ${who} ${job} off: ${row(o)}`);
      ok(row(o) === answers[job],
         `A5 owner account ${who}, PRO_PAYS off, ${job}: answered as the owner key is (not 402)`);
      if (job === 'writer') {
        const held = env.db.prepare("SELECT micro_usd AS m FROM ai_cost WHERE account_id = 'owner'").get()?.m;
        ok(held === 100 * 4 + 50 * 20 && !env.db.prepare('SELECT 1 AS x FROM ai_cost WHERE account_id = ?').get(id),
           `A5 owner account ${who}: the cost is the owner wallet's (OWNER_MONTHLY_USD), not the account's`);
      }
    }
  }
  // the owner's wallet is one: spent by the key, it is spent for the signed-in owner too
  {
    const env = freshEnv({ ...base, PRO_PAYS: 'off', OWNER_ACCOUNT_IDS: 'o2' });
    env.db.prepare(`INSERT INTO accounts (id, provider, subject, created_at) VALUES ('o2', 'apple', 's-o2', 0)`).run();
    env.db.prepare(`INSERT INTO ai_cost (account_id, month, micro_usd) VALUES ('owner', ?, ?)`)
      .run(new Date().toISOString().slice(0, 7), 5_000_000);
    const log = upstream();
    const r = await chat(env, 'o2', writer, log.fetcher);
    ok(r.status === 200 && !log.asked.includes('claude'),
       "A5 the owner's month used by the key: the signed-in owner is held to the same cap (the hosted writer is not asked)");
  }
  // anyone else signed in, PRO_PAYS off: still 402, nothing asked (free a1, Pro p1)
  for (const who of ['free', 'pro']) for (const [job, body] of [['writer', writer], ['checker', checker]]) {
    const o = await observe(who, 'off', body, { OWNER_ACCOUNT_IDS: 'o2' });
    ok(row(o) === '402 - - -', `A5 ${who} account (not the owner), PRO_PAYS off, ${job}: 402, nothing asked`);
  }
  // and the owner key exactly as before
  for (const who of ['owner', 'owner job']) for (const [job, body] of [['writer', writer], ['checker', checker]]) {
    const o = await observe(who, 'off', body, { OWNER_ACCOUNT_IDS: 'o2' });
    const want = job === 'writer' ? '200 claude claude claude-opus-5-5' : before[`${who} ${job} off`];
    ok(row(o) === want, `A5 ${who} key, PRO_PAYS off, ${job}: unchanged (${want})`);
  }
}

if (failures) { console.error(`${failures} failed`); process.exit(1); }
console.log('all passed');
