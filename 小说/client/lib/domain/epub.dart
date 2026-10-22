import 'dart:typed_data';

import 'documents.dart';
import 'jobs.dart';

enum EpubIssue {
  corrupt,
  unsupported,
  encrypted,
  fixedLayout,
  missingResource,
  limit,
  expired,
}

final class EpubFailure implements Exception {
  const EpubFailure(this.issue);
  final EpubIssue issue;
}

String epubHelp(EpubIssue issue) => switch (issue) {
  EpubIssue.corrupt => 'EPUB 结构或资源已损坏，原书与旧位置保留。',
  EpubIssue.unsupported =>
    '此 EPUB 含暂不支持的格式或资源。当前支持 EPUB 2/3 的 UTF-8 流式 XHTML、受限 CSS、PNG/JPEG 与普通字体。',
  EpubIssue.encrypted => '此 EPUB 含加密或字体混淆标记，当前不支持；不会尝试解密。',
  EpubIssue.fixedLayout => '此 EPUB 使用固定版式，当前阅读器尚不支持。',
  EpubIssue.missingResource => 'EPUB 引用了缺失的书内资源或片段，请检查原书。',
  EpubIssue.limit => 'EPUB 超出本次安全预算，未打开正文；原记录保留。',
  EpubIssue.expired => '阅读会话已关闭，请重新打开书籍。',
};

final class EpubSpine {
  const EpubSpine(
    this.ordinal,
    this.href,
    this.resource,
    this.title,
    this.images,
  );
  final int ordinal;
  final String href, resource, title;
  final List<String> images;
  String get id => 'c$ordinal';
}

final class EpubToc {
  const EpubToc(this.title, this.spine, this.fragment, this.depth);
  final String title, fragment;
  final int spine, depth;
}

final class EpubSession {
  const EpubSession({
    required this.id,
    required this.revision,
    required this.bookId,
    required this.title,
    required this.protected,
    required this.spine,
    required this.toc,
    required this.warnings,
  });
  final String id, revision, bookId, title;
  final bool protected;
  final List<EpubSpine> spine;
  final List<EpubToc> toc;
  final List<String> warnings;
}

final class EpubChapter {
  const EpubChapter(this.session, this.spine, this.blocks, this.fragments);
  final EpubSession session;
  final EpubSpine spine;
  final Map<String, String> blocks, fragments;
  DocumentAnchor anchor(String block, int start, int end) =>
      DocumentAnchor.capture(
        kind: DocumentKind.epub,
        revision: session.revision,
        chapterId: spine.id,
        spineHref: spine.href,
        blockId: block,
        text: blocks[block]!,
        start: start,
        end: end,
      );
}

final class EpubResource {
  const EpubResource(this.mime, this.bytes);
  final String mime;
  final Uint8List bytes;
}

/// Renderers receive opaque session/resource IDs, never filesystem paths.
abstract interface class EpubDocumentReader {
  Future<bool> accepts(String bookId);
  Future<EpubSession> open(String bookId, JobContext job);
  Future<EpubChapter> chapter(EpubSession session, int ordinal, JobContext job);
  Future<EpubResource> resource(EpubSession session, String id, JobContext job);
  Future<void> close(String sessionId);
}

/// Validate host-renderer messages against canonical text, including every
/// segment of a cross-inline/cross-block selection. Never trust a bridge quote.
List<DocumentAnchor> epubSelection(EpubChapter chapter, Object? message) {
  if (message is! Map ||
      message['session'] != chapter.session.id ||
      message['resource'] != chapter.spine.resource ||
      message['segments'] is! List) {
    throw const FormatException('epub_bridge_identity');
  }
  final segments = message['segments'] as List;
  if (segments.isEmpty || segments.length > 32) {
    throw const FormatException('epub_selection_limit');
  }
  var total = 0, previous = -1;
  final keys = chapter.blocks.keys.toList();
  return [
    for (final item in segments)
      (() {
        if (item is! Map || item['block'] is! String) {
          throw const FormatException('epub_bridge_segment');
        }
        final block = item['block'] as String, text = chapter.blocks[block];
        final ordinal = keys.indexOf(block);
        if (text == null || ordinal <= previous) {
          throw const FormatException('epub_bridge_block');
        }
        previous = ordinal;
        final start = bridgeInteger(item['start']),
            end = bridgeInteger(item['end']);
        if (!utf16Boundary(text, start) ||
            !utf16Boundary(text, end) ||
            end < start ||
            item['exact'] != text.substring(start, end) ||
            (total += end - start) > 2048) {
          throw const FormatException('epub_bridge_range');
        }
        return chapter.anchor(block, start, end);
      })(),
  ];
}
