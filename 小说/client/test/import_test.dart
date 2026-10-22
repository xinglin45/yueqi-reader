import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/app/dependencies.dart';
import 'package:novel_app/domain/access.dart';
import 'package:novel_app/domain/importing.dart';
import 'package:novel_app/domain/jobs.dart';
import 'package:novel_app/domain/library.dart';
import 'package:novel_app/infrastructure/importing/local_importer.dart';
import 'package:novel_app/infrastructure/importing/epub_inspector.dart';
import 'package:novel_app/infrastructure/storage/local_library.dart';
import 'package:platform_services/platform_services.dart';
import 'package:reader_storage/reader_storage.dart';

import 'access_test.dart' show Locations;

class ImportFiles implements DocumentAccess {
  final paths = <String, String>{};
  final retained = <String>{};
  final incoming = StreamController<List<FileGrant>>.broadcast();
  List<FileGrant> selected = [];
  int reads = 0, closed = 0;
  bool failRead = false;
  Future<void> Function()? afterChunk;
  FileGrant add(String name, String path) {
    final id = 'file-${paths.length}';
    paths[id] = path;
    return FileGrant(id: id, displayName: name);
  }

  @override
  Future<PlatformResult<List<FileGrant>>> chooseDocuments() async =>
      PlatformSuccess(selected);
  @override
  Future<PlatformResult<FileGrant?>> chooseDocument() async =>
      PlatformSuccess(selected.firstOrNull);
  @override
  Stream<List<FileGrant>> get incomingDocuments => incoming.stream;
  @override
  Future<PlatformResult<FileGrant>> restoreGrant(String id) async =>
      retained.contains(id) && File(paths[id] ?? 'missing').existsSync()
      ? PlatformSuccess(FileGrant(id: id, displayName: 'restored.txt'))
      : const PlatformUnavailable(PlatformFailure.permissionDenied);
  @override
  Stream<List<int>> readDocument(FileGrant grant) async* {
    reads++;
    try {
      await for (final chunk in File(paths[grant.id]!).openRead()) {
        if (failRead) throw const ImportFailure(ImportIssue.disk);
        yield chunk;
        await afterChunk?.call();
      }
    } finally {
      closed++;
    }
  }

  @override
  Stream<List<int>> readDocumentRange(FileGrant grant, int start, int end) =>
      File(paths[grant.id]!).openRead(start, end);
  @override
  Future<void> retainGrant(FileGrant grant) async {
    retained.add(grant.id);
  }

  @override
  Future<void> releaseGrant(FileGrant grant) async {}
  @override
  Future<void> forgetGrant(FileGrant grant) async {
    retained.remove(grant.id);
  }
}

JobContext job([bool Function()? current]) =>
    JobContext(id: 1, isCurrent: current ?? () => true, report: (_) {});
final fixtures = Directory('../../fixtures/novel/mac04');
void main() {
  late Directory dir;
  late ImportFiles files;
  AppDependencies? deps;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('mac04-');
    files = ImportFiles();
    deps = await AppDependencies.open(Locations(dir.path), documents: files);
  });
  tearDown(() async {
    await deps?.close?.call();
    await files.incoming.close();
    await dir.delete(recursive: true);
  });
  Future<FileGrant> sample(String name, {String? display}) async =>
      files.add(display ?? name, '${fixtures.path}/$name');
  test('managed copy is byte-exact, same digest skips, same display name with other bytes remains independent', () async {
    final importer = deps!.importer!;
    final one = await importer.prepare(
      await sample('简体-utf8.txt', display: '同名.txt'),
      job(),
    );
    expect(one.excerpt, contains('📖'));
    expect(one.encoding, TextEncoding.utf8);
    final result = await importer.commit(
      one.id,
      mode: ImportMode.managed,
      rating: RatingLevel.general,
      job: job(),
    );
    final row = await (deps!.library as LocalLibrary).database.query(
      'SELECT * FROM imports',
    );
    expect(row.single['mode'], 'managed');
    expect(row.single['grant_id'], null);
    final copy = File('${dir.path}/support/novel/objects/${one.digest}');
    expect(
      await copy.readAsBytes(),
      await File(files.paths[one.grant.id]!).readAsBytes(),
    );
    await deps!.access!.acknowledge();
    final duplicate = await importer.prepare(
      await sample('简体-utf8.txt', display: '重命名.txt'),
      job(),
    );
    final skipped = await importer.commit(
      duplicate.id,
      mode: ImportMode.managed,
      rating: RatingLevel.restricted,
      job: job(),
    );
    expect(skipped.duplicate, true);
    expect(skipped.bookId, result.bookId);
    final other = await importer.prepare(
      await sample('同名B.txt', display: '同名.txt'),
      job(),
    );
    await importer.commit(
      other.id,
      mode: ImportMode.managed,
      rating: RatingLevel.general,
      job: job(),
    );
    expect((await deps!.library.load(job())).value, hasLength(2));
    expect(
      (await deps!.library.load(job())).value
          .every((b) => !b.demo && !b.previewAvailable),
      true,
    );
    expect(
      await Directory('${dir.path}/support/novel/import-stage').list().toList(),
      isEmpty,
    );
    expect(files.reads, files.closed);
  });
  test(
    'concurrent identical commits serialize into one intact object and book',
    () async {
      final importer = deps!.importer!;
      final previews = await Future.wait([
        importer.prepare(await sample('同名A.txt'), job()),
        importer.prepare(await sample('同名A.txt'), job()),
      ]);
      final receipts = await Future.wait(
        previews.map(
          (preview) => importer.commit(
            preview.id,
            mode: ImportMode.managed,
            rating: RatingLevel.general,
            job: job(),
          ),
        ),
      );
      expect(receipts.map((r) => r.bookId).toSet(), hasLength(1));
      expect(receipts.where((r) => r.duplicate), hasLength(1));
      await importer.verify(receipts.first.bookId, job());
      expect((await deps!.library.load(job())).value, hasLength(1));
      expect(
        await Directory('${dir.path}/support/novel/objects').list().toList(),
        hasLength(1),
      );
    },
  );
  test('reimport repairs missing or corrupt managed bytes while preserving book metadata', () async {
    final importer = deps!.importer!;
    final preview = await importer.prepare(await sample('同名A.txt'), job());
    final receipt = await importer.commit(
      preview.id,
      mode: ImportMode.managed,
      rating: RatingLevel.general,
      job: job(),
    );
    final db = (deps!.library as LocalLibrary).database;
    await db.transaction([
      SqlCommand('UPDATE books SET title=? WHERE id=?', [
        '保留自定标题',
        receipt.bookId,
      ]),
    ]);
    final object = File('${dir.path}/support/novel/objects/${preview.digest}');
    for (final missing in [true, false]) {
      if (missing) {
        await object.delete();
      } else {
        await object.writeAsString('损坏副本');
      }
      await expectLater(
        importer.verify(receipt.bookId, job()),
        throwsA(isA<ImportFailure>()),
      );
      final retry = await importer.prepare(await sample('同名A.txt'), job());
      final repaired = await importer.commit(
        retry.id,
        mode: ImportMode.managed,
        rating: RatingLevel.general,
        job: job(),
      );
      expect(repaired.bookId, receipt.bookId);
      expect(repaired.duplicate && repaired.repaired, true);
      await importer.verify(receipt.bookId, job());
      expect(
        (await db.query('SELECT title,rating FROM books WHERE id=?', [
          receipt.bookId,
        ])).single,
        {'title': '保留自定标题', 'rating': 'general'},
      );
    }
    expect(
      await object.readAsBytes(),
      await File(files.paths[preview.grant.id]!).readAsBytes(),
    );
  });
  test('UTF-8 BOM and UTF-16 strict decoding, wrong bytes require explicit retry, never replacement characters', () async {
    final importer = deps!.importer!;
    for (final name in ['BOM-utf8.txt', 'UTF16LE.txt']) {
      final preview = await importer.prepare(await sample(name), job());
      expect(preview.excerpt, contains('📖'));
      expect(preview.excerpt.startsWith('\ufeff'), false);
      await importer.discard(preview.id);
    }
    final be = await importer.prepare(await sample('UTF16BE.txt'), job());
    expect(be.issue, ImportIssue.encoding);
    final decoded = await importer.inspect(be.id, TextEncoding.utf16be, job());
    expect(decoded.excerpt, contains('這是自產'));
    await importer.discard(be.id);
    final bad = await importer.prepare(await sample('错误编码.txt'), job());
    expect(bad.issue, ImportIssue.encoding);
    await expectLater(
      importer.commit(
        bad.id,
        mode: ImportMode.managed,
        rating: RatingLevel.general,
        job: job(),
      ),
      throwsA(isA<ImportFailure>()),
    );
    await importer.discard(bad.id);
    expect((await deps!.library.load(job())).value, isEmpty);
  });
  test('unknown and adult gates are checked before committing; imported adult files remain separate with discovery OFF', () async {
    final importer = deps!.importer!;
    final preview = await importer.prepare(await sample('同名A.txt'), job());
    await expectLater(
      importer.commit(
        preview.id,
        mode: ImportMode.managed,
        rating: RatingLevel.unknown,
        job: job(),
      ),
      throwsA(isA<ImportFailure>()),
    );
    await expectLater(
      importer.commit(
        preview.id,
        mode: ImportMode.managed,
        rating: RatingLevel.restricted,
        job: job(),
      ),
      throwsA(isA<ImportFailure>()),
    );
    await deps!.access!.acknowledge();
    final receipt = await importer.commit(
      preview.id,
      mode: ImportMode.managed,
      rating: RatingLevel.restricted,
      job: job(),
    );
    expect((await deps!.library.load(job())).value, isEmpty);
    expect(
      (await (deps!.library as AdultLibrary).loadAdult(job())).value.single.id,
      receipt.bookId,
    );
    await deps!.access!.lock();
    await expectLater(
      importer.verify(receipt.bookId, job()),
      throwsA(isA<AppFailure>()),
    );
  });
  test('reference survives library reopen using device grant, missing/expired and changed contents require explicit relink', () async {
    final external = File('${dir.path}/external.txt');
    await external.writeAsString('自产引用样本。');
    final grant = files.add('引用.txt', external.path);
    final preview = await deps!.importer!.prepare(grant, job());
    final result = await deps!.importer!.commit(
      preview.id,
      mode: ImportMode.reference,
      rating: RatingLevel.general,
      job: job(),
    );
    expect(
      await File('${dir.path}/support/novel/objects/${preview.digest}')
          .exists(),
      false,
    );
    await deps!.close!();
    deps = await AppDependencies.open(Locations(dir.path), documents: files);
    expect(
      (await deps!.importer!.verify(result.bookId, job())).mode,
      ImportMode.reference,
    );
    final moved = await external.rename('${dir.path}/moved.txt');
    await expectLater(
      deps!.importer!.verify(result.bookId, job()),
      throwsA(isA<ImportFailure>()),
    );
    final newGrant = files.add('moved.txt', moved.path);
    await deps!.importer!.relink(result.bookId, newGrant, job());
    expect(files.retained.contains(grant.id), false);
    expect(
      (await deps!.importer!.verify(result.bookId, job())).mode,
      ImportMode.reference,
    );
    await moved.writeAsString('原文件改变，不能伪装成旧修订。');
    await expectLater(
      deps!.importer!.verify(result.bookId, job()),
      throwsA(isA<ImportFailure>()),
    );
    await expectLater(
      deps!.importer!.relink(result.bookId, newGrant, job()),
      throwsA(isA<ImportFailure>()),
    );
  });
  test('cancellation and read/disk failures clean staging and never add false complete records', () async {
    var active = true;
    files.afterChunk = () async {
      active = false;
    };
    await expectLater(
      deps!.importer!.prepare(await sample('简体-utf8.txt'), job(() => active)),
      throwsA(isA<JobCancelled>()),
    );
    files.afterChunk = null;
    files.failRead = true;
    await expectLater(
      deps!.importer!.prepare(await sample('简体-utf8.txt'), job()),
      throwsA(isA<ImportFailure>()),
    );
    files.failRead = false;
    final stage = Directory('${dir.path}/support/novel/import-stage');
    expect(await stage.list().toList(), isEmpty);
    await stage.delete();
    await File(stage.path).writeAsString('simulated unavailable disk');
    await expectLater(
      deps!.importer!.prepare(await sample('简体-utf8.txt'), job()),
      throwsA(isA<ImportFailure>()),
    );
    expect((await deps!.library.load(job())).value, isEmpty);
    expect(files.reads, files.closed);
  });
  test('transaction failure rolls back metadata, removes new object and does not modify external bytes', () async {
    final importer = deps!.importer!;
    final preview = await importer.prepare(await sample('同名A.txt'), job());
    final db = (deps!.library as LocalLibrary).database;
    await db.transaction([
      const SqlCommand(
        "CREATE TRIGGER reject_import BEFORE INSERT ON imports BEGIN SELECT RAISE(ABORT,'test_disk_failure'); END",
      ),
    ]);
    await expectLater(
      importer.commit(
        preview.id,
        mode: ImportMode.managed,
        rating: RatingLevel.general,
        job: job(),
      ),
      throwsA(isA<ImportFailure>()),
    );
    expect(await db.query('SELECT id FROM books'), isEmpty);
    expect(
      await File('${dir.path}/support/novel/objects/${preview.digest}')
          .exists(),
      false,
    );
    expect(
      await File(files.paths[preview.grant.id]!).readAsString(),
      contains('同名测试甲'),
    );
    await importer.discard(preview.id);
  });
  test('EPUB CRC/container metadata accepted; corrupt, traversal, entities, encryption, bomb and unsupported formats denied', () async {
    final importer = deps!.importer!;
    final valid = await importer.prepare(await sample('有效.epub'), job());
    expect(valid.title, '自产导入试验');
    await importer.commit(
      valid.id,
      mode: ImportMode.managed,
      rating: RatingLevel.general,
      job: job(),
    );
    for (final name in [
      '坏包.epub',
      '路径穿越.epub',
      '外部实体.epub',
      '加密标记.epub',
      '展开超限.epub',
    ]) {
      await expectLater(
        importer.prepare(await sample(name), job()),
        throwsA(isA<ImportFailure>()),
      );
    }
    await expectLater(
      importer.prepare(await sample('同名A.txt', display: 'script.json'), job()),
      throwsA(isA<ImportFailure>()),
    );
    expect((await deps!.library.load(job())).value, hasLength(1));
    expect(
      await Directory('${dir.path}/support/novel/import-stage').list().toList(),
      isEmpty,
    );
    expect(
      () => EpubInspector.resolveHref('OEBPS/content.opf', '../../escape'),
      throwsA(isA<ImportFailure>()),
    );
    expect(
      EpubInspector.resolveHref('OEBPS/text/content.opf', '../chapter.xhtml'),
      'OEBPS/chapter.xhtml',
    );
  });
  test('read-only original is untouched; managed copy survives its removal and startup clears only stale staging', () async {
    final source = File('${dir.path}/readonly.txt');
    await source.writeAsString('自产只读原件。');
    if (Platform.isMacOS || Platform.isLinux) {
      expect((await Process.run('chmod', ['444', source.path])).exitCode, 0);
    }
    final preview = await deps!.importer!.prepare(
      files.add('readonly.txt', source.path),
      job(),
    );
    final receipt = await deps!.importer!.commit(
      preview.id,
      mode: ImportMode.managed,
      rating: RatingLevel.general,
      job: job(),
    );
    expect(await source.readAsString(), '自产只读原件。');
    await source.delete();
    await File('${dir.path}/support/novel/import-stage/interrupted')
        .writeAsString('unfinished');
    await deps!.close!();
    deps = await AppDependencies.open(Locations(dir.path), documents: files);
    await deps!.importer!.verify(receipt.bookId, job());
    expect(
      await Directory('${dir.path}/support/novel/import-stage').list().toList(),
      isEmpty,
    );
    expect((await deps!.library.load(job())).value.single.id, receipt.bookId);
  });
  test('large files are streamed with a hard byte limit and scope closes on rejection', () async {
    final file = File('${dir.path}/large.txt');
    final writer = await file.open(mode: FileMode.write);
    await writer.truncate(LocalImporter.maxBytes + 1);
    await writer.close();
    await expectLater(
      deps!.importer!.prepare(files.add('large.txt', file.path), job()),
      throwsA(isA<ImportFailure>()),
    );
    expect(files.reads, files.closed);
    expect(
      await Directory('${dir.path}/support/novel/import-stage').list().toList(),
      isEmpty,
    );
  });
}
