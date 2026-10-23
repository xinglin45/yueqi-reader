import 'package:platform_services/platform_services.dart';

import 'access.dart';
import 'jobs.dart';

enum ImportMode { managed, reference }

enum TextEncoding { auto, utf8, utf16le, utf16be, gb18030, big5 }

enum ImportIssue {
  unsupported,
  tooLarge,
  encoding,
  corrupt,
  permission,
  missing,
  changed,
  disk,
  cancelled,
  classification,
  recovery,
}

final class ImportFailure implements Exception {
  const ImportFailure(this.issue);
  final ImportIssue issue;
}

final class ImportPreview {
  const ImportPreview({
    required this.id,
    required this.grant,
    required this.kind,
    required this.bytes,
    required this.title,
    required this.digest,
    this.encoding,
    this.excerpt = '',
    this.issue,
  });
  final String id, kind, title, digest, excerpt;
  final int bytes;
  final FileGrant grant;
  final TextEncoding? encoding;
  final ImportIssue? issue;
}

final class ImportReceipt {
  const ImportReceipt(
    this.bookId, {
    required this.duplicate,
    this.repaired = false,
  });
  final String bookId;
  final bool duplicate, repaired;
}

final class ImportedFileStatus {
  const ImportedFileStatus(this.mode, this.bytes, this.encoding);
  final ImportMode mode;
  final int bytes;
  final String? encoding;
}

abstract interface class DocumentImporter {
  Future<ImportPreview> prepare(FileGrant grant, JobContext job);
  Future<ImportPreview> inspect(
    String id,
    TextEncoding encoding,
    JobContext job,
  );
  Future<ImportReceipt> commit(
    String id, {
    required ImportMode mode,
    required RatingLevel rating,
    required JobContext job,
  });
  Future<void> discard(String id);
  Future<ImportedFileStatus> information(String bookId);
  Future<ImportedFileStatus> verify(String bookId, JobContext job);
  Future<void> relink(String bookId, FileGrant grant, JobContext job);
}
