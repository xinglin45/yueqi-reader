import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../../domain/importing.dart';

/// Shared OCF/ZIP boundary. Resources are CRC-checked and expanded with budgets;
/// no ZIP paths are ever used as output filesystem paths.
final class EpubArchive {
  EpubArchive._(this.path, this._entries);
  final String path;
  final Map<String, _Entry> _entries;
  static const maxExpanded = 128 * 1024 * 1024;
  Iterable<String> get names => _entries.keys;
  int size(String name) => _entries[name]?.size ?? -1;
  bool contains(String name) => _entries.containsKey(name);
  static Future<EpubArchive> open(String path) async {
    final file = await File(path).open();
    try {
      final length = await file.length();
      if (length > 64 * 1024 * 1024) {
        throw const ImportFailure(ImportIssue.tooLarge);
      }
      if (length < 22) throw const ImportFailure(ImportIssue.corrupt);
      final tailStart = length > 65557 ? length - 65557 : 0;
      await file.setPosition(tailStart);
      final tail = await file.read(length - tailStart);
      var end = -1;
      for (var i = tail.length - 22; i >= 0; i--) {
        if (_u32(tail, i) == 0x06054b50 &&
            i + 22 + _u16(tail, i + 20) == tail.length) {
          end = i;
          break;
        }
      }
      if (end < 0 || _u16(tail, end + 4) != 0 || _u16(tail, end + 6) != 0) {
        throw const ImportFailure(ImportIssue.corrupt);
      }
      final count = _u16(tail, end + 10),
          centralSize = _u32(tail, end + 12),
          centralOffset = _u32(tail, end + 16);
      if (count == 0 ||
          count > 4096 ||
          count != _u16(tail, end + 8) ||
          centralSize > 4 * 1024 * 1024 ||
          centralOffset + centralSize != tailStart + end) {
        throw const ImportFailure(ImportIssue.unsupported);
      }
      await file.setPosition(centralOffset);
      final central = await file.read(centralSize);
      if (central.length != centralSize) {
        throw const ImportFailure(ImportIssue.corrupt);
      }
      final entries = <String, _Entry>{};
      var offset = 0, total = 0;
      final intervals = <(int, int)>[];
      for (var n = 0; n < count; n++) {
        if (offset + 46 > central.length ||
            _u32(central, offset) != 0x02014b50) {
          throw const ImportFailure(ImportIssue.corrupt);
        }
        final flags = _u16(central, offset + 8),
            method = _u16(central, offset + 10),
            packed = _u32(central, offset + 20),
            size = _u32(central, offset + 24);
        final nameLength = _u16(central, offset + 28),
            extra = _u16(central, offset + 30),
            comment = _u16(central, offset + 32),
            local = _u32(central, offset + 42);
        final next = offset + 46 + nameLength + extra + comment;
        if (next > central.length ||
            nameLength == 0 ||
            _u16(central, offset + 34) != 0 ||
            flags & 1 != 0 ||
            (method != 0 && method != 8) ||
            size > 16 * 1024 * 1024 ||
            packed > 64 * 1024 * 1024 ||
            local + 30 >= centralOffset) {
          throw const ImportFailure(ImportIssue.unsupported);
        }
        final name = utf8.decode(
          central.sublist(offset + 46, offset + 46 + nameLength),
        );
        safePath(
          name.endsWith('/') ? name.substring(0, name.length - 1) : name,
        );
        if (entries.containsKey(name)) {
          throw const ImportFailure(ImportIssue.corrupt);
        }
        final unixMode = _u32(central, offset + 38) >> 16;
        if ((unixMode & 0xf000) == 0xa000 || (method == 0 && packed != size)) {
          throw const ImportFailure(ImportIssue.corrupt);
        }
        if (size > 1024 * 1024 && size > packed * 200) {
          throw const ImportFailure(ImportIssue.tooLarge);
        }
        total += size;
        if (total > maxExpanded) {
          throw const ImportFailure(ImportIssue.tooLarge);
        }
        await file.setPosition(local);
        final header = await file.read(30);
        if (header.length != 30 ||
            _u32(header, 0) != 0x04034b50 ||
            _u16(header, 6) != flags ||
            _u16(header, 8) != method) {
          throw const ImportFailure(ImportIssue.corrupt);
        }
        final localNameSize = _u16(header, 26),
            dataStart = local + 30 + localNameSize + _u16(header, 28);
        final localName = await file.read(localNameSize);
        if (utf8.decode(localName) != name ||
            dataStart + packed > centralOffset) {
          throw const ImportFailure(ImportIssue.corrupt);
        }
        intervals.add((local, dataStart + packed));
        entries[name] = _Entry(
          dataStart,
          packed,
          size,
          method,
          _u32(central, offset + 16),
        );
        offset = next;
      }
      if (offset != central.length) {
        throw const ImportFailure(ImportIssue.corrupt);
      }
      intervals.sort((a, b) => a.$1.compareTo(b.$1));
      for (var i = 1; i < intervals.length; i++) {
        if (intervals[i].$1 < intervals[i - 1].$2) {
          throw const ImportFailure(ImportIssue.corrupt);
        }
      }
      final mime = entries['mimetype'];
      if (mime == null ||
          mime.method != 0 ||
          intervals.first.$1 != 0 ||
          mime.offset != 38) {
        throw const ImportFailure(ImportIssue.corrupt);
      }
      final archive = EpubArchive._(path, entries);
      if (ascii.decode(await archive.read('mimetype', 32)) !=
          'application/epub+zip') {
        throw const ImportFailure(ImportIssue.corrupt);
      }
      return archive;
    } on ImportFailure {
      rethrow;
    } catch (_) {
      throw const ImportFailure(ImportIssue.corrupt);
    } finally {
      await file.close();
    }
  }

  Future<Uint8List> read(String name, int budget, {bool capture = true}) async {
    final entry = _entries[name];
    if (entry == null ||
        entry.size > budget ||
        entry.packed > (budget * 2 + 128)) {
      throw const ImportFailure(ImportIssue.corrupt);
    }
    Stream<List<int>> compressed() async* {
      await for (final chunk in File(
        path,
      ).openRead(entry.offset, entry.offset + entry.packed)) {
        for (var i = 0; i < chunk.length; i += 256) {
          yield chunk.sublist(
            i,
            i + 256 < chunk.length ? i + 256 : chunk.length,
          );
        }
      }
    }

    final chunks = entry.method == 0
        ? compressed()
        : compressed().transform(ZLibDecoder(raw: true));
    final out = BytesBuilder(copy: false);
    var seen = 0, crc = 0xffffffff;
    await for (final chunk in chunks) {
      seen += chunk.length;
      if (seen > budget || seen > entry.size) {
        throw const ImportFailure(ImportIssue.tooLarge);
      }
      if (capture) out.add(chunk);
      for (final byte in chunk) {
        crc = (crc >> 8) ^ _crcTable[(crc ^ byte) & 255];
      }
    }
    final bytes = out.takeBytes();
    if (seen != entry.size || (crc ^ 0xffffffff) != entry.crc) {
      throw const ImportFailure(ImportIssue.corrupt);
    }
    return bytes;
  }

  static String safePath(String value) {
    if (value.isEmpty ||
        value.contains('\\') ||
        value.contains(RegExp(r'[\x00-\x1f\x7f%]')) ||
        value.contains(':') ||
        value.contains('?') ||
        value.contains('#') ||
        value.startsWith('/') ||
        value.split('/').any((s) => s == '..' || s == '.' || s.isEmpty)) {
      throw const ImportFailure(ImportIssue.corrupt);
    }
    return value;
  }

  static int _u16(List<int> b, int p) => b[p] | b[p + 1] << 8;
  static int _u32(List<int> b, int p) => _u16(b, p) | _u16(b, p + 2) << 16;
  static String resolveHref(String base, String href) {
    final decoded = Uri.decodeComponent(href);
    if (decoded.contains(':') ||
        decoded.contains('\\') ||
        decoded.startsWith('/') ||
        decoded.contains(RegExp(r'[\x00-\x1f\x7f%]'))) {
      throw const ImportFailure(ImportIssue.corrupt);
    }
    return safePath(
      p.posix.normalize(p.posix.join(p.posix.dirname(base), decoded)),
    );
  }

  static final _crcTable = List<int>.generate(256, (n) {
    var c = n;
    for (var i = 0; i < 8; i++) {
      c = (c & 1) != 0 ? (c >> 1) ^ 0xedb88320 : c >> 1;
    }
    return c;
  });
}

final class _Entry {
  const _Entry(this.offset, this.packed, this.size, this.method, this.crc);
  final int offset, packed, size, method, crc;
}
