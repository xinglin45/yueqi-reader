import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:novel_app/app/dependencies.dart';
import 'package:novel_app/app/theme.dart';
import 'package:novel_app/domain/access.dart';
import 'package:novel_app/domain/documents.dart';
import 'package:novel_app/domain/epub.dart';
import 'package:novel_app/domain/importing.dart';
import 'package:novel_app/domain/reading.dart';
import 'package:novel_app/infrastructure/epub/mac_epub_surface.dart';
import 'package:novel_app/infrastructure/platform_storage_locations.dart';
import 'package:path/path.dart' as p;
import 'package:platform_services/platform_services.dart';

import '../mac07/renderer_probe.dart' show OwnedFiles, job;

final class ProbeLocations implements StorageLocationProvider {
  @override
  Future<AppStorageLocations> locations() async {
    final system = await const SystemStorageLocations().locations();
    return AppStorageLocations(
      support: p.join(system.support, 'mac09-renderer-probe'),
      cache: p.join(system.cache, 'mac09-renderer-probe'),
    );
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final locations = await ProbeLocations().locations();
  await Directory(locations.support).create(recursive: true);
  final data = await rootBundle.load('assets/mac09/flow.epub'),
      bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  if (sha256.convert(bytes).toString() !=
      '0126d8309d0b8b829c78d03df3da7c75c65fd9dc1f5199a1b06fe72a636a0f1c') {
    throw StateError('fixture_digest');
  }
  final file = await File(p.join(locations.support, 'owned.epub'))
      .writeAsBytes(bytes);
  final deps = await AppDependencies.open(
    ProbeLocations(),
    documents: OwnedFiles(file),
  );
  final prepared = await deps.importer!.prepare(
    const FileGrant(id: 'owned', displayName: '山路排版.epub'),
    job(),
  );
  final book = await deps.importer!.commit(
    prepared.id,
    mode: ImportMode.managed,
    rating: RatingLevel.general,
    job: job(),
  );
  final session = await deps.epub!.open(book.bookId, job()),
      chapter = await deps.epub!.chapter(session, 0, job());
  runApp(
    Probe(
      deps: deps,
      chapter: chapter,
      output: p.join(locations.support, 'results.json'),
    ),
  );
}

class Probe extends StatefulWidget {
  const Probe({
    super.key,
    required this.deps,
    required this.chapter,
    required this.output,
  });
  final AppDependencies deps;
  final EpubChapter chapter;
  final String output;
  @override
  State<Probe> createState() => _ProbeState();
}

class _ProbeState extends State<Probe> {
  MacEpubController? controller;
  bool ready = false, busy = false;
  String status = '正在载入生产渲染器';
  Future<void> run() async {
    if (!ready || busy) return;
    setState(() => busy = true);
    final report = <String, Object?>{
      'date': '2026-10-26',
      'fixture_sha256':
          '0126d8309d0b8b829c78d03df3da7c75c65fd9dc1f5199a1b06fe72a636a0f1c',
    };
    try {
      final states = <Map<String, Object?>>[];
      await controller!.configure(const ReadingPreferences(), false);
      await controller!.page(1);
      final initial = epubSelection(
        widget.chapter,
        await controller!.viewport(),
      ).first;
      for (final prefs in [
        const ReadingPreferences(
          layout: ReadingLayout.paged,
          size: 18,
          lineHeight: 1.4,
          margin: 16,
        ),
        const ReadingPreferences(
          layout: ReadingLayout.columns,
          font: ReadingFont.sans,
          size: 30,
          margin: 32,
          theme: ReadingTheme.dark,
        ),
        const ReadingPreferences(
          layout: ReadingLayout.scroll,
          font: ReadingFont.mono,
          size: 26,
          paragraphSpacing: 30,
          width: 600,
          theme: ReadingTheme.green,
        ),
      ]) {
        final before = epubSelection(
          widget.chapter,
          await controller!.configure(prefs, false),
        ).first;
        final checks = Map<String, dynamic>.from(
              (await controller!.checks())! as Map,
            ),
            dom = Map<String, dynamic>.from(checks['dom'] as Map);
        final after = epubSelection(widget.chapter, dom['viewport']).first;
        states.add({
          'preferences': prefs.toJson(),
          'captured': before.toJson(),
          'visible': after.toJson(),
          'retained_anchor_visible': dom['retained_anchor_visible'],
          'same_content_anchor':
              before.blockId == initial.blockId &&
              before.start == initial.start,
          'page_world_isolated': checks['page_script_or_host_visible'] == false,
          'external_requests_denied': (dom['denied'] as List).every(
            (v) => v == true,
          ),
        });
      }
      await controller!.configure(
        const ReadingPreferences(layout: ReadingLayout.paged),
        false,
      );
      final before = epubSelection(
        widget.chapter,
        await controller!.viewport(),
      ).first;
      final page = Map<String, dynamic>.from(
        (await controller!.page(1))! as Map,
      );
      final after = epubSelection(widget.chapter, page['position']).first;
      final saved = await widget.deps.positions!.loadPosition(
        widget.chapter.session.bookId,
        PositionChannel.reading,
      );
      await widget.deps.positions!.savePosition(
        widget.chapter.session.bookId,
        PositionChannel.reading,
        after,
        expectedSequence: saved?.sequence ?? 0,
      );
      report['layouts'] = states;
      report['initial_advanced_anchor'] = initial.toJson();
      report['page_before'] = before.toJson();
      report['page_after'] = after.toJson();
      report['page_advanced'] =
          before.blockId != after.blockId || before.start != after.start;
      report['restore_accepted'] = await controller!.restore(after);
      report['checks_passed'] =
          report['page_advanced'] == true &&
          report['restore_accepted'] == true &&
          states.every(
            (s) =>
                s['retained_anchor_visible'] == true &&
                s['same_content_anchor'] == true &&
                s['page_world_isolated'] == true &&
                s['external_requests_denied'] == true,
          );
      setState(
        () => status = report['checks_passed'] == true
            ? '检查通过：三种布局保留字符锚点、翻页与隔离正常'
            : '检查失败，请查看结果',
      );
    } catch (e) {
      report['checks_passed'] = false;
      report['failure_type'] = e.runtimeType.toString();
      setState(() => status = '检查未完成，请查看结果');
    }
    await File(widget.output)
        .writeAsString(const JsonEncoder.withIndent('  ').convert(report));
    if (mounted) setState(() => busy = false);
  }

  @override
  void dispose() {
    unawaited(controller?.dispose());
    unawaited(widget.deps.close?.call());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: paperTheme(Brightness.light),
    home: Scaffold(
      appBar: AppBar(title: const Text('MAC-09 · 自产长篇原生引擎检查')),
      body: Column(
        children: [
          Wrap(
            spacing: 12,
            children: [
              Text(status),
              TextButton(
                onPressed: ready && !busy ? run : null,
                child: const Text('运行排版检查'),
              ),
            ],
          ),
          Expanded(
            child: MacEpubSurface(
              reader: widget.deps.epub!,
              chapter: widget.chapter,
              size: 24,
              dark: false,
              onCreated: (c) => controller = c,
              onReady: () {
                if (mounted) {
                  setState(() {
                    ready = true;
                    status = '引擎就绪';
                  });
                }
              },
              onNavigate: (_, _) {},
              onError: (kind) {
                if (mounted) setState(() => status = '渲染器失败：$kind');
              },
            ),
          ),
        ],
      ),
    ),
  );
}
