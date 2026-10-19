import 'dart:convert';

import 'package:epub_view/epub_view.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../tool/mac06/anchor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'same EPUB really parses with epub_view/epubx; it is not a JSON-only mock',
    () async {
      final book = await EpubDocument.openAsset(
        'assets/mac06/mountain-letter.epub',
      );
      expect(book.Chapters, hasLength(2));
      expect(book.Content?.Images, hasLength(1));
      final fixture = jsonDecode(
        await rootBundle.loadString('assets/mac06/fixture.json'),
      ) as Map<String, dynamic>;
      expect(fixture['spine'], hasLength(2));
    },
  );
  test(
    'Dart, DOM and speech anchors use UTF-16 without normalizing original text',
    () {
      const text = '📖 e\u0301，目标位置在这里';
      final start = text.indexOf('目标位置');
      expect(start, 6); // emoji=2, space=1, e+combining acute=2, comma=1
      final anchor = ProbeAnchor(
        revision: 'r1',
        spineHref: 'text/ch2.xhtml',
        blockId: 'target',
        startUtf16: start,
        endUtf16: start + 4,
        exact: '目标位置',
      );
      expect(
        anchor.resolve(
          currentRevision: 'r1',
          currentHref: 'text/ch2.xhtml',
          blocks: {'target': text},
        ),
        '目标位置',
      );
      expect(anchor.toJson()['offset_unit'], 'utf16_code_unit');
      expect(text.contains('é'), isFalse);
    },
  );
  test('same words in another block/spine/revision cannot silently capture the anchor', () {
    const anchor = ProbeAnchor(
      revision: 'r1',
      spineHref: 'a',
      blockId: 'chosen',
      startUtf16: 0,
      endUtf16: 2,
      exact: '山路',
    );
    expect(
      anchor.resolve(
        currentRevision: 'r1',
        currentHref: 'a',
        blocks: {'earlier': '山路', 'chosen': '山路'},
      ),
      '山路',
    );
    for (final (revision, href, blocks) in [
      ('r2', 'a', {'chosen': '山路'}),
      ('r1', 'b', {'chosen': '山路'}),
      ('r1', 'a', {'earlier': '山路'}),
      ('r1', 'a', {'chosen': '山间'}),
    ]) {
      expect(
        () => anchor.resolve(
          currentRevision: revision,
          currentHref: href,
          blocks: blocks,
        ),
        throwsFormatException,
      );
    }
  });
  test(
    'half surrogate, negative, inverted and out-of-bounds ranges fail closed',
    () {
      for (final (start, end) in [(1, 2), (-1, 1), (3, 2), (0, 99)]) {
        final anchor = ProbeAnchor(
          revision: 'r',
          spineHref: 'a',
          blockId: 'p',
          startUtf16: start,
          endUtf16: end,
          exact: '',
        );
        expect(
          () => anchor.resolve(
            currentRevision: 'r',
            currentHref: 'a',
            blocks: {'p': '📖 山路'},
          ),
          throwsFormatException,
        );
      }
    },
  );
}
