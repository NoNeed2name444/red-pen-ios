// Jev (TypeSafe AI's System One), for the oath check only - plan §22 Layer 7,
// as the §22a research brief left it: regex first, fail closed.
//
// Jev answers typed questions with probabilities and never writes text. Here
// it gets one yes/no question about an item - does it give a dose, name a
// diagnosis or recommend a treatment? - and a yes can only ADD the oath check
// to an item the patterns missed. A no, a slow answer, an error or anything
// unreadable changes nothing: the patterns' answer stands.
//
// Every call is paid, so it runs only when its key is set AND Pro money
// covers paid calls (PRO_PAYS = "on", ai.js proPays); until then this module
// is inert. Its threshold is the brief's starting point and must be tuned on
// a few hundred of Stethoscore's own labelled items before it is trusted for
// anything more than adding checks.
//
// Request and response follow https://api.typesafe.ai/openapi.json: POST
// /v1/systemone {state, model, questions: {name: {type: 'noul', instructions}}}
// -> {model, answers: {name: {type: 'noul', noul: 0-1}}}, bearer key.

import { proPays } from './ai.js';

export const DEFAULT_ENDPOINT = 'https://api.typesafe.ai/v1/systemone';
export const DEFAULT_MODEL = 'jev-latest';
/// Jev's 1-second budget (plan §22): past it the patterns' answer stands.
export const TIMEOUT_MS = 1000;
/// Yes at or above this: the item gets the oath check (the brief's 0.90 gate).
export const OATH_YES = 0.9;
/// The state is cut to fit Jev's context comfortably.
const MAX_STATE_CHARS = 12_000;

export const OATH_QUESTION = 'This medical study item gives a specific drug dose, states a diagnosis, or recommends a treatment or management step.';

/// Whether Jev may be asked at all: its key, and Pro money for paid calls.
export async function jevAvailable(env) {
  return !!env.JEV_API_KEY && await proPays(env);
}

/// P(yes) for the oath question about `text`, or null: not available, too
/// slow, refused, or an answer that is not a probability.
export async function jevOath(env, text, fetcher = fetch) {
  if (!await jevAvailable(env)) return null;
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), Number(env.JEV_TIMEOUT_MS) || TIMEOUT_MS);
  try {
    const res = await fetcher(env.STETHOSCORE_JEV_ENDPOINT || DEFAULT_ENDPOINT, {
      method: 'POST',
      headers: { authorization: `Bearer ${env.JEV_API_KEY}`, 'content-type': 'application/json' },
      body: JSON.stringify({
        state: String(text || '').slice(0, MAX_STATE_CHARS),
        model: env.STETHOSCORE_JEV_MODEL || DEFAULT_MODEL,
        questions: { oath: { type: 'noul', instructions: OATH_QUESTION } },
      }),
      signal: controller.signal,
    });
    if (!res.ok) return null;
    const data = await res.json();
    const answer = data?.answers?.oath;
    const p = Number(answer?.noul);
    if (answer?.type !== 'noul' || !Number.isFinite(p) || p < 0 || p > 1) return null;
    return p;
  } catch {
    return null;
  } finally {
    clearTimeout(timer);
  }
}

/// The oath check with Jev's say added: the patterns' answer, or yes when
/// Jev is confident the patterns missed one. Never a no the patterns did not
/// give.
export function oathWithJev(patterns, jevP) {
  return patterns || (Number.isFinite(jevP) && jevP >= OATH_YES);
}
