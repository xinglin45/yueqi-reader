import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/application/access.dart';
import 'package:novel_app/domain/access.dart';
import 'package:novel_app/features/access_controls.dart';

void main() {
  testWidgets(
    'narrow large-text settings separate declaration, discovery, lock and clearing',
    (tester) async {
      tester.view.physicalSize = const Size(600, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final access = AccessController(MemoryAccessStore());
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.8)),
            child: Scaffold(
              body: SingleChildScrollView(
                child: StreamBuilder<AccessState>(
                  stream: access.changes,
                  initialData: access.state,
                  builder: (_, _) => Padding(
                    padding: const EdgeInsets.all(24),
                    child: AccessSettings(access: access),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      final toggle = find.byKey(const ValueKey('adult-search'));
      await tester.ensureVisible(toggle);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(find.text('我确认已经成年'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('adult-statement')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('confirm-adult')));
      await tester.pumpAndSettle();
      expect(access.state.acknowledged, true);
      expect(access.state.includeAdultSources, false);
      await tester.ensureVisible(toggle);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(access.state.includeAdultSources, true);
      await tester.ensureVisible(find.text('锁定隐私'));
      await tester.tap(find.text('锁定隐私'));
      await tester.pumpAndSettle();
      expect(access.state.adultDiscovery, false);
      expect(access.state.includeAdultSources, true);
      await tester.tap(find.text('解锁隐私'));
      await tester.pumpAndSettle();
      expect(find.text('我确认已经成年'), findsNothing);
      expect(access.state.adultDiscovery, true);
      await tester.tap(find.byKey(const ValueKey('clear-adult')));
      await tester.pumpAndSettle();
      expect(access.state.acknowledged, false);
      expect(access.state.includeAdultSources, false);
      expect(access.state.privacyLocked, true);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      await access.dispose();
    },
  );
}
