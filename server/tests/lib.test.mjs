// The shared helpers in server/lib (launch plan P0.1): codes, crypto, http,
// limits, owner and appfacts. None is on a live route yet; these pin what
// they do so the routes built on them start from tested ground.
//
// Run: node server/tests/lib.test.mjs

import { DatabaseSync } from 'node:sqlite';
import { ALPHABET, randomCode, normaliseCode } from '../lib/codes.js';
import { sha256hex, hmacHex, b64url } from '../lib/crypto.js';
import { json, fail, text, boundedText } from '../lib/http.js';
import { utcDay, ipKey, hit, refund, flag, limit } from '../lib/limits.js';
import { keyMatches, rowIsOwner, ownerCaller } from '../lib/owner.js';
import { getFact, setFact, teamId, appStoreId } from '../lib/appfacts.js';

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
        all() { return { results: stmt.all(...args) }; },
        run() { return { meta: { changes: Number(stmt.run(...args).changes) } }; },
      };
      return api;
    },
  };
}

// MARK: codes
{
  let all = '';
  for (let i = 0; i < 1000; i++) all += randomCode(10);
  ok(all.length === 10000, 'randomCode gives the length asked');
  ok([...all].every(c => ALPHABET.includes(c)), 'every character is in the alphabet');
  ok(!/[01OIL]/.test(all), 'never 0, 1, O, I or L');
  ok(new Set(all).size === ALPHABET.length, 'every letter of the alphabet turns up');
  ok(randomCode(0).length === 1 && randomCode('x').length === 1, 'a silly length still gives one character');
  ok(normaliseCode(' abcd-efgh-jk ', 10) === 'ABCDEFGHJK', 'normaliseCode upper-cases and strips');
  ok(normaliseCode('ABCDEFGHJ', 10) === null, 'a short code is refused');
  ok(normaliseCode('ABCDEFGHI0', 10) === null, 'a character outside the alphabet is refused');
  ok(normaliseCode(42, 10) === null, 'a non-string is refused');
}

// MARK: crypto
{
  ok(await sha256hex('abc') === 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad', 'sha256 of "abc"');
  ok(await sha256hex(new TextEncoder().encode('abc')) === await sha256hex('abc'), 'sha256 of bytes equals of the string');
  ok(await hmacHex('Jefe', 'what do ya want for nothing?') ===
    '5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843', 'HMAC-SHA256, RFC 4231 case 2');
  ok(b64url(new Uint8Array([0xfb, 0xff, 0xfe])) === '-__-', 'b64url swaps + and / and drops padding');
  ok(b64url('a') === 'YQ', 'b64url of a string');
}

// MARK: http
{
  const plain = await fail(400, 'Nope.').json();
  ok(plain.error === 'Nope.' && plain.message === 'Nope.' && !('code' in plain), 'fail without a code answers as the legacy routes do');
  const coded = fail(429, 'Slow down.', 'too_many', { retryAfter: 60 });
  const body = await coded.json();
  ok(coded.status === 429 && body.code === 'too_many' && body.retryAfter === 60, 'fail with a code and extras');
  ok(json({ a: 1 }).headers.get('content-type') === 'application/json', 'json sets the content type');
  ok(text('  hi  ', 10) === 'hi' && text('abcdef', 3) === 'abc' && text('   ', 3) === null && text(5, 3) === null, 'text trims, caps and refuses blanks');
  ok(await boundedText(new Request('https://w.example/', { method: 'POST', body: 'hello' }), 10) === 'hello', 'boundedText reads a small body');
  let threw = false;
  try { await boundedText(new Request('https://w.example/', { method: 'POST', body: 'x'.repeat(100) }), 10); } catch { threw = true; }
  ok(threw, 'boundedText stops past the limit');
}

// MARK: limits
{
  const db = new DatabaseSync(':memory:');
  db.exec('CREATE TABLE pair_attempts (ip TEXT NOT NULL, hour INTEGER NOT NULL, what TEXT NOT NULL, n INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (ip, hour, what))');
  const env = { DB: d1(db), SESSION_SECRET: 's'.repeat(40) };
  const clock = () => 7200;
  const a = await ipKey(env, '203.0.113.9', '2026-10-07');
  ok(/^ipk:[0-9a-f]{16}$/.test(a), 'ipKey is a short keyed hash');
  ok(!a.includes('203'), 'ipKey does not carry the address');
  ok(a === await ipKey(env, '203.0.113.9', '2026-10-07'), 'ipKey is stable within a day');
  ok(a !== await ipKey(env, '203.0.113.9', '2026-10-08'), 'and rotates the next day');
  ok(a !== await ipKey({ ...env, SESSION_SECRET: 't'.repeat(40) }, '203.0.113.9', '2026-10-07'), 'and depends on the secret');
  ok(utcDay(0) === '1970-01-01', 'utcDay');
  const tries = [];
  for (let i = 0; i < 4; i++) tries.push(await hit(env, a, 'join', 3, clock));
  ok(tries.join() === 'true,true,true,false', 'hit allows n tries an hour, then refuses');
  await refund(env, a, 'join', clock);
  ok(await hit(env, a, 'join', 3, clock) === true, 'refund gives one back');
  ok(await hit(env, a, 'join', 3, () => 10800) === true, 'the next hour starts afresh');
  ok(await hit(env, a, 'other', 3, clock) === true, 'each kind of try counts apart');
  ok(await hit(env, 'acct:x', 'join', 0, clock) === false, 'a limit of 0 refuses');
  ok(typeof flag === 'function' && typeof limit === 'function', 'limits re-exports flag and limit');
}

// MARK: owner
{
  const db = new DatabaseSync(':memory:');
  db.exec('CREATE TABLE accounts (id TEXT PRIMARY KEY, owner INTEGER NOT NULL DEFAULT 0)');
  db.exec("INSERT INTO accounts (id, owner) VALUES ('own', 1), ('stu', 0)");
  const key = 'k'.repeat(40);
  const env = { DB: d1(db), OWNER_KEY: key, OWNER_ACCOUNT_IDS: ' listed , other ' };
  const req = bearer => new Request('https://w.example/', { headers: bearer ? { authorization: 'Bearer ' + bearer } : {} });
  ok(keyMatches(req(key), key), 'keyMatches the right key');
  ok(!keyMatches(req(key.slice(1) + 'x'), key), 'not a wrong one');
  ok(!keyMatches(req('short'), 'short'), 'never a key under 32 characters');
  ok(!keyMatches(req(''), ''), 'never an unset key');
  ok(rowIsOwner(env, { id: 'own', owner: 1 }), 'rowIsOwner for an owner row');
  ok(rowIsOwner(env, { id: 'listed', owner: 0 }), 'and for a listed id');
  ok(!rowIsOwner(env, { id: 'stu', owner: 0 }) && !rowIsOwner(env, null), 'not for anyone else');
  ok(await ownerCaller(req(key), env, null) === 'owner-key', 'ownerCaller: the owner key');
  ok(await ownerCaller(req('x'.repeat(40)), env, async () => 'own') === 'own', 'ownerCaller: an owner account');
  ok(await ownerCaller(req('x'.repeat(40)), env, async () => 'listed') === 'listed', 'ownerCaller: a listed account');
  ok(await ownerCaller(req('x'.repeat(40)), env, async () => 'stu') === null, 'ownerCaller: a student is nobody');
  ok(await ownerCaller(req(''), env, async () => null) === null, 'ownerCaller: signed out is nobody');
}

// MARK: appfacts
{
  const bare = { DB: d1(new DatabaseSync(':memory:')), APPLE_BUNDLE_ID: 'com.example.app' };
  ok(await getFact(bare, 'apple_team_id') === null, 'getFact without the table is null, not an error');
  ok(await teamId({ ...bare, APPLE_TEAM_ID: 'ABCDE12345' }) === 'ABCDE12345', 'teamId falls back to the env');
  ok(await teamId({ ...bare, APPLE_TEAM_ID: 'bad' }) === null, 'and refuses a malformed one');
  ok(await appStoreId(bare, async () => { throw new Error('should not fetch'); }) === null, 'appStoreId without the table is null');

  const db = new DatabaseSync(':memory:');
  db.exec('CREATE TABLE app_facts (key TEXT PRIMARY KEY, value TEXT NOT NULL, updated_at INTEGER NOT NULL)');
  const env = { DB: d1(db), APPLE_BUNDLE_ID: 'com.example.app' };
  ok(await appStoreId({ ...env, APPLE_APP_ID: '1234567890' }) === '1234567890', 'appStoreId: env wins');
  let asked = 0;
  const missing = async () => { asked++; return new Response(JSON.stringify({ results: [] })); };
  ok(await appStoreId(env, missing, () => 1000) === null, 'not on the store yet: null');
  ok(await appStoreId(env, missing, () => 2000) === null && asked === 1, 'and Apple is not asked again within the hour');
  const found = async () => { asked++; return new Response(JSON.stringify({ results: [{ trackId: 987654321 }] })); };
  ok(await appStoreId(env, found, () => 1000 + 3600) === '987654321' && asked === 2, 'an hour on, asked again and found');
  ok(await appStoreId(env, async () => { throw new Error('no'); }, () => 9e9) === '987654321', 'then remembered without asking');
  await setFact(env, 'apple_team_id', 'ZYXWV98765', () => 1);
  ok(await teamId({ ...env, APPLE_TEAM_ID: 'ABCDE12345' }) === 'ZYXWV98765', 'a stored team id wins over the env');
}

console.log(failures ? `\n${failures} failed` : '\nall passed');
process.exit(failures ? 1 : 0);
