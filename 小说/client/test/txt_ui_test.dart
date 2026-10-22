import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/app/app.dart';
import 'package:novel_app/app/dependencies.dart';
import 'package:novel_app/domain/access.dart';
import 'package:novel_app/domain/importing.dart';
import 'package:novel_app/domain/txt.dart';

import 'access_test.dart' show Locations;
import 'import_test.dart' show ImportFiles, job;
import 'access_ui_test.dart' show frames, waitFor, closeDependencies;

void main() {
  testWidgets(
    'imported TXT previews directory before apply, reads actual text, navigates chapters, remembers and restores block',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final dir = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('mac05-ui-'),
      ))!;
      final files = ImportFiles();
      AppDependencies? deps;
      try {
        deps = (await tester.runAsync(
          () => AppDependencies.open(Locations(dir.path), documents: files),
        ))!;
        final source = File('${dir.path}/owned.txt');
        await tester.runAsync(
          () => source.writeAsString(
            '序章\n这是自产的开篇。📖\n第一章山路\n繁體文字與微光。\n後記\n至此。\n',
          ),
        );
        final grant = files.add('自产正文.txt', source.path);
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
        await waitFor(tester, find.text('打开 TXT 阅读'));
        await tester.ensureVisible(find.text('打开 TXT 阅读'));
        await tester.tap(find.text('打开 TXT 阅读'));
        await frames(tester);
        await waitFor(tester, find.text('预览分章'));
        await tester.ensureVisible(find.text('预览分章'));
        await tester.tap(find.text('预览分章'));
        await frames(tester);
        await waitFor(tester, find.text('确认使用此目录'));
        expect(
          await tester.runAsync(() => deps!.txt!.open(book.bookId, job())),
          isNull,
        );
        await tester.ensureVisible(find.text('确认使用此目录'));
        await tester.tap(find.text('确认使用此目录'));
        await frames(tester);
        await waitFor(tester, find.textContaining('这是自产的开篇。'));
        expect(find.textContaining('清晨，山间的雾'), findsNothing);
        await tester.ensureVisible(find.text('章节目录'));
        await tester.tap(find.text('章节目录'));
        await frames(tester);
        await waitFor(tester, find.text('2. 第一章山路'));
        await tester.tap(find.text('2. 第一章山路'));
        await frames(tester);
        await waitFor(tester, find.textContaining('繁體文字與微光。'));
        await tester.ensureVisible(find.text('记住这一段').last);
        await tester.tap(find.text('记住这一段').last);
        await frames(tester);
        await waitFor(tester, find.text('已记住这个文本块。'));
        await tester.pumpWidget(const SizedBox());
        await frames(tester);
        await closeDependencies(tester, deps);
        deps = (await tester.runAsync(
          () => AppDependencies.open(Locations(dir.path), documents: files),
        ))!;
        final index = (await tester.runAsync(
          () => deps!.txt!.open(book.bookId, job()),
        ))!;
        expect(index.rules.headings, TxtHeadings.standard);
        await tester.pumpWidget(NovelApp(dependencies: deps));
        await frames(tester);
        await waitFor(tester, find.text('打开 TXT 阅读'));
        await tester.ensureVisible(find.text('打开 TXT 阅读'));
        await tester.tap(find.text('打开 TXT 阅读'));
        await frames(tester);
        await waitFor(tester, find.text('已恢复到上次记住的文本块。'));
        final changed = (await tester.runAsync(
          () => deps!.txt!.preview(
            book.bookId,
            const TxtRules(headings: TxtHeadings.none),
            job(),
          ),
        ))!;
        await tester.runAsync(() => deps!.txt!.apply(changed.id, job()));
        await tester.pumpWidget(const SizedBox());
        await frames(tester);
        await tester.pumpWidget(NovelApp(dependencies: deps));
        await frames(tester);
        await waitFor(tester, find.text('打开 TXT 阅读'));
        await tester.ensureVisible(find.text('打开 TXT 阅读'));
        await tester.tap(find.text('打开 TXT 阅读'));
        await frames(tester);
        await waitFor(tester, find.textContaining('分章版本已变更，旧位置已保留'));
        await tester.ensureVisible(find.text('文件状态'));
        await tester.tap(find.text('文件状态'));
        await frames(tester);
        await waitFor(tester, find.textContaining('托管副本完整'));
        await tester.tap(find.text('返回'));
        await frames(tester);
        await waitFor(tester, find.textContaining('分章版本已变更，旧位置已保留'));
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
