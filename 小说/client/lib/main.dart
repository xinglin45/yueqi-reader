import 'dart:ui';

import 'package:flutter/material.dart';

import 'app/startup.dart';
import 'application/diagnostics.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterError.onError = (_) =>
      SafeDiagnostics.record(DiagnosticCode.framework);
  PlatformDispatcher.instance.onError = (_, _) {
    SafeDiagnostics.record(DiagnosticCode.unhandled);
    return true;
  };
  ErrorWidget.builder = (_) => const ColoredBox(
    color: Color(0xFFFBF9F5),
    child: Center(
      child: Text(
        '页面暂时无法显示，请重新打开阅栖。',
        textDirection: TextDirection.ltr,
        style: TextStyle(color: Color(0xFF2D2925), fontSize: 16),
      ),
    ),
  );
  runApp(const NovelStartup());
}
