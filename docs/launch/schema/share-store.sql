-- The second D1 database, redpen-shares (binding SHARE_STORE): the bytes of
-- shared sets, kept out of the main database's 500 MB. Package P0.1 copies this
-- file to server/share-store.sql and the deploy workflow applies it.
CREATE TABLE IF NOT EXISTS share_manifests (
  share_id TEXT NOT NULL,
  version  INTEGER NOT NULL,
  part     INTEGER NOT NULL,
  data     BLOB NOT NULL,
  PRIMARY KEY (share_id, version, part)
);
CREATE TABLE IF NOT EXISTS share_blobs (
  share_id TEXT NOT NULL,
  hash     TEXT NOT NULL,
  bytes    INTEGER NOT NULL,
  data     BLOB NOT NULL,
  PRIMARY KEY (share_id, hash)
);
