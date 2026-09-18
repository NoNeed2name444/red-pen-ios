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

function fromBase64url(text) {
  const padded = text.replace(/-/g, '+').replace(/_/g, '/')
    .padEnd(text.length + (4 - text.length % 4) % 4, '=');
  const binary = atob(padded);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

export function decodeClaims(token) {
  const parts = token.split('.');
  if (parts.length !== 3) return null;
  try {
    return JSON.parse(new TextDecoder().decode(fromBase64url(parts[1])));
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
  const ok = await crypto.subtle.verify('HMAC', await hmacKey(secret),
    fromBase64url(parts[2]), encoder.encode(`${parts[0]}.${parts[1]}`));
  if (!ok) return null;
  const claims = decodeClaims(token);
  if (!claims || claims.exp * 1000 < Date.now()) return null;
  return claims;
}

// MARK: Apple's identity token

let appleKeys = null;
let appleKeysAt = 0;

async function keysFromApple() {
  // cached for an hour: Apple rotates these, and fetching them on every sign-in
  // makes Apple's availability our availability
  if (appleKeys && Date.now() - appleKeysAt < 3600_000) return appleKeys;
  const response = await fetch('https://appleid.apple.com/auth/keys');
  if (!response.ok) throw new Error('could not fetch Apple keys');
  appleKeys = (await response.json()).keys;
  appleKeysAt = Date.now();
  return appleKeys;
}

/// Verifies the token's signature against Apple's own key, then every claim
/// that matters: who issued it, who it was issued FOR, that it has not expired,
/// and that it carries the hashed nonce this particular sign-in sent. Without
/// the nonce check, a token captured from one sign-in can be replayed into
/// another.
export async function verifyApple(identityToken, expectedNonce, bundleId) {
  const parts = identityToken.split('.');
  if (parts.length !== 3) return null;
  const header = JSON.parse(new TextDecoder().decode(fromBase64url(parts[0])));
  const jwk = (await keysFromApple()).find(k => k.kid === header.kid);
  if (!jwk) return null;

  const key = await crypto.subtle.importKey('jwk', jwk,
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['verify']);
  const ok = await crypto.subtle.verify('RSASSA-PKCS1-v1_5', key,
    fromBase64url(parts[2]), encoder.encode(`${parts[0]}.${parts[1]}`));
  if (!ok) return null;

  const claims = decodeClaims(identityToken);
  if (!claims) return null;
  if (claims.iss !== 'https://appleid.apple.com') return null;
  if (claims.aud !== bundleId) return null;
  if (claims.exp * 1000 < Date.now()) return null;
  if (claims.nonce !== await sha256Hex(expectedNonce)) return null;
  return claims;
}
