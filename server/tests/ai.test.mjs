// CramDown Cloud's proxy, against a real SQLite and a fake upstream.
//
// What matters here is who gets through: an account Apple has not confirmed
// must be refused before any provider is called, and the daily allowance must
// hold even when requests arrive together.
//
// Run: node server/tests/ai.test.mjs

import { DatabaseSync } from 'node:sqlite';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { chat, clean, linkSubscription, isOwnerKey, accountToken } from '../ai.js';

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

function freshEnv(extra = {}) {
  const db = new DatabaseSync(':memory:');
  // comments out first: they contain example statements with semicolons
  const sql = readFileSync(join(here, '..', 'schema.sql'), 'utf8')
    .split('\n').map(line => line.replace(/--.*$/, '')).join('\n');
  for (const statement of sql.split(';')) if (statement.trim()) db.exec(statement);
  db.prepare(`INSERT INTO accounts (id, provider, subject, created_at) VALUES ('a1', 'apple', 's1', 0)`).run();
  return { DB: d1(db), db, AI_API_KEY: 'k', APPLE_BUNDLE_ID: 'com.cramdown.app', ...extra };
}

const upstreamCalls = [];
const fakeFetch = (appleAnswer) => async (url, init) => {
  if (url.includes('storekit')) {
    if (url.includes('sandbox')) return new Response('{}', { status: 404 });
    return new Response(JSON.stringify(appleAnswer), { status: 200 });
  }
  upstreamCalls.push({ url, body: JSON.parse(init.body) });
  return new Response(JSON.stringify({ choices: [{ message: { content: 'hello' } }], usage: { secret: 1 } }), { status: 200 });
};
const request = { model: 'cramdown-writer', messages: [{ role: 'user', content: 'hi' }], max_tokens: 99999 };

// a real ES256 key, as App Store Connect would issue
const pair = await crypto.subtle.generateKey({ name: 'ECDSA', namedCurve: 'P-256' }, true, ['sign', 'verify']);
const pkcs8 = Buffer.from(await crypto.subtle.exportKey('pkcs8', pair.privateKey)).toString('base64');
const asc = { ASC_KEY_ID: 'KEY', ASC_ISSUER_ID: 'ISS', ASC_PRIVATE_KEY: `-----BEGIN PRIVATE KEY-----\n${pkcs8}\n-----END PRIVATE KEY-----` };
const jws = claims => `x.${Buffer.from(JSON.stringify(claims)).toString('base64url')}.y`;
const a1Token = await accountToken('a1');

// not Pro: refused, and nothing reaches the provider
{
  const env = freshEnv();
  const r = await chat(env, 'a1', request, fakeFetch({}));
  ok(r.status === 402, 'an account with no subscription is refused (402)');
  ok(upstreamCalls.length === 0, 'the provider is never called for it');
}

// owner: allowed, model mapped, tokens capped, only the content comes back
{
  const env = freshEnv({ OWNER_ACCOUNT_IDS: 'x, a1' });
  const r = await chat(env, 'a1', request, fakeFetch({}));
  const body = await r.json();
  ok(r.status === 200 && body.choices[0].message.content === 'hello', 'an owner account gets the answer');
  const sent = upstreamCalls.at(-1).body;
  ok(sent.model === 'baichuan-inc/Baichuan-M2-32B', 'cramdown-writer maps to Baichuan-M2-32B by default');
  ok(sent.max_tokens === 2000, 'max_tokens is capped');
  ok(!('usage' in body), "the upstream's metadata is not passed back");
}

// Apple confirms a live subscription: linked, then allowed
{
  const env = freshEnv(asc);
  const future = Date.now() + 30 * 86_400_000;
  const apple = { bundleId: 'com.cramdown.app', data: [{ lastTransactions: [
    { status: 1, signedTransactionInfo: jws({ expiresDate: future, appAccountToken: a1Token }) }] }] };
  const linked = await (await linkSubscription(env, 'a1', { originalTransactionId: '2000000123' }, fakeFetch(apple))).json();
  ok(linked.pro === true, 'a live subscription confirmed by Apple links as Pro');
  const r = await chat(env, 'a1', request, fakeFetch(apple));
  ok(r.status === 200, 'and the cloud model then answers');
}

// Apple says expired: refused
{
  const env = freshEnv(asc);
  const apple = { bundleId: 'com.cramdown.app', data: [{ lastTransactions: [
    { status: 2, signedTransactionInfo: jws({ expiresDate: Date.now() - 1000 }) }] }] };
  const linked = await (await linkSubscription(env, 'a1', { originalTransactionId: '2000000124' }, fakeFetch(apple))).json();
  ok(linked.pro === false, 'an expired subscription is not Pro');
  ok((await chat(env, 'a1', request, fakeFetch(apple))).status === 402, 'and is refused');
}

// another app's subscription: refused
{
  const env = freshEnv(asc);
  const apple = { bundleId: 'com.someone.else', data: [{ lastTransactions: [
    { status: 1, signedTransactionInfo: jws({ expiresDate: Date.now() + 1e9, appAccountToken: a1Token }) }] }] };
  const linked = await (await linkSubscription(env, 'a1', { originalTransactionId: '2000000125' }, fakeFetch(apple))).json();
  ok(linked.pro === false, "a subscription for a different bundle id doesn't count");
}

// one subscription, one account; and Apple being down doesn't cancel Pro
{
  const env = freshEnv(asc);
  env.DB.prepare(`INSERT INTO accounts (id, provider, subject, created_at) VALUES ('b2', 'google', 's2', 0)`).run();
  const future = Date.now() + 30 * 86_400_000;
  const apple = { bundleId: 'com.cramdown.app', data: [{ lastTransactions: [
    { status: 1, signedTransactionInfo: jws({ expiresDate: future, appAccountToken: a1Token }) }] }] };
  await linkSubscription(env, 'a1', { originalTransactionId: '2000000200' }, fakeFetch(apple));
  const shared = await linkSubscription(env, 'b2', { originalTransactionId: '2000000200' }, fakeFetch(apple));
  ok(shared.status === 409, "someone else's transaction id does not make a second account Pro");

  // a1 is Pro; time passes past the recheck and Apple answers 503
  env.DB.prepare('UPDATE accounts SET checked_at = 0 WHERE id = ?').bind('a1').run();
  const down = async (url, init) => url.includes('storekit') ? new Response('busy', { status: 503 }) : fakeFetch(apple)(url, init);
  ok((await chat(env, 'a1', request, down)).status === 200, 'Apple being down does not take Pro away from a subscriber');
}

// a transaction id someone else bought cannot be claimed first
{
  const env = freshEnv(asc);
  const apple = { bundleId: 'com.cramdown.app', environment: 'Production', data: [{ lastTransactions: [
    { status: 1, signedTransactionInfo: jws({ expiresDate: Date.now() + 1e9, appAccountToken: await accountToken('the-real-buyer') }) }] }] };
  const r = await linkSubscription(env, 'a1', { originalTransactionId: '2000000300' }, fakeFetch(apple));
  ok(r.status === 403, "a subscription bought from another account cannot be linked, even first");
}

// Apple unreachable (the request itself fails): the last answer stands, no 500
{
  const env = freshEnv(asc);
  const thrown = await linkSubscription(env, 'a1', { originalTransactionId: '2000000301' }, async () => { throw new Error('offline'); });
  ok(thrown.status === 503, 'a network failure asking Apple is "try again", not a crash');
}

// Pro pays: reserved before, settled after; the owner is counted and capped
{
  const { reserve, settle, wallet, canPay, costOf, budget } = await import('../ai.js');
  const env = freshEnv({ PRO_PAYS: 'on', PRO_MONTHLY_BUDGET_USD: '1', OWNER_MONTHLY_USD: '1',
                         GEMINI_PRICES: 'gemini-3.5-flash:1/1', GEMINI_AUDIO_PRICES: 'gemini-3.5-flash:3' });
  const w = await wallet(env, 'a1');
  ok(await reserve(env, w, 600_000) && !(await reserve(env, w, 600_000)), 'two calls at once cannot both take the last of the budget');
  await settle(env, w, 600_000, 100_000);
  ok(await reserve(env, w, 600_000), 'settling returns what was held back but not used');
  ok(costOf(env, 'gemini-3.5-flash', { promptTokenCount: 1e6, candidatesTokenCount: 0,
      promptTokensDetails: [{ modality: 'AUDIO', tokenCount: 1e6 }] }) === 3e6, 'audio is priced as audio');
  const owner = await wallet(env, 'owner', true);
  await reserve(env, owner, 1_000_000);
  ok(!(await canPay(env, 'owner', true)), "the owner key's spending is counted and capped too");
  ok((await budget(env)).forUse === null, 'no overall cap is reported as null, not Infinity');
}

// the owner key has a daily allowance too
{
  const env = freshEnv({ OWNER_DAILY_LIMIT: '1' });
  await chat(env, 'owner', request, fakeFetch({}), { owner: true });
  ok((await chat(env, 'owner', request, fakeFetch({}), { owner: true })).status === 429, 'a leaked owner key cannot spend without end');
}

// the daily allowance
{
  const env = freshEnv({ OWNER_ACCOUNT_IDS: 'a1', AI_DAILY_LIMIT: '3' });
  const statuses = [];
  for (let i = 0; i < 5; i++) statuses.push((await chat(env, 'a1', request, fakeFetch({}))).status);
  ok(JSON.stringify(statuses) === JSON.stringify([200, 200, 200, 429, 429]), 'the fourth request of the day is refused (429)');
}

// what may be sent
ok(clean([{ role: 'tool', content: 'x' }]) === null, 'unknown roles are refused');
ok(clean([{ role: 'user', content: 'x'.repeat(70_000) }]) === null, 'oversized prompts are refused');
ok(clean([{ role: 'user', content: 'x', extra: 1 }])[0].extra === undefined, 'extra fields are stripped');
{
  const env = freshEnv({ OWNER_ACCOUNT_IDS: 'a1' });
  ok((await chat(env, 'a1', { ...request, model: 'gpt-5' }, fakeFetch({}))).status === 400, 'only the two cramdown models are accepted');
}

// the owner key
{
  const key = 'k'.repeat(64);
  const req = auth => ({ headers: new Map([['authorization', auth]]) });
  ok(isOwnerKey(req(`Bearer ${key}`), { OWNER_KEY: key }), 'the owner key is recognised');
  ok(!isOwnerKey(req(`Bearer ${'j'.repeat(64)}`), { OWNER_KEY: key }), 'a different key is not');
  ok(!isOwnerKey(req('Bearer '), { OWNER_KEY: '' }), 'an unset owner key never matches, even an empty one');
  const env = freshEnv();
  const r = await chat(env, 'owner', request, fakeFetch({}), { owner: true });
  ok(r.status === 200, 'the owner path answers with no account and no subscription');
}

// Doctor-R1 and MedVAL: their own hosts, and a clear answer before they exist
{
  const env = freshEnv({ OWNER_ACCOUNT_IDS: 'a1' });
  const r = await chat(env, 'a1', { ...request, model: 'cramdown-doctor' }, fakeFetch({}));
  ok(r.status === 503 && (await r.json()).message.includes('Doctor-R1'), 'Doctor-R1 not hosted yet says so (503)');
  const hosted = freshEnv({ OWNER_ACCOUNT_IDS: 'a1', AI_MEDVAL_URL: 'https://medval.example/v1', AI_MEDVAL_KEY: 'mk' });
  const seen = [];
  const spy = async (url, init) => { seen.push({ url, init }); return new Response(JSON.stringify({ choices: [{ message: { content: 'Level 1' } }] })); };
  const m = await chat(hosted, 'a1', { ...request, model: 'cramdown-medval' }, spy);
  ok(m.status === 200, 'MedVAL answers once its host is set');
  ok(seen[0].url === 'https://medval.example/v1/chat/completions', 'and the request goes to the MedVAL host');
  ok(seen[0].init.headers.authorization === 'Bearer mk', 'with the MedVAL host key, not the provider key');
}

// Where CramDown Cloud goes: Baichuan-M2 (Novita) first when its key is set, then
// Gemini, then Workers AI
{
  const { routeFor } = await import('../ai.js');
  const old = routeFor({ AI_API_KEY: 'hf' }, 'cramdown-writer');
  ok(old.sources.length === 1 && old.sources[0].base.includes('huggingface'), 'with nothing else set it is the old Hugging Face route');
  const all = routeFor({ AI_API_KEY: 'hf', AI_WRITER_URL: 'https://api.baichuan-ai.com/v1', AI_WRITER_KEY: 'bk',
                         FIREBASE_API_KEY: 'fk', FIREBASE_PROJECT_ID: 'p', AI: {} }, 'cramdown-checker');
  ok(all.sources.map(x => x.kind).join('>') === 'openai>gemini>workers-ai', 'Baichuan, then Gemini, then Workers AI');
  ok(all.sources[0].model === 'baichuan/baichuan-m2-32b' && all.sources[0].key === 'bk', 'Baichuan-M2-32B by default, with its own key');

  const seen = [];
  const fetcher = async (url) => {
    seen.push(url);
    if (url.includes('baichuan')) return new Response(JSON.stringify({ error: { message: 'rate limit' } }), { status: 429 });
    return new Response(JSON.stringify({ candidates: [{ content: { parts: [{ text: 'from gemini' }] } }] }), { status: 200 });
  };
  const env = freshEnv({ PRO_PAYS: 'on', PRO_MONTHLY_BUDGET_USD: '5', OWNER_ACCOUNT_IDS: 'a1', AI_WRITER_URL: 'https://api.baichuan-ai.com/v1', AI_WRITER_KEY: 'bk',
                         FIREBASE_API_KEY: 'fk', FIREBASE_PROJECT_ID: 'p' });
  const r = await chat(env, 'a1', request, fetcher);
  ok(r.status === 200 && (await r.json()).choices[0].message.content === 'from gemini' && seen[0].includes('baichuan'),
     'Baichuan busy or out of credit: Gemini answers instead');
  const refused = async () => new Response(JSON.stringify({ error: { message: 'bad key' } }), { status: 401 });
  const x = await chat(env, 'a1', request, refused, { owner: true });
  ok(x.status === 502 && (await x.json()).message.startsWith('Provider 401'), 'a real refusal is reported, not hidden behind a fallback');
}

// CramDown Cloud on Gemini, with Workers AI when Gemini is out of quota
{
  const { geminiBody } = await import('../ai.js');
  const g = geminiBody([{ role: 'system', content: 'Be exact.' }, { role: 'user', content: 'Q\n/no_think' },
                        { role: 'assistant', content: 'A' }], 100, 0.2);
  ok(g.systemInstruction.parts[0].text === 'Be exact.' && g.contents.length === 2, 'system text becomes the system instruction');
  ok(g.contents[0].parts[0].text === 'Q' && g.contents[1].role === 'model', 'turns carry over, without the Qwen /no_think tag');
  ok(!g.generationConfig.thinkingConfig && geminiBody([{ role: 'user', content: 'Q' }], 100, 0, 'gemma-4-31b-it').generationConfig.thinkingConfig.thinkingLevel === 'minimal',
     'Gemma is asked not to think, so its answer is not cut off');

  const firebase = { FIREBASE_API_KEY: 'fk', FIREBASE_PROJECT_ID: 'cramdown-redpen', OWNER_ACCOUNT_IDS: 'a1' };
  const seen = [];
  const gemini = status => async (url, init) => {
    seen.push(url);
    if (status !== 200) return new Response(JSON.stringify({ error: { message: 'quota' } }), { status });
    return new Response(JSON.stringify({ candidates: [{ content: { parts: [{ text: 'thinking', thought: true }, { text: 'answer' }] } }] }), { status: 200 });
  };
  const r = await chat(freshEnv(firebase), 'a1', request, gemini(200));
  const body = await r.json();
  ok(r.status === 200 && body.choices[0].message.content === 'answer', 'the writer answers from Gemini, thoughts left out');
  ok(seen[0].includes('projects/cramdown-redpen/models/gemini-3.5-flash:generateContent'), 'through the Firebase project, Flash first');

  let workersAsked = 0;
  const env = freshEnv({ ...firebase, AI: { run: async (model, input) => { workersAsked++; return { response: `from ${model}` }; } } });
  const f = await chat(env, 'a1', request, gemini(429));
  const fb = await f.json();
  ok(f.status === 200 && workersAsked === 1 && fb.choices[0].message.content.startsWith('from @cf/'), 'out of Gemini quota, Workers AI answers');

  const locked = freshEnv({ ...firebase, AI: { run: async () => ({ response: 'cloudflare' }) } });
  const l = await chat(locked, 'a1', request, gemini(401));
  ok(l.status === 200 && (await l.json()).choices[0].message.content === 'cloudflare', 'Gemini locked by App Check (401): Workers AI answers');

  const none = await chat(freshEnv(firebase), 'a1', request, gemini(429), { owner: true });
  ok(none.status === 502 && (await none.json()).message.startsWith('Provider 429'), 'with no fallback the owner sees why');

  // Flash overloaded: Flash-Lite answers instead of giving up on Gemini
  const tried = [];
  const busyFlash = async url => { tried.push(url);
    return url.includes('flash-lite') ? new Response(JSON.stringify({ candidates: [{ content: { parts: [{ text: 'lite' }] } }] }), { status: 200 })
      : new Response(JSON.stringify({ error: { message: 'overloaded' } }), { status: 503 }); };
  const bl = await chat(freshEnv(firebase), 'a1', request, busyFlash);
  ok(bl.status === 200 && (await bl.json()).source === 'gemini-3.5-flash-lite' && tried.length === 2, 'Flash overloaded (503): Flash-Lite answers');

  // per-minute limit on both: wait as asked, then go round again
  let calls = 0;
  const perMinute = async () => { calls++;
    return calls <= 2 ? new Response(JSON.stringify({ error: { message: 'rate', details: [{ retryDelay: '1s' }] } }), { status: 429 })
      : new Response(JSON.stringify({ candidates: [{ content: { parts: [{ text: 'later' }] } }] }), { status: 200 }); };
  const pm = await chat(freshEnv(firebase), 'a1', request, perMinute);
  ok(pm.status === 200 && (await pm.json()).choices[0].message.content === 'later' && calls === 3, 'per-minute limit: waits the retryDelay and tries again');

  // both sources fail: the owner sees both reasons, Gemini's first
  const both = freshEnv({ ...firebase, AI: { run: async () => { throw new Error('4006: daily free allocation'); } } });
  const bm = await (await chat(both, 'a1', request, gemini(429), { owner: true })).json();
  ok(bm.message.includes('gemini 429') && bm.message.includes('workers-ai 503'), 'a fallback failure no longer hides why Gemini failed');
}

// Pro pays for Gemini once billing is on, up to a monthly budget per account
{
  const { geminiModels, charge, priceOf } = await import('../ai.js');
  const off = freshEnv({});
  ok((await geminiModels(off, 'p1')).join() === 'gemini-3.5-flash,gemini-3.5-flash-lite,gemma-4-31b-it',
     'billing off: the free allowances, 3.5 Flash first, no 3.6 Flash');
  const on = freshEnv({ GEMINI_BILLING: 'on', PRO_MONTHLY_BUDGET_USD: '1',
                        GEMINI_PRICES: 'gemini-3.5-flash:0.30/2.50' });
  ok(priceOf(on, 'gemini-3.5-flash').output === 2.5 && priceOf(on, 'gemma-4-31b-it').output === 0, 'prices read from GEMINI_PRICES; Gemma is free');
  ok((await geminiModels(on, 'p1'))[0] === 'gemini-3.5-flash', 'billing on: a Pro account starts on paid Flash');
  // 400k output tokens at $2.50/M = $1.00: the whole budget
  await charge(on, 'p1', 'gemini-3.5-flash', { promptTokenCount: 0, candidatesTokenCount: 300000, thoughtsTokenCount: 100000 });
  ok((await geminiModels(on, 'p1')).join() === 'gemma-4-31b-it', 'over its monthly budget: free Gemma only, so it never costs more than it pays');
  ok((await geminiModels(on, 'p2'))[0] === 'gemini-3.5-flash', 'another account still has its own budget');
  ok((await geminiModels(on, 'p1', true))[0] === 'gemini-3.5-flash', 'the owner is not budgeted');
  await charge(off, 'p3', 'gemini-3.5-flash', { candidatesTokenCount: 1e6 });
  ok(!(await off.DB.prepare('SELECT * FROM ai_cost WHERE account_id = ?').bind('p3').first()), 'nothing is charged while billing is off');
}

// Pro pays for everything: one budget from Pro revenue across every paid service
{
  const { budget, canPay } = await import('../ai.js');
  const env = freshEnv({ PRO_PAYS: 'on', PRO_NET_MONTHLY_USD: '5', COST_SHARE: '0.6', MONTHLY_BILLS: 'github-actions:0.4,apple-developer:0.6',
                         GEMINI_PRICES: 'gemini-3.5-flash:1/1,baichuan/baichuan-m2-32b:1/1' });
  const later = Math.floor(Date.now() / 1000) + 86400;
  env.DB.prepare('UPDATE accounts SET verified_until = ? WHERE id = ?').bind(later, 'a1').run();
  const money = await budget(env);
  ok(money.subscribers === 1 && money.revenue === 5 && Math.abs(money.forUse - 2) < 1e-9, 'for use = Pro revenue x share - the named monthly bills ($5 x 0.6 - $0.40 - $0.60 = $2)');
  ok(await canPay(env, 'a1'), 'under budget: paid services allowed');
  const { charge } = await import('../ai.js');
  await charge(env, 'a1', 'baichuan/baichuan-m2-32b', { prompt_tokens: 1e6, completion_tokens: 1e6 });
  ok(!await canPay(env, 'a1'), 'Novita usage counts too: $2 spent, nothing more is paid for');
  ok(!await canPay(freshEnv({}), 'a1'), 'before launch (PRO_PAYS off) nothing paid is ever used');

  // a paid host is skipped when the money isn't there
  let novita = 0;
  const writer = freshEnv({ OWNER_ACCOUNT_IDS: 'a1', AI_WRITER_URL: 'https://novita', AI_WRITER_KEY: 'k',
                            AI: { run: async () => ({ response: 'free' }) } });
  const r = await chat(writer, 'a1', request, async () => { novita++; return new Response('{}', { status: 500 }); });
  ok(r.status === 200 && novita === 0 && (await r.json()).choices[0].message.content === 'free', 'PRO_PAYS off: Novita is never called, the free model answers');
}


// App Check: the registered debug token is exchanged once, reused, and sent
{
  const { appCheckToken, forgetAppCheck } = await import('../ai.js');
  forgetAppCheck();
  let exchanges = 0, sentHeader = '';
  const fetcher = async (url, init) => {
    if (url.includes('exchangeDebugToken')) {
      exchanges++;
      ok(url.includes('projects/880702682763/apps/1:880702682763:web:abc:exchangeDebugToken') && JSON.parse(init.body).debugToken === 'dbg',
         'the debug token is exchanged for the registered app');
      return new Response(JSON.stringify({ token: 'ac-token', ttl: '3600s' }), { status: 200 });
    }
    sentHeader = init.headers['x-firebase-appcheck'] || '';
    return new Response(JSON.stringify({ candidates: [{ content: { parts: [{ text: 'hi' }] } }] }), { status: 200 });
  };
  const env = freshEnv({ OWNER_ACCOUNT_IDS: 'a1', FIREBASE_API_KEY: 'fk', FIREBASE_PROJECT_ID: 'p',
                         FIREBASE_APP_ID: '1:880702682763:web:abc', APPCHECK_DEBUG_TOKEN: 'dbg' });
  await chat(env, 'a1', request, fetcher);
  await chat(env, 'a1', request, fetcher);
  ok(sentHeader === 'ac-token' && exchanges === 1, 'Gemini calls carry the App Check token, exchanged once and reused');
  let t = 0;
  forgetAppCheck();
  await appCheckToken(env, fetcher, () => t);
  t = 3_600_000;
  await appCheckToken(env, fetcher, () => t);
  ok(exchanges === 3, 'and a fresh one is fetched before the old one expires');
  ok(await appCheckToken({ FIREBASE_API_KEY: 'fk' }, fetcher) === '', 'with no debug token set, nothing is sent');
  forgetAppCheck();
}

// Narrate's cloud transcription: Pro only, through the server
{
  const { transcribeConfig, default: worker } = await import('../worker.js');
  const { transcribeChunk } = await import('../ai.js');
  const old = await transcribeConfig();
  ok(old.status === 410 && !JSON.stringify(await old.json()).includes('fk'), 'the old config endpoint no longer hands the Google key to a phone');

  const firebase = { FIREBASE_API_KEY: 'fk', FIREBASE_PROJECT_ID: 'p' };
  const asked = [];
  const google = async (url, init) => { asked.push({ url, body: JSON.parse(init.body), key: init.headers['x-goog-api-key'] });
    return new Response(JSON.stringify({ candidates: [{ content: { parts: [{ text: '[{"start":0,"end":2,"text":"malar rash"}]' }] } }],
                                         usageMetadata: { promptTokenCount: 1000, candidatesTokenCount: 50 } }), { status: 200 }); };
  const chunk = { audio: 'QUJD'.repeat(50), prompt: 'Transcribe this lecture.' };

  const free = freshEnv(firebase); // a1 is not Pro here
  ok((await transcribeChunk(free, 'a1', chunk, google)).status === 402 && asked.length === 0, 'a free account is refused before Google is asked');

  const pro = freshEnv({ ...firebase, OWNER_ACCOUNT_IDS: 'a1' });
  const r = await transcribeChunk(pro, 'a1', chunk, google);
  const j = await r.json();
  ok(r.status === 200 && j.text.includes('malar rash') && j.model === 'gemini-3.5-flash', 'a Pro account gets the transcript, from 3.5 Flash');
  const sent = asked[0];
  ok(sent.key === 'fk' && sent.body.contents[0].parts[0].inlineData.data === chunk.audio && sent.body.generationConfig.responseSchema.type === 'ARRAY',
     'the server sends the audio to Gemini with its own key and asks for timed phrases');
  ok((await transcribeChunk(pro, 'a1', { audio: '', prompt: 'x' }, google)).status === 400, 'no audio, no call');

  const capped = freshEnv({ ...firebase, OWNER_ACCOUNT_IDS: 'a1', TRANSCRIBE_DAILY: '1' });
  await transcribeChunk(capped, 'a1', chunk, google);
  ok((await transcribeChunk(capped, 'a1', chunk, google)).status === 429, 'a daily number of chunks per account');

  const billed = freshEnv({ ...firebase, OWNER_ACCOUNT_IDS: 'a1', GEMINI_BILLING: 'on', PRO_MONTHLY_BUDGET_USD: '0.017',
                            GEMINI_PRICES: 'gemini-3.5-flash:1/1' });
  ok((await transcribeChunk(billed, 'a1', chunk, google)).status === 200, 'with billing on, a Pro account transcribes within its budget');
  const over = await transcribeChunk(billed, 'a1', chunk, google);
  ok(over.status === 429 && (await over.json()).message.includes('month'), 'over its monthly budget it is told to use the phone (Gemma cannot hear)');

  const busy = await transcribeChunk(pro, 'a1', chunk, async () => new Response('{"error":{"message":"quota"}}', { status: 429 }));
  ok(busy.status === 429, 'Gemini out of quota comes back as busy, so the app falls back to the phone');

  const unsigned = await worker.fetch(new Request('https://x/transcribe/chunk', { method: 'POST', body: JSON.stringify(chunk), headers: { 'content-length': String(JSON.stringify(chunk).length) } }), pro);
  ok(unsigned.status === 401, 'the route needs a signed-in session');
  const huge = await worker.fetch(new Request('https://x/transcribe/chunk', { method: 'POST', body: '{}', headers: { 'content-length': String(50 * 1024 * 1024) } }), pro);
  ok(huge.status === 413, 'a body declared too large is refused before it is read');
}

if (failures) { console.error(`${failures} failed`); process.exit(1); }
console.log('all passed');
