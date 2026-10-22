import 'dart:convert';

import 'package:xml/xml.dart';

import '../../domain/importing.dart';
import 'epub_archive.dart';

/// Metadata inspection only. Rendering support is checked separately on open.
final class EpubInspector {
  static const maxExpanded = EpubArchive.maxExpanded;
  static Future<String> inspect(String path) async {
    try {
      final archive = await EpubArchive.open(path);
      if (archive.contains('META-INF/encryption.xml') ||
          archive.contains('META-INF/rights.xml')) {
        throw const ImportFailure(ImportIssue.unsupported);
      }
      for (final name in archive.names) {
        await archive.read(name, archive.size(name), capture: false);
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

      final container = xml(
        await archive.read('META-INF/container.xml', 128 * 1024),
      );
      final root = container.descendants
          .whereType<XmlElement>()
          .where((e) => e.name.local == 'rootfile')
          .firstOrNull;
      final opf = EpubArchive.safePath(root?.getAttribute('full-path') ?? '');
      final package = xml(await archive.read(opf, 128 * 1024));
      final manifest = <String, String>{};
      for (final item in package.descendants.whereType<XmlElement>().where(
        (e) => e.name.local == 'item',
      )) {
        final id = item.getAttribute('id'), href = item.getAttribute('href');
        if (id == null || href == null || manifest.containsKey(id)) {
          throw const ImportFailure(ImportIssue.corrupt);
        }
        final target = EpubArchive.resolveHref(opf, href);
        if (!archive.contains(target)) {
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
    }
  }

  static String safePath(String value) => EpubArchive.safePath(value);
  static String resolveHref(String base, String href) =>
      EpubArchive.resolveHref(base, href);
}
