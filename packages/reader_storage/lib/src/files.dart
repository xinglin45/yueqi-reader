import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'database.dart';

String newLocalId() {
  final random = Random.secure();
  return List.generate(
    16,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}

/// Managed objects are immutable; database failure leaves a recoverable orphan.
final class ContentFiles {
  ContentFiles(this.root);
  final String root;
  Future<Directory> _objects() async {
    final objects = Directory(p.join(root, 'objects'));
    if (await FileSystemEntity.type(objects.path, followLinks: false) ==
        FileSystemEntityType.link) {
      throw const StorageFailure('unsafe_path');
    }
    return objects.create(recursive: true);
  }

  Future<File> _file(String digest) async {
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(digest))
      throw const StorageFailure('digest');
    final objects = await _objects();
    final file = File(p.join(objects.path, digest));
    if (await FileSystemEntity.type(file.path, followLinks: false) ==
        FileSystemEntityType.link) {
      throw const StorageFailure('unsafe_path');
    }
    return file;
  }

  Future<String> put(List<int> bytes, {int maxBytes = 8 * 1024 * 1024}) async {
    if (bytes.length > maxBytes) throw const StorageFailure('file_budget');
    final digest = sha256.convert(bytes).toString();
    final target = await _file(digest);
    if (await target.exists()) {
      await read(digest);
      return digest;
    }
    final temp = File(
      p.join((await _objects()).path, '.stage-${newLocalId()}'),
    );
    try {
      await temp.writeAsBytes(bytes, flush: true);
      if ((await sha256.bind(temp.openRead()).first).toString() != digest) {
        throw const StorageFailure('file_verification');
      }
      await temp.rename(target.path);
      return digest;
    } finally {
      if (await temp.exists()) await temp.delete();
    }
  }

  Future<List<int>> read(
    String digest, {
    int maxBytes = 8 * 1024 * 1024,
  }) async {
    final file = await _file(digest);
    if (!await file.exists()) throw const StorageFailure('file_missing');
    final bytes = <int>[];
    await for (final chunk in file.openRead()) {
      if (bytes.length + chunk.length > maxBytes)
        throw const StorageFailure('file_budget');
      bytes.addAll(chunk);
    }
    if (sha256.convert(bytes).toString() != digest)
      throw const StorageFailure('file_corrupt');
    return bytes;
  }

  Future<Map<String, List<String>>> audit(Set<String> referenced) async {
    final present = <String>{};
    await for (final item in (await _objects()).list(followLinks: false)) {
      final name = p.basename(item.path);
      if (item is File && RegExp(r'^[a-f0-9]{64}$').hasMatch(name))
        present.add(name);
    }
    return {
      'missing': referenced.difference(present).toList(),
      'orphaned': present.difference(referenced).toList(),
    };
  }
}
