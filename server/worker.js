// Red Pen's server: who somebody is, and their library following them between
// their own devices.
//
// It holds one student's own material on their own account. Nothing is shared
// with anyone else, nothing is read for any other purpose, and the account can
// be deleted from inside the app - which takes the library with it, because
// leaving it behind after somebody asked to be forgotten would not be deleting
// anything.
//
// The sync half is in sync.js. The shape of it - documents with revisions, a
// changes feed, and pictures stored under the hash of their own bytes - is
// explained there.
import { sign, verify, verifyApple, decodeClaims } from './tokens.js';
import { changes, push, missingBlobs, putBlob, getBlob, wipe } from './sync.js';
import { chat, linkSubscription, isOwnerKey, transcribeChunk, budget } from './ai.js';
import { jobsRoute } from './jobs.js';
import { allowed, startPairing, finishPairing, DEVICES_PER_HOUR } from './pair.js';

// the Durable Object that runs generation jobs (see jobs.js)
export { GenerationJobs } from './jobs.js';

const SESSION_SECONDS = 60 * 60 * 24 * 30;

const json = (body, status = 200) => new Response(JSON.stringify(body), {
  status, headers: { 'content-type': 'application/json' },
});
const fail = (status, message) => json({ error: message, message }, status);
const now = () => Math.floor(Date.now() / 1000);

/// A string from a client, kept to a sane length - or null.
///
/// Everything here arrives from an app that anyone can send requests to
/// pretending to be. A display name is whatever the sender says it is, and
/// without a limit "whatever they say" can be a megabyte, stored for ever, and
/// read back on every sign-in.
const text = (value, max) =>
  typeof value === 'string' && value.trim() ? value.trim().slice(0, max) : null;

/// What one account may keep in pictures.
///
/// Not a business rule so much as a floor under the bill: without it, a single
/// signed-in account can upload twelve megabytes at a time for as long as it
/// likes, and nothing in the design would notice.
const BLOB_BUDGET = 2 * 1024 * 1024 * 1024;

/// Old builds asked here for the Firebase key and sent audio to Google
/// themselves. The key now stays on the server (see transcribeChunk), so this
/// only says so: an old build falls back to transcribing on the phone.
export async function transcribeConfig() {
  return fail(410, 'Cloud transcription now goes through Vignette; update the app.');
}

export default {
  async fetch(request, env) {
    const path = new URL(request.url).pathname;

    try {
      // Blobs are raw bytes in both directions, so they are routed before
      // anything tries to read the body as JSON.
      if (path.startsWith('/blobs/') && path !== '/blobs/missing') {
        const id = await holder(request, env);
        if (!id) return fail(401, 'Please sign in again.');
        // deployed without picture storage (no R2): documents still sync
        if (!env.BLOBS) return fail(503, 'Picture sync is not set up on this server.');
        const name = path.slice('/blobs/'.length);
        if (request.method === 'PUT') return await putBlob(env, id, name, request, BLOB_BUDGET);
        if (request.method === 'GET') return await getBlob(env, id, name);
        return fail(405, 'PUT or GET.');
      }

      // Generation jobs: GET and DELETE as well as POST, and a job carries
      // its lecture, so it is sized here like a sync batch
      if (path === '/jobs' || path.startsWith('/jobs/')) {
        if (Number(request.headers.get('content-length')) > 24 * 1024 * 1024) return fail(413, 'That request is too large.');
        if (isOwnerKey(request, env)) return await jobsRoute(request, env, 'owner', { owner: true });
        return await guarded(request, env, id => jobsRoute(request, env, id));
      }

      if (request.method !== 'POST') return fail(405, 'POST only.');
      // Sized before it is read, since a body is read into memory whole:
      // a transcription chunk is about 3 MB (never over 9), a sync batch can
      // be larger, everything else is small.
      const size = Number(request.headers.get('content-length')) || 0;
      const allowed = path === '/transcribe/chunk' ? 10 * 1024 * 1024
        : path === '/sync/push' ? 24 * 1024 * 1024   // a batch of documents
        : 2 * 1024 * 1024;
      if (size > allowed) return fail(413, 'That request is too large.');
      // a big body with no declared size is refused rather than read blind
      if (!size && path === '/transcribe/chunk') return fail(411, 'Say how large the audio is.');
      let body = {};
      try { body = await request.json(); } catch { body = {}; }

      switch (path) {
        case '/auth/apple': return await withApple(body, env);
        case '/auth/google': return await withGoogle(body, env);
        case '/auth/refresh': return await refresh(body, env);
        // a second device, by a code shown on the first (pair.js)
        case '/auth/device': return await deviceAccount(request, env);
        case '/auth/pair': return await pairDevice(request, body, env);
        case '/pair/start': return await guarded(request, env, async id => json(await startPairing(env, id)));
        case '/account/delete': return await deleteAccount(request, env);
        case '/account/signout': return await signOutEverywhere(request, env);
        case '/account/subscription': return await setSubscription(request, body, env);
        case '/sync/changes': return await guarded(request, env, id => changes(env, id, body));
        case '/sync/push': return await guarded(request, env, id => push(env, id, body));
        // Without picture storage nothing is asked for, so a device never
        // tries to upload and the documents' own sync carries on regardless.
        case '/blobs/missing': return await guarded(request, env, id =>
          env.BLOBS ? missingBlobs(env, id, body) : json({ missing: [] }));
        // CramDown Cloud: OpenAI-shaped, so the app's hosted client needs no
        // special case - the session token is the key
        case '/v1/chat/completions':
          if (isOwnerKey(request, env)) return await chat(env, 'owner', body, fetch, { owner: true });
          return await guarded(request, env, id => chat(env, id, body));
        // Narrate's cloud transcription, for Pro: the audio comes here in
        // ten-minute chunks and the server asks Gemini, so the Google key
        // never reaches a phone
        // for the owner: what Pro brings in and what the paid services cost
        // this month
        case '/costs':
          if (!isOwnerKey(request, env)) return fail(404, 'No such endpoint.');
          return json(await budget(env)); // forUse is null until the price is set (capped: false)
        case '/transcribe/config': return await transcribeConfig();
        case '/transcribe/chunk':
          if (isOwnerKey(request, env)) return await transcribeChunk(env, 'owner', body, fetch, { owner: true });
          return await guarded(request, env, id => transcribeChunk(env, id, body));
        default: return fail(404, 'No such endpoint.');
      }
    } catch (error) {
      // never echo the error back: a stack trace in a response is a map
      console.error(path, error);
      return fail(500, 'Something went wrong. Please try again.');
    }
  },
};

// MARK: accounts

async function upsert(env, { provider, subject, email, displayName }) {
  const existing = await env.DB.prepare(
    'SELECT * FROM accounts WHERE provider = ? AND subject = ?')
    .bind(provider, subject).first();
  if (existing) {
    // A name only ever arrives on the first Apple sign-in, so a later blank one
    // must not wipe the one we have.
    if (displayName && !existing.display_name) {
      await env.DB.prepare('UPDATE accounts SET display_name = ? WHERE id = ?')
        .bind(displayName, existing.id).run();
      existing.display_name = displayName;
    }
    return existing;
  }
  const id = crypto.randomUUID();
  await env.DB.prepare(
    `INSERT INTO accounts (id, provider, subject, email, display_name, created_at)
     VALUES (?, ?, ?, ?, ?, ?)`)
    .bind(id, provider, subject, email || null, displayName || null, now()).run();
  return { id, provider, subject, email, display_name: displayName };
}

async function session(env, account) {
  const token = await sign({ sub: account.id, typ: 'access' },
                           env.SESSION_SECRET, SESSION_SECONDS);
  const refreshToken = await sign({ sub: account.id, typ: 'refresh' },
                                  env.SESSION_SECRET, SESSION_SECONDS * 6);
  return json({
    userId: account.id,
    provider: account.provider,
    email: account.email || null,
    displayName: account.display_name || null,
    token, refreshToken, expiresIn: SESSION_SECONDS,
  });
}

// MARK: Apple

async function withApple(body, env) {
  const { identityToken, nonce, fullName } = body;
  if (!identityToken || !nonce) return fail(400, 'Missing sign-in details.');
  const claims = await verifyApple(identityToken, nonce, env.APPLE_BUNDLE_ID);
  if (!claims) return fail(401, "That Apple sign-in couldn't be verified.");
  const account = await upsert(env, {
    provider: 'apple', subject: claims.sub,
    // Apple only sends the address when the student allows it, and "hide my
    // email" sends a relay address. Either is fine; neither is required.
    email: text(claims.email, 320), displayName: text(fullName, 120),
  });
  return await session(env, account);
}

// MARK: Google

async function withGoogle(body, env) {
  const { code, codeVerifier, redirectUri } = body;
  if (!code || !codeVerifier) return fail(400, 'Missing sign-in details.');
  // The client secret lives here and only here: anything shipped inside an app
  // can be read out of it, which is why the app does PKCE and the exchange
  // happens on this side.
  const response = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'content-type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      code, code_verifier: codeVerifier, redirect_uri: redirectUri,
      client_id: env.GOOGLE_CLIENT_ID, client_secret: env.GOOGLE_CLIENT_SECRET,
      grant_type: 'authorization_code',
    }),
  });
  if (!response.ok) return fail(401, "Google wouldn't confirm that sign-in.");
  const claims = decodeClaims((await response.json()).id_token || '');
  // The token came straight from Google's own endpoint over TLS, so its
  // contents are as trustworthy as the connection; the audience check is what
  // stops a token minted for some other app being posted here.
  if (!claims || claims.aud !== env.GOOGLE_CLIENT_ID) {
    return fail(401, "Google's answer didn't match this app.");
  }
  const account = await upsert(env, {
    provider: 'google', subject: claims.sub,
    email: text(claims.email, 320), displayName: text(claims.name, 120),
  });
  return await session(env, account);
}

// MARK: a device of its own, and a second one

const clientIP = request => request.headers.get('cf-connecting-ip') || 'unknown';

/// An account for a device that started "on this device only", so it can
/// sync: no name, no email, just a random id.
async function deviceAccount(request, env) {
  if (!await allowed(env, clientIP(request), 'device', DEVICES_PER_HOUR)) {
    return fail(429, 'Too many new accounts from this network. Try again in an hour.');
  }
  const account = await upsert(env, { provider: 'device', subject: crypto.randomUUID() });
  return await session(env, account);
}

async function pairDevice(request, body, env) {
  const result = await finishPairing(env, clientIP(request), body.code);
  if (result.error) return fail(result.status, result.error);
  const account = await env.DB.prepare('SELECT * FROM accounts WHERE id = ?').bind(result.accountId).first();
  if (!account) return fail(404, 'That code is wrong or has expired.');
  return await session(env, account);
}

// MARK: staying and leaving

async function refresh(body, env) {
  const claims = await verify(body.refreshToken, env.SESSION_SECRET);
  if (!claims || claims.typ !== 'refresh') return fail(401, 'Please sign in again.');
  const account = await env.DB.prepare('SELECT * FROM accounts WHERE id = ?')
    .bind(claims.sub).first();
  if (!account) return fail(401, 'Please sign in again.');
  // A refresh token outlives an access token six times over, so it is the one
  // that most needs the revocation check. Without it, signing out everywhere
  // would end the sessions and the thief would simply mint a new one.
  if (!await stillValid(env, claims)) return fail(401, 'Please sign in again.');
  return await session(env, account);
}

/// Every call that touches somebody's own material goes through this, so the
/// check cannot be forgotten on one route out of six.
async function guarded(request, env, work) {
  const id = await holder(request, env);
  if (!id) return fail(401, 'Please sign in again.');
  return await work(id);
}

async function holder(request, env) {
  const header = request.headers.get('authorization') || '';
  const claims = await verify(header.replace(/^Bearer /, ''), env.SESSION_SECRET);
  if (!claims || claims.typ !== 'access') return null;
  return await stillValid(env, claims) ? claims.sub : null;
}

/// Whether a token that verifies is also one we still honour.
///
/// A signature only proves we issued it. Nothing in a signed token can be taken
/// back, so a thirty-day session on a lost phone stays good for thirty days -
/// unless something outside the token can say otherwise. That is this: each
/// account carries the moment it last revoked everything, and a token issued
/// before it is refused however well it is signed.
async function stillValid(env, claims) {
  const row = await env.DB.prepare(
    'SELECT signed_out_before FROM accounts WHERE id = ?').bind(claims.sub).first();
  // No such account any more - deleted while a token was still in the wild.
  if (!row) return false;
  const cutoff = Number(row.signed_out_before) || 0;
  return typeof claims.iat === 'number' && claims.iat >= cutoff;
}

/// Every session on every device, ended.
///
/// The one thing a student can do from another phone when they have lost this
/// one. Tokens are not stored, so they cannot be deleted one by one; moving the
/// cutoff forward refuses all of them at once, including this caller's, which is
/// what "everywhere" has to mean.
async function signOutEverywhere(request, env) {
  const id = await holder(request, env);
  if (!id) return fail(401, 'Please sign in again.');
  // A second into the future, so a token minted in this same second - including
  // the one that authorised this call - is on the wrong side of the line.
  await env.DB.prepare('UPDATE accounts SET signed_out_before = ? WHERE id = ?')
    .bind(now() + 1, id).run();
  return json({ ok: true });
}

async function deleteAccount(request, env) {
  const id = await holder(request, env);
  if (!id) return fail(401, 'Please sign in again.');
  // Actually deleted, not flagged, and the library goes with it. The App Store
  // requires the account to be removable from inside the app, and an account
  // whose data outlives it has not been deleted.
  await wipe(env, id);
  // The month's AI spend and today's allowance stay: they hold no personal
  // data, and deleting them would let a new account on the same subscription
  // start the month over.
  await env.DB.prepare('DELETE FROM pair_codes WHERE account_id = ?').bind(id).run();
  await env.DB.prepare('DELETE FROM accounts WHERE id = ?').bind(id).run();
  return json({ ok: true });
}

async function setSubscription(request, body, env) {
  const id = await holder(request, env);
  if (!id) return fail(401, 'Please sign in again.');
  const expires = Math.floor(new Date(body.expiresAt || 0).getTime() / 1000) || null;
  await env.DB.prepare('UPDATE accounts SET plan = ?, expires_at = ? WHERE id = ?')
    .bind(text(body.plan, 40), expires, id).run();
  // The one part Apple is asked about: which subscription this is, for the
  // cloud models. The plan above stays a convenience.
  if (body.originalTransactionId) return await linkSubscription(env, id, body);
  // Recorded as a convenience so a second phone knows what to expect. The App
  // Store remains the authority - this row is never what unlocks the app.
  return json({ ok: true });
}
