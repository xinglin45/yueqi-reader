import 'package:flutter/material.dart';

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
  TxtPage? page;
  bool busy = false, cancelled = false, rulesVisible = false;
  double? progress;
  String? notice, error, remembered;
  int sequence = 0, generation = 0;
  TxtHeadings headings = TxtHeadings.standard;
  int maxTitle = 80;
  final prefix = TextEditingController();
  final top = GlobalKey();
  @override
  void initState() {
    super.initState();
    _run(_open);
  }

  @override
  void dispose() {
    generation++;
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
      isCurrent: () => mounted && generation == ticket && !cancelled,
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
    final saved = await widget.deps.positions?.loadPosition(
      widget.bookId,
      PositionChannel.reading,
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
        notice = '已恢复到上次记住的文本块。';
      } else {
        notice = '旧位置未精确匹配，已保留原记录，请重新选择。';
      }
    }
    job.checkCancelled();
    setState(() {});
  }

  Future<void> _read(int first, JobContext job) async {
    final next = await reader.read(index!, first, job);
    job.checkCancelled();
    setState(() => page = next);
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
      builder: (dialog) => StatefulBuilder(
        builder: (dialog, update) => AlertDialog(
          title: Text('章节目录 · ${active.chapterCount} 章'),
          content: SizedBox(
            width: 440,
            height: 420,
            child: FutureBuilder<List<TxtChapter>>(
              future: result,
              builder: (context, snapshot) {
                if (snapshot.hasError) return const Text('目录暂不可用，请返回检查原件与权限。');
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
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
                      offset = (offset - 20).clamp(0, active.chapterCount);
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
    );
    final block = await Navigator.of(context).push(route);
    await route.completed;
    if (block != null && mounted) await _run((job) => _read(block, job));
  }

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topLeft,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 680),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
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
          if (page case final p?)
            KeyedSubtree(
              key: ValueKey('txt-page:${p.index.id}:${p.blocks.first.ordinal}'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 24),
                  Text(
                    p.chapter.title,
                    style: const TextStyle(
                      fontFamily: 'Songti SC',
                      fontSize: 30,
                      height: 1.5,
                    ),
                  ),
                  const Divider(),
                  for (final b in p.blocks)
                    Padding(
                      padding: const EdgeInsets.only(top: 18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SelectableText(
                            b.text,
                            style: const TextStyle(
                              fontFamily: 'Songti SC',
                              fontFamilyFallback: ['STSong', 'serif'],
                              fontSize: 24,
                              height: 1.9,
                            ),
                          ),
                          if (b.continuation)
                            const Text('长段落接续', style: TextStyle(fontSize: 11)),
                          if (remembered == b.id) const Text('上次记住的位置'),
                          if (b.text.trim().isNotEmpty)
                            TextButton(
                              onPressed: busy
                                  ? null
                                  : () => _run((job) async {
                                      final saved = await widget.deps.positions!
                                          .savePosition(
                                            widget.bookId,
                                            PositionChannel.reading,
                                            p.anchor(b),
                                            expectedSequence: sequence,
                                          );
                                      job.checkCancelled();
                                      setState(() {
                                        sequence = saved.sequence;
                                        remembered = b.id;
                                        notice = '已记住这个文本块。';
                                      });
                                    }),
                              child: const Text('记住这一段'),
                            ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 20),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      TextButton(
                        onPressed: busy || p.blocks.first.ordinal == 0
                            ? null
                            : () => _run(
                                (job) => _read(
                                  (p.blocks.first.ordinal - 8).clamp(
                                    0,
                                    index!.blocks - 1,
                                  ),
                                  job,
                                ),
                              ),
                        child: const Text('上一段内容'),
                      ),
                      FilledButton(
                        onPressed:
                            busy || p.blocks.last.ordinal + 1 >= index!.blocks
                            ? null
                            : () => _run(
                                (job) => _read(p.blocks.last.ordinal + 1, job),
                              ),
                        child: const Text('下一段内容'),
                      ),
                      Text(
                        '文本块 ${p.blocks.first.ordinal + 1}–${p.blocks.last.ordinal + 1} / ${index!.blocks}',
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    '已按需读取 TXT 正文。自动滚动进度、分页与完整排版将在后续阅读器步骤接入。',
                    style: TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
        ],
      ),
    ),
  );
}
