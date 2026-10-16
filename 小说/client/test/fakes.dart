import 'dart:async';

import 'package:novel_app/app/dependencies.dart';
import 'package:novel_app/application/jobs.dart';
import 'package:novel_app/domain/library.dart';
import 'package:platform_services/platform_services.dart';

class ControlledLibrary implements LibraryRepository {
  final loads = <Completer<JobResult<List<BookSummary>>>>[];
  final readers = <String, Completer<JobResult<ReadingPreview>>>{};
  final contexts = <JobContext>[];
  @override
  Future<JobResult<List<BookSummary>>> load(JobContext job) {
    contexts.add(job);
    final value = Completer<JobResult<List<BookSummary>>>();
    loads.add(value);
    return value.future;
  }

  @override
  Future<JobResult<List<BookSummary>>> addDemonstration(JobContext job) =>
      load(job);
  @override
  Future<JobResult<ReadingPreview>> preview(String bookId, JobContext job) {
    contexts.add(job);
    final value = Completer<JobResult<ReadingPreview>>();
    readers[bookId] = value;
    return value.future;
  }
}

class FakeFiles implements FileAccess {
  PlatformResult<FileGrant?> next = const PlatformUnavailable(
    PlatformFailure.permissionDenied,
  );
  int calls = 0;
  @override
  Future<PlatformResult<FileGrant?>> chooseDocument() async {
    calls++;
    return next;
  }

  @override
  Future<PlatformResult<FileGrant>> restoreGrant(String grantId) async =>
      const PlatformUnavailable(PlatformFailure.permissionDenied);
}

AppDependencies fakeDependencies({
  required LibraryRepository library,
  FileAccess files = const UnavailablePlatform(),
}) => AppDependencies(
  library: library,
  files: files,
  secrets: const UnavailablePlatform(),
  speech: const UnavailablePlatform(),
  windows: const UnavailablePlatform(),
);
