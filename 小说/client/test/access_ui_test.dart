import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/app/app.dart';
import 'package:novel_app/app/dependencies.dart';
import 'package:novel_app/app/navigation.dart';
import 'package:novel_app/domain/jobs.dart';
import 'package:novel_app/domain/library.dart';

import 'access_test.dart' show Locations;

Future<void> waitFor(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 100; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
    if (finder.evaluate().isNotEmpty) return;
  }
  expect(finder, findsWidgets);
}

Future<void> frames(WidgetTester tester) async {
  for (var i = 0; i < 3; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 200));
  }
}

Future<void> closeDependencies(
  WidgetTester tester,
  AppDependencies? deps,
) async {
  if (deps == null) return;
  var done = false;
  Object? error;
  deps.close!().then(
    (_) => done = true,
    onError: (Object e) {
      error = e;
      done = true;
    },
  );
  for (var i = 0; i < 100 && !done; i++) {
    await frames(tester);
  }
  expect(error, isNull);
  expect(done, true);
}

void main() {
  testWidgets(
    'unchecked declaration can cancel; one local confirmation survives restart and lock hides preview/sidebar without erasing collection',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final dir = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('mac16-ui-'),
      ))!;
      AppDependencies? deps;
      final nav = AppNavigation();
      try {
        deps = (await tester.runAsync(
          () => AppDependencies.open(Locations(dir.path)),
        ))!;
        await tester.runAsync(
          () => deps!.library.load(
            JobContext(id: 1, isCurrent: () => true, report: (_) {}),
          ),
        );
        final access = deps.access!;
        await tester.pumpWidget(NovelApp(dependencies: deps, navigation: nav));
        await tester.tap(find.text('成人收藏'));
        await frames(tester);
        await tester.tap(find.text('查看成年声明'));
        await frames(tester);
        expect(
          tester
              .widget<CheckboxListTile>(
                find.byKey(const ValueKey('adult-statement')),
              )
              .value,
          false,
        );
        expect(
          tester
              .widget<FilledButton>(find.byKey(const ValueKey('confirm-adult')))
              .onPressed,
          null,
        );
        await tester.tap(find.text('取消'));
        await frames(tester);
        expect(access.state.acknowledged, false);
        await tester.tap(find.text('全部书籍'));
        await frames(tester);
        await waitFor(tester, find.text('体验演示样本'));
        await tester.tap(find.text('成人收藏'));
        await frames(tester);
        await tester.tap(find.text('查看成年声明'));
        await frames(tester);
        await tester.tap(find.byKey(const ValueKey('adult-statement')));
        await frames(tester);
        await tester.tap(find.byKey(const ValueKey('confirm-adult')));
        for (var i = 0; i < 100 && !access.state.acknowledged; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump();
        }
        expect(access.state.acknowledged, true);
        expect(access.state.includeAdultSources, false);
        await frames(tester);
        await tester.tap(find.text('成人收藏'));
        await frames(tester);
        await tester.tap(find.text('加入分级测试卡片（不含成人正文）'));
        await waitFor(tester, find.text('分级测试卡片'));
        await tester.tap(find.text('分级测试卡片'));
        await tester.pump();
        await waitFor(tester, find.textContaining('这是自产的标签测试卡片'));
        expect(find.text('分级测试卡片'), findsWidgets);
        // Search preference changes must not dispose an active protected reader.
        await tester.runAsync(() => access.setDiscovery(true));
        await tester.pump();
        await tester.runAsync(() => access.setDiscovery(false));
        await tester.pump();
        expect(find.textContaining('这是自产的标签测试卡片'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('privacy-lock')));
        await waitFor(tester, find.text('当前无法访问'));
        expect(find.text('分级测试卡片'), findsNothing);
        expect(find.textContaining('这是自产的标签测试卡片'), findsNothing);
        await tester.tap(find.byKey(const ValueKey('privacy-lock')));
        await waitFor(tester, find.textContaining('这是自产的标签测试卡片'));
        expect(find.text('我确认已经成年'), findsNothing);
        await tester.pumpWidget(const SizedBox());
        await frames(tester);
        await closeDependencies(tester, deps);
        deps = (await tester.runAsync(
          () => AppDependencies.open(Locations(dir.path)),
        ))!;
        expect(deps.access!.state.acknowledged, true);
        expect(deps.access!.state.includeAdultSources, false);
        final retained = await tester.runAsync(
          () => (deps!.library as AdultLibrary).loadAdult(
            JobContext(id: 1, isCurrent: () => true, report: (_) {}),
          ),
        );
        expect(retained!.value, hasLength(1));
      } finally {
        await tester.pumpWidget(const SizedBox());
        await frames(tester);
        nav.dispose();
        await closeDependencies(tester, deps);
        await tester.runAsync(() => dir.delete(recursive: true));
      }
    },
  );
}
