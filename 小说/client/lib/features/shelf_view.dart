import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:platform_services/platform_services.dart';

import '../app/dependencies.dart';
import '../app/navigation.dart';
import '../domain/jobs.dart';
import '../domain/library.dart';
import '../domain/shelf.dart';
import 'access_controls.dart';
import 'import_flow.dart';

String stateLabel(ReadingState s) => switch (s) {
  ReadingState.unread => '未读',
  ReadingState.reading => '在读',
  ReadingState.finished => '读完',
};
String healthLabel(String s) => switch (s) {
  'available' => '本机可用',
  'missing' => '文件缺失',
  'permission' => '需恢复授权',
  'changed' => '原件已改变',
  'recycled' => '托管副本在回收区',
  'unknown' => '待检查',
  _ => '需检查文件',
};

class BookArtwork extends StatefulWidget {
  const BookArtwork({
    super.key,
    required this.book,
    required this.deps,
    this.width = 120,
  });
  final BookSummary book;
  final AppDependencies deps;
  final double width;
  @override
  State<BookArtwork> createState() => _BookArtworkState();
}

class _BookArtworkState extends State<BookArtwork> {
  Future<Uint8List?>? future;
  MemoryImage? provider;
  bool hidden = false;
  void Function()? stop;
  @override
  void initState() {
    super.initState();
    future = widget.deps.shelf?.cover(widget.book.id);
    stop = widget.deps.access?.registerProtectedStop(() {
      hidden = true;
      unawaited(provider?.evict());
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    stop?.call();
    unawaited(provider?.evict());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: widget.width,
    height: widget.width * 1.5,
    child: hidden
        ? const Icon(Icons.lock_outline)
        : FutureBuilder<Uint8List?>(
            future: future,
            builder: (context, snapshot) {
              if (snapshot.hasData) {
                provider ??= MemoryImage(snapshot.data!);
                return Image(
                  image: provider!,
                  fit: BoxFit.cover,
                  excludeFromSemantics: true,
                );
              }
              return widget.book.demo
                  ? Image.asset(
                      'assets/mountain-letter-cover.png',
                      fit: BoxFit.cover,
                      excludeFromSemantics: true,
                    )
                  : DecoratedBox(
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Icon(Icons.menu_book_outlined, size: 36),
                    );
            },
          ),
  );
}

class ManagedShelf extends StatefulWidget {
  const ManagedShelf({
    super.key,
    required this.deps,
    required this.navigation,
    this.recent = false,
    this.onImport,
  });
  final AppDependencies deps;
  final AppNavigation navigation;
  final bool recent;
  final VoidCallback? onImport;
  @override
  State<ManagedShelf> createState() => _ManagedShelfState();
}

class _ManagedShelfState extends State<ManagedShelf> {
  ShelfRepository get repo => widget.deps.shelf!;
  ShelfScope scope = ShelfScope.normal;
  ShelfOptions options = const ShelfOptions();
  ShelfPage? data;
  bool busy = true;
  String? error, lastAction;
  int generation = 0, page = 0;
  final selected = <String>{};
  final search = TextEditingController();
  Timer? debounce;
  bool get visible =>
      scope == ShelfScope.normal ||
      widget.deps.access?.state.adultVisible == true;
  @override
  void initState() {
    super.initState();
    unawaited(_initialize());
  }

  @override
  void dispose() {
    generation++;
    debounce?.cancel();
    search.dispose();
    super.dispose();
  }

  Future<void> _initialize() async {
    final initialScope = scope;
    final initialGeneration = ++generation;
    try {
      final saved = await repo.preferences(scope, recent: widget.recent);
      final undo = await repo.latestAction(initialScope);
      if (!mounted ||
          initialScope != scope ||
          initialGeneration != generation ||
          !visible) {
        return;
      }
      options = saved;
      search.text = saved.search;
      lastAction = undo;
      await _load();
    } catch (_) {
      if (mounted) {
        setState(() {
          busy = false;
          error = '未能载入书架设置，请重试。';
        });
      }
    }
  }

  Future<void> _load() async {
    final current = ++generation;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await repo.list(
        scope,
        options,
        JobContext(
          id: current,
          isCurrent: () => mounted && generation == current && visible,
          report: (_) {},
        ),
        page: page,
        recent: widget.recent,
      );
      if (!mounted || current != generation || !visible) return;
      setState(() {
        data = result;
        busy = false;
        selected.removeWhere((id) => !result.books.any((b) => b.book.id == id));
      });
    } catch (_) {
      if (mounted && current == generation) {
        setState(() {
          busy = false;
          error = '未能读取书架，原资料仍保留。';
        });
      }
    }
  }

  Future<void> _options(ShelfOptions next) async {
    options = next;
    page = 0;
    selected.clear();
    await _load();
    try {
      await repo.savePreferences(scope, next, recent: widget.recent);
    } catch (_) {
      _notice('筛选已生效，但未能保存设置。');
    }
  }

  void _notice(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  Future<void> _work(
    Future<Object?> Function() operation, {
    bool undo = false,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    setState(() => busy = true);
    try {
      final result = await operation();
      if (undo && result is String) {
        lastAction = result;
        messenger.showSnackBar(
          SnackBar(
            content: const Text('已保存，可撤销本次管理。'),
            action: SnackBarAction(
              label: '撤销',
              onPressed: () async {
                try {
                  await repo.undo(result);
                  if (mounted) {
                    lastAction = null;
                    await _load();
                  }
                } catch (_) {
                  messenger.showSnackBar(
                    const SnackBar(content: Text('记录已变化，未覆盖较新的更改。')),
                  );
                }
              },
            ),
          ),
        );
      }
      if (mounted) {
        selected.clear();
        await _load();
      }
    } catch (_) {
      if (mounted) {
        setState(() => busy = false);
        _notice('操作未完成。请刷新后重试；较新的记录和原文件会保留。');
      }
    }
  }

  Future<T?> _dialog<T>(Widget Function(BuildContext) builder) async {
    final route = DialogRoute<T>(
      context: context,
      builder: (ctx) => StreamBuilder(
        stream: widget.deps.access?.changes,
        builder: (ctx, _) {
          if (scope == ShelfScope.adult &&
              widget.deps.access?.state.adultVisible != true) {
            return AlertDialog(
              title: const Text('内容已隐藏'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('返回'),
                ),
              ],
            );
          }
          return builder(ctx);
        },
      ),
    );
    final result = await Navigator.of(context).push(route);
    await route.completed;
    return result;
  }

  Future<bool> _confirm(String title, String message) async =>
      await _dialog<bool>(
        (ctx) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('确认'),
            ),
          ],
        ),
      ) ==
      true;
  Map<String, int> get revisions => {
    for (final b in data!.books)
      if (selected.contains(b.book.id)) b.book.id: b.revision,
  };
  Future<void> _apply(BookEdit e) =>
      _work(() => repo.edit(revisions, e), undo: true);
  void _open(ShelfBook b) {
    if (b.removed || b.recycled) {
      _notice('请先从回收区恢复书籍或托管副本。');
      return;
    }
    widget.navigation.go(AppLocation(AppPage.reader, bookId: b.book.id));
  }

  Future<void> _groupEditor([ShelfGroup? group]) async {
    final field = TextEditingController(text: group?.label ?? '');
    var kind = group?.kind ?? 'collection';
    final result = await _dialog<bool>(
      (ctx) => StatefulBuilder(
        builder: (ctx, update) => AlertDialog(
          title: Text(group == null ? '新建合集或标签' : '重命名分组'),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  key: const ValueKey('group-label'),
                  controller: field,
                  maxLength: 80,
                  decoration: const InputDecoration(labelText: '名称'),
                ),
                if (group == null)
                  DropdownButton<String>(
                    value: kind,
                    items: const [
                      DropdownMenuItem(value: 'collection', child: Text('合集')),
                      DropdownMenuItem(value: 'tag', child: Text('标签')),
                    ],
                    onChanged: (v) => update(() => kind = v!),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('保存分组'),
            ),
          ],
        ),
      ),
    );
    final label = field.text;
    field.dispose();
    if (result == true && mounted) {
      await _work(
        () => group == null
            ? repo.createGroup(scope, label, kind)
            : repo.renameGroup(scope, group.id, label),
      );
    }
  }

  Future<void> _assignGroups() async {
    final groups = data!.groups.where((g) => !g.removed).toList();
    final picked = <String>{};
    final result = await _dialog<bool>(
      (ctx) => StatefulBuilder(
        builder: (ctx, update) => AlertDialog(
          title: const Text('设置合集与标签'),
          content: SizedBox(
            width: 380,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('将选中书籍的自定义归属替换为以下选择；成人独立分组保留。'),
                  for (final g in groups)
                    CheckboxListTile(
                      value: picked.contains(g.id),
                      title: Text(
                        '${g.kind == 'tag' ? '标签' : '合集'} · ${g.label}',
                      ),
                      onChanged: (v) => update(
                        () =>
                            v == true ? picked.add(g.id) : picked.remove(g.id),
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('保存归属'),
            ),
          ],
        ),
      ),
    );
    if (result == true && mounted) {
      await _apply(BookEdit(groups: picked.toList()));
    }
  }

  Future<void> _details(ShelfBook b) async {
    final title = TextEditingController(text: b.book.title),
        author = TextEditingController(text: b.author),
        synopsis = TextEditingController(text: b.synopsis),
        order = TextEditingController(text: '${b.order}');
    var language = b.language;
    final result = await _dialog<String>(
      (ctx) => StatefulBuilder(
        builder: (ctx, update) => AlertDialog(
          title: const Text('书籍详情'),
          content: SizedBox(
            width: 540,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    key: const ValueKey('edit-title'),
                    controller: title,
                    maxLength: 200,
                    decoration: const InputDecoration(labelText: '书名'),
                  ),
                  TextField(
                    key: const ValueKey('edit-author'),
                    controller: author,
                    maxLength: 200,
                    decoration: const InputDecoration(labelText: '作者'),
                  ),
                  TextField(
                    controller: synopsis,
                    maxLength: 4000,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(labelText: '简介'),
                  ),
                  DropdownButton<String>(
                    value: const ['zh', 'zh-Hans', 'zh-Hant'].contains(language)
                        ? language
                        : 'zh',
                    items: const [
                      DropdownMenuItem(value: 'zh', child: Text('中文')),
                      DropdownMenuItem(value: 'zh-Hans', child: Text('简体中文')),
                      DropdownMenuItem(value: 'zh-Hant', child: Text('繁体中文')),
                    ],
                    onChanged: (v) => update(() => language = v!),
                  ),
                  TextField(
                    controller: order,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: '手动序号（小的在前，默认0）',
                    ),
                  ),
                  Text(
                    '${b.format.toUpperCase()} · ${b.mode == 'reference'
                        ? '系统书签引用'
                        : b.mode == 'managed'
                        ? '应用托管副本'
                        : '自产样本'} · ${b.bytes} 字节\n${healthLabel(b.health)}\n${b.similarTitles > 0 ? '存在同名书籍：保留独立版本，不按书名合并。' : '重复检查依据文件摘要；书名与作者仅供人工辨认。'}',
                    style: const TextStyle(height: 1.7),
                  ),
                  if (b.sourceName.isNotEmpty) Text('导入文件名：${b.sourceName}'),
                  const Text('编辑只影响本地元数据，不重写原文件。用户导入不代表作品许可已获核验。'),
                  Wrap(
                    spacing: 8,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, 'cover'),
                        child: const Text('选择本地封面'),
                      ),
                      if (b.cover)
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, 'clearCover'),
                          child: const Text('恢复默认封面'),
                        ),
                      if (b.mode != 'sample' && !b.recycled)
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, 'file'),
                          child: const Text('检查/重新关联文件'),
                        ),
                      if (b.mode == 'managed')
                        TextButton(
                          onPressed: () => Navigator.pop(
                            ctx,
                            b.recycled ? 'restoreFile' : 'recycleFile',
                          ),
                          child: Text(b.recycled ? '恢复托管副本' : '托管副本移入回收区'),
                        ),
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, 'records'),
                        child: const Text('移除个人记录（可撤销）'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            FilledButton(
              key: const ValueKey('save-book-details'),
              onPressed: () => Navigator.pop(ctx, 'save'),
              child: const Text('保存详情'),
            ),
          ],
        ),
      ),
    );
    final edit = BookEdit(
      title: title.text,
      author: author.text,
      synopsis: synopsis.text,
      language: language,
      order: int.tryParse(order.text) ?? -1,
    );
    title.dispose();
    author.dispose();
    synopsis.dispose();
    order.dispose();
    if (!mounted) return;
    if (result == 'save') {
      await _work(() => repo.edit({b.book.id: b.revision}, edit), undo: true);
    }
    if (result == 'cover') await _pickCover(b);
    if (result == 'clearCover') {
      await _work(() => repo.setCover(b.book.id, b.revision, null), undo: true);
    }
    if (!mounted) return;
    if (result == 'file') {
      await showImportedStatus(context, widget.deps, b.book.id);
      if (mounted) {
        await _work(
          () => repo.checkFile(
            b.book.id,
            JobContext(
              id: 0,
              isCurrent: () => mounted && visible,
              report: (_) {},
            ),
          ),
        );
      }
    }
    if (result == 'recycleFile' &&
        await _confirm(
          '回收托管副本',
          '正文将从可读目录移入应用回收区，仍占磁盘空间，可稍后恢复。书架、位置和笔记保留；不会删除外部原件。',
        )) {
      await _work(() => repo.recycleFile(b.book.id));
    }
    if (result == 'restoreFile') await _work(() => repo.restoreFile(b.book.id));
    if (result == 'records' &&
        await _confirm(
          '移除个人记录',
          '移除本书阅读/听书位置及已有书签、笔记。正文和书架保留，可撤销；撤销遇到新记录时停止，避免覆盖。',
        )) {
      await _work(
        () => repo.edit({
          b.book.id: b.revision,
        }, const BookEdit(clearRecords: true)),
        undo: true,
      );
    }
  }

  Future<void> _pickCover(ShelfBook b) async {
    final files = widget.deps.files;
    if (files is! CoverAccess || files is! DocumentAccess) {
      _notice('当前平台尚未接入封面选择。');
      return;
    }
    final picked = await (files as CoverAccess).chooseCover();
    if (picked is! PlatformSuccess<FileGrant?> || picked.value == null) return;
    final grant = picked.value!;
    try {
      final builder = BytesBuilder(copy: false);
      await for (final chunk in (files).readDocument(grant)) {
        if (builder.length + chunk.length > 4 * 1024 * 1024) {
          throw const FormatException('cover_budget');
        }
        builder.add(chunk);
      }
      if (mounted && visible) {
        await _work(
          () => repo.setCover(b.book.id, b.revision, builder.takeBytes()),
          undo: true,
        );
      }
    } catch (_) {
      _notice('封面未更改。请选择4 MiB内、最长边4096且不超过8M像素的单帧PNG/JPEG。');
    } finally {
      await (files).releaseGrant(grant);
    }
  }

  Widget _choice<T>(
    T value,
    List<(T, String)> choices,
    ValueChanged<T> change,
  ) => DropdownButton<T>(
    value: value,
    items: [
      for (final c in choices) DropdownMenuItem(value: c.$1, child: Text(c.$2)),
    ],
    onChanged: busy
        ? null
        : (v) {
            if (v != null) change(v);
          },
  );
  @override
  Widget build(BuildContext context) {
    final access = widget.deps.access;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '留一点时间，给阅读',
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.recent ? '最近阅读' : '我的书架',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                ],
              ),
            ),
            FilledButton.icon(
              key: const ValueKey('import-book'),
              onPressed: busy ? null : widget.onImport,
              icon: const Icon(Icons.add),
              label: const Text('导入书籍'),
            ),
          ],
        ),
        const SizedBox(height: 24),
        if (!widget.recent)
          Wrap(
            spacing: 8,
            children: [
              for (final s in ShelfScope.values)
                TextButton(
                  onPressed: () async {
                    generation++;
                    scope = s;
                    page = 0;
                    selected.clear();
                    data = null;
                    if (visible) {
                      await _initialize();
                    } else {
                      setState(() => busy = false);
                    }
                  },
                  child: Text(s == ShelfScope.normal ? '全部书籍' : '成人收藏'),
                ),
            ],
          ),
        if (!visible && access != null)
          AdultCollection(
            dependencies: widget.deps,
            access: access,
            library: widget.deps.library as AdultLibrary,
            navigation: widget.navigation,
          )
        else ...[
          Wrap(
            spacing: 16,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _choice(options.state, [
                ('', '全部状态'),
                for (final s in ReadingState.values) (s.name, stateLabel(s)),
              ], (v) => _options(options.change(state: v))),
              _choice(options.sort, [
                for (final s in ShelfSort.values)
                  (
                    s,
                    switch (s) {
                      ShelfSort.manual => '手动排序',
                      ShelfSort.title => '书名排序',
                      ShelfSort.author => '作者排序',
                      ShelfSort.recent => '最近阅读排序',
                      ShelfSort.added => '最近加入排序',
                    },
                  ),
              ], (v) => _options(options.change(sort: v))),
              _choice(options.format, const [
                ('', '全部格式'),
                ('txt', 'TXT'),
                ('epub', 'EPUB'),
              ], (v) => _options(options.change(format: v))),
              _choice(
                data?.groups.any((g) => g.id == options.group && !g.removed) ==
                        true
                    ? options.group
                    : '',
                [
                  ('', '全部合集/标签'),
                  for (final g in data?.groups ?? <ShelfGroup>[])
                    if (!g.removed) (g.id, g.label),
                ],
                (v) => _options(options.change(group: v)),
              ),
              FilterChip(
                label: const Text('收藏'),
                selected: options.favorite,
                onSelected: busy
                    ? null
                    : (v) => _options(options.change(favorite: v)),
              ),
              FilterChip(
                label: const Text('已移出书架'),
                selected: options.removed,
                onSelected: busy
                    ? null
                    : (v) => _options(options.change(removed: v)),
              ),
              IconButton(
                tooltip: options.grid ? '切换列表' : '切换网格',
                onPressed: busy
                    ? null
                    : () => _options(options.change(grid: !options.grid)),
                icon: Icon(
                  options.grid
                      ? Icons.view_list_outlined
                      : Icons.grid_view_outlined,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            key: const ValueKey('shelf-search'),
            controller: search,
            decoration: const InputDecoration(
              hintText: '搜索书名、作者或标签',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (v) {
              debounce?.cancel();
              debounce = Timer(
                const Duration(milliseconds: 300),
                () => _options(options.change(search: v)),
              );
            },
          ),
          Wrap(
            spacing: 8,
            children: [
              TextButton(
                onPressed: busy ? null : () => _groupEditor(),
                child: const Text('新建合集/标签'),
              ),
              if (lastAction != null)
                TextButton(
                  key: const ValueKey('undo-shelf'),
                  onPressed: busy
                      ? null
                      : () => _work(() async {
                          await repo.undo(lastAction!);
                          lastAction = null;
                          return null;
                        }),
                  child: const Text('撤销上次管理'),
                ),
              TextButton(
                onPressed: busy ? null : () => _load(),
                child: const Text('刷新书架'),
              ),
            ],
          ),
          if (data?.groups.isNotEmpty ?? false)
            Wrap(
              spacing: 8,
              children: [
                for (final g in data!.groups)
                  InputChip(
                    label: Text(
                      '${g.kind == 'tag' ? '#' : ''}${g.label}${g.removed ? '（已停用）' : ''}',
                    ),
                    onPressed: busy
                        ? null
                        : () => g.removed
                              ? _work(
                                  () => repo.removeGroup(
                                    scope,
                                    g.id,
                                    removed: false,
                                  ),
                                )
                              : _groupEditor(g),
                    onDeleted: busy || g.removed
                        ? null
                        : () async {
                            if (await _confirm(
                              '停用分组',
                              '书籍与归属会保留，点击已停用分组可恢复。',
                            )) {
                              await _work(() => repo.removeGroup(scope, g.id));
                            }
                          },
                  ),
              ],
            ),
          const Divider(height: 32),
          if (busy)
            const LinearProgressIndicator()
          else if (error != null)
            Text(error!)
          else if (data != null) ...[
            Text(
              '本机书架 · ${data!.total} 本 · 第${page + 1}页（每页50本）',
              style: Theme.of(context).textTheme.labelMedium,
            ),
            if (data!.books.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: Column(
                  children: [
                    const Text('这里还没有符合条件的书籍。可调整筛选或恢复已移出的书籍。'),
                    if (!options.removed && options.search.isEmpty)
                      TextButton(
                        onPressed: () => _work(
                          () => widget.deps.library.addDemonstration(
                            JobContext(
                              id: 0,
                              isCurrent: () => mounted,
                              report: (_) {},
                            ),
                          ),
                        ),
                        child: const Text('体验演示样本'),
                      ),
                  ],
                ),
              ),
            if (selected.isNotEmpty)
              Wrap(
                spacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text('已选 ${selected.length} 本'),
                  for (final s in ReadingState.values)
                    TextButton(
                      onPressed: () => _apply(BookEdit(state: s)),
                      child: Text('标为${stateLabel(s)}'),
                    ),
                  TextButton(
                    onPressed: () => _apply(const BookEdit(favorite: true)),
                    child: const Text('加入收藏'),
                  ),
                  TextButton(
                    onPressed: () => _apply(const BookEdit(favorite: false)),
                    child: const Text('取消收藏'),
                  ),
                  TextButton(
                    onPressed: _assignGroups,
                    child: const Text('设置合集/标签'),
                  ),
                  TextButton(
                    onPressed: () async {
                      if (await _confirm(
                        options.removed ? '恢复书架' : '移出书架',
                        options.removed
                            ? '保留原有书籍身份、位置和文件。'
                            : '仅隐藏书架记录，文件、位置和笔记保留；可在“已移出书架”恢复。',
                      )) {
                        await _apply(BookEdit(removed: !options.removed));
                      }
                    },
                    child: Text(options.removed ? '恢复书架' : '移出书架'),
                  ),
                ],
              ),
            TextButton(
              onPressed: () => setState(() {
                if (selected.length == data!.books.length) {
                  selected.clear();
                } else {
                  selected.addAll(data!.books.map((b) => b.book.id));
                }
              }),
              child: const Text('选择/取消本页'),
            ),
            options.grid
                ? Wrap(
                    spacing: 28,
                    runSpacing: 28,
                    children: [
                      for (final b in data!.books)
                        SizedBox(width: 170, child: _card(b)),
                    ],
                  )
                : Column(children: [for (final b in data!.books) _card(b)]),
            const SizedBox(height: 24),
            Wrap(
              spacing: 12,
              children: [
                TextButton(
                  onPressed: page > 0
                      ? () {
                          page--;
                          selected.clear();
                          _load();
                        }
                      : null,
                  child: const Text('上一页'),
                ),
                TextButton(
                  onPressed: (page + 1) * 50 < data!.total
                      ? () {
                          page++;
                          selected.clear();
                          _load();
                        }
                      : null,
                  child: const Text('下一页'),
                ),
              ],
            ),
          ],
          if (scope == ShelfScope.adult && access != null)
            TextButton(
              onPressed: busy
                  ? null
                  : () => _work(
                      () => (widget.deps.library as AdultLibrary)
                          .addClassificationCard(
                            JobContext(
                              id: 0,
                              isCurrent: () => mounted && visible,
                              report: (_) {},
                            ),
                          ),
                    ),
              child: const Text('加入分级测试卡片（不含成人正文）'),
            ),
        ],
      ],
    );
  }

  Widget _card(ShelfBook b) {
    final info = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: () => _open(b),
          child: Text(
            b.book.title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
        ),
        if (b.author.isNotEmpty) Text(b.author),
        Text(
          '${b.format.toUpperCase()} · ${stateLabel(b.state)}${b.favorite ? ' · 收藏' : ''}',
          style: Theme.of(context).textTheme.labelMedium,
        ),
        Text(
          '${b.mode == 'reference'
              ? '系统书签引用'
              : b.mode == 'managed'
              ? '本机离线'
              : '自产样本'} · ${healthLabel(b.health)}',
          style: Theme.of(context).textTheme.labelSmall,
        ),
        Wrap(
          spacing: 4,
          children: [
            for (final g in data!.groups)
              if (!g.removed && b.groups.contains(g.id))
                Text(
                  '#${g.label}',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
          ],
        ),
        Wrap(
          spacing: 4,
          children: [
            TextButton(
              onPressed: () => _open(b),
              child: Text(
                b.book.importedTxt
                    ? '打开 TXT 阅读'
                    : b.book.importedEpub
                    ? '打开 EPUB 阅读'
                    : '打开阅读预览',
              ),
            ),
            TextButton(
              key: ValueKey('details-${b.book.id}'),
              onPressed: () => _details(b),
              child: const Text('详情'),
            ),
          ],
        ),
      ],
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: options.grid
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Checkbox(
                  value: selected.contains(b.book.id),
                  onChanged: (v) => setState(
                    () => v == true
                        ? selected.add(b.book.id)
                        : selected.remove(b.book.id),
                  ),
                ),
                InkWell(
                  onTap: () => _open(b),
                  child: BookArtwork(
                    key: ValueKey('${b.book.id}-${b.revision}'),
                    book: b.book,
                    deps: widget.deps,
                    width: 148,
                  ),
                ),
                const SizedBox(height: 10),
                info,
              ],
            )
          : Row(
              children: [
                Checkbox(
                  value: selected.contains(b.book.id),
                  onChanged: (v) => setState(
                    () => v == true
                        ? selected.add(b.book.id)
                        : selected.remove(b.book.id),
                  ),
                ),
                BookArtwork(
                  key: ValueKey('${b.book.id}-${b.revision}'),
                  book: b.book,
                  deps: widget.deps,
                  width: 48,
                ),
                const SizedBox(width: 16),
                Expanded(child: info),
              ],
            ),
    );
  }
}
