import 'dart:io';

import 'package:novel_app/infrastructure/storage/local_library.dart';
import 'package:reader_storage/reader_storage.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/app/dependencies.dart';
import 'package:novel_app/domain/documents.dart';
import 'package:novel_app/domain/access.dart';
import 'package:novel_app/domain/importing.dart';
import 'package:novel_app/domain/txt.dart';
import 'package:novel_app/domain/reading.dart';

import 'access_test.dart' show Locations;
import 'import_test.dart' show ImportFiles, job;

void main() {
  test('SQLite default and per-book preferences, automatic UTF16 anchor and independent listening survive close/reopen', () async {
    final dir = await Directory.systemTemp.createTemp('mac09-storage-'),
        files = ImportFiles();
    AppDependencies? deps;
    try {
      deps = await AppDependencies.open(Locations(dir.path), documents: files);
      final file = files.add('排版.txt', '../../fixtures/novel/mac09/山路排版.txt');
      final prepared = await deps.importer!.prepare(file, job());
      final book = await deps.importer!.commit(
        prepared.id,
        mode: ImportMode.managed,
        rating: RatingLevel.general,
        job: job(),
      );
      final index = await deps.txt!.apply(
        (await deps.txt!.preview(book.bookId, const TxtRules(), job())).id,
        job(),
      );
      final page = await deps.txt!.read(index, 30, job()),
          block = page.blocks.first;
      final at = block.text.indexOf('📖') + 2;
      final anchor = DocumentAnchor.capture(
        kind: DocumentKind.txt,
        revision: index.id,
        chapterId: page.chapter.id,
        spineHref: 'text.txt',
        blockId: block.id,
        text: block.text,
        start: at,
        end: at,
      );
      final session = await deps.reading!.open(
        ReadingIdentity(book.bookId, index.id, DocumentKind.txt),
        isCurrent: () => true,
      );
      await session.setPreferences(
        const ReadingPreferences(font: ReadingFont.sans, size: 26),
        global: true,
      );
      await session.setPreferences(
        const ReadingPreferences(
          layout: ReadingLayout.columns,
          size: 30,
          margin: 32,
          theme: ReadingTheme.green,
        ),
      );
      session.observe(anchor);
      await deps.positions!.savePosition(
        book.bookId,
        PositionChannel.listening,
        page.anchor(page.blocks[1]),
        expectedSequence: 0,
      );
      await deps.close!.call();
      deps = null;
      deps = await AppDependencies.open(Locations(dir.path), documents: files);
      final restored = await deps.reading!.open(
        ReadingIdentity(book.bookId, index.id, DocumentKind.txt),
        isCurrent: () => true,
      );
      expect(restored.anchor!.toJson(), anchor.toJson());
      expect(restored.sequence, 1);
      expect(restored.preferences.layout, ReadingLayout.columns);
      expect(restored.preferences.size, 30);
      expect(restored.overridden, isTrue);
      expect(
        (await deps.positions!.loadPosition(
          book.bookId,
          PositionChannel.listening,
        ))!.anchor.blockId,
        page.blocks[1].id,
      );
      await restored.setPreferences(restored.preferences, reset: true);
      expect(restored.preferences.size, 26);
      expect(restored.preferences.font, ReadingFont.sans);
      expect(restored.overridden, isFalse);
      final db = (deps.library as LocalLibrary).database;
      await db.transaction([
        const SqlCommand(
          "UPDATE reading_preferences SET value='[]' WHERE scope='*'",
        ),
      ]);
      final fallback = await deps.reading!.open(
        ReadingIdentity(book.bookId, index.id, DocumentKind.txt),
        isCurrent: () => true,
      );
      expect(fallback.preferences.size, 24);
      expect(fallback.error, contains('偏好损坏'));
      expect(
        (await deps.txt!.read(index, 30, job())).blocks.first.text,
        block.text,
      );
    } finally {
      await deps?.close?.call();
      await files.incoming.close();
      await dir.delete(recursive: true);
    }
  });
}
