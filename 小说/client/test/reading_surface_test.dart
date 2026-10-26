import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/domain/documents.dart';
import 'package:novel_app/domain/reading.dart';
import 'package:novel_app/domain/txt.dart';
import 'package:novel_app/features/text_surface.dart';

void main() {
  testWidgets(
    'scroll, font, paged, columns and narrow reflow retain a nearby canonical character',
    (tester) async {
      tester.view.physicalSize = const Size(1100, 750);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final text = List.filled(80, '山路微光，简繁體📖文字相伴。').join();
      final block = TxtBlock(0, text, 0, 0, 1, 0, false, const []);
      const index = TxtIndex(
        id: 'r',
        bookId: 'b',
        encoding: 'utf8',
        rules: TxtRules(),
        blocks: 1,
        units: 1,
        chapterCount: 1,
      );
      final page = TxtPage(index, const TxtChapter(0, '章', 0, 1), [block]);
      var prefs = const ReadingPreferences();
      late StateSetter update;
      DocumentAnchor? observed;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, set) {
                update = set;
                return TextReadingSurface(
                  page: page,
                  preferences: prefs,
                  onAnchor: (a) => observed = a,
                  onPrevious: null,
                  onNext: null,
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, -800),
      );
      await tester.pumpAndSettle();
      final before = observed!;
      expect(before.start, greaterThan(0));
      update(() => prefs = prefs.copyWith(size: 30, font: ReadingFont.sans));
      await tester.pumpAndSettle();
      expect(observed!.blockId, before.blockId);
      expect(observed!.start, before.start);
      final sizeAnchor = observed!;
      update(() => prefs = prefs.copyWith(layout: ReadingLayout.paged));
      await tester.pumpAndSettle();
      expect(observed!.start, sizeAnchor.start);
      update(() => prefs = prefs.copyWith(layout: ReadingLayout.columns));
      await tester.pumpAndSettle();
      expect(utf16Boundary(text, observed!.start), isTrue);
      expect(observed!.start, before.start);
      tester.view.physicalSize = const Size(600, 750);
      await tester.pumpAndSettle();
      expect(utf16Boundary(text, observed!.start), isTrue);
      expect(observed!.start, before.start);
      expect(tester.takeException(), isNull);
    },
  );
}
