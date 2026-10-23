import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/app/dependencies.dart';
import 'package:novel_app/domain/access.dart';
import 'package:novel_app/domain/importing.dart';
import 'package:novel_app/domain/documents.dart';
import 'package:novel_app/domain/jobs.dart';
import 'package:novel_app/domain/txt.dart';
import 'package:novel_app/infrastructure/txt/decoder.dart';
import 'package:novel_app/infrastructure/storage/local_library.dart';
import 'package:reader_storage/reader_storage.dart';
import 'package:reader_core/reader_core.dart';
import 'package:novel_app/infrastructure/storage/schema.dart';

import 'access_test.dart' show Locations;
import 'import_test.dart' show ImportFiles, job;

void main() {
  test('stream scalar mapping survives every byte boundary, BOM, CRLF, CR, combining and emoji', () {
    const original = '甲\r\n繁體📖e\u0301\r乙\n';
    final encodings = <String, List<int>>{
      'utf8': [239, 187, 191, ...utf8.encode(original)],
      'utf16le': [
        255,
        254,
        ...original.codeUnits.expand((u) => [u & 255, u >> 8]),
      ],
      'utf16be': [
        254,
        255,
        ...original.codeUnits.expand((u) => [u >> 8, u & 255]),
      ],
    };
    for (final entry in encodings.entries) {
      final decoder = TxtDecoder(entry.key), lines = Newlines();
      final values = <Scalar>[];
      for (final byte in entry.value) {
        values.addAll(lines.add(decoder.add([byte])));
      }
      values.addAll(lines.add(decoder.add([], last: true), last: true));
      expect(
        String.fromCharCodes(values.map((s) => s.value)),
        original.replaceAll('\r\n', '\n').replaceAll('\r', '\n'),
      );
      expect(values.first.start, entry.key == 'utf8' ? 3 : 2);
      expect(values.last.end, entry.value.length);
      expect(values[1].end - values[1].start, entry.key == 'utf8' ? 2 : 4);
    }
    for (final encoding in ['utf8', 'utf16le', 'utf16be']) {
      expect(
        () => TxtDecoder(encoding).add([0xff], last: true),
        throwsFormatException,
      );
    }
  });
  test(
    'legacy chunks roundtrip with system codec and correct raw ranges',
    () async {
      if (!Platform.isMacOS) return;
      for (final pair in [('gb18030', 'GB18030.txt'), ('big5', 'Big5.txt')]) {
        final raw = await File('../../fixtures/novel/mac04/${pair.$2}')
            .readAsBytes();
        final decoder = TxtDecoder(pair.$1), out = <Scalar>[];
        for (final byte in raw) {
          out.addAll(decoder.add([byte]));
        }
        out.addAll(decoder.add([], last: true));
        final text = String.fromCharCodes(out.map((s) => s.value));
        expect(text, contains(pair.$1 == 'big5' ? '這是自產' : '这是自产'));
        if (pair.$1 == 'gb18030') expect(text, contains('📖'));
        expect(out.last.end, raw.length);
      }
    },
  );
  test('schema5 imported original and policy survive schema6 migration without automatic parsing', () async {
    final dir = await Directory.systemTemp.createTemp('mac05-upgrade-');
    final files = ImportFiles();
    AppDependencies? deps;
    final root = '${dir.path}/support/novel';
    final db = await StorageDatabase.open(
      directory: root,
      product: ReaderProduct.novel,
      migrations: novelSchema.take(5).toList(),
    );
    final bytes = utf8.encode('第一章旧版本\n保留导入原件与分级。\n');
    final digest = await ContentFiles(root).put(bytes);
    try {
      await db.transaction([
        const SqlCommand(
          "INSERT INTO books(id,title,language,rating,created_at,updated_at) VALUES('legacy','旧导入','zh','general',1,1)",
        ),
        SqlCommand(
          "INSERT INTO documents VALUES('legacy-source','legacy',?,'txt','text/plain',?,'import-v1',1)",
          [digest, bytes.length],
        ),
        const SqlCommand(
          "INSERT INTO content_policy(book_id,level,policy_version,source_access) VALUES('legacy','general','owned','notRequired')",
        ),
        const SqlCommand(
          "INSERT INTO imports VALUES('legacy-source','managed',NULL,'utf8','awaiting_parser')",
        ),
      ]);
      await db.close();
      deps = await AppDependencies.open(Locations(dir.path), documents: files);
      expect(
        (deps.library as LocalLibrary).database.info['version'],
        novelSchema.last.version,
      );
      expect((await deps.library.load(job())).value.single.title, '旧导入');
      expect(await deps.txt!.open('legacy', job()), isNull);
      final candidate = await deps.txt!.preview(
        'legacy',
        const TxtRules(),
        job(),
      );
      await deps.txt!.apply(candidate.id, job());
      expect(
        (await deps.txt!.read(
          candidate,
          0,
          job(),
        )).blocks.map((b) => b.text).join(),
        contains('保留导入原件与分级'),
      );
    } finally {
      await db.close();
      await deps?.close?.call();
      await files.incoming.close();
      await dir.delete(recursive: true);
    }
  });
  group('real imported TXT reader', () {
    late Directory dir;
    late ImportFiles files;
    AppDependencies? deps;
    setUp(() async {
      dir = await Directory.systemTemp.createTemp('mac05-');
      files = ImportFiles();
      deps = await AppDependencies.open(Locations(dir.path), documents: files);
    });
    tearDown(() async {
      await deps?.close?.call();
      await files.incoming.close();
      await dir.delete(recursive: true);
    });
    Future<String> add(
      String text, {
      ImportMode mode = ImportMode.managed,
      RatingLevel rating = RatingLevel.general,
    }) async {
      final source = File('${dir.path}/source-${files.paths.length}.txt');
      await source.writeAsString(text);
      final preview = await deps!.importer!.prepare(
        files.add('自产.txt', source.path),
        job(),
      );
      return (await deps!.importer!.commit(
        preview.id,
        mode: mode,
        rating: rating,
        job: job(),
      )).bookId;
    }

    test('preview/explicit apply; repeated headings, preface and afterword; exact body and raw mapping', () async {
      const text = '开篇\r\n序章\r第一章 山路\n甲📖e\u0301\n第一章 山路\n乙\n後記\n完\n';
      final id = await add(text), reader = deps!.txt!;
      expect(await reader.open(id, job()), isNull);
      final candidate = await reader.preview(id, const TxtRules(), job());
      expect(candidate.chapterCount, 5);
      expect(await reader.open(id, job()), isNull);
      final active = await reader.apply(candidate.id, job());
      final chapters = await reader.chapters(active, 0, job());
      expect(chapters.map((c) => c.title), [
        '正文前',
        '序章',
        '第一章 山路',
        '第一章 山路',
        '後記',
      ]);
      final out = StringBuffer();
      for (var block = 0; block < active.blocks;) {
        final page = await reader.read(active, block, job());
        for (final b in page.blocks) {
          out.write(b.text);
          expect(b.sourceOffsets.length, b.text.length + 1);
          if (b.text.contains('📖')) {
            expect(b.sourceOffsets[b.text.indexOf('📖') + 1], -1);
          }
        }
        block = page.blocks.last.ordinal + 1;
      }
      expect(
        out.toString(),
        text.replaceAll('\r\n', '\n').replaceAll('\r', '\n'),
      );
    });
    test('long paragraph is bounded without loss; no-heading book is one chapter; cancellation and restart preserve old index and positions', () async {
      final text = '甲📖e\u0301' * 3000;
      final id = await add(text), reader = deps!.txt!;
      final candidate = await reader.preview(id, const TxtRules(), job());
      final active = await reader.apply(candidate.id, job());
      expect(active.chapterCount, 1);
      final first = await reader.read(active, 0, job());
      expect(first.blocks.every((b) => b.text.length <= 2048), true);
      final anchor = first.anchor(first.blocks.first);
      await deps!.positions!.savePosition(
        id,
        PositionChannel.reading,
        anchor,
        expectedSequence: 0,
      );
      var current = true;
      await expectLater(
        reader.preview(
          id,
          const TxtRules(headings: TxtHeadings.none),
          JobContext(
            id: 2,
            isCurrent: () => current,
            report: (_) => current = false,
          ),
        ),
        throwsA(isA<JobCancelled>()),
      );
      expect((await reader.open(id, job()))!.id, active.id);
      final next = await reader.preview(
        id,
        const TxtRules(headings: TxtHeadings.none),
        job(),
      );
      await reader.apply(next.id, job());
      expect(
        (await deps!.positions!.loadPosition(
          id,
          PositionChannel.reading,
        ))!.anchor.revision,
        active.id,
      );
      await deps!.close!();
      deps = await AppDependencies.open(Locations(dir.path), documents: files);
      expect((await deps!.txt!.open(id, job()))!.id, next.id);
      final all = StringBuffer();
      for (var start = 0; start < next.blocks;) {
        final page = await deps!.txt!.read(next, start, job());
        all.writeAll(page.blocks.map((b) => b.text));
        start = page.blocks.last.ordinal + 1;
      }
      expect(all.toString(), text);
      final db = (deps!.library as LocalLibrary).database;
      expect(await db.query('PRAGMA foreign_key_check'), isEmpty);
    });
    test('failed index commit retains previous directory; corrupt index detected and rebuild is explicit', () async {
      final id = await add('第一章风声\n自产正文。\n第二章灯火\n另一段。\n'), reader = deps!.txt!;
      final first = await reader.preview(id, const TxtRules(), job());
      await reader.apply(first.id, job());
      final second = await reader.preview(
        id,
        const TxtRules(headings: TxtHeadings.none),
        job(),
      );
      final db = (deps!.library as LocalLibrary).database;
      await db.transaction([
        const SqlCommand(
          "CREATE TRIGGER reject_txt BEFORE INSERT ON txt_active BEGIN SELECT RAISE(ABORT,'owned_failure'); END",
        ),
      ]);
      await expectLater(
        reader.apply(second.id, job()),
        throwsA(isA<StorageFailure>()),
      );
      expect((await reader.open(id, job()))!.id, first.id);
      expect(
        await File(
          '${dir.path}/support/novel/txt-stage/${second.id}/blocks.bin',
        ).exists(),
        true,
      );
      await db.transaction([const SqlCommand('DROP TRIGGER reject_txt')]);
      await reader.apply(second.id, job());
      await File(
        '${dir.path}/support/novel/txt-indices/${second.id}/blocks.bin',
      ).writeAsBytes([0]);
      await expectLater(reader.open(id, job()), throwsA(isA<AppFailure>()));
      final repaired = await reader.preview(id, const TxtRules(), job());
      await reader.apply(repaired.id, job());
      expect((await reader.open(id, job()))!.id, repaired.id);
    });
    test('existing index remains readable during background rebuild; cancelled work removes staging', () async {
      final id = await add('第一章山路\n${'自产中文📖，一段长路。\n' * 150000}'),
          reader = deps!.txt!;
      final first = await reader.preview(id, const TxtRules(), job());
      await reader.apply(first.id, job());
      var active = true;
      final building = reader.preview(
        id,
        const TxtRules(headings: TxtHeadings.none),
        job(() => active),
      );
      final cancelled = expectLater(building, throwsA(isA<JobCancelled>()));
      final page = await reader.read(first, 0, job());
      expect(page.blocks.map((b) => b.text).join(), contains('自产中文'));
      active = false;
      await cancelled;
      expect((await reader.open(id, job()))!.id, first.id);
      expect(
        await Directory('${dir.path}/support/novel/txt-stage').list().toList(),
        isEmpty,
      );
    });
    test('reference index stores no body copy; changed original and locked protected routes refuse text', () async {
      final id = await add('第一章 山路\n自产引用正文📖\n', mode: ImportMode.reference);
      final progress = <double>[];
      final reader = deps!.txt!;
      final candidate = await reader.preview(
        id,
        const TxtRules(),
        JobContext(id: 1, isCurrent: () => true, report: progress.add),
      );
      expect(progress.every((p) => p >= 0 && p <= 1), true);
      for (var i = 1; i < progress.length; i++) {
        expect(progress[i], greaterThanOrEqualTo(progress[i - 1]));
      }
      await reader.apply(candidate.id, job());
      final indexFiles = await Directory(
        '${dir.path}/support/novel/txt-indices/${candidate.id}',
      ).list().toList();
      expect(indexFiles.map((f) => f.uri.pathSegments.last).toSet(), {
        'blocks.bin',
        'manifest.json',
      });
      expect(
        (await reader.read(
          candidate,
          0,
          job(),
        )).blocks.map((b) => b.text).join(),
        contains('自产引用正文'),
      );
      await File(files.paths.values.single).writeAsString('第一章 山路\n已经改变正文!!\n');
      await expectLater(reader.open(id, job()), throwsA(isA<ImportFailure>()));
      await expectLater(
        reader.read(candidate, 0, job()),
        throwsA(anyOf(isA<AppFailure>(), isA<ImportFailure>())),
      );
      await deps!.access!.acknowledge();
      final protected = await add(
        '第一章 中性\n仅为中性门禁测试。',
        rating: RatingLevel.restricted,
      );
      final adult = await reader.preview(protected, const TxtRules(), job());
      await reader.apply(adult.id, job());
      await deps!.access!.lock();
      await expectLater(
        reader.read(adult, 0, job()),
        throwsA(isA<AppFailure>()),
      );
      await expectLater(
        reader.chapters(adult, 0, job()),
        throwsA(isA<AppFailure>()),
      );
    });
  });
}
