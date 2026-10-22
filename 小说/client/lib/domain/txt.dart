import 'documents.dart';
import 'jobs.dart';

enum TxtHeadings { standard, strict, none }

final class TxtRules {
  const TxtRules({
    this.headings = TxtHeadings.standard,
    this.maxTitle = 80,
    this.prefix = '',
  });
  final TxtHeadings headings;
  final int maxTitle;
  final String prefix;
  Map<String, Object> toJson() => {
    'headings': headings.name,
    'max_title': maxTitle,
    'prefix': prefix,
  };
  factory TxtRules.fromJson(Map<String, dynamic> json) {
    final rules = TxtRules(
      headings: TxtHeadings.values.byName(json['headings'] as String),
      maxTitle: json['max_title'] as int,
      prefix: json['prefix'] as String,
    );
    if (rules.maxTitle < 10 ||
        rules.maxTitle > 120 ||
        rules.prefix.length > 16 ||
        rules.prefix.contains(RegExp(r'[\r\n\x00]'))) {
      throw const FormatException('txt_rules');
    }
    return rules;
  }
}

final class TxtChapter {
  const TxtChapter(this.ordinal, this.title, this.first, this.end);
  final int ordinal, first, end;
  final String title;
  String get id => 'c$ordinal';
}

final class TxtIndex {
  const TxtIndex({
    this.title = '本地 TXT',
    this.protected = false,
    required this.id,
    required this.bookId,
    required this.encoding,
    required this.rules,
    required this.blocks,
    required this.units,
    required this.chapterCount,
    this.preview = const [],
  });
  final String id, bookId, encoding;
  final String title;
  final bool protected;
  final TxtRules rules;
  final int blocks, units, chapterCount;

  /// A bounded directory preview, never all chapter contents.
  final List<TxtChapter> preview;
}

final class TxtBlock {
  const TxtBlock(
    this.ordinal,
    this.text,
    this.normalizedStart,
    this.sourceStart,
    this.sourceEnd,
    this.paragraph,
    this.continuation,
    this.sourceOffsets,
  );
  final int ordinal, normalizedStart, sourceStart, sourceEnd, paragraph;
  final bool continuation;
  final String text;

  /// UTF-16 boundaries to original byte offsets; -1 marks half a surrogate pair.
  final List<int> sourceOffsets;
  String get id => 'b$ordinal';
}

final class TxtPage {
  const TxtPage(this.index, this.chapter, this.blocks);
  final TxtIndex index;
  final TxtChapter chapter;
  final List<TxtBlock> blocks;
  DocumentAnchor anchor(TxtBlock block) => DocumentAnchor.capture(
    kind: DocumentKind.txt,
    revision: index.id,
    chapterId: chapter.id,
    spineHref: 'text.txt',
    blockId: block.id,
    text: block.text,
    start: 0,
    end: 0,
  );
}

abstract interface class TxtDocumentReader {
  Future<bool> accepts(String bookId);
  Future<TxtIndex?> open(String bookId, JobContext job);
  Future<TxtIndex> preview(String bookId, TxtRules rules, JobContext job);
  Future<TxtIndex> apply(String candidateId, JobContext job);
  Future<void> discard(String candidateId);
  Future<List<TxtChapter>> chapters(TxtIndex index, int offset, JobContext job);
  Future<TxtPage> read(TxtIndex index, int firstBlock, JobContext job);
}
