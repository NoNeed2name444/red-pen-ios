-- Unified D1 additions for groups A, B, D, E and F (C needs no tables).
-- Package P0.1 appends this file, unchanged, to server/schema.sql.
-- Rules the test harness depends on: every statement is CREATE ... IF NOT EXISTS,
-- no triggers, and no semicolon or double dash inside a string literal.
-- New columns on accounts live in accounts-alters.sql, and indexes on those
-- columns in accounts-indexes.sql, because this file runs before the ALTERs on
-- an existing database.

-- MARK: shared facts the worker learns (A app_config + B app_facts, merged)
-- keys: apple_team_id, app_store_id, app_store_lookup_at
CREATE TABLE IF NOT EXISTS app_facts (
  key        TEXT PRIMARY KEY,
  value      TEXT NOT NULL,
  updated_at INTEGER NOT NULL
);

-- MARK: A - shared sets (bytes live in the SHARE_STORE database or R2)
CREATE TABLE IF NOT EXISTS shares (
  id             TEXT PRIMARY KEY,
  code           TEXT NOT NULL UNIQUE,
  owner_id       TEXT NOT NULL,
  set_id         TEXT NOT NULL,
  kind           TEXT NOT NULL,
  title          TEXT NOT NULL,
  subject        TEXT,
  item_count     INTEGER NOT NULL DEFAULT 0,
  image_count    INTEGER NOT NULL DEFAULT 0,
  publisher_name TEXT,
  version        INTEGER NOT NULL DEFAULT 0,
  pending        INTEGER NOT NULL DEFAULT 0,
  bytes          INTEGER NOT NULL DEFAULT 0,
  storage        TEXT NOT NULL DEFAULT 'd1',
  status         TEXT NOT NULL DEFAULT 'pending',
  fingerprint    TEXT,
  imports        INTEGER NOT NULL DEFAULT 0,
  created_at     INTEGER NOT NULL,
  updated_at     INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS shares_by_owner ON shares (owner_id);
CREATE UNIQUE INDEX IF NOT EXISTS shares_owner_set ON shares (owner_id, set_id);
CREATE INDEX IF NOT EXISTS shares_by_fingerprint ON shares (fingerprint) WHERE fingerprint IS NOT NULL;

-- MARK: A - classes and study groups (kind: class | study)
-- licence_id from design A is dropped: a licence points at its class instead
-- (licences.group_id). members_share_generated is design D's class setting.
CREATE TABLE IF NOT EXISTS groups (
  id           TEXT PRIMARY KEY,
  kind         TEXT NOT NULL,
  name         TEXT NOT NULL,
  owner_id     TEXT NOT NULL,
  join_code    TEXT NOT NULL UNIQUE,
  admin_code   TEXT NOT NULL UNIQUE,
  join_open    INTEGER NOT NULL DEFAULT 1,
  leaderboard  INTEGER NOT NULL DEFAULT 0,
  members_share_generated INTEGER NOT NULL DEFAULT 0,
  status       TEXT NOT NULL DEFAULT 'live',
  rev          INTEGER NOT NULL DEFAULT 0,
  created_at   INTEGER NOT NULL,
  updated_at   INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS groups_by_owner ON groups (owner_id);

CREATE TABLE IF NOT EXISTS group_members (
  group_id     TEXT NOT NULL,
  account_id   TEXT NOT NULL,
  role         TEXT NOT NULL DEFAULT 'member',
  handle       TEXT NOT NULL,
  display_name TEXT,
  on_board     INTEGER NOT NULL DEFAULT 0,
  joined_at    INTEGER NOT NULL,
  PRIMARY KEY (group_id, account_id)
);
CREATE INDEX IF NOT EXISTS group_members_by_account ON group_members (account_id);
CREATE UNIQUE INDEX IF NOT EXISTS group_members_handle ON group_members (group_id, handle);

CREATE TABLE IF NOT EXISTS group_sets (
  group_id  TEXT NOT NULL,
  share_id  TEXT NOT NULL,
  rev       INTEGER NOT NULL,
  added_by  TEXT NOT NULL,
  added_at  INTEGER NOT NULL,
  removed   INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (group_id, share_id)
);
CREATE INDEX IF NOT EXISTS group_sets_by_share ON group_sets (share_id);

-- weekly counts per account per install, for opt-in leaderboards only
CREATE TABLE IF NOT EXISTS weekly_stats (
  account_id TEXT NOT NULL,
  week       TEXT NOT NULL,
  device     TEXT NOT NULL,
  answered   INTEGER NOT NULL DEFAULT 0,
  days_mask  INTEGER NOT NULL DEFAULT 0,
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

-- A - moderation of user-generated content (design A table reports, renamed).
-- target_type: share | group | member.  reason: abuse | copyright | spam | other
-- Item accuracy reports are F error_reports, and contact is F support_messages.
CREATE TABLE IF NOT EXISTS moderation_reports (
  id          TEXT PRIMARY KEY,
  reporter_id TEXT,
  target_type TEXT NOT NULL,
  target_ref  TEXT NOT NULL,
  reason      TEXT NOT NULL,
  note        TEXT,
  status      TEXT NOT NULL DEFAULT 'open',
  created_at  INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS moderation_reports_open ON moderation_reports (status, created_at);
CREATE INDEX IF NOT EXISTS moderation_reports_target ON moderation_reports (target_type, target_ref);
CREATE UNIQUE INDEX IF NOT EXISTS moderation_reports_once ON moderation_reports (reporter_id, target_type, target_ref) WHERE reporter_id IS NOT NULL;

-- MARK: B - App Store subscriptions, passes and notifications
CREATE TABLE IF NOT EXISTS apple_subscriptions (
  original_transaction_id TEXT PRIMARY KEY,
  account_id         TEXT,
  account_token      TEXT,
  app_transaction_id TEXT,
  product_id         TEXT NOT NULL,
  state              TEXT NOT NULL,
  expires_at         INTEGER NOT NULL DEFAULT 0,
  entitled_until     INTEGER NOT NULL DEFAULT 0,
  auto_renew         INTEGER,
  environment        TEXT NOT NULL,
  storefront         TEXT,
  first_offer_type   INTEGER,
  first_offer_id     TEXT,
  last_offer_type    INTEGER,
  last_offer_id      TEXT,
  converted_at       INTEGER,
  signed_at          INTEGER NOT NULL,
  updated_at         INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS apple_subscriptions_account ON apple_subscriptions (account_id);
CREATE INDEX IF NOT EXISTS apple_subscriptions_token   ON apple_subscriptions (account_token);
CREATE INDEX IF NOT EXISTS apple_subscriptions_offer   ON apple_subscriptions (first_offer_id);

CREATE TABLE IF NOT EXISTS apple_passes (
  transaction_id          TEXT PRIMARY KEY,
  original_transaction_id TEXT NOT NULL,
  account_id              TEXT,
  account_token           TEXT,
  product_id              TEXT NOT NULL,
  purchased_at            INTEGER NOT NULL,
  days                    INTEGER NOT NULL,
  revoked_at              INTEGER,
  environment             TEXT NOT NULL,
  offer_id                TEXT,
  signed_at               INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS apple_passes_account ON apple_passes (account_id);
CREATE INDEX IF NOT EXISTS apple_passes_token   ON apple_passes (account_token);

-- extracted fields only, never the raw payload, pruned after 180 days
CREATE TABLE IF NOT EXISTS apple_notifications (
  uuid        TEXT PRIMARY KEY,
  type        TEXT NOT NULL,
  subtype     TEXT,
  environment TEXT,
  signed_at   INTEGER NOT NULL,
  original_transaction_id TEXT,
  account_id  TEXT,
  outcome     TEXT NOT NULL,
  received_at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS apple_notifications_received ON apple_notifications (received_at);

-- Pro time the App Store did not sell (referral, welcome, gift). Free models only.
CREATE TABLE IF NOT EXISTS pro_grants (
  id              TEXT PRIMARY KEY,
  account_id      TEXT NOT NULL,
  kind            TEXT NOT NULL,
  days            INTEGER NOT NULL,
  state           TEXT NOT NULL,
  starts_at       INTEGER,
  ends_at         INTEGER,
  bank_expires_at INTEGER NOT NULL,
  created_at      INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS pro_grants_account ON pro_grants (account_id, state);

-- one referral per Apple Account ever
CREATE TABLE IF NOT EXISTS referrals (
  id                 TEXT PRIMARY KEY,
  referrer_id        TEXT,
  referee_id         TEXT,
  app_transaction_id TEXT NOT NULL UNIQUE,
  code               TEXT NOT NULL,
  state              TEXT NOT NULL,
  claimed_at         INTEGER NOT NULL,
  claim_day          TEXT NOT NULL,
  decided_at         INTEGER,
  reason             TEXT
);
CREATE INDEX IF NOT EXISTS referrals_referrer ON referrals (referrer_id, state, decided_at);
CREATE UNIQUE INDEX IF NOT EXISTS referrals_referee ON referrals (referee_id) WHERE referee_id IS NOT NULL;

-- B - class access (group licences), owner-created, attached to one A class.
-- Joining the class with its join code takes a seat while seats remain.
CREATE TABLE IF NOT EXISTS licences (
  id                 TEXT PRIMARY KEY,
  group_id           TEXT NOT NULL UNIQUE,
  name               TEXT NOT NULL,
  institution        TEXT,
  seats              INTEGER NOT NULL,
  ends_at            INTEGER NOT NULL,
  paid_models        INTEGER NOT NULL DEFAULT 0,
  monthly_budget_usd REAL NOT NULL DEFAULT 0,
  created_by         TEXT NOT NULL,
  created_at         INTEGER NOT NULL,
  disabled_at        INTEGER
);
CREATE TABLE IF NOT EXISTS licence_seats (
  licence_id TEXT NOT NULL,
  account_id TEXT NOT NULL,
  joined_at  INTEGER NOT NULL,
  removed_at INTEGER,
  PRIMARY KEY (licence_id, account_id)
);
CREATE INDEX IF NOT EXISTS licence_seats_account ON licence_seats (account_id);

-- B - ambassadors. offer_status drives the App Store Connect automation:
-- manual | pending | created | failed
CREATE TABLE IF NOT EXISTS ambassadors (
  id           TEXT PRIMARY KEY,
  name         TEXT NOT NULL,
  school       TEXT NOT NULL,
  offer_ref    TEXT UNIQUE,
  custom_code  TEXT,
  account_id   TEXT,
  active       INTEGER NOT NULL DEFAULT 1,
  offer_status TEXT NOT NULL DEFAULT 'manual',
  offer_error  TEXT,
  created_at   INTEGER NOT NULL
);

-- MARK: D - remote config and the generated-set cache
CREATE TABLE IF NOT EXISTS remote_config (
  id          TEXT PRIMARY KEY,
  version     INTEGER NOT NULL,
  body        TEXT NOT NULL,
  updated_at  INTEGER NOT NULL,
  updated_by  TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS remote_config_history (
  version     INTEGER PRIMARY KEY,
  body        TEXT NOT NULL,
  updated_at  INTEGER NOT NULL,
  updated_by  TEXT NOT NULL,
  note        TEXT
);

CREATE TABLE IF NOT EXISTS gen_cache (
  scope        TEXT NOT NULL,
  source_hash  TEXT NOT NULL,
  recipe_key   TEXT NOT NULL,
  extract      TEXT NOT NULL,
  mode         TEXT NOT NULL,
  items        INTEGER NOT NULL,
  checked      INTEGER NOT NULL DEFAULT 0,
  object_key   TEXT,
  body         TEXT,
  bytes        INTEGER NOT NULL,
  created_by   TEXT NOT NULL,
  created_at   INTEGER NOT NULL,
  hits         INTEGER NOT NULL DEFAULT 0,
  last_hit_at  INTEGER,
  expires_at   INTEGER NOT NULL,
  PRIMARY KEY (scope, source_hash, recipe_key)
);
CREATE INDEX IF NOT EXISTS gen_cache_by_creator ON gen_cache (created_by);
CREATE INDEX IF NOT EXISTS gen_cache_by_expiry  ON gen_cache (expires_at);

-- MARK: E - anonymous, opt-in diagnostics and usage counts (no account, IP or install id anywhere)
CREATE TABLE IF NOT EXISTS diag_groups (
  signature     TEXT PRIMARY KEY,
  kind          TEXT NOT NULL,
  title         TEXT NOT NULL,
  top_frames    TEXT NOT NULL,
  binary_uuid   TEXT,
  symbols       TEXT,
  first_seen    INTEGER NOT NULL,
  last_seen     INTEGER NOT NULL,
  first_version TEXT,
  last_version  TEXT,
  n             INTEGER NOT NULL DEFAULT 0,
  status        TEXT NOT NULL DEFAULT 'open',
  fixed_in      TEXT
);
CREATE INDEX IF NOT EXISTS diag_groups_seen ON diag_groups (last_seen);
CREATE TABLE IF NOT EXISTS diag_counts (
  signature TEXT NOT NULL,
  day       TEXT NOT NULL,
  version   TEXT NOT NULL,
  n         INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (signature, day, version)
);
CREATE TABLE IF NOT EXISTS diag_samples (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  signature   TEXT NOT NULL,
  received_at INTEGER NOT NULL,
  version     TEXT,
  os          TEXT,
  device      TEXT,
  flavour     TEXT,
  body        TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS diag_samples_sig ON diag_samples (signature, received_at);
CREATE TABLE IF NOT EXISTS perf_reports (
  id      INTEGER PRIMARY KEY AUTOINCREMENT,
  day     TEXT NOT NULL,
  version TEXT,
  idiom   TEXT,
  flavour TEXT,
  metrics TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS perf_reports_day ON perf_reports (day);
CREATE TABLE IF NOT EXISTS perf_daily (
  day     TEXT NOT NULL,
  version TEXT NOT NULL,
  idiom   TEXT NOT NULL,
  metric  TEXT NOT NULL,
  n       INTEGER NOT NULL,
  p50     REAL,
  p90     REAL,
  mean    REAL,
  PRIMARY KEY (day, version, idiom, metric)
);
CREATE TABLE IF NOT EXISTS usage_reports (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  day         TEXT NOT NULL,
  received_at INTEGER NOT NULL,
  version     TEXT,
  flavour     TEXT,
  idiom       TEXT,
  lang        TEXT,
  cohort      TEXT,
  counts      TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS usage_reports_day ON usage_reports (day);
CREATE TABLE IF NOT EXISTS usage_daily (
  day     TEXT NOT NULL,
  event   TEXT NOT NULL,
  version TEXT NOT NULL,
  flavour TEXT NOT NULL,
  idiom   TEXT NOT NULL,
  lang    TEXT NOT NULL,
  n       INTEGER NOT NULL DEFAULT 0,
  reports INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (day, event, version, flavour, idiom, lang)
);
CREATE TABLE IF NOT EXISTS usage_cohorts (
  cohort TEXT NOT NULL,
  day    TEXT NOT NULL,
  n      INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (cohort, day)
);
CREATE TABLE IF NOT EXISTS telemetry_budget (
  day  TEXT PRIMARY KEY,
  rows INTEGER NOT NULL DEFAULT 0
);

-- MARK: F - item error reports, support messages, published benchmark summaries
CREATE TABLE IF NOT EXISTS error_reports (
  id           TEXT PRIMARY KEY,
  account_id   TEXT,
  created_at   INTEGER NOT NULL,
  reason       TEXT NOT NULL,
  item_kind    TEXT NOT NULL,
  set_id       TEXT,
  item_id      TEXT,
  share_code   TEXT,
  origin       TEXT,
  model        TEXT,
  source_label TEXT,
  note         TEXT,
  snapshot     TEXT NOT NULL,
  fingerprint  TEXT NOT NULL,
  app_version  TEXT,
  build        TEXT,
  locale       TEXT,
  status       TEXT NOT NULL DEFAULT 'open',
  owner_note   TEXT,
  correction   TEXT,
  resolved_at  INTEGER
);
CREATE INDEX IF NOT EXISTS error_reports_by_status  ON error_reports (status, created_at);
CREATE INDEX IF NOT EXISTS error_reports_by_account ON error_reports (account_id, created_at);
CREATE INDEX IF NOT EXISTS error_reports_by_print   ON error_reports (fingerprint);
CREATE INDEX IF NOT EXISTS error_reports_by_share   ON error_reports (share_code) WHERE share_code IS NOT NULL;

CREATE TABLE IF NOT EXISTS support_messages (
  id         TEXT PRIMARY KEY,
  created_at INTEGER NOT NULL,
  account_id TEXT,
  reply_to   TEXT,
  topic      TEXT NOT NULL,
  body       TEXT NOT NULL,
  locale     TEXT,
  status     TEXT NOT NULL DEFAULT 'open'
);
CREATE INDEX IF NOT EXISTS support_by_status ON support_messages (status, created_at);

CREATE TABLE IF NOT EXISTS bench_runs (
  id           TEXT PRIMARY KEY,
  kind         TEXT NOT NULL,
  dataset      TEXT NOT NULL,
  run_id       TEXT NOT NULL,
  commit_sha   TEXT,
  ran_at       INTEGER NOT NULL,
  published_at INTEGER NOT NULL,
  summary      TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS bench_runs_latest ON bench_runs (kind, dataset, ran_at);
