import 'dart:convert';
import 'dart:io';

import 'package:novel_app/infrastructure/epub/loader.dart';

Future<void> main(List<String> args) async {
  final dir = await Directory.systemTemp.createTemp('mac07-loader-');
  try {
    final watch = Stopwatch()..start();
    final value = await buildEpub(
      args.single,
      dir.path,
      's0123456789abcdef0123456789abcdef',
      check: () {},
      progress: (_) {},
    );
    watch.stop();
    stdout.writeln(
      const JsonEncoder.withIndent('  ').convert({
        'spine': value['spine'],
        'toc': value['toc'],
        'warnings': value['warnings'],
        'resource_count': (value['resources'] as Map).length,
        'load_ms': watch.elapsedMilliseconds,
        'peak_process_rss_bytes': ProcessInfo.maxRss,
        'source_digest': value['source_digest'],
      }),
    );
  } finally {
    await dir.delete(recursive: true);
  }
}
