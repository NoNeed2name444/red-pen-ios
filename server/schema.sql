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
  expires_at    INTEGER
);

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
