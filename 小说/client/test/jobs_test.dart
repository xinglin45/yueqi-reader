import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/application/diagnostics.dart';
import 'package:novel_app/application/jobs.dart';

void main() {
  test(
    'cancel invalidates late success, failure and progress; retry has a new id',
    () async {
      final job = JobController<String>();
      addTearDown(job.dispose);
      final events = <JobSnapshot<String>>[];
      job.events.listen(events.add);
      final pending = Completer<JobResult<String>>();
      late JobContext context;
      final running = job.run((value) {
        context = value;
        return pending.future;
      });
      final id = job.snapshot.id;
      context.report(.4);
      context.report(.2);
      context.report(double.nan);
      context.report(2);
      expect(job.snapshot.progress, .4);
      job.cancel();
      expect(context.isCancelled, isTrue);
      final count = events.length;
      context.report(.9);
      pending.complete(const JobResult('late secret'));
      await running;
      expect(events.length, count);
      expect(job.snapshot.status, JobStatus.cancelled);
      await job.run((_) async => const JobResult('new'));
      expect(job.snapshot.id, greaterThan(id));
      expect(job.snapshot.value, 'new');
      context.report(1);
      expect(job.snapshot.status, JobStatus.ready);
      final error = Completer<JobResult<String>>();
      final failure = job.run((_) => error.future);
      job.cancel();
      error.completeError(StateError('private-path/token'));
      await failure;
      expect(job.snapshot.error, isNull);
    },
  );
  test(
    'replacement, terminal result and disposal invalidate every old callback',
    () async {
      final job = JobController<String>();
      final old = Completer<JobResult<String>>();
      late JobContext oldContext;
      final first = job.run((context) {
        oldContext = context;
        return old.future;
      });
      late JobContext terminalContext;
      await job.run((context) async {
        terminalContext = context;
        return const JobResult('current');
      });
      old.complete(const JobResult('wrong book'));
      await first;
      oldContext.report(.8);
      terminalContext.report(.8);
      expect(terminalContext.isCancelled, isTrue);
      expect(job.snapshot.value, 'current');
      final last = Completer<JobResult<String>>();
      final pending = job.run((_) => last.future);
      job.dispose();
      last.completeError(Exception('credential'));
      await pending;
      expect(job.snapshot.status, JobStatus.running);
      await job.run((_) async => const JobResult('disposed'));
      expect(job.snapshot.value, isNull);
    },
  );
  test('typed failure, empty, partial and sanitized unknown failure have separate states', () async {
    final job = JobController<List<String>>();
    addTearDown(job.dispose);
    for (final code in FailureCode.values) {
      await job.run((_) async => throw AppFailure(code));
      expect(job.snapshot.error, code);
      expect(job.snapshot.status, JobStatus.failed);
    }
    await job.run((_) async => const JobResult([], empty: true));
    expect(job.snapshot.status, JobStatus.empty);
    await job.run(
      (_) async => const JobResult(['retained'], issues: [FailureCode.offline]),
    );
    expect(job.snapshot.status, JobStatus.partial);
    expect(job.snapshot.value, ['retained']);
    await job.run((_) async => throw StateError('cookie=secret'));
    expect(job.snapshot.error, FailureCode.unexpected);
    expect(job.snapshot.value, isNull);
    for (var i = 0; i < 25; i++) {
      SafeDiagnostics.record(DiagnosticCode.framework);
    }
    expect(SafeDiagnostics.codes, hasLength(20));
    expect(() => SafeDiagnostics.codes.clear(), throwsUnsupportedError);
  });
}
