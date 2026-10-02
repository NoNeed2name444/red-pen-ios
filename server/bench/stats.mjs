// Small statistics shared by the benches and the accuracy model's training
// (bench/train-accuracy.mjs): a seeded sample and the Wilson interval, plus
// reading a letter or a risk out of a model's reply.

export function rng(seed) {
  let a = seed >>> 0;
  return () => { a = (a + 0x6D2B79F5) >>> 0; let t = a; t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61); return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
}

export function sample(total, n, seed) {
  const r = rng(seed); const picked = new Set();
  while (picked.size < Math.min(n, total)) picked.add(Math.floor(r() * total));
  return [...picked].sort((a, b) => a - b);
}

export function wilson(k, n, z = 1.96) {
  if (!n) return [0, 0];
  const p = k / n, d = 1 + z * z / n;
  const c = (p + z * z / (2 * n)) / d, h = (z * Math.sqrt(p * (1 - p) / n + z * z / (4 * n * n))) / d;
  return [Math.max(0, c - h), Math.min(1, c + h)];
}

/// The letter the model chose: from its JSON, or - a reply cut off before the
/// JSON - from its last explicit conclusion ("the answer is C", "Answer: C").
/// The letter must be a capital standing alone, so "the answer is a
/// thiazide" is not read as A, and the last conclusion wins over options
/// discussed on the way. Nothing clear is no answer, never a guess.
export function letterFrom(reply) {
  const text = String(reply);
  try {
    const j = JSON.parse(text.slice(text.indexOf('{'), text.lastIndexOf('}') + 1));
    if (/^[A-D]$/i.test(String(j.answer).trim())) return String(j.answer).trim().toUpperCase();
  } catch {}
  const stated = [...text.matchAll(/\b[Aa]nswer\s*(?:is|:)\s*(?:option\s*)?\(?([A-D])\)?(?![A-Za-z0-9])/g)];
  if (stated.length) return stated.at(-1)[1];
  const m = text.match(/^\s*\(?([A-D])[).:](?:\s|$)/m);
  return m ? m[1] : null;
}

/// MedVAL's risk level out of a checker reply (the same parse the app uses).
export function riskFrom(reply) {
  const m = String(reply).match(/\[\[ ## risk_level ## \]\]\s*\n?\s*(?:Level\s*)?([1-4])/i)
    || String(reply).match(/risk[_ ]level[^0-9]{0,20}([1-4])/i);
  return m ? Number(m[1]) : null;
}


/// A refusal's limit: 'day' (stop until midnight UTC), 'minute' (wait), or null.
export function limitKind(message, body = {}) {
  if (body?.limit === 'day') return 'day';
  const m = String(message || '');
  if (/PerDay|4006|daily free allocation|per day|today's \d+ cloud requests|resets at midnight|share of today's free allowance/i.test(m)) return 'day';
  if (/PerMinute|per minute|RESOURCE_EXHAUSTED|exceeded your current quota|overloaded|rate limit/i.test(m)) return 'minute';
  return null;
}
