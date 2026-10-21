// Small hashing helpers on WebCrypto (available in Workers and in Node 22).

const enc = new TextEncoder();
const hex = bytes => [...new Uint8Array(bytes)].map(b => b.toString(16).padStart(2, '0')).join('');

/// SHA-256 of a string or bytes, as 64 lower-case hex characters.
export async function sha256hex(input) {
  const data = typeof input === 'string' ? enc.encode(input) : input;
  return hex(await crypto.subtle.digest('SHA-256', data));
}

/// HMAC-SHA256(secret, message), as 64 lower-case hex characters.
export async function hmacHex(secret, message) {
  const key = await crypto.subtle.importKey('raw', enc.encode(String(secret)),
    { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  return hex(await crypto.subtle.sign('HMAC', key, enc.encode(String(message))));
}

/// Base64url without padding, of bytes or a string.
export function b64url(input) {
  const bytes = typeof input === 'string' ? enc.encode(input) : new Uint8Array(input);
  let binary = '';
  for (let i = 0; i < bytes.length; i++) binary += String.fromCharCode(bytes[i]);
  return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}
