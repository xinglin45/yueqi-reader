import '../application/jobs.dart';
import '../domain/library.dart';

/// Session only: no disk, network, login, import or persisted reading position.
final class SessionLibrary implements LibraryRepository {
  static const sampleParagraphs = [
    '清晨，山间的雾还没有散。林舟推开木窗，看见昨夜的雨在青石上留下细细的光。远处的钟声越过屋檐，落在安静的小路上。',
    '他把信折好，放进旧书的夹页。今天没有急着出发的理由，只有一段尚未走完的山路，以及山路尽头等着他的朋友。',
    '收好行囊后，林舟沿着村口的小路向上走。石阶被雨水洗过，两侧的草木散发出清新的气息。山风从林间穿过，带来远处溪水的声音，也带来一些陌生而熟悉的记忆。',
  ];
  bool _demoEnabled = false;
  static const sample = BookSummary(
    id: 'demo-mountain-letter',
    title: '山间来信',
    subtitle: '原创演示短篇 · 仅本次会话',
    demo: true,
  );
  @override
  Future<JobResult<List<BookSummary>>> load(JobContext job) async {
    job.checkCancelled();
    final books = _demoEnabled ? [sample] : <BookSummary>[];
    return JobResult(List.unmodifiable(books), empty: books.isEmpty);
  }

  @override
  Future<JobResult<List<BookSummary>>> addDemonstration(JobContext job) async {
    job.checkCancelled();
    _demoEnabled = true;
    return load(job);
  }

  @override
  Future<JobResult<ReadingPreview>> preview(
    String bookId,
    JobContext job,
  ) async {
    job.checkCancelled();
    if (!_demoEnabled || bookId != sample.id) {
      throw const AppFailure(FailureCode.missing);
    }
    return JobResult(
      ReadingPreview(
        book: sample,
        chapter: '第三章　山路微光',
        paragraphs: sampleParagraphs,
      ),
    );
  }
}
