import 'documents.dart';

enum PermissionState { unknown, allowed, denied }

enum ContentClass { general, adult, unknown, prohibited }

final class DocumentRevision {
  const DocumentRevision({
    required this.id,
    required this.bookId,
    required this.digest,
    required this.kind,
    required this.byteLength,
    required this.parserVersion,
  });
  final String id, bookId, digest, parserVersion;
  final DocumentKind kind;
  final int byteLength;
}

final class ChapterRecord {
  const ChapterRecord(
    this.id,
    this.documentId,
    this.ordinal,
    this.title,
    this.spineHref,
  );
  final String id, documentId, title, spineHref;
  final int ordinal;
}

final class ResourceRecord {
  const ResourceRecord(
    this.documentId,
    this.href,
    this.digest,
    this.mediaType,
    this.byteLength, {
    this.cachePermission = PermissionState.unknown,
  });
  final String documentId, href, digest, mediaType;
  final int byteLength;
  final PermissionState cachePermission;
}

final class AnnotationRecord {
  const AnnotationRecord(
    this.id,
    this.bookId,
    this.anchor,
    this.kind,
    this.note, {
    this.rowRevision = 1,
    this.deleted = false,
  });
  final String id, bookId, kind, note;
  final DocumentAnchor anchor;
  final int rowRevision;
  final bool deleted;
}

final class CollectionRecord {
  const CollectionRecord(
    this.id,
    this.label,
    this.kind, {
    this.rowRevision = 1,
    this.deleted = false,
  });
  final String id, label, kind;
  final int rowRevision;
  final bool deleted;
}

final class SourceBinding {
  const SourceBinding(
    this.id,
    this.bookId,
    this.sourceId,
    this.sourceItemId, {
    this.verification = 'unknown',
    this.cachePermission = PermissionState.unknown,
  });
  final String id, bookId, sourceId, sourceItemId, verification;
  final PermissionState cachePermission;
}

final class StoredJob {
  const StoredJob(
    this.id,
    this.kind,
    this.state, {
    this.bookId,
    this.progress,
    this.errorCode,
  });
  final String id, kind, state;
  final String? bookId, errorCode;
  final double? progress;
}
