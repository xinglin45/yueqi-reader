import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/main.dart';

void main() {
  testWidgets(
    'Chinese input survives dialog navigation in the novel namespace',
    (tester) async {
      await tester.pumpWidget(const NovelBootstrapApp());
      expect(find.byKey(const ValueKey('bootstrap-novel')), findsOneWidget);
      expect(find.text('阅栖'), findsOneWidget);

      const sample = '山间来信／山間來信 📖 e\u0301';
      await tester.enterText(find.byType(TextField), sample);
      await tester.tap(find.text('显示输入内容'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(SelectableText, sample), findsOneWidget);
      await tester.tap(find.text('返回'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        sample,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
