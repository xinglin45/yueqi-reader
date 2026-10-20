import 'dart:convert';

import 'package:reader_storage/reader_storage.dart';

import '../../domain/documents.dart';
import '../../domain/jobs.dart';
import '../../domain/library.dart';
import '../session_library.dart';

/// Real local storage; only the owned preview is admitted before MAC-04 import.
final class LocalLibrary implements LibraryRepository, PositionRepository {
  LocalLibrary(this.database, this.files);
  final StorageDatabase database;
  final ContentFiles files;
  static const chapterId = 'preview-chapter-3';
  static const spine = 'managed.txt';
  static const parser = 'owned-preview-v1';
  static final sampleBytes = utf8.encode(
    ['第三章　山路微光', ...SessionLibrary.sampleParagraphs].join('\n\n'),
  );

  BookSummary _book(Map<String, Object?> row) => BookSummary(
    id: row['id']! as String,
    title: row['title']! as String,
    subtitle: '原创演示短篇 · 已保存在本机',
    demo: true,
    persistent: true,
  );
  @override
  Future<JobResult<List<BookSummary>>> load(JobContext job) async {
    job.checkCancelled();
    final rows = await database.query(
      "SELECT * FROM books WHERE deleted=0 AND rating='general' ORDER BY created_at,id LIMIT 200",
    );
    job.checkCancelled();
    final books = rows.map(_book).toList();
    return JobResult(books, empty: books.isEmpty);
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
    return load(job);
  }

  @override
  Future<JobResult<ReadingPreview>> preview(
    String bookId,
    JobContext job,
  ) async {
    job.checkCancelled();
    final rows = await database.query(
      '''SELECT b.*, d.id AS document_id,d.digest,d.parser_version
      FROM books b JOIN documents d ON d.book_id=b.id
      WHERE b.id=? AND b.deleted=0 AND b.rating='general' ORDER BY d.created_at DESC,d.id LIMIT 1''',
      [bookId],
    );
    if (rows.isEmpty) throw const AppFailure(FailureCode.missing);
    final row = rows.single;
    if (row['parser_version'] != parser) {
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
    final chunks = text.split('\n\n');
    final paragraphs = chunks.skip(1).toList();
    final saved = await loadPosition(bookId, PositionChannel.reading);
    String? restored;
    if (saved != null) {
      final resolution = saved.anchor.resolve(
        currentRevision: row['document_id']! as String,
        currentChapter: chapterId,
        currentSpine: spine,
        blocks: {for (final (i, p) in paragraphs.indexed) 'p$i': p},
      );
      if (resolution.match == AnchorMatch.exact) {
        restored = saved.anchor.blockId;
      }
    }
    job.checkCancelled();
    return JobResult(
      ReadingPreview(
        book: _book(row),
        chapter: chunks.first,
        paragraphs: paragraphs,
        documentRevision: row['document_id']! as String,
        chapterId: chapterId,
        spineHref: spine,
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
    final rows = await database.query(
      'SELECT * FROM positions WHERE book_id=? AND channel=?',
      [bookId, channel.name],
    );
    if (rows.isEmpty) return null;
    final row = rows.single;
    final anchor = DocumentAnchor.fromJson(
      jsonDecode(row['anchor']! as String) as Map<String, dynamic>,
    );
    if (anchor.revision != row['document_id']) {
      throw const FormatException('position_revision');
    }
    return StoredPosition(bookId, channel, anchor, row['local_seq']! as int);
  }

  @override
  Future<StoredPosition> savePosition(
    String bookId,
    PositionChannel channel,
    DocumentAnchor anchor, {
    required int expectedSequence,
  }) async {
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
