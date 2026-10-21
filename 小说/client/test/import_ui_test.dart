import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/app/app.dart';
import 'package:novel_app/app/dependencies.dart';
import 'package:novel_app/domain/access.dart';

import 'access_test.dart' show Locations;
import 'access_ui_test.dart' show frames, waitFor, closeDependencies;
import 'import_test.dart' show ImportFiles;

void main() {
  testWidgets(
    'batch preview requires a classification and confirms only valid files; source preserved, shelf uses generic document art',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 1500);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final dir = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('mac04-ui-'),
      ))!;
      final files = ImportFiles();
      files.selected = [
        files.add('简体-utf8.txt', '../../fixtures/novel/mac04/简体-utf8.txt'),
        files.add('坏包.epub', '../../fixtures/novel/mac04/坏包.epub'),
      ];
      AppDependencies? deps;
      try {
        deps = (await tester.runAsync(
          () => AppDependencies.open(Locations(dir.path), documents: files),
        ))!;
        await tester.pumpWidget(NovelApp(dependencies: deps));
        await frames(tester);
        await tester.tap(find.byKey(const ValueKey('import-book')));
        await frames(tester);
        await waitFor(tester, find.textContaining('文件结构或完整性检查失败'));
        final confirm = find.widgetWithText(FilledButton, '确认导入可用文件');
        expect(tester.widget<FilledButton>(confirm).onPressed, null);
        final classification = find
            .byType(DropdownButtonFormField<RatingLevel>)
            .first;
        await tester.ensureVisible(classification);
        await tester.tap(classification);
        await frames(tester);
        await tester.tap(find.text('普通').last);
        await frames(tester);
        expect(find.textContaining('这是自产的中文导入样本'), findsOneWidget);
        await tester.ensureVisible(confirm);
        await tester.tap(confirm);
        await frames(tester);
        await waitFor(tester, find.textContaining('文件已入库；TXT分章'));
        expect(find.textContaining('文件结构或完整性检查失败'), findsOneWidget);
        await tester.tap(find.text('返回书架'));
        await frames(tester);
        await waitFor(tester, find.text('查看文件状态'));
        expect(find.byType(Image), findsNothing);
        expect(
          await tester.runAsync(
            () => File('../../fixtures/novel/mac04/简体-utf8.txt').exists(),
          ),
          true,
        );
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        await frames(tester);
        await closeDependencies(tester, deps);
        await tester.runAsync(() => files.incoming.close());
        await tester.runAsync(() => dir.delete(recursive: true));
      }
    },
  );
  testWidgets(
    'incoming drag/open batch uses same preview; dismissing without confirmation leaves no imported book',
    (tester) async {
      tester.view.physicalSize = const Size(1100, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final dir = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('mac04-incoming-'),
      ))!;
      final files = ImportFiles();
      AppDependencies? deps;
      try {
        deps = (await tester.runAsync(
          () => AppDependencies.open(Locations(dir.path), documents: files),
        ))!;
        await tester.pumpWidget(NovelApp(dependencies: deps));
        await frames(tester);
        files.incoming.add([
          files.add('简体-utf8.txt', '../../fixtures/novel/mac04/简体-utf8.txt'),
        ]);
        await frames(tester);
        await waitFor(tester, find.text('文件 1 · 选择分级后显示预览'));
        await tester.tap(find.text('返回书架'));
        await frames(tester);
        await waitFor(tester, find.text('体验演示样本'));
        var stage = <FileSystemEntity>[];
        for (var i = 0; i < 100; i++) {
          await frames(tester);
          stage = (await tester.runAsync(
            () =>
                Directory('${dir.path}/support/novel/import-stage')
                    .list()
                    .toList(),
          ))!;
          if (stage.isEmpty) break;
        }
        expect(stage, isEmpty);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        await frames(tester);
        await closeDependencies(tester, deps);
        await tester.runAsync(() => files.incoming.close());
        await tester.runAsync(() => dir.delete(recursive: true));
      }
    },
  );
}
