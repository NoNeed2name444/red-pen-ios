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
import { chat, clean, linkSubscription, isOwnerKey } from '../ai.js';

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
    { status: 1, signedTransactionInfo: jws({ expiresDate: future }) }] }] };
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
    { status: 1, signedTransactionInfo: jws({ expiresDate: Date.now() + 1e9 }) }] }] };
  const linked = await (await linkSubscription(env, 'a1', { originalTransactionId: '2000000125' }, fakeFetch(apple))).json();
  ok(linked.pro === false, "a subscription for a different bundle id doesn't count");
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

// Where CramDown Cloud goes: Baichuan-M3 first when its key is set, then
// Gemini, then Workers AI
{
  const { routeFor } = await import('../ai.js');
  const old = routeFor({ AI_API_KEY: 'hf' }, 'cramdown-writer');
  ok(old.sources.length === 1 && old.sources[0].base.includes('huggingface'), 'with nothing else set it is the old Hugging Face route');
  const all = routeFor({ AI_API_KEY: 'hf', AI_WRITER_URL: 'https://api.baichuan-ai.com/v1', AI_WRITER_KEY: 'bk',
                         FIREBASE_API_KEY: 'fk', FIREBASE_PROJECT_ID: 'p', AI: {} }, 'cramdown-checker');
  ok(all.sources.map(x => x.kind).join('>') === 'openai>gemini>workers-ai', 'Baichuan-M3, then Gemini, then Workers AI');
  ok(all.sources[0].model === 'Baichuan-M3' && all.sources[0].key === 'bk', 'Baichuan-M3 by default, with its own key');

  const seen = [];
  const fetcher = async (url) => {
    seen.push(url);
    if (url.includes('baichuan')) return new Response(JSON.stringify({ error: { message: 'rate limit' } }), { status: 429 });
    return new Response(JSON.stringify({ candidates: [{ content: { parts: [{ text: 'from gemini' }] } }] }), { status: 200 });
  };
  const env = freshEnv({ OWNER_ACCOUNT_IDS: 'a1', AI_WRITER_URL: 'https://api.baichuan-ai.com/v1', AI_WRITER_KEY: 'bk',
                         FIREBASE_API_KEY: 'fk', FIREBASE_PROJECT_ID: 'p' });
  const r = await chat(env, 'a1', request, fetcher);
  ok(r.status === 200 && (await r.json()).choices[0].message.content === 'from gemini' && seen[0].includes('baichuan'),
     'Baichuan-M3 busy (5 a minute): Gemini answers instead');
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

  const none = await chat(freshEnv(firebase), 'a1', request, gemini(429), { owner: true });
  ok(none.status === 502 && (await none.json()).message.startsWith('Provider 429'), 'with no fallback the owner sees why');
}

// Narrate's transcription settings
{
  const { transcribeConfig, default: worker } = await import('../worker.js');
  const none = transcribeConfig({});
  ok(none.status === 503, 'transcription config says so when Firebase is not set up');
  const set = await transcribeConfig({ FIREBASE_API_KEY: 'fk', FIREBASE_PROJECT_ID: 'cramdown-x' }).json();
  ok(set.apiKey === 'fk' && set.projectId === 'cramdown-x', 'and hands back the project once it is');
  ok(set.models[0] === 'gemini-3.5-flash' && set.models.includes('gemini-3.5-flash-lite'),
     'with Gemini 3.5 Flash first and Flash-Lite as the fallback');
  const swapped = await transcribeConfig({ FIREBASE_API_KEY: 'fk', FIREBASE_PROJECT_ID: 'p', TRANSCRIBE_MODELS: 'gemini-3.8-flash, gemini-3.5-flash' }).json();
  ok(swapped.models.join('|') === 'gemini-3.8-flash|gemini-3.5-flash', 'a model swap is a server setting, not an app update');
  const routed = await worker.fetch(new Request('https://x/transcribe/config', { method: 'POST' }),
                                    { FIREBASE_API_KEY: 'fk', FIREBASE_PROJECT_ID: 'p' });
  ok(routed.status === 200, 'and it is routed without a sign-in');
}

if (failures) { console.error(`${failures} failed`); process.exit(1); }
console.log('all passed');
