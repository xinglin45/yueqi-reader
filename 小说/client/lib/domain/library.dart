import 'jobs.dart';

final class BookSummary {
  const BookSummary({
    required this.id,
    required this.title,
    required this.subtitle,
    this.demo = false,
  });
  final String id;
  final String title;
  final String subtitle;
  final bool demo;
}

/// Temporary presentation content, deliberately not a DocumentReader engine.
final class ReadingPreview {
  ReadingPreview({
    required this.book,
    required this.chapter,
    required List<String> paragraphs,
  }) : paragraphs = List.unmodifiable(paragraphs);
  final BookSummary book;
  final String chapter;
  final List<String> paragraphs;
}

abstract interface class LibraryRepository {
  Future<JobResult<List<BookSummary>>> load(JobContext job);
  Future<JobResult<List<BookSummary>>> addDemonstration(JobContext job);
  Future<JobResult<ReadingPreview>> preview(String bookId, JobContext job);
}
