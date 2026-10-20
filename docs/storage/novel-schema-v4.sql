-- MAC-16 actual SQLite schema v4, 2026-10-20. No user records.
CREATE INDEX books_visibility ON books(deleted,rating);
CREATE INDEX content_policy_level ON content_policy(level);
CREATE INDEX positions_document ON positions(document_id);
CREATE TABLE annotations (
      id TEXT PRIMARY KEY, book_id TEXT NOT NULL, document_id TEXT NOT NULL,
      kind TEXT NOT NULL CHECK(kind IN ('bookmark','highlight','note')),
      anchor TEXT NOT NULL CHECK(json_valid(anchor)), note TEXT NOT NULL DEFAULT '',
      row_revision INTEGER NOT NULL DEFAULT 1,
      deleted INTEGER NOT NULL DEFAULT 0 CHECK(deleted IN (0,1)), updated_at INTEGER NOT NULL,
      FOREIGN KEY(book_id,document_id) REFERENCES documents(book_id,id)
    ) STRICT;
CREATE TABLE books (
      id TEXT PRIMARY KEY, title TEXT NOT NULL, language TEXT NOT NULL,
      rating TEXT NOT NULL DEFAULT 'unknown' CHECK(rating IN ('general','adult','unknown','prohibited')),
      rating_evidence TEXT, raw_rating TEXT, row_revision INTEGER NOT NULL DEFAULT 1,
      deleted INTEGER NOT NULL DEFAULT 0 CHECK(deleted IN (0,1)),
      created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL
    ) STRICT;
CREATE TABLE chapters (
      id TEXT NOT NULL, document_id TEXT NOT NULL REFERENCES documents(id),
      ordinal INTEGER NOT NULL CHECK(ordinal>=0), title TEXT NOT NULL,
      spine_href TEXT NOT NULL, PRIMARY KEY(document_id,id), UNIQUE(document_id,ordinal)
    ) STRICT;
CREATE TABLE collection_books (
      collection_id TEXT NOT NULL REFERENCES collections(id),
      book_id TEXT NOT NULL REFERENCES books(id), PRIMARY KEY(collection_id,book_id)
    ) STRICT;
CREATE TABLE collections (
      id TEXT PRIMARY KEY, label TEXT NOT NULL,
      kind TEXT NOT NULL CHECK(kind IN ('collection','tag','adult')),
      row_revision INTEGER NOT NULL DEFAULT 1,
      deleted INTEGER NOT NULL DEFAULT 0 CHECK(deleted IN (0,1))
    ) STRICT;
CREATE TABLE content_policy (
    book_id TEXT PRIMARY KEY REFERENCES books(id),
    raw_rating TEXT, level TEXT NOT NULL CHECK(level IN ('general','mature','restricted','unknown','prohibited')),
    minimum_age INTEGER CHECK(minimum_age IS NULL OR minimum_age>=0),
    original_regions TEXT NOT NULL DEFAULT '[]' CHECK(json_valid(original_regions)),
    evidence TEXT, policy_version TEXT NOT NULL,
    regional_review TEXT NOT NULL DEFAULT 'skipped_by_user' CHECK(regional_review='skipped_by_user'),
    source_access TEXT NOT NULL DEFAULT 'unknown' CHECK(source_access IN ('notRequired','allowed','loginRequired','ageRequired','paid','expired','unknown'))
  ) STRICT;
CREATE TABLE "documents" (
      id TEXT PRIMARY KEY, book_id TEXT NOT NULL REFERENCES books(id),
      digest TEXT NOT NULL CHECK(length(digest)=64),
      kind TEXT NOT NULL CHECK(kind IN ('txt','epub')),
      media_type TEXT NOT NULL, byte_length INTEGER NOT NULL CHECK(byte_length>=0),
      parser_version TEXT NOT NULL, created_at INTEGER NOT NULL,
      UNIQUE(book_id,id), UNIQUE(digest,kind,parser_version)
    ) STRICT;
CREATE TABLE jobs (
      id TEXT PRIMARY KEY, kind TEXT NOT NULL CHECK(kind IN ('import','download')),
      book_id TEXT REFERENCES books(id), state TEXT NOT NULL,
      progress REAL CHECK(progress IS NULL OR (progress>=0 AND progress<=1)),
      error_code TEXT, updated_at INTEGER NOT NULL
    ) STRICT;
CREATE TABLE positions (
      book_id TEXT NOT NULL, channel TEXT NOT NULL CHECK(channel IN ('reading','listening')),
      document_id TEXT NOT NULL, anchor TEXT NOT NULL CHECK(json_valid(anchor)),
      local_seq INTEGER NOT NULL CHECK(local_seq>0), updated_at INTEGER NOT NULL,
      PRIMARY KEY(book_id,channel),
      FOREIGN KEY(book_id,document_id) REFERENCES documents(book_id,id)
    ) STRICT;
CREATE TABLE resources (
      document_id TEXT NOT NULL REFERENCES documents(id), href TEXT NOT NULL,
      digest TEXT NOT NULL CHECK(length(digest)=64), media_type TEXT NOT NULL,
      byte_length INTEGER NOT NULL CHECK(byte_length>=0),
      cache_permission TEXT NOT NULL DEFAULT 'unknown' CHECK(cache_permission IN ('unknown','allowed','denied')),
      PRIMARY KEY(document_id,href)
    ) STRICT;
CREATE TABLE settings (
      key TEXT PRIMARY KEY CHECK(key IN ('theme','text_scale')),
      value TEXT NOT NULL CHECK(json_valid(value)), row_revision INTEGER NOT NULL DEFAULT 1
    ) STRICT;
CREATE TABLE source_bindings (
      id TEXT PRIMARY KEY, book_id TEXT NOT NULL REFERENCES books(id),
      source_id TEXT NOT NULL, source_item_id TEXT NOT NULL,
      verification TEXT NOT NULL DEFAULT 'unknown',
      cache_permission TEXT NOT NULL DEFAULT 'unknown' CHECK(cache_permission IN ('unknown','allowed','denied')),
      credential_ref TEXT, row_revision INTEGER NOT NULL DEFAULT 1,
      deleted INTEGER NOT NULL DEFAULT 0 CHECK(deleted IN (0,1)),
      UNIQUE(source_id,source_item_id)
    ) STRICT;
