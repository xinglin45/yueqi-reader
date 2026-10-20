import 'package:phosphor_icons/phosphor_icons.dart';

import 'dart:async';

import 'package:flutter/material.dart';

import '../application/jobs.dart';

String failureTitle(FailureCode code) => switch (code) {
  FailureCode.permissionDenied => '当前无法访问',
  FailureCode.offline => '暂时无法连接',
  FailureCode.corrupt => '无法读取这份数据',
  FailureCode.missing => '找不到这本书',
  FailureCode.unsupported => '此能力尚未接入',
  FailureCode.unexpected => '这次操作未完成',
};
String failureHelp(FailureCode code) => switch (code) {
  FailureCode.permissionDenied => '请检查成年声明、隐私锁或来源自身的访问条件；文件操作请检查文件授权。',
  FailureCode.offline => '请检查连接后重试。已有本地内容不依赖网络。',
  FailureCode.corrupt => '请保留原文件，重新选择有效数据后重试。',
  FailureCode.missing => '可以返回书架重新选择；演示样本仅保留于本次会话。',
  FailureCode.unsupported => '文件导入在 MAC-04/13 接入；本阶段可以体验自产演示样本。',
  FailureCode.unexpected => '请重试或返回上一页。诊断仅保留错误类别。',
};

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actions = const [],
  });
  final IconData icon;
  final String title;
  final String message;
  final List<Widget> actions;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 12),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 34,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 20),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                height: 1.8,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            if (actions.isNotEmpty) ...[
              const SizedBox(height: 24),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                alignment: WrapAlignment.center,
                children: actions,
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

class TaskView<T> extends StatefulWidget {
  const TaskView({
    super.key,
    required this.load,
    required this.builder,
    required this.empty,
    this.label = '正在加载',
  });
  final Future<JobResult<T>> Function(JobContext) load;
  final Widget Function(T) builder;
  final Widget empty;
  final String label;
  @override
  State<TaskView<T>> createState() => TaskViewState<T>();
}

class TaskViewState<T> extends State<TaskView<T>> {
  final _job = JobController<T>();
  void reload() => run(widget.load);
  void run(Future<JobResult<T>> Function(JobContext) work) =>
      unawaited(_job.run(work));
  @override
  void initState() {
    super.initState();
    reload();
  }

  @override
  void dispose() {
    _job.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<JobSnapshot<T>>(
    stream: _job.events,
    initialData: _job.snapshot,
    builder: (context, snapshot) {
      final state = snapshot.data ?? _job.snapshot;
      return switch (state.status) {
        JobStatus.idle || JobStatus.running => EmptyState(
          icon: PhosphorIconsLight.hourglass,
          title: widget.label,
          message:
              '任务 #${state.id} · ${state.progress == null ? '进度待定' : '${(state.progress! * 100).round()}%'}',
          actions: [
            SizedBox(
              width: 180,
              child: LinearProgressIndicator(
                value: state.progress,
                semanticsLabel: widget.label,
              ),
            ),
            TextButton(onPressed: _job.cancel, child: const Text('取消任务')),
          ],
        ),
        JobStatus.cancelled => EmptyState(
          icon: PhosphorIconsLight.stopCircle,
          title: '任务已取消',
          message: '任务 #${state.id} 的后续事件不会更新此页面。',
          actions: [TextButton(onPressed: reload, child: const Text('重新开始'))],
        ),
        JobStatus.failed => EmptyState(
          icon: PhosphorIconsLight.warningCircle,
          title: failureTitle(state.error!),
          message: failureHelp(state.error!),
          actions: [TextButton(onPressed: reload, child: const Text('重试'))],
        ),
        JobStatus.empty => widget.empty,
        JobStatus.ready || JobStatus.partial => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (state.status == JobStatus.partial)
              Padding(
                padding: const EdgeInsets.only(bottom: 20),
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 12,
                  children: [
                    Text('部分完成 · ${state.issues.map(failureTitle).join('、')}'),
                    TextButton(onPressed: reload, child: const Text('重试未完成部分')),
                  ],
                ),
              ),
            widget.builder(state.value as T),
          ],
        ),
      };
    },
  );
}
