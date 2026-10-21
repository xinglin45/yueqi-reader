import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/domain/documents.dart';
import 'package:novel_app/domain/jobs.dart';
import 'package:novel_app/infrastructure/storage/local_library.dart';
import 'package:novel_app/infrastructure/storage/schema.dart';
import 'package:reader_core/reader_core.dart';
import 'package:reader_storage/reader_storage.dart';

JobContext job() => JobContext(id: 1, isCurrent: () => true, report: (_) {});
Future<StorageDatabase> open(
  String path, {
  List<SchemaStep>? schema,
  ReaderProduct product = ReaderProduct.novel,
}) => StorageDatabase.open(
  directory: path,
  product: product,
  migrations: schema ?? novelSchema,
);
DocumentAnchor anchor(
  String revision, {
  String block = 'p1',
  String text = '📖 e\u0301，目标位置在这里。',
}) => DocumentAnchor.capture(
  kind: DocumentKind.txt,
  revision: revision,
  chapterId: LocalLibrary.chapterId,
  spineHref: LocalLibrary.spine,
  blockId: block,
  text: text,
  start: 6,
  end: 10,
);
void main() {
  late Directory dir;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('阅栖-MAC03-');
  });
  tearDown(() async {
    await dir.delete(recursive: true);
  });
  test('v2 to v3 preserves cursors and allows retained parser revisions of the same bytes', () async {
    var db = await open(dir.path, schema: novelSchema.take(2).toList());
    var library = LocalLibrary(db, ContentFiles(dir.path));
    final book = (await library.addDemonstration(job())).value.single;
    final preview = (await library.preview(book.id, job())).value;
    final position = DocumentAnchor.capture(
      kind: DocumentKind.txt,
      revision: preview.documentRevision!,
      chapterId: preview.chapterId!,
      spineHref: preview.spineHref!,
      blockId: 'p1',
      text: preview.paragraphs[1],
      start: 0,
      end: 0,
    );
    await library.savePosition(
      book.id,
      PositionChannel.reading,
      position,
      expectedSequence: 0,
    );
    await db.close();
    db = await open(dir.path);
    addTearDown(db.close);
    library = LocalLibrary(db, ContentFiles(dir.path));
    expect(db.readOnly, false);
    expect(
      (await library.loadPosition(
        book.id,
        PositionChannel.reading,
      ))!.anchor.toJson(),
      position.toJson(),
    );
    expect((await library.preview(book.id, job())).value.restoredBlockId, 'p1');
    await db.transaction([
      SqlCommand(
        '''INSERT INTO documents(id,book_id,digest,kind,media_type,byte_length,parser_version,created_at)
      SELECT 'new-parser-revision',book_id,digest,kind,media_type,byte_length,'parser-v2',created_at FROM documents WHERE id=?''',
        [preview.documentRevision!],
      ),
    ]);
    expect(await db.query('SELECT id FROM documents'), hasLength(2));
    expect(await db.query('PRAGMA foreign_key_check'), isEmpty);
  });
  test('backup failure prevents migration and never labels an incomplete backup valid', () async {
    var db = await open(dir.path, schema: [novelSchema.first]);
    final library = LocalLibrary(db, ContentFiles(dir.path));
    final book = (await library.addDemonstration(job())).value.single;
    await db.close();
    await File('${dir.path}/migration-backups').writeAsString('occupied');
    db = await open(dir.path);
    addTearDown(db.close);
    expect(db.readOnly, true);
    expect(db.info['version'], 1);
    expect(db.info['backup'], null);
    expect((await db.query('SELECT id FROM books')).single['id'], book.id);
  });
  test(
    'context relocation is explicit and repeated text never silently wins',
    () {
      const text = '起点📖 e\u0301，目标位置，后文保留。';
      final start = text.indexOf('目标位置');
      final original = DocumentAnchor.capture(
        kind: DocumentKind.epub,
        revision: 'r',
        chapterId: 'c',
        spineHref: 'OEBPS/ch1.xhtml',
        blockId: 'p',
        text: text,
        start: start,
        end: start + 4,
      );
      final context = original.resolve(
        currentRevision: 'r',
        currentChapter: 'c',
        currentSpine: 'OEBPS/ch1.xhtml',
        blocks: {'p': '前缀$text'},
      );
      expect(context.match, AnchorMatch.context);
      expect(context.original.start, start);
      expect(context.candidate!.start, start + 2);
      final repeated = original.resolve(
        currentRevision: 'r',
        currentChapter: 'c',
        currentSpine: 'OEBPS/ch1.xhtml',
        blocks: {'p': '前缀$text$text'},
      );
      expect(repeated.match, AnchorMatch.chapterStart);
      expect(repeated.candidate, null);
    },
  );
  test(
    'managed file budgets and symlinks cannot masquerade as owned content',
    () async {
      final files = ContentFiles(dir.path);
      await expectLater(
        files.put([1, 2, 3], maxBytes: 2),
        throwsA(isA<StorageFailure>()),
      );
      final digest = await files.put([1, 2, 3]);
      await expectLater(
        files.read(digest, maxBytes: 2),
        throwsA(isA<StorageFailure>()),
      );
      final external = File('${dir.path}/external');
      await external.writeAsString('untouched');
      await Link('${dir.path}/objects/${'0' * 64}').create(external.path);
      await expectLater(files.read('0' * 64), throwsA(isA<StorageFailure>()));
      expect(await external.readAsString(), 'untouched');
    },
  );
  test('actual SQLite binding supports FTS5 literal Chinese with short-query fallback', () async {
    final db = await open(dir.path);
    addTearDown(db.close);
    expect(db.readOnly, false);
    await db.transaction([
      const SqlCommand(
        "CREATE VIRTUAL TABLE research_tri USING fts5(body,tokenize='trigram case_sensitive 1')",
      ),
      const SqlCommand('INSERT INTO research_tri VALUES(?)', [
        '山间来信，山間來信。📖 e\u0301，100%_',
      ]),
    ]);
    for (final query in [
      '山',
      '山间',
      '山间来信',
      '山間來信',
      '📖',
      'e\u0301',
      '100%_',
      '，',
      '不存在词',
    ]) {
      final literal = await db.query(
        'SELECT body FROM research_tri WHERE instr(body,?)>0',
        [query],
      );
      expect(literal.length, query == '不存在词' ? 0 : 1);
      if (query.runes.length >= 3) {
        final matches = await db.query(
          'SELECT body FROM research_tri WHERE research_tri MATCH ? AND instr(body,?)>0',
          ['"${query.replaceAll('"', '""')}"', query],
        );
        expect(matches, literal);
      }
    }
    expect((await db.query('PRAGMA foreign_keys')).single.values.single, 1);
  });
  test(
    'sample, stable identity, files and independent cursors survive reopening',
    () async {
      var db = await open(dir.path);
      var library = LocalLibrary(db, ContentFiles(dir.path));
      final first = (await library.addDemonstration(job())).value.single;
      final preview = (await library.preview(first.id, job())).value;
      final read = DocumentAnchor.capture(
        kind: DocumentKind.txt,
        revision: preview.documentRevision!,
        chapterId: preview.chapterId!,
        spineHref: preview.spineHref!,
        blockId: 'p1',
        text: preview.paragraphs[1],
        start: 0,
        end: 0,
      );
      await library.savePosition(
        first.id,
        PositionChannel.reading,
        read,
        expectedSequence: 0,
      );
      final listen = DocumentAnchor.capture(
        kind: DocumentKind.txt,
        revision: preview.documentRevision!,
        chapterId: preview.chapterId!,
        spineHref: preview.spineHref!,
        blockId: 'p0',
        text: preview.paragraphs[0],
        start: 0,
        end: 0,
      );
      await library.savePosition(
        first.id,
        PositionChannel.listening,
        listen,
        expectedSequence: 0,
      );
      await library.saveSetting('theme', 'dark');
      await db.close();
      db = await open(dir.path);
      addTearDown(db.close);
      library = LocalLibrary(db, ContentFiles(dir.path));
      final again = (await library.addDemonstration(job())).value;
      expect(again.single.id, first.id);
      expect(
        (await library.preview(first.id, job())).value.restoredBlockId,
        'p1',
      );
      expect(
        (await library.loadPosition(
          first.id,
          PositionChannel.listening,
        ))!.anchor.blockId,
        'p0',
      );
      expect(await library.loadSetting('theme'), 'dark');
      expect((await db.query('SELECT * FROM documents')).length, 1);
    },
  );
  test(
    'failed multi-row writes roll back and later writes still work',
    () async {
      final db = await open(dir.path);
      addTearDown(db.close);
      await expectLater(
        db.transaction([
          const SqlCommand(
            "INSERT INTO books(id,title,language,created_at,updated_at) VALUES('rollback','同名','zh',0,0)",
          ),
          const SqlCommand(
            "INSERT INTO chapters VALUES('orphan','missing-doc',0,'坏引用','bad')",
          ),
        ]),
        throwsA(isA<StorageFailure>()),
      );
      expect(await db.query('SELECT * FROM books'), isEmpty);
      final library = LocalLibrary(db, ContentFiles(dir.path));
      expect((await library.addDemonstration(job())).value, hasLength(1));
      await expectLater(
        library.saveSetting('age_acknowledged', true),
        throwsA(isA<StorageFailure>()),
      );
    },
  );
  test('stale concurrent position writes cannot overwrite newer progress or another book', () async {
    final db = await open(dir.path);
    addTearDown(db.close);
    final library = LocalLibrary(db, ContentFiles(dir.path));
    final book = (await library.addDemonstration(job())).value.single;
    final preview = (await library.preview(book.id, job())).value;
    final point = anchor(preview.documentRevision!);
    await expectLater(
      library.savePosition(
        book.id,
        PositionChannel.reading,
        point,
        expectedSequence: 5,
      ),
      throwsA(isA<StorageFailure>()),
    );
    final outcomes = await Future.wait(
      List.generate(
        2,
        (_) => library
            .savePosition(
              book.id,
              PositionChannel.reading,
              point,
              expectedSequence: 0,
            )
            .then((_) => true, onError: (Object _) => false),
      ),
    );
    expect(outcomes.where((ok) => ok), hasLength(1));
    expect(
      (await library.loadPosition(book.id, PositionChannel.reading))!.sequence,
      1,
    );
    await expectLater(
      library.savePosition(
        'another-book',
        PositionChannel.reading,
        point,
        expectedSequence: 0,
      ),
      throwsA(isA<AppFailure>()),
    );
  });
  test('v1 upgrade backs up data; injected migration failure remains read-only and recoverable', () async {
    var db = await open(dir.path, schema: [novelSchema.first]);
    var library = LocalLibrary(db, ContentFiles(dir.path));
    final book = (await library.addDemonstration(job())).value.single;
    await db.close();
    db = await open(
      dir.path,
      schema: [
        novelSchema.first,
        const SchemaStep(2, [
          'CREATE TABLE transient_test(id INTEGER)',
          'THIS IS INVALID SQL',
        ]),
      ],
    );
    expect(db.readOnly, true);
    expect(db.info['recovery'], 'migration_failed');
    expect((await db.query('SELECT id FROM books')).single['id'], book.id);
    expect(
      await db.query(
        "SELECT name FROM sqlite_master WHERE name='transient_test'",
      ),
      isEmpty,
    );
    await expectLater(
      db.transaction([const SqlCommand('DELETE FROM books')]),
      throwsA(isA<StorageFailure>()),
    );
    final backup = File('${dir.path}/migration-backups/${db.info['backup']}');
    expect(backup.existsSync(), true);
    await db.close();
    final restored = await Directory('${dir.path}/restore').create();
    await backup.copy('${restored.path}/novel.sqlite');
    final restoredDb = await open(restored.path, schema: [novelSchema.first]);
    expect(
      (await restoredDb.query('SELECT id FROM books')).single['id'],
      book.id,
    );
    await restoredDb.close();
    db = await open(dir.path);
    addTearDown(db.close);
    library = LocalLibrary(db, ContentFiles(dir.path));
    expect(db.info['version'], 5);
    expect(db.readOnly, false);
    expect((await library.load(job())).value.single.id, book.id);
    expect(await library.loadSetting('theme'), null);
  });
  test(
    'newer schema never downgraded; novel and comic data remain isolated',
    () async {
      var novel = await open('${dir.path}/novel');
      final library = LocalLibrary(novel, ContentFiles('${dir.path}/novel'));
      await library.addDemonstration(job());
      await novel.close();
      novel = await open('${dir.path}/novel', schema: [novelSchema.first]);
      expect(novel.readOnly, true);
      expect(novel.info['recovery'], 'newer_schema');
      await novel.close();
      final comic = await open(
        '${dir.path}/comic',
        product: ReaderProduct.comic,
      );
      expect(await comic.query('SELECT * FROM books'), isEmpty);
      await comic.close();
      await File('${dir.path}/novel/novel.sqlite')
          .copy('${dir.path}/comic/comic.sqlite');
      await expectLater(
        open('${dir.path}/comic', product: ReaderProduct.comic),
        throwsA(
          isA<StorageFailure>().having((e) => e.code, 'code', 'wrong_product'),
        ),
      );
    },
  );
  test(
    'corrupt DB and missing/corrupt objects stay intact and report failure',
    () async {
      final bad = File('${dir.path}/novel.sqlite');
      final bytes = utf8.encode('not a sqlite database');
      await bad.writeAsBytes(bytes);
      await expectLater(open(dir.path), throwsA(isA<StorageFailure>()));
      expect(await bad.readAsBytes(), bytes);
      final files = ContentFiles('${dir.path}/content');
      final hash = await files.put(utf8.encode('简繁📖'));
      expect(await files.read(hash), utf8.encode('简繁📖'));
      expect((await files.audit({hash, '0' * 64}))['missing'], ['0' * 64]);
      expect((await files.audit({}))['orphaned'], [hash]);
      await File('${dir.path}/content/objects/$hash').writeAsString('changed');
      await expectLater(
        files.read(hash),
        throwsA(
          isA<StorageFailure>().having((e) => e.code, 'code', 'file_corrupt'),
        ),
      );
      await expectLater(
        files.read('../private'),
        throwsA(isA<StorageFailure>()),
      );
      await expectLater(
        files.read('0' * 64),
        throwsA(
          isA<StorageFailure>().having((e) => e.code, 'code', 'file_missing'),
        ),
      );
    },
  );
  test('unknown permissions stay unknown and soft-deleted metadata is not displayed', () async {
    final db = await open(dir.path);
    addTearDown(db.close);
    final library = LocalLibrary(db, ContentFiles(dir.path));
    final book = (await library.addDemonstration(job())).value.single;
    await db.transaction([
      const SqlCommand(
        "INSERT INTO books(id,title,language,created_at,updated_at) VALUES('unknown','同名','zh',0,0)",
      ),
      SqlCommand(
        "INSERT INTO source_bindings(id,book_id,source_id,source_item_id) VALUES('source',?,'s','item')",
        [book.id],
      ),
    ]);
    expect(
      (await db.query(
        "SELECT cache_permission,verification FROM source_bindings",
      )).single,
      {'cache_permission': 'unknown', 'verification': 'unknown'},
    );
    expect((await library.load(job())).value, hasLength(1));
    await db.transaction([
      SqlCommand(
        'UPDATE books SET deleted=1,row_revision=row_revision+1 WHERE id=?',
        [book.id],
      ),
    ]);
    expect((await library.load(job())).value, isEmpty);
    expect(
      (await db.query('SELECT row_revision FROM books WHERE id=?', [
        book.id,
      ])).single['row_revision'],
      2,
    );
  });
  test('anchor protocol preserves Unicode, rejects unsafe wire offsets and explains fallback', () {
    const text = '📖 e\u0301，目标位置在这里。';
    final a = anchor('r');
    expect(scalarToUtf16(text, 5), 6);
    expect(utf16ToScalar(text, 6), 5);
    final restored = DocumentAnchor.fromJson(
      jsonDecode(jsonEncode(a.toJson())) as Map<String, dynamic>,
    );
    expect(
      restored
          .resolve(
            currentRevision: 'r',
            currentChapter: LocalLibrary.chapterId,
            currentSpine: LocalLibrary.spine,
            blocks: {'p1': text},
          )
          .match,
      AnchorMatch.exact,
    );
    final fallback = restored.resolve(
      currentRevision: 'r2',
      currentChapter: LocalLibrary.chapterId,
      currentSpine: LocalLibrary.spine,
      blocks: {'p1': text},
    );
    expect(fallback.match, AnchorMatch.chapterStart);
    expect(fallback.original.toJson(), a.toJson());
    expect(fallback.candidate, null);
    for (final value in [
      double.nan,
      double.infinity,
      -1,
      1.25,
      '6',
      9007199254740992,
    ]) {
      expect(() => bridgeInteger(value), throwsFormatException);
    }
    expect(() => utf16ToScalar(text, 1), throwsFormatException);
    expect(
      () => DocumentAnchor.fromJson({...a.toJson(), 'schema_version': 2}),
      throwsFormatException,
    );
    expect(
      () => DocumentAnchor.fromJson({...a.toJson(), 'exact': '变更'}),
      throwsFormatException,
    );
    expect(
      () => DocumentAnchor.capture(
        kind: DocumentKind.txt,
        revision: 'r',
        chapterId: 'c',
        spineHref: 's',
        blockId: 'p',
        text: text,
        start: 1,
        end: 2,
      ),
      throwsFormatException,
    );
  });
}
