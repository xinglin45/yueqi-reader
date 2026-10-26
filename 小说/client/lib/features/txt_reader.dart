import 'dart:async';

import 'package:flutter/material.dart';

import '../application/reading.dart';
import '../domain/reading.dart';
import 'reading_controls.dart';
import 'text_surface.dart';

import '../app/dependencies.dart';
import '../domain/documents.dart';
import '../domain/importing.dart';
import '../domain/jobs.dart';
import '../domain/library.dart';
import '../domain/txt.dart';
import 'task_view.dart';
import 'import_flow.dart';

class TxtReaderView extends StatefulWidget {
  const TxtReaderView({
    super.key,
    required this.bookId,
    required this.deps,
    required this.onOpened,
  });
  final String bookId;
  final AppDependencies deps;
  final ValueChanged<BookSummary> onOpened;
  @override
  State<TxtReaderView> createState() => _TxtReaderViewState();
}

class _TxtReaderViewState extends State<TxtReaderView> {
  TxtDocumentReader get reader => widget.deps.txt!;
  TxtIndex? index, candidate;
  ReadingSession? reading;
  DocumentAnchor? target;
  TxtPage? page;
  bool busy = false, cancelled = false, rulesVisible = false;
  double? progress;
  String? notice, error, remembered;
  int sequence = 0, generation = 0;
  TxtHeadings headings = TxtHeadings.standard;
  int maxTitle = 80;
  final prefix = TextEditingController();
  final top = GlobalKey();
  final concealed = ValueNotifier(false);
  final dialogs = <DialogRoute<int>>[];
  void Function()? unregister;
  @override
  void initState() {
    super.initState();
    unregister = widget.deps.access?.registerProtectedStop(
      () => concealed.value = true,
    );
    _run(_open);
  }

  @override
  void dispose() {
    generation++;
    unregister?.call();
    concealed.value = true;
    if (dialogs.isEmpty) {
      concealed.dispose();
    } else {
      unawaited(
        Future.wait(dialogs.map((r) => r.completed))
            .whenComplete(concealed.dispose),
      );
    }
    unawaited(reading?.finish());
    prefix.dispose();
    final id = candidate?.id;
    if (id != null) reader.discard(id);
    super.dispose();
  }

  Future<void> _run(Future<void> Function(JobContext) action) async {
    final ticket = ++generation;
    setState(() {
      busy = true;
      cancelled = false;
      error = null;
      progress = null;
    });
    final job = JobContext(
      id: ticket,
      isCurrent: () =>
          mounted && generation == ticket && !cancelled && !concealed.value,
      report: (p) {
        if (mounted && generation == ticket) setState(() => progress = p);
      },
    );
    try {
      await action(job);
    } on JobCancelled {
      if (mounted && generation == ticket) {
        setState(() => notice = '任务已取消，当前目录和已保存位置保留。');
      }
    } on ImportFailure catch (e) {
      if (mounted && generation == ticket) {
        setState(
          () => error = e.issue == ImportIssue.changed
              ? '原件内容已改变，请保留旧记录并重新导入。'
              : '原件不可用，请从文件状态检查授权或重新关联。',
        );
      }
    } on AppFailure catch (e) {
      if (mounted && generation == ticket) {
        setState(() => error = failureHelp(e.code));
      }
    } catch (_) {
      if (mounted && generation == ticket) {
        setState(() => error = '正文或索引未能读取。可以重新预览分章；旧目录和位置仍保留。');
      }
    } finally {
      if (mounted && generation == ticket) setState(() => busy = false);
    }
  }

  Future<void> _open(JobContext job) async {
    setState(() {
      page = null;
      index = null;
      target = null;
      remembered = null;
      notice = null;
    });
    final active = await reader.open(widget.bookId, job);
    job.checkCancelled();
    if (active == null) {
      setState(() => rulesVisible = true);
      return;
    }
    index = active;
    headings = active.rules.headings;
    maxTitle = active.rules.maxTitle;
    prefix.text = active.rules.prefix;
    reading = await widget.deps.reading?.open(
      ReadingIdentity(widget.bookId, active.id, DocumentKind.txt),
      isCurrent: () => !job.isCancelled,
    );
    job.checkCancelled();
    final saved = reading?.anchor == null
        ? null
        : StoredPosition(
            widget.bookId,
            PositionChannel.reading,
            reading!.anchor!,
            reading!.sequence,
          );
    sequence = saved?.sequence ?? 0;
    var first = 0;
    if (saved != null) {
      if (saved.anchor.revision == active.id) {
        first = int.tryParse(saved.anchor.blockId.replaceFirst('b', '')) ?? 0;
        if (first >= active.blocks) first = 0;
      } else {
        notice = '分章版本已变更，旧位置已保留。请选择章节，确认位置后再记住这一段。';
      }
    }
    await _read(first, job);
    if (saved != null && saved.anchor.revision == active.id && page != null) {
      final result = saved.anchor.resolve(
        currentRevision: active.id,
        currentChapter: page!.chapter.id,
        currentSpine: 'text.txt',
        blocks: {for (final b in page!.blocks) b.id: b.text},
      );
      if (result.match == AnchorMatch.exact) {
        remembered = saved.anchor.blockId;
        target = saved.anchor;
        notice = '已恢复到上次记住的文本块。';
      } else {
        reading?.needsReview = true;
        notice = '旧位置未精确匹配，已保留原记录，请重新选择。';
      }
    }
    job.checkCancelled();
    setState(() {});
  }

  Future<void> _read(int first, JobContext job, {bool atEnd = false}) async {
    reading?.navigate = (a) async {
      if (!mounted) return false;
      var restored = false;
      await _run((job) async {
        final ordinal = int.tryParse(a.blockId.replaceFirst('b', ''));
        if (ordinal == null) throw const FormatException('txt_anchor_block');
        await _read(ordinal, job);
        final resolved = a.resolve(
          currentRevision: index!.id,
          currentChapter: page!.chapter.id,
          currentSpine: 'text.txt',
          blocks: {for (final b in page!.blocks) b.id: b.text},
        );
        if (resolved.match != AnchorMatch.exact) {
          throw const FormatException('txt_anchor_context');
        }
        setState(() => target = a);
        restored = true;
      });
      return restored;
    };
    final next = await reader.read(index!, first, job);
    job.checkCancelled();
    setState(() {
      page = next;
      target = next.anchor(next.blocks.first);
      if (atEnd) {
        final block = next.blocks.last;
        var offset = (block.text.length - 1).clamp(0, block.text.length);
        if (!utf16Boundary(block.text, offset)) offset--;
        target = DocumentAnchor.capture(
          kind: DocumentKind.txt,
          revision: next.index.id,
          chapterId: next.chapter.id,
          spineHref: 'text.txt',
          blockId: block.id,
          text: block.text,
          start: offset,
          end: offset,
        );
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !job.isCancelled && top.currentContext != null) {
        Scrollable.ensureVisible(top.currentContext!, alignment: 0);
      }
    });
    widget.onOpened(
      BookSummary(
        id: index!.bookId,
        title: index!.title,
        subtitle: '本地 TXT',
        persistent: true,
        protected: index!.protected,
      ),
    );
  }

  Future<void> _preview(JobContext job) async {
    if (candidate != null) {
      await reader.discard(candidate!.id);
      candidate = null;
    }
    final next = await reader.preview(
      widget.bookId,
      TxtRules(headings: headings, maxTitle: maxTitle, prefix: prefix.text),
      job,
    );
    job.checkCancelled();
    setState(() => candidate = next);
  }

  Future<void> _apply(JobContext job) async {
    final next = await reader.apply(candidate!.id, job);
    job.checkCancelled();
    setState(() {
      index = next;
      page = null;
      candidate = null;
      rulesVisible = false;
      remembered = null;
      notice = '已切换分章版本，原位置仍保留；阅读后可主动记住新位置。';
    });
    await reading?.finish();
    reading = await widget.deps.reading?.open(
      ReadingIdentity(widget.bookId, next.id, DocumentKind.txt),
      isCurrent: () => !job.isCancelled,
    );
    await _read(0, job);
  }

  Future<void> _directory() async {
    final active = index!;
    var offset = 0;
    var result = reader.chapters(
      active,
      0,
      JobContext(id: 0, isCurrent: () => mounted, report: (_) {}),
    );
    final route = DialogRoute<int>(
      context: context,
      builder: (dialog) => ValueListenableBuilder<bool>(
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
            : StatefulBuilder(
                builder: (dialog, update) => AlertDialog(
                  title: Text('章节目录 · ${active.chapterCount} 章'),
                  content: SizedBox(
                    width: 440,
                    height: 420,
                    child: FutureBuilder<List<TxtChapter>>(
                      future: result,
                      builder: (context, snapshot) {
                        if (snapshot.hasError) {
                          return const Text('目录暂不可用，请返回检查原件与权限。');
                        }
                        if (!snapshot.hasData) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }
                        return ListView(
                          children: [
                            for (final c in snapshot.data!.take(20))
                              ListTile(
                                title: Text('${c.ordinal + 1}. ${c.title}'),
                                onTap: () => Navigator.pop(dialog, c.first),
                              ),
                          ],
                        );
                      },
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: offset == 0
                          ? null
                          : () => update(() {
                              offset = (offset - 20).clamp(
                                0,
                                active.chapterCount,
                              );
                              result = reader.chapters(
                                active,
                                offset,
                                JobContext(
                                  id: 0,
                                  isCurrent: () => mounted && dialog.mounted,
                                  report: (_) {},
                                ),
                              );
                            }),
                      child: const Text('上一组'),
                    ),
                    TextButton(
                      onPressed: offset + 20 >= active.chapterCount
                          ? null
                          : () => update(() {
                              offset += 20;
                              result = reader.chapters(
                                active,
                                offset,
                                JobContext(
                                  id: 0,
                                  isCurrent: () => mounted && dialog.mounted,
                                  report: (_) {},
                                ),
                              );
                            }),
                      child: const Text('下一组'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(dialog),
                      child: const Text('返回'),
                    ),
                  ],
                ),
              ),
      ),
    );
    dialogs.add(route);
    final block = await Navigator.of(context).push(route);
    await route.completed;
    dialogs.remove(route);
    if (block != null && mounted && !concealed.value) {
      reading?.rememberJump();
      await _run((job) => _read(block, job));
    }
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: concealed,
    builder: (context, hidden, _) =>
        hidden ? const Text('内容已隐藏') : _content(context),
  );
  Widget _content(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final controls = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            index?.title ?? '本地 TXT',
            key: top,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              TextButton(
                onPressed: busy || index == null ? null : _directory,
                child: const Text('章节目录'),
              ),
              TextButton(
                onPressed: busy
                    ? null
                    : () => setState(() => rulesVisible = !rulesVisible),
                child: const Text('分章规则'),
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
                        if (mounted) await _run(_open);
                      },
                child: const Text('文件状态'),
              ),
            ],
          ),
          if (busy) ...[
            LinearProgressIndicator(value: progress),
            TextButton(
              onPressed: () => setState(() => cancelled = true),
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
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(notice!),
            ),
          if (rulesVisible) ...[
            const Text('先预览目录，再确认切换。重建不会覆盖旧位置；正文按原始字节读取，不改写原件。'),
            const SizedBox(height: 16),
            DropdownButtonFormField<TxtHeadings>(
              initialValue: headings,
              decoration: const InputDecoration(labelText: '章节识别'),
              items: const [
                DropdownMenuItem(
                  value: TxtHeadings.standard,
                  child: Text('常规：章 / 回 / 卷 / 序与后记'),
                ),
                DropdownMenuItem(
                  value: TxtHeadings.strict,
                  child: Text('严格：第…章 / 节 / 回'),
                ),
                DropdownMenuItem(
                  value: TxtHeadings.none,
                  child: Text('不分章：全文'),
                ),
              ],
              onChanged: busy ? null : (v) => setState(() => headings = v!),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: prefix,
              maxLength: 16,
              enabled: !busy,
              decoration: const InputDecoration(labelText: '额外标题前缀（可留空，按文字匹配）'),
            ),
            Text('标题最长 $maxTitle 字'),
            Slider(
              value: maxTitle.toDouble(),
              min: 10,
              max: 120,
              divisions: 22,
              onChanged: busy
                  ? null
                  : (v) => setState(() => maxTitle = v.round()),
            ),
            OutlinedButton(
              onPressed: busy ? null : () => _run(_preview),
              child: const Text('预览分章'),
            ),
          ],
          if (candidate case final draft?) ...[
            const SizedBox(height: 16),
            Text('预览：${draft.chapterCount} 章，${draft.blocks} 个文本块；仅展示前20章。'),
            for (final c in draft.preview) Text('${c.ordinal + 1}. ${c.title}'),
            FilledButton(
              onPressed: busy ? null : () => _run(_apply),
              child: const Text('确认使用此目录'),
            ),
          ],
        ],
      );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: constraints.maxHeight * .42),
            child: SingleChildScrollView(child: controls),
          ),
          if (reading case final r?)
            ReadingTools(
              session: r,
              onBack: r.history.isEmpty
                  ? null
                  : () => _run((job) async {
                      final a = r.popHistory()!;
                      await _read(int.parse(a.blockId.substring(1)), job);
                      setState(() => target = a);
                    }),
              onProgress: (v) {
                r.rememberJump();
                _run((job) => _read((v * (index!.blocks - 1)).round(), job));
              },
            ),
          if (page case final p?)
            Expanded(
              child: StreamBuilder<void>(
                stream: reading?.changes,
                builder: (context, _) => TextReadingSurface(
                  page: p,
                  preferences:
                      reading?.preferences ?? const ReadingPreferences(),
                  anchor: target,
                  onAnchor: (a) => reading?.observe(a),
                  onPrevious: p.blocks.first.ordinal == 0
                      ? null
                      : () => _run(
                          (j) => _read(
                            (p.blocks.first.ordinal - 8).clamp(
                              0,
                              index!.blocks - 1,
                            ),
                            j,
                            atEnd: true,
                          ),
                        ),
                  onNext: p.blocks.last.ordinal + 1 >= index!.blocks
                      ? null
                      : () => _run((j) => _read(p.blocks.last.ordinal + 1, j)),
                ),
              ),
            ),
          if (page != null)
            TextButton(
              onPressed: () => _run((j) async {
                final r = reading;
                final a = r?.anchor ?? page!.anchor(page!.blocks.first);
                if (r != null) {
                  r.observe(a, explicit: true);
                  await r.flush();
                  if (r.needsReview || r.error != null) {
                    throw const AppFailure(FailureCode.unexpected);
                  }
                  sequence = r.sequence;
                } else {
                  final saved = await widget.deps.positions!.savePosition(
                    widget.bookId,
                    PositionChannel.reading,
                    a,
                    expectedSequence: sequence,
                  );
                  sequence = saved.sequence;
                }
                j.checkCancelled();
                setState(() => notice = '已记住这个文本块。');
              }),
              child: const Text('记住这一段'),
            ),
        ],
      );
    },
  );
}
