// Codes people read aloud or type: share codes and class join codes (10
// characters), referral codes (7). The alphabet is pair.js's: capitals and
// digits without 0, O, 1, I and L, so nothing is misread.

export const ALPHABET = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';

/// `len` characters drawn evenly from ALPHABET. 31 * 8 = 248, so a byte of
/// 248 or more is dropped and drawn again rather than folded back, which would
/// make the first eight letters likelier than the rest.
export function randomCode(len) {
  const n = Math.max(1, Math.floor(Number(len) || 0));
  let out = '';
  while (out.length < n) {
    const bytes = crypto.getRandomValues(new Uint8Array(n * 2));
    for (const b of bytes) {
      if (b >= 248) continue;
      out += ALPHABET[b % ALPHABET.length];
      if (out.length === n) break;
    }
  }
  return out;
}

/// A code as typed or pasted: upper-cased, stripped to letters and digits, and
/// valid only when every character is in ALPHABET and the length is exact.
/// Anything else is null.
export function normaliseCode(raw, len) {
  if (typeof raw !== 'string') return null;
  const code = raw.toUpperCase().replace(/[^A-Z0-9]/g, '');
  if (code.length !== len) return null;
  for (const c of code) if (!ALPHABET.includes(c)) return null;
  return code;
}
