import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../../domain/jobs.dart';
import '../../domain/txt.dart';
import 'decoder.dart';

const txtRecordBytes = 96;
const txtBlockUnits = 2048;

final class HashSink implements Sink<Digest> {
  Digest? value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}

Future<Map<String, dynamic>> parseTxt({
  required String path,
  required String output,
  required String encoding,
  required TxtRules rules,
  required JobContext job,
}) async {
  final receive = ReceivePort(), done = Completer<Map<String, dynamic>>();
  SendPort? control;
  final subscription = receive.listen((dynamic message) {
    if (message is SendPort) {
      control = message;
    } else if (message is double) {
      job.report(message);
    } else if (message is Map) {
      if (message['error'] != null) {
        done.completeError(
          message['error'] == 'cancelled'
              ? const JobCancelled()
              : AppFailure(
                  message['error'] == 'limit'
                      ? FailureCode.unsupported
                      : FailureCode.corrupt,
                ),
        );
      } else {
        done.complete(Map<String, dynamic>.from(message));
      }
    } else if (message is List) {
      if (!done.isCompleted) {
        done.completeError(const AppFailure(FailureCode.unexpected));
      }
    }
  });
  final timer = Timer.periodic(const Duration(milliseconds: 20), (_) {
    if (job.isCancelled) control?.send('cancel');
  });
  Isolate? isolate;
  try {
    job.checkCancelled();
    isolate = await Isolate.spawn(_serve, [
      receive.sendPort,
      path,
      output,
      encoding,
      rules.toJson(),
    ], onError: receive.sendPort);
    final result = await done.future;
    job.checkCancelled();
    return result;
  } finally {
    timer.cancel();
    await subscription.cancel();
    receive.close();
    isolate?.kill(priority: Isolate.immediate);
  }
}

void _serve(List<dynamic> args) async {
  final reply = args[0] as SendPort, control = ReceivePort();
  var cancelled = false;
  control.listen((_) => cancelled = true);
  reply.send(control.sendPort);
  try {
    final result = await buildTxtIndex(
      path: args[1] as String,
      output: args[2] as String,
      encoding: args[3] as String,
      rules: TxtRules.fromJson(Map<String, dynamic>.from(args[4] as Map)),
      cancelled: () => cancelled,
      progress: reply.send,
    );
    reply.send(result);
  } on JobCancelled {
    reply.send({'error': 'cancelled'});
  } on FormatException catch (e) {
    reply.send({'error': e.message.startsWith('limit') ? 'limit' : 'encoding'});
  } catch (_) {
    reply.send({'error': 'corrupt'});
  } finally {
    control.close();
  }
}

/// Writes only fixed-size block ranges/hashes and bounded chapter metadata.
/// Body text is decoded on demand from the original, including reference mode.
Future<Map<String, dynamic>> buildTxtIndex({
  required String path,
  required String output,
  required String encoding,
  required TxtRules rules,
  required bool Function() cancelled,
  required void Function(double) progress,
}) async {
  final source = File(path), size = await File(path).length();
  if (size <= 0 || size > 64 * 1024 * 1024) {
    throw const FormatException('limit_source');
  }
  await Directory(output).create(recursive: true);
  final file = await File('$output/blocks.bin').open(mode: FileMode.writeOnly);
  final rawHash = HashSink(), indexHash = HashSink(), textHash = HashSink();
  final raw = sha256.startChunkedConversion(rawHash),
      index = sha256.startChunkedConversion(indexHash),
      normalized = sha256.startChunkedConversion(textHash);
  final decoder = TxtDecoder(encoding), newlines = Newlines();
  final records = BytesBuilder(copy: false);
  final chapters = <Map<String, dynamic>>[];
  var body = StringBuffer(),
      units = 0,
      totalUnits = 0,
      count = 0,
      paragraph = 0,
      read = 0;
  var start = 0, end = 0, continuation = false, blockContinuation = false;
  var line = StringBuffer(), lineUnits = 0, lineFirst = 0;
  final standard = RegExp(
    r'^第[零〇一二三四五六七八九十百千万萬两兩壹贰貳叁參肆伍陆陸柒捌玖拾佰仟0-9０-９]{1,20}[章节節回卷部篇集幕]',
  );
  final strict = RegExp(r'^第[零〇一二三四五六七八九十百千万萬两兩0-9０-９]{1,20}[章节節回]');
  final special = RegExp(
    r'^(?:序章|序言|序|楔子|前言|引子|后记|後記|尾声|尾聲|终章|終章|番外)(?:\s|[　：:、.．\-—]|$)',
  );
  void check() {
    if (cancelled()) throw const JobCancelled();
  }

  void finishLine() {
    final title = line.toString().trim();
    if (rules.headings != TxtHeadings.none &&
        lineUnits <= rules.maxTitle &&
        title.isNotEmpty &&
        ((rules.headings == TxtHeadings.standard
                ? standard.hasMatch(title) || special.hasMatch(title)
                : strict.hasMatch(title)) ||
            (rules.prefix.isNotEmpty && title.startsWith(rules.prefix)))) {
      if (chapters.length >= 20000) {
        throw const FormatException('limit_chapters');
      }
      chapters.add({'title': title, 'first': lineFirst});
    }
    line = StringBuffer();
    lineUnits = 0;
    lineFirst = count;
  }

  void flushBlock() {
    if (units == 0) return;
    if (count >= 1000000) throw const FormatException('limit_blocks');
    final text = body.toString(), bytes = utf8.encode(text);
    final record = ByteData(txtRecordBytes);
    final fields = [
      totalUnits,
      units,
      start,
      end,
      paragraph,
      blockContinuation ? 1 : 0,
      bytes.length,
      count,
    ];
    for (var i = 0; i < fields.length; i++) {
      record.setUint64(i * 8, fields[i], Endian.little);
    }
    final data = record.buffer.asUint8List();
    data.setRange(64, 96, sha256.convert(bytes).bytes);
    records.add(data);
    normalized.add(bytes);
    totalUnits += units;
    count++;
    units = 0;
    body = StringBuffer();
  }

  void take(Iterable<Scalar> values) {
    for (final s in values) {
      final length = s.value > 0xffff ? 2 : 1;
      if (units + length > txtBlockUnits) {
        flushBlock();
        continuation = true;
      }
      if (units == 0) {
        start = s.start;
        blockContinuation = continuation;
      }
      body.writeCharCode(s.value);
      units += length;
      end = s.end;
      if (s.value != 10) {
        lineUnits += length;
        if (lineUnits <= rules.maxTitle) line.writeCharCode(s.value);
      }
      if (s.value == 10) {
        flushBlock();
        finishLine();
        paragraph++;
        continuation = false;
      }
    }
  }

  Future<void> drain() async {
    if (records.length == 0) return;
    final bytes = records.takeBytes();
    index.add(bytes);
    await file.writeFrom(bytes);
  }

  try {
    await for (final chunk in source.openRead()) {
      check();
      raw.add(chunk);
      read += chunk.length;
      if (read > 64 * 1024 * 1024) throw const FormatException('limit_source');
      take(newlines.add(decoder.add(chunk)));
      await drain();
      progress((read / size).clamp(0, 1) * .98);
    }
    take(newlines.add(decoder.add(const [], last: true), last: true));
    flushBlock();
    if (lineUnits > 0) finishLine();
    await drain();
    check();
    raw.close();
    index.close();
    normalized.close();
    if (count == 0) throw const FormatException('empty_text');
    if (chapters.isEmpty) {
      chapters.add({'title': '全文', 'first': 0});
    } else if (chapters.first['first'] != 0) {
      chapters.insert(0, {'title': '正文前', 'first': 0});
    }
    for (var i = 0; i < chapters.length; i++) {
      chapters[i]['end'] = i + 1 < chapters.length
          ? chapters[i + 1]['first']
          : count;
    }
    final manifest = <String, dynamic>{
      'parser': 'txt-v1',
      'encoding': encoding,
      'rules': rules.toJson(),
      'blocks': count,
      'units': totalUnits,
      'source_digest': rawHash.value.toString(),
      'index_digest': indexHash.value.toString(),
      'text_digest': textHash.value.toString(),
      'chapters': chapters,
    };
    await file.flush();
    await File('$output/manifest.json')
        .writeAsString(jsonEncode(manifest), flush: true);
    progress(1);
    return manifest;
  } finally {
    await file.close();
  }
}
