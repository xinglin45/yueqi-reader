import 'import_flow.dart';
import '../app/dependencies.dart';

import 'package:flutter/material.dart';

import '../application/access.dart';
import '../app/navigation.dart';
import '../domain/library.dart';
import 'task_view.dart';

Future<void> accessAction(
  BuildContext context,
  Future<void> Function() action,
) async {
  try {
    await action();
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('未能保存访问设置，本次不会增加访问权限。')));
    }
  }
}

Future<void> showAdultDeclaration(
  BuildContext context,
  AccessController access,
) async {
  var checked = false;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialog) => StatefulBuilder(
      builder: (dialog, update) => AlertDialog(
        title: const Text('成年声明'),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('仅在本机保存这份声明。确认后不会自动开启搜索，也不替代来源自身的访问流程。'),
              CheckboxListTile(
                key: const ValueKey('adult-statement'),
                contentPadding: EdgeInsets.zero,
                title: const Text('我确认已经成年'),
                value: checked,
                onChanged: (value) => update(() => checked = value ?? false),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const ValueKey('confirm-adult'),
            onPressed: checked ? () => Navigator.pop(dialog, true) : null,
            child: const Text('确认'),
          ),
        ],
      ),
    ),
  );
  if (confirmed == true && context.mounted) {
    await accessAction(context, access.acknowledge);
  }
}

class AdultSearchSwitch extends StatelessWidget {
  const AdultSearchSwitch({super.key, required this.access});
  final AccessController access;
  @override
  Widget build(BuildContext context) => SwitchListTile(
    key: const ValueKey('adult-search'),
    contentPadding: EdgeInsets.zero,
    title: const Text('搜索18+书源'),
    subtitle: Text(
      access.state.privacyLocked
          ? '隐私已锁定，当前不请求18+来源'
          : '默认关闭；关闭后保留已有收藏和阅读权限。更改后需重新搜索。',
    ),
    value: access.state.includeAdultSources,
    onChanged: (value) async {
      if (value && !access.state.acknowledged) {
        await showAdultDeclaration(context, access);
        return; // Declaring never silently enables discovery.
      }
      await accessAction(context, () => access.setDiscovery(value));
    },
  );
}

class AccessSettings extends StatelessWidget {
  const AccessSettings({super.key, required this.access});
  final AccessController access;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(access.state.acknowledged ? '成年声明：已在本机确认' : '成年声明：尚未确认'),
        subtitle: const Text('不收集生日、实名或证件；声明不随书库备份或同步。'),
      ),
      Wrap(
        spacing: 12,
        children: [
          if (!access.state.acknowledged)
            TextButton(
              onPressed: () => showAdultDeclaration(context, access),
              child: const Text('查看成年声明'),
            )
          else
            TextButton(
              key: const ValueKey('clear-adult'),
              onPressed: () =>
                  accessAction(context, access.clearAcknowledgement),
              child: const Text('清除本机声明'),
            ),
          TextButton(
            onPressed: () => accessAction(
              context,
              access.state.privacyLocked ? access.unlock : access.lock,
            ),
            child: Text(access.state.privacyLocked ? '解锁隐私' : '锁定隐私'),
          ),
        ],
      ),
      AdultSearchSwitch(access: access),
      const Text(
        '隐私锁隐藏受保护预览并作废相关会话。它不是加密或密码认证，不删除收藏；解锁无需重复成年声明。',
        style: TextStyle(height: 1.8),
      ),
    ],
  );
}

class AdultCollection extends StatefulWidget {
  const AdultCollection({
    super.key,
    required this.access,
    required this.library,
    required this.navigation,
    this.dependencies,
  });
  final AccessController access;
  final AdultLibrary library;
  final AppNavigation navigation;
  final AppDependencies? dependencies;
  @override
  State<AdultCollection> createState() => _AdultCollectionState();
}

class _AdultCollectionState extends State<AdultCollection> {
  final _task = GlobalKey<TaskViewState<List<BookSummary>>>();
  @override
  Widget build(BuildContext context) {
    final state = widget.access.state;
    if (!state.adultVisible) {
      return EmptyState(
        icon: Icons.lock_outline,
        title: '成人收藏独立保存',
        message: !state.acknowledged
            ? '确认成年声明后可查看此分组。取消不影响普通阅读。'
            : '隐私已锁定，收藏仍保留在本机。',
        actions: [
          TextButton(
            onPressed: () => !state.acknowledged
                ? showAdultDeclaration(context, widget.access)
                : accessAction(context, widget.access.unlock),
            child: Text(!state.acknowledged ? '查看成年声明' : '解锁隐私'),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('成人收藏独立保存', style: TextStyle(fontSize: 20)),
        const Text('关闭搜索不会删除收藏。当前仅支持自产分级测试卡片，不含成人正文。'),
        const SizedBox(height: 16),
        TextButton(
          onPressed: () =>
              _task.currentState?.run(widget.library.addClassificationCard),
          child: const Text('加入分级测试卡片（不含成人正文）'),
        ),
        TaskView<List<BookSummary>>(
          key: _task,
          load: widget.library.loadAdult,
          empty: const Padding(
            padding: EdgeInsets.all(24),
            child: Text('当前尚无收藏。'),
          ),
          builder: (books) => Column(
            children: [
              for (final book in books)
                ListTile(
                  title: Text(book.title),
                  subtitle: Text(book.subtitle),
                  onTap: () {
                    if (!book.previewAvailable &&
                        !book.importedTxt &&
                        !book.importedEpub &&
                        widget.dependencies != null) {
                      showImportedStatus(
                        context,
                        widget.dependencies!,
                        book.id,
                      );
                    } else {
                      widget.navigation.go(
                        AppLocation(AppPage.reader, bookId: book.id),
                      );
                    }
                  },
                ),
            ],
          ),
        ),
      ],
    );
  }
}
