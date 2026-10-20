import 'dart:convert';

import 'package:crypto/crypto.dart';

enum DocumentKind { txt, epub }

enum PositionChannel { reading, listening }

enum AnchorMatch { exact, context, chapterStart, unresolved }

bool utf16Boundary(String text, int offset) =>
    offset >= 0 &&
    offset <= text.length &&
    !(offset > 0 &&
        offset < text.length &&
        text.codeUnitAt(offset - 1) >= 0xd800 &&
        text.codeUnitAt(offset - 1) <= 0xdbff &&
        text.codeUnitAt(offset) >= 0xdc00 &&
        text.codeUnitAt(offset) <= 0xdfff);

int scalarToUtf16(String text, int scalarOffset) {
  if (scalarOffset < 0 || scalarOffset > text.runes.length) {
    throw const FormatException('scalar_offset');
  }
  return String.fromCharCodes(text.runes.take(scalarOffset)).length;
}

int utf16ToScalar(String text, int offset) {
  if (!utf16Boundary(text, offset)) throw const FormatException('utf16_offset');
  return text.substring(0, offset).runes.length;
}

int bridgeInteger(Object? value) {
  if (value is! num ||
      !value.isFinite ||
      value < 0 ||
      value > 0x1fffffffffffff ||
      value != value.truncateToDouble()) {
    throw const FormatException('integer_required');
  }
  return value.toInt();
}

String _hash(String prefix, String exact, String suffix) =>
    sha256.convert(utf8.encode(jsonEncode([prefix, exact, suffix]))).toString();

/// No screen coordinates or paths. TXT block IDs come from the parser revision;
/// EPUB uses normalized manifest spine href + stable block ID from MAC-06.
final class DocumentAnchor {
  const DocumentAnchor._(
    this.kind,
    this.revision,
    this.chapterId,
    this.spineHref,
    this.blockId,
    this.start,
    this.end,
    this.exact,
    this.prefix,
    this.suffix,
    this.fingerprint,
  );
  final DocumentKind kind;
  final String revision, chapterId, spineHref, blockId;
  final int start, end;
  final String exact, prefix, suffix, fingerprint;

  factory DocumentAnchor.capture({
    required DocumentKind kind,
    required String revision,
    required String chapterId,
    required String spineHref,
    required String blockId,
    required String text,
    required int start,
    required int end,
  }) {
    if (revision.isEmpty ||
        chapterId.isEmpty ||
        spineHref.isEmpty ||
        blockId.isEmpty ||
        !utf16Boundary(text, start) ||
        !utf16Boundary(text, end) ||
        end < start ||
        end - start > 512) {
      throw const FormatException('anchor_range_or_identity');
    }
    final before = String.fromCharCodes(
      text
          .substring(0, start)
          .runes
          .toList()
          .reversed
          .take(16)
          .toList()
          .reversed,
    );
    final after = String.fromCharCodes(text.substring(end).runes.take(16));
    final exact = text.substring(start, end);
    return DocumentAnchor._(
      kind,
      revision,
      chapterId,
      spineHref,
      blockId,
      start,
      end,
      exact,
      before,
      after,
      _hash(before, exact, after),
    );
  }
  Map<String, Object> toJson() => {
    'schema_version': 1,
    'document_kind': kind.name,
    'content_revision': revision,
    'chapter_id': chapterId,
    'spine_href': spineHref,
    'block_id': blockId,
    'offset_unit': 'utf16_code_unit',
    'start': start,
    'end': end,
    'exact': exact,
    'prefix': prefix,
    'suffix': suffix,
    'context_sha256': fingerprint,
  };
  factory DocumentAnchor.fromJson(Map<String, dynamic> value) {
    if (value['schema_version'] != 1 ||
        value['offset_unit'] != 'utf16_code_unit') {
      throw const FormatException('anchor_version_or_unit');
    }
    String field(String key) {
      final v = value[key];
      if (v is! String || v.length > 1024) {
        throw const FormatException('anchor_field');
      }
      return v;
    }

    final kind = DocumentKind.values
        .where((k) => k.name == value['document_kind'])
        .firstOrNull;
    final revision = field('content_revision'),
        chapter = field('chapter_id'),
        spine = field('spine_href'),
        block = field('block_id');
    final start = bridgeInteger(value['start']),
        end = bridgeInteger(value['end']);
    final exact = field('exact'),
        prefix = field('prefix'),
        suffix = field('suffix'),
        fingerprint = field('context_sha256');
    if (kind == null ||
        [revision, chapter, spine, block].any((s) => s.isEmpty) ||
        end < start ||
        end - start != exact.length ||
        exact.length > 512 ||
        prefix.runes.length > 16 ||
        suffix.runes.length > 16 ||
        fingerprint != _hash(prefix, exact, suffix)) {
      throw const FormatException('anchor_invalid');
    }
    return DocumentAnchor._(
      kind,
      revision,
      chapter,
      spine,
      block,
      start,
      end,
      exact,
      prefix,
      suffix,
      fingerprint,
    );
  }
  AnchorResolution resolve({
    required String currentRevision,
    required String currentChapter,
    required String currentSpine,
    required Map<String, String> blocks,
  }) {
    AnchorResolution fallback() => AnchorResolution(
      currentChapter == chapterId && currentSpine == spineHref
          ? AnchorMatch.chapterStart
          : AnchorMatch.unresolved,
      this,
      null,
    );
    if (currentRevision != revision ||
        currentChapter != chapterId ||
        currentSpine != spineHref) {
      return fallback();
    }
    final text = blocks[blockId];
    if (text == null) return fallback();
    bool matches(int index) =>
        utf16Boundary(text, index) &&
        utf16Boundary(text, index + exact.length) &&
        index + exact.length <= text.length &&
        text.substring(index, index + exact.length) == exact &&
        text.substring(0, index).endsWith(prefix) &&
        text.substring(index + exact.length).startsWith(suffix);
    if (matches(start)) return AnchorResolution(AnchorMatch.exact, this, this);
    // Only a unique context match inside the same block/revision is a candidate.
    if (exact.isEmpty) return fallback();
    final candidates = <int>[];
    var offset = 0;
    while (offset <= text.length) {
      final index = text.indexOf(exact, offset);
      if (index < 0) break;
      if (matches(index)) candidates.add(index);
      offset = index + 1;
    }
    if (candidates.length != 1) return fallback();
    final candidate = DocumentAnchor.capture(
      kind: kind,
      revision: revision,
      chapterId: chapterId,
      spineHref: spineHref,
      blockId: blockId,
      text: text,
      start: candidates.single,
      end: candidates.single + exact.length,
    );
    return AnchorResolution(AnchorMatch.context, this, candidate);
  }
}

final class AnchorResolution {
  const AnchorResolution(this.match, this.original, this.candidate);
  final AnchorMatch match;
  final DocumentAnchor original;

  /// Context matches require explicit acceptance; fallback never overwrites storage.
  final DocumentAnchor? candidate;
}

final class StoredPosition {
  const StoredPosition(this.bookId, this.channel, this.anchor, this.sequence);
  final String bookId;
  final PositionChannel channel;
  final DocumentAnchor anchor;
  final int sequence;
}

abstract interface class PositionRepository {
  Future<StoredPosition?> loadPosition(String bookId, PositionChannel channel);
  Future<StoredPosition> savePosition(
    String bookId,
    PositionChannel channel,
    DocumentAnchor anchor, {
    required int expectedSequence,
  });
}
