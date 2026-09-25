-- The whole database.
--
-- An account, and that account's own library so it can follow the student
-- between their own devices. Nothing here is shared with anybody else.
--
-- The pictures are not in this file: they live in object storage under the hash
-- of their own bytes, because a term of slide images is gigabytes and a database
-- is the wrong place for it.

CREATE TABLE IF NOT EXISTS accounts (
  id            TEXT PRIMARY KEY,
  provider      TEXT NOT NULL,          -- apple | google | email
  -- the provider's own id for this person, which is what identifies them on a
  -- second sign-in. Apple's is stable per developer account; Google's is the
  -- `sub` claim; for email it is the address itself.
  subject       TEXT NOT NULL,
  email         TEXT,
  display_name  TEXT,
  created_at    INTEGER NOT NULL,
  plan          TEXT,
  expires_at    INTEGER,
  -- Sessions issued before this moment are refused however well they are
  -- signed. A signed token cannot be taken back on its own, so this is what
  -- makes "sign out on every device" - the only thing a student can do about a
  -- phone they have lost - mean anything.
  -- Existing deployments: ALTER TABLE accounts ADD COLUMN signed_out_before INTEGER NOT NULL DEFAULT 0;
  signed_out_before INTEGER NOT NULL DEFAULT 0,
  -- CramDown Cloud: the App Store subscription this account paid with, and
  -- until when Apple last confirmed it. Unlike `plan`, these ARE what the
  -- cloud models check, because they are Apple's answer rather than the app's.
  -- Existing deployments:
  --   ALTER TABLE accounts ADD COLUMN original_transaction_id TEXT;
  --   ALTER TABLE accounts ADD COLUMN verified_until INTEGER NOT NULL DEFAULT 0;
  --   ALTER TABLE accounts ADD COLUMN checked_at INTEGER NOT NULL DEFAULT 0;
  original_transaction_id TEXT,
  verified_until INTEGER NOT NULL DEFAULT 0,
  checked_at INTEGER NOT NULL DEFAULT 0,
  -- "Production" or "Sandbox", as Apple reports it: test purchases unlock Pro
  -- for testing but are not revenue. Existing deployments:
  --   ALTER TABLE accounts ADD COLUMN apple_env TEXT;
  apple_env TEXT,
  -- The app's owner (their personal build has no App Store subscription):
  -- Pro without one. Set by hand in the database, never by a request.
  -- Existing deployments: ALTER TABLE accounts ADD COLUMN owner INTEGER NOT NULL DEFAULT 0;
  owner INTEGER NOT NULL DEFAULT 0
);
-- One subscription, one account (see linkSubscription): the unique index on
-- original_transaction_id is created by the deploy workflow, where an old
-- duplicate cannot stop the deploy.

-- One person, one account per provider. Signing in with Apple and then with
-- Google using the same address makes two accounts on purpose: we cannot prove
-- the two are the same person, and merging them on an unverified claim is how
-- an account gets taken over.
CREATE UNIQUE INDEX IF NOT EXISTS accounts_provider_subject
  ON accounts (provider, subject);

-- The library, as documents.
--
-- One row per set, folder or deck schedule, per account. `rev` is the account's
-- own revision counter at the moment the row was written, which is what makes
-- "everything since 47" a single indexed scan rather than a comparison of the
-- whole library.
CREATE TABLE IF NOT EXISTS docs (
  account_id  TEXT NOT NULL,
  id          TEXT NOT NULL,
  kind        TEXT NOT NULL,          -- set | folder | review | saying
  rev         INTEGER NOT NULL,
  updated_at  INTEGER NOT NULL,       -- the device's clock, for settling edits
  deleted     INTEGER NOT NULL DEFAULT 0,
  -- Absent on a tombstone. Keeping the contents of something somebody deleted
  -- is the opposite of deleting it.
  payload     TEXT,
  PRIMARY KEY (account_id, id)
);

-- The changes feed is this index. Without it every sync is a table scan, which
-- is fine for one student and ruinous for a thousand.
CREATE INDEX IF NOT EXISTS docs_by_rev ON docs (account_id, rev);

-- The revision counter itself, one row per account. Incremented inside the same
-- statement that reads it, so two devices pushing at once cannot be handed the
-- same number - which would leave one device's change invisible to anybody who
-- had already asked past it.
CREATE TABLE IF NOT EXISTS sync_state (
  account_id  TEXT PRIMARY KEY,
  rev         INTEGER NOT NULL DEFAULT 0
);

-- How much of the shared database each account's documents take, kept as a
-- running total as documents are written (sync.js push), so a push need not
-- count the whole library first and one account cannot fill the database.
CREATE TABLE IF NOT EXISTS doc_usage (
  account_id  TEXT PRIMARY KEY,
  bytes       INTEGER NOT NULL DEFAULT 0,
  docs        INTEGER NOT NULL DEFAULT 0
);

-- The same for pictures in R2: claimed before an upload is stored, so
-- uploads arriving together cannot all pass the check, and corrected from a
-- listing of R2 once a day (sync.js claim).
CREATE TABLE IF NOT EXISTS blob_usage (
  account_id  TEXT PRIMARY KEY,
  bytes       INTEGER NOT NULL DEFAULT 0,
  objects     INTEGER NOT NULL DEFAULT 0,
  counted_at  INTEGER NOT NULL DEFAULT 0
);

-- Cloud model requests per account per UTC day, so one account cannot run up
-- the provider bill for everybody.
CREATE TABLE IF NOT EXISTS ai_usage (
  account_id TEXT NOT NULL,
  day        TEXT NOT NULL,
  requests   INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (account_id, day)
);

-- CramDown Cloud's estimated Gemini spend per Pro account per month, in
-- millionths of a dollar, once the project pays for Gemini (GEMINI_BILLING)
CREATE TABLE IF NOT EXISTS ai_cost (
  account_id TEXT NOT NULL,
  month      TEXT NOT NULL,
  micro_usd  INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (account_id, month)
);
-- the month's total across everyone (budget() in ai.js) without reading
-- every month there has ever been
CREATE INDEX IF NOT EXISTS ai_cost_by_month ON ai_cost (month);

-- Linking a second device (pair.js): a short code, shown on a device that is
-- already in, typed on the new one. Single use, ten minutes.
CREATE TABLE IF NOT EXISTS pair_codes (
  code        TEXT PRIMARY KEY,
  account_id  TEXT NOT NULL,
  expires_at  INTEGER NOT NULL
);

-- Wrong codes and new device accounts, counted per address per hour, so a
-- code cannot be guessed and accounts cannot be minted without end.
CREATE TABLE IF NOT EXISTS pair_attempts (
  ip      TEXT NOT NULL,
  hour    INTEGER NOT NULL,
  what    TEXT NOT NULL,
  n       INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (ip, hour, what)
);

-- The owner's personal build carries a one-time claim (in the build itself,
-- never in the repository); the first device account made with it becomes
-- the owner's. Only the hash is kept.
-- `claimed_by` is the account it made, so the same build presenting it again
-- (a lost response, a sign-out) gets that account back rather than an
-- ordinary one. Existing deployments: ALTER TABLE owner_claims ADD COLUMN claimed_by TEXT;
CREATE TABLE IF NOT EXISTS owner_claims (
  hash  TEXT PRIMARY KEY,
  used  INTEGER NOT NULL DEFAULT 0,
  claimed_by TEXT
);

-- Accounts deleted, kept by id only (no name, no email) until everything that
-- belonged to them has been removed twice: once at once, and again by the
-- nightly pass, which also catches anything a device was still writing at the
-- moment of deletion (worker.js scheduled).
CREATE TABLE IF NOT EXISTS deleted_accounts (
  id          TEXT PRIMARY KEY,
  deleted_at  INTEGER NOT NULL,
  passes      INTEGER NOT NULL DEFAULT 0
);

-- The purchase tag (appAccountToken) of a deleted account, with the sign-in it
-- belonged to: the same person signing in again with the same Apple or Google
-- account may link the subscription they bought before (ai.js mayUse).
CREATE TABLE IF NOT EXISTS released_tokens (
  token        TEXT PRIMARY KEY,
  provider     TEXT NOT NULL,
  subject      TEXT NOT NULL,
  released_at  INTEGER NOT NULL
);

-- The accuracy engine (accuracy.js). A verdict's signals - each checker
-- model's vote, the evidence it was shown, how much of the item its lecture
-- contains - kept by the hash of the item's own content, so an item is never
-- checked twice unless it is edited. No account, no item text: only what the
-- models said about content with that hash.
CREATE TABLE IF NOT EXISTS accuracy_verdicts (
  hash        TEXT PRIMARY KEY,
  signals     TEXT NOT NULL,
  created_at  INTEGER NOT NULL
);

-- "Report an error": one row per item and account, with the item itself (the
-- training run needs to know what was reported) and the student's note.
-- Removed with the account.
CREATE TABLE IF NOT EXISTS accuracy_reports (
  hash        TEXT NOT NULL,
  account_id  TEXT NOT NULL,
  kind        TEXT NOT NULL,
  item        TEXT NOT NULL,
  note        TEXT,
  created_at  INTEGER NOT NULL,
  PRIMARY KEY (hash, account_id)
);
CREATE INDEX IF NOT EXISTS accuracy_reports_by_account ON accuracy_reports (account_id);

-- The accuracy model's weights, as each training run published them
-- (bench/train-accuracy.mjs); the newest is used.
CREATE TABLE IF NOT EXISTS accuracy_model (
  version     TEXT PRIMARY KEY,
  body        TEXT NOT NULL,
  created_at  INTEGER NOT NULL
);
