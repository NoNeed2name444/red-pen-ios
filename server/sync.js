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

const finite = (value, fallback) => {
  const n = Number(value);
  return value !== undefined && value !== null && value !== '' && Number.isFinite(n) ? n : fallback;
};

// MARK: pulling

/// A page of the changes feed is cut by size as well as by count. A set can
/// carry a whole lecture, so two hundred of them can be far more than a Worker
/// may hold in memory at once - and a page that cannot be sent is sent again,
/// and fails again, for ever. At least one document always goes, however big.
const PAGE_BYTES = 8 * 1024 * 1024;

export async function changes(env, account, body) {
  const since = Number(body.since) || 0;
  const limit = Math.min(Math.max(Number(body.limit) || 200, 1), 500);
  const budget = finite(env.SYNC_PAGE_BYTES, PAGE_BYTES);
  // First only the sizes (one more than asked for, so "is there another page"
  // needs no second query) ...
  const heads = (await env.DB.prepare(
    `SELECT rev, COALESCE(LENGTH(payload), 0) AS size FROM docs
     WHERE account_id = ? AND rev > ? ORDER BY rev ASC LIMIT ?`)
    .bind(account, since, limit + 1).all()).results;
  let take = 0, bytes = 0;
  for (const row of heads.slice(0, limit)) {
    if (take > 0 && bytes + Number(row.size) > budget) break;
    bytes += Number(row.size);
    take += 1;
  }
  if (!take) return json({ docs: [], cursor: since, more: false });
  const last = heads[take - 1].rev;
  // ... then the documents themselves, up to the last one that fits
  const rows = (await env.DB.prepare(
    `SELECT id, kind, rev, updated_at, deleted, payload FROM docs
     WHERE account_id = ? AND rev > ? AND rev <= ? ORDER BY rev ASC`)
    .bind(account, since, last).all()).results;

  return json({
    docs: rows.map(row => ({
      id: row.id,
      kind: row.kind,
      rev: row.rev,
      updatedAt: new Date(row.updated_at * 1000).toISOString(),
      deleted: !!row.deleted,
      // D1 gives text back; the app wants the payload base64 in JSON, which is
      // how Swift's Data encodes anyway.
      payload: row.payload || null,
    })),
    cursor: last,
    more: heads.length > take,
  });
}

// MARK: pushing

const MAX_PAYLOAD_CHARS = 1_900_000;
const MAX_DOCS_PER_ACCOUNT = 50_000;
/// What one account's documents may take in the database everyone shares.
/// Pictures live in R2; what is left is text, and 64 MB of it is hundreds of
/// lectures. DOC_BYTES_PER_ACCOUNT changes it.
const DOC_BYTES_PER_ACCOUNT = 64 * 1024 * 1024;
/// Past this the database itself is nearly full (D1's free plan stops at
/// 500 MB): nothing may grow any more, so sign-in, pairing and everyone's
/// allowances keep working. DB_SOFT_LIMIT_BYTES changes it.
const DB_SOFT_LIMIT_BYTES = 400 * 1000 * 1000;
/// Documents written per database call (three statements each, as one
/// transaction). A whole batch as one call per document would run into the
/// free plan's thousand calls per request at about three hundred documents.
const WRITE_CHUNK = 20;
/// D1 binds at most 100 parameters to one statement.
const READ_CHUNK = 90;

/// How much of the database this account's documents take, kept as a running
/// total beside the revision counter (see push). An account that has never
/// been counted - every account, the first time after this was added - is
/// counted once.
async function docUsage(env, account) {
  const row = await env.DB.prepare('SELECT bytes, docs FROM doc_usage WHERE account_id = ?').bind(account).first();
  if (row) return { bytes: Number(row.bytes) || 0, docs: Number(row.docs) || 0 };
  const counted = await env.DB.prepare(
    'SELECT COUNT(*) AS docs, COALESCE(SUM(LENGTH(payload)), 0) AS bytes FROM docs WHERE account_id = ?')
    .bind(account).first();
  const usage = { bytes: Number(counted?.bytes) || 0, docs: Number(counted?.docs) || 0 };
  await env.DB.prepare('INSERT OR IGNORE INTO doc_usage (account_id, bytes, docs) VALUES (?, ?, ?)')
    .bind(account, usage.bytes, usage.docs).run();
  return usage;
}

const conflictOf = (id, row) => ({
  id,
  kind: row.kind,
  rev: row.rev,
  updatedAt: new Date(row.updated_at * 1000).toISOString(),
  deleted: !!row.deleted,
  payload: row.payload || null,
});

export async function push(env, account, body) {
  // one account cannot fill the database everyone shares: a count of its
  // documents and of their bytes, kept as it goes rather than counted again
  // on every push
  const quota = finite(env.DOC_BYTES_PER_ACCOUNT, DOC_BYTES_PER_ACCOUNT);
  const dbLimit = finite(env.DB_SOFT_LIMIT_BYTES, DB_SOFT_LIMIT_BYTES);
  const usage = await docUsage(env, account);
  if (usage.docs >= MAX_DOCS_PER_ACCOUNT) return json({ error: 'This library is too large to sync.' }, 507);
  // Capped because a batch is whatever the sender says it is. A real device
  // sends tens; a request claiming fifty thousand is not a sync. Anything past
  // the cap is simply not answered, and the device sends it again next time.
  const docs = (Array.isArray(body.docs) ? body.docs.slice(0, 500) : []).filter(doc =>
    // D1 rows stop at 2 MB; an id or kind is a short name, never a document
    doc && typeof doc.id === 'string' && doc.id && doc.id.length <= 200
    && (doc.kind == null || (typeof doc.kind === 'string' && /^[A-Za-z0-9_.-]{1,40}$/.test(doc.kind)))
    // a payload is base64 text or nothing: anything else cannot be bound to
    // the statement below, and one such document would fail the whole batch
    && (doc.payload == null || (typeof doc.payload === 'string' && doc.payload.length <= MAX_PAYLOAD_CHARS)));

  // What is there now, for every document in the batch at once - without the
  // bodies, which only a conflict needs.
  const existing = new Map();
  const ids = [...new Set(docs.map(d => d.id))];
  for (let i = 0; i < ids.length; i += READ_CHUNK) {
    const part = ids.slice(i, i + READ_CHUNK);
    const found = await env.DB.prepare(
      `SELECT id, rev, kind, COALESCE(LENGTH(payload), 0) AS size FROM docs
       WHERE account_id = ? AND id IN (${part.map(() => '?').join(', ')})`)
      .bind(account, ...part).all();
    for (const row of found.results) existing.set(row.id, row);
  }

  const accepted = [];
  const conflicts = [];
  const stale = [];
  const writes = [];
  let refused = 0;
  const seen = new Set();
  for (const doc of docs) {
    // the same id twice in one batch: the first is the one that counts
    if (seen.has(doc.id)) continue;
    seen.add(doc.id);
    const before = existing.get(doc.id);
    // The device says which revision it was working from. If the document has
    // moved since, it is working from stale information and has to be told -
    // on the revision alone, never on whose clock is further ahead.
    //
    // Letting a later timestamp through would save a round trip and quietly
    // skip the client's merge, which is the only place a losing version is kept
    // as a copy. A device with a fast clock would then overwrite other people's
    // work without anybody being told. The extra round trip is rare and cheap;
    // that is not.
    if (before && before.rev > (Number(doc.rev) || 0)) { stale.push(doc.id); continue; }

    const deleted = doc.deleted ? 1 : 0;
    // A tombstone drops the body. Keeping the contents of something somebody
    // deleted is the opposite of deleting it.
    const payload = deleted ? null : (doc.payload || null);
    const grows = (payload ? payload.length : 0) - (before ? Number(before.size) || 0 : 0);
    const added = before ? 0 : 1;
    // Past the account's share only what shrinks or deletes gets through, so
    // a full library can still be tidied.
    if ((grows > 0 && usage.bytes + grows > quota) || usage.docs + added > MAX_DOCS_PER_ACCOUNT) { refused++; continue; }
    usage.bytes += grows;
    usage.docs += added;
    writes.push({ doc, deleted, payload, grows, added, incomingAt: Math.floor(new Date(doc.updatedAt).getTime() / 1000) || now() });
  }

  // Each document takes its revision and is written in one transaction, three
  // statements that nothing else can come between. Taken separately, a device
  // pulling in the gap could see a later revision land before this one and
  // move its cursor past it - and never be sent this document at all.
  //
  // The compare-and-set is the upsert's own WHERE clause: a row that has moved
  // on since the revision the device quoted changes nothing and reports zero.
  // The kind of a tombstone is kept from the row it deletes, since a tombstone
  // is sent without knowing what it was a tombstone FOR, and must not relabel
  // a folder as a set on its way out.
  let full = false;
  for (let i = 0; i < writes.length; i += WRITE_CHUNK) {
    const part = [];
    for (const w of writes.slice(i, i + WRITE_CHUNK)) {
      // the database is nearly full: only what shrinks it goes on
      if (full && w.grows > 0) { refused++; continue; }
      part.push(w);
    }
    if (!part.length) continue;
    const statements = [];
    for (const w of part) {
      const kind = w.doc.kind || null;
      statements.push(
        env.DB.prepare(
          `INSERT INTO sync_state (account_id, rev) VALUES (?, 1)
           ON CONFLICT(account_id) DO UPDATE SET rev = rev + 1
           RETURNING rev`).bind(account),
        env.DB.prepare(
          `INSERT INTO docs (account_id, id, kind, rev, updated_at, deleted, payload)
           VALUES (?, ?, COALESCE(?, 'set'), (SELECT rev FROM sync_state WHERE account_id = ?), ?, ?, ?)
           ON CONFLICT(account_id, id) DO UPDATE SET
             kind = CASE WHEN excluded.deleted = 1 THEN docs.kind ELSE COALESCE(?, docs.kind) END,
             rev = excluded.rev, updated_at = excluded.updated_at,
             deleted = excluded.deleted, payload = excluded.payload
           WHERE docs.rev <= ?`)
          .bind(account, w.doc.id, kind, account, w.incomingAt, w.deleted, w.payload, kind, Number(w.doc.rev) || 0),
        // counted only when the write above landed: the row now carries the
        // revision this transaction just took
        env.DB.prepare(
          `UPDATE doc_usage SET bytes = MAX(0, bytes + ?), docs = docs + ?
           WHERE account_id = ? AND EXISTS (SELECT 1 FROM docs WHERE account_id = ? AND id = ?
             AND rev = (SELECT rev FROM sync_state WHERE account_id = ?))`)
          .bind(w.grows, w.added, account, account, w.doc.id, account),
      );
    }
    const results = await env.DB.batch(statements);
    part.forEach((w, n) => {
      const rev = results[3 * n].results?.[0]?.rev;
      const written = results[3 * n + 1];
      const size = Number(written?.meta?.size_after) || 0;
      if (size > dbLimit) full = true;
      // Somebody else got there between our read and our write. Send back
      // whatever is actually there now, exactly as the fast path does.
      if (!written?.meta || written.meta.changes === 0) { stale.push(w.doc.id); return; }
      const before = existing.get(w.doc.id);
      const kind = w.deleted ? (before?.kind || w.doc.kind || 'set') : (w.doc.kind || before?.kind || 'set');
      accepted.push({ ...w.doc, kind, rev, deleted: !!w.deleted, payload: w.payload });
    });
  }

  for (const id of stale) {
    const current = await env.DB.prepare(
      'SELECT rev, updated_at, kind, deleted, payload FROM docs WHERE account_id = ? AND id = ?')
      .bind(account, id).first();
    if (current) conflicts.push(conflictOf(id, current));
  }

  // Nothing could be kept for want of room: say so, rather than answer as if
  // the device had sent nothing.
  if (refused && !accepted.length && !conflicts.length) {
    return json({ error: 'This library is too large to sync.' }, 507);
  }
  return json({ accepted, conflicts });
}

// MARK: pictures

/// Names checked against R2 per call, and per account per day. Each check is
/// one billed R2 operation, so a device (or a script) asking the same
/// question in a loop must not be able to run the bill up.
const CHECKS_PER_CALL = 500;
const CHECKS_PER_DAY = 50_000;

/// Adds `n` to a per-day counter, all or nothing, while it stays within
/// `limit` (the same table and statement shape as the AI allowances).
async function count(env, name, n, limit) {
  if (n <= 0) return true;
  const result = await env.DB.prepare(
    `INSERT INTO ai_usage (account_id, day, requests) VALUES (?, ?, ?)
     ON CONFLICT (account_id, day) DO UPDATE SET requests = requests + excluded.requests
     WHERE requests + excluded.requests <= ?`)
    .bind(name, new Date().toISOString().slice(0, 10), n, limit).run();
  return n <= limit && (result.meta?.changes ?? 0) > 0;
}

export async function missingBlobs(env, account, body) {
  const wanted = [...new Set((Array.isArray(body.names) ? body.names : []).filter(isHash))];
  // Only so many are looked up in one call. The rest are reported missing,
  // never present: a device that uploads a picture the server already has
  // costs one upload (putBlob sees it is there and stores nothing), while a
  // picture wrongly reported present would never be uploaded at all, and every
  // other device would ask for it and fail for ever.
  const checked = wanted.slice(0, CHECKS_PER_CALL);
  const unchecked = wanted.slice(CHECKS_PER_CALL);
  if (!await count(env, `blobcheck:${account}`, checked.length, finite(env.BLOB_CHECKS_DAILY, CHECKS_PER_DAY))) {
    return json({ error: "That's today's picture checks used. Pictures carry on syncing tomorrow." }, 429);
  }
  // Asked all at once. Five hundred of these one after another is five hundred
  // round trips before the first byte of the first picture moves, which on a
  // reinstall is the whole delay the student sees.
  // in groups of 40: a Worker may only make so many calls at once, and a
  // name dropped here would be reported as present
  const found = [];
  for (let i = 0; i < checked.length; i += 40) {
    found.push(...await Promise.all(checked.slice(i, i + 40).map(name => env.BLOBS.head(key(account, name)))));
  }
  const missing = checked.filter((_, i) => !found[i]).concat(unchecked);
  return json({ missing });
}

/// Pictures one account may hold, by count as well as by bytes: a byte
/// budget alone lets a million tiny files in.
const MAX_BLOBS = 60_000;
/// How long a running total is trusted before R2 is listed to correct it.
const RECOUNT_SECONDS = 24 * 60 * 60;

export async function putBlob(env, account, name, request, budget = Infinity) {
  if (!isHash(name)) return json({ error: 'bad name' }, 400);
  // refused on its declared size before it is read into memory
  const declared = Number(request.headers?.get?.('content-length')) || 0;
  if (declared > 12 * 1024 * 1024) return json({ error: 'too big' }, 413);
  const data = await request.arrayBuffer();
  if (data.byteLength > 12 * 1024 * 1024) return json({ error: 'too big' }, 413);

  // Already here: the same bytes under the same name, so there is nothing to
  // store and nothing to count. Checked before the budget so that a retry of an
  // upload that already succeeded can never be the thing that trips it.
  const already = await env.BLOBS.head(key(account, name));
  if (already) return json({ ok: true });

  // The name has to be the hash of what arrived. Without this check a caller
  // could park anything under any address, and every device that later asked
  // for that picture would get the wrong bytes - for ever, because nothing
  // would ever re-fetch a blob it believes it already has.
  const digest = await crypto.subtle.digest('SHA-256', data);
  const actual = [...new Uint8Array(digest)]
    .map(b => b.toString(16).padStart(2, '0')).join('');
  if (actual !== name) return json({ error: 'that is not its hash' }, 400);

  // The space is claimed before the write, in one conditional statement, so
  // uploads arriving together cannot all pass a check none of them has yet
  // written past.
  const limited = budget < Infinity;
  if (limited && !await claim(env, account, data.byteLength, budget)) {
    return json({ error: 'This account has run out of picture storage.' }, 507);
  }
  try {
    await env.BLOBS.put(key(account, name), data);
  } catch (error) {
    // not stored, so not counted
    if (limited) await release(env, account, data.byteLength).catch(() => {});
    throw error;
  }
  return json({ ok: true });
}

/// Takes `bytes` (and one picture) from the account's allowance, or refuses.
///
/// Kept as a running total rather than counted by listing R2 on every upload,
/// which made a whole library's upload cost the square of its size in R2
/// calls. A total can drift (an upload that half fails, two uploads of the
/// same new picture at once), so once a day it is corrected from a listing.
async function claim(env, account, bytes, budget) {
  const row = await env.DB.prepare('SELECT counted_at FROM blob_usage WHERE account_id = ?').bind(account).first();
  if (!row || now() - (Number(row.counted_at) || 0) > RECOUNT_SECONDS) {
    const held = await listed(env, account);
    await env.DB.prepare(
      `INSERT INTO blob_usage (account_id, bytes, objects, counted_at) VALUES (?, ?, ?, ?)
       ON CONFLICT (account_id) DO UPDATE SET bytes = excluded.bytes, objects = excluded.objects, counted_at = excluded.counted_at`)
      .bind(account, held.bytes, held.objects, now()).run();
  }
  const taken = await env.DB.prepare(
    `UPDATE blob_usage SET bytes = bytes + ?, objects = objects + 1
     WHERE account_id = ? AND bytes + ? <= ? AND objects < ?`)
    .bind(bytes, account, bytes, budget, finite(env.MAX_BLOBS_PER_ACCOUNT, MAX_BLOBS)).run();
  return (taken.meta?.changes ?? 0) > 0;
}

async function release(env, account, bytes) {
  await env.DB.prepare(
    'UPDATE blob_usage SET bytes = MAX(0, bytes - ?), objects = MAX(0, objects - 1) WHERE account_id = ?')
    .bind(bytes, account).run();
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

/// How many pictures, and bytes of them, this account holds in R2 - by
/// listing, which is exact but costs a call per thousand pictures, so it is
/// only the once-a-day correction of the running total (see claim).
async function listed(env, account) {
  let bytes = 0, objects = 0;
  let cursor;
  do {
    const page = await env.BLOBS.list({ prefix: `${account}/`, cursor });
    for (const object of page.objects) { bytes += object.size || 0; objects += 1; }
    cursor = page.truncated ? page.cursor : undefined;
  } while (cursor);
  return { bytes, objects };
}

function isHash(name) { return /^[0-9a-f]{64}$/.test(name || ''); }

// MARK: leaving

/// Everything belonging to an account, gone: its documents and their
/// counters, its pictures, and the lines read aloud for it (tts.js keeps them
/// under tts/<account>/).
export async function wipe(env, account) {
  await env.DB.prepare('DELETE FROM docs WHERE account_id = ?').bind(account).run();
  await env.DB.prepare('DELETE FROM sync_state WHERE account_id = ?').bind(account).run();
  await env.DB.prepare('DELETE FROM doc_usage WHERE account_id = ?').bind(account).run();
  await env.DB.prepare('DELETE FROM blob_usage WHERE account_id = ?').bind(account).run();
  if (!env.BLOBS) return; // deployed without picture storage
  // R2 has no "delete by prefix", so the keys have to be listed and removed in
  // batches. A page at a time, because an account with a term of lectures in it
  // has thousands.
  for (const prefix of [`${account}/`, `tts/${account}/`]) {
    let cursor;
    do {
      const page = await env.BLOBS.list({ prefix, cursor });
      if (page.objects.length) {
        await env.BLOBS.delete(page.objects.map(o => o.key));
      }
      cursor = page.truncated ? page.cursor : undefined;
    } while (cursor);
  }
}
