import 'dart:async';

import 'package:flutter/services.dart';
import 'package:platform_services/platform_services.dart';

import '../domain/importing.dart';

final class MacDocumentAccess implements DocumentAccess, CoverAccess {
  MacDocumentAccess({MethodChannel? channel})
    : channel = channel ?? const MethodChannel('local.yueqi.documents') {
    this.channel.setMethodCallHandler((call) async {
      if (call.method == 'incoming') _incoming.add(_grants(call.arguments));
    });
  }
  final MethodChannel channel;
  final _incoming = StreamController<List<FileGrant>>.broadcast(sync: true);
  List<FileGrant> _grants(dynamic values) => [
    for (final row in values as List<dynamic>)
      FileGrant(id: row['id'] as String, displayName: row['name'] as String),
  ];
  @override
  Stream<List<FileGrant>> get incomingDocuments {
    channel.invokeMethod<void>('ready').catchError((Object _) {});
    return _incoming.stream;
  }

  @override
  Future<PlatformResult<List<FileGrant>>> chooseDocuments() async {
    try {
      return PlatformSuccess(
        _grants(await channel.invokeMethod<dynamic>('choose')),
      );
    } on MissingPluginException {
      return const PlatformUnavailable(PlatformFailure.unsupported);
    } on PlatformException {
      return const PlatformUnavailable(PlatformFailure.permissionDenied);
    }
  }

  @override
  Future<PlatformResult<FileGrant?>> chooseCover() async {
    try {
      final rows = _grants(await channel.invokeMethod<dynamic>('chooseCover'));
      return PlatformSuccess(rows.firstOrNull);
    } on PlatformException {
      return const PlatformUnavailable(PlatformFailure.permissionDenied);
    }
  }

  @override
  Future<PlatformResult<FileGrant?>> chooseDocument() async {
    final result = await chooseDocuments();
    if (result is PlatformSuccess<List<FileGrant>>) {
      for (final extra in result.value.skip(1)) {
        await releaseGrant(extra);
      }
      return PlatformSuccess(result.value.firstOrNull);
    }
    return const PlatformUnavailable(PlatformFailure.permissionDenied);
  }

  @override
  Future<PlatformResult<FileGrant>> restoreGrant(String grantId) async {
    try {
      final row = await channel.invokeMapMethod<String, dynamic>('restore', {
        'id': grantId,
      });
      return PlatformSuccess(
        FileGrant(id: grantId, displayName: row!['name'] as String),
      );
    } on PlatformException {
      return const PlatformUnavailable(PlatformFailure.permissionDenied);
    }
  }

  @override
  Stream<List<int>> readDocument(FileGrant grant) => _read(grant, 0, null);
  @override
  Stream<List<int>> readDocumentRange(FileGrant grant, int start, int end) =>
      _read(grant, start, end);
  Stream<List<int>> _read(FileGrant grant, int start, int? end) async* {
    if (start < 0 || (end != null && (end < start || end > 64 * 1024 * 1024))) {
      throw const ImportFailure(ImportIssue.tooLarge);
    }
    var remaining = end == null ? null : end - start;
    String? handle;
    try {
      handle = await channel.invokeMethod<String>('open', {
        'id': grant.id,
        'start': start,
      });
      while (remaining == null || remaining > 0) {
        final chunk = await channel.invokeMethod<Uint8List>('read', {
          'handle': handle,
        });
        if (chunk == null || chunk.isEmpty) break;
        final accepted = remaining != null && remaining < chunk.length
            ? Uint8List.sublistView(chunk, 0, remaining)
            : chunk;
        yield accepted;
        if (remaining != null) remaining -= accepted.length;
      }
    } on PlatformException catch (e) {
      throw ImportFailure(
        e.code == 'missing'
            ? ImportIssue.missing
            : e.code == 'tooLarge'
            ? ImportIssue.tooLarge
            : ImportIssue.permission,
      );
    } finally {
      if (handle != null) {
        await channel.invokeMethod<void>('close', {'handle': handle});
      }
    }
  }

  @override
  Future<void> retainGrant(FileGrant grant) =>
      channel.invokeMethod<void>('retain', {'id': grant.id});
  @override
  Future<void> releaseGrant(FileGrant grant) =>
      channel.invokeMethod<void>('release', {'id': grant.id});
  @override
  Future<void> forgetGrant(FileGrant grant) =>
      channel.invokeMethod<void>('forget', {'id': grant.id});
  Future<String> legacyPreview(String path, TextEncoding encoding) async {
    try {
      return (await channel.invokeMethod<String>('decodeSnapshot', {
        'path': path,
        'encoding': encoding.name,
      }))!;
    } on PlatformException {
      throw const ImportFailure(ImportIssue.encoding);
    }
  }

  Future<void> dispose() async {
    channel.setMethodCallHandler(null);
    await _incoming.close();
  }
}
