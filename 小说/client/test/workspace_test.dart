import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/reader_core.dart';

void main() {
  test(
    'UTF-8 content round-trips beneath the actual Chinese workspace path',
    () async {
      final project = Directory.current;
      expect(project.path, contains('小说'));
      final temporary = await Directory('${project.path}/.dart_tool')
          .createTemp('中文路径-');
      addTearDown(() => temporary.delete(recursive: true));
      final file = File('${temporary.path}/山间来信-山間來信-📖.txt');
      const sample = '简体／繁體\n📖 e\u0301\n';
      await file.writeAsString(sample, flush: true);
      expect(await file.readAsString(), sample);
    },
  );

  test('shared core stays platform independent and product namespaces are isolated', () {
    expect(ReaderProduct.novel.namespace, isNot(ReaderProduct.comic.namespace));
    final core = Directory('../../packages/reader_core');
    expect(core.existsSync(), isTrue);
    final imports = core
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .expand((file) => file.readAsLinesSync())
        .where((line) => RegExp(r'^\s*(import|export)\s').hasMatch(line));
    for (final line in imports) {
      expect(
        line,
        isNot(
          matches(r'(package:(novel_app|comic_app|flutter)/|dart:(io|ui))'),
        ),
      );
    }
  });
  test('domain, jobs and platform contracts have no native or application dependency', () {
    for (final path in [
      'lib/domain',
      'lib/application',
      '../../packages/platform_services/lib',
    ]) {
      for (final file
          in Directory(path)
              .listSync(recursive: true)
              .whereType<File>()
              .where((file) => file.path.endsWith('.dart'))) {
        final imports = file.readAsLinesSync().where(
          (line) => RegExp(r'^\s*(import|export)\s').hasMatch(line),
        );
        for (final line in imports) {
          expect(
            line,
            isNot(
              matches(
                r'(package:(flutter|novel_app|comic_app|.*_macos|path_provider|flutter_tts)/|dart:(io|ui)|AppKit|/Users/)',
              ),
            ),
            reason: file.path,
          );
          if (path == 'lib/domain') {
            expect(line, isNot(contains('../application/')));
          }
        }
      }
    }
  });
}
