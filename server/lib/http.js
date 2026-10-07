// Response helpers shared by the worker and every module on the router.
//
// The error shape is {error, message, code}: `error` and `message` carry the
// same human sentence (older app builds read either), and `code` is the stable
// word the app maps and localises. Business errors on new routes always carry
// a code (plan section 3.1); a code is left out when none is given, so the
// legacy routes answer exactly as they did.

export const json = (body, status = 200, headers = {}) => new Response(JSON.stringify(body), {
  status, headers: { 'content-type': 'application/json', ...headers },
});

export function fail(status, message, code, extra) {
  const body = { error: message, message };
  if (code) body.code = code;
  if (extra && typeof extra === 'object') Object.assign(body, extra);
  return json(body, status);
}

/// A string from a client, kept to a sane length - or null.
///
/// Everything here arrives from an app that anyone can send requests to
/// pretending to be. A display name is whatever the sender says it is, and
/// without a limit "whatever they say" can be a megabyte, stored for ever, and
/// read back on every sign-in.
export const text = (value, max) =>
  typeof value === 'string' && value.trim() ? value.trim().slice(0, max) : null;

/// A request's body as bytes, read no further than `max` bytes.
///
/// The declared size is checked before this, but a body sent without one
/// (chunked) would otherwise be read into memory whole, however large. Past
/// the limit the read stops and the body counts as unreadable.
export async function boundedBytes(request, max) {
  if (!request.body) return new Uint8Array(0);
  const reader = request.body.getReader();
  const chunks = [];
  let size = 0;
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    size += value.byteLength;
    if (size > max) {
      await reader.cancel().catch(() => {});
      throw new Error('body too large');
    }
    chunks.push(value);
  }
  const bytes = new Uint8Array(size);
  let at = 0;
  for (const chunk of chunks) { bytes.set(chunk, at); at += chunk.byteLength; }
  return bytes;
}

/// The same, as text.
export async function boundedText(request, max) {
  return new TextDecoder().decode(await boundedBytes(request, max));
}

export const now = () => Math.floor(Date.now() / 1000);
