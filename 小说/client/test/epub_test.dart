import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader_storage/reader_storage.dart';
import 'package:novel_app/app/dependencies.dart';
import 'package:novel_app/domain/access.dart';
import 'package:novel_app/domain/documents.dart';
import 'package:novel_app/domain/epub.dart';
import 'package:novel_app/domain/importing.dart';
import 'package:novel_app/domain/jobs.dart';
import 'package:novel_app/infrastructure/epub/loader.dart';
import 'package:novel_app/infrastructure/storage/local_library.dart';

import 'access_test.dart' show Locations;
import 'import_test.dart' show ImportFiles, job;

const fixture = '../../fixtures/novel/mac07';
const testSession = 's0123456789abcdef0123456789abcdef';
void main() {
  late Directory dir;
  AppDependencies? deps;
  late ImportFiles files;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('mac07-test-');
    files = ImportFiles();
  });
  tearDown(() async {
    await deps?.close?.call();
    deps = null;
    await files.incoming.close();
    await dir.delete(recursive: true);
  });
  Future<void> boot() async =>
      deps = await AppDependencies.open(Locations(dir.path), documents: files);
  Future<String> importBook({
    ImportMode mode = ImportMode.managed,
    RatingLevel rating = RatingLevel.general,
    String? path,
  }) async {
    final grant = files.add('自产 EPUB.epub', path ?? '$fixture/流式EPUB3.epub');
    final preview = await deps!.importer!.prepare(grant, job());
    return (await deps!.importer!.commit(
      preview.id,
      mode: mode,
      rating: rating,
      job: job(),
    )).bookId;
  }

  test('EPUB3 nav and EPUB2 NCX resolve nested toc, relative images and exact text runs', () async {
    for (final version in [2, 3]) {
      final output = '${dir.path}/v$version';
      final value = await loadEpub(
        '$fixture/流式EPUB$version.epub',
        output,
        testSession,
        job(),
      );
      expect((value['spine'] as List).length, 2);
      expect((value['toc'] as List).last['fragment'], 'target');
      if (version == 3) expect((value['toc'] as List)[1]['depth'], 1);
      final canonical =
          jsonDecode(await File('$output/c0.json').readAsString()) as Map;
      final text = (canonical['blocks'] as Map).values.join('');
      expect(text, contains('清晨，山间微光落在窗边。📖 e\u0301 繁體原文。'));
      expect(text, contains('沿著山路向前。'));
      expect(text, isNot(contains('shān')));
      expect(text, contains('时刻清晨'));
      final html = await File('$output/r0').readAsString();
      expect(html, contains('reader-book://$testSession/r4'));
      expect(html, isNot(contains('<script')));
      expect(html, isNot(contains('onclick')));
      expect(html, isNot(contains('https://example.invalid')));
      expect(html, contains("script-src 'none'"));
      expect(
        value['warnings'],
        containsAll(['script_removed', 'external_blocked']),
      );
    }
  });
  test('existing MAC06 embedded font, ruby and CSS use the same controlled resources', () async {
    final value = await loadEpub(
      '../../fixtures/novel/mac06/mountain-letter.epub',
      '${dir.path}/font',
      testSession,
      job(),
    );
    final resources = value['resources'] as Map;
    expect(resources.values.any((dynamic r) => r['mime'] == 'font/ttf'), true);
    final cssId = resources.keys.singleWhere(
      (dynamic k) => resources[k]['mime'] == 'text/css',
    );
    final css = await File('${dir.path}/font/$cssId').readAsString();
    expect(css, contains('reader-book://$testSession/'));
    expect(css, isNot(contains('../fonts/')));
    final chapter = jsonDecode(
      await File('${dir.path}/font/c1.json').readAsString(),
    ) as Map;
    expect(
      (chapter['blocks'] as Map).values.join(''),
      contains('📖 e\u0301，目标位置在这里'),
    );
  });
  test('unsupported, corrupt, entity, path, symlink and image budgets fail closed in worker', () async {
    final cases = {
      '缺失图片': 'missingResource',
      '片段缺失': 'missingResource',
      '固定版式': 'fixedLayout',
      '不支持SVG': 'unsupported',
      'CSS导入': 'unsupported',
      'CSS转义': 'unsupported',
      'DTD实体': 'unsupported',
      '重复DOM标识': 'corrupt',
      '符号链接': 'corrupt',
      '双重编码路径': 'corrupt',
      '超大图片尺寸': 'limit',
      '加密': 'encrypted',
    };
    for (final e in cases.entries) {
      await expectLater(
        loadEpub(
          '$fixture/${e.key}.epub',
          '${dir.path}/${e.key}',
          testSession,
          job(),
        ),
        throwsA(
          isA<EpubFailure>().having((e) => e.issue.name, 'issue', e.value),
        ),
        reason: e.key,
      );
    }
    for (final name in ['路径穿越', '坏包', '外部实体', '展开超限']) {
      await expectLater(
        loadEpub(
          '../../fixtures/novel/mac04/$name.epub',
          '${dir.path}/bad-$name',
          testSession,
          job(),
        ),
        throwsA(isA<EpubFailure>()),
      );
    }
  });
  test('XML line endings and long CDATA share exact DOM text with bounded scalar-safe spans', () async {
    final output = '${dir.path}/normalized';
    await loadEpub('$fixture/规范文本.epub', output, testSession, job());
    final value =
        jsonDecode(await File('$output/c1.json').readAsString()) as Map;
    final blocks = Map<String, String>.from(value['blocks'] as Map);
    expect(blocks.values.join(), '第二章正文甲\n正文乙\n${'長段📖e\u0301' * 1001}');
    expect(
      blocks.values.every((s) => s.length <= 2048 && !s.contains('\r')),
      true,
    );
    for (final s in blocks.values) {
      expect(utf16Boundary(s, s.length), true);
      expect(s.runes.last, isNot(inInclusiveRange(0xd800, 0xdfff)));
    }
  });
  test('canonical paths allow book-relative parents, deny authorities, query, escapes and double encoding', () {
    expect(epubHref('Book/text/one.xhtml', '../images/hill.png'), (
      'Book/images/hill.png',
      '',
    ));
    expect(epubHref('Book/text/one.xhtml', '#target'), (
      'Book/text/one.xhtml',
      'target',
    ));
    for (final href in [
      'https://example.invalid/x',
      '//other/x',
      'file:///private',
      '../../../private',
      'a?x=1',
      '%252e%252e/private',
      '..\\private',
      '/absolute',
    ]) {
      expect(
        () => epubHref('Book/text/one.xhtml', href),
        throwsA(anything),
        reason: href,
      );
    }
  });
  test('managed session persists immutable revision and exact selection anchor across full reopen', () async {
    await boot();
    final book = await importBook();
    final first = await deps!.epub!.open(book, job()),
        chapter = await deps!.epub!.chapter(first, 1, job());
    final block = chapter.blocks.keys.firstWhere(
      (id) => chapter.blocks[id]!.contains('目标位置'),
    );
    final text = chapter.blocks[block]!, start = text.indexOf('目标位置');
    final selected = epubSelection(chapter, {
      'session': first.id,
      'resource': chapter.spine.resource,
      'segments': [
        {'block': block, 'start': start, 'end': start + 4, 'exact': '目标位置'},
      ],
    });
    final saved = await deps!.positions!.savePosition(
      book,
      PositionChannel.reading,
      selected.single,
      expectedSequence: 0,
    );
    await deps!.epub!.close(first.id);
    await deps!.close!();
    deps = null;
    await boot();
    final next = await deps!.epub!.open(book, job());
    expect(next.id, isNot(first.id));
    expect(next.revision, first.revision);
    final restored = await deps!.epub!.chapter(next, 1, job());
    expect(
      saved.anchor
          .resolve(
            currentRevision: next.revision,
            currentChapter: restored.spine.id,
            currentSpine: restored.spine.href,
            blocks: restored.blocks,
          )
          .match,
      AnchorMatch.exact,
    );
    expect(
      (await deps!.positions!.loadPosition(
        book,
        PositionChannel.reading,
      ))!.anchor.exact,
      '目标位置',
    );
    expect(
      (await (deps!.library as LocalLibrary).database.query(
        'PRAGMA foreign_key_check',
      )),
      isEmpty,
    );
  });
  test('cross-inline and cross-block bridge messages verify every UTF16 segment and reject forged identities/ranges', () async {
    await boot();
    final book = await importBook(),
        session = await deps!.epub!.open(book, job());
    final chapter = await deps!.epub!.chapter(session, 0, job());
    final keys = chapter.blocks.keys.toList();
    final first = keys.firstWhere((k) => chapter.blocks[k] == '清晨，'),
        second = keys[keys.indexOf(first) + 1];
    final message = <String, Object>{
      'session': session.id,
      'resource': chapter.spine.resource,
      'segments': [
        {'block': first, 'start': 1, 'end': 3, 'exact': '晨，'},
        {'block': second, 'start': 0, 'end': 2, 'exact': '山间'},
      ],
    };
    expect(epubSelection(chapter, message).map((a) => a.exact).join(), '晨，山间');
    Map<String, Object> changed(Map<String, Object> patch) => {
      ...message,
      ...patch,
    };
    for (final bad in [
      changed({'session': 'other'}),
      changed({'resource': 'r9999'}),
      changed({
        'segments': [
          {'block': first, 'start': 0.5, 'end': 2, 'exact': '清晨'},
        ],
      }),
      changed({
        'segments': [
          {'block': first, 'start': double.nan, 'end': 2, 'exact': '清晨'},
        ],
      }),
      changed({
        'segments': [
          {'block': first, 'start': 0, 'end': 1, 'exact': '假'},
        ],
      }),
      changed({
        'segments': [
          (message['segments'] as List).last,
          (message['segments'] as List).first,
        ],
      }),
    ]) {
      expect(() => epubSelection(chapter, bad), throwsFormatException);
    }
    final emoji = keys.firstWhere((k) => chapter.blocks[k]!.contains('📖')),
        text = chapter.blocks[emoji]!,
        at = text.indexOf('📖');
    expect(
      () => epubSelection(
        chapter,
        changed({
          'segments': [
            {
              'block': emoji,
              'start': at + 1,
              'end': at + 2,
              'exact': text.substring(at + 1, at + 2),
            },
          ],
        }),
      ),
      throwsFormatException,
    );
  });
  test('reference session resources are temporary, original/grant required on reopening and changes rejected', () async {
    await boot();
    final source = await File('$fixture/流式EPUB3.epub')
        .copy('${dir.path}/original.epub');
    final book = await importBook(
      mode: ImportMode.reference,
      path: source.path,
    );
    final session = await deps!.epub!.open(book, job());
    final objects = Directory('${dir.path}/support/novel/objects');
    expect(
      await objects.exists()
          ? await objects.list().toList()
          : <FileSystemEntity>[],
      isEmpty,
    );
    final resources = Directory(
      '${dir.path}/support/novel/epub-sessions/${session.id}',
    );
    expect(await resources.exists(), true);
    expect(
      (await deps!.epub!.resource(
        session,
        session.spine.first.resource,
        job(),
      )).mime,
      'application/xhtml+xml',
    );
    await deps!.epub!.close(session.id);
    expect(await resources.exists(), false);
    await source.writeAsBytes([1, 2, 3]);
    await expectLater(
      deps!.epub!.open(book, job()),
      throwsA(isA<ImportFailure>()),
    );
    expect(
      await Directory('${dir.path}/support/novel/epub-sessions')
          .list()
          .toList(),
      isEmpty,
    );
    expect(files.reads, files.closed);
  });
  test('locking or invalidating access retires sessions and blocks chapter/resource ports immediately', () async {
    await boot();
    await deps!.access!.acknowledge();
    final book = await importBook(rating: RatingLevel.restricted),
        session = await deps!.epub!.open(book, job());
    await deps!.access!.setDiscovery(false);
    expect((await deps!.epub!.chapter(session, 0, job())).blocks, isNotEmpty);
    await deps!.access!.lock();
    await expectLater(
      deps!.epub!.chapter(session, 0, job()),
      throwsA(isA<AppFailure>()),
    );
    await expectLater(
      deps!.epub!.resource(session, session.spine.first.resource, job()),
      throwsA(isA<AppFailure>()),
    );
    await deps!.access!.unlock();
    await expectLater(
      deps!.epub!.resource(session, session.spine.first.resource, job()),
      throwsA(isA<EpubFailure>()),
    );
    final fresh = await deps!.epub!.open(book, job());
    deps!.access!.invalidateProtected();
    await expectLater(
      deps!.epub!.chapter(fresh, 0, job()),
      throwsA(isA<EpubFailure>()),
    );
  });
  test('cancelling a build clears session files and leaves no parsed revision or position', () async {
    await boot();
    final book = await importBook();
    var current = true;
    await expectLater(
      deps!.epub!.open(
        book,
        JobContext(
          id: 1,
          isCurrent: () => current,
          report: (_) => current = false,
        ),
      ),
      throwsA(isA<JobCancelled>()),
    );
    expect(
      await Directory('${dir.path}/support/novel/epub-sessions')
          .list()
          .toList(),
      isEmpty,
    );
    expect(
      await (deps!.library as LocalLibrary).database.query(
        "SELECT * FROM documents WHERE parser_version=?",
        [epubParser],
      ),
      isEmpty,
    );
    final retry = await deps!.epub!.open(book, job());
    expect(retry.spine.length, 2);
  });
  test('unknown resources, changed session bytes, forged session and closed sessions never return data', () async {
    await boot();
    final book = await importBook(),
        session = await deps!.epub!.open(book, job());
    for (final name in ['../r0', 'r9999', 'file:///private', 'r0?secret']) {
      await expectLater(
        deps!.epub!.resource(session, name, job()),
        throwsA(isA<EpubFailure>()),
      );
    }
    final root = '${dir.path}/support/novel/epub-sessions/${session.id}';
    await File('$root/${session.spine.first.resource}')
        .writeAsString('changed');
    await expectLater(
      deps!.epub!.resource(session, session.spine.first.resource, job()),
      throwsA(isA<EpubFailure>()),
    );
    await File('$root/c0.json').writeAsString('{}');
    await expectLater(
      deps!.epub!.chapter(session, 0, job()),
      throwsA(isA<EpubFailure>()),
    );
    await deps!.epub!.close(session.id);
    await expectLater(
      deps!.epub!.chapter(session, 0, job()),
      throwsA(isA<EpubFailure>()),
    );
  });
  test('failed parsed-document transaction keeps imported original and allows clean retry', () async {
    await boot();
    final book = await importBook(),
        db = (deps!.library as LocalLibrary).database;
    await db.transaction([
      const SqlCommand(
        "CREATE TRIGGER fail_epub BEFORE INSERT ON documents WHEN NEW.parser_version='epub-v1' BEGIN SELECT RAISE(ABORT,'test'); END",
      ),
    ]);
    await expectLater(deps!.epub!.open(book, job()), throwsA(anything));
    expect(
      await db.query("SELECT * FROM documents WHERE parser_version='epub-v1'"),
      isEmpty,
    );
    expect(
      await Directory('${dir.path}/support/novel/epub-sessions')
          .list()
          .toList(),
      isEmpty,
    );
    await deps!.importer!.verify(book, job());
    await db.transaction([const SqlCommand('DROP TRIGGER fail_epub')]);
    expect((await deps!.epub!.open(book, job())).spine.length, 2);
  });
}
