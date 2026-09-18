-- The whole database. Two tables, and neither of them holds anything a student
-- wrote.
--
-- What is here: an account id, whichever provider proved it, an address if one
-- was given, and the subscription the App Store confirmed. What is not here,
-- and never will be: decks, cards, questions, recordings, transcripts,
-- pronunciations. Those stay on the phone. There is nothing in this file to
-- lose in a breach beyond a list of email addresses, and that is the point.

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

-- A code that was emailed, and the tries spent on it.
--
-- The code is stored HASHED. A database that can be read should not hand over
-- live sign-in codes, and nothing here ever needs the original back - verifying
-- means hashing what was typed and comparing.
CREATE TABLE IF NOT EXISTS codes (
  email       TEXT PRIMARY KEY,
  code_hash   TEXT NOT NULL,
  expires_at  INTEGER NOT NULL,
  tries       INTEGER NOT NULL DEFAULT 0,
  sent_at     INTEGER NOT NULL
);
