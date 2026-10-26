import 'dart:io';

import 'access_ui_test.dart' show closeDependencies;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/app/app.dart';
import 'package:novel_app/app/dependencies.dart';
import 'package:novel_app/app/navigation.dart';
import 'package:novel_app/domain/jobs.dart';
import 'package:novel_app/infrastructure/storage/local_library.dart';
import 'package:platform_services/platform_services.dart';

class _Locations implements StorageLocationProvider {
  const _Locations(this.root);
  final String root;
  @override
  Future<AppStorageLocations> locations() async =>
      AppStorageLocations(support: '$root/support', cache: '$root/cache');
}

Future<void> _waitFor(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 100; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
    if (finder.evaluate().isNotEmpty) return;
  }
  expect(finder, findsWidgets);
}

void main() {
  testWidgets(
    'real database composition restores the D1 paragraph marker and theme after disposal/reopen',
    (tester) async {
      final dir = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('阅栖-shell-'),
      ))!;
      final locations = _Locations(dir.path);
      AppDependencies? dependencies;
      try {
        dependencies = (await tester.runAsync(
          () => AppDependencies.open(locations),
        ))!;
        final book = (await tester.runAsync(
          () => dependencies!.library.addDemonstration(
            JobContext(id: 1, isCurrent: () => true, report: (_) {}),
          ),
        ))!.value.single;
        final nav = AppNavigation();
        await tester.pumpWidget(
          NovelApp(dependencies: dependencies, navigation: nav),
        );
        nav.go(AppLocation(AppPage.reader, bookId: book.id));
        await tester.pump();
        final remember = find.byKey(const ValueKey('remember-paragraph-1'));
        await _waitFor(tester, remember);
        await tester.ensureVisible(remember);
        await tester.tap(remember);
        await _waitFor(tester, find.text('已记住第2段，下次打开可继续。'));
        await tester.tap(find.byKey(const ValueKey('toggle-theme')));
        await tester.pump();
        expect(
          await tester.runAsync(
            () => (dependencies!.library as LocalLibrary).loadSetting('theme'),
          ),
          'dark',
        );
        await tester.pumpWidget(const SizedBox());
        nav.dispose();
        await closeDependencies(tester, dependencies);
        dependencies = (await tester.runAsync(
          () => AppDependencies.open(locations),
        ))!;
        final restarted = AppNavigation();
        await tester.pumpWidget(
          NovelApp(dependencies: dependencies, navigation: restarted),
        );
        restarted.go(AppLocation(AppPage.reader, bookId: book.id));
        await tester.pump();
        await _waitFor(tester, find.text('上次记住 · 第2段'));
        expect(
          tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
          ThemeMode.dark,
        );
        expect(tester.takeException(), null);
        await tester.pumpWidget(const SizedBox());
        restarted.dispose();
      } finally {
        if (dependencies != null) await closeDependencies(tester, dependencies);
        await tester.runAsync(() => dir.delete(recursive: true));
      }
    },
  );
}
