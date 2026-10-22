import 'dart:async';

import 'package:platform_services/platform_services.dart';

import '../features/import_flow.dart';
import '../domain/access.dart';
import '../features/access_controls.dart';

import 'package:phosphor_icons/phosphor_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../features/pages.dart';
import '../domain/library.dart';
import 'dependencies.dart';
import 'navigation.dart';
import 'theme.dart';

class NovelApp extends StatefulWidget {
  const NovelApp({super.key, required this.dependencies, this.navigation});
  final AppDependencies dependencies;
  final AppNavigation? navigation;
  @override
  State<NovelApp> createState() => _NovelAppState();
}

class _NovelAppState extends State<NovelApp> {
  late final AppNavigation _navigation;
  late final ShellRouter _router;
  bool _dark = false;
  int _libraryEpoch = 0;
  bool _importing = false;
  final _importQueue = <List<FileGrant>?>[];
  StreamSubscription<List<FileGrant>>? _incoming;
  Future<void> _openImport([List<FileGrant>? grants]) async {
    if (grants?.isEmpty == true) return;
    _importQueue.add(grants);
    if (_importing) return;
    _importing = true;
    try {
      while (mounted && _importQueue.isNotEmpty) {
        final next = _importQueue.removeAt(0);
        final context = _router.navigatorKey.currentContext;
        if (context == null || !context.mounted) continue;
        if (widget.dependencies.storageReadOnly) {
          stageNotice(context, '资料暂时只读', '当前不能保存导入文件，请退出后按照恢复说明处理。');
          if (widget.dependencies.files case final DocumentAccess files) {
            for (final grant in next ?? <FileGrant>[]) {
              await files.releaseGrant(grant);
            }
          }
          continue;
        }
        if (widget.dependencies.importer == null) {
          await showImport(context, widget.dependencies.files);
          continue;
        } else {
          await showImportFlow(context, widget.dependencies, grants: next);
        }
        if (mounted) {
          _libraryEpoch++;
          _navigation.replace(const AppLocation(AppPage.library));
          _router.refresh();
        }
      }
    } finally {
      _importing = false;
    }
  }

  final _messenger = GlobalKey<ScaffoldMessengerState>();
  Future<void> _toggleTheme() async {
    setState(() => _dark = !_dark);
    try {
      await widget.dependencies.persistTheme?.call(_dark);
    } catch (_) {
      _messenger.currentState?.showSnackBar(
        const SnackBar(content: Text('外观已切换，但未能保存。下次打开可能需要重新选择。')),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    _dark = widget.dependencies.initialDark;
    _navigation = widget.navigation ?? AppNavigation();
    _router = ShellRouter(
      navigation: _navigation,
      builder: (location) => StreamBuilder<AccessState>(
        stream: widget.dependencies.access?.changes,
        initialData: widget.dependencies.access?.state ?? const AccessState(),
        builder: (context, snapshot) => ReaderShell(
          key: ValueKey(snapshot.data!.visibilityRevision),
          location: location,
          libraryEpoch: _libraryEpoch,
          onImport: () => _openImport(),
          dependencies: widget.dependencies,
          navigation: _navigation,
          onThemeChanged: _toggleTheme,
        ),
      ),
    );
    if (widget.dependencies.files case final DocumentAccess files) {
      _incoming = files.incomingDocuments.listen((grants) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) unawaited(_openImport(grants));
        });
        WidgetsBinding.instance.scheduleFrame();
      });
    }
  }

  @override
  void dispose() {
    _incoming?.cancel();
    _router.dispose();
    if (widget.navigation == null) _navigation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp.router(
    title: '阅栖',
    scaffoldMessengerKey: _messenger,
    builder: (context, child) => Column(
      children: [
        if (widget.dependencies.storageReadOnly)
          Material(
            color: Theme.of(context).colorScheme.errorContainer,
            child: const SafeArea(
              bottom: false,
              child: Padding(
                padding: EdgeInsets.all(12),
                child: Text('本地资料暂时以只读方式打开，本次更改不会保存。原资料已保留，请退出后查看恢复说明。'),
              ),
            ),
          ),
        Expanded(child: child!),
      ],
    ),
    debugShowCheckedModeBanner: false,
    theme: paperTheme(Brightness.light),
    darkTheme: paperTheme(Brightness.dark),
    themeMode: _dark ? ThemeMode.dark : ThemeMode.light,
    routerDelegate: _router,
    routeInformationParser: const LocationParser(),
  );
}

class ReaderShell extends StatefulWidget {
  const ReaderShell({
    super.key,
    required this.location,
    required this.dependencies,
    required this.navigation,
    required this.onThemeChanged,
    required this.onImport,
    required this.libraryEpoch,
  });
  final AppLocation location;
  final AppDependencies dependencies;
  final AppNavigation navigation;
  final VoidCallback onThemeChanged, onImport;
  final int libraryEpoch;
  @override
  State<ReaderShell> createState() => _ReaderShellState();
}

class _ReaderShellState extends State<ReaderShell> {
  final _scaffold = GlobalKey<ScaffoldState>();
  BookSummary? _currentPreview;
  void _opened(BookSummary book) {
    if (mounted && _currentPreview?.id != book.id) {
      setState(() => _currentPreview = book);
    }
  }

  final _contentFocus = FocusNode(debugLabel: 'main-content');
  @override
  void didUpdateWidget(ReaderShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.location.path != widget.location.path) {
      _contentFocus.requestFocus();
    }
  }

  @override
  void dispose() {
    _contentFocus.dispose();
    super.dispose();
  }

  void _go(AppPage page) {
    _scaffold.currentState?.closeDrawer();
    widget.navigation.go(AppLocation(page));
  }

  Widget _sidebar(double width) => Container(
    width: width,
    color: Theme.of(context).colorScheme.surfaceContainerLow,
    child: SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.only(left: 16, bottom: 24),
              child: Row(
                children: [
                  Icon(PhosphorIconsLight.bookOpen),
                  SizedBox(width: 10),
                  Text(
                    '阅栖',
                    style: TextStyle(fontSize: 21, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final page in [
                      AppPage.library,
                      AppPage.recent,
                      AppPage.search,
                      AppPage.sources,
                      AppPage.settings,
                    ])
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: TextButton(
                          key: ValueKey('nav-${page.path}'),
                          onPressed: () => _go(page),
                          style: TextButton.styleFrom(
                            alignment: Alignment.centerLeft,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 18,
                            ),
                            foregroundColor: Theme.of(context)
                                .colorScheme
                                .onSurface,
                            backgroundColor: widget.location.page == page
                                ? Theme.of(context)
                                      .colorScheme
                                      .surfaceContainerHigh
                                : Colors.transparent,
                            side: widget.location.page == page
                                ? BorderSide(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .outlineVariant,
                                  )
                                : BorderSide.none,
                          ),
                          child: Row(
                            children: [
                              Icon(page.icon),
                              const SizedBox(width: 18),
                              Text(
                                page.label,
                                style: const TextStyle(fontSize: 18),
                              ),
                            ],
                          ),
                        ),
                      ),
                    const SizedBox(height: 24),
                    const Divider(),
                    const SizedBox(height: 24),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        '阅读，从这里开始。',
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.8,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    if (_currentPreview != null) ...[
                      const SizedBox(height: 24),
                      TextButton(
                        onPressed: () {
                          _scaffold.currentState?.closeDrawer();
                          widget.navigation.go(
                            AppLocation(
                              AppPage.reader,
                              bookId: _currentPreview!.id,
                            ),
                          );
                        },
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (_currentPreview!.demo) const Cover(width: 58),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _currentPreview!.title,
                                    style: TextStyle(
                                      fontSize: 16,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurface,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    _currentPreview!.persistent
                                        ? '本机内容\n位置可保存'
                                        : '正在预览\n仅本次会话',
                                    style: TextStyle(fontSize: 11, height: 1.8),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            TextButton.icon(
              onPressed: _about,
              icon: const Icon(PhosphorIconsLight.info, size: 16),
              label: const Align(
                alignment: Alignment.centerLeft,
                child: Text('阶段说明 · MAC-05', style: TextStyle(fontSize: 12)),
              ),
            ),
            TextButton.icon(
              key: const ValueKey('nav-notes'),
              onPressed: () => _go(AppPage.notes),
              icon: const Icon(PhosphorIconsLight.note, size: 17),
              label: const Align(
                alignment: Alignment.centerLeft,
                child: Text('笔记与书签', style: TextStyle(fontSize: 12)),
              ),
            ),
          ],
        ),
      ),
    ),
  );
  void _about() => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('阅栖 · 应用壳检查点'),
      content: const SizedBox(
        width: 420,
        child: Text(
          '沿用已确认的 D1 暖纸设计。当前提供导航、响应布局、平台端口和可取消任务。\n\n本地书架、样本文本与段落位置已可保存，退出后继续使用。演示内容为自产文本。TXT/EPUB文件已可批量导入托管副本或系统书签引用；TXT已可后台分章、目录跳转和分块阅读；EPUB正式阅读、系统听书和低存在感窗口仍待后续任务。\n\n获准普通/18+在线来源仍为 0/0。',
          style: TextStyle(height: 1.8),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.pop(context);
            _go(AppPage.states);
          },
          child: const Text('检查界面状态'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('返回'),
        ),
      ],
    ),
  );
  void _lowMode() => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('低存在感'),
      content: const SizedBox(
        width: 426,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('在不打断阅读的情况下，切换为更轻量的阅读形态。', style: TextStyle(height: 1.8)),
            SizedBox(height: 20),
            ListTile(
              enabled: false,
              contentPadding: EdgeInsets.zero,
              leading: Icon(PhosphorIconsLight.bookOpen),
              title: Text('菜单栏阅读'),
            ),
            ListTile(
              enabled: false,
              contentPadding: EdgeInsets.zero,
              leading: Icon(PhosphorIconsLight.minus),
              title: Text('悬浮阅读条'),
            ),
            ListTile(
              enabled: false,
              contentPadding: EdgeInsets.zero,
              leading: Icon(PhosphorIconsLight.rectangle),
              title: Text('极简窗'),
            ),
            SizedBox(height: 16),
            Text(
              '同一阅读会话与系统窗口将在 MAC-09/13 接入，本阶段尚不能切换。',
              style: TextStyle(fontSize: 12, height: 1.8),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('返回阅读'),
        ),
      ],
    ),
  );
  Widget _toolbar(bool narrow) {
    final reading = widget.location.page == AppPage.reader;
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainer,
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
      ),
      child: Row(
        children: [
          if (narrow)
            IconButton(
              key: const ValueKey('open-navigation'),
              onPressed: () => _scaffold.currentState?.openDrawer(),
              tooltip: '打开导航',
              icon: const Icon(PhosphorIconsLight.list),
            ),
          if (reading || widget.navigation.canGoBack)
            IconButton(
              onPressed: () {
                if (!widget.navigation.back()) _go(AppPage.library);
              },
              tooltip: '返回上一页',
              icon: const Icon(PhosphorIconsLight.arrowLeft, size: 18),
            ),
          Expanded(
            child: Text(
              reading ? '阅读预览' : widget.location.page.label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          if (reading) ...[
            IconButton(
              onPressed: () => stageNotice(
                context,
                '阅读排版',
                '当前采用 D1 的宋体、24字号与1.9行高。可调排版和位置恢复将在 MAC-07/09 接入。',
              ),
              tooltip: '阅读排版',
              icon: const Icon(PhosphorIconsLight.textAa),
            ),
            if (!narrow)
              IconButton(
                onPressed: () => _go(AppPage.notes),
                tooltip: '笔记与书签',
                icon: const Icon(PhosphorIconsLight.note),
              ),
            IconButton(
              onPressed: _lowMode,
              tooltip: '低存在感',
              icon: const Icon(PhosphorIconsLight.rectangle),
            ),
          ],
          if (widget.dependencies.access case final access?)
            IconButton(
              key: const ValueKey('privacy-lock'),
              tooltip: access.state.privacyLocked ? '解锁隐私' : '锁定隐私',
              icon: Icon(
                access.state.privacyLocked ? Icons.lock : Icons.lock_open,
              ),
              onPressed: () => accessAction(
                context,
                access.state.privacyLocked ? access.unlock : access.lock,
              ),
            ),
          IconButton(
            key: const ValueKey('toggle-theme'),
            onPressed: widget.onThemeChanged,
            tooltip: Theme.of(context).brightness == Brightness.dark
                ? '切换浅色'
                : '切换深色',
            icon: Icon(
              Theme.of(context).brightness == Brightness.dark
                  ? PhosphorIconsLight.sun
                  : PhosphorIconsLight.moon,
            ),
          ),
          if (!reading)
            IconButton(
              onPressed: widget.onImport,
              tooltip: '导入书籍',
              icon: const Icon(PhosphorIconsLight.plus),
            ),
        ],
      ),
    );
  }

  Widget _page() => switch (widget.location.page) {
    AppPage.library || AppPage.recent => LibraryPage(
      dependencies: widget.dependencies,
      navigation: widget.navigation,
      onImport: widget.onImport,
      recent: widget.location.page == AppPage.recent,
    ),
    AppPage.reader => ReaderPage(
      bookId: widget.location.bookId ?? '',
      dependencies: widget.dependencies,
      navigation: widget.navigation,
      onOpened: _opened,
    ),
    AppPage.search => SearchPage(
      navigation: widget.navigation,
      access: widget.dependencies.access,
      discovery: widget.dependencies.discovery,
    ),
    AppPage.sources => const SourcesPage(),
    AppPage.settings => SettingsPage(
      access: widget.dependencies.access,
      persisted:
          widget.dependencies.persistTheme != null &&
          !widget.dependencies.storageReadOnly,
      dark: Theme.of(context).brightness == Brightness.dark,
      onThemeChanged: widget.onThemeChanged,
    ),
    AppPage.states => const StateCheckPage(),
    _ => AuxiliaryPage(
      page: widget.location.page,
      navigation: widget.navigation,
    ),
  };
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final narrow = constraints.maxWidth < 760;
      final sidebarWidth = constraints.maxWidth < 1100 ? 220.0 : 276.0;
      return Shortcuts(
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
        },
        child: Actions(
          actions: {
            DismissIntent: CallbackAction<DismissIntent>(
              onInvoke: (_) {
                _scaffold.currentState?.closeDrawer();
                return null;
              },
            ),
          },
          child: Scaffold(
            key: _scaffold,
            drawer: narrow
                ? Drawer(
                    width: 276,
                    shape: const RoundedRectangleBorder(),
                    child: _sidebar(276),
                  )
                : null,
            body: Row(
              children: [
                if (!narrow) ...[
                  _sidebar(sidebarWidth),
                  const VerticalDivider(width: 1),
                ],
                Expanded(
                  child: Column(
                    children: [
                      _toolbar(narrow),
                      Expanded(
                        child: FocusTraversalGroup(
                          child: Focus(
                            focusNode: _contentFocus,
                            skipTraversal: true,
                            child: SingleChildScrollView(
                              key: ValueKey('scroll-${widget.location.path}'),
                              padding: EdgeInsets.fromLTRB(
                                narrow
                                    ? 24
                                    : widget.location.page == AppPage.reader &&
                                          constraints.maxWidth >= 1100
                                    ? 92
                                    : 54,
                                narrow ? 32 : 48,
                                narrow ? 24 : 54,
                                48,
                              ),
                              child: KeyedSubtree(
                                key: ValueKey((
                                  widget.location.path,
                                  widget.libraryEpoch,
                                )),
                                child: _page(),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
