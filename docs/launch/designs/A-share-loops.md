> **Source design, feature group A** (architect output, 2026-09-24), copied verbatim.
> It is an input to [`../implementation-plan.md`](../implementation-plan.md). Where the two disagree, **the plan wins**:
> see the plan's section 2 (conflict resolutions) and the work package that implements this design.

# Feature group A (share loops): implementation design

## Before you start: facts from the code that change the design

1. **Cloudflare R2 is not switched on for this account.** Listing R2 buckets returns `403 code 10042 "Please enable R2 through the Cloudflare Dashboard"`. `worker-deploy.yml` removes the `[[r2_buckets]]` binding when R2 is missing, so `env.BLOBS` is undefined in production. Shared sets therefore have to work with D1 only. R2 is used automatically if it is ever turned on.
2. **Workers free-plan limits matter here.** Each invocation gets about 10 ms of CPU and at most 50 D1 queries. D1 rows are capped at 2 MB, SQL statements at 100 KB, bound parameters at 100 per query, and a free database at 500 MB (5 GB per account). Every route below stays within these.
3. **Many students share one campus address.** `/auth/device` allows 5 new accounts per IP per hour (`DEVICES_PER_HOUR`). A lecture hall on one NAT'd Wi-Fi address joining a class would hit that limit after 5 students. Account creation reached through a valid invite code needs its own, much larger limit (see 5.3).
4. **"Start without an account" makes a local-only session with no server account** (`Session.localToken`, `useThisDeviceOnly`). So receiving a shared set must not need a server account. Classes and leaderboards need one, created through `AccountStore.ensureServerSession()`.
5. **`Store.addSet` does not clear `tombstones[id]`.** Imports use deterministic IDs, so re-importing a deleted set needs a dedicated `Store.importShared` that clears the tombstone and stamps `updatedAt`.
6. **Pictures are stored inside the set.** `StudySet.images` is an index-addressed base64 pool. Only `MCQQuestion.imageIndex` and `AnkiCard.imageIndex` point into it. `OcclusionBox` coordinates are normalised to 0–1, so pictures can be shrunk before sharing without breaking occlusion cards.
7. **Swift Playgrounds.** `AppleProductTypes.iOSApplication` has no entitlements, so there are no associated domains and no universal links there. It does have `additionalInfoPlistContentFilePath`, which can carry `CFBundleURLTypes`, so the existing `redpen://` scheme can probably work in Playgrounds. That needs checking on a device (see 4.3).
8. **No Apple Team ID exists anywhere in the repo.** The apple-app-site-association file (AASA) needs it. Section 9 shows how it gets filled in without the owner typing it.
9. **Workers Rate Limiting binding (`[[ratelimits]]`, period 10 or 60 s) is GA with no extra charge.** The docs don't say explicitly whether the free plan has it, so the code falls back to the existing D1 counters (`pair_attempts` / `allowed()`) when the binding is absent.
10. **Guideline 1.2 (user-generated content) applies to all of group A.** It requires a filter for objectionable material, a report mechanism with timely responses, the ability to block abusive users, and published contact information. This is the main review risk; see section 7.

## 1. Product behaviour

### A1. Share a set as a link
- Where: the set's context menu → **Share link…**.
  - Options: "Include lecture text" (off by default) and "Show my name as publisher" (off by default).
  - The first time, the user accepts the Community rules sheet.
  - Output: `https://<worker>/s/K7QMX2PAHD`, shared through SwiftUI `ShareLink` with the message "<title> — 40 questions on Vignette".
- **Receiver with the app installed**:
  - The universal link opens the app, which shows a preview sheet (title, type, count, publisher if shown, "Report").
  - **Add to library** imports a copy. No server account is needed.
- **Receiver without the app** gets a Worker web page with:
  - Title, count, type, and an "Open in Vignette" button (`redpen://s/CODE`).
  - An App Store badge. Tapping it also copies the link to the clipboard. After install, the app's empty library offers a `PasteButton`: "Open the set you were sent". This is deferred deep linking without fingerprinting.
  - A Smart App Banner with `app-argument`.
  - Before the app is live, the page says "Coming soon to the App Store".
- **Updates**:
  - The publisher's menu shows **Update shared link** when the set changed since it was last published. This makes a new version on the same URL.
  - Receivers check versions on launch and when foregrounded (throttled to every 6 h), and in the background on the Xcode build. "Updated by publisher" merges the new version while keeping the receiver's own edits and review progress (see 3.4).
- **Revoke**: the publisher's "Stop sharing" makes the link 410. Copies already imported stay on devices but stop updating.
- Re-sharing an imported set shares the original link, so the lecturer can still revoke it. Only your own sets can be published.

### A2. Lecturer → class
- **Classes & groups** screen (Library toolbar) → **New class**: name plus a leaderboard toggle (off by default for classes).
  - Output: join link `https://<worker>/j/9FJ2KQ7MWT` and a co-lecturer link, which carries a separate admin code.
- **Lecturer controls**:
  - **Add set to class** attaches a set from their library, publishing it if needed.
  - **Update for class** republishes, and every member gets the new version.
  - **Remove from class**, **Rotate join link**, **Close joining**, **Delete class**.
  - The lecturer sees the member count only, never a member list (privacy). They can remove a member by handle only from leaderboard rows or reports.
- **Members**:
  - Opening the join link creates a device account silently if needed, through the invite limit.
  - New class sets are auto-added to a library folder named after the class. There is a setting to turn auto-add off, in which case they appear as "New in <class>" in the class screen.
  - A local notification says "Dr Salma added 'Cardiology wk 3' to MBBS Y2". It is fired from background refresh on the Xcode build, or on foreground in Playgrounds.
  - No APNs, so the owner has no push key to create.
- Leaving a class keeps the imported sets but stops their updates.

### A3. Study-group leaderboards
- **Study group**: made by any student. Leaderboard on by default for the group, but every member must opt in individually.
  - To appear, a member picks a display name for that group (2–24 characters, filtered). Pseudonyms are fine; the account name is never used.
- **What is shown**: weekly (ISO week) **questions/cards answered** and **active days (0–7)**, ranked by answered, then active days.
  - Accuracy and time studied are never uploaded.
  - No prizes, ever (keeps it clear of 5.3 contests).
- **Controls**:
  - Tapping a row gives Report or Block. Block hides that person in every group for you and filters your rows from them.
  - "Hide me" (opt out) takes effect at once.
  - Stats older than 8 weeks are deleted.
- **Upload rule**: stats go up once per account per device, never per group, and only while the account is opted in to at least one leaderboard (data minimisation).

## 2. Data model: D1 (`server/schema.sql` additions, all `CREATE … IF NOT EXISTS`)

Do not put semicolons inside comments: the test harnesses split the file on `;`.

```sql
-- A published copy of one set. Anyone with the code can read it.
CREATE TABLE IF NOT EXISTS shares (
  id             TEXT PRIMARY KEY,            -- uuid
  code           TEXT NOT NULL UNIQUE,        -- 10 chars, pair.js alphabet (31^10, ~49 bits)
  owner_id       TEXT NOT NULL,               -- accounts.id
  set_id         TEXT NOT NULL,               -- the publisher's own StudySet.id
  kind           TEXT NOT NULL,               -- StudySetKind raw value
  title          TEXT NOT NULL,               -- <= 120, filtered
  subject        TEXT,                        -- <= 60, filtered
  item_count     INTEGER NOT NULL DEFAULT 0,
  image_count    INTEGER NOT NULL DEFAULT 0,
  publisher_name TEXT,                        -- null unless the publisher chose to show it
  version        INTEGER NOT NULL DEFAULT 0,  -- live version, 0 = never committed
  pending        INTEGER NOT NULL DEFAULT 0,  -- version uploaded but not yet committed
  bytes          INTEGER NOT NULL DEFAULT 0,  -- manifest + pictures, live version
  storage        TEXT NOT NULL DEFAULT 'd1',  -- d1 | r2 (where its bytes are)
  status         TEXT NOT NULL DEFAULT 'pending', -- pending | live | revoked | suspended | removed
  fingerprint    TEXT,                        -- sha256 of normalised lecture text (group D cache hook)
  imports        INTEGER NOT NULL DEFAULT 0,  -- manifest fetches with ?count=1, approximate
  created_at     INTEGER NOT NULL,
  updated_at     INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS shares_by_owner ON shares (owner_id);
CREATE UNIQUE INDEX IF NOT EXISTS shares_owner_set ON shares (owner_id, set_id);
CREATE INDEX IF NOT EXISTS shares_by_fingerprint ON shares (fingerprint) WHERE fingerprint IS NOT NULL;

-- Class and study-group, one table. kind: class | study
CREATE TABLE IF NOT EXISTS groups (
  id           TEXT PRIMARY KEY,
  kind         TEXT NOT NULL,
  name         TEXT NOT NULL,                 -- <= 60, filtered
  owner_id     TEXT NOT NULL,
  join_code    TEXT NOT NULL UNIQUE,          -- 10 chars
  admin_code   TEXT NOT NULL UNIQUE,          -- 10 chars, joins as admin (co-lecturer)
  join_open    INTEGER NOT NULL DEFAULT 1,
  leaderboard  INTEGER NOT NULL DEFAULT 0,    -- class default 0, study default 1
  status       TEXT NOT NULL DEFAULT 'live',  -- live | suspended | removed
  rev          INTEGER NOT NULL DEFAULT 0,    -- bumped on any set add/update/remove
  licence_id   TEXT,                          -- reserved for group B group licences, A never reads it
  created_at   INTEGER NOT NULL,
  updated_at   INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS groups_by_owner ON groups (owner_id);

CREATE TABLE IF NOT EXISTS group_members (
  group_id     TEXT NOT NULL,
  account_id   TEXT NOT NULL,
  role         TEXT NOT NULL DEFAULT 'member', -- owner | admin | member
  handle       TEXT NOT NULL,                  -- hex16 HMAC(SESSION_SECRET, group_id:account_id), per-group pseudonym
  display_name TEXT,                           -- per group, filtered, null until chosen
  on_board     INTEGER NOT NULL DEFAULT 0,     -- leaderboard opt-in
  joined_at    INTEGER NOT NULL,
  PRIMARY KEY (group_id, account_id)
);
CREATE INDEX IF NOT EXISTS group_members_by_account ON group_members (account_id);
CREATE UNIQUE INDEX IF NOT EXISTS group_members_handle ON group_members (group_id, handle);

CREATE TABLE IF NOT EXISTS group_sets (
  group_id  TEXT NOT NULL,
  share_id  TEXT NOT NULL,
  rev       INTEGER NOT NULL,                  -- groups.rev at the moment of the last change
  added_by  TEXT NOT NULL,
  added_at  INTEGER NOT NULL,
  removed   INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (group_id, share_id)
);
CREATE INDEX IF NOT EXISTS group_sets_by_share ON group_sets (share_id);

-- Weekly counts, per account per device, so a phone and an iPad add up rather than overwrite
CREATE TABLE IF NOT EXISTS weekly_stats (
  account_id TEXT NOT NULL,
  week       TEXT NOT NULL,                    -- ISO week, 2026-W39
  device     TEXT NOT NULL,                    -- random install id (uuid), not a hardware id
  answered   INTEGER NOT NULL DEFAULT 0,
  days_mask  INTEGER NOT NULL DEFAULT 0,       -- bit 0 = Monday ... bit 6 = Sunday
  updated_at INTEGER NOT NULL,
  PRIMARY KEY (account_id, week, device)
);
CREATE INDEX IF NOT EXISTS weekly_stats_by_week ON weekly_stats (week);

CREATE TABLE IF NOT EXISTS blocks (
  account_id TEXT NOT NULL,
  blocked_id TEXT NOT NULL,
  at         INTEGER NOT NULL,
  PRIMARY KEY (account_id, blocked_id)
);

-- Shared with group F (Report an error). Whichever lands first creates it, and the other reuses it.
CREATE TABLE IF NOT EXISTS reports (
  id          TEXT PRIMARY KEY,
  reporter_id TEXT,                            -- null for anonymous (web page) or after the reporter deleted their account
  target_type TEXT NOT NULL,                   -- share | group | member | question | card | case | contact
  target_ref  TEXT NOT NULL,                   -- share code, group id, group_id:handle, or item ref
  reason      TEXT NOT NULL,                   -- abuse | copyright | error | spam | other
  note        TEXT,                            -- <= 1000
  status      TEXT NOT NULL DEFAULT 'open',    -- open | actioned | dismissed
  created_at  INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS reports_open ON reports (status, created_at);
CREATE UNIQUE INDEX IF NOT EXISTS reports_once ON reports (reporter_id, target_type, target_ref) WHERE reporter_id IS NOT NULL;

-- Small server-side settings written by CI (e.g. apple_team_id), overridable by env vars
CREATE TABLE IF NOT EXISTS app_config (
  key   TEXT PRIMARY KEY,
  value TEXT NOT NULL,
  at    INTEGER NOT NULL
);
```

### New `accounts` columns
Add these to the ALTER loop in `worker-deploy.yml`, and to the table definition in `schema.sql` for fresh databases:
- `ugc_terms_at INTEGER NOT NULL DEFAULT 0`: when the account accepted the Community rules. The server refuses publish, create and join without it.
- `share_banned INTEGER NOT NULL DEFAULT 0`: set by an owner action.
- `joined_via TEXT`: the share or group code an account was created through. Group B's referral credits hook; A only records it.

### Byte storage: second D1 database `redpen-shares`, binding `SHARE_STORE`, file `server/share-store.sql`
This keeps the main database's 500 MB for accounts and sync.

```sql
CREATE TABLE IF NOT EXISTS share_manifests (
  share_id TEXT NOT NULL, version INTEGER NOT NULL, part INTEGER NOT NULL,
  data BLOB NOT NULL,                          -- <= 1,800,000 bytes per part
  PRIMARY KEY (share_id, version, part)
);
CREATE TABLE IF NOT EXISTS share_blobs (
  share_id TEXT NOT NULL, hash TEXT NOT NULL,
  bytes INTEGER NOT NULL, data BLOB NOT NULL,  -- <= 1,800,000 bytes (the app downscales to about 300 KB)
  PRIMARY KEY (share_id, hash)
);
```

If `env.BLOBS` (R2) exists, new shares use `storage='r2'` with keys `share/{shareId}/v{n}.json` and `share/{shareId}/b/{hash}`. Old D1 shares stay readable through their `storage` column.

Pictures are stored per share, never across accounts. This follows `sync.js`'s rule that an upload must not reveal whether someone else holds the same bytes.

### Where the storage limits live
Limits are env vars with defaults in `wrangler.toml [vars]`, read through a `limit(env, name, dflt)` helper that group D's remote config can later take over:

| Var | Default |
|---|---|
| `SHARES_PER_ACCOUNT` | 100 |
| `SHARE_MANIFEST_BYTES` | 4,000,000 |
| `SHARE_BLOB_BYTES` | 1,800,000 |
| `SHARE_BYTES_D1` | 8,000,000 per share |
| `SHARE_BYTES_R2` | 30,000,000 per share |
| `SHARE_STORE_SOFT_CAP` | 400,000,000 (D1 total; above it, new picture uploads get 507 and text-only shares still work) |
| `GROUPS_PER_ACCOUNT` | 10 |
| `GROUP_MEMBERS` | 600 |
| `GROUP_SETS` | 300 |
| `PUBLISHES_PER_HOUR` | 20 |
| `JOINS_PER_HOUR` | 20 |
| `INVITE_DEVICES_PER_HOUR` | 300 |

Sharing, classes and leaderboards are free for everyone (it is the growth loop). Group D's flags can gate them later without an app update.

## 3. Wire formats and the app-side pure logic

### 3.1 Codes and links
- **Codes**: 10 characters from `ABCDEFGHJKMNPQRSTUVWXYZ23456789`, generated by rejection sampling (bytes ≥ 248 are dropped, avoiding `pair.js`'s modulo bias, which matters for long-lived codes). Stored upper-case. Input is normalised with the existing `normalise()` extended to 10 characters (new export `normaliseCode(raw, len)`).
- **Links**: `https://<worker>/s/<CODE>` (set), `https://<worker>/j/<CODE>` (join a group; an admin code is also a `/j/` code, and the server knows which it is).
- **Custom scheme**: `redpen://s/<CODE>`, `redpen://j/<CODE>`. The `redpen` scheme is already registered, and `AuthRules` only consumes host `auth`.
- **The app also accepts**: the bare code typed or pasted (10 characters, with or without dashes or spaces), and any text containing one of the URLs (WhatsApp adds text around links).

### 3.2 Manifest (the uploaded set)
- The manifest is the `StudySet` JSON exactly as `JSONEncoder.sync` writes it, with every `images[i]` replaced by `"blob:<sha256hex>"` (existing `BlobRefs.pack`), plus a top-level `"format": 1`.
- Stripped before upload by `SharePacking.outgoing`:
  - `folderId` and `origin`.
  - `sources` unless "Include lecture text" is on. `SourceDoc.fileBlob` is always cleared (a device-local hash).
- Pictures are recompressed first: at most 1600 px on the long side, JPEG quality 0.72, done in `ShareImages.swift` with ImageIO. Normalised occlusion boxes make this safe.

### 3.3 Stable IDs on import
- `SharePacking.incoming(manifest:shareId:code:version:publisher:groupId:)`:
  - Set id = `UUIDv5(ns, "\(shareId):set")`.
  - Every item id (questions, cards, qaCards, osceChecklists, narrateSegments, and `SourceDoc` ids) = `UUIDv5(ns, "\(shareId):\(originalId)")`.
  - `ns` is a fixed namespace UUID constant.
- Why:
  - Re-importing is idempotent.
  - Two of the receiver's devices importing separately converge through sync.
  - IDs stay stable across versions, so `ReviewStore` progress (keyed by card id) survives updates.
  - The receiver's IDs never equal the publisher's, so a lecturer who is also a class member never collides.
- UUIDv5 uses CryptoKit `Insecure.SHA1`. The file stays pure Foundation + CryptoKit, like `BlobRefs`.
- `Store.importShared(_:)`: `tombstones[set.id] = nil`, `updatedAt = Date()`, then append or replace. This is what lets a deleted-then-reimported set win over its tombstone in sync.

### 3.4 `StudySet.origin` (new optional field, travels with sync)

```swift
struct ShareOrigin: Codable, Hashable {
    var shareId: String          // server uuid
    var code: String
    var version: Int
    var publisher: String?       // publisher_name as shown, may be nil
    var groupId: String?         // set when it arrived through a class/group
    var importedHash: String     // SharePacking.contentHash of the set as imported/last updated
    var importedAt: Date
}
```

- Add `origin` to `StudySet`'s `Keys` and to its tolerant `init(from:)`: `origin = try c.decodeIfPresent(ShareOrigin.self, forKey: .origin)`.
- `contentHash` is SHA-256 of `JSONEncoder` with `.sortedKeys` over the set, with `id`, `createdAt`, `updatedAt`, `folderId` and `origin` blanked.

**Update merge**: `ShareMerge.apply(base: StudySet?, local: StudySet, remote: StudySet) -> (set, stats{added, changed, removed, keptLocal})`. It is pure and tested.
- **Base** is the previously imported manifest, cached at `Application Support/shares/<shareId>.json`. On a device without the cache, base is nil.
- **With a base, per collection, keyed by id**:
  - Remote item not in base and not in local → add.
  - In local and base, local == base → take remote.
  - Local ≠ base → keep local and count `keptLocal`.
  - In base but not remote → remove, unless locally edited.
  - In local only → the user's own addition, keep it.
  - Order: remote order, then local additions.
  - `bookMarkdown` and `name` follow the same three-way rule.
- **With no base**:
  - `contentHash(local) == origin.importedHash` → take remote wholesale (keeping the mapped IDs).
  - Otherwise treat every differing item as locally edited.
- **Pictures**: afterwards the pool is rebuilt from the pictures referenced by the final items (remote pool for remote items, local pool for kept ones), de-duplicated by `BlobRefs.name`, and `imageIndex` is remapped. Only `MCQQuestion` and `AnkiCard` have `imageIndex` today. Add a unit test that fails if a new model gains `imageIndex` without merge support.

### 3.5 Weekly stats (pure)
- `WeeklyStats.compute(days: [String: Int], now: Date, calendar: Calendar(identifier: .iso8601) in the user's time zone) -> (week: "YYYY-Www", answered: Int, daysMask: Int)`.
- It reads `StudyLog.days` (`"2026-09-24": 32`). Also compute the previous week, sent once on the first launch after a week ends.

### 3.6 Name rules (pure, the same in Swift and JS)
- Steps:
  1. NFKC.
  2. Strip zero-width and bidi control characters (U+200B–U+200F, U+202A–U+202E, U+2066–U+2069).
  3. Collapse whitespace and trim.
  4. Length 2–24 for display names, 1–120 for titles, 1–60 for group names.
- Reject:
  - URLs or domain-like strings (`\b\w+\.(com|net|org|io|app|me|ly|gg)\b`, `http`, `www`).
  - `@handles`.
  - More than 6 digits (phone numbers).
  - Anything matching a small English + Arabic (including Egyptian-colloquial) blocklist, compared after normalising Arabic letter variants (أ/إ/آ→ا, ة→ه, ى→ي) and removing tashkeel.
- The shared test vectors in `server/tests/fixtures/name-rules.json` are read by both the JS and Swift suites, so the two implementations can't drift.

## 4. Worker routes

New modules:
- `server/share.js`: publish, commit, public reads, versions, revoke, mine, limits, terms.
- `server/groups.js`: groups, feed, leaderboard, stats.
- `server/moderation.js`: reports, blocks, owner review and takedown; shared with group F.
- `server/names.js`: the name rules.
- `server/sharepage.js`: HTML pages, AASA, robots, og image.
- `server/storage.js`: a D1/R2 backend with `putManifest`, `getManifest`, `hasBlob`, `putBlob`, `getBlob` and `deleteShare`.

Auth reuses `holder()` / `guarded()` in `worker.js`. Owner checks reuse `isOwnerKey()`, `accounts.owner = 1` or `OWNER_ACCOUNT_IDS`, through a new `isOwnerAccount(env, id)` in `moderation.js`. All JSON errors use the existing `fail(status, message)` shape `{error, message}`.

### 4.1 Changes to `worker.js` (minimal diff, since another job is editing it)
Coordinate by adding blocks rather than restructuring:

- **A. Before the POST-only check**, next to the `/blobs/` and `/jobs` blocks:

```js
if (request.method === 'GET' || request.method === 'HEAD') {
  const page = await publicRoute(request, env, path);   // sharepage.js + share.js reads
  if (page) return page;
}
if (path.startsWith('/share-blobs/')) return await guarded(request, env, id => shareBlobPut(request, env, id, path));
```
- **B. The body-size map**: `path === '/shares/publish' ? 5 * 1024 * 1024`.
- **C. Switch cases**: one line each, forwarding to the module functions below (all POST, JSON, like the existing style).
- **D. `/auth/device`**: pass `body.via` into `deviceAccount` (see 5.3).
- **E. `deleteAccount`**: `await wipeSocial(env, id)` before deleting the account row.

### 4.2 Share routes

**`POST /shares/limits`** (auth, any account)
- Response:
```
200 { termsAccepted: bool, banned: bool, images: bool, maxManifestBytes, maxBlobBytes, maxShareBytes, sharesUsed, sharesMax }
```
- `images` is false when the D1 soft cap is reached. The app then says "Pictures can't be shared right now; N picture cards will be left out", and publishing still works without them.

**`POST /shares/terms`** (auth)
- Request: `{ version: 1 }`
- Response: `200 { ok: true }`. Sets `accounts.ugc_terms_at = now`.

**`POST /shares/publish`** (auth, body ≤ 5 MB)
- Request:
```
{ shareId?: uuid,                 // present = new version of an existing share
  setId: uuid, kind: "mcq"|"anki"|"book"|"qa"|"osce"|"narrate",
  title: string, subject?: string, publisherName?: string|null,
  fingerprint?: hex64, manifest: <object, see 3.2> }
```
- Server steps:
  1. Terms accepted, not `share_banned`, rate limit `publish:<acct>` `PUBLISHES_PER_HOUR`.
  2. `shareId` must be the caller's; otherwise (caller, setId) finds or creates a share through `shares_owner_set`.
  3. Count ≤ `SHARES_PER_ACCOUNT`.
  4. Name rules on title, subject and publisherName.
  5. Manifest checks: an object with `format === 1`, `kind` in the allowed set, and `images` only `blob:<64 hex>` strings (≤ 150).
  6. The server extracts the blob list itself. It never trusts a client list.
  7. `item_count` is computed from array lengths.
  8. Re-serialised size ≤ `SHARE_MANIFEST_BYTES`.
  9. The manifest is stored as version `pending = version + 1`, in parts of 1.8 MB.
  10. `missing` = hashes not yet stored for this share.
- Response:
```
200 { shareId, code, url, pendingVersion, missing: [hash] }
```
- Errors:

| Status | When |
|---|---|
| 400 | Shape |
| 403 | `"Accept the community rules first."` / banned |
| 409 | Not your share |
| 413 | Too large |
| 422 | `{ field: "title", message: "That name isn't allowed." }` |
| 429 | Rate limited |
| 507 | Storage full |

**`PUT /share-blobs/{shareId}/{hash}`** (auth, raw body, `content-length` required, ≤ `SHARE_BLOB_BYTES`)
- Owner of the share only. SHA-256 of the body must equal `hash` (same rule as `sync.js putBlob`). Idempotent if already present.
- Running total ≤ `SHARE_BYTES_D1` or `SHARE_BYTES_R2`.
- Response: `200 { ok: true }`. Errors: 400, 403, 411, 413, 507.
- Optimisation when R2 exists: `/shares/publish` copies any missing hash already under the owner's own sync prefix `${account}/${hash}` server-side, so it is not uploaded twice.

**`POST /shares/commit`** (auth)
- Request: `{ shareId, version }`, where `version` must equal `pending`.
- Server steps:
  1. Every blob the manifest references must exist, otherwise `409 { missing: [...] }`.
  2. In one `DB.batch`: set `version = pending`, `status = 'live'`, `bytes`, `updated_at`.
  3. Bump the feed of every group holding the share: `UPDATE groups SET rev = rev + 1 … WHERE id IN (SELECT group_id FROM group_sets WHERE share_id = ? AND removed = 0)`, then set `group_sets.rev` from `groups.rev`.
  4. Delete manifest versions older than `version - 1` (keep one for rollback).
  5. Delete blobs no longer referenced by the last two versions (bounded work: a single `DELETE … WHERE hash NOT IN (json_each(?))`).
- Response: `200 { shareId, code, version, url }`

**`POST /shares/mine`** (auth)
- Response:
```
200 { shares: [{ shareId, code, setId, title, kind, version, status, imports, updatedAt, groups: [groupId] }] }
```

**`POST /shares/revoke`** (auth, owner of the share)
- Request: `{ shareId }`
- Sets status `revoked`, deletes storage, marks `group_sets.removed = 1` and bumps those groups' `rev`, and purges cached public URLs (`caches.default.delete` for the meta and manifest URLs).
- Response: `200 { ok: true }`

**`POST /shares/versions`** (public, rate limited by IP)
- Request: `{ codes: [CODE] }` (≤ 200)
- Response:
```
200 { versions: { CODE: { version, status } } }     // unknown codes are omitted
```
- One `SELECT … WHERE code IN (…)`, chunked to fit the 100-parameter limit.

**Public reads** (GET/HEAD, no auth; handled in `publicRoute`):

| Route | Returns |
|---|---|
| `GET /s/{code}` | HTML page (4.4). Unknown: 404 page. revoked, suspended or removed: 410 page "This set is no longer available". |
| `GET /s/{code}.json` | `200 { code, title, subject, kind, itemCount, imageCount, publisherName, version, updatedAt }` (404/410). `cache-control: public, max-age=60`. |
| `GET /s/{code}/v/{n}.json` | The manifest bytes, only for `n` equal to the live version or the one before (so a client racing an update still succeeds). `content-type: application/json`, `x-content-type-options: nosniff`, `cache-control: public, max-age=86400, immutable`, served through `caches.default`. `?count=1` increments `imports` (the app sends it on first import only). 410 when not live. |
| `GET /s/{code}/b/{hash}` | Picture bytes. `content-type: application/octet-stream`, `nosniff`, `content-disposition: attachment`, immutable cache. The share must be live; the status is checked on a cache miss only, and a revoke purges. |

Serving user bytes as octet-stream with nosniff is what stops a user-uploaded "picture" from being rendered as HTML on the same origin as the AASA file.

### 4.3 Group routes (all POST, auth)

**`POST /groups/create`**
- Request: `{ kind: "class"|"study", name, leaderboard?: bool }`
- Checks: terms accepted, not banned, ≤ `GROUPS_PER_ACCOUNT` owned.
- Response: `200 { group: GroupDTO, joinUrl, adminUrl }`

GroupDTO:
```
{ id, kind, name, role, members, sets, joinOpen, leaderboard, rev,
  joinCode?, adminCode?,                // only for owner (adminCode) / owner+admin (joinCode)
  me: { handle, displayName, onBoard } }
```

**`POST /groups/join`**
- Request: `{ code, displayName?: string }`
- Checks:
  - Terms accepted.
  - Rate limit `join:<acct>` `JOINS_PER_HOUR` plus the IP wrong-code counter (`allowed(env, ip, 'groupcode', 30)`; a correct code refunds it, as in `pair.js`).
  - Code is `join_code` (role member) or `admin_code` (role admin).
  - `join_open` (admin codes ignore it), member count < `GROUP_MEMBERS`, group live.
  - `handle` = hex16 HMAC-SHA256(SESSION_SECRET, `${groupId}:${accountId}`).
- Idempotent: joining again returns the group and can upgrade member → admin with an admin code.
- Response: `200 { group }`. Errors: 404 wrong or expired code, 403 joining closed, 409 full, 429.

**`GET /j/{code}` (HTML) and `GET /j/{code}.json`** (public)
- JSON: `{ name, kind, members, sets }`. Admin codes render the same page with "Join as co-lecturer".

**`POST /groups/mine`** → `200 { groups: [GroupDTO] }`

**`POST /groups/feed`** (called by every member's app on sync)
- Request: `{ since: { groupId: rev } }`
- Response:
```
200 { groups: [{ id, rev, name, sets: [{ shareId, code, version, title, kind, itemCount, addedAt, removed }] }],
      gone: [groupId] }       // groups the caller is no longer in, or that were deleted or removed
```
- One query over the caller's memberships. It returns full set lists only for groups whose `rev` differs from `since`, so it is cheap when nothing changed. `removed` rows are included once so members can drop "new" badges. Their imported copies are kept.

**`POST /groups/sets/add`** (owner or admin)
- Request: `{ groupId, shareId }`. The share must be the caller's own and live.
- ≤ `GROUP_SETS`. Bumps `rev`.
- Response: `200 { rev }`

**`POST /groups/sets/remove`** (owner or admin, or the share's owner)
- Request: `{ groupId, shareId }` → `200 { rev }`

**`POST /groups/update`**
- Request: `{ groupId, name?, joinOpen?, leaderboard?, rotate?: "join"|"admin" }`
- Owner or admin, except `leaderboard` and `rotate: "admin"`, which are owner only. Rotating makes the old link 404.
- Response: `200 { group }`

**`POST /groups/me`**
- Request: `{ groupId, displayName?, onBoard? }`. `onBoard: true` needs a valid displayName (stored or given).
- Response: `200 { me }`

**`POST /groups/members/remove`** (owner or admin; cannot remove the owner)
- Request: `{ groupId, handle }` → `200 { ok }`

**`POST /groups/leave`**
- Request: `{ groupId }`. The owner gets 409 "Delete the class or make a co-lecturer the owner first".
- **`POST /groups/transfer`** `{ groupId, handle }`: owner → an existing admin.

**`POST /groups/delete`** (owner)
- Request: `{ groupId }`. Deletes the group, its members and group_sets. Shares themselves are untouched. Members see it in `gone`.

**`POST /stats/week`**
- Request: `{ week: "2026-W39", device: uuid, answered: int, daysMask: int }`
- Checks:
  - `week` is the current ISO week in UTC, or the previous one within 36 h of its end (±1 day tolerance for time zones). Else 422.
  - `0 ≤ daysMask < 128`.
  - `answered ≤ 3000 × popcount(daysMask)`.
  - If the account has no `on_board = 1` membership: `200 { ok: true, stored: false }` and nothing is stored.
- Storage: upsert with `answered = MAX(answered, ?)`, `days_mask = days_mask | ?` (monotonic, so a device can't lower or erase).
- Rate limit 30 per hour per account.
- 1 call in 50 also runs `DELETE FROM weekly_stats WHERE week < ?` (8 weeks back), so no cron is needed.
- Response: `200 { ok: true, stored: bool }`

**`POST /groups/leaderboard`** (member)
- Request: `{ groupId, week?: "current"|"previous" }`
- 403 if leaderboards are off.
- Rows: opted-in members' `weekly_stats` for that week, aggregated in JS (sum `answered`, OR the masks, `activeDays` = popcount). Excluded: anyone the caller blocked and anyone who blocked the caller.
- Response:
```
200 { week, rows: [{ rank, handle, name, answered, activeDays, me: bool }], optedIn: n, members: n }
```
- Top 50 plus the caller's own row if lower. No account ids, no emails, no other weeks.

### 4.4 Moderation routes (`moderation.js`, shared with group F)

**`POST /reports`**
- Request: `{ targetType, targetRef, reason, note? }`
- Auth is optional: signed-out web page reports go through IP rate limit 10/h; authenticated ones through 30/h per account. Duplicates are ignored by `reports_once`.
- Auto-suspend: when a share or group collects `abuse` or `copyright` reports from **3 distinct accounts**, its status becomes `suspended` (410 to everyone) until the owner reviews it.
- Response: `200 { ok: true }`

**Blocks**
- `POST /blocks/add` `{ groupId, handle }`: resolves the handle to an account server-side, stores `blocks(account_id, blocked_id)`.
- `POST /blocks/remove` `{ blockId }`.
- `POST /blocks/list` → `{ blocks: [{ blockId, name, since }] }`, where `blockId` is an HMAC of the pair (the raw blocked account id is never sent).

**Owner only** (403 otherwise; also allowed with the owner key):
- `POST /owner/reports` `{ status?: "open", before?: ts }` → `{ reports: [...], shares: {code: meta}, groups: {id: meta} }`. Group F's review list in the app reads this same endpoint.
- `POST /owner/reports/resolve` `{ id, action: "dismiss"|"remove"|"restore"|"ban" }`:
  - `remove`: the share or group becomes `removed` and its storage is deleted.
  - `restore`: it becomes `live`.
  - `ban`: the target's account gets `share_banned = 1`, all its shares are suspended, and it is removed from all groups it owns.

**Contact**: `targetType: "contact"` doubles as the published contact channel. There is also a `GET /support` page (with group F's privacy and terms pages) carrying the contact form and a support address if the owner wants one.

### 4.5 Public page (`sharepage.js`)
- **`GET /.well-known/apple-app-site-association`**, served as `application/json` with no redirect:
```json
{"applinks":{"details":[{"appIDs":["<TEAMID>.com.cramdown.app"],"components":[{"/":"/s/*","comment":"shared set"},{"/":"/j/*","comment":"join a class or group"}]}]}}
```
  - `TEAMID` comes from `app_config['apple_team_id']`, falling back to env `APPLE_TEAM_ID`. If both are empty, return 404, so a wrong file is never cached by Apple's CDN.
- **`GET /robots.txt`**: `Disallow: /s/` and `Disallow: /j/`. Pages also carry `<meta name="robots" content="noindex">`.
- **`GET /og.png`**: a static 1200×630 brand card, bundled as base64 in the module. It is needed for WhatsApp and iMessage previews.
- **Page template** for `/s/` and `/j/`:
  - Language: `ar` or `en` from `Accept-Language`; Arabic sets `dir="rtl"`.
  - All user strings are HTML-escaped.
  - `content-security-policy: default-src 'none'; img-src 'self'; style-src 'unsafe-inline'; script-src 'sha256-<hash of the one inline copy-to-clipboard script>'; base-uri 'none'; form-action 'self'`.
  - `x-frame-options: DENY`, `referrer-policy: no-referrer`.
  - Content: `og:title`, `og:description` ("40 MCQs · Cardiology"), `og:image` = `/og.png`.
  - Smart App Banner `<meta name="apple-itunes-app" content="app-id=ID, app-argument=https://…/s/CODE">`, only once the App Store id is known.
  - Buttons: "Open in Vignette" → `redpen://s/CODE`. A button is needed because a tap on a same-domain link does not fire a universal link. "Get Vignette on the App Store" → `https://apps.apple.com/app/idID`, whose click handler first runs `navigator.clipboard.writeText(location.href)`.
  - Small print: "For medical education, not clinical decisions."
  - A "Report" link opens a small form that posts to `/reports`.
- **App Store id with no manual step**: `https://itunes.apple.com/lookup?bundleId=<APPLE_BUNDLE_ID>` is looked up at most once an hour and cached in `app_config['app_store_id']`. Before the app is live there is no result, and the page shows "Coming soon to the App Store" plus an optional `TESTFLIGHT_URL` var.

### 4.6 Account deletion: `wipeSocial(env, id)` in `groups.js`
- Delete the account's shares (storage included).
- For each owned group: transfer to the oldest admin if one exists, otherwise delete the group.
- Delete its `group_members`, `weekly_stats`, and `blocks` in both directions.
- Set `reports.reporter_id = NULL` for its reports.
- Keep it within the 50-query budget: a set-based `DELETE … WHERE owner_id = ?`, and share storage deletes in one statement per table.

## 5. Security, privacy and abuse

### 5.1 Authorisation
- Every write checks role from `group_members` or ownership from `shares.owner_id` inside the same statement's `WHERE` (e.g. `UPDATE … WHERE id = ? AND owner_id = ?`, checking `meta.changes`). The pattern is copied from `sync.js`'s compare-and-set.
- Public reads expose only what the page shows: no owner id, no email, no member list.

### 5.2 Guessing and enumeration
- Codes are about 49 bits.
- Wrong codes are counted per IP in `pair_attempts` (`'sharecode'` 60/h for `/s/`, `'groupcode'` 30/h for `/j/` and joins). A correct code refunds the count.
- With the `[[ratelimits]]` binding (`SHARE_RL`, limit 120 per 60 s keyed by `cf-connecting-ip`) the public GETs are throttled without D1 writes. Without the binding, only wrong codes cost a D1 write.

### 5.3 Account creation through invites
- `/auth/device` gains `{ via: CODE }`. If `via` is a live share code, or an open group join or admin code, the IP bucket is `'device-invite'` with `INVITE_DEVICES_PER_HOUR = 300` instead of 5.
- Also a per-code cap: at most 50 new accounts per code per hour, keyed `code:<CODE>` in `pair_attempts`, so one leaked code can't mint unlimited accounts.
- `accounts.joined_via = CODE` is recorded for group B.

### 5.4 Content and size
- The server parses the manifest once at publish (lecturer-rate, not student-rate), allowlists its shape, and extracts blob refs itself. Pictures are hash-verified.
- All user bytes are served non-sniffable. Size caps are in section 2. The storage soft cap protects the free D1 database.

### 5.5 Objectionable-content filter (Guideline 1.2)
- `names.js` runs on titles, subjects, group names and display names, both in the app before upload and on the server.
- Optional, behind flag `SHARE_AI_SCREEN` (default off; costs free Workers AI neurons): screen the title plus the first 4k characters of manifest text with `@cf/meta/llama-guard-3-8b` at publish. A flagged share becomes `suspended` pending owner review.

### 5.6 Privacy
- Receivers are anonymous to publishers. The `imports` count is approximate and aggregate.
- Lecturers see member counts only.
- Leaderboards: opt-in per group, a pseudonym per group, per-group handles that can't be linked across groups, weekly aggregates only, deleted after 8 weeks, never uploaded unless opted in somewhere.
- The device id is a random UUID stored in UserDefaults, reset on reinstall. It is not `identifierForVendor`.
- Lecture text is not shared unless the publisher turns it on.
- No fingerprinting for deferred links (Guideline 5.1.2): only the clipboard the user explicitly triggers, plus `PasteButton`, which avoids the paste prompt.

### 5.7 Copyright (Guideline 5.2)
- The publish sheet states: "Only share material you made or have permission to share. Slides and lecture text belong to their authors." The terms, hosted by group F, carry a takedown procedure.
- The `copyright` report reason feeds the auto-suspend. The owner action removes the share and deletes its storage.

### 5.8 Timely response
- The owner's review list (group F's screen) shows open share, group and member reports first, with a badge count.
- Auto-suspend at 3 distinct reporters means content comes down even while the owner is offline.

## 6. App side (paths under `ios/RedPen`)

### 6.1 New pure files (Foundation / CryptoKit only, so they are unit-testable on the macOS runner)
- `Models/ShareModels.swift`: `ShareOrigin`, `ShareMeta` (the public JSON), `PublishRequest/Reply`, `GroupDTO`, `GroupMe`, `FeedReply`, `LeaderboardRow`, `ShareLimits`.
- `Shared/ShareLinks.swift`:
  - `enum ShareLink { case set(String), group(String) }`.
  - `parse(_ url: URL)` accepts `https://<AuthAPI host>/s|j/CODE` and `redpen://s|j/CODE`.
  - `find(in text: String)` covers WhatsApp-wrapped text and bare codes; `normalise(_:)`; `url(for:)`.
- `Shared/StableIDs.swift`: `UUIDv5(namespace:name:)`.
- `Shared/SharePacking.swift`: `outgoing(_ set:, includeSources:) -> (manifest: Data, blobs: [String: Data], itemCount, imageCount)`, `incoming(...)`, `contentHash(_:)`.
- `Shared/ShareMerge.swift`: section 3.4.
- `Shared/WeeklyStats.swift`: section 3.5.
- `Shared/NameRules.swift`: section 3.6.

### 6.2 New files that use UIKit, network or SwiftUI
- `Shared/ShareImages.swift`: ImageIO downscale and JPEG re-encode.
- `Shared/ShareAPI.swift`:
  - Wraps `AuthAPI.send` for POSTs.
  - Adds `AuthAPI.get(_ path:) -> Data` for public GETs, using the same failure mapping plus new `Failure.gone(String)` for 410.
  - `PUT` for share blobs, uploaded 4 at a time with retry.
  - Publish flow: `limits` → `terms` if needed → `publish` → upload `missing` → `commit`, with progress callbacks.
- `Persistence/ShareStore.swift`: `@MainActor final class ShareStore: ObservableObject`.
  - Persisted: `Documents/redpen-shares.json` holds `{ outgoing: [setId: {shareId, code, version, publishedHash}], groups: [GroupDTO], feedRevs: [groupId: Int], autoAdd: [groupId: Bool], installId, lastVersionCheck }`. Merge bases live in `Application Support/shares/`.
  - Published state: `pendingOpen: ShareLink?`, `preview: ShareMeta?`, `groups`, `updatesAvailable: [setId: Int]`.
  - Methods:
    - `handle(url:)` / `handle(text:)`
    - `publish(set:includeSources:showName:)`
    - `importShared(code:, into: Store, groupId:)`
    - `checkUpdates(store:)`: `POST /shares/versions` for all `library.compactMap(\.origin)`, throttled to 6 h.
    - `applyUpdate(setId:store:)`
    - `pollFeed(store:account:)`
    - `joinGroup(code:account:)`: calls `account.ensureServerSession(via:)` first.
    - `createGroup`, `leave`, `pushStats(account:)`
  - Screenshot runs use a scratch file, like the other stores.
- **`Features/Share/`**:
  - `ShareSetSheet.swift`: the options, a progress bar, the resulting URL with `ShareLink`, "Copy", "Stop sharing".
  - `SharedSetPreview.swift`: the receiver's sheet (Add / Open existing / Report). It shows "Updated" when versions differ.
  - `OpenLinkView.swift`: a text field plus `PasteButton` for Playgrounds, pasted codes and deferred links.
  - `CommunityRulesSheet.swift`: shown once; calls `/shares/terms`.
  - `ReportSheet.swift`: shared with group F's "Report an error" if it lands first.
  - `BlockedPeopleView.swift`
- **`Features/Groups/`**:
  - `GroupsView.swift`: a list of classes and groups, plus Join and Create.
  - `CreateGroupView.swift`
  - `GroupDetailView.swift`: sets with New / Updated badges, "Add set", share join link; owner/admin controls such as rotate, close joining, co-lecturer link, delete.
  - `LeaderboardView.swift`: this week / last week, an opt-in card with a display-name field validated live by `NameRules`, a "Hide me" toggle, and a row menu with Report and Block.
  - `JoinGroupView.swift`

### 6.3 Changed files
- **`Models/StudySet.swift`**: `var origin: ShareOrigin? = nil`, plus the key and decoding (3.4).
- **`Persistence/Store.swift`**: `func importShared(_ set: StudySet)` (clears the tombstone, stamps `updatedAt`, appends or replaces) and `func folder(named:) -> UUID` for class folders.
- **`Persistence/AccountStore.swift`**: `ensureServerSession(via code: String? = nil)`, passed through to `AuthAPI.deviceAccount(claim:via:)`.
- **`Shared/AuthAPI.swift`**:
  - `deviceAccount(claim:via:)`.
  - `get(_:)`.
  - `Failure.gone`; 410 maps to `.gone`, and 422 and 507 go to `.server(message)`.
  - `send` gains an optional `method` parameter for PUT with a raw `Data` body.
- **`RedPenApp.swift`**:
  - `@StateObject private var shares: ShareStore`, with a scratch file on seeded runs, plus `.environmentObject(shares)`.
  - On the root `Group`:
    - `.onOpenURL { shares.handle(url: $0) }`
    - `.onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { a in a.webpageURL.map(shares.handle) }`
  - A pending link survives the sign-in screen and opens after any sign-in, local included, because receiving needs no server.
  - In the existing launch `.task` and in `.onChange(of: phase) == .active`:
    - `await shares.checkUpdates(store:)`
    - `await shares.pollFeed(store:account:)`, only when `account.token != Session.localToken`
    - `await shares.pushStats(account:)`
- **`Shared/CloudJobCollector.swift`**: inside the existing BG refresh handler, also run `ShareStore.backgroundPoll()`, which reads the stored session and posts the local notification. The existing `canRefresh` guard already makes this a no-op in Playgrounds. Also schedule the refresh when the user is in any group, not only when jobs are pending.
- **`Shared/BackgroundWork.swift` (`AppNotifications`)**: `notifyGroupUpdate(groupName:setTitle:isNew:)`.
- **`Features/Library/LibraryRows.swift`** (set context menu):
  - Own sets: "Share link…", "Update shared link" (when `contentHash ≠ outgoing.publishedHash`), "Add to class…".
  - Imported sets: "Share original link", "Report".
  - A small "From <publisher/class>" caption and an "Update available" badge.
- **`Features/Library/LibraryView.swift`**: a toolbar item "Classes & groups", the sheet routing for `shares.preview`, and, on an empty library, the `PasteButton` card "Open a set you were sent".
- **`Features/Auth/AccountView.swift`**: rows for "My shared links" (from `/shares/mine`, with revoke), "Blocked people" and "Community rules".
- **`Shared/PreviewExtras.swift`**: new screenshot screens `sharePreview`, `groupDetail` and `leaderboard` with seeded data, so the existing preview workflows capture them.

### 6.4 Build targets: Xcode vs Playgrounds

| Capability | Xcode / App Store build | Playgrounds (`make_swiftpm.py`) |
|---|---|---|
| Universal links `/s/`, `/j/` | Yes: entitlement `com.apple.developer.associated-domains: ["applinks:redpen-auth.vv7sh4rnnw.workers.dev"]` in `project.yml` | No (no entitlements). The web page's "Open in Vignette" uses `redpen://` if the scheme is declared (next row), else the user pastes. |
| `redpen://s|j/` scheme | Already in Info.plist | Add `additionalInfoPlistContentFilePath: "AdditionalInfo.plist"` to the generated `Package.swift`, and have the script write a plist with `CFBundleURLTypes` (`redpen`). Check on device whether Playgrounds honours it; if not, it is ignored harmlessly. |
| Background feed poll plus notification | Yes (the existing BG refresh id) | No. Polls on launch and on foreground only (`canRefresh` is already false). |
| Paste or type a link or code | Yes | Yes (the main path) |
| Everything else in A | Same code | Same code |

There are no app extensions in group A, so there is nothing to exclude. Detection stays at runtime (Info.plist and the permitted BG ids), matching existing practice, rather than `#if SWIFT_PACKAGE`.

**`project.yml` changes**:
- `entitlements.properties` gains `com.apple.developer.associated-domains: [applinks:redpen-auth.vv7sh4rnnw.workers.dev]`. For Debug, also consider `…?mode=developer` to skip Apple's CDN cache.
- Nothing else. The URL scheme already exists.

## 7. App Store Review risks and how to stay compliant

- **1.2 user-generated content (high risk if missed).** Share titles and content, group names, display names and leaderboards are all UGC. All four requirements are covered:
  1. Filter: `NameRules` / `names.js`, plus the optional Llama Guard screen.
  2. Report with timely response: a Report button on every shared-set preview, imported set, group page, leaderboard row and web page; auto-suspend at 3 reporters; the owner review list.
  3. Block: leaderboard rows and group contexts, with a Blocked People list.
  4. Published contact: the `/support` page, the App Store Connect Support URL, and the in-app Contact.
  - Also: Community rules accepted before any UGC action, and enforced server-side.
  - In the App Review notes, describe the moderation flow and give a live demo share link and demo class link.
- **1.2.1 creator content** does not apply: there is no monetisation of creator content. No age-gating mechanism is needed beyond the questionnaire.
- **5.2 intellectual property.** Lecturer slides are third-party content. Covered by the rights attestation in the publish sheet, lecture text off by default, a copyright report reason, and the takedown steps in the terms. Never ship the app with sample shared content you do not own.
- **3.1.1 in-app purchase.**
  - Shared sets and classes never unlock Pro features. A receiver gets content, and cloud generation stays Pro-gated.
  - The web page must not sell Pro or link to an outside purchase.
  - Group licences (group B) must not be sold inside A's class flow outside IAP. `groups.licence_id` is only a placeholder for B.
- **3.2.2(x).** Never require sharing, inviting or joining a group to unlock anything. If group B rewards referrals, it must reward the referred signup, not the act of sharing. The guideline allows incentives for in-app actions; the risk is presenting it as a requirement.
- **5.3 contests.** Leaderboards have no prizes, no "win", no ambassador rewards tied to rank. If a prize is ever added, official rules must appear in the app with the statement that Apple is not a sponsor.
- **5.1.1 data collection and 5.1.2 no fingerprinting.** The privacy labels must add the new data types (section 9). Deferred deep linking uses only the user-initiated clipboard plus `PasteButton`, never IP or device matching.
- **5.1.1(v) account sign-in.** Receiving a set needs no account. Classes need an account, which is created silently (device account) with no Apple or Google requirement, so this is fine.
- **2.1 completeness.** Associated Domains must validate at review time. The AASA file must be live with the correct Team ID before submission. The deploy step checks this (section 8, deploy-workflow row).
- **Minors.** Medical students are adults, but the leaderboard and groups mean the age questionnaire should answer "User-Generated Content: Yes". Expect 13+ or 16+; accept whatever the questionnaire yields.

## 8. Tests

### 8.1 Server tests
Node 22 with `node:sqlite`, using the same harness as `pair.test.mjs`: the schema is split on `;` into an in-memory DB, a fake D1 with `prepare/bind/first/all/run` plus `batch`, and a second in-memory DB for `SHARE_STORE`. A Map-backed fake R2 has `put/get/head/delete/list`.

**`server/tests/share.test.mjs`**
- Publish before accepting terms → 403. After `/shares/terms` it proceeds.
- Codes are 10 characters from the alphabet. 1,000 codes: no duplicates, no character outside the alphabet (rejection sampling).
- Title with URL, phone number or blocklisted word, in English and Arabic including a tashkeel/variant spelling → 422. Bidi override characters are stripped.
- Manifest checks:
  - `images` containing base64 or `data:` → 400.
  - More than 150 pictures → 400.
  - Oversize → 413.
  - Wrong `format` → 400.
  - `sources` are stored as sent (the app strips them), but `fileBlob` is removed server-side.
- `missing` lists exactly the hashes not stored. A PUT with the wrong hash → 400. A PUT by a non-owner → 403. A repeat PUT → ok, with no double-counted bytes.
- Commit with a picture missing → `409 { missing }`. After uploading → live, version 1.
- Republish → version 2. Version 1's manifest is still readable, version 0 is gone. A picture unreferenced by v1 and v2 is deleted.
- Another account's `shareId` → 409. The same `(owner, setId)` reuses the share.
- Per-account share count and per-share byte limits are enforced.
- Public reads:
  - `GET /s/CODE.json` has no owner id or email.
  - The manifest has `nosniff` and immutable cache headers.
  - A picture is served as `application/octet-stream` with `content-disposition: attachment`.
- Revoke → 410 on the page, json, manifest and picture. Storage is emptied. Groups holding it get `rev` bumped and `removed: true` in the feed.
- `/shares/versions` ignores unknown codes, caps at 200, and is rate limited per IP.
- 61 wrong-code GETs from one IP → 429. A correct code refunds.
- With `env.BLOBS` present, new shares go to R2 and old D1 shares still read.
- The D1 soft cap makes `limits.images = false` and picture PUTs return 507, while text-only publish still works.
- Every route stays within 50 queries: wrap the fake `prepare` with a counter and assert ≤ 50 per request.

**`server/tests/groups.test.mjs`**
- Create class or study group, check the defaults (leaderboard 0 or 1). Join via the join code (member) and via the admin code (admin, even while joining is closed).
- Rotating the join code makes the old one 404. Joining closed → 403. The member cap → 409. Rejoining is idempotent.
- Only owner or admin can add or remove sets. A member → 403. Adding someone else's share → 403.
- The feed:
  - Returns only changed groups.
  - `rev` increases on add, on republish (commit bumps every group holding the share) and on remove.
  - `gone` lists left, deleted or removed groups.
- The owner can't leave without transfer. Transfer to an admin works. Delete removes members and group_sets but not shares.
- Removing a member by handle works. Handles differ across groups for the same account and are stable within a group.
- Stats:
  - Refused for the wrong week (422). The previous week is accepted only within 36 h.
  - `answered` above `3000 × popcount` → 422. Mask bits are OR'd and `answered` is MAX-merged per device, summed across devices.
  - Not stored when not opted in anywhere.
  - Rows older than 8 weeks are purged by the lazy cleanup (force the 1-in-50 branch with an injectable random).
- Leaderboard:
  - Only opted-in members, ranked by answered then active days, top 50 plus me.
  - Blocked in either direction are hidden.
  - 403 when leaderboards are off or for a non-member.
  - No account ids in the response.
- `/auth/device` with `via` = a valid code uses the invite bucket (the 6th device from one IP succeeds). An invalid `via` falls back to the 5/h limit. The per-code 50/h cap holds. `joined_via` is recorded.
- `wipeSocial`: shares, storage, memberships, stats and blocks are gone. An owned group is transferred to the oldest admin, or deleted when there is none. Reports are anonymised.

**`server/tests/moderation.test.mjs`**
- Duplicate reports from the same account are ignored.
- 3 distinct abuse reporters → share `suspended` → 410.
- Owner `restore` → live. Owner `remove` → removed and storage deleted. `ban` → `share_banned`, all shares suspended, publish → 403.
- Non-owner calls to `/owner/*` → 403. The owner key is accepted.
- Blocks add, list and remove. The block list does not reveal the raw account id.

**`server/tests/sharepage.test.mjs`**
- A title containing `<script>` is escaped in the HTML. The CSP header is present. The script hash matches the inline script.
- `Accept-Language: ar` → `dir="rtl"` with Arabic strings.
- The Smart App Banner is present only when `app_store_id` is known. The lookup is cached, with no second fetch within the hour (fake fetch).
- AASA: correct JSON and `content-type` when the team id is set, 404 when unset. `robots.txt` disallows `/s/` and `/j/`.
- The 410 page for revoked or suspended, 404 for unknown.

**Name-rules parity**: `server/tests/fixtures/name-rules.json` holds `[{ input, kind, ok, normalised }]`, used by `names.test.mjs` and by the Swift suite.

**Workflows**:
- `server-tests.yml`: add steps `node server/tests/share.test.mjs`, `groups.test.mjs`, `moderation.test.mjs`, `sharepage.test.mjs`, `names.test.mjs`.
- `worker-deploy.yml`: extend the "Tests first" line with the same files.

### 8.2 Swift suites
Top-level code in `ios/RedPen/Tests`, copied to `main.swift` by `swift-tests.yml`.

**`Tests/ShareTests.swift`**
- `ShareLinks.parse` and `find`:
  - https and `redpen://` forms, lower case and dashes.
  - WhatsApp-wrapped text ("Check this https://…/s/k7qm-x2pahd 👍").
  - Other hosts rejected. `/j/` vs `/s/`.
  - A bare 10-character code accepted, a 9-character one rejected.
- `UUIDv5` matches RFC 4122 test vectors (the DNS namespace with "www.example.com" → `2ed6657d-e927-568b-95e1-2665a8aea6a2`).
- `SharePacking.outgoing`: strips `folderId` and `origin`; strips `sources` unless asked; always clears `fileBlob`; every picture becomes `blob:<hash>`; item counts are right.
- `SharePacking.incoming`:
  - Set and item ids are deterministic per share, differ from the publisher's, and are equal across two imports.
  - `origin` is filled in. `imageIndex` still points at the right picture.
- `contentHash` ignores `id`, `updatedAt`, `folderId` and `origin`, and changes on any item edit.
- `ShareMerge`:
  - Untouched local → takes remote.
  - An edited item is kept (`keptLocal` = 1).
  - Upstream add, change and remove are applied.
  - A local-only addition is kept and appended.
  - A picture pool with a kept local item referencing an old picture: the pool is rebuilt and deduplicated, and indexes are remapped correctly.
  - Nil base plus a matching `importedHash` → wholesale. Nil base plus a mismatch → conservative.
  - Guard: fail if `Mirror` finds an `imageIndex` property on any model other than `MCQQuestion` and `AnkiCard`.
- `NameRules`: runs the shared fixture file `server/tests/fixtures/name-rules.json`, read from the repo root.

**`Tests/GroupTests.swift`**
- `WeeklyStats.compute`:
  - ISO week boundaries (Sunday 23:30 vs Monday 00:10 local).
  - Year boundary (2026-12-31 → 2026-W53, 2027-01-04 → 2027-W01).
  - The mask bit order is Monday = bit 0. Days outside the week are ignored. Previous-week computation.
  - Uses a fixed `TimeZone(identifier: "Africa/Cairo")` and UTC.
- Feed diffing (a pure helper `GroupFeedPlan.plan(local:feed:) -> [import | update | markRemoved]`): new set → import, higher version → update, removed → mark only (never delete the user's copy).

**`Tests/SyncTests.swift` (extend)**: a set re-added with an id that has a local tombstone (as `Store.importShared` does: tombstone cleared, newer `updatedAt`) resolves to push, not delete. The pure part lives in `SyncMerge`.

**`swift-tests.yml`** (also add `ios/RedPen/Shared/**` paths, already covered):

```
suite share ShareTests.swift $M/MCQQuestion.swift $M/Differential.swift $M/AnkiCard.swift $M/QACard.swift \
      $M/OsceChecklist.swift $M/NarrateSegment.swift $M/SourceDoc.swift $M/StudySet.swift $M/ShareModels.swift \
      $S/SoundKey.swift $S/PronunciationStore.swift $S/OnDeviceLearning.swift $S/Corrections.swift \
      $S/WordTiming.swift $S/LectureTranscriber.swift $S/Brand.swift $S/BookPages.swift $S/BookFigures.swift \
      $S/Highlight.swift $S/BlobRefs.swift $S/StableIDs.swift $S/ShareLinks.swift $S/SharePacking.swift \
      $S/ShareMerge.swift $S/NameRules.swift
suite groups GroupTests.swift $S/WeeklyStats.swift $M/ShareModels.swift $S/GroupFeedPlan.swift
```

The dependency list mirrors the existing `deck` suite, because `StudySet` drags in the same model files. `StudySet.swift` itself gains only a Codable field, and `ShareModels.swift` must stay Foundation-only.

### 8.3 UI test (optional)
`UITests`: launch with `-previewScreen sharePreview`, tap "Add to library", and assert the set row appears. This uses the existing `PreviewLaunch` mechanism, with no network.

## 9. Ops, deploy and the owner's unavoidable steps

### 9.1 Automated (no owner action)
- **`worker-deploy.yml`**:
  - Create or find D1 `redpen-shares` the same way as `redpen-auth`, `sed` its id into a new `[[d1_databases]] binding = "SHARE_STORE"` block, and run `share-store.sql`.
  - Run the new ALTERs for `ugc_terms_at`, `share_banned` and `joined_via`.
  - Add `[[ratelimits]] name = "SHARE_RL" namespace_id = "7301" [ratelimits.simple] limit = 120 period = 60`. If deploying with it ever fails on the free plan, the step deletes the block like the R2 fallback, and the code falls back to D1 counters.
  - After deploy, a check step: `curl -sf $URL/.well-known/apple-app-site-association | jq .applinks` prints a warning (not a failure) until the Team ID is known.
- **Team ID with no manual step**: the TestFlight signing job, once it exists, reads the team from the signed app (`codesign -d --entitlements :- Vignette.app | plutil -extract com.apple.developer.team-identifier raw -`). It then runs `npx wrangler d1 execute redpen-auth --remote --command "INSERT OR REPLACE INTO app_config VALUES ('apple_team_id', '<id>', unixepoch())"` using the existing `CLOUDFLARE_API_TOKEN` secret. Fallback: an optional `apple_team_id` input on the deploy workflow; it is not a secret.
- **App Store id**: automatic through the iTunes lookup once the app is live.
- **Associated Domains capability**: turned on automatically by `xcodebuild -allowProvisioningUpdates` with the App Store Connect API key the signing workflow already needs.

### 9.2 Owner steps at publish time (App Store Connect only)
1. **App Privacy (nutrition labels)**. Add, all "Linked to you", "Not used for tracking", purpose "App Functionality":
   - **User Content → Other User Content**: shared sets, group names, per-group display names, reports.
   - **Usage Data → Product Interaction**: weekly answered count and active days, only for leaderboard opt-ins.
   - **Identifiers → User ID**: the account id, already declared for sync.
2. **Age rating questionnaire**: answer "Yes" to user-generated content / social features. Accept the resulting rating.
3. **App Information**:
   - Support URL: `https://redpen-auth.vv7sh4rnnw.workers.dev/support`.
   - Privacy Policy URL: `…/privacy` (group F).
4. **App Review notes** (paste text that will be prepared in `docs/launch/`):
   - How sharing, classes and leaderboards work, and the moderation steps (filter, report, block, auto-suspend, owner review within 24 h, contact page).
   - A live demo share link and demo class join link.
   - "Start without an account" needs no credentials.
5. **Only if manual signing is ever used instead of the API key**: tick "Associated Domains" on the App ID in the Developer portal. Not needed with automatic provisioning.
6. **Optional, not required for launch**: enable R2 in the Cloudflare dashboard (needs a card on file; stays at $0 under 10 GB). The deploy workflow then picks it up automatically and picture-heavy shares get the 30 MB limit instead of 8 MB.

## 10. Build order
Each step ships on its own.

1. **Server A1**: `names.js`, `storage.js` (D1 plus R2), `share.js`, `sharepage.js`, `moderation.js` (reports, blocks, owner review), schema and deploy changes, and the tests. Deploy early: AASA and the pages can go live before the app.
2. **App A1**: pure files and suites first, then `ShareStore`, the share sheet and preview, the URL handling in `RedPenApp`, the `LibraryRows` menu, the Community rules sheet, reporting, the `project.yml` entitlement and `make_swiftpm.py`'s plist.
3. **Server and app A2**: `groups.js` (create, join, feed, sets), `/auth/device` `via`, `wipeSocial`; `GroupsView`, `GroupDetailView`, auto-import folders, BG poll and notifications.
4. **A3**: `/stats/week`, the leaderboard, `WeeklyStats`, `LeaderboardView`, the blocked people UI.
5. **Hooks for other groups, already in the schema**:
   - `shares.fingerprint` for group D's per-class generation cache (look up a live share in the same class with the same fingerprint before running a generation job).
   - `accounts.joined_via` for group B's referral credits.
   - `groups.licence_id` for group B's group licences.
   - The `limit()` helper for group D's remote config.
   - The `reports` table and `/owner/reports` shared with group F.

## Files referenced (worktree `/tmp/claude-0/-home-user/8857977a-f678-5988-9658-6061ad2dfd91/scratchpad/rp-prev`)
- **Server**: `server/worker.js`, `server/schema.sql`, `server/pair.js`, `server/tokens.js`, `server/sync.js`, `server/ai.js` (`isPro`, `proGate`, `isOwnerKey`), `server/wrangler.toml`, `server/tests/pair.test.mjs` (the harness to copy).
- **Workflows**: `.github/workflows/worker-deploy.yml`, `.github/workflows/server-tests.yml`, `.github/workflows/swift-tests.yml`.
- **App**:
  - `ios/project.yml`, `ios/RedPen/RedPenApp.swift`
  - `ios/RedPen/Models/StudySet.swift`, `ios/RedPen/Models/AnkiCard.swift`
  - `ios/RedPen/Persistence/Store.swift`, `ios/RedPen/Persistence/AccountStore.swift`
  - `ios/RedPen/Shared/AuthAPI.swift`, `ios/RedPen/Shared/BlobRefs.swift`, `ios/RedPen/Shared/SyncDocuments.swift`, `ios/RedPen/Shared/StudyLog.swift`, `ios/RedPen/Shared/CloudJobCollector.swift`, `ios/RedPen/Shared/BackgroundWork.swift`, `ios/RedPen/Shared/SubscriptionStore.swift`
  - `ios/RedPen/Features/Auth/SignInView.swift`, `ios/RedPen/Features/Library/LibraryRows.swift`
- **Playgrounds build**: `/tmp/claude-0/-home-user/8857977a-f678-5988-9658-6061ad2dfd91/scratchpad/make_swiftpm.py`

## Sources
- [Cloudflare Workers Rate Limiting binding](https://developers.cloudflare.com/workers/runtime-apis/bindings/rate-limit/)
- [Rate Limiting in Workers is now GA](https://developers.cloudflare.com/changelog/post/2025-09-19-ratelimit-workers-ga/)
- [Workers pricing](https://developers.cloudflare.com/workers/platform/pricing/)
- [D1 limits](https://developers.cloudflare.com/d1/platform/limits/)
- [App Store Review Guidelines (1.2, 3.2.2, 5.2, 5.3)](https://developer.apple.com/app-store/review/guidelines/)
- [AppleProductTypes.swift parameter and capability list (gist)](https://gist.github.com/treastrain/2f21d42c360dc9b9876ddde125abe247)
- [Configuring an associated domain (Apple)](https://developer.apple.com/documentation/xcode/configuring-an-associated-domain)
