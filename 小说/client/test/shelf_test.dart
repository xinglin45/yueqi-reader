import 'package:novel_app/domain/jobs.dart';

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/app/dependencies.dart';
import 'package:novel_app/domain/access.dart';
import 'package:novel_app/domain/importing.dart';
import 'package:novel_app/domain/shelf.dart';
import 'package:novel_app/domain/documents.dart';
import 'package:novel_app/infrastructure/storage/local_library.dart';
import 'package:novel_app/infrastructure/storage/schema.dart';
import 'package:reader_core/reader_core.dart';
import 'package:reader_storage/reader_storage.dart';

import 'access_test.dart' show Locations;
import 'import_test.dart' show ImportFiles, job;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late ImportFiles files;
  AppDependencies? deps;
  LocalLibrary getLibrary() => deps!.library as LocalLibrary;
  Future<ShelfPage> list({
    ShelfOptions options = const ShelfOptions(),
    ShelfScope scope = ShelfScope.normal,
    int page = 0,
    bool recent = false,
  }) => deps!.shelf!.list(scope, options, job(), page: page, recent: recent);
  Future<String> sample() async =>
      (await deps!.library.addDemonstration(job())).value.single.id;
  Future<String> import({
    ImportMode mode = ImportMode.managed,
    String name = '简体-utf8.txt',
    RatingLevel rating = RatingLevel.general,
  }) async {
    final p = await deps!.importer!.prepare(
      files.add(name, '../../fixtures/novel/mac04/$name'),
      job(),
    );
    return (await deps!.importer!.commit(
      p.id,
      mode: mode,
      rating: rating,
      job: job(),
    )).bookId;
  }

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('mac08-');
    files = ImportFiles();
    deps = await AppDependencies.open(Locations(dir.path), documents: files);
  });
  tearDown(() async {
    await deps?.close?.call();
    await files.incoming.close();
    await dir.delete(recursive: true);
  });
  test('v6 migration keeps immutable revisions, position, original and policy; adds defaults', () async {
    await deps!.close!.call();
    deps = null;
    final root = '${dir.path}/legacy/support/novel';
    var db = await StorageDatabase.open(
      directory: root,
      product: ReaderProduct.novel,
      migrations: novelSchema.take(6).toList(),
    );
    final library = LocalLibrary(db, ContentFiles(root));
    final id = (await library.addDemonstration(job())).value.single.id;
    final preview = (await library.preview(id, job())).value;
    final anchor = DocumentAnchor.capture(
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
      id,
      PositionChannel.reading,
      anchor,
      expectedSequence: 0,
    );
    await db.close();
    deps = await AppDependencies.open(
      Locations('${dir.path}/legacy'),
      documents: files,
    );
    expect(getLibrary().database.info['version'], novelSchema.last.version);
    expect((await list()).books.single.state, ReadingState.reading);
    expect(
      (await getLibrary().loadPosition(
        id,
        PositionChannel.reading,
      ))!.anchor.toJson(),
      anchor.toJson(),
    );
    expect(
      await getLibrary().database.query('PRAGMA foreign_key_check'),
      isEmpty,
    );
    expect(
      await getLibrary().database.query(
        "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'",
      ),
      hasLength(21),
    );
  });
  test('metadata, tags, favorites, manual order, filters and preferences survive reopen; digest is unchanged', () async {
    final id = await import();
    final before = (await getLibrary().database.query(
      'SELECT digest FROM documents WHERE book_id=?',
      [id],
    )).single;
    final group = await deps!.shelf!.createGroup(
      ShelfScope.normal,
      '秋日',
      'tag',
    );
    final book = (await list()).books.single;
    await deps!.shelf!.edit(
      {id: book.revision},
      BookEdit(
        title: '山間 📖',
        author: '自产作者',
        synopsis: '保留简繁与组合e\u0301',
        language: 'zh-Hant',
        state: ReadingState.finished,
        favorite: true,
        order: 7,
        groups: [group],
      ),
    );
    const options = ShelfOptions(
      grid: false,
      state: 'finished',
      sort: ShelfSort.author,
      favorite: true,
      search: '秋日',
    );
    await deps!.shelf!.savePreferences(ShelfScope.normal, options);
    await deps!.close!.call();
    deps = await AppDependencies.open(Locations(dir.path), documents: files);
    expect(
      (await deps!.shelf!.preferences(ShelfScope.normal)).toJson(),
      options.toJson(),
    );
    final current = (await list(options: options)).books.single;
    expect(current.book.title, '山間 📖');
    expect(current.author, '自产作者');
    expect(current.groups, [group]);
    expect(current.order, 7);
    expect(
      (await getLibrary().database.query(
        'SELECT digest FROM documents WHERE book_id=?',
        [id],
      )).single,
      before,
    );
    await deps!.shelf!.removeGroup(ShelfScope.normal, group);
    expect((await list()).groups.single.removed, true);
    await deps!.shelf!.removeGroup(ShelfScope.normal, group, removed: false);
    expect((await list(options: options)).total, 1);
  });
  test('only successfully opened books become recent; finished status is not reset and adult stays separate', () async {
    final a = await sample();
    await import();
    expect((await list(recent: true)).books, isEmpty);
    await deps!.shelf!.markOpened(a);
    expect((await list(recent: true)).books.single.book.id, a);
    final b = (await list(recent: true)).books.single;
    await deps!.shelf!.edit({
      a: b.revision,
    }, const BookEdit(state: ReadingState.finished));
    await deps!.shelf!.markOpened(a);
    expect(
      (await list(recent: true)).books.single.state,
      ReadingState.finished,
    );
  });
  test('batch revision conflict and SQL failure roll back the whole edit and undo log', () async {
    await sample();
    await import();
    final books = (await list()).books;
    final stale = {for (final b in books) b.book.id: b.revision};
    await deps!.shelf!.markOpened(books.first.book.id);
    await expectLater(
      deps!.shelf!.edit(stale, const BookEdit(favorite: true)),
      throwsA(isA<StorageFailure>()),
    );
    expect((await list()).books.every((b) => !b.favorite), true);
    final db = getLibrary().database;
    await db.transaction([
      const SqlCommand(
        "CREATE TRIGGER fail_metadata BEFORE INSERT ON book_metadata BEGIN SELECT RAISE(ABORT,'test'); END",
      ),
    ]);
    final current = (await list()).books;
    final prior = await db.query('SELECT id FROM shelf_actions');
    await expectLater(
      deps!.shelf!.edit({
        for (final b in current) b.book.id: b.revision,
      }, const BookEdit(favorite: true)),
      throwsA(isA<StorageFailure>()),
    );
    expect(await db.query('SELECT id FROM shelf_actions'), prior);
    expect((await list()).books.every((b) => !b.favorite), true);
  });
  test('remove/restore and durable undo retain book identity, file and independent positions', () async {
    final id = await import(mode: ImportMode.reference);
    final original = File('../../fixtures/novel/mac04/简体-utf8.txt');
    final bytes = await original.readAsBytes();
    final book = (await list()).books.single;
    final action = await deps!.shelf!.edit({
      id: book.revision,
    }, const BookEdit(removed: true));
    expect((await list()).total, 0);
    expect(
      (await list(options: const ShelfOptions(removed: true)))
          .books
          .single
          .book
          .id,
      id,
    );
    await deps!.close!.call();
    deps = await AppDependencies.open(Locations(dir.path), documents: files);
    expect(await deps!.shelf!.latestAction(ShelfScope.normal), action);
    await deps!.shelf!.undo(action);
    expect((await list()).books.single.book.id, id);
    expect(await original.readAsBytes(), bytes);
    await expectLater(
      deps!.shelf!.recycleFile(id),
      throwsA(isA<StorageFailure>()),
    );
    expect(await original.readAsBytes(), bytes);
  });
  test('undo rejects newer changes; personal records removal has separate reversible semantics', () async {
    final id = await sample();
    final library = getLibrary();
    final p = (await library.preview(id, job())).value;
    final anchor = DocumentAnchor.capture(
      kind: DocumentKind.txt,
      revision: p.documentRevision!,
      chapterId: p.chapterId!,
      spineHref: p.spineHref!,
      blockId: 'p0',
      text: p.paragraphs[0],
      start: 0,
      end: 0,
    );
    await library.savePosition(
      id,
      PositionChannel.reading,
      anchor,
      expectedSequence: 0,
    );
    await library.savePosition(
      id,
      PositionChannel.listening,
      anchor,
      expectedSequence: 0,
    );
    var b = (await list()).books.single;
    final action = await deps!.shelf!.edit({
      id: b.revision,
    }, const BookEdit(clearRecords: true));
    expect(await library.loadPosition(id, PositionChannel.reading), null);
    await deps!.shelf!.undo(action);
    expect(
      await library.loadPosition(id, PositionChannel.listening),
      isNotNull,
    );
    b = (await list()).books.single;
    final old = await deps!.shelf!.edit({
      id: b.revision,
    }, const BookEdit(favorite: true));
    await deps!.shelf!.markOpened(id);
    await expectLater(deps!.shelf!.undo(old), throwsA(isA<StorageFailure>()));
    expect((await list()).books.single.favorite, true);
  });
  test('managed recycle moves only a verified object and resumes recorded intent after restart', () async {
    final id = await import();
    final db = getLibrary().database;
    final digest =
        (await db.query('SELECT digest FROM documents WHERE book_id=?', [
              id,
            ])).first['digest']
            as String;
    final root = '${dir.path}/support/novel';
    final original = File('$root/objects/$digest'),
        recycled = File('$root/recycle/$digest');
    final bytes = await original.readAsBytes();
    // Simulate interruption after intent committed and before atomic rename.
    await db.transaction([
      SqlCommand("INSERT INTO file_recycle VALUES(?,?,'recycle')", [
        id,
        digest,
      ]),
    ]);
    await deps!.close!.call();
    deps = await AppDependencies.open(Locations(dir.path), documents: files);
    expect(await original.exists(), false);
    expect(await recycled.readAsBytes(), bytes);
    expect((await list()).books.single.recycled, true);
    await expectLater(getLibrary().checkAccess(id), throwsA(isA<AppFailure>()));
    await deps!.shelf!.restoreFile(id);
    expect(await original.readAsBytes(), bytes);
    expect(await recycled.exists(), false);
    expect((await list()).books.single.recycled, false);
    await deps!.shelf!.recycleFile(id);
    final p = await deps!.importer!.prepare(
      files.add('重复.txt', '../../fixtures/novel/mac04/简体-utf8.txt'),
      job(),
    );
    await expectLater(
      deps!.importer!.commit(
        p.id,
        mode: ImportMode.managed,
        rating: RatingLevel.general,
        job: job(),
      ),
      throwsA(
        isA<ImportFailure>().having(
          (e) => e.issue,
          'issue',
          ImportIssue.recovery,
        ),
      ),
    );
    await deps!.importer!.discard(p.id);
  });
  test('recycle refuses symlinks and keeps intent for recovery; no external target is moved', () async {
    final id = await import();
    final root = '${dir.path}/support/novel';
    final external = Directory('${dir.path}/untouched');
    await external.create();
    await Link('$root/recycle').create(external.path);
    await expectLater(
      deps!.shelf!.recycleFile(id),
      throwsA(isA<StorageFailure>()),
    );
    expect(await external.list().toList(), isEmpty);
    expect(
      await getLibrary().database.query('SELECT book_id FROM file_recycle'),
      hasLength(1),
    );
    await Link('$root/recycle').delete();
    await deps!.shelf!.restoreFile(id);
    expect((await list()).books.single.health, 'available');
  });
  test('adult groups, metadata, cover and recovery operations respect search OFF and fail closed on lock', () async {
    await deps!.access!.acknowledge();
    await deps!.access!.unlock();
    final id = await import(rating: RatingLevel.restricted);
    expect(
      (await getLibrary().database.query(
        "SELECT scope FROM collections WHERE id='adult-default'",
      )).single['scope'],
      'adult',
    );
    final group = await deps!.shelf!.createGroup(
      ShelfScope.adult,
      '私密标签',
      'tag',
    );
    final adult = (await list(scope: ShelfScope.adult)).books.single;
    final normalGroup = await deps!.shelf!.createGroup(
      ShelfScope.normal,
      '普通标签',
      'tag',
    );
    await expectLater(
      deps!.shelf!.edit({id: adult.revision}, BookEdit(groups: [normalGroup])),
      throwsFormatException,
    );
    await deps!.shelf!.edit({id: adult.revision}, BookEdit(groups: [group]));
    expect((await list()).books, isEmpty);
    expect((await list()).groups.map((g) => g.label), ['普通标签']);
    expect(deps!.access!.state.includeAdultSources, false);
    await deps!.shelf!.markOpened(id);
    expect((await list(scope: ShelfScope.adult, recent: true)).total, 1);
    await deps!.access!.lock();
    await expectLater(
      list(scope: ShelfScope.adult),
      throwsA(isA<AppFailure>()),
    );
    await expectLater(deps!.shelf!.cover(id), throwsA(isA<AppFailure>()));
    await expectLater(deps!.shelf!.recycleFile(id), throwsA(isA<AppFailure>()));
    expect((await list()).total, 0);
  });
  test('same titles keep independent identities; pages are bounded with exact totals and cancelled work rejects', () async {
    final db = getLibrary().database;
    await db.transaction([
      for (var i = 0; i < 61; i++) ...[
        SqlCommand(
          "INSERT INTO books(id,title,language,rating,created_at,updated_at) VALUES(?,'同名','zh','general',?,1)",
          ['own-$i', i],
        ),
        SqlCommand(
          "INSERT INTO content_policy(book_id,level,policy_version,source_access) VALUES(?,'general','owned','notRequired')",
          ['own-$i'],
        ),
      ],
    ]);
    final first = await list(), second = await list(page: 1);
    expect(first.total, 61);
    expect(first.books, hasLength(50));
    expect(second.books, hasLength(11));
    expect({
      ...first.books.map((b) => b.book.id),
      ...second.books.map((b) => b.book.id),
    }, hasLength(61));
    expect(first.books.first.similarTitles, 60);
    await expectLater(
      deps!.shelf!.list(
        ShelfScope.normal,
        const ShelfOptions(),
        job(() => false),
      ),
      throwsA(isA<JobCancelled>()),
    );
  });
  test('cover validates header/decode budget, normalizes owned image, persists and undoes without touching original', () async {
    final id = await sample();
    final b = (await list()).books.single;
    final source = File('assets/mountain-letter-cover.png');
    final bytes = await source.readAsBytes();
    final action = await deps!.shelf!.setCover(id, b.revision, bytes);
    final cover = await deps!.shelf!.cover(id);
    expect(cover, isNotNull);
    expect(cover!.length, lessThan(bytes.length));
    expect(await source.readAsBytes(), bytes);
    final revision = (await list()).books.single.revision;
    await expectLater(
      deps!.shelf!.setCover(id, revision, Uint8List(5 * 1024 * 1024)),
      throwsFormatException,
    );
    final huge = Uint8List.fromList(bytes);
    ByteData.sublistView(huge).setUint32(16, 100000);
    await expectLater(
      deps!.shelf!.setCover(id, revision, huge),
      throwsFormatException,
    );
    await deps!.close!.call();
    deps = await AppDependencies.open(Locations(dir.path), documents: files);
    expect(await deps!.shelf!.cover(id), cover);
    await deps!.shelf!.undo(action);
    expect(await deps!.shelf!.cover(id), null);
  });
}
