// Proxy mode for the verification bench (layer.mjs --proxy): this branch's own
// checkBatch runs here, and the live Worker is only a model proxy. Every
// checker call is rewritten to the Worker's owner benchmark route - one named
// model, `x-bench: 1` - so the Worker's own limits apply (OWNER_BENCH_DAILY_LIMIT,
// the Workers AI neuron pool, the Gemini ceiling) and its keys never leave it.
//
// Free families only (docs/verification/rag-plan.md section 7, item 5): the
// pins are the live free order, read from votersFor, and a Claude pin is
// refused, since the Worker would spend the owner's Anthropic allowance on it.
import { votersFor } from '../../server/accuracy.js';

/// The free families a pin may name; the Worker's `use` takes these two.
const FREE = new Set(['gemini', 'workers-ai']);

/// Thrown for a pin that is not a free family's.
export class PinRefused extends Error {
  constructor(pin, why) { super(`refused pin "${pin}": ${why}`); this.name = 'PinRefused'; this.pin = pin; }
}

/// The Worker's `use` for a pin ("bench:gemini:gemini-3.5-flash-lite" or the
/// bare "gemini:gemini-3.5-flash-lite"): never a Claude model, whatever the
/// way it is spelled, and only a free family.
export function usePin(pin) {
  const text = String(pin || '').trim();
  const use = text.replace(/^bench:/, '');
  if (/claude|anthropic/i.test(use)) throw new PinRefused(text, 'claude is never pinned (the owner\'s paid key); free families only');
  const at = use.indexOf(':');
  if (at < 1 || at === use.length - 1) throw new PinRefused(text, 'a pin is <family>:<model>');
  if (!FREE.has(use.slice(0, at))) throw new PinRefused(text, 'free families only (gemini, workers-ai)');
  return use;
}

/// The live free order as `bench:` pins, read from the engine's own
/// votersFor (server/accuracy.js) so it follows the live list: what a
/// student's check asks, in order, Claude left out because it is the owner's
/// only. The environment is stood in for with every free provider set up.
export function freeVoterPins() {
  const everything = { AI: {}, FIREBASE_API_KEY: 'x', FIREBASE_PROJECT_ID: 'x' };
  return votersFor(everything, '', false).map(v => `bench:${usePin(v)}`);
}

/// The chat call as the Worker takes it: its writer route with one model
/// pinned and no grounding, so the model gives its own judgement and the
/// engine's own evidence (already in the prompt) is all it reads.
export function rewriteChat(body, extra = {}) {
  const use = usePin(body?.model);
  return { ...body, model: 'cramdown-writer', use, ground: false, ...extra };
}

/// A fetcher for checkBatch: chat calls go to the Worker rewritten (with
/// `x-bench: 1`); anything else (the evidence and proof lookups) goes where
/// it was going, as it does in the Worker. `fetchImpl` is for tests.
export function proxyFetcher(fetchImpl = fetch) {
  return async (url, init = {}) => {
    if (!String(url).endsWith('/chat/completions')) return fetchImpl(url, init);
    const body = JSON.parse(init.body);
    return fetchImpl(url, { ...init, headers: { ...init.headers, 'x-bench': '1' }, body: JSON.stringify(rewriteChat(body)) });
  };
}

/// The environment checkBatch is given in proxy mode: the Worker's models
/// through BENCH_BASE_URL (the Worker's /v1) and BENCH_API_KEY (the owner key).
/// `route`: the vignette route, on as live or off.
export function proxyEnv({ base, key, voters, route = 'on', db }) {
  return { DB: db, BENCH_MODELS: 'on', BENCH_BASE_URL: base, BENCH_API_KEY: key, ACCURACY_VOTERS: voters.join(','),
    VIGNETTE_ROUTE: route === 'off' ? 'off' : 'on',
    OWNER_ACCOUNT_IDS: 'bench', OWNER_BENCH_DAILY_LIMIT: '100000', ACCURACY_DAILY_CEILING: '100000' };
}
