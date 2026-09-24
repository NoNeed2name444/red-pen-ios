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
  route.wallet = await wallet(env, accountId, owner);
  route.canPay = await canPay(env, accountId, owner, route.wallet);
  const gemini = route.sources?.find(s => s.kind === 'gemini');
  if (gemini) gemini.models = await geminiModels(env, accountId, owner, 'modes', route.canPay);
  // The checker is a different model from the writer: a model grading its
  // own work tends to agree with itself. 3.5 Flash checks first (fast, and
  // not the 3.1 Pro that writes); `avoid` names the models that wrote what
  // is being checked, and they are skipped while any other is left.
  if (gemini && body.model === 'cramdown-checker') gemini.models = checkerOrder(env, gemini.models, body.avoid);
  // The owner's benchmarks: one named model and nothing else, so models can
  // be compared ("gemini:gemini-3.5-flash", "workers-ai:@cf/...", "hf:org/model").
  if (owner && typeof body.use === 'string') {
    const pinned = pinnedSource(env, body.use);
    if (!pinned) return fail(400, 'That model is not available on this server.');
    route.sources = [pinned];
  }

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

export function pinnedSource(env, use) {
  const at = use.indexOf(':');
  const kind = use.slice(0, at), model = use.slice(at + 1).trim();
  if (at < 1 || !model || model.length > 120) return null;
  if (kind === 'gemini' && env.FIREBASE_API_KEY && env.FIREBASE_PROJECT_ID) return { kind: 'gemini', models: [model] };
  if (kind === 'workers-ai' && env.AI) return { kind: 'workers-ai', model };
  if (kind === 'hf' && env.AI_API_KEY) return { kind: 'openai', base: env.AI_BASE_URL || DEFAULT_BASE, key: env.AI_API_KEY, model };
  return null;
}

export function checkerOrder(env, models, avoid) {
  const order = list(env.CHECKER_MODELS || CHECKER_MODELS);
  const ranked = [...models].sort((a, b) => rank(order, a) - rank(order, b));
  const skip = new Set(Array.isArray(avoid) ? avoid.filter(m => typeof m === 'string') : []);
  const others = ranked.filter(m => !skip.has(m));
  return others.length ? others : ranked;
}
const rank = (order, model) => (order.indexOf(model) + 1) || order.length + 1;

/// Null for a signed-in Pro account, otherwise the refusal to send back.
export async function proGate(env, accountId, fetcher, why) {
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
  // the month's budget first: a refusal there should not use up a chunk of
  // today's allowance
  const payer = await wallet(env, accountId, owner);
  const paying = await canPay(env, accountId, owner, payer);
  const models = await geminiModels(env, accountId, owner, 'transcribe', paying);
  if (!models.length) return fail(429, "This month's cloud transcription is used up. This phone can still transcribe.");
  const limit = owner ? 200 : Number(env.TRANSCRIBE_DAILY) || 36; // ten-minute chunks: six hours a day
  if (!await spend(env, `transcribe:${owner ? 'owner' : accountId}`, limit)) {
    return fail(429, "That's today's cloud transcription used. It resets at midnight UTC; this phone can still transcribe.");
  }
  // 32 kbps audio is 4,000 bytes a second, and Gemini counts 32 tokens a second
  const audioTokens = Math.ceil(audio.length * 0.75 / 4000 * 32);
  let reserved = 0, actual = 0;
  if (paying && payer) {
    reserved = worstCase(env, models, Math.ceil(prompt.length / 3), audioTokens, 16384);
    if (!await reserve(env, payer, reserved)) return fail(429, "This month's cloud transcription is used up. This phone can still transcribe.");
  }
  // one round only: a nine-megabyte upload is not something to repeat on a timer
  const result = await generate(env, models, () => ({
    contents: [{ role: 'user', parts: [{ inlineData: { mimeType: 'audio/mp4', data: audio } }, { text: prompt }] }],
    generationConfig: { temperature: 0, maxOutputTokens: 16384, responseMimeType: 'application/json', responseSchema: PHRASES },
  }), fetcher, { rounds: 1, onUsage: (model, usage) => { actual += costOf(env, model, usage); } });
  if (reserved) await settle(env, payer, reserved, actual).catch(e => console.error('settle', e));
  if (!result.ok) {
    console.error('transcribe', result.status, result.detail);
    const busy = [429, 500, 502, 503, 504].includes(result.status);
    return fail(busy ? 429 : 502, busy ? 'Gemini is busy or out of quota right now. Try again later, or transcribe on this phone.'
                                      : `Gemini couldn't transcribe that (${result.status}).`);
  }
  return json({ text: result.content, model: result.source });
}

/// Each job tries its sources in order until one answers: Baichuan on Novita
/// (once its key exists), then Gemini, then Cloudflare's free models. Only
/// "busy / out of quota / down" moves on; a real refusal stops.
async function complete(env, route, messages, maxTokens, temperature, fetcher) {
  let result = { ok: false, status: 503, detail: 'Vignette Cloud is not set up yet.' };
  const failures = [];
  // Paid calls hold back their worst case before they go, so requests arriving
  // together cannot all spend the same last dollar; the difference is settled
  // after, from what Google or Novita actually counted.
  let reserved = 0, actual = 0;
  const gemini = route.sources.find(s => s.kind === 'gemini');
  if (route.canPay && route.wallet) {
    const models = [...(gemini?.models || []), ...route.sources.filter(s => s.paid).map(s => s.model)];
    const inputTokens = Math.ceil(messages.reduce((n, m) => n + m.content.length, 0) / 3);
    reserved = worstCase(env, models, inputTokens, 0, maxTokens * 2);
    if (!await reserve(env, route.wallet, reserved)) {
      reserved = 0;
      route.canPay = false;
      if (gemini) gemini.models = list(env.BUDGET_MODELS || 'gemma-4-31b-it');
    }
  }
  const counted = (model, usage) => { actual += costOf(env, model, usage); };
  for (const source of route.sources) {
    // a paid host (Baichuan on Novita) only while Pro money covers it
    if (source.paid && !route.canPay) continue;
    if (source.kind === 'gemini') result = await askGemini(env, messages, maxTokens, temperature, fetcher, source.models, counted);
    else if (source.kind === 'workers-ai') result = await askWorkersAI(env, messages, maxTokens, temperature, source.model);
    else {
      result = await askOpenAI(source, messages, maxTokens, temperature, fetcher);
      if (result.usage) counted(source.model, result.usage);
    }
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
  // a bookkeeping failure never costs the student their answer
  if (reserved) await settle(env, route.wallet, reserved, actual).catch(e => console.error('settle', e));
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

async function askGemini(env, messages, maxTokens, temperature, fetcher, chosen, onUsage) {
  const models = chosen?.length ? chosen : list(env.CLOUD_MODELS || FREE_MODELS);
  return generate(env, models, model => geminiBody(messages, maxTokens, temperature, model), fetcher, { onUsage });
}

/// One Gemini request, trying each model in turn while the answer is "busy",
/// "out of quota" or "not offered".
async function generate(env, models, bodyFor, fetcher, { onUsage = () => {}, rounds = 2 } = {}) {
  let last = { ok: false, status: 503, detail: 'No Gemini model is set up.' };
  const appCheck = await appCheckToken(env, fetcher);
  // the free tier counts requests per minute: when every model says "too
  // many", wait as long as Google asks (up to 30 s) and go round once more
  for (let round = 0; round < rounds; round++) {
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
      // billed whether or not the answer is usable (cut off, blocked, all thought)
      if (answer?.usageMetadata) onUsage(model, answer.usageMetadata);
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

const FREE_MODELS = 'gemini-3.1-pro-preview,gemini-3.5-flash,gemini-3.5-flash-lite,gemma-4-31b-it';
/// Models that cost money from the first request (no free allowance): before
/// Pro pays (PRO_PAYS off) only the owner's own key may use them, so turning
/// billing on for a test cannot bill every student's request with no cap.
const PAID_ONLY = 'gemini-3.1-pro-preview';
/// The accuracy checker's preference: 3.5 Flash, then 3.1 Pro (when the
/// writer was Flash), then the smaller ones.
const CHECKER_MODELS = 'gemini-3.5-flash,gemini-3.1-pro-preview,gemini-3.5-flash-lite,gemma-4-31b-it';
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

const finite = (value, fallback) => {
  const n = Number(value);
  return value !== undefined && value !== '' && Number.isFinite(n) ? n : fallback;
};

export async function budget(env) {
  const net = finite(env.PRO_NET_MONTHLY_USD, 0);
  const share = finite(env.COST_SHARE, 0.6);
  // every monthly bill by name ("github-actions:4,apple-developer:8.25"), so a
  // new cost is one more entry rather than a code change
  const bills = Object.fromEntries(list(env.MONTHLY_BILLS || '').map(b => b.split(':')).map(([k, v]) => [k, finite(v, 0)]));
  const fixed = Object.values(bills).reduce((a, b) => a + b, 0) + finite(env.FIXED_MONTHLY_USD, 0);
  let subscribers = 0, spent = 0;
  try {
    // test (sandbox) purchases unlock Pro for testing but bring in no money
    subscribers = (await env.DB.prepare(
      "SELECT COUNT(*) AS n FROM accounts WHERE verified_until > ? AND COALESCE(apple_env, 'Production') = 'Production'")
      .bind(now()).first())?.n || 0;
  } catch {
    try { subscribers = (await env.DB.prepare('SELECT COUNT(*) AS n FROM accounts WHERE verified_until > ?').bind(now()).first())?.n || 0; } catch { /* no table */ }
  }
  try {
    // the "tx:" rows repeat the account rows under the subscription, for the
    // per-account limit; counting both would double the month's spend
    spent = ((await env.DB.prepare("SELECT SUM(micro_usd) AS s FROM ai_cost WHERE month = ? AND account_id NOT LIKE 'tx:%'")
      .bind(month()).first())?.s || 0) / 1e6;
  } catch { /* no table yet */ }
  const revenue = subscribers * net;
  const capped = net > 0;
  const forUse = capped ? Math.max(0, revenue * share - fixed) : null;
  const perAccount = finite(env.PRO_MONTHLY_BUDGET_USD, capped ? forUse / Math.max(subscribers, 1) : 0);
  return { subscribers, revenue, bills, fixed, capped, forUse, perAccount, spent };
}

/// Whose money a paid call is: the account, and its App Store subscription
/// too, so deleting the account and signing in again does not start the
/// month's allowance over. The owner's own key is counted and capped as well.
export async function wallet(env, accountId, owner = false) {
  if (!proPays(env)) return null;
  const money = await budget(env);
  if (owner) return { keys: ['owner'], cap: finite(env.OWNER_MONTHLY_USD, 20), money };
  let tx = null;
  try {
    tx = (await env.DB.prepare('SELECT original_transaction_id AS t FROM accounts WHERE id = ?').bind(accountId).first())?.t || null;
  } catch { /* no column yet */ }
  return { keys: [accountId, ...(tx ? [`tx:${tx}`] : [])], cap: money.perAccount, money };
}

async function spentBy(env, key) {
  try {
    return ((await env.DB.prepare('SELECT micro_usd FROM ai_cost WHERE account_id = ? AND month = ?')
      .bind(key, month()).first())?.micro_usd || 0) / 1e6;
  } catch { return 0; }
}

export async function canPay(env, accountId, owner = false, known) {
  const payer = known === undefined ? await wallet(env, accountId, owner) : known;
  if (!payer || payer.cap <= 0) return false;
  // everyone together within what Pro brings in (once the price is set)
  if (!owner && payer.money.capped && payer.money.spent >= payer.money.forUse) return false;
  for (const key of payer.keys) if (await spentBy(env, key) >= payer.cap) return false;
  return true;
}

/// Holds `micro` back from every key of the wallet, all or none, and only
/// while each stays within its cap - one statement per key, so two requests
/// at once cannot both take the last of it.
export async function reserve(env, payer, micro) {
  if (!payer || micro <= 0) return true;
  const cap = Math.floor(payer.cap * 1e6);
  const taken = [];
  for (const key of payer.keys) {
    await env.DB.prepare('INSERT OR IGNORE INTO ai_cost (account_id, month, micro_usd) VALUES (?, ?, 0)').bind(key, month()).run();
    const done = await env.DB.prepare(
      'UPDATE ai_cost SET micro_usd = micro_usd + ? WHERE account_id = ? AND month = ? AND micro_usd + ? <= ?')
      .bind(micro, key, month(), micro, cap).run();
    if ((done.meta?.changes ?? 0) === 0) {
      for (const k of taken) await adjust(env, k, -micro);
      return false;
    }
    taken.push(key);
  }
  return true;
}

async function adjust(env, key, micro) {
  if (!micro) return;
  await env.DB.prepare('UPDATE ai_cost SET micro_usd = MAX(0, micro_usd + ?) WHERE account_id = ? AND month = ?')
    .bind(micro, key, month()).run();
}

/// Replaces what was held back with what was actually counted.
export async function settle(env, payer, reserved, actual) {
  if (!payer) return;
  for (const key of payer.keys) await adjust(env, key, Math.ceil(actual) - reserved);
}

export async function geminiModels(env, accountId, owner = false, purpose = 'modes', paying) {
  const audio = purpose === 'transcribe';
  if (!proPays(env)) {
    const chain = list(audio ? env.TRANSCRIBE_MODELS || TRANSCRIBE_MODELS : env.CLOUD_MODELS || FREE_MODELS);
    if (owner) return chain;
    const paidOnly = new Set(list(env.PAID_ONLY_MODELS || PAID_ONLY));
    return chain.filter(m => !paidOnly.has(m));
  }
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

/// One response's cost in millionths of a dollar, from its token counts.
/// Thinking is billed as output; audio input has its own, higher price
/// (GEMINI_AUDIO_PRICES, "model:dollars per million").
export function costOf(env, model, usage) {
  if (!usage) return 0;
  const price = priceOf(env, model);
  const input = usage.promptTokenCount ?? usage.prompt_tokens ?? 0;
  const audio = (usage.promptTokensDetails || []).filter(d => d.modality === 'AUDIO').reduce((n, d) => n + (d.tokenCount || 0), 0);
  const out = (usage.candidatesTokenCount ?? usage.completion_tokens ?? 0) + (usage.thoughtsTokenCount || 0);
  return Math.ceil((input - audio) * price.input + audio * audioPriceOf(env, model, price.input) + out * price.output);
}

function audioPriceOf(env, model, fallback) {
  for (const entry of list(env.GEMINI_AUDIO_PRICES || '')) {
    const [name, rate] = entry.split(':');
    if (name === model) return finite(rate, fallback);
  }
  return fallback;
}

/// The most a call could cost on any of these models.
export function worstCase(env, models, inputTokens, audioTokens, outputTokens) {
  const usage = { promptTokenCount: inputTokens + audioTokens, candidatesTokenCount: outputTokens,
                  promptTokensDetails: [{ modality: 'AUDIO', tokenCount: audioTokens }] };
  return Math.max(0, ...models.map(m => costOf(env, m, usage)));
}

/// Adds a cost to a wallet's month outright (no reservation).
export async function charge(env, accountId, model, usage) {
  if (!proPays(env) || !usage || !accountId) return;
  const micro = costOf(env, model, usage);
  if (!micro) return;
  await env.DB.prepare(
    `INSERT INTO ai_cost (account_id, month, micro_usd) VALUES (?, ?, ?)
     ON CONFLICT (account_id, month) DO UPDATE SET micro_usd = micro_usd + excluded.micro_usd`)
    .bind(accountId, month(), micro).run();
}

/// Cloudflare Workers AI, on the account's free daily allowance.
async function askWorkersAI(env, messages, maxTokens, temperature, pinned) {
  const model = pinned || env.FALLBACK_MODEL || '@cf/nvidia/nemotron-3-120b-a12b';
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
  if (owners.includes(account.id) || account.owner === 1) return true;
  if ((account.verified_until || 0) > now() && now() - (account.checked_at || 0) < RECHECK_SECONDS) return true;
  if (!account.original_transaction_id) return false;
  const apple = await askApple(env, account.original_transaction_id, fetcher);
  if (apple === null) return (account.verified_until || 0) > now();
  const until = await ownsIt(apple, account.id) ? apple.until : 0;
  await env.DB.prepare('UPDATE accounts SET verified_until = ?, checked_at = ? WHERE id = ?')
    .bind(until, now(), account.id).run();
  await recordEnvironment(env, account.id, apple.environment);
  return until > now();
}

/// The appAccountToken the app puts on every purchase for this account: the
/// first 16 bytes of SHA-256("vignette-account:" + id), as a UUID. Apple keeps
/// it inside the signed transaction, so a subscription can only be linked by
/// the account that bought it - a transaction id alone, which anyone with a
/// receipt can read, is not enough.
export async function accountToken(accountId) {
  const digest = new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(`vignette-account:${accountId}`)));
  const hex = [...digest.slice(0, 16)].map(b => b.toString(16).padStart(2, '0')).join('');
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20, 32)}`;
}

async function ownsIt(apple, accountId) {
  const mine = await accountToken(accountId);
  return apple.tokens.some(t => String(t).toLowerCase() === mine);
}

async function recordEnvironment(env, accountId, environment) {
  if (!environment) return;
  try {
    await env.DB.prepare('UPDATE accounts SET apple_env = ? WHERE id = ?').bind(environment, accountId).run();
  } catch { /* column added by the next deploy */ }
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
  const apple = await askApple(env, original, fetcher);
  if (apple === null) return fail(503, "Apple couldn't be reached to confirm the subscription. Try again in a minute.");
  if (apple.until > now() && !await ownsIt(apple, accountId)) {
    return fail(403, 'This subscription was bought while signed in to a different Vignette account. Sign in with that account to use it.');
  }
  try {
    await env.DB.prepare(
      'UPDATE accounts SET original_transaction_id = ?, verified_until = ?, checked_at = ? WHERE id = ?')
      .bind(original, apple.until, now(), accountId).run();
  } catch {
    // the unique index: another account linked it a moment ago
    return fail(409, 'This subscription is already linked to another Vignette account.');
  }
  await recordEnvironment(env, accountId, apple.environment);
  return json({ ok: true, pro: apple.until > now() });
}

/// Until when Apple says this subscription is live: its expiry while active
/// or in billing grace, otherwise 0. Asked of the App Store Server API over
/// TLS, so the answer is Apple's own; production first, then the sandbox that
/// TestFlight purchases live in.
export async function askApple(env, originalTransactionId, fetcher = fetch) {
  const none = { until: 0, tokens: [], environment: null };
  if (!env.ASC_KEY_ID || !env.ASC_ISSUER_ID || !env.ASC_PRIVATE_KEY) return none;
  // a network failure, a key that will not import or a garbled answer says
  // nothing about the subscription either: null, like Apple being down
  try {
    const token = await appStoreToken(env);
    for (const host of ['https://api.storekit.itunes.apple.com', 'https://api.storekit-sandbox.itunes.apple.com']) {
      const response = await fetcher(`${host}/inApps/v1/subscriptions/${originalTransactionId}`, {
        headers: { authorization: `Bearer ${token}` },
      });
      if (response.status === 404) continue;
      // Apple busy or down: the last answer we had stands
      if (!response.ok) return null;
      const answer = await response.json();
      if (answer.bundleId && answer.bundleId !== env.APPLE_BUNDLE_ID) return none;
      let until = 0;
      const tokens = [];
      for (const group of answer.data || []) {
        for (const last of group.lastTransactions || []) {
          // 1 active, 4 billing grace period - both still entitled
          if (last.status !== 1 && last.status !== 4) continue;
          const info = decodeClaims(last.signedTransactionInfo || '') || {};
          const expires = Math.floor((info.expiresDate || 0) / 1000);
          // grace has no new expiry yet; a day at a time until Apple decides
          until = Math.max(until, last.status === 4 ? now() + 86_400 : expires);
          if (info.appAccountToken) tokens.push(info.appAccountToken);
        }
      }
      return { until, tokens, environment: answer.environment || (host.includes('sandbox') ? 'Sandbox' : 'Production') };
    }
    return none;
  } catch (error) {
    console.error('apple', error);
    return null;
  }
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
