import '../application/access.dart';
import '../application/discovery.dart';
import '../infrastructure/device_access_store.dart';

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:reader_core/reader_core.dart';
import 'package:reader_storage/reader_storage.dart';
import 'package:platform_services/platform_services.dart';

import '../domain/documents.dart';
import '../infrastructure/storage/local_library.dart';
import '../infrastructure/storage/schema.dart';

import '../domain/library.dart';
import '../infrastructure/session_library.dart';

final class AppDependencies {
  const AppDependencies({
    required this.library,
    required this.files,
    required this.secrets,
    required this.speech,
    required this.windows,
    this.positions,
    this.access,
    this.discovery,
    this.storageReadOnly = false,
    this.initialDark = false,
    this.persistTheme,
    this.close,
  });

  /// Session-only composition for widget tests; production uses open().
  factory AppDependencies.local() {
    const platform = UnavailablePlatform();
    return AppDependencies(
      library: SessionLibrary(),
      files: platform,
      secrets: platform,
      speech: platform,
      windows: platform,
    );
  }
  static Future<AppDependencies> open(StorageLocationProvider provider) async {
    final locations = await provider.locations();
    final directory = p.join(locations.support, ReaderProduct.novel.namespace);
    await Directory(p.join(locations.cache, ReaderProduct.novel.namespace))
        .create(recursive: true);
    final fresh = !await File(p.join(directory, 'novel.sqlite')).exists();
    final access = await AccessController.open(
      LocalDeviceAccessStore(p.join(locations.support, 'novel-device')),
    );
    if (fresh) {
      try {
        await access.clearAcknowledgement();
        await access.unlock();
      } catch (_) {
        /* Ordinary reading remains available, grants fail closed. */
      }
    }
    final discovery = DiscoveryCoordinator(
      access,
      const [],
      (_, _, _, _) async => const [],
    );
    StorageDatabase? opened;
    try {
      final database = await StorageDatabase.open(
        directory: directory,
        product: ReaderProduct.novel,
        migrations: novelSchema,
      );
      opened = database;
      final library = LocalLibrary(
        database,
        ContentFiles(directory),
        access: access,
      );
      final dark =
          !database.readOnly && await library.loadSetting('theme') == 'dark';
      const platform = UnavailablePlatform();
      return AppDependencies(
        library: library,
        positions: library,
        access: access,
        discovery: discovery,
        files: platform,
        secrets: platform,
        speech: platform,
        windows: platform,
        storageReadOnly: database.readOnly,
        initialDark: dark,
        persistTheme: (value) =>
            library.saveSetting('theme', value ? 'dark' : 'light'),
        close: () async {
          await discovery.dispose();
          await access.dispose();
          await database.close();
        },
      );
    } catch (_) {
      await discovery.dispose();
      await access.dispose();
      await opened?.close();
      rethrow;
    }
  }

  final AccessController? access;
  final DiscoveryCoordinator? discovery;
  final PositionRepository? positions;
  final bool storageReadOnly, initialDark;
  final Future<void> Function(bool dark)? persistTheme;
  final Future<void> Function()? close;
  final LibraryRepository library;
  final FileAccess files;
  final SecureStore secrets;
  final SpeechService speech;
  final WindowIntegration windows;
}
