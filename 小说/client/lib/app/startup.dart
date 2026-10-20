import 'package:flutter/material.dart';

import '../infrastructure/platform_storage_locations.dart';
import 'app.dart';
import 'dependencies.dart';
import 'theme.dart';

class NovelStartup extends StatefulWidget {
  const NovelStartup({super.key});
  @override
  State<NovelStartup> createState() => _NovelStartupState();
}

class _NovelStartupState extends State<NovelStartup> {
  AppDependencies? _dependencies;
  bool _failed = false;
  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    setState(() => _failed = false);
    try {
      final dependencies = await AppDependencies.open(
        const SystemStorageLocations(),
      );
      if (!mounted) {
        await dependencies.close?.call();
        return;
      }
      setState(() => _dependencies = dependencies);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    _dependencies?.close?.call();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dependencies = _dependencies;
    if (dependencies != null) return NovelApp(dependencies: dependencies);
    return MaterialApp(
      title: '阅栖',
      debugShowCheckedModeBanner: false,
      theme: paperTheme(Brightness.light),
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _failed ? '本地资料暂时不能打开' : '正在打开本地书架',
                  style: const TextStyle(fontSize: 24),
                ),
                const SizedBox(height: 24),
                if (_failed) ...[
                  const Text('原文件已保留。请确认资料目录可用，或退出阅栖后按照恢复说明处理。'),
                  const SizedBox(height: 24),
                  FilledButton(onPressed: _open, child: const Text('重试')),
                ] else
                  const CircularProgressIndicator(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
