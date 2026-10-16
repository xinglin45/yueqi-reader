import 'dart:async';

import '../domain/jobs.dart';
export '../domain/jobs.dart';

/// Owner-scoped jobs: UI disposal, cancellation and replacement invalidate an ID
/// immediately. Cooperative workers check the signal; uncooperative callbacks
/// still cannot publish. Diagnostics retain codes only, never raw exceptions.
final class JobController<T> {
  final _events = StreamController<JobSnapshot<T>>.broadcast(sync: true);
  JobSnapshot<T> _snapshot = JobSnapshot<T>();
  int _generation = 0;
  bool _disposed = false;
  static int _nextId = 0;
  Stream<JobSnapshot<T>> get events => _events.stream;
  JobSnapshot<T> get snapshot => _snapshot;

  void _emit(JobSnapshot<T> value) {
    if (_disposed) return;
    _snapshot = value;
    _events.add(value);
  }

  Future<void> run(Future<JobResult<T>> Function(JobContext) worker) async {
    if (_disposed) return;
    final generation = ++_generation;
    final id = ++_nextId;
    bool current() => !_disposed && generation == _generation;
    _emit(JobSnapshot(id: id, status: JobStatus.running));
    final context = JobContext(
      id: id,
      isCurrent: current,
      report: (progress) {
        if (!progress.isFinite || progress < 0 || progress > 1) return;
        if (progress < (_snapshot.progress ?? 0)) return;
        _emit(
          JobSnapshot(id: id, status: JobStatus.running, progress: progress),
        );
      },
    );
    try {
      final result = await worker(context);
      if (!current()) return;
      ++_generation;
      _emit(
        JobSnapshot(
          id: id,
          status: result.issues.isNotEmpty
              ? JobStatus.partial
              : result.empty
              ? JobStatus.empty
              : JobStatus.ready,
          progress: 1,
          value: result.value,
          issues: List.unmodifiable(result.issues),
        ),
      );
    } on JobCancelled {
      if (current()) {
        ++_generation;
        _emit(JobSnapshot(id: id, status: JobStatus.cancelled));
      }
    } on AppFailure catch (error) {
      if (current()) {
        ++_generation;
        _emit(JobSnapshot(id: id, status: JobStatus.failed, error: error.code));
      }
    } catch (_) {
      if (current()) {
        ++_generation;
        _emit(
          JobSnapshot(
            id: id,
            status: JobStatus.failed,
            error: FailureCode.unexpected,
          ),
        );
      }
    }
  }

  void cancel() {
    if (_disposed || _snapshot.status != JobStatus.running) return;
    ++_generation;
    _emit(
      JobSnapshot(
        id: _snapshot.id,
        status: JobStatus.cancelled,
        progress: _snapshot.progress,
      ),
    );
  }

  void dispose() {
    if (_disposed) return;
    ++_generation;
    _disposed = true;
    unawaited(_events.close());
  }
}
