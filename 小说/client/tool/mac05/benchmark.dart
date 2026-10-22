import 'dart:convert';
import 'dart:io';

import 'package:novel_app/domain/txt.dart';
import 'package:novel_app/domain/jobs.dart';
import 'package:novel_app/infrastructure/txt/parser.dart';

Future<void> main(List<String> args) async {
  final root = Directory(
    args.isEmpty ? 'build/mac05/benchmark-data' : args.single,
  );
  await root.create(recursive: true);
  final results = <Map<String, Object>>[];
  for (final mib in [10, 50]) {
    final source = File('${root.path}/owned-$mib.txt');
    final sink = await source.open(mode: FileMode.write);
    final chunk = utf8.encode(
      '第一章 山路\n${'自产简繁文字，窗外有微光。繁體閱讀📖e\u0301。\n' * 500}',
    );
    var left = mib * 1024 * 1024;
    while (left >= chunk.length) {
      await sink.writeFrom(chunk);
      left -= chunk.length;
    }
    await sink.writeFrom(List.filled(left, 32));
    await sink.close();
    final watch = Stopwatch()..start();
    final m = await parseTxt(
      path: source.path,
      output: '${root.path}/index-$mib',
      encoding: 'utf8',
      rules: const TxtRules(),
      job: JobContext(id: 1, isCurrent: () => true, report: (_) {}),
    );
    watch.stop();
    if (m['source_digest'] != m['text_digest']) {
      throw StateError('loss_or_normalization');
    }
    results.add({
      'mib': mib,
      'bytes': await source.length(),
      'parse_ms': watch.elapsedMilliseconds,
      'blocks': m['blocks'] as int,
      'chapters': (m['chapters'] as List).length,
      'index_bytes': await File('${root.path}/index-$mib/blocks.bin').length(),
      'peak_process_rss_bytes': ProcessInfo.maxRss,
      'exact_all_text_hash': true,
    });
  }
  stdout.writeln(
    const JsonEncoder.withIndent('  ').convert({
      'mode':
          'Dart AOT standalone parser isolate; not Flutter Release rendering',
      'results': results,
    }),
  );
}
