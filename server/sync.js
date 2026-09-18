// The syncing half: one student's library, following them between their own
// devices.
//
// Three ideas hold it up.
//
// **A revision counter per account.** Every write takes the next number, and a
// device asks "what has happened since 47?". That makes the common case - a
// phone that opened the app and nothing has changed - one small query, and it
// makes a new device's first sync the same code path as every other.
//
// **Compare-and-set on the way in.** A push says which revision it was working
// from. If the document has moved since, the write is refused and the server's
// copy comes back instead, so the device can merge and try again. Refusing is
// per document: one stale deck must not throw away the nineteen good ones in
// the same batch.
//
// **Pictures live under the hash of their own bytes.** The same diagram in
// three decks is stored once, an upload can be retried without duplicating
// anything, and a device that already has a picture asks for nothing.

const json = (body, status = 200) => new Response(JSON.stringify(body), {
  status, headers: { 'content-type': 'application/json' },
});
const now = () => Math.floor(Date.now() / 1000);

/// The next revision for this account.
///
/// Read and written inside the same statement so two devices pushing at the
/// same moment cannot be handed the same number - which would leave one of
/// their changes invisible to a device that had already asked past it.
async function nextRev(env, account) {
  const row = await env.DB.prepare(
    `INSERT INTO sync_state (account_id, rev) VALUES (?, 1)
     ON CONFLICT(account_id) DO UPDATE SET rev = rev + 1
     RETURNING rev`).bind(account).first();
  return row.rev;
}

// MARK: pulling

export async function changes(env, account, body) {
  const since = Number(body.since) || 0;
  // One more than asked for, so "is there another page" needs no second query.
  const limit = Math.min(Math.max(Number(body.limit) || 200, 1), 500);
  const rows = await env.DB.prepare(
    `SELECT id, kind, rev, updated_at, deleted, payload FROM docs
     WHERE account_id = ? AND rev > ? ORDER BY rev ASC LIMIT ?`)
    .bind(account, since, limit + 1).all();

  const page = rows.results.slice(0, limit);
  const more = rows.results.length > limit;
  const cursor = page.length ? page[page.length - 1].rev : since;

  return json({
    docs: page.map(row => ({
      id: row.id,
      kind: row.kind,
      rev: row.rev,
      updatedAt: new Date(row.updated_at * 1000).toISOString(),
      deleted: !!row.deleted,
      // D1 gives text back; the app wants the payload base64 in JSON, which is
      // how Swift's Data encodes anyway.
      payload: row.payload || null,
    })),
    cursor,
    more,
  });
}

// MARK: pushing

export async function push(env, account, body) {
  const docs = Array.isArray(body.docs) ? body.docs : [];
  const accepted = [];
  const conflicts = [];

  for (const doc of docs) {
    if (!doc || typeof doc.id !== 'string') continue;
    const existing = await env.DB.prepare(
      'SELECT rev, updated_at, kind, deleted, payload FROM docs WHERE account_id = ? AND id = ?')
      .bind(account, doc.id).first();

    const incomingAt = Math.floor(new Date(doc.updatedAt).getTime() / 1000) || now();

    // The device says which revision it was working from. If the document has
    // moved since, it is working from stale information and has to be told -
    // on the revision alone, never on whose clock is further ahead.
    //
    // Letting a later timestamp through would save a round trip and quietly
    // skip the client's merge, which is the only place a losing version is kept
    // as a copy. A device with a fast clock would then overwrite other people's
    // work without anybody being told. The extra round trip is rare and cheap;
    // that is not.
    if (existing && existing.rev > (Number(doc.rev) || 0)) {
      conflicts.push({
        id: doc.id,
        kind: existing.kind,
        rev: existing.rev,
        updatedAt: new Date(existing.updated_at * 1000).toISOString(),
        deleted: !!existing.deleted,
        payload: existing.payload || null,
      });
      continue;
    }

    const rev = await nextRev(env, account);
    const deleted = doc.deleted ? 1 : 0;
    // A tombstone drops the body. Keeping the contents of something somebody
    // deleted is the opposite of deleting it.
    const payload = deleted ? null : (doc.payload || null);
    // A tombstone is sent without knowing what it was a tombstone FOR, so it
    // must not relabel a folder as a set on its way out.
    const kind = deleted
      ? (existing?.kind || doc.kind || 'set')
      : (doc.kind || existing?.kind || 'set');

    await env.DB.prepare(
      `INSERT INTO docs (account_id, id, kind, rev, updated_at, deleted, payload)
       VALUES (?, ?, ?, ?, ?, ?, ?)
       ON CONFLICT(account_id, id) DO UPDATE SET
         kind = excluded.kind, rev = excluded.rev, updated_at = excluded.updated_at,
         deleted = excluded.deleted, payload = excluded.payload`)
      .bind(account, doc.id, kind, rev, incomingAt, deleted, payload).run();

    accepted.push({ ...doc, kind, rev, deleted: !!deleted, payload });
  }

  return json({ accepted, conflicts });
}

// MARK: pictures

export async function missingBlobs(env, account, body) {
  const names = Array.isArray(body.names) ? body.names.slice(0, 500) : [];
  const missing = [];
  for (const name of names) {
    if (!isHash(name)) continue;
    const head = await env.BLOBS.head(key(account, name));
    if (!head) missing.push(name);
  }
  return json({ missing });
}

export async function putBlob(env, account, name, request) {
  if (!isHash(name)) return json({ error: 'bad name' }, 400);
  const data = await request.arrayBuffer();
  if (data.byteLength > 12 * 1024 * 1024) return json({ error: 'too big' }, 413);

  // The name has to be the hash of what arrived. Without this check a caller
  // could park anything under any address, and every device that later asked
  // for that picture would get the wrong bytes - for ever, because nothing
  // would ever re-fetch a blob it believes it already has.
  const digest = await crypto.subtle.digest('SHA-256', data);
  const actual = [...new Uint8Array(digest)]
    .map(b => b.toString(16).padStart(2, '0')).join('');
  if (actual !== name) return json({ error: 'that is not its hash' }, 400);

  await env.BLOBS.put(key(account, name), data);
  return json({ ok: true });
}

export async function getBlob(env, account, name) {
  if (!isHash(name)) return json({ error: 'bad name' }, 400);
  const object = await env.BLOBS.get(key(account, name));
  if (!object) return json({ error: 'no such picture' }, 404);
  return new Response(object.body, {
    headers: {
      'content-type': 'application/octet-stream',
      // Content addressed, so it can be cached for ever: these bytes cannot
      // become different bytes without becoming a different name.
      'cache-control': 'private, max-age=31536000, immutable',
    },
  });
}

/// Blobs are namespaced per account rather than shared across all of them.
///
/// Sharing by hash would be cheaper, and it would also mean that uploading a
/// picture tells you whether somebody else already has that exact file. Storage
/// is not worth that.
function key(account, name) { return `${account}/${name}`; }

function isHash(name) { return /^[0-9a-f]{64}$/.test(name || ''); }

// MARK: leaving

/// Everything belonging to an account, gone.
export async function wipe(env, account) {
  await env.DB.prepare('DELETE FROM docs WHERE account_id = ?').bind(account).run();
  await env.DB.prepare('DELETE FROM sync_state WHERE account_id = ?').bind(account).run();
  // R2 has no "delete by prefix", so the keys have to be listed and removed in
  // batches. A page at a time, because an account with a term of lectures in it
  // has thousands.
  let cursor;
  do {
    const listed = await env.BLOBS.list({ prefix: `${account}/`, cursor });
    if (listed.objects.length) {
      await env.BLOBS.delete(listed.objects.map(o => o.key));
    }
    cursor = listed.truncated ? listed.cursor : undefined;
  } while (cursor);
}
