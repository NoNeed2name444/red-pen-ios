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

if (failures) { console.error(`${failures} failed`); process.exit(1); }
console.log('all passed');
