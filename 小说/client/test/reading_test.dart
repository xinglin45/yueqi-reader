import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:platform_services/platform_services.dart';
import 'package:novel_app/application/reading.dart';
import 'package:novel_app/domain/documents.dart';
import 'package:novel_app/domain/reading.dart';
import 'package:novel_app/domain/txt.dart';
import 'package:novel_app/features/text_surface.dart';

final class Positions implements PositionRepository {
  final values = <(String, PositionChannel), StoredPosition>{};
  int writes = 0;
  Completer<void>? gate;
  @override
  Future<StoredPosition?> loadPosition(
    String id,
    PositionChannel channel,
  ) async => values[(id, channel)];
  @override
  Future<StoredPosition> savePosition(
    String id,
    PositionChannel channel,
    DocumentAnchor anchor, {
    required int expectedSequence,
  }) async {
    await gate?.future;
    final key = (id, channel);
    if ((values[key]?.sequence ?? 0) != expectedSequence) {
      throw StateError('conflict');
    }
    writes++;
    return values[key] = StoredPosition(
      id,
      channel,
      anchor,
      expectedSequence + 1,
    );
  }
}

DocumentAnchor a(int start, {String revision = 'r'}) => DocumentAnchor.capture(
  kind: DocumentKind.txt,
  revision: revision,
  chapterId: 'c0',
  spineHref: 'text.txt',
  blockId: 'b0',
  text: '简繁體📖文字',
  start: start,
  end: start,
);
void main() {
  test('coalesced progress drains before book switch; stale callbacks and listening remain isolated', () async {
    final repo = Positions();
    final c = ReadingCoordinator(repo, null);
    final first = await c.open(
      const ReadingIdentity('one', 'r', DocumentKind.txt),
      isCurrent: () => true,
    );
    final listen = await repo.savePosition(
      'one',
      PositionChannel.listening,
      a(1),
      expectedSequence: 0,
    );
    for (final offset in [0, 1, 2, 3, 5, 6]) {
      first.observe(a(offset));
    }
    final second = await c.open(
      const ReadingIdentity('two', 'r', DocumentKind.txt),
      isCurrent: () => true,
    );
    expect(repo.writes, 2);
    expect(repo.values[('one', PositionChannel.reading)]!.anchor.start, 6);
    first.observe(a(0));
    await first.flush();
    second.observe(a(2));
    await c.close();
    expect(repo.values[('one', PositionChannel.listening)], same(listen));
    expect(repo.values[('two', PositionChannel.reading)]!.anchor.start, 2);
    expect(repo.writes, 3);
  });
  test('reflow duplicate observations do not create writes; revocation drops pending progress', () async {
    final repo = Positions();
    final owner = ReadingCoordinator(repo, null);
    final s = await owner.open(
      const ReadingIdentity('one', 'r', DocumentKind.txt),
      isCurrent: () => true,
    );
    s.observe(a(5));
    await s.flush();
    s.observe(a(5));
    await s.flush();
    expect(repo.writes, 1);
    s.observe(a(6));
    owner.revoke();
    await owner.flush();
    expect(repo.writes, 1);
    s.observe(a(0), explicit: true);
    expect(repo.writes, 1);
    await owner.close();
  });
  test(
    'revision mismatch and CAS conflict preserve prior durable record',
    () async {
      final repo = Positions();
      await repo.savePosition(
        'one',
        PositionChannel.reading,
        a(5, revision: 'old'),
        expectedSequence: 0,
      );
      final c = ReadingCoordinator(repo, null);
      final r = await c.open(
        const ReadingIdentity('one', 'r', DocumentKind.txt),
        isCurrent: () => true,
      );
      expect(r.needsReview, isTrue);
      r.observe(a(0));
      await c.flush();
      expect(
        repo.values[('one', PositionChannel.reading)]!.anchor.revision,
        'old',
      );
      r.observe(a(2), explicit: true);
      await c.flush();
      expect(repo.values[('one', PositionChannel.reading)]!.anchor.start, 2);
      await repo.savePosition(
        'one',
        PositionChannel.reading,
        a(3),
        expectedSequence: 2,
      );
      r.observe(a(6));
      await c.flush();
      expect(r.needsReview, isTrue);
      expect(repo.values[('one', PositionChannel.reading)]!.anchor.start, 3);
      await c.close();
    },
  );
  test('all four surfaces share one cursor; hiding pauses and history stays bounded', () async {
    final c = ReadingCoordinator(Positions(), null);
    final r = await c.open(
      const ReadingIdentity('book', 'r', DocumentKind.txt),
      isCurrent: () => true,
    );
    for (final surface in ReaderSurface.values) {
      r.attach(surface);
      r.observe(a(5));
      expect(c.current, same(r));
      expect(r.anchor!.start, 5);
    }
    r.advancing = true;
    r.hide();
    expect(r.visible, isFalse);
    r.restore();
    expect(r.advancing, isFalse);
    for (var i = 0; i < 30; i++) {
      r.rememberJump();
    }
    expect(r.history.length, 20);
    expect(r.popHistory()!.start, 5);
    await c.close();
  });
  testWidgets(
    'bounded pagination covers every UTF16 unit without splitting emoji across widths and fonts',
    (tester) async {
      final text = List.filled(50, '简体與繁體📖文字，换行也要保留。\n').join();
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
      for (final width in [140.0, 310.0, 600.0]) {
        for (final font in ['Songti SC', 'PingFang SC']) {
          final pages = paginateText(
            page,
            TextStyle(fontFamily: font, fontSize: 24, height: 1.9),
            width,
            200,
            TextScaler.noScaling,
            18,
          );
          final slices = pages.expand((p) => p).toList();
          expect(
            slices.map((s) => text.substring(s.start, s.end)).join(),
            text,
          );
          for (final slice in slices) {
            expect(utf16Boundary(text, slice.start), isTrue);
            expect(utf16Boundary(text, slice.end), isTrue);
            expect(slice.height, lessThanOrEqualTo(201));
          }
        }
      }
    },
  );
  test('return to durable cursor cancels obsolete pending write; in-flight save still restores latest', () async {
    final repo = Positions();
    final owner = ReadingCoordinator(repo, null);
    final r = await owner.open(
      const ReadingIdentity('b', 'r', DocumentKind.txt),
      isCurrent: () => true,
    );
    r.observe(a(1));
    await r.flush();
    r.observe(a(2));
    r.observe(a(1));
    await r.flush();
    expect(repo.writes, 1);
    repo.gate = Completer<void>();
    r.observe(a(2));
    final saving = r.flush();
    r.observe(a(1));
    final latest = r.flush();
    repo.gate!.complete();
    await saving;
    await latest;
    expect(repo.values[('b', PositionChannel.reading)]!.anchor.start, 1);
    await owner.close();
  });
  test(
    'anchor navigation rejects another revision and remembers validated origin',
    () async {
      final owner = ReadingCoordinator(Positions(), null);
      final s = await owner.open(
        const ReadingIdentity('b', 'r', DocumentKind.txt),
        isCurrent: () => true,
      );
      s.observe(a(1));
      DocumentAnchor? target;
      s.navigate = (a) async {
        target = a;
        return true;
      };
      expect(await s.jumpTo(a(2, revision: 'other')), isFalse);
      expect(target, isNull);
      expect(await s.jumpTo(a(5)), isTrue);
      expect(target!.start, 5);
      expect(s.popHistory()!.start, 1);
      await owner.close();
    },
  );
  test('preference decoding rejects nonfinite and unknown input', () {
    final json = const ReadingPreferences().toJson();
    expect(
      () => ReadingPreferences.fromJson({...json, 'size': double.nan}),
      throwsFormatException,
    );
    expect(
      () => ReadingPreferences.fromJson({...json, 'layout': 'script'}),
      throwsArgumentError,
    );
  });
}
