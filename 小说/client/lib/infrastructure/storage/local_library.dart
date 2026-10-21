import 'dart:convert';

import 'package:reader_storage/reader_storage.dart';

import '../../domain/documents.dart';
import '../../domain/access.dart';
import '../../application/access.dart';
import '../../domain/jobs.dart';
import '../../domain/library.dart';
import '../session_library.dart';

/// Real local storage; only the owned preview is admitted before MAC-04 import.
final class LocalLibrary
    implements LibraryRepository, PositionRepository, AdultLibrary {
  LocalLibrary(this.database, this.files, {this.access});
  final AccessController? access;
  AccessState get _access => access?.state ?? const AccessState();
  final StorageDatabase database;
  final ContentFiles files;
  // A stored upstream grant is historical metadata, never a new session grant.
  final _verifiedSourceAccess = <String>{};
  static const chapterId = 'preview-chapter-3';
  static const spine = 'managed.txt';
  static const parser = 'owned-preview-v1';
  static final sampleBytes = utf8.encode(
    ['第三章　山路微光', ...SessionLibrary.sampleParagraphs].join('\n\n'),
  );

  BookSummary _book(Map<String, Object?> row) => BookSummary(
    id: row['id']! as String,
    title: row['title']! as String,
    subtitle: row['parser_hint'] == 'import-v1'
        ? '文件已导入 · 阅读解析待接入'
        : row['parser_hint'] == 'classification-card-v1'
        ? '标签测试 · 不含成人正文'
        : '原创演示短篇 · 已保存在本机',
    demo: row['parser_hint'] == parser,
    previewAvailable: row['parser_hint'] != 'import-v1',
    protected: _rating(row).protected,
    persistent: true,
  );
  ContentRating _rating(Map<String, Object?> row) {
    final name =
        row['policy_level'] ??
        (row['rating'] == 'adult' ? 'restricted' : row['rating']);
    final level =
        RatingLevel.values.where((v) => v.name == name).firstOrNull ??
        RatingLevel.unknown;
    final recordedSource =
        SourceAccess.values
            .where((v) => v.name == row['source_access'])
            .firstOrNull ??
        (row['rating_evidence'] == 'owned-preview-v1'
            ? SourceAccess.notRequired
            : SourceAccess.unknown);
    return ContentRating(
      level: level,
      raw: row['policy_raw'] as String?,
      minimumAge: row['minimum_age'] as int?,
      originalRegions: row['original_regions'] is String
          ? (jsonDecode(row['original_regions']! as String) as List<dynamic>)
                .cast<String>()
          : const [],
      evidence: row['policy_evidence'] as String?,
      policyVersion: (row['policy_version'] as String?) ?? 'legacy-v3',
      sourceAccess:
          recordedSource == SourceAccess.allowed &&
              !_verifiedSourceAccess.contains(row['id'])
          ? SourceAccess.unknown
          : recordedSource,
    );
  }

  bool get _hasPolicy => (database.info['version']! as int) >= 4;
  String get _policyColumns => _hasPolicy
      ? 'p.level AS policy_level,p.raw_rating AS policy_raw,p.minimum_age,p.original_regions,p.evidence AS policy_evidence,p.policy_version,p.source_access'
      : 'NULL AS policy_level';
  String get _policyJoin =>
      _hasPolicy ? 'LEFT JOIN content_policy p ON p.book_id=b.id' : '';
  Future<void> checkAccess(String bookId) async {
    await _admit(bookId);
  }

  Future<ContentRating> _admit(String bookId) async {
    final rows = await database.query(
      'SELECT b.id,b.rating,b.rating_evidence,$_policyColumns FROM books b $_policyJoin WHERE b.id=? AND b.deleted=0',
      [bookId],
    );
    if (rows.isEmpty) throw const AppFailure(FailureCode.missing);
    final rating = _rating(rows.single);
    if (!mayRead(rating, _access)) {
      throw const AppFailure(FailureCode.permissionDenied);
    }
    return rating;
  }

  Future<void> _recheck(String bookId, ContentRating rating, int ticket) async {
    if (rating.protected && ticket != _access.visibilityRevision) {
      throw const AppFailure(FailureCode.permissionDenied);
    }
    await _admit(bookId);
    if (rating.protected && ticket != _access.visibilityRevision) {
      throw const AppFailure(FailureCode.permissionDenied);
    }
  }

  Future<JobResult<List<BookSummary>>> _loadGroup(
    JobContext job,
    bool adult,
  ) async {
    job.checkCancelled();
    final ticket = _access.visibilityRevision;
    if (adult && !_access.adultVisible) {
      throw const AppFailure(FailureCode.permissionDenied);
    }
    final condition = adult
        ? (_hasPolicy
              ? "(p.level IN ('mature','restricted') OR p.minimum_age>=18 OR b.rating='adult')"
              : "b.rating='adult'")
        : (_hasPolicy
              ? "b.rating='general' AND (p.level IS NULL OR p.level='general') AND (p.minimum_age IS NULL OR p.minimum_age<18)"
              : "b.rating='general'");
    final rows = await database.query(
      'SELECT b.*,$_policyColumns,(SELECT parser_version FROM documents d WHERE d.book_id=b.id LIMIT 1) AS parser_hint FROM books b $_policyJoin WHERE b.deleted=0 AND $condition ORDER BY b.created_at,b.id LIMIT 200',
    );
    job.checkCancelled();
    if (adult &&
        (!_access.adultVisible || ticket != _access.visibilityRevision)) {
      throw const AppFailure(FailureCode.permissionDenied);
    }
    final books = rows
        .where((row) => mayRead(_rating(row), _access))
        .map(_book)
        .toList();
    return JobResult(books, empty: books.isEmpty);
  }

  @override
  Future<JobResult<List<BookSummary>>> load(JobContext job) =>
      _loadGroup(job, false);
  @override
  Future<JobResult<List<BookSummary>>> loadAdult(JobContext job) =>
      _loadGroup(job, true);
  @override
  Future<JobResult<List<BookSummary>>> addClassificationCard(
    JobContext job,
  ) async {
    if (!_access.adultVisible || !_hasPolicy) {
      throw const AppFailure(FailureCode.permissionDenied);
    }
    job.checkCancelled();
    final ticket = _access.visibilityRevision;
    final bytes = utf8.encode('分级测试卡片\n\n这是自产的标签测试卡片，不含成人正文，仅验证分组和隐私操作。');
    final digest = await files.put(bytes);
    job.checkCancelled();
    if (!_access.adultVisible || ticket != _access.visibilityRevision) {
      throw const AppFailure(FailureCode.permissionDenied);
    }
    final existing = await database.query(
      'SELECT id FROM documents WHERE digest=?',
      [digest],
    );
    job.checkCancelled();
    if (!_access.adultVisible || ticket != _access.visibilityRevision) {
      throw const AppFailure(FailureCode.permissionDenied);
    }
    if (existing.isEmpty) {
      final book = newLocalId(),
          revision = 'sha256:$digest:classification-card-v1',
          now = DateTime.now().millisecondsSinceEpoch;
      await database.transaction([
        SqlCommand(
          'INSERT INTO books(id,title,language,rating,rating_evidence,created_at,updated_at) VALUES(?,?,?,?,?,?,?)',
          [
            book,
            '分级测试卡片',
            'zh',
            'adult',
            'owned-classification-card',
            now,
            now,
          ],
        ),
        SqlCommand(
          'INSERT INTO content_policy(book_id,raw_rating,level,minimum_age,evidence,policy_version,source_access) VALUES(?,?,?,?,?,?,?)',
          [
            book,
            '18+ 测试标签',
            'restricted',
            18,
            'owned-metadata-only',
            'local-v1',
            'notRequired',
          ],
        ),
        SqlCommand(
          'INSERT INTO documents(id,book_id,digest,kind,media_type,byte_length,parser_version,created_at) VALUES(?,?,?,?,?,?,?,?)',
          [
            revision,
            book,
            digest,
            'txt',
            'text/plain',
            bytes.length,
            'classification-card-v1',
            now,
          ],
        ),
        SqlCommand(
          'INSERT INTO chapters(id,document_id,ordinal,title,spine_href) VALUES(?,?,?,?,?)',
          ['classification-card', revision, 0, '分级测试卡片', 'card.txt'],
        ),
        SqlCommand(
          'INSERT INTO resources(document_id,href,digest,media_type,byte_length,cache_permission) VALUES(?,?,?,?,?,?)',
          [revision, 'card.txt', digest, 'text/plain', bytes.length, 'allowed'],
        ),
        SqlCommand(
          "INSERT OR IGNORE INTO collections(id,label,kind) VALUES('adult-default','成人收藏','adult')",
        ),
        SqlCommand("INSERT INTO collection_books VALUES('adult-default',?)", [
          book,
        ]),
      ]);
    }
    return loadAdult(job);
  }

  Future<void> setSourceAccess(String bookId, SourceAccess value) async {
    await database.transaction([
      SqlCommand('UPDATE content_policy SET source_access=? WHERE book_id=?', [
        value.name,
        bookId,
      ], 1),
    ]);
    if (value == SourceAccess.allowed) {
      _verifiedSourceAccess.add(bookId);
    } else {
      _verifiedSourceAccess.remove(bookId);
    }
    access?.invalidateProtected();
  }

  @override
  Future<JobResult<List<BookSummary>>> addDemonstration(JobContext job) async {
    job.checkCancelled();
    final digest = await files.put(sampleBytes);
    job.checkCancelled();
    final known = await database.query(
      'SELECT book_id FROM documents WHERE digest=? AND kind=?',
      [digest, 'txt'],
    );
    if (known.isEmpty) {
      final book = newLocalId(), revision = 'sha256:$digest:$parser';
      final now = DateTime.now().millisecondsSinceEpoch;
      job.checkCancelled();
      await database.transaction([
        SqlCommand(
          'INSERT INTO books(id,title,language,rating,rating_evidence,created_at,updated_at) VALUES(?,?,?,?,?,?,?)',
          [book, '山间来信', 'zh-Hans', 'general', 'owned-preview-v1', now, now],
        ),
        SqlCommand(
          'INSERT INTO documents(id,book_id,digest,kind,media_type,byte_length,parser_version,created_at) VALUES(?,?,?,?,?,?,?,?)',
          [
            revision,
            book,
            digest,
            'txt',
            'text/plain;charset=utf-8',
            sampleBytes.length,
            parser,
            now,
          ],
        ),
        SqlCommand(
          'INSERT INTO chapters(id,document_id,ordinal,title,spine_href) VALUES(?,?,?,?,?)',
          [chapterId, revision, 0, '第三章　山路微光', spine],
        ),
        SqlCommand(
          'INSERT INTO resources(document_id,href,digest,media_type,byte_length,cache_permission) VALUES(?,?,?,?,?,?)',
          [
            revision,
            spine,
            digest,
            'text/plain',
            sampleBytes.length,
            'allowed',
          ],
        ),
      ]);
    }
    if (_hasPolicy) {
      await database.transaction([
        SqlCommand(
          "INSERT OR IGNORE INTO content_policy(book_id,level,evidence,policy_version,source_access) SELECT book_id,'general','owned-preview-v1','local-v1','notRequired' FROM documents WHERE digest=?",
          [digest],
        ),
      ]);
    }
    return load(job);
  }

  @override
  Future<JobResult<ReadingPreview>> preview(
    String bookId,
    JobContext job,
  ) async {
    job.checkCancelled();
    final ticket = _access.visibilityRevision;
    final classification = await _admit(bookId);
    final rows = await database.query(
      '''SELECT b.*, d.id AS document_id,d.digest,d.parser_version AS parser_hint,d.parser_version
      FROM books b JOIN documents d ON d.book_id=b.id
      WHERE b.id=? AND b.deleted=0 ORDER BY d.created_at DESC,d.id LIMIT 1''',
      [bookId],
    );
    if (rows.isEmpty) throw const AppFailure(FailureCode.missing);
    final row = rows.single;
    if (row['parser_version'] != parser &&
        row['parser_version'] != 'classification-card-v1') {
      throw const AppFailure(FailureCode.unsupported);
    }
    late final String text;
    try {
      text = utf8.decode(await files.read(row['digest']! as String));
    } on StorageFailure catch (error) {
      throw AppFailure(
        error.code == 'file_missing'
            ? FailureCode.missing
            : FailureCode.corrupt,
      );
    }
    final chapters = await database.query(
      'SELECT id,spine_href FROM chapters WHERE document_id=? ORDER BY ordinal LIMIT 1',
      [row['document_id']],
    );
    if (chapters.isEmpty) throw const AppFailure(FailureCode.corrupt);
    final activeChapter = chapters.single['id']! as String,
        activeSpine = chapters.single['spine_href']! as String;
    final chunks = text.split('\n\n');
    final paragraphs = chunks.skip(1).toList();
    final saved = await loadPosition(bookId, PositionChannel.reading);
    String? restored;
    if (saved != null) {
      final resolution = saved.anchor.resolve(
        currentRevision: row['document_id']! as String,
        currentChapter: activeChapter,
        currentSpine: activeSpine,
        blocks: {for (final (i, p) in paragraphs.indexed) 'p$i': p},
      );
      if (resolution.match == AnchorMatch.exact) {
        restored = saved.anchor.blockId;
      }
    }
    job.checkCancelled();
    await _recheck(bookId, classification, ticket);
    return JobResult(
      ReadingPreview(
        book: _book({
          ...row,
          'policy_level': classification.level.name,
          'minimum_age': classification.minimumAge,
          'source_access': classification.sourceAccess.name,
        }),
        chapter: chunks.first,
        paragraphs: paragraphs,
        documentRevision: row['document_id']! as String,
        chapterId: activeChapter,
        spineHref: activeSpine,
        blockIds: List.generate(paragraphs.length, (i) => 'p$i'),
        restoredBlockId: restored,
        positionSequence: saved?.sequence ?? 0,
        positionNeedsReview: saved != null && restored == null,
      ),
    );
  }

  @override
  Future<StoredPosition?> loadPosition(
    String bookId,
    PositionChannel channel,
  ) async {
    final ticket = _access.visibilityRevision;
    final classification = await _admit(bookId);
    final rows = await database.query(
      'SELECT * FROM positions WHERE book_id=? AND channel=?',
      [bookId, channel.name],
    );
    if (rows.isEmpty) {
      await _recheck(bookId, classification, ticket);
      return null;
    }
    final row = rows.single;
    final anchor = DocumentAnchor.fromJson(
      jsonDecode(row['anchor']! as String) as Map<String, dynamic>,
    );
    if (anchor.revision != row['document_id']) {
      throw const FormatException('position_revision');
    }
    await _recheck(bookId, classification, ticket);
    return StoredPosition(bookId, channel, anchor, row['local_seq']! as int);
  }

  @override
  Future<StoredPosition> savePosition(
    String bookId,
    PositionChannel channel,
    DocumentAnchor anchor, {
    required int expectedSequence,
  }) async {
    final ticket = _access.visibilityRevision;
    final classification = await _admit(bookId);
    if (expectedSequence < 0) throw const FormatException('sequence');
    // Parsing our own encoding also enforces wire limits before persistence.
    DocumentAnchor.fromJson(anchor.toJson());
    await database.transaction([
      SqlCommand(
        '''INSERT INTO positions(book_id,channel,document_id,anchor,local_seq,updated_at)
      SELECT ?,?,?,?,?,? WHERE ?=0 OR EXISTS(SELECT 1 FROM positions WHERE book_id=? AND channel=? AND local_seq=?) ON CONFLICT(book_id,channel) DO UPDATE SET
      document_id=excluded.document_id,anchor=excluded.anchor,local_seq=excluded.local_seq,updated_at=excluded.updated_at
      WHERE positions.local_seq=?''',
        [
          bookId,
          channel.name,
          anchor.revision,
          jsonEncode(anchor.toJson()),
          expectedSequence + 1,
          DateTime.now().millisecondsSinceEpoch,
          expectedSequence,
          bookId,
          channel.name,
          expectedSequence,
          expectedSequence,
        ],
        1,
      ),
    ]);
    await _recheck(bookId, classification, ticket);
    return StoredPosition(bookId, channel, anchor, expectedSequence + 1);
  }

  Future<void> saveSetting(String key, Object value) async {
    if (key == 'theme' && value != 'light' && value != 'dark') {
      throw const FormatException('theme');
    }
    if (key == 'text_scale' &&
        (value is! num || !value.isFinite || value < 0.5 || value > 3)) {
      throw const FormatException('scale');
    }
    await database.transaction([
      SqlCommand(
        '''INSERT INTO settings(key,value) VALUES(?,?)
      ON CONFLICT(key) DO UPDATE SET value=excluded.value,row_revision=settings.row_revision+1''',
        [key, jsonEncode(value)],
      ),
    ]);
  }

  Future<Object?> loadSetting(String key) async {
    final rows = await database.query(
      'SELECT value FROM settings WHERE key=?',
      [key],
    );
    return rows.isEmpty ? null : jsonDecode(rows.single['value']! as String);
  }
}
