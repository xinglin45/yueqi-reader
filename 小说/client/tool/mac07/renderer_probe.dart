import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:novel_app/app/dependencies.dart';
import 'package:novel_app/app/theme.dart';
import 'package:novel_app/domain/access.dart';
import 'package:novel_app/domain/epub.dart';
import 'package:novel_app/domain/importing.dart';
import 'package:novel_app/domain/jobs.dart';
import 'package:novel_app/infrastructure/epub/mac_epub_surface.dart';
import 'package:novel_app/infrastructure/platform_storage_locations.dart';
import 'package:path/path.dart' as p;
import 'package:platform_services/platform_services.dart';

JobContext job() => JobContext(id: 1, isCurrent: () => true, report: (_) {});

final class QaLocations implements StorageLocationProvider {
  @override
  Future<AppStorageLocations> locations() async {
    final system = await const SystemStorageLocations().locations();
    return AppStorageLocations(
      support: p.join(system.support, 'mac07-renderer-probe'),
      cache: p.join(system.cache, 'mac07-renderer-probe'),
    );
  }
}

/// Only the digest-checked bundled owned fixture. No user picker or arbitrary
/// file input is accepted by this diagnostic harness.
final class OwnedFiles implements DocumentAccess {
  OwnedFiles(this.file);
  final File file;
  @override
  Stream<List<FileGrant>> get incomingDocuments => const Stream.empty();
  @override
  Future<PlatformResult<List<FileGrant>>> chooseDocuments() async =>
      const PlatformSuccess([]);
  @override
  Future<PlatformResult<FileGrant?>> chooseDocument() async =>
      const PlatformSuccess(null);
  @override
  Stream<List<int>> readDocument(FileGrant grant) => file.openRead();
  @override
  Stream<List<int>> readDocumentRange(FileGrant grant, int start, int end) =>
      file.openRead(start, end);
  @override
  Future<void> retainGrant(FileGrant grant) async {}
  @override
  Future<void> releaseGrant(FileGrant grant) async {}
  @override
  Future<void> forgetGrant(FileGrant grant) async {}
  @override
  Future<PlatformResult<FileGrant>> restoreGrant(String id) async =>
      const PlatformUnavailable(PlatformFailure.unsupported);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final locations = await QaLocations().locations();
  await Directory(locations.support).create(recursive: true);
  final data = await rootBundle.load('assets/mac06/mountain-letter.epub'),
      bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  if (sha256.convert(bytes).toString() !=
      '3d6d0a4ee10305897ef708f43e76375433998025b1417f0b655cb431090df701') {
    throw StateError('owned_fixture_digest');
  }
  final source = await File(p.join(locations.support, 'owned-fixture.epub'))
      .writeAsBytes(bytes);
  final deps = await AppDependencies.open(
    QaLocations(),
    documents: OwnedFiles(source),
  );
  final preview = await deps.importer!.prepare(
    const FileGrant(id: 'owned', displayName: '自产探针.epub'),
    job(),
  );
  final book = await deps.importer!.commit(
    preview.id,
    mode: ImportMode.managed,
    rating: RatingLevel.general,
    job: job(),
  );
  final session = await deps.epub!.open(book.bookId, job()),
      chapter = await deps.epub!.chapter(session, 0, job());
  runApp(
    RendererProbe(
      deps: deps,
      session: session,
      initial: chapter,
      output: p.join(locations.support, 'results'),
    ),
  );
}

class RendererProbe extends StatefulWidget {
  const RendererProbe({
    super.key,
    required this.deps,
    required this.session,
    required this.initial,
    required this.output,
  });
  final AppDependencies deps;
  final EpubSession session;
  final EpubChapter initial;
  final String output;
  @override
  State<RendererProbe> createState() => _RendererProbeState();
}

class _RendererProbeState extends State<RendererProbe> {
  late EpubChapter chapter = widget.initial;
  MacEpubController? controller;
  bool ready = false, busy = false, dark = false;
  double size = 24;
  int reload = 0;
  String status = '正在加载同一生产渲染器';
  @override
  void dispose() {
    unawaited(controller?.dispose());
    unawaited(widget.deps.close?.call());
    super.dispose();
  }

  Future<void> navigate(int ordinal, String fragment) async {
    final next = await widget.deps.epub!.chapter(
      widget.session,
      ordinal,
      job(),
    );
    if (mounted) {
      setState(() {
        chapter = next;
        ready = false;
        reload++;
        status = '正在载入章节';
      });
    }
  }

  Future<void> checks() async {
    if (!ready || busy) return;
    setState(() => busy = true);
    try {
      final raw = await controller!.checks(),
          result = jsonDecode(jsonEncode(raw)) as Map<String, dynamic>,
          dom = result['dom'] as Map<String, dynamic>;
      result['canonical_mapping_equal'] = mapEquals(
        Map<String, String>.from(dom['blocks'] as Map),
        chapter.blocks,
      );
      result['validated_selection'] = epubSelection(
        chapter,
        dom['selection'],
      ).map((a) => a.toJson()).toList();
      result['range_tests_validated'] = [
        for (final item in dom['range_tests'] as List)
          epubSelection(chapter, item).map((a) => a.toJson()).toList(),
      ];
      final before = epubSelection(chapter, await controller!.capture());
      final layouts = <Map<String, Object?>>[];
      for (final pixels in [18.0, 30.0, 24.0]) {
        final value = await controller!.layout(pixels, pixels == 30);
        final anchors = epubSelection(chapter, value);
        final after = epubSelection(chapter, await controller!.capture());
        layouts.add({
          'size': pixels,
          'exact': anchors.map((a) => a.exact).join(),
          'restored_exact': after.map((a) => a.exact).join(),
          'same_selection':
              after.map((a) => a.exact).join() ==
              before.map((a) => a.exact).join(),
        });
      }
      result['layouts'] = layouts;
      result['saved_anchor_restore'] = await controller!.restore(before.first);
      result['source_fixture_sha256'] =
          '3d6d0a4ee10305897ef708f43e76375433998025b1417f0b655cb431090df701';
      result['chapter'] = chapter.spine.ordinal;
      result['checks_passed'] =
          result['canonical_mapping_equal'] == true &&
          result['page_script_or_host_visible'] == false &&
          (dom['denied'] as List).every((dynamic b) => b == true) &&
          layouts.every((r) => r['same_selection'] == true);
      await Directory(widget.output).create(recursive: true);
      await File('${widget.output}/chapter-${chapter.spine.ordinal}.json')
          .writeAsString(const JsonEncoder.withIndent('  ').convert(result));
      if (mounted) {
        setState(
          () => status =
              '检查${result['checks_passed'] == true ? '通过' : '失败'}：原文映射、外联隔离、选区与三次布局恢复；结果已保存。',
        );
      }
    } catch (_) {
      if (mounted) setState(() => status = '检查未完成，保留失败状态。');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: paperTheme(dark ? Brightness.dark : Brightness.light),
    home: Scaffold(
      appBar: AppBar(title: const Text('MAC-07 · 自产 EPUB 渲染检查')),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                Text(status),
                TextButton(
                  onPressed: ready && !busy ? checks : null,
                  child: const Text('保存引擎检查'),
                ),
                TextButton(
                  onPressed: busy ? null : () => navigate(0, ''),
                  child: const Text('第一章'),
                ),
                TextButton(
                  onPressed: busy ? null : () => navigate(1, ''),
                  child: const Text('第二章'),
                ),
                TextButton(
                  onPressed: ready && !busy
                      ? () => setState(() => dark = !dark)
                      : null,
                  child: const Text('切换主题'),
                ),
              ],
            ),
          ),
          Expanded(
            child: MacEpubSurface(
              key: ValueKey('${chapter.spine.ordinal}:$reload'),
              reader: widget.deps.epub!,
              chapter: chapter,
              size: size,
              dark: dark,
              onCreated: (value) => controller = value,
              onReady: () {
                if (mounted) {
                  setState(() {
                    ready = true;
                    status = '已载入，可真实选字后保存检查';
                  });
                }
              },
              onError: (kind) {
                if (mounted) {
                  setState(() {
                    ready = false;
                    status = '渲染器失败：$kind';
                  });
                }
              },
              onNavigate: (rid, fragment) {
                final i = widget.session.spine.indexWhere(
                  (s) => s.resource == rid,
                );
                if (i >= 0) navigate(i, fragment);
              },
            ),
          ),
        ],
      ),
    ),
  );
}
