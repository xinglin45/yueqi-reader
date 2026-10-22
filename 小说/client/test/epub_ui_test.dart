import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/app/app.dart';
import 'package:novel_app/app/dependencies.dart';
import 'package:novel_app/domain/access.dart';
import 'package:novel_app/domain/documents.dart';
import 'package:novel_app/domain/importing.dart';
import 'package:novel_app/features/epub_reader.dart';
import 'package:novel_app/infrastructure/epub/mac_epub_surface.dart';

import 'access_test.dart' show Locations;
import 'import_test.dart' show ImportFiles, job;
import 'access_ui_test.dart' show frames, waitFor, closeDependencies;

void main() {
  testWidgets(
    'EPUB shelf, directory, validated renderer position and reload preserve actual SQLite anchor',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      tester.view.physicalSize = const Size(1500, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final files = ImportFiles(),
          dir = (await tester.runAsync(
            () => Directory.systemTemp.createTemp('mac07-ui-'),
          ))!;
      final messenger = tester.binding.defaultBinaryMessenger;
      const codec = StandardMethodCodec();
      var currentId = -1;
      final rendererIds = <int>[];
      final started = <int>{};
      Map<String, Object> selection() {
        final surface = tester.widget<MacEpubSurface>(
          find.byType(MacEpubSurface),
        );
        final blocks = surface.chapter.blocks;
        final block = blocks.keys.firstWhere(
          (k) => blocks[k]!.contains('目标位置'),
          orElse: () => blocks.keys.first,
        );
        final at = blocks[block]!.indexOf('目标位置');
        return {
          'session': surface.chapter.session.id,
          'resource': surface.chapter.spine.resource,
          'segments': [
            {
              'block': block,
              'start': at < 0 ? 0 : at,
              'end': at < 0 ? 0 : at + 4,
              'exact': at < 0 ? '' : '目标位置',
            },
          ],
        };
      }

      messenger.setMockMethodCallHandler(SystemChannels.platform_views, (
        call,
      ) async {
        if (call.method == 'create') {
          currentId = (call.arguments as Map)['id'] as int;
          rendererIds.add(currentId);
          final id = currentId;
          messenger.setMockMethodCallHandler(
            MethodChannel('reader/epub/$currentId'),
            (call) async {
              if (call.method == 'start') started.add(id);
              if (call.method == 'capture' || call.method == 'layout') {
                return selection();
              }
              if (call.method == 'restore') return true;
              return null;
            },
          );
        }
        return null;
      });
      Future<void> incoming(String method, Object? args) async {
        await messenger.handlePlatformMessage(
          'reader/epub/$currentId',
          codec.encodeMethodCall(MethodCall(method, args)),
          null,
        );
      }

      Future<void> ready(int ordinal) async {
        for (var i = 0; i < 100; i++) {
          await frames(tester);
          final all = find.byType(MacEpubSurface).evaluate();
          if (all.isNotEmpty &&
              (all.first.widget as MacEpubSurface).chapter.spine.ordinal ==
                  ordinal &&
              started.contains(currentId)) {
            break;
          }
        }
        final surface = tester.widget<MacEpubSurface>(
          find.byType(MacEpubSurface),
        );
        expect(surface.chapter.spine.ordinal, ordinal);
        await incoming('ready', {
          'session': surface.chapter.session.id,
          'resource': surface.chapter.spine.resource,
          'blocks': surface.chapter.blocks,
        });
        await frames(tester);
        expect(
          tester
              .widget<TextButton>(find.widgetWithText(TextButton, '记住文本位置'))
              .onPressed,
          isNotNull,
        );
      }

      AppDependencies? deps;
      try {
        deps = (await tester.runAsync(
          () => AppDependencies.open(Locations(dir.path), documents: files),
        ))!;
        final grant = files.add(
          '自产章节.epub',
          '../../fixtures/novel/mac07/流式EPUB3.epub',
        );
        final preview = (await tester.runAsync(
          () => deps!.importer!.prepare(grant, job()),
        ))!;
        final book = (await tester.runAsync(
          () => deps!.importer!.commit(
            preview.id,
            mode: ImportMode.managed,
            rating: RatingLevel.general,
            job: job(),
          ),
        ))!;
        await tester.pumpWidget(NovelApp(dependencies: deps));
        await frames(tester);
        await waitFor(tester, find.text('打开 EPUB 阅读'));
        await tester.ensureVisible(find.text('打开 EPUB 阅读'));
        await tester.tap(find.text('打开 EPUB 阅读'));
        await frames(tester);
        await ready(0);
        expect(find.textContaining('清晨，山间的雾'), findsNothing);
        await tester.ensureVisible(find.text('章节目录'));
        await tester.tap(find.text('章节目录'));
        await frames(tester);
        await waitFor(tester, find.text('第二章 微光'));
        await tester.tap(find.text('第二章 微光'));
        await frames(tester);
        await ready(1);
        await tester.ensureVisible(find.text('记住文本位置'));
        await tester.tap(find.text('记住文本位置'));
        await frames(tester);
        await waitFor(tester, find.text('已记住当前 EPUB 文本位置。'));
        final saved = await tester.runAsync(
          () => deps!.positions!.loadPosition(
            book.bookId,
            PositionChannel.reading,
          ),
        );
        expect(saved!.anchor.exact, '目标位置');
        expect(saved.anchor.spineHref, 'Book/text/two.xhtml');
        await incoming('error', {'kind': 'process_terminated'});
        await frames(tester);
        await waitFor(tester, find.text('重新加载本章'));
        await tester.ensureVisible(find.text('重新加载本章'));
        await tester.tap(find.text('重新加载本章'));
        await frames(tester);
        await ready(1);
        await tester.pumpWidget(const SizedBox());
        await frames(tester);
        await closeDependencies(tester, deps);
        deps = (await tester.runAsync(
          () => AppDependencies.open(Locations(dir.path), documents: files),
        ))!;
        await tester.pumpWidget(NovelApp(dependencies: deps));
        await frames(tester);
        await waitFor(tester, find.text('打开 EPUB 阅读'));
        await tester.ensureVisible(find.text('打开 EPUB 阅读'));
        await tester.tap(find.text('打开 EPUB 阅读'));
        await frames(tester);
        await ready(1);
        await waitFor(tester, find.text('已恢复到上次记住的 EPUB 文本位置。'));
        expect(
          tester
              .widget<MacEpubSurface>(find.byType(MacEpubSurface))
              .anchor!
              .exact,
          '目标位置',
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await frames(tester);
      } finally {
        await tester.pumpWidget(const SizedBox());
        await frames(tester);
        if (deps != null) await closeDependencies(tester, deps);
        messenger.setMockMethodCallHandler(SystemChannels.platform_views, null);
        for (final id in rendererIds) {
          messenger.setMockMethodCallHandler(
            MethodChannel('reader/epub/$id'),
            null,
          );
        }
        await files.incoming.close();
        await tester.runAsync(() => dir.delete(recursive: true));
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );
  testWidgets(
    'privacy lock masks protected EPUB header and an open image dialog',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final files = ImportFiles(),
          dir = (await tester.runAsync(
            () => Directory.systemTemp.createTemp('mac07-image-ui-'),
          ))!;
      AppDependencies? deps;
      try {
        deps = (await tester.runAsync(
          () => AppDependencies.open(Locations(dir.path), documents: files),
        ))!;
        await tester.runAsync(() => deps!.access!.acknowledge());
        final grant = files.add(
          '中性分级检查.epub',
          '../../fixtures/novel/mac07/流式EPUB3.epub',
        );
        final preview = (await tester.runAsync(
          () => deps!.importer!.prepare(grant, job()),
        ))!;
        final book = (await tester.runAsync(
          () => deps!.importer!.commit(
            preview.id,
            mode: ImportMode.managed,
            rating: RatingLevel.restricted,
            job: job(),
          ),
        ))!;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: EpubReaderView(
                  bookId: book.bookId,
                  deps: deps,
                  onOpened: (_) {},
                ),
              ),
            ),
          ),
        );
        await frames(tester);
        await waitFor(tester, find.text('第一章　雨后山路'));
        await tester.ensureVisible(find.text('本章图片'));
        await tester.tap(find.text('本章图片'));
        await frames(tester);
        await waitFor(tester, find.text('图片 1'));
        await tester.tap(find.text('图片 1'));
        await frames(tester);
        await waitFor(tester, find.text('书内图片'));
        expect(find.byType(InteractiveViewer), findsOneWidget);
        await tester.runAsync(() => deps!.access!.lock());
        await frames(tester);
        expect(find.text('书内图片'), findsNothing);
        expect(find.byType(InteractiveViewer), findsNothing);
        expect(find.text('第一章　雨后山路'), findsNothing);
        expect(find.text('山路与微光'), findsNothing);
        expect(find.text('内容已隐藏'), findsWidgets);
        await tester.tap(find.text('返回'));
        await frames(tester);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        await frames(tester);
        if (deps != null) await closeDependencies(tester, deps);
        await files.incoming.close();
        await tester.runAsync(() => dir.delete(recursive: true));
      }
    },
  );
}
