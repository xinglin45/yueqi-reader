import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:xml/xml.dart';

import '../../domain/epub.dart';
import '../../domain/importing.dart';
import '../../domain/jobs.dart';
import '../importing/epub_archive.dart';

const epubParser = 'epub-v1';
const epubXhtml = 'http://www.w3.org/1999/xhtml';

/// A cancellable worker owns bounded decompression, XML and sanitization.
/// Only a small descriptor crosses back; chapter text/resources remain in the
/// private, disposable session directory, not the permanent imported objects.
Future<Map<String, dynamic>> loadEpub(
  String path,
  String output,
  String session,
  JobContext job,
) async {
  final port = ReceivePort(), done = Completer<Map<String, dynamic>>();
  SendPort? control;
  final sub = port.listen((dynamic value) {
    if (done.isCompleted) return;
    if (value is SendPort) {
      control = value;
    } else if (value is double) {
      job.report(value);
    } else if (value is Map) {
      if (value['error'] == 'cancelled') {
        done.completeError(const JobCancelled());
      } else if (value['error'] is String) {
        done.completeError(
          EpubFailure(EpubIssue.values.byName(value['error'] as String)),
        );
      } else {
        done.complete(Map<String, dynamic>.from(value));
      }
    } else if (value is List) {
      done.completeError(const EpubFailure(EpubIssue.corrupt));
    }
  });
  final timer = Timer.periodic(const Duration(milliseconds: 20), (_) {
    if (job.isCancelled) control?.send('cancel');
  });
  Isolate? worker;
  try {
    job.checkCancelled();
    worker = await Isolate.spawn(_worker, [
      port.sendPort,
      path,
      output,
      session,
    ], onError: port.sendPort);
    final result = await done.future;
    job.checkCancelled();
    return result;
  } finally {
    timer.cancel();
    await sub.cancel();
    port.close();
    worker?.kill(priority: Isolate.immediate);
  }
}

void _worker(List<dynamic> args) async {
  final reply = args[0] as SendPort, control = ReceivePort();
  var cancelled = false;
  control.listen((_) => cancelled = true);
  reply.send(control.sendPort);
  try {
    reply.send(
      await buildEpub(
        args[1] as String,
        args[2] as String,
        args[3] as String,
        check: () {
          if (cancelled) throw const JobCancelled();
        },
        progress: reply.send,
      ),
    );
  } on JobCancelled {
    reply.send({'error': 'cancelled'});
  } on EpubFailure catch (e) {
    reply.send({'error': e.issue.name});
  } on ImportFailure catch (e) {
    reply.send({
      'error': e.issue == ImportIssue.tooLarge ? 'limit' : 'corrupt',
    });
  } catch (_) {
    reply.send({'error': 'corrupt'});
  } finally {
    control.close();
  }
}

XmlDocument epubXml(Uint8List bytes, {int budget = 200000}) {
  final text = utf8
      .decode(bytes)
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n');
  if (text.toUpperCase().contains('<!DOCTYPE') ||
      text.toUpperCase().contains('<!ENTITY')) {
    throw const EpubFailure(EpubIssue.unsupported);
  }
  final doc = XmlDocument.parse(text), stack = <(XmlNode, int)>[(doc, 0)];
  var count = 0;
  while (stack.isNotEmpty) {
    final (node, depth) = stack.removeLast();
    if (++count > budget || depth > 64) {
      throw const EpubFailure(EpubIssue.limit);
    }
    for (final child in node.children) {
      stack.add((child, depth + 1));
    }
  }
  return doc;
}

Iterable<XmlElement> elements(XmlNode node, String name) =>
    node.descendants.whereType<XmlElement>().where((e) => e.name.local == name);
String shortText(String text) =>
    String.fromCharCodes(text.trim().runes.take(200));

/// Canonical book path + decoded fragment, with exactly one percent decoding.
/// Traversal within the book is allowed; traversal outside it is rejected.
(String, String) epubHref(String base, String href) {
  final uri = Uri.parse(href);
  if (uri.hasScheme ||
      uri.hasAuthority ||
      uri.hasQuery ||
      href.contains('\\')) {
    throw const EpubFailure(EpubIssue.unsupported);
  }
  final fragment = uri.fragment;
  if (fragment.length > 512 || fragment.contains(RegExp(r'[\x00-\x1f\x7f%]'))) {
    throw const EpubFailure(EpubIssue.unsupported);
  }
  final path = uri.path.isEmpty
      ? base
      : EpubArchive.resolveHref(base, uri.path);
  return (path, fragment);
}

Future<Map<String, dynamic>> buildEpub(
  String path,
  String output,
  String session, {
  required void Function() check,
  required void Function(double) progress,
}) async {
  if (!RegExp(r'^s[a-f0-9]{32}$').hasMatch(session)) {
    throw const EpubFailure(EpubIssue.corrupt);
  }
  final sourceDigest = (await sha256.bind(File(path).openRead()).first)
      .toString();
  final archive = await EpubArchive.open(path);
  check();
  if (archive.contains('META-INF/encryption.xml') ||
      archive.contains('META-INF/rights.xml')) {
    throw const EpubFailure(EpubIssue.encrypted);
  }
  final container = epubXml(
    await archive.read('META-INF/container.xml', 128 * 1024),
    budget: 8192,
  );
  final roots = elements(container, 'rootfile').toList();
  if (roots.length != 1) throw const EpubFailure(EpubIssue.unsupported);
  final opf = EpubArchive.safePath(
    roots.single.getAttribute('full-path') ?? '',
  );
  final package = epubXml(await archive.read(opf, 512 * 1024), budget: 20000);
  if (package.rootElement.name.local != 'package' ||
      package.rootElement.name.namespaceUri != 'http://www.idpf.org/2007/opf') {
    throw const EpubFailure(EpubIssue.corrupt);
  }
  final version = package.rootElement.getAttribute('version');
  if (version != '2.0' && version != '3.0') {
    throw const EpubFailure(EpubIssue.unsupported);
  }
  if (elements(package, 'meta').any(
    (e) =>
        (e.getAttribute('property') == 'rendition:layout' &&
            e.innerText.trim() == 'pre-paginated') ||
        (e.getAttribute('name') == 'fixed-layout' &&
            e.getAttribute('content') == 'true'),
  )) {
    throw const EpubFailure(EpubIssue.fixedLayout);
  }
  final items = <String, Map<String, dynamic>>{},
      byPath = <String, Map<String, dynamic>>{};
  const allowed = {
    'application/xhtml+xml',
    'application/x-dtbncx+xml',
    'text/css',
    'image/png',
    'image/jpeg',
    'font/ttf',
    'font/otf',
    'font/woff',
    'font/woff2',
    'application/vnd.ms-opentype',
    'application/font-sfnt',
    'application/font-woff',
    'text/plain',
  };
  final warnings = <String>{};
  for (final e in elements(package, 'item')) {
    final id = e.getAttribute('id') ?? '',
        href = e.getAttribute('href') ?? '',
        mime = e.getAttribute('media-type') ?? '';
    final target = epubHref(opf, href);
    if (id.isEmpty ||
        id.length > 512 ||
        href.isEmpty ||
        target.$2.isNotEmpty ||
        items.containsKey(id) ||
        byPath.containsKey(target.$1)) {
      throw const EpubFailure(EpubIssue.corrupt);
    }
    if (!archive.contains(target.$1)) {
      throw const EpubFailure(EpubIssue.missingResource);
    }
    if (!allowed.contains(mime)) {
      if (mime == 'application/javascript' || mime == 'text/javascript') {
        warnings.add('script_removed');
      } else {
        throw const EpubFailure(EpubIssue.unsupported);
      }
    }
    final item = <String, dynamic>{
      'id': id,
      'path': target.$1,
      'mime': mime,
      'properties': e.getAttribute('properties') ?? '',
      'resource': 'r${items.length}',
    };
    items[id] = item;
    byPath[target.$1] = item;
  }
  final refs = elements(package, 'itemref').toList();
  if (refs.isEmpty || refs.length > 512) {
    throw const EpubFailure(EpubIssue.limit);
  }
  final spine = <Map<String, dynamic>>[], seenSpine = <String>{};
  for (final ref in refs) {
    final item = items[ref.getAttribute('idref')];
    if (item == null ||
        item['mime'] != 'application/xhtml+xml' ||
        !seenSpine.add(item['path'] as String)) {
      throw const EpubFailure(EpubIssue.unsupported);
    }
    spine.add({
      'ordinal': spine.length,
      'href': item['path'],
      'resource': item['resource'],
      'title': '第${spine.length + 1}节',
      'images': <String>[],
    });
  }
  final documents = <String, Map<String, dynamic>>{},
      resources = <String, Map<String, dynamic>>{};
  var written = 0, imagePixels = 0;
  await Directory(output).create(recursive: true);
  Future<void> write(String name, Uint8List bytes) async {
    check();
    written += bytes.length;
    if (written > 192 * 1024 * 1024) throw const EpubFailure(EpubIssue.limit);
    await File('$output/$name').writeAsBytes(bytes, flush: true);
  }

  String url(String base, String href, Set<String> mimeTypes) {
    final (target, fragment) = epubHref(base, href);
    final item = byPath[target];
    if (item == null) throw const EpubFailure(EpubIssue.missingResource);
    if (!mimeTypes.contains(item['mime'])) {
      throw const EpubFailure(EpubIssue.unsupported);
    }
    return 'reader-book://$session/${item['resource']}${fragment.isEmpty ? '' : '#${Uri.encodeComponent(fragment)}'}';
  }

  String css(String raw, String base) {
    if (raw.length > 512 * 1024 ||
        raw.contains('\\') ||
        RegExp(
          r'@import|expression\s*\(|-moz-binding|behavior\s*:|writing-mode\s*:\s*vertical',
          caseSensitive: false,
        ).hasMatch(raw)) {
      throw const EpubFailure(EpubIssue.unsupported);
    }
    final pattern = RegExp(
      r'''url\(\s*(?:"([^"]*)"|'([^']*)'|([^'"()\s]+))\s*\)''',
      caseSensitive: false,
    );
    if (pattern.allMatches(raw).length !=
        RegExp(r'url\s*\(', caseSensitive: false).allMatches(raw).length) {
      throw const EpubFailure(EpubIssue.unsupported);
    }
    return raw.replaceAllMapped(pattern, (match) {
      final value = match[1] ?? match[2] ?? match[3]!;
      if (_external(value)) {
        warnings.add('external_blocked');
        return 'none';
      }
      return 'url("${url(base, value, {'image/png', 'image/jpeg', 'font/ttf', 'font/otf', 'font/woff', 'font/woff2', 'application/vnd.ms-opentype', 'application/font-sfnt', 'application/font-woff'})}")';
    });
  }

  const tags = {
    'html',
    'head',
    'title',
    'meta',
    'link',
    'style',
    'body',
    'h1',
    'h2',
    'h3',
    'h4',
    'h5',
    'h6',
    'p',
    'strong',
    'b',
    'em',
    'i',
    'u',
    's',
    'a',
    'img',
    'figure',
    'figcaption',
    'blockquote',
    'ruby',
    'rt',
    'rp',
    'nav',
    'ol',
    'li',
    'span',
    'div',
    'section',
    'article',
    'main',
    'header',
    'footer',
    'aside',
    'ul',
    'br',
    'hr',
    'code',
    'pre',
    'sub',
    'sup',
    'small',
    'abbr',
    'cite',
    'q',
    'dl',
    'dt',
    'dd',
    'table',
    'caption',
    'colgroup',
    'col',
    'thead',
    'tbody',
    'tfoot',
    'tr',
    'td',
    'th',
    'wbr',
    'address',
  };
  final chapterFiles = <String, Map<String, Object>>{};
  final navTrees = <String, XmlDocument>{};
  final rawLinks = <(String, String)>[];
  for (final (index, item) in items.values.indexed) {
    check();
    final mime = item['mime'] as String,
        name = item['path'] as String,
        rid = item['resource'] as String;
    final budget = mime == 'application/xhtml+xml'
        ? 2 * 1024 * 1024
        : mime == 'text/css'
        ? 512 * 1024
        : 8 * 1024 * 1024;
    final bytes = await archive.read(name, budget);
    var payload = bytes;
    if (mime == 'application/javascript' || mime == 'text/javascript') {
      continue;
    }
    if (mime == 'application/xhtml+xml') {
      final tree = epubXml(bytes),
          all = [
            tree.rootElement,
            ...tree.rootElement.descendants.whereType<XmlElement>(),
          ];
      if ((item['properties'] as String).split(' ').contains('nav')) {
        navTrees[name] = tree.copy();
      }
      for (final a in elements(tree, 'a')) {
        final href = a.getAttribute('href');
        if (href != null) rawLinks.add((name, href));
        if (rawLinks.length > 20000) throw const EpubFailure(EpubIssue.limit);
      }
      final ids = <String>{};
      for (final e in all) {
        final tag = e.name.local;
        if (tag == 'script' || tag == 'base') {
          e.parent?.children.remove(e);
          warnings.add('script_removed');
          continue;
        }
        if (!tags.contains(tag) || e.name.namespaceUri != epubXhtml) {
          throw const EpubFailure(EpubIssue.unsupported);
        }
        final id = e.getAttribute('id');
        if (id != null && (id.length > 512 || !ids.add(id))) {
          throw const EpubFailure(EpubIssue.corrupt);
        }
        for (final a in e.attributes.toList()) {
          final attr = a.name.local.toLowerCase();
          if (attr.startsWith('on') ||
              attr.startsWith('data-rk') ||
              {
                'srcdoc',
                'srcset',
                'action',
                'formaction',
                'ping',
                'download',
                'target',
                'http-equiv',
                'contenteditable',
                'autofocus',
              }.contains(attr)) {
            e.attributes.remove(a);
            warnings.add('active_attributes_removed');
          }
          if (a.name.prefix == 'xml' && attr == 'base') {
            e.attributes.remove(a);
          }
        }
        if (tag == 'meta') {
          e.parent?.children.remove(e);
          continue;
        }
        final inline = e.getAttribute('style');
        if (inline != null) e.setAttribute('style', css(inline, name));
        if (tag == 'style') {
          final styled = css(e.innerText, name);
          e.children
            ..clear()
            ..add(XmlText(styled));
        }
        for (final attr in ['src', 'href']) {
          final value = e.getAttribute(attr);
          if (value == null) continue;
          if (_external(value)) {
            e.removeAttribute(attr);
            warnings.add('external_blocked');
            continue;
          }
          Set<String>? expected;
          if (tag == 'a' && attr == 'href') {
            expected = {'application/xhtml+xml'};
          }
          if (tag == 'img' && attr == 'src') {
            expected = {'image/png', 'image/jpeg'};
          }
          if (tag == 'link' &&
              attr == 'href' &&
              e.getAttribute('rel')?.toLowerCase() == 'stylesheet') {
            expected = {'text/css'};
          }
          if (expected == null) {
            e.removeAttribute(attr);
            warnings.add('active_attributes_removed');
          } else {
            e.setAttribute(attr, url(name, value, expected));
          }
        }
      }
      final head = elements(tree, 'head').singleOrNull,
          body = elements(tree, 'body').singleOrNull;
      if (head == null || body == null) {
        throw const EpubFailure(EpubIssue.corrupt);
      }
      final blocks = <String, String>{},
          fragmentsAt = <String, int>{},
          images = <String>[];
      void visit(XmlNode node, {bool ignored = false, bool pre = false}) {
        if (node is XmlElement) {
          final tag = node.name.local, id = node.getAttribute('id');
          if (id != null) fragmentsAt[id] = blocks.length;
          if (tag == 'img') {
            final source = node.getAttribute('src');
            if (source != null) images.add(Uri.parse(source).path.substring(1));
          }
          final skip =
              ignored ||
              {'rt', 'rp', 'style', 'script'}.contains(tag) ||
              node.getAttribute('aria-hidden') == 'true';
          for (final child in node.children.toList()) {
            visit(child, ignored: skip, pre: pre || tag == 'pre');
          }
        } else if ((node is XmlText || node is XmlCDATA) &&
            !ignored &&
            (pre || node.value!.trim().isNotEmpty)) {
          final original = node.value!, replacement = <XmlNode>[];
          var start = 0;
          while (start < original.length) {
            var end = (start + 2048).clamp(0, original.length);
            if (end < original.length &&
                original.codeUnitAt(end - 1) >= 0xd800 &&
                original.codeUnitAt(end - 1) <= 0xdbff) {
              end--;
            }
            final text = original.substring(start, end),
                key = 'b${blocks.length}';
            if (blocks.length >= 50000) {
              throw const EpubFailure(EpubIssue.limit);
            }
            blocks[key] = text;
            replacement.add(
              XmlElement(
                XmlName('span'),
                [XmlAttribute(XmlName('data-rk'), key)],
                [XmlText(text)],
              ),
            );
            start = end;
          }
          final parent = node.parent!, at = parent.children.indexOf(node);
          parent.children.replaceRange(at, at + 1, replacement);
        }
      }

      visit(body);
      // Image-only chapters have an accessible, host-owned text anchor.
      if (blocks.isEmpty) {
        blocks['b0'] = '本节为图片内容。';
        body.children.add(
          XmlElement(
            XmlName('p'),
            [XmlAttribute(XmlName('data-rk'), 'b0')],
            [XmlText(blocks['b0']!)],
          ),
        );
      }
      final keys = blocks.keys.toList(), fragments = <String, String>{};
      for (final e in fragmentsAt.entries) {
        fragments[e.key] = keys[e.value.clamp(0, keys.length - 1)];
      }
      final chapter = {'blocks': blocks, 'fragments': fragments};
      documents[name] = {'fragments': fragments};
      final sp = spine.where((s) => s['href'] == name).firstOrNull;
      if (sp != null) {
        sp['title'] = shortText(
          elements(body, 'h1').firstOrNull?.innerText ??
              elements(head, 'title').firstOrNull?.innerText ??
              sp['title'] as String,
        );
        sp['images'] = images.toSet().toList();
        final canonical = Uint8List.fromList(utf8.encode(jsonEncode(chapter)));
        await write('c${sp['ordinal']}.json', canonical);
        chapterFiles['c${sp['ordinal']}'] = {
          'bytes': canonical.length,
          'sha256': sha256.convert(canonical).toString(),
        };
      }
      final csp =
          "default-src 'none'; img-src reader-book://$session; style-src 'unsafe-inline' reader-book://$session; font-src reader-book://$session; script-src 'none'; connect-src 'none'; frame-src 'none'; object-src 'none'; base-uri 'none'; form-action 'none'";
      head.children.insert(
        0,
        XmlElement(XmlName('meta'), [
          XmlAttribute(XmlName('http-equiv'), 'Content-Security-Policy'),
          XmlAttribute(XmlName('content'), csp),
        ]),
      );
      payload = Uint8List.fromList(utf8.encode(tree.toXmlString()));
    } else if (mime == 'text/css') {
      payload = Uint8List.fromList(utf8.encode(css(utf8.decode(bytes), name)));
    } else if (mime == 'image/png' || mime == 'image/jpeg') {
      imagePixels += _image(bytes, mime);
      if (imagePixels > 32 * 1024 * 1024) {
        throw const EpubFailure(EpubIssue.limit);
      }
    } else if (mime.startsWith('font/') ||
        mime == 'application/vnd.ms-opentype' ||
        mime == 'application/font-sfnt' ||
        mime == 'application/font-woff') {
      if (bytes.length < 12 ||
          ![
            0x00010000,
            0x4f54544f,
            0x774f4646,
            0x774f4632,
            0x74746366,
          ].contains(ByteData.sublistView(bytes).getUint32(0))) {
        throw const EpubFailure(EpubIssue.corrupt);
      }
    }
    await write(rid, payload);
    resources[rid] = {
      'mime': mime,
      'bytes': payload.length,
      'sha256': sha256.convert(payload).toString(),
    };
    progress((index + 1) / items.length);
  }
  // Resolve both EPUB3 nav and EPUB2 NCX to the same spine/fragment model.
  final toc = <Map<String, dynamic>>[];
  void entry(String title, String base, String href, int depth) {
    if (toc.length >= 4096 || depth > 32) {
      throw const EpubFailure(EpubIssue.limit);
    }
    if (_external(href)) {
      warnings.add('external_blocked');
      return;
    }
    final (target, fragment) = epubHref(base, href);
    final ordinal = spine.indexWhere((s) => s['href'] == target);
    if (ordinal < 0 ||
        (fragment.isNotEmpty &&
            !(documents[target]!['fragments'] as Map).containsKey(fragment))) {
      throw const EpubFailure(EpubIssue.missingResource);
    }
    toc.add({
      'title': shortText(title),
      'spine': ordinal,
      'fragment': fragment,
      'depth': depth,
    });
  }

  final nav = items.values
      .where((i) => (i['properties'] as String).split(' ').contains('nav'))
      .toList();
  if (version == '3.0' && nav.length == 1) {
    final tree = navTrees[nav.single['path']]!;
    final tocNav = elements(tree, 'nav')
        .where(
          (e) =>
              (e.getAttribute(
                        'type',
                        namespace: 'http://www.idpf.org/2007/ops',
                      ) ??
                      '')
                  .split(' ')
                  .contains('toc'),
        )
        .firstOrNull;
    if (tocNav == null) throw const EpubFailure(EpubIssue.corrupt);
    for (final a in elements(tocNav, 'a')) {
      var depth = 0;
      for (var p = a.parent; p != null && p != tocNav; p = p.parent) {
        if (p is XmlElement && p.name.local == 'ol') depth++;
      }
      entry(
        a.innerText,
        nav.single['path'] as String,
        a.getAttribute('href') ?? '',
        depth - 1,
      );
    }
  } else if (version == '2.0') {
    final ncxId = elements(package, 'spine').single.getAttribute('toc'),
        ncx = items[ncxId];
    if (ncx == null || ncx['mime'] != 'application/x-dtbncx+xml') {
      throw const EpubFailure(EpubIssue.unsupported);
    }
    final tree = epubXml(await archive.read(ncx['path'] as String, 512 * 1024));
    for (final point in elements(tree, 'navPoint')) {
      var depth = 0;
      for (var p = point.parent; p != null; p = p.parent) {
        if (p is XmlElement && p.name.local == 'navPoint') depth++;
      }
      entry(
        elements(point, 'text').firstOrNull?.innerText ?? '',
        ncx['path'] as String,
        elements(point, 'content').firstOrNull?.getAttribute('src') ?? '',
        depth,
      );
    }
  } else {
    throw const EpubFailure(EpubIssue.unsupported);
  }
  if (toc.isEmpty) {
    for (final s in spine) {
      toc.add({
        'title': s['title'],
        'spine': s['ordinal'],
        'fragment': '',
        'depth': 0,
      });
    }
  }
  // Validate all internal hyperlinks and their fragments, including non-TOC ones.
  for (final (base, href) in rawLinks) {
    if (_external(href)) continue;
    final (target, fragment) = epubHref(base, href);
    if (!documents.containsKey(target) ||
        (fragment.isNotEmpty &&
            !(documents[target]!['fragments'] as Map).containsKey(fragment))) {
      throw const EpubFailure(EpubIssue.missingResource);
    }
  }
  check();
  if ((await sha256.bind(File(path).openRead()).first).toString() !=
      sourceDigest) {
    throw const EpubFailure(EpubIssue.corrupt);
  }
  check();
  return {
    'source_digest': sourceDigest,
    'chapters': chapterFiles,
    'spine': spine,
    'toc': toc,
    'resources': resources,
    'warnings': warnings.toList(),
  };
}

bool _external(String value) {
  final uri = Uri.tryParse(value);
  return uri == null ||
      uri.hasScheme ||
      uri.hasAuthority ||
      value.startsWith('//');
}

int _image(Uint8List bytes, String mime) {
  var width = 0, height = 0;
  final data = ByteData.sublistView(bytes);
  if (mime == 'image/png') {
    if (bytes.length < 33 ||
        base64.encode(bytes.sublist(0, 8)) != 'iVBORw0KGgo=' ||
        ascii.decode(bytes.sublist(12, 16)) != 'IHDR') {
      throw const EpubFailure(EpubIssue.corrupt);
    }
    width = data.getUint32(16);
    height = data.getUint32(20);
  } else {
    if (bytes.length < 4 || bytes[0] != 255 || bytes[1] != 216) {
      throw const EpubFailure(EpubIssue.corrupt);
    }
    var pos = 2;
    while (pos + 4 < bytes.length) {
      if (bytes[pos++] != 255) throw const EpubFailure(EpubIssue.corrupt);
      while (pos < bytes.length && bytes[pos] == 255) {
        pos++;
      }
      if (pos + 3 >= bytes.length) break;
      final tag = bytes[pos++], size = data.getUint16(pos);
      if (size < 2 || pos + size > bytes.length) {
        throw const EpubFailure(EpubIssue.corrupt);
      }
      if ({0xc0, 0xc1, 0xc2}.contains(tag) && size >= 8) {
        height = data.getUint16(pos + 3);
        width = data.getUint16(pos + 5);
        break;
      }
      pos += size;
    }
  }
  if (width <= 0 ||
      height <= 0 ||
      width > 8192 ||
      height > 8192 ||
      width * height > 32 * 1024 * 1024) {
    throw const EpubFailure(EpubIssue.limit);
  }
  return width * height;
}
