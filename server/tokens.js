// Signing our own sessions, and checking Apple's.
//
// Two different jobs that both happen to be JWTs. OUR token is symmetric: we
// signed it, we verify it, so HMAC with a secret only the worker knows.
// APPLE'S token is asymmetric and signed by Apple, so it has to be verified
// against Apple's published keys - and that verification is the whole security
// of Sign in with Apple. A token this side of the wire is a string somebody
// could have typed.

const encoder = new TextEncoder();

function base64url(bytes) {
  let binary = '';
  for (const b of new Uint8Array(bytes)) binary += String.fromCharCode(b);
  return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

/// Decodes one segment, or returns null if it is not valid base64url.
///
/// Returns rather than throws on purpose. Every token reaching this file came
/// off the wire and may be anything at all; a malformed one is an ordinary
/// "no" - a 401 - and must never become an exception that surfaces as a 500.
function fromBase64url(text) {
  if (typeof text !== 'string' || !/^[A-Za-z0-9_-]*$/.test(text)) return null;
  try {
    const padded = text.replace(/-/g, '+').replace(/_/g, '/')
      .padEnd(text.length + (4 - text.length % 4) % 4, '=');
    const binary = atob(padded);
    const bytes = new Uint8Array(binary.length);
    for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
    return bytes;
  } catch {
    return null;
  }
}

/// Whether a token's claims are still good: an expiry that is actually a
/// number, and still in the future.
///
/// The type check is the point. A token with no `exp` at all would give
/// `undefined * 1000`, which is NaN, and every comparison with NaN is false -
/// so a bare "is it past its expiry" test says no, and a token that never
/// expires is treated as fresh for ever.
function unexpired(claims) {
  return !!claims && typeof claims.exp === 'number' && claims.exp * 1000 >= Date.now();
}

export function decodeClaims(token) {
  const parts = (token || '').split('.');
  if (parts.length !== 3) return null;
  const bytes = fromBase64url(parts[1]);
  if (!bytes) return null;
  try {
    const claims = JSON.parse(new TextDecoder().decode(bytes));
    // A JWT payload is a JSON object. An array or a bare string parses
    // perfectly well and would then be read for claims it cannot have.
    return claims && typeof claims === 'object' && !Array.isArray(claims) ? claims : null;
  } catch {
    return null;
  }
}

/// The algorithm the token says it was signed with.
///
/// Checked even though both verifiers below pin the algorithm themselves, so a
/// forged `alg` cannot change how anything is verified. It is refused early
/// because a token asking to be treated differently from how we issue them has
/// nothing legitimate to say.
function algorithm(token) {
  const parts = (token || '').split('.');
  const bytes = parts.length === 3 ? fromBase64url(parts[0]) : null;
  if (!bytes) return null;
  try {
    return JSON.parse(new TextDecoder().decode(bytes)).alg || null;
  } catch {
    return null;
  }
}

export async function sha256Hex(text) {
  const digest = await crypto.subtle.digest('SHA-256', encoder.encode(text));
  return [...new Uint8Array(digest)].map(b => b.toString(16).padStart(2, '0')).join('');
}

// MARK: our own sessions

async function hmacKey(secret) {
  return crypto.subtle.importKey('raw', encoder.encode(secret),
    { name: 'HMAC', hash: 'SHA-256' }, false, ['sign', 'verify']);
}

export async function sign(payload, secret, seconds) {
  const header = base64url(encoder.encode(JSON.stringify({ alg: 'HS256', typ: 'JWT' })));
  const body = base64url(encoder.encode(JSON.stringify({
    ...payload,
    iat: Math.floor(Date.now() / 1000),
    exp: Math.floor(Date.now() / 1000) + seconds,
  })));
  const signature = await crypto.subtle.sign('HMAC', await hmacKey(secret),
    encoder.encode(`${header}.${body}`));
  return `${header}.${body}.${base64url(signature)}`;
}

export async function verify(token, secret) {
  const parts = (token || '').split('.');
  if (parts.length !== 3) return null;
  if (algorithm(token) !== 'HS256') return null;
  const signature = fromBase64url(parts[2]);
  if (!signature) return null;
  const ok = await crypto.subtle.verify('HMAC', await hmacKey(secret),
    signature, encoder.encode(`${parts[0]}.${parts[1]}`));
  if (!ok) return null;
  const claims = decodeClaims(token);
  if (!unexpired(claims)) return null;
  if (typeof claims.sub !== 'string' || !claims.sub) return null;
  return claims;
}

// MARK: Apple's identity token

let appleKeys = null;
let appleKeysAt = 0;

async function keysFromApple(force = false) {
  // cached for an hour: Apple rotates these, and fetching them on every sign-in
  // makes Apple's availability our availability
  if (!force && appleKeys && Date.now() - appleKeysAt < 3600_000) return appleKeys;
  const response = await fetch('https://appleid.apple.com/auth/keys');
  if (!response.ok) throw new Error('could not fetch Apple keys');
  appleKeys = (await response.json()).keys;
  appleKeysAt = Date.now();
  return appleKeys;
}

/// The key a token was signed with, fetching again if we have not seen it.
///
/// The cache is what makes a rotation dangerous: Apple starts signing with a
/// new key, our hour-old copy does not have it, and every Apple sign-in fails
/// until the cache happens to expire. A kid we do not recognise is exactly the
/// signal that our copy is stale, so it is worth one more fetch - and only one,
/// because an unknown kid is also what a forged token looks like.
async function appleKey(kid) {
  if (!kid) return null;
  const found = (await keysFromApple()).find(k => k.kid === kid);
  if (found) return found;
  return (await keysFromApple(true)).find(k => k.kid === kid) || null;
}

/// Verifies the token's signature against Apple's own key, then every claim
/// that matters: who issued it, who it was issued FOR, that it has not expired,
/// and that it carries the hashed nonce this particular sign-in sent. Without
/// the nonce check, a token captured from one sign-in can be replayed into
/// another.
export async function verifyApple(identityToken, expectedNonce, bundleId) {
  const parts = (identityToken || '').split('.');
  if (parts.length !== 3) return null;
  // Apple signs these with RS256. Pinned rather than read from the token,
  // because an algorithm chosen by whoever sent the token is not a check.
  if (algorithm(identityToken) !== 'RS256') return null;

  const headerBytes = fromBase64url(parts[0]);
  const signature = fromBase64url(parts[2]);
  if (!headerBytes || !signature) return null;
  let header;
  try { header = JSON.parse(new TextDecoder().decode(headerBytes)); } catch { return null; }

  const jwk = await appleKey(header.kid);
  if (!jwk) return null;

  const key = await crypto.subtle.importKey('jwk', jwk,
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['verify']);
  const ok = await crypto.subtle.verify('RSASSA-PKCS1-v1_5', key,
    signature, encoder.encode(`${parts[0]}.${parts[1]}`));
  if (!ok) return null;

  const claims = decodeClaims(identityToken);
  if (!claims) return null;
  if (claims.iss !== 'https://appleid.apple.com') return null;
  if (claims.aud !== bundleId) return null;
  if (!unexpired(claims)) return null;
  if (typeof claims.sub !== 'string' || !claims.sub) return null;
  // Without a nonce there is nothing tying this token to the sign-in that is
  // happening now, and a token captured from an earlier one would be accepted.
  if (!expectedNonce || typeof claims.nonce !== 'string') return null;
  if (claims.nonce !== await sha256Hex(expectedNonce)) return null;
  return claims;
}
