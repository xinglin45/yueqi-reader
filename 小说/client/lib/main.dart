import 'package:flutter/material.dart';
import 'package:reader_core/reader_core.dart';

void main() {
  runApp(const NovelBootstrapApp());
}

/// MAC-01 verifies the host and shared package wiring, before the D1 app shell.
class NovelBootstrapApp extends StatelessWidget {
  const NovelBootstrapApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '阅栖',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF9F654B),
          surface: const Color(0xFFFBF9F5),
        ),
        scaffoldBackgroundColor: const Color(0xFFFBF9F5),
      ),
      home: const _BootstrapPage(product: ReaderProduct.novel),
    );
  }
}

class _BootstrapPage extends StatefulWidget {
  const _BootstrapPage({required this.product});

  final ReaderProduct product;

  @override
  State<_BootstrapPage> createState() => _BootstrapPageState();
}

class _BootstrapPageState extends State<_BootstrapPage> {
  final _text = TextEditingController(text: '简体中文 · 繁體中文 📖');

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: ValueKey('bootstrap-${widget.product.namespace}'),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.menu_book_outlined, size: 36),
                  const SizedBox(height: 24),
                  Text('阅栖', style: Theme.of(context).textTheme.headlineLarge),
                  const SizedBox(height: 12),
                  Text(
                    '阅读，从这里开始。',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    '基础工程已就绪。接下来将按已确认的D1设计搭建书架与阅读界面。',
                    style: TextStyle(height: 1.8),
                  ),
                  const SizedBox(height: 36),
                  TextField(
                    controller: _text,
                    decoration: const InputDecoration(
                      labelText: '中文输入检查',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 2,
                    minLines: 1,
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('输入内容'),
                        content: SelectableText(_text.text),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text('返回'),
                          ),
                        ],
                      ),
                    ),
                    child: const Text('显示输入内容'),
                  ),
                  const SizedBox(height: 40),
                  Text(
                    'MAC-01 · 工程检查版',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
