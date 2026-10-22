import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../app/dependencies.dart';
import '../domain/documents.dart';
import '../domain/epub.dart';
import '../domain/importing.dart';
import '../domain/jobs.dart';
import '../domain/library.dart';
import '../infrastructure/epub/mac_epub_surface.dart';
import 'import_flow.dart';
import 'task_view.dart';

class EpubReaderView extends StatefulWidget {
  const EpubReaderView({
    super.key,
    required this.bookId,
    required this.deps,
    required this.onOpened,
  });
  final String bookId;
  final AppDependencies deps;
  final ValueChanged<BookSummary> onOpened;
  @override
  State<EpubReaderView> createState() => _EpubReaderViewState();
}

class _EpubReaderViewState extends State<EpubReaderView> {
  EpubDocumentReader get reader => widget.deps.epub!;
  EpubSession? session;
  EpubChapter? chapter;
  DocumentAnchor? restore;
  MacEpubController? renderer;
  bool busy = false, renderReady = false, renderFailed = false;
  double? progress;
  double size = 24;
  int generation = 0, sequence = 0, reload = 0;
  String? error, notice;
  String fragment = '';
  List<DocumentAnchor> selection = [];
  final concealed = ValueNotifier(false);
  final dialogs = <DialogRoute<Object?>>[];
  ImageProvider? displayedImage;
  void Function()? unregister;
  @override
  void initState() {
    super.initState();
    unregister = widget.deps.access?.registerProtectedStop(() {
      concealed.value = true;
      unawaited(renderer?.dispose());
      unawaited(displayedImage?.evict());
    });
    _run(_open);
  }

  @override
  void dispose() {
    generation++;
    unregister?.call();
    concealed.value = true;
    unawaited(renderer?.dispose());
    unawaited(displayedImage?.evict());
    final id = session?.id;
    if (id != null) unawaited(reader.close(id));
    if (dialogs.isEmpty) {
      concealed.dispose();
    } else {
      unawaited(
        Future.wait(dialogs.map((r) => r.completed))
            .whenComplete(concealed.dispose),
      );
    }
    super.dispose();
  }

  Future<T?> _dialog<T>(Widget Function(BuildContext) builder) async {
    final route = DialogRoute<T>(
      context: context,
      builder: (dialog) => ValueListenableBuilder(
        valueListenable: concealed,
        builder: (_, hidden, _) => hidden
            ? AlertDialog(
                title: const Text('内容已隐藏'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialog),
                    child: const Text('返回'),
                  ),
                ],
              )
            : builder(dialog),
      ),
    );
    dialogs.add(route);
    final result = await Navigator.of(context).push(route);
    await route.completed;
    dialogs.remove(route);
    return result;
  }

  Future<void> _run(Future<void> Function(JobContext) action) async {
    final current = ++generation;
    setState(() {
      busy = true;
      error = null;
      progress = null;
    });
    final job = JobContext(
      id: current,
      isCurrent: () => mounted && current == generation && !concealed.value,
      report: (p) {
        if (mounted && current == generation) setState(() => progress = p);
      },
    );
    try {
      await action(job);
    } on JobCancelled {
      if (mounted && current == generation) {
        setState(() => notice = '任务已取消，原书和已保存位置保留。');
      }
    } on EpubFailure catch (e) {
      if (mounted && current == generation) {
        setState(() => error = epubHelp(e.issue));
      }
    } on ImportFailure {
      if (mounted && current == generation) {
        setState(() => error = '原件不可用或已改变，请在文件状态中检查授权、重新关联或重新导入。');
      }
    } on AppFailure catch (e) {
      if (mounted && current == generation) {
        setState(() => error = failureHelp(e.code));
      }
    } catch (_) {
      if (mounted && current == generation) {
        setState(() => error = '这次阅读操作未完成。旧位置保留，可重新打开后重试。');
      }
    } finally {
      if (mounted && current == generation) setState(() => busy = false);
    }
  }

  Future<void> _open(JobContext job) async {
    final old = session?.id;
    setState(() {
      chapter = null;
      session = null;
      selection = [];
      restore = null;
      renderer = null;
      renderReady = false;
      renderFailed = false;
    });
    if (old != null) await reader.close(old);
    final next = await reader.open(widget.bookId, job);
    try {
      job.checkCancelled();
      session = next;
      final saved = await widget.deps.positions?.loadPosition(
        widget.bookId,
        PositionChannel.reading,
      );
      sequence = saved?.sequence ?? 0;
      var ordinal = 0;
      if (saved != null &&
          saved.anchor.revision == next.revision &&
          saved.anchor.kind == DocumentKind.epub) {
        ordinal = next.spine.indexWhere(
          (s) =>
              s.id == saved.anchor.chapterId &&
              s.href == saved.anchor.spineHref,
        );
        if (ordinal < 0) ordinal = 0;
      }
      final content = await reader.chapter(next, ordinal, job);
      job.checkCancelled();
      if (saved != null) {
        final resolution = saved.anchor.resolve(
          currentRevision: next.revision,
          currentChapter: content.spine.id,
          currentSpine: content.spine.href,
          blocks: content.blocks,
        );
        if (resolution.match == AnchorMatch.exact) {
          restore = saved.anchor;
          notice = '已恢复到上次记住的 EPUB 文本位置。';
        } else {
          notice = '旧位置暂未精确匹配，已保留原记录；请确认阅读位置后再保存。';
        }
      }
      setState(() {
        chapter = content;
        fragment = '';
      });
      widget.onOpened(
        BookSummary(
          id: next.bookId,
          title: next.title,
          subtitle: '本地 EPUB',
          persistent: true,
          protected: next.protected,
          previewAvailable: false,
          importedEpub: true,
        ),
      );
    } catch (_) {
      await reader.close(next.id);
      rethrow;
    }
  }

  Future<void> _navigate(int ordinal, String target, JobContext job) async {
    final next = await reader.chapter(session!, ordinal, job);
    if (target.isNotEmpty && !next.fragments.containsKey(target)) {
      throw const EpubFailure(EpubIssue.missingResource);
    }
    job.checkCancelled();
    setState(() {
      chapter = next;
      restore = null;
      fragment = target;
      selection = [];
      renderer = null;
      renderReady = false;
      renderFailed = false;
      reload++;
    });
  }

  Future<void> _directory() async {
    final next = await _dialog<EpubToc>(
      (dialog) => AlertDialog(
        title: const Text('章节目录'),
        content: SizedBox(
          width: 440,
          height: 420,
          child: ListView.builder(
            itemCount: session!.toc.length,
            itemBuilder: (_, i) {
              final t = session!.toc[i];
              return ListTile(
                contentPadding: EdgeInsets.only(
                  left: 16 + (t.depth.clamp(0, 6)) * 12.0,
                  right: 12,
                ),
                title: Text(t.title),
                onTap: () => Navigator.pop(dialog, t),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: const Text('返回'),
          ),
        ],
      ),
    );
    if (next != null && mounted && !concealed.value) {
      await _run((job) => _navigate(next.spine, next.fragment, job));
    }
  }

  Future<void> _capture(JobContext job, {bool save = false}) async {
    final current = chapter!;
    await reader.chapter(session!, current.spine.ordinal, job);
    final anchors = epubSelection(current, await renderer!.capture());
    job.checkCancelled();
    if (save) {
      final saved = await widget.deps.positions!.savePosition(
        widget.bookId,
        PositionChannel.reading,
        anchors.first,
        expectedSequence: sequence,
      );
      job.checkCancelled();
      sequence = saved.sequence;
      notice = anchors.length > 1
          ? '已记住选区起点；共识别 ${anchors.length} 个原文片段。'
          : '已记住当前 EPUB 文本位置。';
    } else {
      notice = anchors.every((a) => a.exact.isEmpty)
          ? '当前没有选中文字，已定位当前可见文本。'
          : '选区已与原文核对：${anchors.length} 个片段，UTF-16 偏移一致。';
    }
    setState(() => selection = anchors);
  }

  Future<void> _images() async {
    final images = chapter!.spine.images;
    final id = await _dialog<String>(
      (dialog) => AlertDialog(
        title: const Text('本章图片'),
        content: SizedBox(
          width: 360,
          height: 300,
          child: ListView.builder(
            itemCount: images.length,
            itemBuilder: (_, i) => ListTile(
              title: Text('图片 ${i + 1}'),
              onTap: () => Navigator.pop(dialog, images[i]),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: const Text('返回'),
          ),
        ],
      ),
    );
    if (id == null || !mounted || concealed.value) return;
    await _run((job) async {
      final image = await reader.resource(session!, id, job);
      if (!image.mime.startsWith('image/')) {
        throw const EpubFailure(EpubIssue.unsupported);
      }
      job.checkCancelled();
      final provider = ResizeImage(
        MemoryImage(image.bytes),
        width: 2048,
        allowUpscaling: false,
      );
      displayedImage = provider;
      try {
        await _dialog<void>(
          (dialog) => AlertDialog(
            title: const Text('书内图片'),
            content: SizedBox(
              width: 680,
              height: 480,
              child: InteractiveViewer(
                child: Image(
                  image: provider,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => const Text('图片未能解码。'),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialog),
                child: const Text('返回'),
              ),
            ],
          ),
        );
      } finally {
        await provider.evict();
        displayedImage = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: concealed,
    builder: (context, hidden, _) =>
        hidden ? const Text('内容已隐藏') : _content(context),
  );
  Widget _surface(EpubChapter active) {
    if (defaultTargetPlatform != TargetPlatform.macOS) {
      return const Center(child: Text('当前平台尚未接入 EPUB 渲染适配。'));
    }
    if (renderFailed) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('阅读视图未能加载或已退出，旧位置保留。'),
            TextButton(
              onPressed: busy
                  ? null
                  : () => setState(() {
                      renderFailed = false;
                      renderReady = false;
                      reload++;
                    }),
              child: const Text('重新加载本章'),
            ),
          ],
        ),
      );
    }
    return MacEpubSurface(
      key: ValueKey('${session!.id}:${active.spine.ordinal}:$reload'),
      reader: reader,
      chapter: active,
      size: size,
      dark: Theme.of(context).brightness == Brightness.dark,
      anchor: restore,
      fragment: fragment,
      onCreated: (value) => renderer = value,
      onReady: () {
        if (mounted) setState(() => renderReady = true);
      },
      onError: (kind) {
        if (mounted) {
          setState(() {
            renderFailed = true;
            renderReady = false;
          });
        }
      },
      onNavigate: (rid, target) {
        if (busy || !mounted) return;
        final ordinal = session!.spine.indexWhere((s) => s.resource == rid);
        if (ordinal >= 0) _run((job) => _navigate(ordinal, target, job));
      },
    );
  }

  Widget _content(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final active = chapter,
          height = constraints.hasBoundedHeight ? constraints.maxHeight : 780.0;
      final controls = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            session?.title ?? '本地 EPUB',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              TextButton(
                onPressed: busy || session == null ? null : _directory,
                child: const Text('章节目录'),
              ),
              TextButton(
                onPressed: busy
                    ? null
                    : () async {
                        await showImportedStatus(
                          context,
                          widget.deps,
                          widget.bookId,
                        );
                        if (mounted && !concealed.value) await _run(_open);
                      },
                child: const Text('文件状态'),
              ),
              TextButton(
                onPressed: busy || active == null || active.spine.images.isEmpty
                    ? null
                    : _images,
                child: const Text('本章图片'),
              ),
              TextButton(
                onPressed: busy || !renderReady
                    ? null
                    : () => _run((j) => _capture(j)),
                child: const Text('核对选区'),
              ),
              TextButton(
                onPressed: busy || !renderReady || widget.deps.positions == null
                    ? null
                    : () => _run((j) => _capture(j, save: true)),
                child: const Text('记住文本位置'),
              ),
            ],
          ),
          if (busy) ...[
            LinearProgressIndicator(value: progress),
            TextButton(
              onPressed: () {
                generation++;
                setState(() {
                  busy = false;
                  notice = '任务已取消，原记录保留。';
                });
              },
              child: const Text('取消任务'),
            ),
          ],
          if (error != null)
            Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          if (notice != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(notice!),
            ),
          if (session?.warnings.isNotEmpty == true)
            const Text(
              '已移除书内脚本、活动属性或外联内容；仅加载受控的书内资源。',
              style: TextStyle(fontSize: 12),
            ),
          if (active != null) ...[
            Text(
              active.spine.title,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            Row(
              children: [
                const Text('字号'),
                Expanded(
                  child: Slider(
                    value: size,
                    min: 16,
                    max: 36,
                    divisions: 10,
                    label: '${size.round()}',
                    onChanged: renderReady && !busy
                        ? (v) => setState(() => size = v)
                        : null,
                  ),
                ),
                Text('${size.round()}'),
              ],
            ),
          ],
          if (selection.any((a) => a.exact.isNotEmpty))
            Text(
              selection.map((a) => a.exact).join(''),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14),
            ),
        ],
      );
      return SizedBox(
        height: height,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: height * .55),
              child: SingleChildScrollView(child: controls),
            ),
            if (active != null) ...[
              Expanded(child: _surface(active)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  TextButton(
                    onPressed: busy || active.spine.ordinal == 0
                        ? null
                        : () => _run(
                            (j) => _navigate(active.spine.ordinal - 1, '', j),
                          ),
                    child: const Text('上一节'),
                  ),
                  FilledButton(
                    onPressed:
                        busy ||
                            active.spine.ordinal + 1 >= session!.spine.length
                        ? null
                        : () => _run(
                            (j) => _navigate(active.spine.ordinal + 1, '', j),
                          ),
                    child: const Text('下一节'),
                  ),
                  Text(
                    '${active.spine.ordinal + 1} / ${session!.spine.length}',
                  ),
                ],
              ),
              const Text(
                'EPUB 滚动阅读 · 主动保存文本位置；完整分页、自动进度、笔记与听书待后续步骤。',
                style: TextStyle(fontSize: 11),
              ),
            ] else ...[
              const Spacer(),
              if (!busy)
                OutlinedButton(
                  onPressed: () => _run(_open),
                  child: const Text('重新打开 EPUB'),
                ),
            ],
          ],
        ),
      );
    },
  );
}
