import 'dart:convert';
import 'dart:io';

import 'package:novel_app/domain/documents.dart';
import 'package:novel_app/domain/jobs.dart';
import 'package:novel_app/infrastructure/storage/local_library.dart';
import 'package:novel_app/infrastructure/storage/schema.dart';
import 'package:reader_core/reader_core.dart';
import 'package:reader_storage/reader_storage.dart';

/// Run write and verify as separate OS processes. Only owned fixture data.
Future<void> main(List<String> args) async {
  if (args.length != 2 ||
      !['write', 'write-crash', 'verify'].contains(args[0])) {
    throw ArgumentError(
      'Expected write|verify and an isolated probe directory',
    );
  }
  final database = await StorageDatabase.open(
    directory: args[1],
    product: ReaderProduct.novel,
    migrations: novelSchema,
  );
  try {
    final library = LocalLibrary(database, ContentFiles(args[1]));
    final job = JobContext(id: 1, isCurrent: () => true, report: (_) {});
    if (args[0] != 'verify') {
      final book = (await library.addDemonstration(job)).value.single;
      final preview = (await library.preview(book.id, job)).value;
      final previous = await library.loadPosition(
        book.id,
        PositionChannel.reading,
      );
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
        book.id,
        PositionChannel.reading,
        anchor,
        expectedSequence: previous?.sequence ?? 0,
      );
      await library.saveSetting('theme', 'dark');
    }
    final book = (await library.load(job)).value.single;
    final preview = (await library.preview(book.id, job)).value;
    final position = await library.loadPosition(
      book.id,
      PositionChannel.reading,
    );
    if (preview.restoredBlockId != 'p1' ||
        await library.loadSetting('theme') != 'dark') {
      throw StateError('restart verification failed');
    }
    await database.transaction([
      const SqlCommand(
        "CREATE VIRTUAL TABLE temp.tri USING fts5(body,tokenize='trigram case_sensitive 1')",
      ),
      const SqlCommand(
        "CREATE VIRTUAL TABLE temp.uni USING fts5(body,tokenize='unicode61 remove_diacritics 0')",
      ),
      const SqlCommand('INSERT INTO temp.tri VALUES(?)', [
        '山间来信，山間來信，📖 e\u0301，100%_',
      ]),
      const SqlCommand('INSERT INTO temp.uni SELECT * FROM temp.tri'),
    ]);
    final checks = <Map<String, Object?>>[];
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
      final matches = await database.query(
        'SELECT body FROM temp.tri WHERE instr(body,?)>0',
        [query],
      );
      final fts = await database.query(
        'SELECT body FROM temp.tri WHERE tri MATCH ?',
        ['"${query.replaceAll('"', '""')}"'],
      );
      final uni = await database.query(
        'SELECT body FROM temp.uni WHERE uni MATCH ?',
        ['"${query.replaceAll('"', '""')}"'],
      );
      checks.add({
        'query': query,
        'literal_hits': matches.length,
        'trigram_hits': fts.length,
        'unicode61_hits': uni.length,
        'strategy': query.runes.length < 3
            ? 'substring'
            : 'trigram_then_verify',
      });
    }
    final schema = await database.query(
      "SELECT name,sql FROM sqlite_master WHERE type IN ('table','index') AND sql IS NOT NULL AND name NOT LIKE 'sqlite_%' ORDER BY type DESC,name",
    );
    final output = <String, Object?>{
      'date': '2026-10-20',
      'phase': args[0],
      'process_id': pid,
      'worker': database.info,
      'book_id': book.id,
      'reading_block': preview.restoredBlockId,
      'reading_sequence': position?.sequence,
      'paragraphs': preview.paragraphs.length,
      'theme': await library.loadSetting('theme'),
      'document_count': (await database.query('SELECT id FROM documents'))
          .length,
      'search_checks': checks,
      'schema': schema,
      'source_counts': {'normal': 0, 'adult': 0},
    };
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(output));
    await stdout.flush();
    if (args[0] == 'write-crash') {
      exit(0);
    } // Deliberately skip SQLite close/checkpoint.
  } finally {
    await database.close();
  }
}
