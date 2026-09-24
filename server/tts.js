// Reading text aloud in a human-sounding voice, for Pro.
//
// The phone's own voices sound like a machine reading a list. Deepgram's
// Aura-2 on Cloudflare Workers AI sounds like a person: it paces a sentence
// the way a speaker would, with natural pauses and emphasis. It is not free,
// though - $0.03 per 1,000 characters, taken out of the same 10,000 free
// "neurons" a day that the text models fall back on - so it is rationed:
//
//   1. Every line is kept in R2 (env.BLOBS) under a hash of the voice and the
//      words, so a card read a second time, by anyone, costs nothing.
//   2. Aura-2 is used within a small shared number of characters a day
//      (TTS_FREE_DAILY_CHARS), which keeps it inside the free allowance.
//   3. Past that, only once Pro pays for things (PRO_PAYS = "on"), a Pro
//      account may carry on with Aura-2 out of its monthly budget, counted
//      like every other paid call (see budget() in ai.js).
//   4. Otherwise MeloTTS, which costs about a fiftieth of a cent an hour of
//      speech, so it is in effect free. It has one voice only.
//   5. If Workers AI refuses altogether (the day's allowance is gone), the
//      answer is 503 and the phone reads the line with its own voice.
//
// Each account may ask for TTS_DAILY_LIMIT lines a day (300 by default) of
// at most 1,500 characters each; the app splits longer text into sentences.
import { proGate, spend, wallet, canPay, reserve, settle, proPays } from './ai.js';

export const MAX_TTS_CHARS = 1500;
const DEFAULT_DAILY_LIMIT = 300;
const DEFAULT_FREE_CHARS = 2500;
export const AURA = '@cf/deepgram/aura-2-en';
export const MELO = '@cf/myshell-ai/melotts';
// Aura-2's price, in millionths of a dollar per character ($0.03 per 1,000)
const AURA_MICRO_PER_CHAR = 30;

/// Who says what. Both British, one of each sex, so a student with the phone
/// in a pocket can tell the examiner from the patient at once. Deepgram
/// describes Pandora as "smooth, calm, melodic" and Draco as "warm,
/// approachable, trustworthy, baritone".
const DEFAULT_VOICES = { narrator: 'pandora', patient: 'draco' };

const json = (body, status = 200) => new Response(JSON.stringify(body), {
  status, headers: { 'content-type': 'application/json' },
});
const fail = (status, message) => json({ error: { message }, message }, status);
const today = () => new Date().toISOString().slice(0, 10);

/// The speaker Aura-2 is asked for, for one of the app's two roles.
/// TTS_VOICES can change them without a code change ("narrator:thalia,...").
export function voiceFor(env, role) {
  const chosen = { ...DEFAULT_VOICES };
  for (const pair of String(env.TTS_VOICES || '').split(',')) {
    const [name, speaker] = pair.split(':').map(s => (s || '').trim());
    if (name in chosen && /^[a-z]+$/.test(speaker || '')) chosen[name] = speaker;
  }
  return chosen[role] || null;
}

/// Spaces tidied, so "Hello  world" and "Hello world" share one cached file.
export function tidy(text) {
  return typeof text === 'string' ? text.replace(/\s+/g, ' ').trim() : '';
}

/// The name a line is cached under: which model, which speaker, which words.
export async function cacheKey(model, speaker, text) {
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(`${model}|${speaker}|${text}`));
  const hex = [...new Uint8Array(digest)].map(b => b.toString(16).padStart(2, '0')).join('');
  return `tts/${hex}.mp3`;
}

/// Takes `chars` from today's shared Aura-2 allowance, all or nothing. The
/// check and the addition are one statement, so two requests at once cannot
/// both take the last of it. Kept in ai_usage under a name no account has.
export async function takeFreeChars(env, chars) {
  const limit = Number(env.TTS_FREE_DAILY_CHARS ?? DEFAULT_FREE_CHARS);
  if (!Number.isFinite(limit) || chars > limit) return false;
  const result = await env.DB.prepare(
    `INSERT INTO ai_usage (account_id, day, requests) VALUES ('tts-chars:all', ?, ?)
     ON CONFLICT (account_id, day) DO UPDATE SET requests = requests + excluded.requests
     WHERE requests + excluded.requests <= ?`)
    .bind(today(), chars, limit).run();
  return (result.meta?.changes ?? 0) > 0;
}

/// Whatever the Workers AI binding hands back, as bytes: Aura-2 sends a
/// stream, MeloTTS either raw bytes or JSON with the MP3 in base64.
export async function audioBytes(out) {
  if (!out) return null;
  if (out instanceof ArrayBuffer) return new Uint8Array(out);
  if (ArrayBuffer.isView(out)) return new Uint8Array(out.buffer, out.byteOffset, out.byteLength);
  if (out instanceof Response) return new Uint8Array(await out.arrayBuffer());
  if (typeof out.getReader === 'function') return new Uint8Array(await new Response(out).arrayBuffer());
  if (typeof out.audio === 'string') {
    const raw = atob(out.audio);
    const bytes = new Uint8Array(raw.length);
    for (let i = 0; i < raw.length; i++) bytes[i] = raw.charCodeAt(i);
    return bytes;
  }
  return null;
}

/// Asks one model for one line. Null when it failed or sent nothing usable.
async function synthesise(env, model, speaker, text) {
  try {
    const input = model === MELO ? { prompt: text, lang: 'en' } : { text, speaker, encoding: 'mp3' };
    const bytes = await audioBytes(await env.AI.run(model, input));
    // a real line of speech is kilobytes; a few bytes is an error message
    return bytes && bytes.byteLength > 256 ? bytes : null;
  } catch (error) {
    console.error('tts', model, String(error?.message || error).slice(0, 300));
    return null;
  }
}

async function cached(env, key) {
  if (!env.BLOBS) return null;
  try {
    const object = await env.BLOBS.get(key);
    return object ? new Uint8Array(await object.arrayBuffer()) : null;
  } catch { return null; }
}

async function keep(env, key, bytes) {
  if (!env.BLOBS) return;
  try {
    await env.BLOBS.put(key, bytes, { httpMetadata: { contentType: 'audio/mpeg' } });
  } catch (error) { console.error('tts cache', error); }
}

const audio = (bytes, model, cache) => new Response(bytes, {
  status: 200,
  headers: {
    'content-type': 'audio/mpeg',
    // which voice it was, so the app can tell; never anything about cost
    'x-voice-model': model === MELO ? 'melotts' : 'aura-2',
    'x-voice-cache': cache ? 'hit' : 'miss',
  },
});

/// POST /tts {text, voice: "narrator" | "patient"} -> MP3 bytes.
export async function speech(env, accountId, body, fetcher = fetch, { owner = false } = {}) {
  if (!env.AI) return fail(503, "Natural voices aren't set up on this server.");
  if (!owner) {
    const refused = await proGate(env, accountId, fetcher, 'The natural voice is part of Pro.');
    if (refused) return refused;
  }
  const text = tidy(body?.text);
  if (!text) return fail(400, 'Nothing to read.');
  if (text.length > MAX_TTS_CHARS) return fail(413, `At most ${MAX_TTS_CHARS} characters at a time.`);
  const role = body?.voice === 'patient' ? 'patient' : 'narrator';
  const speaker = voiceFor(env, role);

  const limit = owner ? Number(env.OWNER_TTS_DAILY_LIMIT) || 1000 : Number(env.TTS_DAILY_LIMIT) || DEFAULT_DAILY_LIMIT;
  if (!await spend(env, `tts:${owner ? 'owner' : accountId}`, limit)) {
    return fail(429, `That's today's ${limit} natural-voice lines used. The phone's own voice carries on, and it resets at midnight UTC.`);
  }

  // Aura-2, from the cache, then free, then (once Pro pays) out of the budget
  const auraKey = await cacheKey(AURA, speaker, text);
  const hit = await cached(env, auraKey);
  if (hit) return audio(hit, AURA, true);

  let payer = null, reserved = 0;
  let useAura = await takeFreeChars(env, text.length);
  if (!useAura && proPays(env)) {
    payer = await wallet(env, accountId, owner);
    if (payer && await canPay(env, accountId, owner, payer)) {
      reserved = text.length * AURA_MICRO_PER_CHAR;
      useAura = await reserve(env, payer, reserved);
      if (!useAura) reserved = 0;
    }
  }
  if (useAura) {
    const bytes = await synthesise(env, AURA, speaker, text);
    if (bytes) {
      await keep(env, auraKey, bytes);
      return audio(bytes, AURA, false);
    }
    // nothing came back, so nothing is charged for it
    if (reserved) await settle(env, payer, reserved, 0).catch(e => console.error('settle', e));
  }

  // MeloTTS: one voice for both roles, so the cache ignores the speaker
  const meloKey = await cacheKey(MELO, 'default', text);
  const meloHit = await cached(env, meloKey);
  if (meloHit) return audio(meloHit, MELO, true);
  const melo = await synthesise(env, MELO, 'default', text);
  if (melo) {
    await keep(env, meloKey, melo);
    return audio(melo, MELO, false);
  }
  return fail(503, "The natural voice isn't available right now; the phone's own voice will read instead.");
}
