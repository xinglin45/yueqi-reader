// Separate research entry point: flutter run -t tool/mac06/probe.dart.
// The D1 production routes do not import this library.
import 'dart:async';
import 'dart:convert';

import 'package:epub_view/epub_view.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:novel_app/app/theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: paperTheme(Brightness.light),
      home: const Mac06Probe(),
    ),
  );
}

class Mac06Probe extends StatefulWidget {
  const Mac06Probe({super.key});
  @override
  State<Mac06Probe> createState() => _Mac06ProbeState();
}

class _Mac06ProbeState extends State<Mac06Probe> {
  late final Future<Map<String, dynamic>> _fixture = rootBundle
      .loadString('assets/mac06/fixture.json')
      .then((value) => jsonDecode(value) as Map<String, dynamic>);
  bool _native = true;
  int _chapter = 0;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('MAC-06 · EPUB 技术试验', style: TextStyle(fontSize: 18)),
    ),
    body: FutureBuilder<Map<String, dynamic>>(
      future: _fixture,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final fixture = snapshot.data!;
        final spine = (fixture['spine'] as List<dynamic>)
            .cast<Map<String, dynamic>>();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              child: Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  ChoiceChip(
                    label: const Text('受控 WebView'),
                    selected: _native,
                    onSelected: (_) => setState(() => _native = true),
                  ),
                  ChoiceChip(
                    label: const Text('Flutter · epub_view 3.3.0'),
                    selected: !_native,
                    onSelected: (_) => setState(() => _native = false),
                  ),
                  if (_native)
                    DropdownButton<int>(
                      value: _chapter,
                      items: [
                        for (final (index, chapter) in spine.indexed)
                          DropdownMenuItem(
                            value: index,
                            child: Text('目录 ${index + 1} · ${chapter['id']}'),
                          ),
                      ],
                      onChanged: (value) {
                        if (value != null) setState(() => _chapter = value);
                      },
                    ),
                  const Text(
                    '同一自产 EPUB · 无私人书籍或在线来源',
                    style: TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
            const Divider(),
            Expanded(
              child: _native
                  ? NativeEpubProbe(
                      key: ValueKey(_chapter),
                      fixture: fixture,
                      chapter: _chapter,
                    )
                  : const FlutterEpubProbe(),
            ),
          ],
        );
      },
    ),
  );
}

class NativeEpubProbe extends StatefulWidget {
  const NativeEpubProbe({
    super.key,
    required this.fixture,
    required this.chapter,
  });
  final Map<String, dynamic> fixture;
  final int chapter;
  @override
  State<NativeEpubProbe> createState() => _NativeEpubProbeState();
}

class _NativeEpubProbeState extends State<NativeEpubProbe> {
  MethodChannel? _channel;
  String _status = '正在加载离线章节与资源';
  bool _running = false;
  Map<String, dynamic>? _result;
  bool _disposed = false;
  Future<void> _created(int id) async {
    final channel = MethodChannel('mac06/webview/$id');
    _channel = channel;
    channel.setMethodCallHandler((call) async {
      if (call.method == 'ready') await _checks();
    });
    for (var attempt = 0; attempt < 60 && !_disposed; attempt++) {
      if (await channel.invokeMethod<bool>('status') == true) {
        await _checks();
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    if (mounted && _result == null) setState(() => _status = '加载超时，可重新运行试验');
  }

  Future<void> _checks() async {
    if (_running || _disposed || _channel == null) return;
    _running = true;
    try {
      final raw = await _channel!.invokeMethod<Object?>('checks');
      if (!mounted) return;
      final result = jsonDecode(jsonEncode(raw)) as Map<String, dynamic>;
      final dom = result['dom'] as Map<String, dynamic>;
      final spine = (widget.fixture['spine'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      final actualChapter = spine.indexWhere(
        (doc) => doc['path'] == dom['path'],
      );
      if (actualChapter < 0) throw PlatformException(code: 'unknown_document');
      final expected = spine[actualChapter]['blocks'];
      final actual = dom['blocks'];
      final mappingEqual = jsonEncode(actual) == jsonEncode(expected);
      // Compare key order independently: StandardMessageCodec maps may reorder.
      bool equalBlocks(List<dynamic> a, List<dynamic> b) =>
          a.length == b.length &&
          List.generate(
            a.length,
            (i) =>
                a[i]['id'] == b[i]['id'] &&
                a[i]['text'] == b[i]['text'] &&
                a[i]['utf16_length'] == b[i]['utf16_length'],
          ).every((value) => value);
      result['canonical_mapping_equal'] =
          mappingEqual ||
          equalBlocks(actual as List<dynamic>, expected as List<dynamic>);
      result['revision'] = widget.fixture['revision'];
      result['chapter'] = actualChapter;
      // Probe output is only the committed, self-authored fixture. No book import.
      debugPrint(
        'MAC06_WEBVIEW_RESULT ${jsonEncode(result)}',
        wrapWidth: 200000,
      );
      setState(() {
        _result = result;
        _status =
            '第${actualChapter + 1}章 · 映射 ${result['canonical_mapping_equal'] == true ? '通过' : '失败'} · 选字 ${dom['selected']} · ${((dom['restorations'] as List<dynamic>).length)} 次布局恢复';
      });
    } on PlatformException catch (_) {
      if (mounted) setState(() => _status = '桥接检查未完成');
    } finally {
      _running = false;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _channel?.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chapter =
        (widget.fixture['spine'] as List<dynamic>)[widget.chapter]
            as Map<String, dynamic>;
    if (!kDebugMode || defaultTargetPlatform != TargetPlatform.macOS) {
      return const Center(child: Text('此原生探针仅在 macOS Debug 可用。其他三端尚未实测。'));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: Wrap(
            spacing: 16,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(_status, key: const ValueKey('native-probe-status')),
              TextButton(onPressed: _checks, child: const Text('重新检查')),
            ],
          ),
        ),
        Expanded(
          child: AppKitView(
            viewType: 'local.yueqi.mac06.webview',
            creationParamsCodec: const StandardMessageCodec(),
            creationParams: {
              'revision': widget.fixture['revision'],
              'resources': widget.fixture['resources'],
              'path': chapter['path'],
            },
            onPlatformViewCreated: _created,
          ),
        ),
      ],
    );
  }
}

class FlutterEpubProbe extends StatefulWidget {
  const FlutterEpubProbe({super.key});
  @override
  State<FlutterEpubProbe> createState() => _FlutterEpubProbeState();
}

class _FlutterEpubProbeState extends State<FlutterEpubProbe> {
  late final EpubController _controller = EpubController(
    document: EpubDocument.openAsset('assets/mac06/mountain-letter.epub'),
  );
  String _status = '正在用 Flutter widget 排版同一 EPUB';
  String? _cfi;
  String _selection = '';
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _anchor() {
    try {
      final before = _controller.generateEpubCfi();
      if (before != null) _controller.gotoEpubCfi(before);
      setState(() => _cfi = before);
      debugPrint(
        'MAC06_FLUTTER_ANCHOR ${jsonEncode({'cfi': before, 'scope': 'viewport/paragraph only; no exact character selection mapping claimed'})}',
      );
    } catch (_) {
      setState(() => _status = 'CFI 试验未完成');
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.all(12),
        child: Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            Text(_status),
            TextButton(onPressed: _anchor, child: const Text('保存并恢复 CFI')),
            TextButton(
              onPressed: () => _controller.jumpTo(index: 0),
              child: const Text('回到开头'),
            ),
            TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Flutter 目录'),
                  content: SizedBox(
                    width: 400,
                    height: 260,
                    child: EpubViewTableOfContents(controller: _controller),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('返回'),
                    ),
                  ],
                ),
              ),
              child: const Text('查看 Flutter 目录'),
            ),
            if (_cfi != null) Text(_cfi!),
            if (_selection.isNotEmpty) Text('选字：$_selection'),
          ],
        ),
      ),
      Expanded(
        child: SelectionArea(
          onSelectionChanged: (content) {
            if (mounted) setState(() => _selection = content?.plainText ?? '');
          },
          child: EpubView(
            controller: _controller,
            onDocumentLoaded: (book) {
              if (mounted) {
                setState(
                  () => _status =
                      '已加载 ${book.Chapters?.length ?? 0} 章 · 图片 ${book.Content?.Images?.length ?? 0}',
                );
              }
              debugPrint(
                'MAC06_FLUTTER_LOADED ${jsonEncode({'chapters': book.Chapters?.length, 'images': book.Content?.Images?.length})}',
              );
            },
            onDocumentError: (_) {
              if (mounted) setState(() => _status = '此 Flutter 路线未能打开样本');
            },
            onExternalLinkPressed: (_) =>
                setState(() => _status = '链接已拦截；内部链接需另做适配'),
          ),
        ),
      ),
    ],
  );
}
