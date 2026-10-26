import 'dart:io';

import 'package:novel_app/infrastructure/storage/schema.dart';
import 'package:reader_storage/reader_storage.dart';
import 'package:reader_core/reader_core.dart';

Future<void> main() async {
  final dir = await Directory.systemTemp.createTemp('mac09-schema-');
  final db = await StorageDatabase.open(
    directory: dir.path,
    product: ReaderProduct.novel,
    migrations: novelSchema,
  );
  try {
    final rows = await db.query(
      "SELECT sql FROM sqlite_master WHERE sql IS NOT NULL AND name NOT LIKE 'sqlite_%' ORDER BY type,name",
    );
    stdout.writeln(
      '-- MAC-09 actual SQLite schema v8, 2026-10-26. No user records.',
    );
    for (final row in rows) {
      stdout.writeln('${row['sql']};');
    }
  } finally {
    await db.close();
    await dir.delete(recursive: true);
  }
}
