import 'dart:async';

import 'package:flutter/material.dart';
import 'package:platform_services/platform_services.dart';

import '../app/dependencies.dart';
import '../domain/access.dart';
import '../domain/importing.dart';
import '../domain/jobs.dart';
import 'access_controls.dart';

String importHelp(ImportIssue issue) => switch (issue) {
  ImportIssue.unsupported => '不支持此格式、加密或压缩方式；本步支持TXT与常规EPUB。',
  ImportIssue.tooLarge => '文件或解压后内容超过当前导入上限（原文件64 MiB）。',
  ImportIssue.encoding => '无法完整解码，请选择编码并重新预览；没有替换或忽略原文字节。',
  ImportIssue.corrupt => '文件结构或完整性检查失败，请保留原件并重新选择。',
  ImportIssue.permission => '文件授权或内容权限不可用，请重新选择或检查成年声明与隐私锁。',
  ImportIssue.missing => '文件已丢失，请重新选择。',
  ImportIssue.changed => '内容已改变，未覆盖旧修订或位置。请作为新文件导入，或关联内容相同的原件。',
  ImportIssue.disk => '未能完成本地保存，请检查资料目录或剩余空间后重试。',
  ImportIssue.cancelled => '未提交的文件已取消；此前已完成的文件会保留。',
  ImportIssue.classification => '请先选择普通或成人分级；未知分级不会自动归入普通书架。',
};
Future<void> showImportFlow(
  BuildContext context,
  AppDependencies deps, {
  List<FileGrant>? grants,
}) => showDialog<void>(
  context: context,
  builder: (_) => _ImportDialog(deps: deps, initial: grants),
);

class _Row {
  _Row(this.grant);
  final FileGrant grant;
  ImportPreview? preview;
  RatingLevel rating = RatingLevel.unknown;
  TextEncoding encoding = TextEncoding.auto;
  ImportMode mode = ImportMode.managed;
  String? message;
  ImportReceipt? receipt;
}

class _ImportDialog extends StatefulWidget {
  const _ImportDialog({required this.deps, this.initial});
  final AppDependencies deps;
  final List<FileGrant>? initial;
  @override
  State<_ImportDialog> createState() => _ImportDialogState();
}

class _ImportDialogState extends State<_ImportDialog> {
  final rows = <_Row>[];
  bool busy = false, cancelled = false;
  double? progress;
  String? notice;
  Future<void>? work;
  StreamSubscription<AccessState>? subscription;
  DocumentImporter get importer => widget.deps.importer!;
  DocumentAccess get files => widget.deps.files as DocumentAccess;
  JobContext get job => JobContext(
    id: 1,
    isCurrent: () => mounted && !cancelled,
    report: (p) {
      if (mounted) setState(() => progress = p);
    },
  );
  @override
  void initState() {
    super.initState();
    subscription = widget.deps.access?.changes.listen((state) {
      if (!state.adultVisible &&
          rows.any((r) => r.rating == RatingLevel.restricted)) {
        cancelled = true;
        for (final row in rows.where(
          (r) => r.rating == RatingLevel.restricted,
        )) {
          final preview = row.preview;
          row.preview = null;
          row.message = '受保护预览已清除，请解锁后重新预览。';
          if (preview != null) unawaited(importer.discard(preview.id));
        }
      }
      if (mounted) setState(() {});
    });
    work = _choose(widget.initial);
  }

  Future<void> _choose(List<FileGrant>? initial) async {
    setState(() {
      busy = true;
      notice = null;
    });
    try {
      final picked = initial == null
          ? await files.chooseDocuments()
          : PlatformSuccess<List<FileGrant>>(initial);
      if (picked is! PlatformSuccess<List<FileGrant>>) {
        notice = '未能选择文件，请重试。';
        return;
      }
      rows.addAll(picked.value.take(32).map(_Row.new));
      for (final row in rows) {
        job.checkCancelled();
        await _prepare(row);
      }
      if (rows.isEmpty) notice = '未选择文件，可以再次选择。';
    } on JobCancelled {
      notice = importHelp(ImportIssue.cancelled);
    } catch (_) {
      notice = '文件选择未完成，请重试。';
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _prepare(_Row row) async {
    try {
      if (row.preview != null) await importer.discard(row.preview!.id);
      row.preview = null;
      row.message = null;
      final preview = await importer.prepare(row.grant, job);
      if (row.rating == RatingLevel.restricted &&
          !(widget.deps.access?.state.adultVisible ?? false)) {
        await importer.discard(preview.id);
        return;
      }
      row.preview = row.encoding == TextEncoding.auto
          ? preview
          : await importer.inspect(preview.id, row.encoding, job);
    } on ImportFailure catch (e) {
      row.message = importHelp(e.issue);
    }
    if (mounted) setState(() {});
  }

  Future<void> _reinspect(_Row row, TextEncoding encoding) async {
    setState(() => busy = true);
    cancelled = false;
    try {
      row.encoding = encoding;
      if (row.preview == null) {
        await _prepare(row);
      } else {
        row.preview = await importer.inspect(row.preview!.id, encoding, job);
      }
    } on ImportFailure catch (e) {
      row.message = importHelp(e.issue);
    } on JobCancelled {
      notice = importHelp(ImportIssue.cancelled);
    } catch (_) {
      notice = importHelp(ImportIssue.disk);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _commit() async {
    setState(() => busy = true);
    cancelled = false;
    try {
      for (final row in rows) {
        job.checkCancelled();
        if (row.preview == null ||
            row.preview!.issue != null ||
            row.rating == RatingLevel.unknown ||
            row.receipt != null) {
          continue;
        }
        try {
          row.receipt = await importer.commit(
            row.preview!.id,
            mode: row.mode,
            rating: row.rating,
            job: job,
          );
          row.preview = null;
          row.message = row.receipt!.repaired
              ? '已修复已有托管副本，原分级与位置保留。'
              : row.receipt!.duplicate
              ? '已有相同文件，已跳过；原有分级与位置保留。'
              : '文件已入库；TXT/EPUB可在书架打开阅读。';
        } on ImportFailure catch (e) {
          row.message = importHelp(e.issue);
        }
        if (mounted) setState(() {});
      }
    } on JobCancelled {
      notice = importHelp(ImportIssue.cancelled);
    } catch (_) {
      notice = importHelp(ImportIssue.disk);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    cancelled = true;
    subscription?.cancel();
    unawaited(_cleanup());
    super.dispose();
  }

  Future<void> _cleanup() async {
    try {
      await work;
    } catch (_) {}
    for (final row in rows) {
      try {
        if (row.preview != null) await importer.discard(row.preview!.id);
      } catch (_) {}
      try {
        await files.releaseGrant(row.grant);
      } catch (_) {}
    }
  }

  Widget _row(_Row row, int index) {
    final visible =
        row.rating == RatingLevel.general ||
        (row.rating == RatingLevel.restricted &&
            (widget.deps.access?.state.adultVisible ?? false));
    final preview = row.preview;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            visible ? row.grant.displayName : '文件 ${index + 1} · 选择分级后显示预览',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          if (row.receipt == null) ...[
            const SizedBox(height: 12),
            DropdownButtonFormField<RatingLevel>(
              initialValue: row.rating,
              decoration: const InputDecoration(labelText: '本机分级'),
              items: [
                for (final (level, label) in [
                  (RatingLevel.unknown, '未分类（暂不导入）'),
                  (RatingLevel.general, '普通'),
                  (RatingLevel.restricted, '成人（独立分组）'),
                ])
                  DropdownMenuItem(value: level, child: Text(label)),
              ],
              onChanged: busy ? null : (v) => setState(() => row.rating = v!),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<ImportMode>(
              initialValue: row.mode,
              decoration: const InputDecoration(labelText: '导入模式'),
              items: const [
                DropdownMenuItem(
                  value: ImportMode.managed,
                  child: Text('托管副本（默认，保留原件）'),
                ),
                DropdownMenuItem(
                  value: ImportMode.reference,
                  child: Text('引用原件（重启后使用系统授权）'),
                ),
              ],
              onChanged: busy ? null : (v) => setState(() => row.mode = v!),
            ),
            if (preview?.kind == 'txt') ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<TextEncoding>(
                initialValue: row.encoding,
                decoration: const InputDecoration(labelText: 'TXT编码'),
                items: [
                  for (final e in TextEncoding.values)
                    DropdownMenuItem(
                      value: e,
                      child: Text(
                        e == TextEncoding.auto ? '自动：UTF-8 / BOM' : e.name,
                      ),
                    ),
                ],
                onChanged: busy
                    ? null
                    : (e) {
                        work = _reinspect(row, e!);
                      },
              ),
            ],
            if (row.rating == RatingLevel.restricted &&
                !(widget.deps.access?.state.acknowledged ?? false))
              TextButton(
                onPressed: () =>
                    showAdultDeclaration(context, widget.deps.access!),
                child: const Text('查看成年声明'),
              ),
            if (preview != null && visible) ...[
              const SizedBox(height: 12),
              Text(
                '${preview.title} · ${preview.bytes} 字节 · ${preview.encoding?.name ?? (preview.kind == 'txt' ? '待确认编码' : 'EPUB容器检查')}',
              ),
              if (preview.issue != null)
                Text(importHelp(preview.issue!))
              else if (preview.excerpt.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: SelectableText(preview.excerpt, maxLines: 8),
                ),
            ],
            if (!busy && (row.message != null || row.preview == null))
              TextButton(
                onPressed: () {
                  work = _reinspect(row, row.encoding);
                },
                child: const Text('重新预览'),
              ),
          ],
          if (row.message != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(row.message!),
            ),
          const Divider(),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('导入书籍'),
    content: SizedBox(
      width: 580,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '先选择分级并检查预览，再确认导入。支持批量TXT/EPUB，每批最多32个，每个文件最多64 MiB。托管或引用均不修改外部原件。',
            ),
            if (busy) ...[
              const SizedBox(height: 16),
              LinearProgressIndicator(value: progress),
              const Text('正在检查文件；取消只停止未提交项。'),
            ],
            if (notice != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(notice!),
              ),
            for (final (i, row) in rows.indexed) _row(row, i),
            if (rows.isEmpty && !busy)
              TextButton(
                onPressed: () {
                  cancelled = false;
                  work = _choose(null);
                },
                child: const Text('选择TXT / EPUB'),
              ),
          ],
        ),
      ),
    ),
    actions: [
      if (busy)
        TextButton(
          onPressed: () => setState(() => cancelled = true),
          child: const Text('取消未提交项'),
        ),
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('返回书架'),
      ),
      FilledButton(
        onPressed:
            busy ||
                !rows.any(
                  (r) =>
                      r.receipt == null &&
                      r.preview != null &&
                      r.preview!.issue == null &&
                      r.rating != RatingLevel.unknown &&
                      (r.rating == RatingLevel.general ||
                          (widget.deps.access?.state.adultVisible ?? false)),
                )
            ? null
            : () {
                work = _commit();
              },
        child: const Text('确认导入可用文件'),
      ),
    ],
  );
}

Future<void> showImportedStatus(
  BuildContext context,
  AppDependencies deps,
  String bookId,
) async {
  final importer = deps.importer;
  if (importer == null) return;
  JobContext job() =>
      JobContext(id: 1, isCurrent: () => context.mounted, report: (_) {});
  String message;
  var reference = false;
  try {
    final info = await importer.information(bookId);
    reference = info.mode == ImportMode.reference;
    await importer.verify(bookId, job());
    message =
        '${info.mode == ImportMode.managed ? '托管副本完整，原文件移动或删除不影响此副本。' : '引用仍可访问；未创建永久托管副本。'}\n文件已入库；TXT可预览分章后阅读，EPUB可直接在书架打开。';
  } on ImportFailure catch (e) {
    message =
        '${importHelp(e.issue)}${reference ? '' : '\n可重新导入相同原件以修复托管副本，保留现有书籍记录。'}';
  } on AppFailure {
    message = importHelp(ImportIssue.permission);
  } on JobCancelled {
    return;
  } catch (_) {
    message = importHelp(ImportIssue.disk);
  }
  if (!context.mounted) return;
  final route = DialogRoute<void>(
    context: context,
    builder: (dialog) => AlertDialog(
      title: const Text('本地文件状态'),
      content: Text(message),
      actions: [
        if (reference)
          TextButton(
            onPressed: () async {
              final selected = await deps.files.chooseDocument();
              if (selected is! PlatformSuccess<FileGrant?> ||
                  selected.value == null) {
                return;
              }
              try {
                await importer.relink(bookId, selected.value!, job());
                if (dialog.mounted) Navigator.pop(dialog);
              } on ImportFailure catch (e) {
                if (dialog.mounted) {
                  ScaffoldMessenger.of(
                    dialog,
                  ).showSnackBar(SnackBar(content: Text(importHelp(e.issue))));
                }
              } on AppFailure {
                if (dialog.mounted) Navigator.pop(dialog);
              } on JobCancelled {
                return;
              } catch (_) {
                if (dialog.mounted) {
                  ScaffoldMessenger.of(dialog).showSnackBar(
                    SnackBar(content: Text(importHelp(ImportIssue.disk))),
                  );
                }
              } finally {
                if (deps.files is DocumentAccess) {
                  await (deps.files as DocumentAccess).releaseGrant(
                    selected.value!,
                  );
                }
              }
            },
            child: const Text('重新关联相同原件（引用模式）'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(dialog),
          child: const Text('返回'),
        ),
      ],
    ),
  );
  await Navigator.of(context).push(route);
  await route.completed;
}
