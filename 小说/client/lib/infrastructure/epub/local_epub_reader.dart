import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:reader_storage/reader_storage.dart';

import '../../domain/epub.dart';
import '../../domain/importing.dart';
import '../../domain/jobs.dart';
import '../importing/local_importer.dart';
import 'loader.dart';

final class _Session {
  _Session(this.value, this.manifest, this.visibility);
  final EpubSession value;
  final Map<String, dynamic> manifest;
  final int visibility;
}

final class LocalEpubReader implements EpubDocumentReader {
  LocalEpubReader(this.importer) {
    _unregister = importer.access.registerProtectedStop(() {
      for (final id in _sessions.keys.toList()) {
        unawaited(close(id));
      }
    });
  }
  final LocalImporter importer;
  final _sessions = <String, _Session>{};
  late final void Function() _unregister;
  Future<EpubSession>? _opening;
  bool _closed = false;
  String get _root => '${importer.root}/epub-sessions';
  Future<void> initialize() async {
    final root = Directory(_root);
    if (await FileSystemEntity.type(root.path, followLinks: false) ==
        FileSystemEntityType.link) {
      throw const EpubFailure(EpubIssue.corrupt);
    }
    if (await root.exists()) await root.delete(recursive: true);
    await root.create(recursive: true);
  }

  @override
  Future<bool> accepts(String bookId) async {
    await importer.library.checkAccess(bookId);
    final rows = await importer.library.database.query(
      'SELECT d.kind FROM documents d JOIN imports i ON i.document_id=d.id WHERE d.book_id=?',
      [bookId],
    );
    return rows.firstOrNull?['kind'] == 'epub';
  }

  Future<void> _admit(String bookId, JobContext job) async {
    job.checkCancelled();
    if (_closed) throw const EpubFailure(EpubIssue.expired);
    await importer.library.checkAccess(bookId);
  }

  Future<_Session> _active(EpubSession session, JobContext job) async {
    await _admit(session.bookId, job);
    final active = _sessions[session.id];
    if (active == null ||
        !identical(active.value, session) ||
        active.visibility != importer.access.state.visibilityRevision) {
      throw const EpubFailure(EpubIssue.expired);
    }
    return active;
  }

  @override
  Future<EpubSession> open(String bookId, JobContext job) {
    if (_opening != null || _sessions.length >= 2) {
      return Future.error(const EpubFailure(EpubIssue.limit));
    }
    final next = _open(bookId, job);
    _opening = next;
    return next.whenComplete(() => _opening = null);
  }

  Future<EpubSession> _open(String bookId, JobContext original) async {
    final visibility = importer.access.state.visibilityRevision;
    final job = JobContext(
      id: original.id,
      isCurrent: () =>
          !_closed &&
          !original.isCancelled &&
          visibility == importer.access.state.visibilityRevision,
      report: original.report,
    );
    await _admit(bookId, job);
    final id = 's${newLocalId().replaceAll('-', '')}',
        dir = Directory('$_root/$id');
    try {
      final result = await importer.withSnapshot(bookId, job, (
        file,
        source,
      ) async {
        if (source['kind'] != 'epub') {
          throw const EpubFailure(EpubIssue.unsupported);
        }
        final manifest = await loadEpub(
          file.path,
          dir.path,
          id,
          JobContext(
            id: job.id,
            isCurrent: () => !job.isCancelled,
            report: (p) =>
                job.report(source['mode'] == 'reference' ? .6 + p * .4 : p),
          ),
        );
        if (manifest['source_digest'] != source['digest']) {
          throw const ImportFailure(ImportIssue.changed);
        }
        await _admit(bookId, job);
        final rows = await importer.library.database.query(
          'SELECT id FROM documents WHERE book_id=? AND digest=? AND kind=? AND parser_version=?',
          [bookId, source['digest'], 'epub', epubParser],
        );
        final revision = rows.firstOrNull?['id'] as String? ?? newLocalId();
        final spines = <EpubSpine>[
          for (final s in manifest['spine'] as List)
            EpubSpine(
              s['ordinal'] as int,
              s['href'] as String,
              s['resource'] as String,
              s['title'] as String,
              List<String>.from(s['images'] as List),
            ),
        ];
        if (rows.isEmpty) {
          await importer.library.database.transaction([
            SqlCommand(
              'INSERT INTO documents(id,book_id,digest,kind,media_type,byte_length,parser_version,created_at) VALUES(?,?,?,?,?,?,?,?)',
              [
                revision,
                bookId,
                source['digest'],
                'epub',
                'application/epub+zip',
                source['byte_length'],
                epubParser,
                DateTime.now().millisecondsSinceEpoch,
              ],
            ),
            for (final s in spines)
              SqlCommand('INSERT INTO chapters VALUES(?,?,?,?,?)', [
                s.id,
                revision,
                s.ordinal,
                s.title,
                s.href,
              ]),
          ]);
        }
        return _Session(
          EpubSession(
            id: id,
            revision: revision,
            bookId: bookId,
            title: source['title']! as String,
            protected: source['rating'] == 'adult',
            spine: List.unmodifiable(spines),
            toc: List.unmodifiable([
              for (final t in manifest['toc'] as List)
                EpubToc(
                  t['title'] as String,
                  t['spine'] as int,
                  t['fragment'] as String,
                  t['depth'] as int,
                ),
            ]),
            warnings: List<String>.unmodifiable(manifest['warnings'] as List),
          ),
          manifest,
          visibility,
        );
      });
      await _admit(bookId, job);
      _sessions[id] = result;
      return result.value;
    } catch (_) {
      if (await dir.exists()) await dir.delete(recursive: true);
      rethrow;
    }
  }

  Future<Uint8List> _bytes(String id, String name, Map meta, int limit) async {
    final file = File('$_root/$id/$name');
    if (await FileSystemEntity.type(file.path, followLinks: false) !=
            FileSystemEntityType.file ||
        meta['bytes'] is! int ||
        (meta['bytes'] as int) > limit ||
        await file.length() != meta['bytes']) {
      throw const EpubFailure(EpubIssue.corrupt);
    }
    final bytes = await file.readAsBytes();
    if (sha256.convert(bytes).toString() != meta['sha256']) {
      throw const EpubFailure(EpubIssue.corrupt);
    }
    return bytes;
  }

  @override
  Future<EpubChapter> chapter(
    EpubSession session,
    int ordinal,
    JobContext job,
  ) async {
    final active = await _active(session, job);
    if (ordinal < 0 || ordinal >= session.spine.length) {
      throw const EpubFailure(EpubIssue.missingResource);
    }
    final name = 'c$ordinal';
    final bytes = await _bytes(
      session.id,
      '$name.json',
      (active.manifest['chapters'] as Map)[name] as Map,
      16 * 1024 * 1024,
    );
    final value = jsonDecode(utf8.decode(bytes)) as Map;
    await _active(session, job);
    return EpubChapter(
      session,
      session.spine[ordinal],
      Map<String, String>.unmodifiable(value['blocks'] as Map),
      Map<String, String>.unmodifiable(value['fragments'] as Map),
    );
  }

  @override
  Future<EpubResource> resource(
    EpubSession session,
    String id,
    JobContext job,
  ) async {
    final active = await _active(session, job);
    if (!RegExp(r'^r[0-9]{1,4}$').hasMatch(id)) {
      throw const EpubFailure(EpubIssue.missingResource);
    }
    final meta = (active.manifest['resources'] as Map)[id];
    if (meta is! Map) throw const EpubFailure(EpubIssue.missingResource);
    final bytes = await _bytes(session.id, id, meta, 16 * 1024 * 1024);
    await _active(session, job);
    return EpubResource(meta['mime'] as String, bytes);
  }

  @override
  Future<void> close(String sessionId) async {
    final session = _sessions.remove(sessionId);
    if (session == null) return;
    final dir = Directory('$_root/$sessionId');
    if (await dir.exists()) await dir.delete(recursive: true);
  }

  Future<void> dispose() async {
    _closed = true;
    _unregister();
    try {
      await _opening;
    } catch (_) {}
    for (final id in _sessions.keys.toList()) {
      await close(id);
    }
  }
}
