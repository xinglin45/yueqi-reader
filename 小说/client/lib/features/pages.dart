import 'import_flow.dart';
import 'txt_reader.dart';
import 'access_controls.dart';
import '../application/access.dart';
import '../application/discovery.dart';

import 'preview_position.dart';

import 'package:phosphor_icons/phosphor_icons.dart';
import 'package:flutter/material.dart';
import 'package:platform_services/platform_services.dart';

import '../app/dependencies.dart';
import '../app/navigation.dart';
import '../application/jobs.dart';
import '../domain/library.dart';
import 'task_view.dart';

void stageNotice(BuildContext context, String title, String message) {
  showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Text(message, style: const TextStyle(height: 1.8)),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('知道了'),
        ),
      ],
    ),
  );
}

Future<void> showImport(BuildContext context, FileAccess files) =>
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('导入书籍'),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: TaskView<FileGrant?>(
              label: '正在选择文件',
              load: (job) async {
                final result = await files.chooseDocument();
                job.checkCancelled();
                return switch (result) {
                  PlatformSuccess<FileGrant?>(:final value) => JobResult(
                    value,
                    empty: value == null,
                  ),
                  PlatformUnavailable<FileGrant?>(
                    reason: PlatformFailure.cancelled,
                  ) =>
                    const JobResult(null, empty: true),
                  PlatformUnavailable<FileGrant?>(:final reason) =>
                    throw AppFailure(switch (reason) {
                      PlatformFailure.permissionDenied =>
                        FailureCode.permissionDenied,
                      PlatformFailure.unsupported => FailureCode.unsupported,
                      PlatformFailure.unavailable => FailureCode.missing,
                      PlatformFailure.cancelled => FailureCode.missing,
                    }),
                };
              },
              empty: const EmptyState(
                icon: PhosphorIconsLight.folderOpen,
                title: '未选择文件',
                message: '关闭后可再次从书架发起导入。',
              ),
              builder: (grant) => EmptyState(
                icon: PhosphorIconsLight.fileText,
                title: '已选择：${grant!.displayName}',
                message: '文件端口已返回受控引用；实际解析与入库将在 MAC-04 接入，本次未导入书籍。',
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('返回书架'),
          ),
        ],
      ),
    );

class PageHeading extends StatelessWidget {
  const PageHeading(this.title, {super.key, this.eyebrow, this.action});
  final String title;
  final String? eyebrow;
  final Widget? action;
  @override
  Widget build(BuildContext context) {
    final heading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (eyebrow != null) ...[
          Text(
            eyebrow!,
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
        ],
        Text(
          title,
          style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w600),
        ),
      ],
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 36),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth >= 600) {
            return Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(child: heading),
                ?action,
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              heading,
              if (action != null) ...[const SizedBox(height: 20), action!],
            ],
          );
        },
      ),
    );
  }
}

class Cover extends StatelessWidget {
  const Cover({super.key, this.width = 104});
  final double width;
  @override
  Widget build(BuildContext context) => Semantics(
    label: '原创演示短篇《山间来信》封面',
    image: true,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: Image.asset(
        'assets/mountain-letter-cover.png',
        width: width,
        height: width * 1.5,
        fit: BoxFit.cover,
        excludeFromSemantics: true,
      ),
    ),
  );
}

class LibraryPage extends StatefulWidget {
  const LibraryPage({
    super.key,
    required this.dependencies,
    required this.navigation,
    this.recent = false,
    this.onImport,
  });
  final AppDependencies dependencies;
  final AppNavigation navigation;
  final bool recent;
  final VoidCallback? onImport;
  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  final _task = GlobalKey<TaskViewState<List<BookSummary>>>();
  int _tab = 0;
  bool _grid = true;
  void _open(BookSummary book) {
    if (!book.previewAvailable && !book.importedTxt) {
      showImportedStatus(context, widget.dependencies, book.id);
      return;
    }
    widget.navigation.go(AppLocation(AppPage.reader, bookId: book.id));
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      PageHeading(
        widget.recent ? '最近阅读' : '我的书架',
        eyebrow: '留一点时间，给阅读',
        action: FilledButton.icon(
          key: const ValueKey('import-book'),
          onPressed:
              widget.onImport ??
              () => showImport(context, widget.dependencies.files),
          icon: const Icon(PhosphorIconsLight.plus, size: 18),
          label: const Text('导入书籍'),
        ),
      ),
      Wrap(
        spacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final (index, title) in ['全部书籍', '在读', '成人收藏'].indexed)
            TextButton(
              onPressed: () => setState(() => _tab = index),
              style: TextButton.styleFrom(
                foregroundColor: _tab == index
                    ? Theme.of(context).colorScheme.onSurface
                    : Theme.of(context).colorScheme.onSurfaceVariant,
                side: _tab == index
                    ? BorderSide(color: Theme.of(context).colorScheme.primary)
                    : BorderSide.none,
              ),
              child: Text(title),
            ),
          IconButton(
            onPressed: () => setState(() => _grid = !_grid),
            tooltip: _grid ? '切换列表' : '切换网格',
            icon: Icon(
              _grid ? PhosphorIconsLight.list : PhosphorIconsLight.squaresFour,
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      const Divider(),
      const SizedBox(height: 24),
      if (widget.recent || _tab == 1)
        const EmptyState(
          icon: PhosphorIconsLight.clock,
          title: '从书架继续阅读',
          message: '最近阅读列表尚未接入；已保存的样本可在书架打开并恢复记住的段落。',
        )
      else if (_tab == 2 &&
          widget.dependencies.access != null &&
          widget.dependencies.library is AdultLibrary)
        AdultCollection(
          dependencies: widget.dependencies,
          access: widget.dependencies.access!,
          library: widget.dependencies.library as AdultLibrary,
          navigation: widget.navigation,
        )
      else if (_tab == 2)
        const EmptyState(
          icon: PhosphorIconsLight.lockSimple,
          title: '成人收藏独立保存',
          message: '当前尚无收藏。成年声明、隐私锁与搜索开关将在 MAC-16 分别接入；关闭搜索不会删除已有收藏。',
        )
      else
        TaskView<List<BookSummary>>(
          key: _task,
          load: widget.dependencies.library.load,
          empty: EmptyState(
            icon: PhosphorIconsLight.bookOpenText,
            title: '把喜欢的故事，放进书架',
            message: '这里会保存你的本地书籍。先体验一段自产样本，或查看导入进度。无需登录。',
            actions: [
              FilledButton(
                onPressed: () => _task.currentState?.run(
                  widget.dependencies.library.addDemonstration,
                ),
                child: const Text('体验演示样本'),
              ),
            ],
          ),
          builder: (books) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${books.every((book) => book.persistent) ? '本机书架' : '本次会话'} · ${books.length} 本',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 24),
              if (_grid)
                Wrap(
                  spacing: 32,
                  runSpacing: 32,
                  children: [
                    for (final book in books)
                      SizedBox(
                        width: 148,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            InkWell(
                              onTap: () => _open(book),
                              borderRadius: BorderRadius.circular(4),
                              child: book.demo
                                  ? const Cover(width: 148)
                                  : const SizedBox(
                                      width: 148,
                                      height: 222,
                                      child: Center(
                                        child: Icon(
                                          PhosphorIconsLight.fileText,
                                          size: 48,
                                        ),
                                      ),
                                    ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              book.title,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              book.subtitle,
                              style: TextStyle(
                                fontSize: 11,
                                height: 1.6,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextButton(
                              onPressed: () => _open(book),
                              child: Text(
                                book.importedTxt
                                    ? '打开 TXT 阅读'
                                    : book.previewAvailable
                                    ? '打开阅读预览'
                                    : '查看文件状态',
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                )
              else
                for (final book in books)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: book.demo
                        ? const Cover(width: 40)
                        : const Icon(PhosphorIconsLight.fileText),
                    title: Text(book.title),
                    subtitle: Text(book.subtitle),
                    trailing: const Icon(PhosphorIconsLight.caretRight),
                    onTap: () => _open(book),
                  ),
            ],
          ),
        ),
      const SizedBox(height: 40),
      const Divider(),
      const SizedBox(height: 12),
      Wrap(
        spacing: 12,
        runSpacing: 8,
        children: [
          for (final page in [AppPage.notes, AppPage.tasks, AppPage.statistics])
            TextButton.icon(
              onPressed: () => widget.navigation.go(AppLocation(page)),
              icon: Icon(page.icon, size: 17),
              label: Text(page.label),
            ),
        ],
      ),
    ],
  );
}

class ReaderPage extends StatelessWidget {
  const ReaderPage({
    super.key,
    required this.bookId,
    required this.dependencies,
    required this.navigation,
    required this.onOpened,
  });
  final String bookId;
  final AppDependencies dependencies;
  final AppNavigation navigation;
  final ValueChanged<BookSummary> onOpened;
  @override
  Widget build(BuildContext context) => dependencies.txt == null
      ? _sample(context)
      : TaskView<bool>(
          empty: const SizedBox(),
          load: (job) async =>
              JobResult(await dependencies.txt!.accepts(bookId)),
          builder: (isTxt) => isTxt
              ? TxtReaderView(
                  bookId: bookId,
                  deps: dependencies,
                  onOpened: onOpened,
                )
              : _sample(context),
        );
  Widget _sample(BuildContext context) => TaskView<ReadingPreview>(
    load: (job) async {
      final result = await dependencies.library.preview(bookId, job);
      job.checkCancelled();
      onOpened(result.value.book);
      return result;
    },
    empty: const EmptyState(
      icon: PhosphorIconsLight.bookOpen,
      title: '正文为空',
      message: '请返回书架重新选择。',
    ),
    builder: (preview) => Align(
      alignment: Alignment.topLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${preview.book.title}  /  ${preview.book.persistent
                  ? '自产样本 · 段落位置可保存'
                  : preview.book.demo
                  ? '自产演示 · 无进度保存'
                  : '阅读预览'}',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 32),
            LayoutBuilder(
              builder: (context, constraints) => Text(
                preview.chapter,
                style: TextStyle(
                  fontFamily: 'Songti SC',
                  fontFamilyFallback: const ['STSong', 'serif'],
                  fontSize: constraints.maxWidth < 420 ? 27 : 36,
                  letterSpacing: 2,
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Divider(),
            const SizedBox(height: 28),
            PreviewParagraphs(
              preview: preview,
              positions: dependencies.positions,
              readOnly: dependencies.storageReadOnly,
            ),
            const SizedBox(height: 20),
            const Divider(),
            const SizedBox(height: 20),
            Text(
              '演示文本至此 · 导入 TXT 可在书架打开阅读，EPUB 阅读待接入',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            TextButton(
              onPressed: () =>
                  navigation.go(const AppLocation(AppPage.library)),
              child: const Text('返回书架'),
            ),
          ],
        ),
      ),
    ),
  );
}

class SearchPage extends StatefulWidget {
  const SearchPage({
    super.key,
    required this.navigation,
    this.access,
    this.discovery,
  });
  final AccessController? access;
  final DiscoveryCoordinator? discovery;
  final AppNavigation navigation;
  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _query = TextEditingController();
  bool _submitted = false;
  Future<void> _search() async {
    await widget.discovery?.search(_query.text);
    if (mounted) setState(() => _submitted = true);
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const PageHeading('在线搜书', eyebrow: '寻找下一段故事'),
      TextField(
        controller: _query,
        decoration: InputDecoration(
          labelText: '书名或作者',
          prefixIcon: const Icon(PhosphorIconsLight.magnifyingGlass),
          suffixIcon: IconButton(
            onPressed: _search,
            tooltip: '检查可用来源',
            icon: const Icon(PhosphorIconsLight.arrowRight),
          ),
        ),
        onSubmitted: (_) => _search(),
      ),
      const SizedBox(height: 20),
      if (widget.access != null)
        AdultSearchSwitch(access: widget.access!)
      else
        const Text('18+ 搜索：关闭 · 当前没有参与请求的来源', style: TextStyle(fontSize: 12)),
      EmptyState(
        icon: PhosphorIconsLight.globe,
        title: _submitted ? '尚无可用来源，未发出搜索请求' : '先为阅读添加来源',
        message: '当前获准内置来源：普通 0 / 18+ 0。来源管理与搜索调度将在 MAC-17/19 接入。',
        actions: [
          TextButton(
            onPressed: () =>
                widget.navigation.go(const AppLocation(AppPage.sources)),
            child: const Text('查看来源状态'),
          ),
        ],
      ),
    ],
  );
}

class SourcesPage extends StatelessWidget {
  const SourcesPage({super.key});
  @override
  Widget build(BuildContext context) => const Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      PageHeading('来源', eyebrow: '内容有来处，阅读才安心'),
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(PhosphorIconsLight.sealCheck),
        title: Text('普通 0 / 18+ 0'),
        subtitle: Text('获准内置来源 · 尚未自动启用任何来源'),
      ),
      Divider(),
      EmptyState(
        icon: PhosphorIconsLight.plugsConnected,
        title: '来源接入正在准备',
        message: '来源技术、使用范围和自身访问条件分别记录。当前采用“地外文明”开发模式，地区专项已跳过，不计作来源批准。真实在线搜索和阅读尚未接入。',
      ),
    ],
  );
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.dark,
    required this.onThemeChanged,
    this.persisted = false,
    this.access,
  });
  final bool dark;
  final bool persisted;
  final AccessController? access;
  final VoidCallback onThemeChanged;
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  int _section = 0;
  final _sections = ['通用', '阅读', '低存在感', '快捷键', '数据与隐私'];
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const PageHeading('设置', eyebrow: '让阅读，适合自己'),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final (index, title) in _sections.indexed)
            ChoiceChip(
              label: Text(title),
              selected: _section == index,
              onSelected: (_) => setState(() => _section = index),
            ),
        ],
      ),
      const SizedBox(height: 32),
      const Divider(),
      const SizedBox(height: 24),
      if (_section == 0) ...[
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('深色外观'),
          subtitle: Text(widget.persisted ? '下次打开时保留你的选择' : '仅在本次会话中使用'),
          value: widget.dark,
          onChanged: (_) => widget.onThemeChanged(),
        ),
        const ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text('本地优先'),
          subtitle: Text('本地阅读不依赖登录或共享服务'),
        ),
      ],
      if (_section == 1)
        const ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text('宋体 · 24 · 1.9 倍行高'),
          subtitle: Text('沿用 D1 阅读预览默认值；排版与位置恢复在 MAC-07/09 接入'),
        ),
      if (_section == 2) ...[
        const Text(
          '低存在感',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        const Text('在不打断阅读的情况下，切换为更轻量的阅读形态。', style: TextStyle(height: 1.8)),
        const SizedBox(height: 20),
        for (final label in ['菜单栏阅读', '悬浮阅读条', '极简窗'])
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(PhosphorIconsLight.rectangle),
            title: Text(label),
            subtitle: const Text('系统表面与同一会话接续在 MAC-09/13 接入'),
            enabled: false,
          ),
      ],
      if (_section == 3)
        const ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text('Tab / Shift+Tab · 移动焦点'),
          subtitle: Text('Enter / 空格激活按钮；Esc 关闭对话框或窄窗侧栏。全局快捷键在 MAC-13 接入。'),
        ),
      if (_section == 4)
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('本地资料'),
          subtitle: Text(
            widget.persisted
                ? '样本、段落位置和外观已保存在这台设备上。成年声明与隐私锁仅在本机保存，同步尚未接入。'
                : '当前为会话内预览，未连接本地资料库。',
          ),
        ),
      if (_section == 4 && widget.access != null)
        AccessSettings(access: widget.access!),
    ],
  );
}

class AuxiliaryPage extends StatelessWidget {
  const AuxiliaryPage({
    super.key,
    required this.page,
    required this.navigation,
  });
  final AppPage page;
  final AppNavigation navigation;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      PageHeading(page.label, eyebrow: '阅栖 · 本地优先'),
      EmptyState(
        icon: page.icon,
        title: switch (page) {
          AppPage.tasks => '还没有下载任务',
          AppPage.notes => '留住阅读时的想法',
          AppPage.statistics => '阅读，让时间留下痕迹',
          _ => '这个地址无法打开',
        },
        message: switch (page) {
          AppPage.tasks => '下载队列将在 MAC-20 接入。当前没有联网下载；可在阶段说明中检查可取消任务的界面状态。',
          AppPage.notes => '书签、摘录和笔记将在 MAC-11 接入。',
          AppPage.statistics => '本地统计将在后续数据与阅读会话中接入；当前没有真实阅读时长。',
          _ => '请返回书架重新选择。无效地址不会打开文件或执行来源规则。',
        },
        actions: [
          TextButton(
            onPressed: () => navigation.go(const AppLocation(AppPage.library)),
            child: const Text('返回书架'),
          ),
        ],
      ),
    ],
  );
}

enum PreviewScenario { ready, partial, empty, permission, offline, corrupt }

class StateCheckPage extends StatefulWidget {
  const StateCheckPage({super.key});
  @override
  State<StateCheckPage> createState() => _StateCheckPageState();
}

class _StateCheckPageState extends State<StateCheckPage> {
  PreviewScenario _scenario = PreviewScenario.ready;
  int _revision = 0;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const PageHeading('界面状态检查', eyebrow: '本地模拟 · 不联网、不解析私人文件'),
      DropdownButtonFormField<PreviewScenario>(
        initialValue: _scenario,
        decoration: const InputDecoration(labelText: '选择检查结果'),
        items: [
          for (final scenario in PreviewScenario.values)
            DropdownMenuItem(
              value: scenario,
              child: Text(switch (scenario) {
                PreviewScenario.ready => '完成',
                PreviewScenario.partial => '部分成功',
                PreviewScenario.empty => '无结果',
                PreviewScenario.permission => '权限拒绝',
                PreviewScenario.offline => '离线',
                PreviewScenario.corrupt => '损坏数据',
              }),
            ),
        ],
        onChanged: (value) {
          if (value != null) {
            setState(() {
              _scenario = value;
              _revision++;
            });
          }
        },
      ),
      const SizedBox(height: 24),
      TaskView<List<String>>(
        key: ValueKey((_scenario, _revision)),
        label: '正在检查界面状态',
        load: (job) async {
          final scenario = _scenario;
          for (var i = 1; i <= 4; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 400));
            job.checkCancelled();
            job.report(i / 4);
          }
          return switch (scenario) {
            PreviewScenario.ready => const JobResult(['自产样本状态已就绪']),
            PreviewScenario.partial => const JobResult(
              ['已保留成功项目'],
              issues: [FailureCode.offline],
            ),
            PreviewScenario.empty => const JobResult([], empty: true),
            PreviewScenario.permission => throw const AppFailure(
              FailureCode.permissionDenied,
            ),
            PreviewScenario.offline => throw const AppFailure(
              FailureCode.offline,
            ),
            PreviewScenario.corrupt => throw const AppFailure(
              FailureCode.corrupt,
            ),
          };
        },
        empty: const EmptyState(
          icon: PhosphorIconsLight.magnifyingGlassMinus,
          title: '没有结果',
          message: '可以修改条件后重新检查。',
        ),
        builder: (items) => EmptyState(
          icon: PhosphorIconsLight.checkCircle,
          title: items.first,
          message: '仅检查界面与任务生命周期，不代表导入或下载完成。',
        ),
      ),
    ],
  );
}
