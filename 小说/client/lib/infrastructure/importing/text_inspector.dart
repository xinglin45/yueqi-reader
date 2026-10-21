import 'dart:convert';
import 'dart:io';

import '../../domain/importing.dart';

typedef LegacyTextPreview = Future<String> Function(
  String path,
  TextEncoding encoding,
);

final class TextInspector {
  TextInspector(this.legacy);
  final LegacyTextPreview legacy;
  Future<(TextEncoding, String)> inspect(
    String path,
    TextEncoding requested,
  ) async {
    final file = File(path);
    final prefix = await file
        .openRead(0, 4)
        .fold(<int>[], (a, b) => a..addAll(b));
    var encoding = requested, skip = 0;
    if (encoding == TextEncoding.auto) {
      encoding = prefix.length >= 2 && prefix[0] == 255 && prefix[1] == 254
          ? TextEncoding.utf16le
          : prefix.length >= 2 && prefix[0] == 254 && prefix[1] == 255
          ? TextEncoding.utf16be
          : TextEncoding.utf8;
    }
    if (encoding == TextEncoding.gb18030 || encoding == TextEncoding.big5) {
      return (encoding, await legacy(path, encoding));
    }
    if (encoding == TextEncoding.utf8 &&
        prefix.length >= 3 &&
        prefix[0] == 239 &&
        prefix[1] == 187 &&
        prefix[2] == 191) {
      skip = 3;
    }
    if ((encoding == TextEncoding.utf16le &&
            prefix.length >= 2 &&
            prefix[0] == 255 &&
            prefix[1] == 254) ||
        (encoding == TextEncoding.utf16be &&
            prefix.length >= 2 &&
            prefix[0] == 254 &&
            prefix[1] == 255)) {
      skip = 2;
    }
    final preview = StringBuffer();
    var collected = 0;
    void add(String value) {
      if (value.contains('\u0000')) {
        throw const ImportFailure(ImportIssue.encoding);
      }
      if (collected < 2000) {
        final runes = value.runes.take(2000 - collected).toList();
        preview.write(String.fromCharCodes(runes));
        collected += runes.length;
      }
    }

    try {
      if (encoding == TextEncoding.utf8) {
        await for (final text in utf8.decoder.bind(file.openRead(skip))) {
          add(text);
        }
      } else {
        int? byte, high;
        await for (final chunk in file.openRead(skip)) {
          for (final next in chunk) {
            if (byte == null) {
              byte = next;
              continue;
            }
            final unit = encoding == TextEncoding.utf16le
                ? byte | next << 8
                : byte << 8 | next;
            byte = null;
            if (high != null) {
              if (unit < 0xdc00 || unit > 0xdfff) {
                throw const ImportFailure(ImportIssue.encoding);
              }
              add(
                String.fromCharCode(
                  0x10000 + ((high - 0xd800) << 10) + unit - 0xdc00,
                ),
              );
              high = null;
            } else if (unit >= 0xd800 && unit <= 0xdbff) {
              high = unit;
            } else if (unit >= 0xdc00 && unit <= 0xdfff) {
              throw const ImportFailure(ImportIssue.encoding);
            } else {
              add(String.fromCharCode(unit));
            }
          }
        }
        if (byte != null || high != null) {
          throw const ImportFailure(ImportIssue.encoding);
        }
      }
      if (collected == 0) throw const ImportFailure(ImportIssue.encoding);
      return (encoding, preview.toString());
    } on FormatException {
      throw const ImportFailure(ImportIssue.encoding);
    }
  }
}
