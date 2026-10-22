import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:platform_services/platform_services.dart';
import 'package:reader_storage/reader_storage.dart';

import '../../application/access.dart';
import '../../domain/access.dart';
import '../../domain/importing.dart';
import '../../domain/jobs.dart';
import '../storage/local_library.dart';
import 'epub_inspector.dart';
import 'text_inspector.dart';

final class LocalImporter implements DocumentImporter {
  LocalImporter(this.library, this.access, this.files, this.root, this.text);
  static const maxBytes = 64 * 1024 * 1024;
  final LocalLibrary library;
  final AccessController access;
  final DocumentAccess files;
  final String root;
  final TextInspector text;
  final _inspectionSeq = <String, int>{};
  final _staged = <String, (File, ImportPreview)>{};
  Future<void> initialize() async {
    final stage = Directory(p.join(root, 'import-stage'));
    if (await FileSystemEntity.type(stage.path, followLinks: false) ==
        FileSystemEntityType.link) {
      throw const ImportFailure(ImportIssue.disk);
    }
    // The database's single-writer lease was acquired before composition.
    if (await stage.exists()) await stage.delete(recursive: true);
    await stage.create(recursive: true);
  }

  Future<(File, String, int)> _copy(FileGrant grant, JobContext job) async {
    final target = File(p.join(root, 'import-stage', newLocalId()));
    RandomAccessFile? writer;
    try {
      writer = await target.open(mode: FileMode.writeOnly);
      var size = 0;
      final hash = await sha256
          .bind(
            files.readDocument(grant).asyncMap((chunk) async {
              job.checkCancelled();
              size += chunk.length;
              if (size > maxBytes) {
                throw const ImportFailure(ImportIssue.tooLarge);
              }
              await writer!.writeFrom(chunk);
              job.report(size / maxBytes * .6);
              return chunk;
            }),
          )
          .first;
      job.checkCancelled();
      if (size == 0) throw const ImportFailure(ImportIssue.corrupt);
      await writer.flush();
      await writer.close();
      writer = null;
      return (target, hash.toString(), size);
    } catch (_) {
      await writer?.close();
      if (await target.exists()) await target.delete();
      rethrow;
    }
  }

  @override
  Future<ImportPreview> prepare(FileGrant grant, JobContext job) async {
    final extension = p.extension(grant.displayName).toLowerCase();
    if (!['.txt', '.epub'].contains(extension)) {
      throw const ImportFailure(ImportIssue.unsupported);
    }
    File? staged;
    try {
      final (file, digest, size) = await _copy(grant, job);
      staged = file;
      final id = newLocalId(), kind = extension.substring(1);
      final preview = ImportPreview(
        id: id,
        grant: grant,
        kind: kind,
        bytes: size,
        title: p
            .basenameWithoutExtension(grant.displayName)
            .runes
            .take(200)
            .map(String.fromCharCode)
            .join(),
        digest: digest,
      );
      _staged[id] = (file, preview);
      return await inspect(id, TextEncoding.auto, job);
    } on ImportFailure {
      if (staged != null) {
        _staged.removeWhere((_, v) => v.$1.path == staged!.path);
        if (await staged.exists()) await staged.delete();
      }
      rethrow;
    } on JobCancelled {
      if (staged != null) {
        _staged.removeWhere((_, v) => v.$1.path == staged!.path);
        if (await staged.exists()) await staged.delete();
      }
      rethrow;
    } catch (_) {
      if (staged != null) {
        _staged.removeWhere((_, v) => v.$1.path == staged!.path);
        if (await staged.exists()) await staged.delete();
      }
      throw const ImportFailure(ImportIssue.disk);
    }
  }

  @override
  Future<ImportPreview> inspect(
    String id,
    TextEncoding encoding,
    JobContext job,
  ) async {
    final entry = _staged[id];
    if (entry == null) throw const ImportFailure(ImportIssue.missing);
    final (file, original) = entry;
    job.checkCancelled();
    final request = (_inspectionSeq[id] ?? 0) + 1;
    _inspectionSeq[id] = request;
    var title = original.title, excerpt = '';
    TextEncoding? resolved;
    ImportIssue? issue;
    if (original.kind == 'epub') {
      title = await Isolate.run(() => EpubInspector.inspect(file.path));
      if (title.isEmpty) title = original.title;
    } else {
      try {
        final info = await text.inspect(file.path, encoding);
        resolved = info.$1;
        excerpt = info.$2;
      } on ImportFailure catch (e) {
        if (e.issue != ImportIssue.encoding) rethrow;
        issue = e.issue;
      }
    }
    job.checkCancelled();
    if (!_staged.containsKey(id) || _inspectionSeq[id] != request) {
      throw const JobCancelled();
    }
    final updated = ImportPreview(
      id: id,
      grant: original.grant,
      kind: original.kind,
      bytes: original.bytes,
      title: title,
      digest: original.digest,
      encoding: resolved,
      excerpt: excerpt,
      issue: issue,
    );
    _staged[id] = (file, updated);
    return updated;
  }

  void _admitRating(RatingLevel rating) {
    if (rating != RatingLevel.general && rating != RatingLevel.restricted) {
      throw const ImportFailure(ImportIssue.classification);
    }
    if (rating == RatingLevel.restricted && !access.state.adultVisible) {
      throw const ImportFailure(ImportIssue.permission);
    }
  }

  Future<void> _commitTail = Future.value();
  @override
  Future<ImportReceipt> commit(
    String id, {
    required ImportMode mode,
    required RatingLevel rating,
    required JobContext job,
  }) {
    final operation = _commitTail.then(
      (_) => _commitNow(id, mode: mode, rating: rating, job: job),
    );
    _commitTail = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return operation;
  }

  Future<void> dispose() async {
    await _commitTail;
    for (final id in _staged.keys.toList()) {
      await discard(id);
    }
  }

  Future<ImportReceipt> _commitNow(
    String id, {
    required ImportMode mode,
    required RatingLevel rating,
    required JobContext job,
  }) async {
    _admitRating(rating);
    job.checkCancelled();
    final ticket = access.state.visibilityRevision;
    final entry = _staged[id];
    if (entry == null) throw const ImportFailure(ImportIssue.missing);
    final (file, preview) = entry;
    if (preview.issue != null) throw ImportFailure(preview.issue!);
    var retained = false;
    try {
      final existing = await library.database.query(
        'SELECT book_id FROM documents WHERE digest=? AND kind=? LIMIT 1',
        [preview.digest, preview.kind],
      );
      job.checkCancelled();
      _admitRating(rating);
      if (existing.isNotEmpty) {
        final bookId = existing.single['book_id']! as String;
        await library.checkAccess(bookId);
        var repaired = false;
        final rows = await library.database.query(
          'SELECT mode FROM imports i JOIN documents d ON d.id=i.document_id WHERE d.book_id=?',
          [bookId],
        );
        if (mode == ImportMode.managed &&
            rows.firstOrNull?['mode'] == 'managed') {
          final target = File(p.join(root, 'objects', preview.digest));
          if (await FileSystemEntity.type(
                    target.parent.path,
                    followLinks: false,
                  ) ==
                  FileSystemEntityType.link ||
              await FileSystemEntity.type(target.path, followLinks: false) ==
                  FileSystemEntityType.link) {
            throw const ImportFailure(ImportIssue.disk);
          }
          if (!await target.exists() ||
              (await sha256.bind(target.openRead()).first).toString() !=
                  preview.digest) {
            job.checkCancelled();
            await library.checkAccess(bookId);
            await target.parent.create(recursive: true);
            await file.rename(target.path);
            repaired = true;
          }
        }
        await discard(id);
        return ImportReceipt(
          existing.single['book_id']! as String,
          duplicate: true,
          repaired: repaired,
        );
      }
      if (mode == ImportMode.reference) {
        await files.retainGrant(preview.grant);
        retained = true;
      }
      final book = newLocalId(),
          revision = 'sha256:${preview.digest}:import-v1';
      final now = DateTime.now().millisecondsSinceEpoch;
      final target = File(p.join(root, 'objects', preview.digest));
      var created = false;
      if (mode == ImportMode.managed) {
        if (await FileSystemEntity.type(
              target.parent.path,
              followLinks: false,
            ) ==
            FileSystemEntityType.link) {
          throw const ImportFailure(ImportIssue.disk);
        }
        await target.parent.create(recursive: true);
        if (await FileSystemEntity.type(target.path, followLinks: false) ==
            FileSystemEntityType.link) {
          throw const ImportFailure(ImportIssue.disk);
        }
        if (await target.exists()) {
          if ((await sha256.bind(target.openRead()).first).toString() !=
              preview.digest) {
            throw const ImportFailure(ImportIssue.corrupt);
          }
        } else {
          await file.rename(target.path);
          created = true;
        }
      }
      try {
        job.checkCancelled();
        _admitRating(rating);
        if (rating == RatingLevel.restricted &&
            ticket != access.state.visibilityRevision) {
          throw const ImportFailure(ImportIssue.permission);
        }
        await library.database.transaction([
          SqlCommand(
            'INSERT INTO books(id,title,language,rating,rating_evidence,created_at,updated_at) VALUES(?,?,?,?,?,?,?)',
            [
              book,
              preview.title,
              'zh',
              rating == RatingLevel.general ? 'general' : 'adult',
              'user-local-import-v1',
              now,
              now,
            ],
          ),
          SqlCommand(
            'INSERT INTO content_policy(book_id,raw_rating,level,minimum_age,evidence,policy_version,source_access) VALUES(?,?,?,?,?,?,?)',
            [
              book,
              '用户在本机选择',
              rating.name,
              rating == RatingLevel.restricted ? 18 : null,
              'user-local-import-v1',
              'local-v1',
              'notRequired',
            ],
          ),
          SqlCommand(
            'INSERT INTO documents(id,book_id,digest,kind,media_type,byte_length,parser_version,created_at) VALUES(?,?,?,?,?,?,?,?)',
            [
              revision,
              book,
              preview.digest,
              preview.kind,
              preview.kind == 'txt' ? 'text/plain' : 'application/epub+zip',
              preview.bytes,
              'import-v1',
              now,
            ],
          ),
          SqlCommand(
            'INSERT INTO imports(document_id,mode,grant_id,encoding,status) VALUES(?,?,?,?,?)',
            [
              revision,
              mode.name,
              mode == ImportMode.reference ? preview.grant.id : null,
              preview.encoding?.name,
              'awaiting_parser',
            ],
          ),
          SqlCommand(
            'INSERT INTO resources(document_id,href,digest,media_type,byte_length,cache_permission) VALUES(?,?,?,?,?,?)',
            [
              revision,
              'original.${preview.kind}',
              preview.digest,
              preview.kind == 'txt' ? 'text/plain' : 'application/epub+zip',
              preview.bytes,
              'unknown',
            ],
          ),
          if (rating == RatingLevel.restricted) ...[
            const SqlCommand(
              "INSERT OR IGNORE INTO collections(id,label,kind) VALUES('adult-default','成人收藏','adult')",
            ),
            SqlCommand(
              "INSERT INTO collection_books VALUES('adult-default',?)",
              [book],
            ),
          ],
        ]);
      } catch (_) {
        if (created && await target.exists()) await target.delete();
        rethrow;
      }
      retained = false; // The committed record now owns the persisted bookmark.
      try {
        await discard(id);
      } catch (_) {
        /* Startup clears leftover staging. */
      }
      return ImportReceipt(book, duplicate: false);
    } on ImportFailure {
      rethrow;
    } on JobCancelled {
      rethrow;
    } catch (_) {
      throw const ImportFailure(ImportIssue.disk);
    } finally {
      if (retained) await files.forgetGrant(preview.grant);
    }
  }

  @override
  Future<void> discard(String id) async {
    _inspectionSeq.remove(id);
    final entry = _staged.remove(id);
    if (entry == null) return;
    if (await entry.$1.exists()) await entry.$1.delete();
  }

  Future<Map<String, Object?>> _record(String bookId) async {
    await library.checkAccess(bookId);
    final rows = await library.database.query(
      'SELECT i.*,d.digest,d.kind,d.byte_length,b.title,b.rating FROM imports i JOIN documents d ON d.id=i.document_id JOIN books b ON b.id=d.book_id WHERE d.book_id=?',
      [bookId],
    );
    if (rows.isEmpty) throw const ImportFailure(ImportIssue.unsupported);
    return rows.single;
  }

  Future<Map<String, Object?>> sourceRecord(String bookId) => _record(bookId);

  Future<T> withSnapshot<T>(
    String bookId,
    JobContext job,
    Future<T> Function(File, Map<String, Object?>) action,
  ) async {
    final ticket = access.state.visibilityRevision;
    final row = await _record(bookId);
    job.checkCancelled();
    if (row['mode'] == 'managed') {
      final file = File(p.join(root, 'objects', row['digest']! as String));
      if (await FileSystemEntity.type(file.path, followLinks: false) !=
          FileSystemEntityType.file) {
        throw const ImportFailure(ImportIssue.missing);
      }
      final result = await action(file, row);
      job.checkCancelled();
      await library.checkAccess(bookId);
      if (ticket != access.state.visibilityRevision) {
        throw const ImportFailure(ImportIssue.permission);
      }
      return result;
    }
    final grant = await files.restoreGrant(row['grant_id']! as String);
    if (grant is! PlatformSuccess<FileGrant>) {
      throw const ImportFailure(ImportIssue.permission);
    }
    File? snapshot;
    try {
      final (file, digest, _) = await _copy(grant.value, job);
      snapshot = file;
      if (digest != row['digest']) {
        throw const ImportFailure(ImportIssue.changed);
      }
      final result = await action(file, row);
      job.checkCancelled();
      await library.checkAccess(bookId);
      if (ticket != access.state.visibilityRevision) {
        throw const ImportFailure(ImportIssue.permission);
      }
      return result;
    } finally {
      if (snapshot != null && await snapshot.exists()) await snapshot.delete();
      await files.releaseGrant(grant.value);
    }
  }

  Future<List<int>> readRange(
    String bookId,
    int start,
    int end,
    JobContext job,
  ) async {
    final ticket = access.state.visibilityRevision;
    final row = await _record(bookId);
    if (start < 0 ||
        end <= start ||
        end > (row['byte_length']! as int) ||
        end - start > 128 * 1024) {
      throw const ImportFailure(ImportIssue.corrupt);
    }
    final bytes = <int>[];
    if (row['mode'] == 'managed') {
      final file = File(p.join(root, 'objects', row['digest']! as String));
      if (await FileSystemEntity.type(file.path, followLinks: false) !=
          FileSystemEntityType.file) {
        throw const ImportFailure(ImportIssue.missing);
      }
      await for (final chunk in file.openRead(start, end)) {
        job.checkCancelled();
        bytes.addAll(chunk);
      }
    } else {
      final grant = await files.restoreGrant(row['grant_id']! as String);
      if (grant is! PlatformSuccess<FileGrant>) {
        throw const ImportFailure(ImportIssue.permission);
      }
      try {
        await for (final chunk in files.readDocumentRange(
          grant.value,
          start,
          end,
        )) {
          job.checkCancelled();
          bytes.addAll(chunk);
          if (bytes.length > end - start) {
            throw const ImportFailure(ImportIssue.corrupt);
          }
        }
      } finally {
        await files.releaseGrant(grant.value);
      }
    }
    job.checkCancelled();
    await library.checkAccess(bookId);
    if (bytes.length != end - start ||
        ticket != access.state.visibilityRevision) {
      throw const ImportFailure(ImportIssue.changed);
    }
    return bytes;
  }

  @override
  Future<ImportedFileStatus> information(String bookId) async {
    final row = await _record(bookId);
    return ImportedFileStatus(
      row['mode'] == 'managed' ? ImportMode.managed : ImportMode.reference,
      row['byte_length']! as int,
      row['encoding'] as String?,
    );
  }

  @override
  Future<ImportedFileStatus> verify(String bookId, JobContext job) async {
    final row = await _record(bookId);
    job.checkCancelled();
    final digest = row['digest']! as String;
    if (row['mode'] == 'managed') {
      final file = File(p.join(root, 'objects', digest));
      if (await FileSystemEntity.type(file.path, followLinks: false) !=
          FileSystemEntityType.file) {
        throw const ImportFailure(ImportIssue.missing);
      }
      if ((await sha256.bind(file.openRead()).first).toString() != digest) {
        throw const ImportFailure(ImportIssue.changed);
      }
    } else {
      final result = await files.restoreGrant(row['grant_id']! as String);
      if (result is! PlatformSuccess<FileGrant>) {
        throw const ImportFailure(ImportIssue.permission);
      }
      try {
        final (copy, hash, _) = await _copy(result.value, job);
        await copy.delete();
        if (hash != digest) throw const ImportFailure(ImportIssue.changed);
      } finally {
        await files.releaseGrant(result.value);
      }
    }
    job.checkCancelled();
    await library.checkAccess(bookId);
    return ImportedFileStatus(
      row['mode'] == 'managed' ? ImportMode.managed : ImportMode.reference,
      row['byte_length']! as int,
      row['encoding'] as String?,
    );
  }

  @override
  Future<void> relink(String bookId, FileGrant grant, JobContext job) async {
    final row = await _record(bookId);
    if (row['mode'] != 'reference') {
      throw const ImportFailure(ImportIssue.unsupported);
    }
    final (file, hash, _) = await _copy(grant, job);
    await file.delete();
    if (hash != row['digest']) throw const ImportFailure(ImportIssue.changed);
    var retained = false;
    try {
      await files.retainGrant(grant);
      retained = true;
      job.checkCancelled();
      await library.checkAccess(bookId);
      await library.database.transaction([
        SqlCommand(
          'UPDATE imports SET grant_id=? WHERE document_id=? AND grant_id=?',
          [grant.id, row['document_id'], row['grant_id']],
          1,
        ),
      ]);
      retained = false;
      if (grant.id != row['grant_id']) {
        try {
          await files.forgetGrant(
            FileGrant(id: row['grant_id']! as String, displayName: ''),
          );
        } catch (_) {
          // The committed new grant remains valid if old-grant cleanup fails.
        }
      }
    } finally {
      if (retained) await files.forgetGrant(grant);
    }
  }
}
