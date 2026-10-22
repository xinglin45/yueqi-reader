import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:reader_storage/reader_storage.dart';

import '../../domain/txt.dart';
import '../../domain/jobs.dart';
import '../../domain/importing.dart';
import '../importing/local_importer.dart';
import 'decoder.dart';
import 'parser.dart';

final class LocalTxtReader implements TxtDocumentReader {
  LocalTxtReader(this.importer);
  final LocalImporter importer;
  StorageDatabase get db => importer.library.database;
  String get root => importer.root;
  final _pending =
      <String, (String, Map<String, dynamic>, Map<String, Object?>)>{};
  Future<TxtIndex>? _building;
  bool _closed = false;
  Future<void> initialize() async {
    final stage = Directory('$root/txt-stage');
    if (await FileSystemEntity.type(stage.path, followLinks: false) ==
        FileSystemEntityType.link) {
      throw const AppFailure(FailureCode.corrupt);
    }
    if (await stage.exists()) await stage.delete(recursive: true);
    await stage.create(recursive: true);
  }

  @override
  Future<bool> accepts(String bookId) async {
    await importer.library.checkAccess(bookId);
    final rows = await db.query(
      'SELECT d.kind FROM documents d JOIN imports i ON i.document_id=d.id WHERE d.book_id=?',
      [bookId],
    );
    return rows.firstOrNull?['kind'] == 'txt';
  }

  Future<void> _admit(String bookId, JobContext job) async {
    job.checkCancelled();
    if (_closed) throw const JobCancelled();
    await importer.library.checkAccess(bookId);
  }

  TxtIndex _from(String bookId, String id, Map<String, dynamic> m) => TxtIndex(
    id: id,
    title: (_pending[id]?.$3['title'] as String?) ?? '本地 TXT',
    protected: _pending[id]?.$3['rating'] == 'adult',
    bookId: bookId,
    encoding: m['encoding'] as String,
    rules: TxtRules.fromJson(Map<String, dynamic>.from(m['rules'] as Map)),
    blocks: m['blocks'] as int,
    units: m['units'] as int,
    chapterCount: (m['chapters'] as List).length,
    preview: [
      for (final (i, c) in (m['chapters'] as List).take(20).indexed)
        TxtChapter(i, c['title'] as String, c['first'] as int, c['end'] as int),
    ],
  );
  Future<TxtIndex> _load(String bookId, String id) async {
    final rows = await db.query(
      'SELECT t.*,b.title,b.rating FROM txt_indices t JOIN documents d ON d.id=t.document_id JOIN books b ON b.id=d.book_id WHERE t.document_id=?',
      [id],
    );
    if (rows.isEmpty) throw const AppFailure(FailureCode.missing);
    final row = rows.single;
    return TxtIndex(
      id: id,
      title: row['title']! as String,
      protected: row['rating'] == 'adult',
      bookId: bookId,
      encoding: row['encoding']! as String,
      rules: TxtRules.fromJson(
        jsonDecode(row['rules']! as String) as Map<String, dynamic>,
      ),
      blocks: row['block_count']! as int,
      units: row['utf16_length']! as int,
      chapterCount: row['chapter_count']! as int,
    );
  }

  @override
  Future<TxtIndex?> open(String bookId, JobContext job) async {
    await _admit(bookId, job);
    final ticket = importer.access.state.visibilityRevision;
    final rows = await db.query(
      'SELECT document_id FROM txt_active WHERE book_id=?',
      [bookId],
    );
    if (rows.isEmpty) return null;
    await importer.verify(bookId, job);
    final id = rows.single['document_id']! as String;
    final index = await _load(bookId, id);
    final expected = (await db.query(
      'SELECT index_digest FROM txt_indices WHERE document_id=?',
      [id],
    )).single['index_digest'];
    final file = File('$root/txt-indices/$id/blocks.bin');
    final valid = await Isolate.run(
      () async =>
          await FileSystemEntity.type(file.path, followLinks: false) ==
              FileSystemEntityType.file &&
          await file.length() == index.blocks * txtRecordBytes &&
          (await sha256.bind(file.openRead()).first).toString() == expected,
    );
    await _admit(bookId, job);
    if (!valid) throw const AppFailure(FailureCode.corrupt);
    if (ticket != importer.access.state.visibilityRevision) {
      throw const AppFailure(FailureCode.permissionDenied);
    }
    return index;
  }

  @override
  Future<TxtIndex> preview(String bookId, TxtRules rules, JobContext job) {
    if (_building != null || _pending.length >= 2) {
      return Future.error(const AppFailure(FailureCode.unexpected));
    }
    final result = _preview(bookId, rules, job);
    _building = result;
    return result.whenComplete(() => _building = null);
  }

  Future<TxtIndex> _preview(
    String bookId,
    TxtRules rules,
    JobContext original,
  ) async {
    TxtRules.fromJson(rules.toJson());
    final ticket = importer.access.state.visibilityRevision;
    final job = JobContext(
      id: original.id,
      isCurrent: () =>
          !original.isCancelled &&
          !_closed &&
          ticket == importer.access.state.visibilityRevision,
      report: original.report,
    );
    await _admit(bookId, job);
    final id = newLocalId(), path = '$root/txt-stage/$id';
    try {
      final index = await importer.withSnapshot(bookId, job, (
        file,
        source,
      ) async {
        if (source['kind'] != 'txt' || source['encoding'] == null) {
          throw const AppFailure(FailureCode.unsupported);
        }
        final parseJob = JobContext(
          id: job.id,
          isCurrent: () => !job.isCancelled,
          report: (p) =>
              job.report(source['mode'] == 'reference' ? .6 + p * .4 : p),
        );
        final manifest = await parseTxt(
          path: file.path,
          output: path,
          encoding: source['encoding']! as String,
          rules: rules,
          job: parseJob,
        );
        if (manifest['source_digest'] != source['digest']) {
          throw const ImportFailure(ImportIssue.changed);
        }
        _pending[id] = (bookId, manifest, source);
        return _from(bookId, id, manifest);
      });
      await _admit(bookId, job);
      return index;
    } catch (_) {
      await discard(id);
      if (await Directory(path).exists()) {
        await Directory(path).delete(recursive: true);
      }
      rethrow;
    }
  }

  @override
  Future<TxtIndex> apply(String candidateId, JobContext job) async {
    final pending = _pending[candidateId];
    if (pending == null) throw const AppFailure(FailureCode.missing);
    final (bookId, m, source) = pending;
    await _admit(bookId, job);
    final ticket = importer.access.state.visibilityRevision;
    final now = DateTime.now().millisecondsSinceEpoch;
    final stage = Directory('$root/txt-stage/$candidateId'),
        target = Directory('$root/txt-indices/$candidateId');
    if (await FileSystemEntity.type(target.parent.path, followLinks: false) ==
        FileSystemEntityType.link) {
      throw const AppFailure(FailureCode.corrupt);
    }
    await target.parent.create(recursive: true);
    await stage.rename(target.path);
    var committed = false;
    try {
      await _admit(bookId, job);
      if (ticket != importer.access.state.visibilityRevision) {
        throw const AppFailure(FailureCode.permissionDenied);
      }
      final chapters = m['chapters'] as List;
      await db.transaction([
        SqlCommand(
          'INSERT INTO documents(id,book_id,digest,kind,media_type,byte_length,parser_version,created_at) VALUES(?,?,?,?,?,?,?,?)',
          [
            candidateId,
            bookId,
            source['digest'],
            'txt',
            'text/plain',
            source['byte_length'],
            'txt-v1-$candidateId',
            now,
          ],
        ),
        SqlCommand('INSERT INTO txt_indices VALUES(?,?,?,?,?,?,?,?,?)', [
          candidateId,
          source['document_id'],
          m['encoding'],
          jsonEncode(m['rules']),
          m['blocks'],
          m['units'],
          chapters.length,
          m['index_digest'],
          m['text_digest'],
        ]),
        for (final (i, c) in chapters.indexed) ...[
          SqlCommand('INSERT INTO chapters VALUES(?,?,?,?,?)', [
            'c$i',
            candidateId,
            i,
            c['title'],
            'text.txt',
          ]),
          SqlCommand('INSERT INTO txt_chapter_ranges VALUES(?,?,?,?)', [
            candidateId,
            'c$i',
            c['first'],
            c['end'],
          ]),
        ],
        SqlCommand(
          'INSERT INTO txt_active VALUES(?,?) ON CONFLICT(book_id) DO UPDATE SET document_id=excluded.document_id',
          [bookId, candidateId],
        ),
      ]);
      committed = true;
      _pending.remove(candidateId);
      await importer.library.checkAccess(bookId);
      return await _load(bookId, candidateId);
    } finally {
      if (!committed) {
        if (await target.exists()) await target.rename(stage.path);
      }
    }
  }

  @override
  Future<void> discard(String candidateId) async {
    _pending.remove(candidateId);
    if (!RegExp(r'^[a-zA-Z0-9-]+$').hasMatch(candidateId)) return;
    final dir = Directory('$root/txt-stage/$candidateId');
    if (await dir.exists()) await dir.delete(recursive: true);
  }

  @override
  Future<List<TxtChapter>> chapters(
    TxtIndex index,
    int offset,
    JobContext job,
  ) async {
    final ticket = importer.access.state.visibilityRevision;
    await _admit(index.bookId, job);
    if (offset < 0) throw const FormatException('chapter_offset');
    final rows = await db.query(
      'SELECT c.ordinal,c.title,r.first_block,r.end_block FROM chapters c JOIN txt_chapter_ranges r ON r.document_id=c.document_id AND r.chapter_id=c.id JOIN documents d ON d.id=c.document_id WHERE c.document_id=? AND d.book_id=? ORDER BY c.ordinal LIMIT 100 OFFSET ?',
      [index.id, index.bookId, offset],
    );
    await _admit(index.bookId, job);
    if (ticket != importer.access.state.visibilityRevision) {
      throw const AppFailure(FailureCode.permissionDenied);
    }
    return [
      for (final r in rows)
        TxtChapter(
          r['ordinal']! as int,
          r['title']! as String,
          r['first_block']! as int,
          r['end_block']! as int,
        ),
    ];
  }

  @override
  Future<TxtPage> read(TxtIndex index, int firstBlock, JobContext job) async {
    final ticket = importer.access.state.visibilityRevision;
    await _admit(index.bookId, job);
    if (firstBlock < 0 || firstBlock >= index.blocks) {
      throw const FormatException('block_offset');
    }
    final owners = await db.query(
      'SELECT d.book_id FROM documents d JOIN txt_indices t ON t.document_id=d.id WHERE d.id=? AND d.book_id=?',
      [index.id, index.bookId],
    );
    if (owners.isEmpty) throw const AppFailure(FailureCode.missing);
    final chapterRows = await db.query(
      'SELECT c.ordinal,c.title,r.first_block,r.end_block FROM txt_chapter_ranges r JOIN chapters c ON c.document_id=r.document_id AND c.id=r.chapter_id WHERE r.document_id=? AND r.first_block<=? AND r.end_block>?',
      [index.id, firstBlock, firstBlock],
    );
    if (chapterRows.length != 1) throw const AppFailure(FailureCode.corrupt);
    final c = chapterRows.single,
        chapter = TxtChapter(
          c['ordinal']! as int,
          c['title']! as String,
          c['first_block']! as int,
          c['end_block']! as int,
        );
    final count = (chapter.end - firstBlock).clamp(0, 8);
    final file = await File('$root/txt-indices/${index.id}/blocks.bin').open();
    final blocks = <TxtBlock>[];
    try {
      await file.setPosition(firstBlock * txtRecordBytes);
      final records = await file.read(count * txtRecordBytes);
      if (records.length != count * txtRecordBytes) {
        throw const AppFailure(FailureCode.corrupt);
      }
      for (var i = 0; i < count; i++) {
        job.checkCancelled();
        final b = ByteData.sublistView(
          records,
          i * txtRecordBytes,
          (i + 1) * txtRecordBytes,
        );
        int field(int n) => b.getUint64(n * 8, Endian.little);
        final bytes = await importer.readRange(
          index.bookId,
          field(2),
          field(3),
          job,
        );
        final scalars = Newlines()
            .add(
              TxtDecoder(
                index.encoding,
                base: field(2),
                allowBom: field(2) == 0,
              ).add(bytes, last: true),
              last: true,
            )
            .toList();
        final text = String.fromCharCodes(scalars.map((s) => s.value));
        final hash = records.sublist(
          i * txtRecordBytes + 64,
          (i + 1) * txtRecordBytes,
        );
        if (text.length != field(1) ||
            sha256.convert(utf8.encode(text)).toString() !=
                Digest(hash).toString() ||
            field(7) != firstBlock + i) {
          throw const AppFailure(FailureCode.corrupt);
        }
        final offsets = <int>[scalars.first.start];
        for (final s in scalars) {
          if (s.value > 0xffff) offsets.add(-1);
          offsets.add(s.end);
        }
        blocks.add(
          TxtBlock(
            firstBlock + i,
            text,
            field(0),
            field(2),
            field(3),
            field(4),
            field(5) == 1,
            offsets,
          ),
        );
      }
    } finally {
      await file.close();
    }
    await _admit(index.bookId, job);
    if (ticket != importer.access.state.visibilityRevision) {
      throw const AppFailure(FailureCode.permissionDenied);
    }
    return TxtPage(index, chapter, blocks);
  }

  Future<void> dispose() async {
    _closed = true;
    try {
      await _building;
    } catch (_) {}
    for (final id in _pending.keys.toList()) {
      await discard(id);
    }
  }
}
