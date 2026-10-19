/// MAC-06 research contract. It is not a persisted MAC-03 reading position.
final class ProbeAnchor {
  const ProbeAnchor({
    required this.revision,
    required this.spineHref,
    required this.blockId,
    required this.startUtf16,
    required this.endUtf16,
    required this.exact,
  });
  final String revision;
  final String spineHref;
  final String blockId;
  final int startUtf16;
  final int endUtf16;
  final String exact;
  Map<String, Object> toJson() => {
    'version': 1,
    'revision': revision,
    'spine_href': spineHref,
    'block_id': blockId,
    'start_utf16': startUtf16,
    'end_utf16': endUtf16,
    'exact': exact,
    'offset_unit': 'utf16_code_unit',
  };
  String resolve({
    required String currentRevision,
    required String currentHref,
    required Map<String, String> blocks,
  }) {
    if (currentRevision != revision || currentHref != spineHref) {
      throw const FormatException('revision_or_spine_mismatch');
    }
    final text = blocks[blockId];
    if (text == null) throw const FormatException('block_missing');
    bool boundary(int index) =>
        index >= 0 &&
        index <= text.length &&
        !(index > 0 &&
            index < text.length &&
            text.codeUnitAt(index - 1) >= 0xD800 &&
            text.codeUnitAt(index - 1) <= 0xDBFF &&
            text.codeUnitAt(index) >= 0xDC00 &&
            text.codeUnitAt(index) <= 0xDFFF);
    if (startUtf16 > endUtf16 || !boundary(startUtf16) || !boundary(endUtf16)) {
      throw const FormatException('invalid_utf16_range');
    }
    final resolved = text.substring(startUtf16, endUtf16);
    if (resolved != exact) throw const FormatException('text_changed');
    return resolved;
  }
}
