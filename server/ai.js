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
// Hugging Face's router has one live host for Baichuan-M2 (Featherless);
// without naming it, the router answers "not supported by any provider you
// have enabled" unless that host is switched on in the account's settings
const DEFAULT_MODEL = 'baichuan-inc/Baichuan-M2-32B:featherless-ai';
const DEFAULT_DAILY_LIMIT = 400;
const MAX_PROMPT_CHARS = 60_000;
const MAX_TOKENS = 2_000;
/// How long one upstream call may take before the next source is tried: a
/// provider that accepts the connection and never answers would otherwise
/// hold the request (and a background job's alarm) until the platform kills it.
const UPSTREAM_TIMEOUT_MS = 120_000;
const AUDIO_TIMEOUT_MS = 240_000;
/// How long a confirmed subscription is trusted before Apple is asked again.
const RECHECK_SECONDS = 6 * 60 * 60;

const json = (body, status = 200) => new Response(JSON.stringify(body), {
  status, headers: { 'content-type': 'application/json' },
});
const fail = (status, message) => json({ error: { message }, message }, status);
const now = () => Math.floor(Date.now() / 1000);
const today = () => new Date().toISOString().slice(0, 10);

/// `maxTokensCap` lets a background job ask for the longer replies it was
/// sized for (jobs.js; never more than 8,000); `rounds: 1` skips waiting out a
/// per-minute limit inside the call (a job tries again on its next alarm);
/// `bench` counts the owner's benchmarks apart from the owner's own app.
export async function chat(env, accountId, body, fetcher = fetch, { owner = false, maxTokensCap, rounds, bench = false } = {}) {
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
  route.account = owner ? 'owner' : accountId;
  route.owner = owner;
  if (rounds) route.rounds = rounds;
  route.wallet = await wallet(env, accountId, owner);
  route.canPay = await canPay(env, accountId, owner, route.wallet);
  const gemini = route.sources?.find(s => s.kind === 'gemini');
  if (gemini) gemini.models = await geminiModels(env, accountId, owner, 'modes', route.canPay);
  // The checker is a different model from the writer: a model grading its
  // own work tends to agree with itself. 3.5 Flash checks first (fast, and
  // not the 3.1 Pro that writes); `avoid` names the models that wrote what
  // is being checked, and they are skipped while any other is left.
  if (gemini && body.model === 'cramdown-checker') gemini.models = checkerOrder(env, gemini.models, body.avoid);
  // A request can ask for one model first (the syllabus check asks for 3.1
  // Pro); only among the models this account may use, so it grants nothing.
  if (gemini && typeof body.prefer === 'string' && gemini.models.includes(body.prefer)) {
    gemini.models = [body.prefer, ...gemini.models.filter(m => m !== body.prefer)];
  }
  // The owner's benchmarks: one named model and nothing else, so models can
  // be compared ("gemini:gemini-3.5-flash", "workers-ai:@cf/...", "hf:org/model").
  if (owner && typeof body.use === 'string') {
    const pinned = pinnedSource(env, body.use);
    if (!pinned) return fail(400, 'That model is not available on this server.');
    route.sources = [pinned];
  }

  // the owner's own builds get a much higher allowance, but still one: a
  // leaked owner key cannot spend without end. The benchmarks have one of
  // their own, so a long run can never leave the owner's app without cloud
  // for the rest of the day.
  const limit = bench ? Number(env.OWNER_BENCH_DAILY_LIMIT) || 2500
    : owner ? Number(env.OWNER_DAILY_LIMIT) || 3000 : Number(env.AI_DAILY_LIMIT) || DEFAULT_DAILY_LIMIT;
  if (!await spend(env, bench ? 'owner-bench' : owner ? 'owner' : accountId, limit)) {
    const message = `That's today's ${limit} cloud requests used. On-device models still work, and the allowance resets at midnight UTC.`;
    // `limit: "day"` says which kind of limit, so a client need not read the words
    return json({ error: { message }, message, limit: 'day' }, 429);
  }

  const cap = Math.min(Number(maxTokensCap) || MAX_TOKENS, 8_000);
  const maxTokens = Math.min(Math.max(Number(body.max_tokens) || 800, 16), cap);
  const temperature = Math.min(Math.max(Number(body.temperature ?? 0.7), 0), 1.5);

  // The checker is shown current evidence from official sources as well as
  // the lecture (see evidence.js), so an outdated or wrong claim is caught
  // even when the lecture says it too.
  let sent = messages;
  let evidence = [];
  const last = messages[messages.length - 1]?.content || '';
  // The owner's checker comparison asks for the model's own judgement
  // (ground: false); everyone else's checks are always grounded.
  const checked = body.model === 'cramdown-checker' && !(owner && body.ground === false) && medvalParts(last);
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

/// One named free model, for the accuracy engine's votes (accuracy.js):
/// "gemini:<model>" or "workers-ai:<model>" only - never a paid host - and a
/// Gemini model only when this account may use it right now (geminiModels:
/// the free chain, or Gemma alone once over a Pro budget). Every free limit
/// still applies: the account's share of scarce Gemini models (freeShare),
/// the day's Gemini ceiling, and the Workers AI neuron shares (takeNeurons).
/// One round: a per-minute limit is the next voter's turn, not a wait.
export async function askModel(env, account, owner, use, messages, maxTokens, fetcher = fetch) {
  if (!/^(gemini|workers-ai):/.test(use)) return { ok: false, status: 400, detail: 'Only free models vote.' };
  const source = pinnedSource(env, use);
  if (!source) return { ok: false, status: 503, detail: `${use} is not set up here.` };
  const route = { sources: [source], account: owner ? 'owner' : account, owner, rounds: 1 };
  route.wallet = await wallet(env, account, owner);
  route.canPay = await canPay(env, account, owner, route.wallet);
  if (source.kind === 'gemini') {
    const allowed = await geminiModels(env, account, owner, 'modes', route.canPay);
    if (!allowed.includes(source.models[0])) return { ok: false, status: 429, detail: `${use} is not available to this account now.` };
  }
  return complete(env, route, messages, maxTokens, 0, fetcher);
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
  // Gemini counts 32 tokens a second of audio, however it is encoded; the
  // seconds are estimated from the bytes at 12 kbps, the least speech is
  // sent at, so a low-bitrate recording is never under-reserved
  const audioTokens = Math.ceil(audio.length * 0.75 / 1500 * 32);
  let reserved = 0, actual = 0;
  if (paying && payer) {
    reserved = worstCase(env, models, Math.ceil(prompt.length / 3), audioTokens, 16384);
    if (!await reserve(env, payer, reserved)) return fail(429, "This month's cloud transcription is used up. This phone can still transcribe.");
  }
  // one round only: a nine-megabyte upload is not something to repeat on a timer
  const result = await generate(env, models, model => ({
    contents: [{ role: 'user', parts: [{ inlineData: { mimeType: 'audio/mp4', data: audio } }, { text: prompt }] }],
    generationConfig: {
      temperature: 0, maxOutputTokens: 16384, responseMimeType: 'application/json', responseSchema: PHRASES,
      // Gemini 3 thinks by default and the thinking comes out of the same
      // 16,384 tokens (and is billed): writing down what was said needs little
      ...(/^gemini-3/.test(model) ? { thinkingConfig: { thinkingLevel: 'low' } } : {}),
    },
  }), fetcher, { rounds: 1, timeout: AUDIO_TIMEOUT_MS, onUsage: (model, usage) => { actual += costOf(env, model, usage); },
                 allow: await freeShare(env, owner ? 'owner' : accountId, owner) });
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
    if (source.kind === 'gemini') result = await askGemini(env, messages, maxTokens, temperature, fetcher, source.models, counted, route);
    else if (source.kind === 'workers-ai') result = await askWorkersAI(env, messages, maxTokens, temperature, source.model, route.account || 'owner', !!route.owner);
    else {
      result = await askOpenAI(source, messages, maxTokens, temperature, fetcher);
      if (result.usage) counted(source.model, result.usage);
    }
    if (result.ok) { result.source = result.source || source.kind; break; }
    failures.push(`${source.kind} ${result.status}: ${result.detail}`);
    // busy, out of quota, down - or, for Gemini, locked by the Firebase
    // project's App Check: the next source may still answer
    const next = [408, 429, 500, 502, 503, 504].includes(result.status)
      || (source.kind === 'gemini' && [401, 403].includes(result.status))
      // the paid host's key refused or expired (Novita answers a bad key
      // with 403), its credit used up (402) or the model withdrawn (404):
      // the free sources still answer, rather than every request failing
      || (source.paid && [401, 402, 403, 404].includes(result.status));
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
  let upstream;
  try {
    upstream = await fetcher(`${route.base.replace(/\/+$/, '')}/chat/completions`, {
      method: 'POST',
      headers: { 'content-type': 'application/json', authorization: `Bearer ${route.key}` },
      body: JSON.stringify({ model: route.model, messages, max_tokens: maxTokens, temperature, stream: false }),
      signal: timeoutSignal(UPSTREAM_TIMEOUT_MS),
    });
  } catch (error) {
    // timed out or unreachable: "down", so the next source is tried
    return { ok: false, status: 504, detail: `${route.model}: ${String(error?.message || error).slice(0, 200)}` };
  }
  if (!upstream.ok) return { ok: false, status: upstream.status, detail: await readError(upstream) };
  let answer = null;
  try { answer = await upstream.json(); } catch { /* an HTML error page with a 200 */ }
  const content = withoutThinking(answer?.choices?.[0]?.message?.content);
  // billed whether or not the reply is usable
  return content ? { ok: true, content, source: route.model, usage: answer.usage }
    : { ok: false, status: 502, detail: 'The cloud model sent back nothing usable.', usage: answer?.usage };
}

/// The answer without a reasoning model's thinking: everything up to the last
/// `</think>` (QwQ, Doctor-R1 and MedVAL often send no opening tag, because
/// their chat template already opened it), and nothing at all when the reply
/// stopped mid-thought.
export function withoutThinking(raw) {
  if (typeof raw !== 'string') return '';
  const end = raw.lastIndexOf('</think>');
  if (end >= 0) return raw.slice(end + '</think>'.length).trim();
  if (/<think>/.test(raw)) return '';
  return raw.trim();
}

const timeoutSignal = ms => (typeof AbortSignal !== 'undefined' && AbortSignal.timeout ? AbortSignal.timeout(ms) : undefined);

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
  // Gemini 3 thinks by default, and its thinking counts against the same
  // limit: a 200-token call (the checker's search terms) or a 900-token check
  // could come back as nothing but thought - billed, counted against the day's
  // free requests, and empty. So thinking gets room of its own (the reply
  // still stops where it was asked to; the paid reservation already allows
  // twice the tokens asked for), and a short call is asked to think briefly.
  // "low" is a level every Gemini 3 model accepts.
  else if (/^gemini-3/.test(model)) {
    body.generationConfig.maxOutputTokens = maxTokens * 2;
    if (maxTokens <= 1000) body.generationConfig.thinkingConfig = { thinkingLevel: 'low' };
  }
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

async function askGemini(env, messages, maxTokens, temperature, fetcher, chosen, onUsage, route = {}) {
  const models = chosen?.length ? chosen : list(env.CLOUD_MODELS || FREE_MODELS);
  return generate(env, models, model => geminiBody(messages, maxTokens, temperature, model), fetcher,
    { onUsage, rounds: route.rounds || 2, allow: await freeShare(env, route.account, !!route.owner), timeout: UPSTREAM_TIMEOUT_MS });
}

/// One Gemini request, trying each model in turn while the answer is "busy",
/// "out of quota" or "not offered".
async function generate(env, models, bodyFor, fetcher, { onUsage = () => {}, rounds = 2, allow = null, timeout = UPSTREAM_TIMEOUT_MS } = {}) {
  let last = { ok: false, status: 503, detail: 'No Gemini model is set up.' };
  const appCheck = await appCheckToken(env, fetcher);
  // the free tier counts requests per minute: when every model says "too
  // many", wait as long as Google asks (up to 30 s) and go round once more
  for (let round = 0; round < rounds; round++) {
    let wait = 0;
    for (const model of models) {
      // Google already said this model's allowance for the day is gone (3.1
      // Pro's free input-token limit is zero): asking again only costs the
      // student a round trip - and its "retry in 59 s" stopped the second
      // round for the models that were only busy for a minute
      if (await dayOut(env, model)) {
        last = { ok: false, status: 429, detail: `${model}: today's allowance is used (Google said so earlier today).` };
        continue;
      }
      // this account's share of a scarce free allowance is used up, or the
      // day's ceiling on Gemini calls is reached: the next model, as if busy
      if (allow && !await allow(model)) {
        last = { ok: false, status: 429, detail: `${model}: this account's share of today's free requests is used.` };
        continue;
      }
      let response;
      try {
        response = await fetcher(
          `https://firebasevertexai.googleapis.com/v1beta/projects/${env.FIREBASE_PROJECT_ID}/models/${model}:generateContent`, {
            method: 'POST',
            headers: {
              'content-type': 'application/json', 'x-goog-api-key': env.FIREBASE_API_KEY,
              ...(appCheck ? { 'x-firebase-appcheck': appCheck } : {}),
            },
            body: JSON.stringify(bodyFor(model)),
            signal: timeoutSignal(timeout),
          });
      } catch (error) {
        // timed out or unreachable: like "busy", the next model may answer
        last = { ok: false, status: 504, detail: `${model}: ${String(error?.message || error).slice(0, 200)}` };
        continue;
      }
      if (!response.ok) {
        const raw = await response.text();
        last = { ok: false, status: response.status, detail: `${model}: ${errorMessage(raw)}` };
        if (response.status === 429 && dailyQuota(raw)) {
          await markDayOut(env, model);
          continue;
        }
        // "overloaded" comes as a 429 with no delay: a few seconds is enough
        if (response.status === 429) wait = Math.max(wait, retryDelay(raw) || 5);
        // out of quota, overloaded or not offered: the next model may answer
        if ([404, 429, 500, 502, 503, 504].includes(response.status)) continue;
        return last;
      }
      let answer = null;
      try { answer = await response.json(); } catch { /* garbled: treated as empty below */ }
      // billed whether or not the answer is usable (cut off, blocked, all thought)
      if (answer?.usageMetadata) onUsage(model, answer.usageMetadata);
      const parts = answer?.candidates?.[0]?.content?.parts || [];
      const content = parts.filter(p => !p.thought).map(p => p.text || '').join('');
      // A model with no free allowance answered: the Firebase project is
      // billed, so every Gemini call from now on costs money (see billingSeen)
      if (content && paidOnly(env).has(model)) await markBilled(env);
      if (content) return { ok: true, content, source: model, usage: answer.usageMetadata };
      last = { ok: false, status: 502, detail: `${model}: sent back nothing usable.` };
    }
    if (last.status !== 429 || !wait || wait > 30) break;
    await sleep(wait * 1000);
  }
  return last;
}

const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));

/// True when a 429 names a per-day quota ("...PerDay..." in its violations),
/// as opposed to a per-minute one that is gone in a minute.
export function dailyQuota(raw) {
  try {
    const details = JSON.parse(raw)?.error?.details;
    const violations = (Array.isArray(details) ? details : []).flatMap(d => (Array.isArray(d?.violations) ? d.violations : []));
    return violations.some(v => /PerDay/i.test(`${v?.quotaId || ''} ${v?.quotaMetric || ''}`));
  } catch { return false; }
}

/// Models Google has said are out for the day, remembered in ai_usage (so
/// every isolate knows) until midnight UTC, and in memory per database.
const dayOutCache = new WeakMap();
async function dayOut(env, model) {
  const db = env.DB;
  if (!db || typeof db !== 'object') return false;
  const key = `${today()}|${model}`;
  const known = dayOutCache.get(db) || new Map();
  dayOutCache.set(db, known);
  const hit = known.get(key);
  if (hit && (hit.value || hit.until > Date.now())) return hit.value;
  let value = false;
  try {
    value = !!(await db.prepare('SELECT 1 AS x FROM ai_usage WHERE account_id = ? AND day = ?').bind(`gemini-dayout:${model}`, today()).first());
  } catch { /* no table */ }
  known.set(key, { value, until: Date.now() + 60_000 });
  return value;
}

async function markDayOut(env, model) {
  const db = env.DB;
  if (!db || typeof db !== 'object') return;
  try {
    await db.prepare('INSERT OR IGNORE INTO ai_usage (account_id, day, requests) VALUES (?, ?, 1)').bind(`gemini-dayout:${model}`, today()).run();
  } catch { /* no table: the next call just asks again */ }
  const known = dayOutCache.get(db) || new Map();
  known.set(`${today()}|${model}`, { value: true, until: Infinity });
  dayOutCache.set(db, known);
}

function errorMessage(raw) {
  try {
    const parsed = JSON.parse(raw);
    const message = parsed?.error?.message || raw.slice(0, 400);
    const quota = quotaNote(parsed);
    return quota ? `${String(message).slice(0, 160)} ${quota}` : message;
  } catch { return raw.slice(0, 400); }
}

/// Which limit Google says was hit, from the error's details: the quota's
/// name (it says per minute or per day), its value, and how long to wait -
/// "[quota GenerateRequestsPerDayPerProjectPerModel-FreeTier=20; retry 41s]".
/// Google does not publish the free limits; this is where the real numbers are.
export function quotaNote(parsed) {
  const details = Array.isArray(parsed?.error?.details) ? parsed.error.details : [];
  const failure = details.find(d => Array.isArray(d?.violations));
  const retry = details.find(d => typeof d?.retryDelay === 'string')?.retryDelay;
  const parts = (failure?.violations || []).slice(0, 2)
    .map(v => `${v.quotaId || v.quotaMetric || 'quota'}=${v.quotaValue ?? '?'}`);
  if (!parts.length && !retry) return '';
  return `[quota ${parts.join(', ') || '?'}${retry ? `; retry ${retry}` : ''}]`;
}

/// Seconds Google asks to wait before the next request ("retryDelay": "17s").
export function retryDelay(raw) {
  const m = String(raw).match(/"retryDelay"\s*:\s*"(\d+(?:\.\d+)?)s"/);
  return m ? Math.ceil(parseFloat(m[1])) : 0;
}

// MARK: who pays for Gemini

const FREE_MODELS = 'gemini-3.1-pro-preview,gemini-3.5-flash,gemini-3.5-flash-lite,gemma-4-31b-it';
/// Models that cost money from the first request (no free allowance): before
/// Pro pays (PRO_PAYS off) only the owner's own key may use them.
///
/// That alone does not make turning billing on safe: once the Firebase project
/// is on the Blaze plan, Google bills 3.5 Flash and Flash-Lite from the first
/// token too - a billed project has no free tier. So the moment a paid-only
/// model answers, the server knows the project is billed and behaves as
/// GEMINI_BILLING = "on" (see billingSeen): every paid call is then counted
/// against a budget, and with no budget set, students get the free Gemma only.
const PAID_ONLY = 'gemini-3.1-pro-preview';
const paidOnly = env => new Set(list(env.PAID_ONLY_MODELS || PAID_ONLY));
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

/// Whether a paid-only model has ever answered here, which means the Firebase
/// project is billed whatever PRO_PAYS says. Kept in ai_usage under a name no
/// account has, and remembered for a few minutes per database.
const billedCache = new WeakMap();
export async function billingSeen(env) {
  const db = env.DB;
  if (!db || typeof db !== 'object') return false;
  const hit = billedCache.get(db);
  if (hit && (hit.value || hit.until > Date.now())) return hit.value;
  let value = false;
  try {
    value = !!(await db.prepare("SELECT 1 AS x FROM ai_usage WHERE account_id = 'gemini:billed' AND day = 'seen'").first());
  } catch { /* no table */ }
  billedCache.set(db, { value, until: Date.now() + 5 * 60_000 });
  return value;
}

async function markBilled(env) {
  if (!env.DB || billedCache.get(env.DB)?.value) return;
  try {
    await env.DB.prepare("INSERT OR IGNORE INTO ai_usage (account_id, day, requests) VALUES ('gemini:billed', 'seen', 1)").run();
    billedCache.set(env.DB, { value: true, until: Infinity });
    console.error('gemini: a paid-only model answered - the project is billed; paid calls are now budgeted');
  } catch (error) { console.error('billing flag', error); }
}

/// Paid calls are counted and capped: Pro pays, or the project is billed.
export async function paysNow(env) {
  return proPays(env) || await billingSeen(env);
}

/// Before paid calls are budgeted, Google's free allowances are shared by
/// everyone, and some are tiny (3.5 Flash about 20 requests a day for the
/// whole project). So each account may take only a share of the scarce ones
/// (FREE_MODEL_SHARES, "model:requests a day"), and all accounts together at
/// most GEMINI_DAILY_CEILING non-Gemma calls a day - a ceiling that also caps
/// what a billing change nobody told the server about could ever cost.
/// Returns the check for generate(), or null when nothing is limited.
const FREE_MODEL_SHARES = 'gemini-3.5-flash:4,gemini-3.5-flash-lite:100';
async function freeShare(env, account, owner) {
  if (await paysNow(env)) return null;
  const shares = Object.fromEntries(list(env.FREE_MODEL_SHARES ?? FREE_MODEL_SHARES)
    .map(e => e.split(':')).map(([m, n]) => [m, finite(n, Infinity)]));
  const ceiling = finite(env.GEMINI_DAILY_CEILING, 1000);
  return async model => {
    if (model.startsWith('gemma')) return true;
    if (!owner && account && Number.isFinite(shares[model]) && !await spend(env, `free:${model}:${account}`, shares[model])) return false;
    return spend(env, 'gemini:all', ceiling);
  };
}

const finite = (value, fallback) => {
  const n = Number(value);
  return value !== undefined && value !== '' && Number.isFinite(n) ? n : fallback;
};

/// Pro revenue and spend are read at most once a minute per database: they
/// are a whole-table count and a month's sum, and every paid call asks. The
/// per-account caps are still checked, and reserved atomically, on every call.
const budgetCache = new WeakMap();
export async function budget(env, { fresh = false } = {}) {
  const db = env.DB;
  const sig = [env.PRO_NET_MONTHLY_USD, env.COST_SHARE, env.MONTHLY_BILLS, env.FIXED_MONTHLY_USD, env.PRO_MONTHLY_BUDGET_USD].join('|');
  const hit = db && typeof db === 'object' ? budgetCache.get(db) : null;
  if (!fresh && hit && hit.sig === sig && hit.until > Date.now()) return hit.value;
  const value = await countBudget(env);
  if (db && typeof db === 'object') budgetCache.set(db, { sig, value, until: Date.now() + 60_000 });
  return value;
}

async function countBudget(env) {
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
  if (!await paysNow(env)) return null;
  const money = await budget(env);
  if (owner) return { keys: ['owner'], cap: finite(env.OWNER_MONTHLY_USD, 20), money };
  let tx = null, sandbox = false;
  try {
    const row = await env.DB.prepare('SELECT original_transaction_id AS t, apple_env AS e FROM accounts WHERE id = ?').bind(accountId).first();
    tx = row?.t || null;
    sandbox = row?.e === 'Sandbox';
  } catch { /* no column yet */ }
  // A test (sandbox) purchase unlocks Pro for testing, but it is free and
  // brings in nothing: it gets the free models, never a paying subscriber's
  // share of what Pro revenue pays for.
  return { keys: [accountId, ...(tx ? [`tx:${tx}`] : [])], cap: sandbox ? 0 : money.perAccount, money };
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
  if (!await paysNow(env)) {
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

/// Google prices audio input well above text (2.5 Flash: $1.00 against
/// $0.30 a million). Used when GEMINI_AUDIO_PRICES does not name the model;
/// a model named nowhere is taken at three times its text price, never at
/// the text price itself, so transcription is never under-counted.
const DEFAULT_AUDIO_PRICES = 'gemini-3.5-flash:1.00,gemini-3.5-flash-lite:0.30';
function audioPriceOf(env, model, text) {
  const triple = Math.round(text * 3e6) / 1e6; // three times the text price, without float dust
  for (const source of [env.GEMINI_AUDIO_PRICES || '', DEFAULT_AUDIO_PRICES]) {
    for (const entry of list(source)) {
      const [name, rate] = entry.split(':');
      if (name === model) return finite(rate, triple);
    }
  }
  return triple;
}

/// The most a call could cost on any of these models.
export function worstCase(env, models, inputTokens, audioTokens, outputTokens) {
  const usage = { promptTokenCount: inputTokens + audioTokens, candidatesTokenCount: outputTokens,
                  promptTokensDetails: [{ modality: 'AUDIO', tokenCount: audioTokens }] };
  return Math.max(0, ...models.map(m => costOf(env, m, usage)));
}

/// Adds a cost to a wallet's month outright (no reservation).
export async function charge(env, accountId, model, usage) {
  if (!usage || !accountId || !await paysNow(env)) return;
  const micro = costOf(env, model, usage);
  if (!micro) return;
  await env.DB.prepare(
    `INSERT INTO ai_cost (account_id, month, micro_usd) VALUES (?, ?, ?)
     ON CONFLICT (account_id, month) DO UPDATE SET micro_usd = micro_usd + excluded.micro_usd`)
    .bind(accountId, month(), micro).run();
}

// MARK: Cloudflare's free neurons

/// Workers AI's free 10,000 "neurons" a day are one pool for the whole
/// Cloudflare account: the natural voice (tts.js) and the text fallback below
/// both draw on it, and once it is gone both fail for everyone until midnight
/// UTC. So every call takes an estimate of its neurons first, from a daily
/// pool kept a little under the real one (WORKERS_AI_DAILY_NEURONS) and from
/// the account's share of it (WORKERS_AI_NEURONS_PER_ACCOUNT) - one account
/// cannot spend the day for everybody.
const DAILY_NEURONS = 9000;
const NEURONS_PER_ACCOUNT = 4500;
/// Neurons per million tokens, [input, output], from Cloudflare's price list.
const NEURON_RATES = {
  '@cf/nvidia/nemotron-3-120b-a12b': [45455, 136364],
  '@cf/openai/gpt-oss-120b': [31818, 68182],
  '@cf/meta/llama-4-scout-17b-16e-instruct': [24545, 77273],
  '@cf/qwen/qwq-32b': [60000, 90909],
  '@cf/google/gemma-4-26b-a4b-it': [9091, 27273],
};

async function addUp(env, name, n, limit) {
  const result = await env.DB.prepare(
    `INSERT INTO ai_usage (account_id, day, requests) VALUES (?, ?, ?)
     ON CONFLICT (account_id, day) DO UPDATE SET requests = requests + excluded.requests
     WHERE requests + excluded.requests <= ?`)
    .bind(name, today(), n, limit).run();
  return n <= limit && (result.meta?.changes ?? 0) > 0;
}

async function takeBack(env, name, n) {
  await env.DB.prepare('UPDATE ai_usage SET requests = MAX(0, requests - ?) WHERE account_id = ? AND day = ?')
    .bind(n, name, today()).run();
}

/// Takes `n` neurons for `account` (its share, then the day's pool), all or
/// nothing. The owner's key draws on the pool only.
export async function takeNeurons(env, account, n, owner = false) {
  n = Math.max(1, Math.ceil(n));
  const pool = finite(env.WORKERS_AI_DAILY_NEURONS, DAILY_NEURONS);
  const share = finite(env.WORKERS_AI_NEURONS_PER_ACCOUNT, NEURONS_PER_ACCOUNT);
  const mine = owner ? null : `neurons:${account}`;
  if (mine && !await addUp(env, mine, n, share)) return false;
  if (!await addUp(env, 'neurons:all', n, pool)) {
    if (mine) await takeBack(env, mine, n);
    return false;
  }
  return true;
}

/// Gives back neurons taken for a call that produced nothing.
export async function giveNeurons(env, account, n, owner = false) {
  n = Math.max(1, Math.ceil(n));
  await takeBack(env, 'neurons:all', n);
  if (!owner) await takeBack(env, `neurons:${account}`, n);
}

/// The text fallback's input is kept far below the 60,000 characters a
/// request may carry: a full-size prompt costs a tenth of the day's pool.
const WORKERS_AI_MAX_CHARS = 24_000;

/// Cloudflare Workers AI, on the account's free daily allowance.
async function askWorkersAI(env, messages, maxTokens, temperature, pinned, account = 'owner', owner = true) {
  const model = pinned || env.FALLBACK_MODEL || '@cf/nvidia/nemotron-3-120b-a12b';
  const chars = messages.reduce((n, m) => n + m.content.length, 0);
  if (chars > finite(env.WORKERS_AI_MAX_CHARS, WORKERS_AI_MAX_CHARS)) {
    return { ok: false, status: 503, detail: 'Too long for the free fallback model.' };
  }
  const [rateIn, rateOut] = NEURON_RATES[model] || NEURON_RATES['@cf/nvidia/nemotron-3-120b-a12b'];
  const neurons = (chars / 4) * rateIn / 1e6 + maxTokens * rateOut / 1e6;
  if (!await takeNeurons(env, account, neurons, owner)) {
    return { ok: false, status: 429, detail: "Workers AI: this account's share of today's free allowance is used." };
  }
  try {
    const out = await env.AI.run(model, workersInput(model, messages, maxTokens, temperature));
    // what was taken assumed the whole max_tokens came back; when the model
    // says what it used, the rest goes back to the pool, or the day's
    // allowance runs out at a fraction of what was really spent
    const spent = usedNeurons(out?.usage, rateIn, rateOut);
    const back = spent === null ? 0 : Math.floor(Math.ceil(neurons) - spent);
    if (back >= 1) await giveNeurons(env, account, back, owner).catch(() => {});
    const content = workersText(out);
    if (content) return { ok: true, content, source: model };
    const why = out?.choices?.[0]?.finish_reason === 'length' ? ' (it ran out of tokens while thinking)' : '';
    return { ok: false, status: 502, detail: `Workers AI sent back nothing usable${why}.` };
  } catch (error) {
    await giveNeurons(env, account, neurons, owner).catch(() => {});
    return { ok: false, status: 503, detail: String(error?.message || error).slice(0, 300) };
  }
}

/// What one Workers AI text model is sent. Gemma 4 thinks before it answers
/// unless told not to, and on Workers AI the thinking comes out of the same
/// max_tokens: a 200- or 900-token call came back with the answer empty
/// (content null, the tokens all in reasoning_content) - "sent back nothing
/// usable", again and again. Cloudflare's own example turns it off this way.
export function workersInput(model, messages, maxTokens, temperature) {
  const input = { messages, max_tokens: maxTokens, temperature };
  if (/gemma-4/.test(model)) input.chat_template_kwargs = { enable_thinking: false };
  return input;
}

/// The reply text, whichever shape the model answers in: `response` (the
/// older Workers AI models) or OpenAI's `choices[0].message.content` (Gemma 4,
/// gpt-oss, Nemotron), with any thinking left in the text taken out. Never the
/// reasoning_content: that is the model thinking aloud, not its answer.
export function workersText(out) {
  const raw = typeof out?.response === 'string' && out.response ? out.response
    : out?.choices?.[0]?.message?.content ?? out?.choices?.[0]?.text;
  if (raw && typeof raw === 'object') return JSON.stringify(raw);
  return withoutThinking(raw);
}

/// The neurons a Workers AI reply says it used, or null when it says nothing.
export function usedNeurons(usage, rateIn, rateOut) {
  const input = Number(usage?.prompt_tokens ?? usage?.input_tokens);
  const output = Number(usage?.completion_tokens ?? usage?.output_tokens);
  if (!Number.isFinite(input) || !Number.isFinite(output) || input < 0 || output < 0) return null;
  return input * rateIn / 1e6 + output * rateOut / 1e6;
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
  const until = (await mayUse(env, apple, account)).ok ? apple.until : 0;
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

/// Whether this account may use a subscription Apple describes: it bought it
/// (its own tag is on it), or every tag on it belongs to an account that was
/// deleted and was signed in with this same Apple or Google account - the
/// same person, back after deleting their account, whose new account id can
/// never match the tag on what they bought. A transaction id alone still
/// proves nothing; a tag released by somebody else's sign-in does not count.
async function mayUse(env, apple, account) {
  if (await ownsIt(apple, account.id)) return { ok: true };
  if (!apple.tokens.length || !account.provider || account.provider === 'device') return { ok: false };
  for (const token of new Set(apple.tokens.map(t => String(t).toLowerCase()))) {
    let row = null;
    try {
      row = await env.DB.prepare('SELECT provider, subject FROM released_tokens WHERE token = ?').bind(token).first();
    } catch { return { ok: false }; }
    if (!row || row.provider !== account.provider || row.subject !== account.subject) return { ok: false };
  }
  return { ok: true, retag: true };
}

/// Puts this account's tag on the purchase with Apple (the App Store Server
/// API's Set App Account Token), so later checks match it directly. Best
/// effort: released_tokens still vouches for it if Apple refuses.
async function retag(env, originalTransactionId, accountId, environment, fetcher = fetch) {
  try {
    const host = environment === 'Sandbox' ? 'https://api.storekit-sandbox.itunes.apple.com' : 'https://api.storekit.itunes.apple.com';
    const response = await fetcher(`${host}/inApps/v1/transactions/${originalTransactionId}/appAccountToken`, {
      method: 'PUT',
      headers: { authorization: `Bearer ${await appStoreToken(env)}`, 'content-type': 'application/json' },
      body: JSON.stringify({ appAccountToken: await accountToken(accountId) }),
    });
    if (!response.ok) console.error('apple retag', response.status);
  } catch (error) { console.error('apple retag', error); }
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
  const account = await env.DB.prepare('SELECT * FROM accounts WHERE id = ?').bind(accountId).first();
  if (!account) return fail(401, 'Please sign in again.');
  // Already linked here and confirmed within the last few hours: that answer
  // stands, and Apple is not asked again (the app reports its plan often).
  if (account.original_transaction_id === original && now() - (account.checked_at || 0) < RECHECK_SECONDS) {
    return json({ ok: true, pro: (account.verified_until || 0) > now() });
  }
  // one subscription unlocks one account: a transaction id is not a secret
  // (it is in every receipt), so without this anyone given one gets Pro
  const holder = await env.DB.prepare('SELECT id FROM accounts WHERE original_transaction_id = ? AND id != ?')
    .bind(original, accountId).first();
  if (holder) return fail(409, 'This subscription is already linked to another Vignette account. Sign in with that account, or contact support to move it.');
  const apple = await askApple(env, original, fetcher);
  if (apple === null) return fail(503, "Apple couldn't be reached to confirm the subscription. Try again in a minute.");
  // checked whenever Apple names an owner, live or lapsed: otherwise anyone
  // holding a lapsed subscription's id could link it first and lock its real
  // owner out when they renew
  const allowed = await mayUse(env, apple, account);
  if ((apple.until > now() || apple.tokens.length) && !allowed.ok) {
    return fail(403, 'This subscription was bought while signed in to a different Vignette account. Sign in with that account to use it.');
  }
  if (allowed.retag) await retag(env, original, accountId, apple.environment, fetcher);
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
          const info = decodeClaims(last.signedTransactionInfo || '') || {};
          // whose it is, whatever its state: a lapsed subscription still
          // belongs to the account that bought it
          if (info.appAccountToken) tokens.push(info.appAccountToken);
          // 1 active, 4 billing grace period - both still entitled
          if (last.status !== 1 && last.status !== 4) continue;
          const expires = Math.floor((info.expiresDate || 0) / 1000);
          // grace has no new expiry yet; a day at a time until Apple decides
          until = Math.max(until, last.status === 4 ? now() + 86_400 : expires);
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
