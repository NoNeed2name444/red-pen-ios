// CramDown Cloud: the premium hosted models, behind the same worker as sign-in
// and sync.
//
// The app speaks plain OpenAI-style `/v1/chat/completions` to this worker with
// its own session token. The worker checks two things - that the account has
// a live Pro subscription, confirmed with Apple rather than taken on the app's
// word, and that it is inside its daily allowance - and only then forwards the
// request upstream with the provider key it holds as a secret. The key never
// reaches a phone.
//
// Two model names are accepted, one per job, and mapped here so a model can be
// swapped without an app update:
//   cramdown-writer  -> AI_WRITER_MODEL   (default Baichuan-M2-32B)
//   cramdown-checker -> AI_CHECKER_MODEL  (default the same model, given MedVAL's prompt)

import { decodeClaims } from './tokens.js';

const DEFAULT_BASE = 'https://router.huggingface.co/v1';
const DEFAULT_MODEL = 'baichuan-inc/Baichuan-M2-32B';
const DEFAULT_DAILY_LIMIT = 400;
const MAX_PROMPT_CHARS = 60_000;
const MAX_TOKENS = 2_000;
/// How long a confirmed subscription is trusted before Apple is asked again.
const RECHECK_SECONDS = 6 * 60 * 60;

const json = (body, status = 200) => new Response(JSON.stringify(body), {
  status, headers: { 'content-type': 'application/json' },
});
const fail = (status, message) => json({ error: { message }, message }, status);
const now = () => Math.floor(Date.now() / 1000);
const today = () => new Date().toISOString().slice(0, 10);

export async function chat(env, accountId, body, fetcher = fetch, { owner = false } = {}) {
  // The owner key (the app owner's own builds) skips the account and the
  // subscription check, but not the daily allowance.
  if (!owner) {
    const account = await env.DB.prepare('SELECT * FROM accounts WHERE id = ?')
      .bind(accountId).first();
    if (!account) return fail(401, 'Please sign in again.');
    if (!await isPro(env, account, fetcher)) {
      return fail(402, 'CramDown Cloud is part of Pro.');
    }
  }

  const model = { 'cramdown-writer': env.AI_WRITER_MODEL || DEFAULT_MODEL,
                  'cramdown-checker': env.AI_CHECKER_MODEL || env.AI_WRITER_MODEL || DEFAULT_MODEL }[body.model];
  if (!model) return fail(400, 'Unknown model.');

  const messages = clean(body.messages);
  if (!messages) return fail(400, 'Nothing to send.');

  const limit = Number(env.AI_DAILY_LIMIT) || DEFAULT_DAILY_LIMIT;
  if (!await spend(env, accountId, limit)) {
    return fail(429, `That's today's ${limit} cloud requests used. On-device models still work, and the allowance resets at midnight UTC.`);
  }

  if (!env.AI_API_KEY) return fail(503, 'CramDown Cloud is not set up yet.');
  const upstream = await fetcher(`${(env.AI_BASE_URL || DEFAULT_BASE).replace(/\/+$/, '')}/chat/completions`, {
    method: 'POST',
    headers: { 'content-type': 'application/json', authorization: `Bearer ${env.AI_API_KEY}` },
    body: JSON.stringify({
      model,
      messages,
      max_tokens: Math.min(Math.max(Number(body.max_tokens) || 800, 16), MAX_TOKENS),
      temperature: Math.min(Math.max(Number(body.temperature ?? 0.7), 0), 1.5),
      stream: false,
    }),
  });
  if (!upstream.ok) {
    console.error('upstream', upstream.status, (await upstream.text()).slice(0, 300));
    return fail(502, 'The cloud model is unavailable right now. Try again, or use an on-device model.');
  }
  const answer = await upstream.json();
  const content = answer?.choices?.[0]?.message?.content;
  if (typeof content !== 'string') return fail(502, 'The cloud model sent back nothing usable.');
  // only what the app reads, never the upstream's own metadata
  return json({ choices: [{ message: { role: 'assistant', content } }] });
}

/// Roles and strings only, and a ceiling on the total, so the proxy cannot be
/// used to send a provider anything the app itself would not.
export function clean(raw) {
  if (!Array.isArray(raw) || raw.length === 0 || raw.length > 60) return null;
  let total = 0;
  const out = [];
  for (const m of raw) {
    if (!m || !['system', 'user', 'assistant'].includes(m.role) || typeof m.content !== 'string') return null;
    total += m.content.length;
    if (total > MAX_PROMPT_CHARS) return null;
    out.push({ role: m.role, content: m.content });
  }
  return out;
}

/// One more request today, if the allowance has room. The increment and the
/// check are one statement, so two requests at once cannot both take the last one.
async function spend(env, accountId, limit) {
  const day = today();
  const result = await env.DB.prepare(
    `INSERT INTO ai_usage (account_id, day, requests) VALUES (?, ?, 1)
     ON CONFLICT (account_id, day) DO UPDATE SET requests = requests + 1
     WHERE requests < ?`)
    .bind(accountId, day, limit).run();
  return (result.meta?.changes ?? 0) > 0;
}

// MARK: is this account Pro?

/// Owner accounts (a comma-separated list in OWNER_ACCOUNT_IDS) always are;
/// everyone else is Pro while Apple last said so, re-asked every few hours.
export async function isPro(env, account, fetcher = fetch) {
  const owners = (env.OWNER_ACCOUNT_IDS || '').split(',').map(s => s.trim()).filter(Boolean);
  if (owners.includes(account.id)) return true;
  if ((account.verified_until || 0) > now() && now() - (account.checked_at || 0) < RECHECK_SECONDS) return true;
  if (!account.original_transaction_id) return false;
  const until = await askApple(env, account.original_transaction_id, fetcher);
  await env.DB.prepare('UPDATE accounts SET verified_until = ?, checked_at = ? WHERE id = ?')
    .bind(until, now(), account.id).run();
  return until > now();
}

/// Records which subscription belongs to this account, confirmed with Apple
/// before it is believed. Called by the app whenever StoreKit reports a plan.
export async function linkSubscription(env, accountId, body, fetcher = fetch) {
  const original = typeof body.originalTransactionId === 'string'
    && /^\d{1,30}$/.test(body.originalTransactionId) ? body.originalTransactionId : null;
  if (!original) return json({ ok: true, pro: false });
  const until = await askApple(env, original, fetcher);
  await env.DB.prepare(
    'UPDATE accounts SET original_transaction_id = ?, verified_until = ?, checked_at = ? WHERE id = ?')
    .bind(original, until, now(), accountId).run();
  return json({ ok: true, pro: until > now() });
}

/// Until when Apple says this subscription is live: its expiry while active
/// or in billing grace, otherwise 0. Asked of the App Store Server API over
/// TLS, so the answer is Apple's own; production first, then the sandbox that
/// TestFlight purchases live in.
export async function askApple(env, originalTransactionId, fetcher = fetch) {
  if (!env.ASC_KEY_ID || !env.ASC_ISSUER_ID || !env.ASC_PRIVATE_KEY) return 0;
  const token = await appStoreToken(env);
  for (const host of ['https://api.storekit.itunes.apple.com', 'https://api.storekit-sandbox.itunes.apple.com']) {
    const response = await fetcher(`${host}/inApps/v1/subscriptions/${originalTransactionId}`, {
      headers: { authorization: `Bearer ${token}` },
    });
    if (response.status === 404) continue;
    if (!response.ok) return 0;
    const answer = await response.json();
    if (answer.bundleId && answer.bundleId !== env.APPLE_BUNDLE_ID) return 0;
    let until = 0;
    for (const group of answer.data || []) {
      for (const last of group.lastTransactions || []) {
        // 1 active, 4 billing grace period - both still entitled
        if (last.status !== 1 && last.status !== 4) continue;
        const info = decodeClaims(last.signedTransactionInfo || '') || {};
        const expires = Math.floor((info.expiresDate || 0) / 1000);
        // grace has no new expiry yet; a day at a time until Apple decides
        until = Math.max(until, last.status === 4 ? now() + 86_400 : expires);
      }
    }
    return until;
  }
  return 0;
}

/// The short-lived ES256 token the App Store Server API wants, signed with the
/// in-app purchase key from App Store Connect (a .p8, kept as a secret).
async function appStoreToken(env) {
  const b64url = bytes => btoa(String.fromCharCode(...new Uint8Array(bytes)))
    .replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
  const enc = obj => b64url(new TextEncoder().encode(JSON.stringify(obj)));
  const header = { alg: 'ES256', kid: env.ASC_KEY_ID, typ: 'JWT' };
  const issued = now();
  const payload = { iss: env.ASC_ISSUER_ID, iat: issued, exp: issued + 600,
                    aud: 'appstoreconnect-v1', bid: env.APPLE_BUNDLE_ID };
  const pem = env.ASC_PRIVATE_KEY.replace(/-----[^-]+-----/g, '').replace(/\s+/g, '');
  const der = Uint8Array.from(atob(pem), c => c.charCodeAt(0));
  const key = await crypto.subtle.importKey('pkcs8', der, { name: 'ECDSA', namedCurve: 'P-256' },
                                            false, ['sign']);
  const input = `${enc(header)}.${enc(payload)}`;
  // WebCrypto's ECDSA signature is already raw r||s, which is what a JWS wants
  const signature = await crypto.subtle.sign({ name: 'ECDSA', hash: 'SHA-256' }, key,
                                             new TextEncoder().encode(input));
  return `${input}.${b64url(signature)}`;
}

/// True when the request carries the owner key: a secret derived on GitHub
/// from AI_API_KEY and baked only into the owner's personal build, for using
/// CramDown Cloud without an Apple or Google account. Compared in constant
/// time; an unset or short key never matches.
export function isOwnerKey(request, env) {
  const key = env.OWNER_KEY || '';
  const given = (request.headers.get('authorization') || '').replace(/^Bearer /, '');
  if (key.length < 32 || given.length !== key.length) return false;
  let diff = 0;
  for (let i = 0; i < key.length; i++) diff |= key.charCodeAt(i) ^ given.charCodeAt(i);
  return diff === 0;
}
