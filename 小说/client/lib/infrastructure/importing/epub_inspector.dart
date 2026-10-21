import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

import '../../domain/importing.dart';

/// Bounded ZIP/OCF metadata inspection only; never extract or execute content.
/// ZIP64/multidisk/encrypted packages and unsupported compression are rejected.
final class EpubInspector {
  static const maxExpanded = 128 * 1024 * 1024;
  static Future<String> inspect(String path) async {
    final file = await File(path).open();
    try {
      final length = await file.length();
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
      if (entries.containsKey('META-INF/encryption.xml') ||
          entries.containsKey('META-INF/rights.xml')) {
        throw const ImportFailure(ImportIssue.unsupported);
      }
      Future<Uint8List> read(
        String name,
        int budget, {
        bool capture = true,
      }) async {
        final entry = entries[name];
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

      for (final item in entries.entries) {
        await read(item.key, item.value.size, capture: false);
      }
      final mime = entries['mimetype'];
      if (mime == null ||
          mime.method != 0 ||
          intervals.first.$1 != 0 ||
          mime.offset != 38 ||
          ascii.decode(await read('mimetype', 32)) != 'application/epub+zip') {
        throw const ImportFailure(ImportIssue.corrupt);
      }
      XmlDocument xml(List<int> bytes) {
        final text = utf8.decode(bytes);
        if (text.toUpperCase().contains('<!DOCTYPE') ||
            text.toUpperCase().contains('<!ENTITY') ||
            '<'.allMatches(text).length > 4096) {
          throw const ImportFailure(ImportIssue.unsupported);
        }
        final doc = XmlDocument.parse(text);
        final stack = <(XmlNode, int)>[(doc, 0)];
        var nodes = 0;
        while (stack.isNotEmpty) {
          final (node, depth) = stack.removeLast();
          if (depth > 64 || ++nodes > 8192) {
            throw const ImportFailure(ImportIssue.tooLarge);
          }
          for (final child in node.children) {
            stack.add((child, depth + 1));
          }
        }
        return doc;
      }

      final container = xml(await read('META-INF/container.xml', 128 * 1024));
      final root = container.descendants
          .whereType<XmlElement>()
          .where((e) => e.name.local == 'rootfile')
          .firstOrNull;
      final opf = safePath(root?.getAttribute('full-path') ?? '');
      final package = xml(await read(opf, 128 * 1024));
      final manifest = <String, String>{};
      for (final item in package.descendants.whereType<XmlElement>().where(
        (e) => e.name.local == 'item',
      )) {
        final id = item.getAttribute('id'), href = item.getAttribute('href');
        if (id == null || href == null || manifest.containsKey(id)) {
          throw const ImportFailure(ImportIssue.corrupt);
        }
        final target = resolveHref(opf, href);
        if (!entries.containsKey(target)) {
          throw const ImportFailure(ImportIssue.corrupt);
        }
        manifest[id] = target;
      }
      final spine = package.descendants
          .whereType<XmlElement>()
          .where((e) => e.name.local == 'itemref')
          .toList();
      if (spine.isEmpty ||
          spine.any((e) => !manifest.containsKey(e.getAttribute('idref')))) {
        throw const ImportFailure(ImportIssue.corrupt);
      }
      final title =
          package.descendants
              .whereType<XmlElement>()
              .where((e) => e.name.local == 'title')
              .firstOrNull
              ?.innerText
              .trim() ??
          '';
      return title.runes.take(200).map(String.fromCharCode).join();
    } on ImportFailure {
      rethrow;
    } catch (_) {
      throw const ImportFailure(ImportIssue.corrupt);
    } finally {
      await file.close();
    }
  }

  static String safePath(String value) {
    if (value.isEmpty ||
        value.contains('\\') ||
        value.contains('\u0000') ||
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
        decoded.contains('\u0000')) {
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
