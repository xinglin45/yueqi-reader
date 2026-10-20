import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/app/app.dart';
import 'package:novel_app/app/dependencies.dart';
import 'package:novel_app/app/navigation.dart';
import 'package:novel_app/application/jobs.dart';
import 'package:novel_app/domain/library.dart';
import 'package:novel_app/features/task_view.dart';
import 'package:platform_services/platform_services.dart';

import 'fakes.dart';

Future<void> desktop(
  WidgetTester tester, [
  Size size = const Size(1487, 1058),
]) async {
  tester.view.resetPhysicalSize();
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  test('locations carry an encoded stable id; malformed paths fail closed', () {
    const route = AppLocation(AppPage.reader, bookId: '书/籍 📖');
    expect(AppLocation.parse(Uri.parse(route.path)).bookId, route.bookId);
    for (final path in ['/reader', '/reader/a/b', '/settings/extra', '/nope']) {
      expect(AppLocation.parse(Uri.parse(path)).page, AppPage.unknown);
    }
    expect(AppLocation.parse(Uri.parse('/')).page, AppPage.library);
  });
  testWidgets(
    'D1 empty library, explicit sample, theme and all shell destinations',
    (tester) async {
      await desktop(tester);
      final navigation = AppNavigation();
      addTearDown(navigation.dispose);
      await tester.pumpWidget(
        NovelApp(dependencies: AppDependencies.local(), navigation: navigation),
      );
      await tester.pumpAndSettle();
      expect(find.text('把喜欢的故事，放进书架'), findsOneWidget);
      expect(find.text('山间来信'), findsNothing);
      await tester.tap(find.text('体验演示样本'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('打开阅读预览'));
      await tester.pumpAndSettle();
      expect(find.text('第三章　山路微光'), findsOneWidget);
      expect(navigation.location.bookId, 'demo-mountain-letter');
      await tester.tap(find.byKey(const ValueKey('toggle-theme')));
      await tester.pumpAndSettle();
      expect(
        Theme.of(tester.element(find.byType(ReaderShell))).brightness,
        Brightness.dark,
      );
      expect(find.byTooltip('切换浅色'), findsOneWidget);
      await tester.tap(find.byTooltip('低存在感'));
      await tester.pumpAndSettle();
      expect(find.text('菜单栏阅读'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      for (final page in [
        AppPage.search,
        AppPage.sources,
        AppPage.tasks,
        AppPage.notes,
        AppPage.statistics,
        AppPage.settings,
        AppPage.unknown,
      ]) {
        navigation.go(AppLocation(page));
        await tester.pumpAndSettle();
        expect(navigation.location.page, page);
        expect(tester.takeException(), isNull);
      }
      navigation.go(const AppLocation(AppPage.search));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '山間來信 📖 e\u0301');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.text('尚无可用来源，未发出搜索请求'), findsOneWidget);
      navigation.go(const AppLocation(AppPage.library));
      await tester.pumpAndSettle();
      expect(find.text('山间来信'), findsNWidgets(2));
      await tester.pumpWidget(
        NovelApp(
          key: const ValueKey('fresh'),
          dependencies: AppDependencies.local(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('把喜欢的故事，放进书架'), findsOneWidget);
    },
  );
  testWidgets(
    'repository fake independently drives loading, cancel, retry, partial and errors',
    (tester) async {
      await desktop(tester);
      final repo = ControlledLibrary();
      await tester.pumpWidget(
        NovelApp(dependencies: fakeDependencies(library: repo)),
      );
      await tester.pump();
      expect(find.text('正在加载'), findsOneWidget);
      await tester.tap(find.text('取消任务'));
      await tester.pump();
      repo.loads[0].complete(
        const JobResult([BookSummary(id: 'old', title: '迟到结果', subtitle: '')]),
      );
      await tester.pump();
      expect(find.text('迟到结果'), findsNothing);
      expect(find.text('任务已取消'), findsOneWidget);
      await tester.tap(find.text('重新开始'));
      await tester.pump();
      repo.loads[1].complete(
        const JobResult(
          [BookSummary(id: 'ok', title: '保留结果', subtitle: '')],
          issues: [FailureCode.offline],
        ),
      );
      await tester.pump();
      expect(find.text('保留结果'), findsOneWidget);
      expect(find.textContaining('部分完成'), findsOneWidget);
      await tester.tap(find.text('重试未完成部分'));
      await tester.pump();
      repo.loads[2].completeError(const AppFailure(FailureCode.corrupt));
      await tester.pump();
      expect(find.text('无法读取这份数据'), findsOneWidget);
      await tester.tap(find.text('重试'));
      await tester.pump();
      repo.loads[3].complete(const JobResult([], empty: true));
      await tester.pump();
      expect(find.text('把喜欢的故事，放进书架'), findsOneWidget);
    },
  );
  testWidgets(
    'switching book and leaving a page suppress uncooperative callbacks',
    (tester) async {
      await desktop(tester);
      final repo = ControlledLibrary();
      final nav = AppNavigation();
      addTearDown(nav.dispose);
      await tester.pumpWidget(
        NovelApp(
          dependencies: fakeDependencies(library: repo),
          navigation: nav,
        ),
      );
      await tester.pump();
      nav.go(const AppLocation(AppPage.reader, bookId: 'a'));
      await tester.pump();
      expect(repo.contexts.first.isCancelled, isTrue);
      nav.go(const AppLocation(AppPage.reader, bookId: 'b'));
      await tester.pump();
      expect(repo.contexts[1].isCancelled, isTrue);
      repo.readers['a']!.complete(
        JobResult(
          ReadingPreview(
            book: const BookSummary(id: 'a', title: 'A', subtitle: ''),
            chapter: '旧书',
            paragraphs: ['旧正文'],
          ),
        ),
      );
      repo.readers['b']!.complete(
        JobResult(
          ReadingPreview(
            book: const BookSummary(id: 'b', title: 'B', subtitle: ''),
            chapter: '新书',
            paragraphs: ['新正文'],
          ),
        ),
      );
      await tester.pump();
      expect(find.text('新正文'), findsOneWidget);
      expect(find.text('旧正文'), findsNothing);
      nav.go(const AppLocation(AppPage.sources));
      await tester.pump();
      repo.loads.first.completeError(Exception('private token'));
      await tester.pumpAndSettle();
      expect(find.text('普通 0 / 18+ 0'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'file port permission failure recovers through retry without opening real files',
    (tester) async {
      await desktop(tester);
      final files = FakeFiles();
      await tester.pumpWidget(
        NovelApp(
          dependencies: fakeDependencies(
            library: AppDependencies.local().library,
            files: files,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('import-book')));
      await tester.pumpAndSettle();
      expect(find.text('当前无法访问'), findsOneWidget);
      files.next = const PlatformSuccess(
        FileGrant(id: 'opaque', displayName: '自产.txt'),
      );
      await tester.tap(find.text('重试'));
      await tester.pumpAndSettle();
      expect(find.text('已选择：自产.txt'), findsOneWidget);
      expect(files.calls, 2);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      files.next = const PlatformUnavailable(PlatformFailure.cancelled);
      await tester.tap(find.byKey(const ValueKey('import-book')));
      await tester.pumpAndSettle();
      expect(find.text('未选择文件'), findsOneWidget);
      expect(find.text('找不到这本书'), findsNothing);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
    },
  );
  testWidgets(
    'desktop keyboard reaches primary actions and activates import by Enter',
    (tester) async {
      await desktop(tester);
      await tester.pumpWidget(NovelApp(dependencies: AppDependencies.local()));
      await tester.pumpAndSettle();
      bool focused(Key key) {
        var found = false;
        FocusManager.instance.primaryFocus?.context?.visitAncestorElements((
          element,
        ) {
          if (element.widget.key == key) found = true;
          return true;
        });
        return found;
      }

      final reached = <Key>{};
      const keys = [
        ValueKey('nav-search'),
        ValueKey('nav-sources'),
        ValueKey('nav-settings'),
        ValueKey('import-book'),
      ];
      for (var step = 0; step < 40; step++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        for (final key in keys) {
          if (focused(key)) reached.add(key);
        }
        if (focused(const ValueKey('import-book'))) {
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pumpAndSettle();
          break;
        }
      }
      expect(reached, containsAll(keys));
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(focused(const ValueKey('import-book')), isTrue);
    },
  );
  testWidgets(
    '390/700/1487 layouts, drawer Escape, dark settings and enlarged text have no overflow',
    (tester) async {
      await desktop(tester);
      final nav = AppNavigation();
      addTearDown(nav.dispose);
      await tester.pumpWidget(
        NovelApp(dependencies: AppDependencies.local(), navigation: nav),
      );
      await tester.pumpAndSettle();
      for (final size in [
        const Size(390, 844),
        const Size(700, 820),
        const Size(1487, 1058),
      ]) {
        tester.view.physicalSize = size;
        await tester.pumpAndSettle();
        if (size.width < 760) {
          await tester.tap(find.byTooltip('打开导航'));
          await tester.pumpAndSettle();
          expect(find.byType(Drawer), findsOneWidget);
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pumpAndSettle();
          expect(
            tester.state<ScaffoldState>(find.byType(Scaffold)).isDrawerOpen,
            isFalse,
          );
        }
        for (final page in [
          AppPage.library,
          AppPage.search,
          AppPage.sources,
          AppPage.tasks,
          AppPage.notes,
          AppPage.statistics,
          AppPage.settings,
          AppPage.unknown,
        ]) {
          nav.go(AppLocation(page));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
      }
      tester.view.physicalSize = const Size(390, 844);
      tester.platformDispatcher.textScaleFactorTestValue = 1.6;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      nav.go(const AppLocation(AppPage.settings));
      await tester.pumpAndSettle();
      await tester.tap(find.text('低存在感'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const ValueKey('toggle-theme')));
      await tester.pumpAndSettle();
      expect(find.text('菜单栏阅读'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('narrow reader and dialogs stay usable with enlarged text', (
    tester,
  ) async {
    await desktop(tester, const Size(390, 844));
    final nav = AppNavigation();
    addTearDown(nav.dispose);
    await tester.pumpWidget(
      NovelApp(dependencies: AppDependencies.local(), navigation: nav),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('体验演示样本'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('打开阅读预览'));
    await tester.pumpAndSettle();
    expect(find.text('第三章　山路微光'), findsOneWidget);
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('低存在感'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    nav.go(const AppLocation(AppPage.library));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('import-book')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'common states give permission/offline recovery and no result separately',
    (tester) async {
      for (final code in [FailureCode.permissionDenied, FailureCode.offline]) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: TaskView<String>(
                key: ValueKey(code),
                load: (_) async => throw AppFailure(code),
                builder: Text.new,
                empty: const Text('empty'),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text(failureTitle(code)), findsOneWidget);
        expect(find.text('重试'), findsOneWidget);
      }
    },
  );
}
