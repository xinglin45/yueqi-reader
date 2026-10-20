import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:reader_storage/reader_storage.dart';

import '../domain/access.dart';

/// Sibling of the portable novel library, never inside its database/objects.
/// App backup/sync excludes this local self-attestation and discovery state.
/// This is interface concealment, not encryption or OS-image-copy protection.
final class LocalDeviceAccessStore implements DeviceAccessStore {
  LocalDeviceAccessStore(this.directory);
  final String directory;
  Future<File> _file() async {
    final root = Directory(directory);
    if (await FileSystemEntity.type(directory, followLinks: false) ==
        FileSystemEntityType.link) {
      throw const FormatException('device_directory');
    }
    await root.create(recursive: true);
    final file = File(p.join(directory, 'access-v1.json'));
    if (await FileSystemEntity.type(file.path, followLinks: false) ==
        FileSystemEntityType.link) {
      throw const FormatException('device_file');
    }
    return file;
  }

  @override
  Future<AccessState> read() async {
    try {
      final file = await _file();
      if (!await file.exists()) return const AccessState();
      if (await file.length() > 2048) {
        throw const FormatException('device_budget');
      }
      return AccessState.fromLocalJson(
        jsonDecode(await file.readAsString()) as Map<String, dynamic>,
      );
    } catch (_) {
      return const AccessState(privacyLocked: true);
    }
  }

  @override
  Future<void> write(AccessState state) async {
    final target = await _file();
    final temp = File(p.join(directory, '.access-${newLocalId()}'));
    try {
      await temp.writeAsString(jsonEncode(state.toLocalJson()), flush: true);
      await temp.rename(target.path);
    } finally {
      if (await temp.exists()) await temp.delete();
    }
  }
}
