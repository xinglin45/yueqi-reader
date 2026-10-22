import 'dart:typed_data';

import 'mac_legacy_codec.dart';

final class Scalar {
  const Scalar(this.value, this.start, this.end);
  final int value, start, end;
}

/// Strict scalar decoder, with original byte ranges. At most a 64 KiB chunk + 4 bytes.
final class TxtDecoder {
  TxtDecoder(this.encoding, {int base = 0, this.allowBom = true})
    : _offset = base;
  final String encoding;
  final bool allowBom;
  var _tail = <int>[];
  int _offset;
  bool _first = true;
  List<Scalar> add(List<int> chunk, {bool last = false}) {
    final bytes = Uint8List.fromList([..._tail, ...chunk]);
    final out = <Scalar>[];
    var i = 0;
    if (_first && allowBom) {
      if (!last && bytes.length < 4) {
        _tail = bytes;
        return out;
      }
      if (encoding == 'utf8' &&
          bytes.length >= 3 &&
          bytes[0] == 239 &&
          bytes[1] == 187 &&
          bytes[2] == 191) {
        i = 3;
      }
      if (bytes.length >= 2 &&
          ((encoding == 'utf16le' && bytes[0] == 255 && bytes[1] == 254) ||
              (encoding == 'utf16be' && bytes[0] == 254 && bytes[1] == 255))) {
        i = 2;
      }
    }
    _first = false;
    final legacy = encoding == 'gb18030' || encoding == 'big5';
    final legacyStarts = <int>[];
    final begin = i;
    while (i < bytes.length) {
      final start = i, a = bytes[i];
      int size, scalar;
      if (legacy) {
        size = a < 128
            ? 1
            : encoding == 'gb18030' &&
                  i + 1 < bytes.length &&
                  bytes[i + 1] >= 48 &&
                  bytes[i + 1] <= 57
            ? 4
            : 2;
        if (i + size > bytes.length) break;
        legacyStarts.add(i);
        i += size;
        continue;
      } else if (encoding == 'utf8') {
        size = a < 128
            ? 1
            : a >= 0xc2 && a <= 0xdf
            ? 2
            : a >= 0xe0 && a <= 0xef
            ? 3
            : a >= 0xf0 && a <= 0xf4
            ? 4
            : 0;
        if (size == 0) throw const FormatException('utf8');
        if (i + size > bytes.length) break;
        scalar = a & (size == 1 ? 127 : (1 << (7 - size)) - 1);
        for (var j = 1; j < size; j++) {
          final b = bytes[i + j];
          if (b & 0xc0 != 0x80) throw const FormatException('utf8');
          scalar = scalar << 6 | (b & 63);
        }
        if ((size == 2 && scalar < 128) ||
            (size == 3 && scalar < 2048) ||
            (size == 4 && scalar < 65536)) {
          throw const FormatException('utf8_overlong');
        }
      } else if (encoding == 'utf16le' || encoding == 'utf16be') {
        size = 2;
        if (i + 2 > bytes.length) break;
        int unit(int n) => encoding == 'utf16le'
            ? bytes[n] | bytes[n + 1] << 8
            : bytes[n] << 8 | bytes[n + 1];
        scalar = unit(i);
        if (scalar >= 0xd800 && scalar <= 0xdbff) {
          size = 4;
          if (i + 4 > bytes.length) break;
          final low = unit(i + 2);
          if (low < 0xdc00 || low > 0xdfff) {
            throw const FormatException('utf16');
          }
          scalar = 0x10000 + ((scalar - 0xd800) << 10) + low - 0xdc00;
        }
      } else {
        throw const FormatException('txt_encoding');
      }
      if (scalar == 0 ||
          scalar > 0x10ffff ||
          (scalar >= 0xd800 && scalar <= 0xdfff)) {
        throw const FormatException('scalar');
      }
      i += size;
      out.add(Scalar(scalar, _offset + start, _offset + i));
    }
    if (legacy && i > begin) {
      final input = Uint8List.sublistView(bytes, begin, i);
      final decoded = MacLegacyCodec.convert(input, encoding, 'UTF-32LE');
      final back = MacLegacyCodec.convert(decoded, 'UTF-32LE', encoding);
      if (back.length != input.length ||
          decoded.length != legacyStarts.length * 4) {
        throw const FormatException('legacy_mapping');
      }
      for (var j = 0; j < back.length; j++) {
        if (back[j] != input[j]) {
          throw const FormatException('legacy_roundtrip');
        }
      }
      final data = ByteData.sublistView(decoded);
      for (var j = 0; j < legacyStarts.length; j++) {
        final scalar = data.getUint32(j * 4, Endian.little);
        if (scalar == 0 ||
            scalar > 0x10ffff ||
            (scalar >= 0xd800 && scalar <= 0xdfff)) {
          throw const FormatException('legacy_scalar');
        }
        out.add(
          Scalar(
            scalar,
            _offset + legacyStarts[j],
            _offset + (j + 1 < legacyStarts.length ? legacyStarts[j + 1] : i),
          ),
        );
      }
    }
    _tail = bytes.sublist(i);
    _offset += i;
    if (last && _tail.isNotEmpty) {
      throw const FormatException('truncated_encoding');
    }
    return out;
  }
}

final class Newlines {
  Scalar? _cr;
  Iterable<Scalar> add(Iterable<Scalar> values, {bool last = false}) sync* {
    for (final v in values) {
      if (_cr case final cr?) {
        _cr = null;
        yield Scalar(10, cr.start, v.value == 10 ? v.end : cr.end);
        if (v.value == 10) continue;
      }
      if (v.value == 13) {
        _cr = v;
      } else {
        yield v;
      }
    }
    if (last) {
      if (_cr case final cr?) {
        _cr = null;
        yield Scalar(10, cr.start, cr.end);
      }
    }
  }
}
