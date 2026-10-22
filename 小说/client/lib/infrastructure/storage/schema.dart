import 'package:reader_storage/reader_storage.dart';

/// Novel-owned SQL; reader_storage does not know either product's entities.
const _initialSchema = [
  SchemaStep(1, [
    '''CREATE TABLE books (
      id TEXT PRIMARY KEY, title TEXT NOT NULL, language TEXT NOT NULL,
      rating TEXT NOT NULL DEFAULT 'unknown' CHECK(rating IN ('general','adult','unknown','prohibited')),
      rating_evidence TEXT, raw_rating TEXT, row_revision INTEGER NOT NULL DEFAULT 1,
      deleted INTEGER NOT NULL DEFAULT 0 CHECK(deleted IN (0,1)),
      created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL
    ) STRICT''',
    '''CREATE TABLE documents (
      id TEXT PRIMARY KEY, book_id TEXT NOT NULL REFERENCES books(id),
      digest TEXT NOT NULL CHECK(length(digest)=64),
      kind TEXT NOT NULL CHECK(kind IN ('txt','epub')),
      media_type TEXT NOT NULL, byte_length INTEGER NOT NULL CHECK(byte_length>=0),
      parser_version TEXT NOT NULL, created_at INTEGER NOT NULL,
      UNIQUE(book_id,id), UNIQUE(digest,kind)
    ) STRICT''',
    '''CREATE TABLE chapters (
      id TEXT NOT NULL, document_id TEXT NOT NULL REFERENCES documents(id),
      ordinal INTEGER NOT NULL CHECK(ordinal>=0), title TEXT NOT NULL,
      spine_href TEXT NOT NULL, PRIMARY KEY(document_id,id), UNIQUE(document_id,ordinal)
    ) STRICT''',
    '''CREATE TABLE resources (
      document_id TEXT NOT NULL REFERENCES documents(id), href TEXT NOT NULL,
      digest TEXT NOT NULL CHECK(length(digest)=64), media_type TEXT NOT NULL,
      byte_length INTEGER NOT NULL CHECK(byte_length>=0),
      cache_permission TEXT NOT NULL DEFAULT 'unknown' CHECK(cache_permission IN ('unknown','allowed','denied')),
      PRIMARY KEY(document_id,href)
    ) STRICT''',
    '''CREATE TABLE positions (
      book_id TEXT NOT NULL, channel TEXT NOT NULL CHECK(channel IN ('reading','listening')),
      document_id TEXT NOT NULL, anchor TEXT NOT NULL CHECK(json_valid(anchor)),
      local_seq INTEGER NOT NULL CHECK(local_seq>0), updated_at INTEGER NOT NULL,
      PRIMARY KEY(book_id,channel),
      FOREIGN KEY(book_id,document_id) REFERENCES documents(book_id,id)
    ) STRICT''',
  ]),
  SchemaStep(2, [
    '''CREATE TABLE annotations (
      id TEXT PRIMARY KEY, book_id TEXT NOT NULL, document_id TEXT NOT NULL,
      kind TEXT NOT NULL CHECK(kind IN ('bookmark','highlight','note')),
      anchor TEXT NOT NULL CHECK(json_valid(anchor)), note TEXT NOT NULL DEFAULT '',
      row_revision INTEGER NOT NULL DEFAULT 1,
      deleted INTEGER NOT NULL DEFAULT 0 CHECK(deleted IN (0,1)), updated_at INTEGER NOT NULL,
      FOREIGN KEY(book_id,document_id) REFERENCES documents(book_id,id)
    ) STRICT''',
    '''CREATE TABLE collections (
      id TEXT PRIMARY KEY, label TEXT NOT NULL,
      kind TEXT NOT NULL CHECK(kind IN ('collection','tag','adult')),
      row_revision INTEGER NOT NULL DEFAULT 1,
      deleted INTEGER NOT NULL DEFAULT 0 CHECK(deleted IN (0,1))
    ) STRICT''',
    '''CREATE TABLE collection_books (
      collection_id TEXT NOT NULL REFERENCES collections(id),
      book_id TEXT NOT NULL REFERENCES books(id), PRIMARY KEY(collection_id,book_id)
    ) STRICT''',
    '''CREATE TABLE source_bindings (
      id TEXT PRIMARY KEY, book_id TEXT NOT NULL REFERENCES books(id),
      source_id TEXT NOT NULL, source_item_id TEXT NOT NULL,
      verification TEXT NOT NULL DEFAULT 'unknown',
      cache_permission TEXT NOT NULL DEFAULT 'unknown' CHECK(cache_permission IN ('unknown','allowed','denied')),
      credential_ref TEXT, row_revision INTEGER NOT NULL DEFAULT 1,
      deleted INTEGER NOT NULL DEFAULT 0 CHECK(deleted IN (0,1)),
      UNIQUE(source_id,source_item_id)
    ) STRICT''',
    '''CREATE TABLE jobs (
      id TEXT PRIMARY KEY, kind TEXT NOT NULL CHECK(kind IN ('import','download')),
      book_id TEXT REFERENCES books(id), state TEXT NOT NULL,
      progress REAL CHECK(progress IS NULL OR (progress>=0 AND progress<=1)),
      error_code TEXT, updated_at INTEGER NOT NULL
    ) STRICT''',
    '''CREATE TABLE settings (
      key TEXT PRIMARY KEY CHECK(key IN ('theme','text_scale')),
      value TEXT NOT NULL CHECK(json_valid(value)), row_revision INTEGER NOT NULL DEFAULT 1
    ) STRICT''',
    'CREATE INDEX positions_document ON positions(document_id)',
    'CREATE INDEX books_visibility ON books(deleted,rating)',
  ]),
];

/// v3 keeps historical parser revisions of identical source bytes. Children are
/// staged and recreated before replacing the parent, keeping FK checks enabled.
final List<SchemaStep> novelSchema = List.unmodifiable([
  ..._initialSchema,
  SchemaStep(3, [
    for (final table in ['chapters', 'resources', 'positions', 'annotations'])
      'CREATE TEMP TABLE migrate_$table AS SELECT * FROM $table',
    for (final table in ['annotations', 'positions', 'resources', 'chapters'])
      'DROP TABLE $table',
    _initialSchema[0].statements[1]
        .replaceFirst('CREATE TABLE documents', 'CREATE TABLE documents_next')
        .replaceFirst(
          'UNIQUE(digest,kind)',
          'UNIQUE(digest,kind,parser_version)',
        ),
    'INSERT INTO documents_next SELECT * FROM documents',
    'DROP TABLE documents',
    'ALTER TABLE documents_next RENAME TO documents',
    _initialSchema[0].statements[2],
    _initialSchema[0].statements[3],
    _initialSchema[0].statements[4],
    _initialSchema[1].statements[0],
    for (final table in ['chapters', 'resources', 'positions', 'annotations'])
      'INSERT INTO $table SELECT * FROM migrate_$table',
    for (final table in ['chapters', 'resources', 'positions', 'annotations'])
      'DROP TABLE temp.migrate_$table',
    'CREATE INDEX positions_document ON positions(document_id)',
  ]),
  contentPolicySchema,
  importSchema,
  txtSchema,
]);

/// Device declaration/search/lock flags remain outside this library schema.
const contentPolicySchema = SchemaStep(4, [
  '''CREATE TABLE content_policy (
    book_id TEXT PRIMARY KEY REFERENCES books(id),
    raw_rating TEXT, level TEXT NOT NULL CHECK(level IN ('general','mature','restricted','unknown','prohibited')),
    minimum_age INTEGER CHECK(minimum_age IS NULL OR minimum_age>=0),
    original_regions TEXT NOT NULL DEFAULT '[]' CHECK(json_valid(original_regions)),
    evidence TEXT, policy_version TEXT NOT NULL,
    regional_review TEXT NOT NULL DEFAULT 'skipped_by_user' CHECK(regional_review='skipped_by_user'),
    source_access TEXT NOT NULL DEFAULT 'unknown' CHECK(source_access IN ('notRequired','allowed','loginRequired','ageRequired','paid','expired','unknown'))
  ) STRICT''',
  '''INSERT INTO content_policy(book_id,raw_rating,level,evidence,policy_version,source_access)
    SELECT id,raw_rating,CASE rating WHEN 'adult' THEN 'restricted' ELSE rating END,
      rating_evidence,'legacy-v3',CASE WHEN rating='general' AND rating_evidence='owned-preview-v1' THEN 'notRequired' ELSE 'unknown' END FROM books''',
  'CREATE INDEX content_policy_level ON content_policy(level)',
]);

const importSchema = SchemaStep(5, [
  """CREATE TABLE imports (
    document_id TEXT PRIMARY KEY REFERENCES documents(id),
    mode TEXT NOT NULL CHECK(mode IN ('managed','reference')),
    grant_id TEXT, encoding TEXT CHECK(encoding IN ('utf8','utf16le','utf16be','gb18030','big5')),
    status TEXT NOT NULL CHECK(status='awaiting_parser'),
    CHECK((mode='managed' AND grant_id IS NULL) OR (mode='reference' AND grant_id IS NOT NULL))
  ) STRICT""",
]);

const txtSchema = SchemaStep(6, [
  """CREATE TABLE txt_indices (
    document_id TEXT PRIMARY KEY REFERENCES documents(id),
    source_document_id TEXT NOT NULL REFERENCES imports(document_id),
    encoding TEXT NOT NULL, rules TEXT NOT NULL CHECK(json_valid(rules)),
    block_count INTEGER NOT NULL CHECK(block_count>0 AND block_count<=1000000),
    utf16_length INTEGER NOT NULL CHECK(utf16_length>0),
    chapter_count INTEGER NOT NULL CHECK(chapter_count>0 AND chapter_count<=20001),
    index_digest TEXT NOT NULL CHECK(length(index_digest)=64),
    text_digest TEXT NOT NULL CHECK(length(text_digest)=64)
  ) STRICT""",
  """CREATE TABLE txt_chapter_ranges (
    document_id TEXT NOT NULL, chapter_id TEXT NOT NULL,
    first_block INTEGER NOT NULL CHECK(first_block>=0),
    end_block INTEGER NOT NULL CHECK(end_block>first_block),
    PRIMARY KEY(document_id,chapter_id),
    FOREIGN KEY(document_id,chapter_id) REFERENCES chapters(document_id,id)
  ) STRICT""",
  """CREATE TABLE txt_active (
    book_id TEXT PRIMARY KEY REFERENCES books(id),
    document_id TEXT NOT NULL REFERENCES txt_indices(document_id),
    FOREIGN KEY(book_id,document_id) REFERENCES documents(book_id,id)
  ) STRICT""",
]);
