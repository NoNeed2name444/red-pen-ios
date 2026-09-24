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
//   cramdown-writer  -> Baichuan-M2-32B on Novita's API (AI_WRITER_URL/KEY/MODEL),
//   cramdown-checker    the same, given MedVAL's prompt; then Gemini through
//                       CramDown's Firebase project, then Cloudflare Workers AI,
//                       each taking over when the one before is busy or out of quota
//   cramdown-doctor  -> Doctor-R1 on its own host  (AI_DOCTOR_URL, AI_DOCTOR_KEY)
//   cramdown-medval  -> MedVAL-4B on its own host  (AI_MEDVAL_URL, AI_MEDVAL_KEY)
// The last two are llama.cpp servers (see server/spaces/) - no provider offers
// these models, so they run where we put them.

import { decodeClaims } from './tokens.js';
import { medvalParts, termsPrompt, parseTerms, gather, groundedMessages, answerWithEvidence } from './evidence.js';

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

  const route = routeFor(env, body.model);
  if (!route) return fail(400, 'Unknown model.');
  if (!route.base) return fail(503, `${route.name} in the cloud isn't set up yet.`);

  const messages = clean(body.messages);
  if (!messages) return fail(400, 'Nothing to send.');

  const limit = Number(env.AI_DAILY_LIMIT) || DEFAULT_DAILY_LIMIT;
  // the owner's own builds and the accuracy benchmark are not rationed
  if (!owner && !await spend(env, accountId, limit)) {
    return fail(429, `That's today's ${limit} cloud requests used. On-device models still work, and the allowance resets at midnight UTC.`);
  }

  const maxTokens = Math.min(Math.max(Number(body.max_tokens) || 800, 16), MAX_TOKENS);
  const temperature = Math.min(Math.max(Number(body.temperature ?? 0.7), 0), 1.5);

  // The checker is shown current evidence from official sources as well as
  // the lecture (see evidence.js), so an outdated or wrong claim is caught
  // even when the lecture says it too.
  let sent = messages;
  let evidence = [];
  const last = messages[messages.length - 1]?.content || '';
  const checked = body.model === 'cramdown-checker' && medvalParts(last);
  // any other request can ask for the same evidence (the benchmark does)
  const about = checked ? checked.output : (body.ground === true ? last : '');
  if (about) {
    const picked = await complete(env, route, termsPrompt(about), 200, 0, fetcher);
    if (picked.ok) {
      evidence = await gather(parseTerms(picked.content), fetcher);
      sent = checked ? groundedMessages(messages, evidence) : answerWithEvidence(messages, evidence);
    }
  }
  const result = await complete(env, route, sent, maxTokens, temperature, fetcher);
  if (!result.ok) {
    console.error('upstream', result.status, result.detail);
    // the owner sees the provider's own words, so a clipped error still says
    // what went wrong; everyone else sees a plain sentence
    if (owner) return fail(502, `Provider ${result.status}: ${String(result.detail).slice(0, 600)}`);
    return fail(502, `The cloud model is unavailable right now (${result.status}). Try again, or use an on-device model.`);
  }
  // only what the app reads, never the upstream's own metadata
  return json({
    choices: [{ message: { role: 'assistant', content: result.content } }],
    source: result.source,
    // what the checker was shown, so the app can cite it
    ...(evidence.length ? { evidence: evidence.map(({ id, source, title, url }) => ({ id, source, title, url })) } : {}),
  });
}

/// Each job tries its sources in order until one answers: Baichuan on Novita
/// (once its key exists), then Gemini, then Cloudflare's free models. Only
/// "busy / out of quota / down" moves on; a real refusal stops.
async function complete(env, route, messages, maxTokens, temperature, fetcher) {
  let result = { ok: false, status: 503, detail: 'CramDown Cloud is not set up yet.' };
  const failures = [];
  for (const source of route.sources) {
    if (source.kind === 'gemini') result = await askGemini(env, messages, maxTokens, temperature, fetcher);
    else if (source.kind === 'workers-ai') result = await askWorkersAI(env, messages, maxTokens, temperature);
    else result = await askOpenAI(source, messages, maxTokens, temperature, fetcher);
    if (result.ok) { result.source = result.source || source.kind; break; }
    failures.push(`${source.kind} ${result.status}: ${result.detail}`);
    // busy, out of quota, down - or, for Gemini, locked by the Firebase
    // project's App Check: the next source may still answer
    const next = [408, 429, 500, 502, 503, 504].includes(result.status)
      || (source.kind === 'gemini' && [401, 403].includes(result.status));
    if (!next) break;
  }
  // every source's reason, not just the last one's
  if (!result.ok && failures.length > 1) result.detail = failures.join(' | ');
  return result;
}

async function readError(response) {
  const detail = (await response.text()).slice(0, 400);
  try {
    const parsed = JSON.parse(detail);
    return parsed?.error?.message || (typeof parsed?.error === 'string' ? parsed.error : detail);
  } catch { return detail; }
}

/// An OpenAI-compatible server (a llama.cpp host, Hugging Face's router).
async function askOpenAI(route, messages, maxTokens, temperature, fetcher) {
  const upstream = await fetcher(`${route.base.replace(/\/+$/, '')}/chat/completions`, {
    method: 'POST',
    headers: { 'content-type': 'application/json', authorization: `Bearer ${route.key}` },
    body: JSON.stringify({ model: route.model, messages, max_tokens: maxTokens, temperature, stream: false }),
  });
  if (!upstream.ok) return { ok: false, status: upstream.status, detail: await readError(upstream) };
  const content = (await upstream.json())?.choices?.[0]?.message?.content;
  return typeof content === 'string' ? { ok: true, content, source: route.model }
    : { ok: false, status: 502, detail: 'The cloud model sent back nothing usable.' };
}

/// Gemini through Firebase AI Logic, the same project Narrate transcribes with.
/// OpenAI-style turns become Gemini's: system text is the system instruction,
/// "assistant" is "model".
export function geminiBody(messages, maxTokens, temperature) {
  const system = messages.filter(m => m.role === 'system').map(m => m.content).join('\n\n');
  const contents = messages.filter(m => m.role !== 'system').map(m => ({
    role: m.role === 'assistant' ? 'model' : 'user',
    parts: [{ text: m.content.replace(/\n?\/no_think\s*$/, '') }],
  }));
  const body = { contents, generationConfig: { maxOutputTokens: maxTokens, temperature } };
  if (system) body.systemInstruction = { parts: [{ text: system }] };
  return body;
}

/// A Firebase App Check token for the Gemini calls. Firebase AI Logic now
/// refuses requests without one (and from November 2026 enforcement cannot be
/// switched off), so the worker exchanges the project's registered debug token
/// (APPCHECK_DEBUG_TOKEN, for the app FIREBASE_APP_ID) for a real App Check
/// token and reuses it until shortly before it expires.
let appCheckCache = { token: '', until: 0 };
export async function appCheckToken(env, fetcher = fetch, clock = Date.now) {
  if (!env.APPCHECK_DEBUG_TOKEN || !env.FIREBASE_APP_ID || !env.FIREBASE_API_KEY) return '';
  if (appCheckCache.token && appCheckCache.until > clock()) return appCheckCache.token;
  const project = env.FIREBASE_APP_ID.split(':')[1] || env.FIREBASE_PROJECT_ID;
  const response = await fetcher(
    `https://firebaseappcheck.googleapis.com/v1/projects/${project}/apps/${env.FIREBASE_APP_ID}:exchangeDebugToken`, {
      method: 'POST',
      headers: { 'content-type': 'application/json', 'x-goog-api-key': env.FIREBASE_API_KEY },
      body: JSON.stringify({ debugToken: env.APPCHECK_DEBUG_TOKEN }),
    });
  if (!response.ok) {
    console.error('app check', response.status, await readError(response));
    return '';
  }
  const answer = await response.json();
  const seconds = parseInt(String(answer.ttl || '3600'), 10) || 3600;
  // five minutes' margin, so a token never runs out mid-request
  appCheckCache = { token: answer.token || '', until: clock() + Math.max(60, seconds - 300) * 1000 };
  return appCheckCache.token;
}
export function forgetAppCheck() { appCheckCache = { token: '', until: 0 }; }

async function askGemini(env, messages, maxTokens, temperature, fetcher) {
  const models = (env.CLOUD_MODELS || env.TRANSCRIBE_MODELS || 'gemini-3.6-flash,gemini-3.5-flash,gemini-3.5-flash-lite,gemma-4-31b-it')
    .split(',').map(m => m.trim()).filter(Boolean);
  let last = { ok: false, status: 503, detail: 'No Gemini model is set up.' };
  const appCheck = await appCheckToken(env, fetcher);
  // the free tier counts requests per minute: when every model says "too
  // many", wait as long as Google asks (up to 30 s) and go round once more
  for (let round = 0; round < 2; round++) {
    let wait = 0;
    for (const model of models) {
      const response = await fetcher(
        `https://firebasevertexai.googleapis.com/v1beta/projects/${env.FIREBASE_PROJECT_ID}/models/${model}:generateContent`, {
          method: 'POST',
          headers: {
            'content-type': 'application/json', 'x-goog-api-key': env.FIREBASE_API_KEY,
            ...(appCheck ? { 'x-firebase-appcheck': appCheck } : {}),
          },
          body: JSON.stringify(geminiBody(messages, maxTokens, temperature)),
        });
      if (!response.ok) {
        const raw = await response.text();
        last = { ok: false, status: response.status, detail: `${model}: ${errorMessage(raw)}` };
        if (response.status === 429) wait = Math.max(wait, retryDelay(raw));
        // out of quota, overloaded or not offered: the next model may answer
        if ([404, 429, 500, 502, 503, 504].includes(response.status)) continue;
        return last;
      }
      const parts = (await response.json())?.candidates?.[0]?.content?.parts || [];
      const content = parts.filter(p => !p.thought).map(p => p.text || '').join('');
      if (content) return { ok: true, content, source: model };
      last = { ok: false, status: 502, detail: `${model}: sent back nothing usable.` };
    }
    if (last.status !== 429 || !wait || wait > 30) break;
    await sleep(wait * 1000);
  }
  return last;
}

const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));

function errorMessage(raw) {
  try {
    const parsed = JSON.parse(raw);
    return parsed?.error?.message || raw.slice(0, 400);
  } catch { return raw.slice(0, 400); }
}

/// Seconds Google asks to wait before the next request ("retryDelay": "17s").
export function retryDelay(raw) {
  const m = String(raw).match(/"retryDelay"\s*:\s*"(\d+(?:\.\d+)?)s"/);
  return m ? Math.ceil(parseFloat(m[1])) : 0;
}

/// Cloudflare Workers AI, on the account's free daily allowance.
async function askWorkersAI(env, messages, maxTokens, temperature) {
  const model = env.FALLBACK_MODEL || '@cf/nvidia/nemotron-3-120b-a12b';
  try {
    const out = await env.AI.run(model, { messages, max_tokens: maxTokens, temperature });
    const content = out?.response ?? out?.choices?.[0]?.message?.content;
    return typeof content === 'string' && content ? { ok: true, content, source: model }
      : { ok: false, status: 502, detail: 'Workers AI sent back nothing usable.' };
  } catch (error) {
    return { ok: false, status: 503, detail: String(error?.message || error).slice(0, 300) };
  }
}

/// Where each of the app's model names goes: which server, which key, which
/// model name that server expects. Unknown names get nothing.
export function routeFor(env, name) {
  const sources = [];
  // Baichuan-M2-32B on Novita, or any OpenAI-compatible server, when set
  if (env.AI_WRITER_URL && env.AI_WRITER_KEY) {
    sources.push({ kind: 'openai', base: env.AI_WRITER_URL, key: env.AI_WRITER_KEY,
                   model: env.AI_WRITER_MODEL || 'baichuan/baichuan-m2-32b' });
  }
  if (env.FIREBASE_API_KEY && env.FIREBASE_PROJECT_ID) sources.push({ kind: 'gemini' });
  if (env.AI) sources.push({ kind: 'workers-ai' });
  if (!sources.length && env.AI_API_KEY) {
    sources.push({ kind: 'openai', base: env.AI_BASE_URL || DEFAULT_BASE, key: env.AI_API_KEY,
                   model: env.AI_WRITER_MODEL || DEFAULT_MODEL });
  }
  switch (name) {
    case 'cramdown-writer':
    case 'cramdown-checker':
      return { name: 'CramDown Cloud', base: sources.length ? 'set' : '', sources };
    case 'cramdown-doctor':
      return { name: 'Doctor-R1', base: env.AI_DOCTOR_URL,
               sources: [{ kind: 'openai', base: env.AI_DOCTOR_URL, key: env.AI_DOCTOR_KEY, model: 'doctor-r1' }] };
    case 'cramdown-medval':
      return { name: 'MedVAL', base: env.AI_MEDVAL_URL,
               sources: [{ kind: 'openai', base: env.AI_MEDVAL_URL, key: env.AI_MEDVAL_KEY, model: 'medval' }] };
    default:
      return null;
  }
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
export async function spend(env, accountId, limit) {
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

/// Narrate's second transcriber: Whisper large-v3 turbo on Cloudflare Workers
/// AI, for when Gemini refuses (out of quota, or locked by App Check). One
/// ten-minute piece per call, as base64 audio, answered as timed phrases in
/// the shape the app already reads from Gemini. No sign-in, so it is rationed
/// by address: 60 pieces (ten hours) a day.
export async function whisper(request, body, env) {
  if (!env.AI) return fail(503, "Cloud transcription isn't set up on this server.");
  if (typeof body.audio !== 'string' || body.audio.length < 100 || body.audio.length > 12_000_000) {
    return fail(400, 'Send one piece of audio, base64, under 9 MB.');
  }
  const address = request.headers.get('cf-connecting-ip') || 'unknown';
  if (!await spend(env, `whisper:${address}`, Number(env.WHISPER_DAILY_PIECES) || 60)) {
    return fail(429, "That's today's cloud transcription used on this network. On this phone still works.");
  }
  try {
    const out = await env.AI.run('@cf/openai/whisper-large-v3-turbo', {
      audio: body.audio,
      language: typeof body.language === 'string' ? body.language.slice(0, 5) : undefined,
      // the lecture's own terms, so English words inside Arabic come out spelled
      initial_prompt: typeof body.prompt === 'string' ? body.prompt.slice(0, 800) : undefined,
      vad_filter: true,
      condition_on_previous_text: false,
    });
    const phrases = (out?.segments || [])
      .map(s => ({ start: Number(s.start) || 0, end: Number(s.end) || 0, text: String(s.text || '').trim() }))
      .filter(p => p.text);
    return json({ phrases, text: out?.transcription_info?.text || out?.text || '' });
  } catch (error) {
    console.error('whisper', error);
    return fail(502, 'The cloud transcriber could not read that piece.');
  }
}
