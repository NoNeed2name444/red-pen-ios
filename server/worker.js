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

const SESSION_SECONDS = 60 * 60 * 24 * 30;

const json = (body, status = 200) => new Response(JSON.stringify(body), {
  status, headers: { 'content-type': 'application/json' },
});
const fail = (status, message) => json({ error: message, message }, status);
const now = () => Math.floor(Date.now() / 1000);

export default {
  async fetch(request, env) {
    const path = new URL(request.url).pathname;

    try {
      // Blobs are raw bytes in both directions, so they are routed before
      // anything tries to read the body as JSON.
      if (path.startsWith('/blobs/') && path !== '/blobs/missing') {
        const id = await holder(request, env);
        if (!id) return fail(401, 'Please sign in again.');
        const name = path.slice('/blobs/'.length);
        if (request.method === 'PUT') return await putBlob(env, id, name, request);
        if (request.method === 'GET') return await getBlob(env, id, name);
        return fail(405, 'PUT or GET.');
      }

      if (request.method !== 'POST') return fail(405, 'POST only.');
      let body = {};
      try { body = await request.json(); } catch { body = {}; }

      switch (path) {
        case '/auth/apple': return await withApple(body, env);
        case '/auth/google': return await withGoogle(body, env);
        case '/auth/refresh': return await refresh(body, env);
        case '/account/delete': return await deleteAccount(request, env);
        case '/account/subscription': return await setSubscription(request, body, env);
        case '/sync/changes': return await guarded(request, env, id => changes(env, id, body));
        case '/sync/push': return await guarded(request, env, id => push(env, id, body));
        case '/blobs/missing': return await guarded(request, env, id => missingBlobs(env, id, body));
        default: return fail(404, 'No such endpoint.');
      }
    } catch (error) {
      // never echo the error back: a stack trace in a sign-in response is a map
      console.error(path, error);
      return fail(500, 'Something went wrong signing in.');
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
    email: claims.email || null, displayName: fullName || null,
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
    email: claims.email || null, displayName: claims.name || null,
  });
  return await session(env, account);
}

// MARK: staying and leaving

async function refresh(body, env) {
  const claims = await verify(body.refreshToken, env.SESSION_SECRET);
  if (!claims || claims.typ !== 'refresh') return fail(401, 'Please sign in again.');
  const account = await env.DB.prepare('SELECT * FROM accounts WHERE id = ?')
    .bind(claims.sub).first();
  if (!account) return fail(401, 'Please sign in again.');
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
  return claims && claims.typ === 'access' ? claims.sub : null;
}

async function deleteAccount(request, env) {
  const id = await holder(request, env);
  if (!id) return fail(401, 'Please sign in again.');
  // Actually deleted, not flagged, and the library goes with it. The App Store
  // requires the account to be removable from inside the app, and an account
  // whose data outlives it has not been deleted.
  await wipe(env, id);
  await env.DB.prepare('DELETE FROM accounts WHERE id = ?').bind(id).run();
  return json({ ok: true });
}

async function setSubscription(request, body, env) {
  const id = await holder(request, env);
  if (!id) return fail(401, 'Please sign in again.');
  const expires = Math.floor(new Date(body.expiresAt || 0).getTime() / 1000) || null;
  await env.DB.prepare('UPDATE accounts SET plan = ?, expires_at = ? WHERE id = ?')
    .bind(body.plan || null, expires, id).run();
  // Recorded as a convenience so a second phone knows what to expect. The App
  // Store remains the authority - this row is never what unlocks the app.
  return json({ ok: true });
}
