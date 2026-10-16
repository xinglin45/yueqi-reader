enum FailureCode {
  permissionDenied,
  offline,
  corrupt,
  missing,
  unsupported,
  unexpected,
}

final class AppFailure implements Exception {
  const AppFailure(this.code);
  final FailureCode code;
}

enum JobStatus { idle, running, ready, partial, empty, failed, cancelled }

final class JobResult<T> {
  const JobResult(this.value, {this.empty = false, this.issues = const []});
  final T value;
  final bool empty;
  final List<FailureCode> issues;
}

final class JobSnapshot<T> {
  const JobSnapshot({
    this.id = 0,
    this.status = JobStatus.idle,
    this.progress,
    this.value,
    this.error,
    this.issues = const [],
  });
  final int id;
  final JobStatus status;

  /// null means indeterminate; otherwise a monotone fraction in [0, 1].
  final double? progress;
  final T? value;
  final FailureCode? error;
  final List<FailureCode> issues;
}

final class JobContext {
  JobContext({
    required this.id,
    required this._isCurrent,
    required this._report,
  });
  final int id;
  final bool Function() _isCurrent;
  final void Function(double) _report;
  bool get isCancelled => !_isCurrent();
  void checkCancelled() {
    if (isCancelled) throw const JobCancelled();
  }

  void report(double progress) {
    if (!isCancelled) _report(progress);
  }
}

final class JobCancelled implements Exception {
  const JobCancelled();
}
