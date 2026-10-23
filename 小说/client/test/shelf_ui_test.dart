import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/app/app.dart';
import 'package:novel_app/app/dependencies.dart';
import 'package:novel_app/app/navigation.dart';
import 'package:novel_app/domain/library.dart';
import 'package:novel_app/domain/shelf.dart';

import 'access_test.dart' show Locations;
import 'import_test.dart' show ImportFiles, job;
import 'access_ui_test.dart' show frames, waitFor, closeDependencies;

void main() {
  testWidgets(
    'real shelf edits, bulk states/collections, removal, undo and restart use durable data',
    (tester) async {
      tester.view.physicalSize = const Size(1500, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final dir = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('mac08-ui-'),
      ))!;
      final files = ImportFiles();
      AppDependencies? deps;
      final nav = AppNavigation();
      try {
        deps = (await tester.runAsync(
          () => AppDependencies.open(Locations(dir.path), documents: files),
        ))!;
        await tester.runAsync(() => deps!.library.addDemonstration(job()));
        await tester.pumpWidget(NovelApp(dependencies: deps, navigation: nav));
        await waitFor(tester, find.text('详情'));
        await tester.tap(find.text('详情'));
        await frames(tester);
        await tester.enterText(
          find.byKey(const ValueKey('edit-title')),
          '界面编辑 📖',
        );
        await tester.enterText(
          find.byKey(const ValueKey('edit-author')),
          '自产作者',
        );
        await tester.tap(find.byKey(const ValueKey('save-book-details')));
        await frames(tester);
        await waitFor(tester, find.text('界面编辑 📖'));
        await tester.tap(find.text('新建合集/标签'));
        await frames(tester);
        await tester.enterText(
          find.byKey(const ValueKey('group-label')),
          '秋日合集',
        );
        await tester.tap(find.text('保存分组'));
        await frames(tester);
        await waitFor(tester, find.widgetWithText(InputChip, '秋日合集'));
        await tester.tap(find.text('选择/取消本页'));
        await frames(tester);
        await tester.tap(find.text('设置合集/标签'));
        await frames(tester);
        await tester.tap(find.text('合集 · 秋日合集'));
        await tester.tap(find.text('保存归属'));
        await frames(tester);
        await waitFor(tester, find.text('#秋日合集'));
        await tester.tap(find.text('选择/取消本页'));
        await frames(tester);
        await tester.tap(find.text('标为读完'));
        await waitFor(tester, find.text('TXT · 读完'));
        await tester.tap(find.text('选择/取消本页'));
        await frames(tester);
        await tester.tap(find.text('移出书架'));
        await frames(tester);
        await tester.tap(find.text('确认'));
        await frames(tester);
        await waitFor(tester, find.textContaining('这里还没有符合条件'));
        await waitFor(tester, find.byKey(const ValueKey('undo-shelf')));
        await tester.tap(find.byKey(const ValueKey('undo-shelf')));
        await waitFor(tester, find.text('界面编辑 📖'));
        await tester.tap(find.byTooltip('切换列表'));
        await frames(tester);
        await tester.pumpWidget(const SizedBox());
        await frames(tester);
        await closeDependencies(tester, deps);
        deps = (await tester.runAsync(
          () => AppDependencies.open(Locations(dir.path), documents: files),
        ))!;
        final page = await tester.runAsync(
          () =>
              deps!.shelf!.list(ShelfScope.normal, const ShelfOptions(), job()),
        );
        expect(page!.books.single.author, '自产作者');
        expect(page.books.single.state, ReadingState.finished);
        expect(page.books.single.groups, hasLength(1));
        expect(
          (await tester.runAsync(
            () => deps!.shelf!.preferences(ShelfScope.normal),
          ))!.grid,
          false,
        );
        await tester.pumpWidget(NovelApp(dependencies: deps, navigation: nav));
        await waitFor(tester, find.text('界面编辑 📖'));
        expect(find.byTooltip('切换网格'), findsOneWidget);
        expect(tester.takeException(), null);
      } finally {
        await tester.pumpWidget(const SizedBox());
        await frames(tester);
        nav.dispose();
        await closeDependencies(tester, deps);
        await files.incoming.close();
        await tester.runAsync(() => dir.delete(recursive: true));
      }
    },
  );
  testWidgets(
    'protected metadata dialog, group names and custom cover disappear on lock',
    (tester) async {
      tester.view.physicalSize = const Size(1500, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final dir = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('mac08-private-ui-'),
      ))!;
      AppDependencies? deps;
      final nav = AppNavigation();
      try {
        deps = (await tester.runAsync(
          () => AppDependencies.open(Locations(dir.path)),
        ))!;
        await tester.runAsync(() async {
          await deps!.access!.acknowledge();
          await deps!.access!.unlock();
          final card =
              (await (deps!.library as AdultLibrary).addClassificationCard(
                job(),
              )).value.single;
          final group = await deps!.shelf!.createGroup(
            ShelfScope.adult,
            '隔离标签',
            'tag',
          );
          final book = (await deps!.shelf!.list(
            ShelfScope.adult,
            const ShelfOptions(),
            job(),
          )).books.single;
          await deps!.shelf!.edit({
            card.id: book.revision,
          }, BookEdit(author: '私密作者', groups: [group]));
          final current = (await deps!.shelf!.list(
            ShelfScope.adult,
            const ShelfOptions(),
            job(),
          )).books.single;
          await deps!.shelf!.setCover(
            card.id,
            current.revision,
            await File('assets/mountain-letter-cover.png').readAsBytes(),
          );
        });
        await tester.pumpWidget(NovelApp(dependencies: deps, navigation: nav));
        await waitFor(tester, find.textContaining('这里还没有符合条件'));
        expect(find.text('隔离标签'), findsNothing);
        await tester.tap(find.text('成人收藏'));
        await waitFor(tester, find.text('私密作者'));
        await tester.tap(find.text('详情'));
        await frames(tester);
        expect(find.text('私密作者'), findsWidgets);
        await tester.runAsync(() => deps!.access!.lock());
        await frames(tester);
        expect(find.text('内容已隐藏'), findsOneWidget);
        expect(find.text('私密作者'), findsNothing);
        expect(find.text('隔离标签'), findsNothing);
        expect(find.byKey(const ValueKey('edit-author')), findsNothing);
        expect(find.byType(Image), findsNothing);
        expect(tester.takeException(), null);
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
