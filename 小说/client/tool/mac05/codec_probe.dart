import 'dart:io';
import 'dart:convert';

import 'package:novel_app/infrastructure/txt/decoder.dart';

Future<void> main(List<String> args) async {
  final root = args.single;
  final result = <Map<String, Object>>[];
  for (final (encoding, name) in [
    ('gb18030', 'GB18030.txt'),
    ('big5', 'Big5.txt'),
  ]) {
    final bytes = await File('$root/$name').readAsBytes();
    final decoder = TxtDecoder(encoding), values = <Scalar>[];
    for (final byte in bytes) {
      values.addAll(decoder.add([byte]));
    }
    values.addAll(decoder.add([], last: true));
    final text = String.fromCharCodes(values.map((s) => s.value));
    if (!text.contains(encoding == 'big5' ? '這是自產' : '这是自产') ||
        (encoding == 'gb18030' && !text.contains('📖')) ||
        values.last.end != bytes.length) {
      throw StateError('owned_codec_probe');
    }
    result.add({
      'encoding': encoding,
      'byte_split_roundtrip': true,
      'source_end': values.last.end,
      'emoji_checked': encoding == 'gb18030',
    });
  }
  stdout.writeln(
    const JsonEncoder.withIndent(
      '  ',
    ).convert({'mode': 'Dart AOT; system CoreFoundation', 'results': result}),
  );
}
