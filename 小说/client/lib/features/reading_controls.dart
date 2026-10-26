import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../application/reading.dart';
import '../domain/reading.dart';

Future<void> showReadingPreferences(
  BuildContext context,
  ReadingSession session,
) async {
  var value = session.preferences;
  var global = false;
  await showDialog<void>(
    context: context,
    builder: (dialog) => StatefulBuilder(
      builder: (context, update) => AlertDialog(
        title: const Text('阅读排版'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<ReadingLayout>(
                  initialValue: value.layout,
                  decoration: const InputDecoration(labelText: '阅读方式'),
                  items: [
                    for (final v in ReadingLayout.values)
                      DropdownMenuItem(
                        value: v,
                        child: Text(switch (v) {
                          ReadingLayout.scroll => '连续滚动',
                          ReadingLayout.paged => '单页翻页',
                          ReadingLayout.columns => '桌面双栏',
                        }),
                      ),
                  ],
                  onChanged: (v) =>
                      update(() => value = value.copyWith(layout: v)),
                ),
                DropdownButtonFormField<ReadingFont>(
                  initialValue: value.font,
                  decoration: const InputDecoration(labelText: '字体'),
                  items: [
                    for (final v in ReadingFont.values)
                      DropdownMenuItem(
                        value: v,
                        child: Text(switch (v) {
                          ReadingFont.song => '宋体',
                          ReadingFont.sans => '黑体',
                          ReadingFont.mono => '等宽',
                        }),
                      ),
                  ],
                  onChanged: (v) =>
                      update(() => value = value.copyWith(font: v)),
                ),
                DropdownButtonFormField<ReadingTheme>(
                  initialValue: value.theme,
                  decoration: const InputDecoration(labelText: '正文主题'),
                  items: [
                    for (final v in ReadingTheme.values)
                      DropdownMenuItem(
                        value: v,
                        child: Text(switch (v) {
                          ReadingTheme.app => '跟随应用',
                          ReadingTheme.system => '跟随系统',
                          ReadingTheme.paper => '暖纸',
                          ReadingTheme.dark => '深色',
                          ReadingTheme.green => '护眼',
                        }),
                      ),
                  ],
                  onChanged: (v) =>
                      update(() => value = value.copyWith(theme: v)),
                ),
                for (final item
                    in <
                      (String, double, double, double, void Function(double))
                    >[
                      (
                        '字号',
                        value.size,
                        16,
                        36,
                        (v) => value = value.copyWith(size: v),
                      ),
                      (
                        '行高',
                        value.lineHeight,
                        1.2,
                        2.4,
                        (v) => value = value.copyWith(lineHeight: v),
                      ),
                      (
                        '段距',
                        value.paragraphSpacing,
                        0,
                        40,
                        (v) => value = value.copyWith(paragraphSpacing: v),
                      ),
                      (
                        '页边距',
                        value.margin,
                        8,
                        64,
                        (v) => value = value.copyWith(margin: v),
                      ),
                      (
                        '行宽',
                        value.width,
                        360,
                        1400,
                        (v) => value = value.copyWith(width: v),
                      ),
                    ])
                  Row(
                    children: [
                      SizedBox(
                        width: 64,
                        child: Text(
                          '${item.$1} ${item.$2.toStringAsFixed(item.$1 == '行高' ? 1 : 0)}',
                        ),
                      ),
                      Expanded(
                        child: Slider(
                          value: item.$2,
                          min: item.$3,
                          max: item.$4,
                          onChanged: (v) => update(() => item.$5(v)),
                        ),
                      ),
                    ],
                  ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('设为全局默认'),
                  subtitle: const Text('其他书的独立排版保持原设置'),
                  value: global,
                  onChanged: (v) => update(() => global = v!),
                ),
                Text(session.overridden ? '当前为本书独立排版' : '当前使用全局默认'),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await session.setPreferences(value, reset: true);
              if (dialog.mounted) Navigator.pop(dialog);
            },
            child: const Text('恢复全局默认'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              await session.setPreferences(value, global: global);
              if (dialog.mounted) Navigator.pop(dialog);
            },
            child: const Text('应用排版'),
          ),
        ],
      ),
    ),
  );
}

class ReadingTools extends StatelessWidget {
  const ReadingTools({
    super.key,
    required this.session,
    this.onBack,
    this.onProgress,
  });
  final ReadingSession session;
  final VoidCallback? onBack;
  final ValueChanged<double>? onProgress;
  @override
  Widget build(BuildContext context) => StreamBuilder<void>(
    stream: session.changes,
    builder: (context, _) => Wrap(
      spacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        TextButton(
          onPressed: () => showReadingPreferences(context, session),
          child: const Text('排版'),
        ),
        TextButton(
          onPressed: () => session.setFocus(!session.focus),
          child: Text(session.focus ? '退出专注' : '专注'),
        ),
        if (Theme.of(context).platform == TargetPlatform.macOS)
          TextButton(
            onPressed: () async {
              try {
                await const MethodChannel('reader/window')
                    .invokeMethod<void>('fullscreen');
              } on PlatformException catch (_) {
              } on MissingPluginException catch (_) {}
            },
            child: const Text('全屏'),
          ),
        if (onBack != null)
          TextButton(onPressed: onBack, child: const Text('返回跳转前')),
        if (onProgress != null)
          TextButton(
            onPressed: () async {
              var progress = 0.0;
              final chosen = await showDialog<double>(
                context: context,
                builder: (dialog) => StatefulBuilder(
                  builder: (context, update) => AlertDialog(
                    title: const Text('跳到大致进度'),
                    content: SizedBox(
                      width: 320,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('${(progress * 100).round()}%'),
                          Slider(
                            value: progress,
                            onChanged: (v) => update(() => progress = v),
                          ),
                        ],
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(dialog),
                        child: const Text('取消'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(dialog, progress),
                        child: const Text('跳转'),
                      ),
                    ],
                  ),
                ),
              );
              if (chosen != null) onProgress!(chosen);
            },
            child: const Text('进度跳转'),
          ),
        if (session.needsReview)
          const Text('旧位置待核对 · 自动保存暂停', style: TextStyle(fontSize: 11)),
        if (session.error != null)
          Text(
            session.error!,
            style: TextStyle(
              color: Theme.of(context).colorScheme.error,
              fontSize: 11,
            ),
          ),
      ],
    ),
  );
}

(Color, Color) readingColors(ReadingPreferences prefs, bool dark) =>
    switch (prefs.theme) {
      ReadingTheme.dark => (const Color(0xff252421), const Color(0xffe9e5dc)),
      ReadingTheme.green => (const Color(0xffdae5d4), const Color(0xff263329)),
      ReadingTheme.paper => (const Color(0xfffbf9f5), const Color(0xff2d2925)),
      ReadingTheme.app || ReadingTheme.system =>
        dark
            ? (const Color(0xff252421), const Color(0xffe9e5dc))
            : (const Color(0xfffbf9f5), const Color(0xff2d2925)),
    };
