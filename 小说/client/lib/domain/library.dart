import 'jobs.dart';

final class BookSummary {
  const BookSummary({
    required this.id,
    required this.title,
    required this.subtitle,
    this.demo = false,
    this.persistent = false,
  });
  final String id;
  final String title;
  final String subtitle;
  final bool demo;
  final bool persistent;
}

/// Temporary presentation content, deliberately not a DocumentReader engine.
final class ReadingPreview {
  ReadingPreview({
    required this.book,
    required this.chapter,
    required List<String> paragraphs,
    this.documentRevision,
    this.chapterId,
    this.spineHref,
    this.blockIds = const [],
    this.restoredBlockId,
    this.positionSequence = 0,
    this.positionNeedsReview = false,
  }) : paragraphs = List.unmodifiable(paragraphs);
  final BookSummary book;
  final String chapter;
  final List<String> paragraphs;
  final String? documentRevision, chapterId, spineHref, restoredBlockId;
  final List<String> blockIds;
  final int positionSequence;
  final bool positionNeedsReview;
}

abstract interface class LibraryRepository {
  Future<JobResult<List<BookSummary>>> load(JobContext job);
  Future<JobResult<List<BookSummary>>> addDemonstration(JobContext job);
  Future<JobResult<ReadingPreview>> preview(String bookId, JobContext job);
}
