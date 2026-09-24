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
  // subscription check, but not a daily allowance of its own.
  if (!owner) {
    const refused = await proGate(env, accountId, fetcher, 'Vignette Cloud is part of Pro.');
    if (refused) return refused;
  }

  const route = routeFor(env, body.model);
  if (!route) return fail(400, 'Unknown model.');
  if (!route.base) return fail(503, `${route.name} in the cloud isn't set up yet.`);

  const messages = clean(body.messages);
  if (!messages) return fail(400, 'Nothing to send.');
  route.canPay = await canPay(env, accountId, owner);
  route.account = owner ? '' : accountId;
  const gemini = route.sources?.find(s => s.kind === 'gemini');
  if (gemini) gemini.models = await geminiModels(env, accountId, owner, 'modes', route.canPay);

  // the owner's own builds and the accuracy benchmark get a much higher
  // allowance, but still one: a leaked owner key cannot spend without end
  const limit = owner ? Number(env.OWNER_DAILY_LIMIT) || 3000 : Number(env.AI_DAILY_LIMIT) || DEFAULT_DAILY_LIMIT;
  if (!await spend(env, owner ? 'owner' : accountId, limit)) {
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

/// Null for a signed-in Pro account, otherwise the refusal to send back.
async function proGate(env, accountId, fetcher, why) {
  const account = await env.DB.prepare('SELECT * FROM accounts WHERE id = ?').bind(accountId).first();
  if (!account) return fail(401, 'Please sign in again.');
  if (!await isPro(env, account, fetcher)) return fail(402, why);
  return null;
}

// MARK: Narrate's cloud transcription

/// What Gemini is asked to send back for a stretch of lecture: timed phrases.
const PHRASES = {
  type: 'ARRAY',
  items: { type: 'OBJECT', properties: { start: { type: 'NUMBER' }, end: { type: 'NUMBER' }, text: { type: 'STRING' } },
           required: ['start', 'end', 'text'] },
};
const MAX_AUDIO_CHARS = 9_000_000; // base64 of ~6.7 MB: a ten-minute chunk is ~3.2 MB

/// One chunk of a lecture recording, transcribed by Gemini for a Pro account.
///
/// The audio comes through here rather than going from the phone to Google
/// so that the Google key never leaves the server: only Pro accounts can
/// use it, each within a daily number of chunks and, once Pro pays for
/// Gemini, within its monthly budget.
export async function transcribeChunk(env, accountId, body, fetcher = fetch, { owner = false } = {}) {
  if (!env.FIREBASE_API_KEY || !env.FIREBASE_PROJECT_ID) return fail(503, "Cloud transcription isn't set up on this server.");
  if (!owner) {
    const refused = await proGate(env, accountId, fetcher, 'Cloud transcription is part of Pro.');
    if (refused) return refused;
  }
  const audio = typeof body?.audio === 'string' ? body.audio : '';
  const prompt = typeof body?.prompt === 'string' ? body.prompt.slice(0, 20000) : '';
  if (!audio || audio.length > MAX_AUDIO_CHARS || !/^[A-Za-z0-9+/=]+$/.test(audio.slice(0, 200)) || !prompt) {
    return fail(400, 'That audio could not be sent.');
  }
  const limit = owner ? 200 : Number(env.TRANSCRIBE_DAILY) || 36; // ten-minute chunks: six hours a day
  if (!await spend(env, `transcribe:${owner ? 'owner' : accountId}`, limit)) {
    return fail(429, "That's today's cloud transcription used. It resets at midnight UTC; this phone can still transcribe.");
  }
  const models = await geminiModels(env, accountId, owner, 'transcribe');
  if (!models.length) return fail(429, "This month's cloud transcription is used up. This phone can still transcribe.");
  const result = await generate(env, models, () => ({
    contents: [{ role: 'user', parts: [{ inlineData: { mimeType: 'audio/mp4', data: audio } }, { text: prompt }] }],
    generationConfig: { temperature: 0, maxOutputTokens: 16384, responseMimeType: 'application/json', responseSchema: PHRASES },
  }), fetcher);
  if (!result.ok) {
    console.error('transcribe', result.status, result.detail);
    const busy = [429, 500, 502, 503, 504].includes(result.status);
    return fail(busy ? 429 : 502, busy ? 'Gemini is busy or out of quota right now. Try again later, or transcribe on this phone.'
                                      : `Gemini couldn't transcribe that (${result.status}).`);
  }
  if (!owner) await charge(env, accountId, result.source, result.usage).catch(e => console.error('charge', e));
  return json({ text: result.content, model: result.source });
}

/// Each job tries its sources in order until one answers: Baichuan on Novita
/// (once its key exists), then Gemini, then Cloudflare's free models. Only
/// "busy / out of quota / down" moves on; a real refusal stops.
async function complete(env, route, messages, maxTokens, temperature, fetcher) {
  let result = { ok: false, status: 503, detail: 'Vignette Cloud is not set up yet.' };
  const failures = [];
  for (const source of route.sources) {
    // a paid host (Baichuan on Novita) only while Pro money covers it
    if (source.paid && !route.canPay) continue;
    if (source.kind === 'gemini') result = await askGemini(env, messages, maxTokens, temperature, fetcher, source.models);
    else if (source.kind === 'workers-ai') result = await askWorkersAI(env, messages, maxTokens, temperature);
    else result = await askOpenAI(source, messages, maxTokens, temperature, fetcher);
    // a bookkeeping failure never costs the student their answer
    if (result.ok && route.account) await charge(env, route.account, result.source, result.usage).catch(e => console.error('charge', e));
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
  const answer = await upstream.json();
  const content = answer?.choices?.[0]?.message?.content;
  return typeof content === 'string' ? { ok: true, content, source: route.model, usage: answer.usage }
    : { ok: false, status: 502, detail: 'The cloud model sent back nothing usable.' };
}

/// Gemini through Firebase AI Logic, the same project Narrate transcribes with.
/// OpenAI-style turns become Gemini's: system text is the system instruction,
/// "assistant" is "model".
export function geminiBody(messages, maxTokens, temperature, model = '') {
  const system = messages.filter(m => m.role === 'system').map(m => m.content).join('\n\n');
  const contents = messages.filter(m => m.role !== 'system').map(m => ({
    role: m.role === 'assistant' ? 'model' : 'user',
    parts: [{ text: m.content.replace(/\n?\/no_think\s*$/, '') }],
  }));
  const body = { contents, generationConfig: { maxOutputTokens: maxTokens, temperature } };
  // Gemma thinks out loud by default and the thinking counts against the
  // output limit, which left no room for the answer itself
  if (model.startsWith('gemma')) body.generationConfig.thinkingConfig = { thinkingLevel: 'minimal' };
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

async function askGemini(env, messages, maxTokens, temperature, fetcher, chosen) {
  const models = chosen?.length ? chosen : list(env.CLOUD_MODELS || FREE_MODELS);
  return generate(env, models, model => geminiBody(messages, maxTokens, temperature, model), fetcher);
}

/// One Gemini request, trying each model in turn while the answer is "busy",
/// "out of quota" or "not offered".
async function generate(env, models, bodyFor, fetcher) {
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
          body: JSON.stringify(bodyFor(model)),
        });
      if (!response.ok) {
        const raw = await response.text();
        last = { ok: false, status: response.status, detail: `${model}: ${errorMessage(raw)}` };
        // "overloaded" comes as a 429 with no delay: a few seconds is enough
        if (response.status === 429) wait = Math.max(wait, retryDelay(raw) || 5);
        // out of quota, overloaded or not offered: the next model may answer
        if ([404, 429, 500, 502, 503, 504].includes(response.status)) continue;
        return last;
      }
      const answer = await response.json();
      const parts = answer?.candidates?.[0]?.content?.parts || [];
      const content = parts.filter(p => !p.thought).map(p => p.text || '').join('');
      if (content) return { ok: true, content, source: model, usage: answer.usageMetadata };
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

// MARK: who pays for Gemini

const FREE_MODELS = 'gemini-3.5-flash,gemini-3.5-flash-lite,gemma-4-31b-it';
const PAID_MODELS = 'gemini-3.5-flash,gemini-3.5-flash-lite,gemma-4-31b-it';
const TRANSCRIBE_MODELS = 'gemini-3.5-flash,gemini-3.5-flash-lite';
const list = text => String(text).split(',').map(m => m.trim()).filter(Boolean);
const month = () => new Date().toISOString().slice(0, 7);

/// Pro pays for everything that costs money.
///
/// Until launch (PRO_PAYS = "off") nothing paid is used at all: Google's free
/// allowances, Gemma and Cloudflare's free models. Once the paid accounts
/// exist and PRO_PAYS is "on", what Pro brings in sets what may be spent:
///
///   revenue  = active Pro subscriptions x PRO_NET_MONTHLY_USD (after Apple's cut)
///   fixed    = MONTHLY_BILLS, by name (GitHub Actions minutes, Cloudflare
///              Workers Paid, Apple's developer fee, a rented GPU server, ...)
///   for use  = revenue x COST_SHARE - fixed
///
/// Every paid call (Gemini on the Blaze plan, Baichuan on Novita, ...) is
/// estimated from its token counts and GEMINI_PRICES and added up per
/// account and per month. A request may use a paid service while both its
/// account (an equal share of "for use", or PRO_MONTHLY_BUDGET_USD) and
/// everyone together are under budget; otherwise it gets the free models.
export function proPays(env) {
  return env.PRO_PAYS === 'on' || env.GEMINI_BILLING === 'on';
}

export async function budget(env) {
  const net = Number(env.PRO_NET_MONTHLY_USD) || 0;
  const share = Number(env.COST_SHARE) || 0.6;
  // every monthly bill by name ("github-actions:4,apple-developer:8.25"), so a
  // new cost is one more entry rather than a code change
  const bills = Object.fromEntries(list(env.MONTHLY_BILLS || '').map(b => b.split(':')).map(([k, v]) => [k, Number(v) || 0]));
  const fixed = Object.values(bills).reduce((a, b) => a + b, 0) + (Number(env.FIXED_MONTHLY_USD) || 0);
  let subscribers = 0, spent = 0;
  try {
    subscribers = (await env.DB.prepare('SELECT COUNT(*) AS n FROM accounts WHERE verified_until > ?').bind(now()).first())?.n || 0;
    spent = ((await env.DB.prepare('SELECT SUM(micro_usd) AS s FROM ai_cost WHERE month = ?').bind(month()).first())?.s || 0) / 1e6;
  } catch { /* tables not there yet */ }
  const revenue = subscribers * net;
  const forUse = Math.max(0, revenue * share - fixed);
  // until the price is set, a flat allowance per account and no overall cap
  const perAccount = Number(env.PRO_MONTHLY_BUDGET_USD) || (net ? forUse / Math.max(subscribers, 1) : 2);
  return { subscribers, revenue, bills, fixed, forUse: net ? forUse : Infinity, perAccount, spent };
}

export async function canPay(env, accountId, owner = false) {
  if (!proPays(env)) return false;
  if (owner) return true;
  const money = await budget(env);
  if (money.spent >= money.forUse) return false;
  let mine = 0;
  try {
    mine = ((await env.DB.prepare('SELECT micro_usd FROM ai_cost WHERE account_id = ? AND month = ?')
      .bind(accountId, month()).first())?.micro_usd || 0) / 1e6;
  } catch { /* nothing spent */ }
  return mine < money.perAccount;
}

export async function geminiModels(env, accountId, owner = false, purpose = 'modes', paying) {
  const audio = purpose === 'transcribe';
  if (!proPays(env)) return list(audio ? env.TRANSCRIBE_MODELS || TRANSCRIBE_MODELS : env.CLOUD_MODELS || FREE_MODELS);
  const ok = paying ?? await canPay(env, accountId, owner);
  // over budget: the free Gemma for the modes; Gemma cannot hear, so
  // transcription goes back to the phone
  if (!ok) return audio ? [] : list(env.BUDGET_MODELS || 'gemma-4-31b-it');
  return list(audio ? env.PAID_TRANSCRIBE_MODELS || env.TRANSCRIBE_MODELS || TRANSCRIBE_MODELS
                    : env.PAID_MODELS || PAID_MODELS);
}

/// Dollars per million tokens, input/output, from GEMINI_PRICES
/// ("model:in/out,..."). A model with no price (Gemma) costs nothing.
export function priceOf(env, model) {
  for (const entry of list(env.GEMINI_PRICES || '')) {
    const [name, rates] = entry.split(':');
    if (name === model) {
      const [input, output] = rates.split('/').map(Number);
      return { input: input || 0, output: output || 0 };
    }
  }
  return { input: 0, output: 0 };
}

/// Adds one answer's estimated cost to the account's month. Thinking is
/// billed as output, so it counts too.
export async function charge(env, accountId, model, usage) {
  if (!proPays(env) || !usage || !accountId) return;
  const price = priceOf(env, model);
  const input = usage.promptTokenCount ?? usage.prompt_tokens ?? 0;
  const out = (usage.candidatesTokenCount ?? usage.completion_tokens ?? 0) + (usage.thoughtsTokenCount || 0);
  const micro = Math.ceil(input * price.input + out * price.output);
  if (!micro) return;
  await env.DB.prepare(
    `INSERT INTO ai_cost (account_id, month, micro_usd) VALUES (?, ?, ?)
     ON CONFLICT (account_id, month) DO UPDATE SET micro_usd = micro_usd + excluded.micro_usd`)
    .bind(accountId, month(), micro).run();
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
    sources.push({ kind: 'openai', base: env.AI_WRITER_URL, key: env.AI_WRITER_KEY, paid: true,
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
      return { name: 'Vignette Cloud', base: sources.length ? 'set' : '', sources };
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
  if (until === null) return (account.verified_until || 0) > now();
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
  // one subscription unlocks one account: a transaction id is not a secret
  // (it is in every receipt), so without this anyone given one gets Pro
  const holder = await env.DB.prepare('SELECT id FROM accounts WHERE original_transaction_id = ? AND id != ?')
    .bind(original, accountId).first();
  if (holder) return fail(409, 'This subscription is already linked to another Vignette account. Sign in with that account, or contact support to move it.');
  const until = await askApple(env, original, fetcher);
  if (until === null) return fail(503, "Apple couldn't be reached to confirm the subscription. Try again in a minute.");
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
    // Apple busy or down says nothing about the subscription: null, so the
    // last answer we had stands rather than a subscriber losing Pro
    if (!response.ok) return null;
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
