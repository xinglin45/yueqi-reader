import '../domain/shelf.dart';
import '../infrastructure/shelf/local_shelf.dart';
import '../domain/epub.dart';
import '../infrastructure/epub/local_epub_reader.dart';
import '../domain/importing.dart';
import '../domain/txt.dart';
import '../infrastructure/txt/local_txt_reader.dart';
import '../infrastructure/importing/local_importer.dart';
import '../infrastructure/importing/text_inspector.dart';
import '../infrastructure/mac_document_access.dart';
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
    this.shelf,
    this.positions,
    this.importer,
    this.txt,
    this.epub,
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
  static Future<AppDependencies> open(
    StorageLocationProvider provider, {
    DocumentAccess? documents,
    LegacyTextPreview? legacy,
  }) async {
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
    DocumentAccess? documentFiles;
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
      documentFiles =
          documents ?? (Platform.isMacOS ? MacDocumentAccess() : null);
      final importer = documentFiles == null || database.readOnly
          ? null
          : LocalImporter(
              library,
              access,
              documentFiles,
              directory,
              TextInspector(
                legacy ??
                    ((path, encoding) => (documentFiles as MacDocumentAccess)
                        .legacyPreview(path, encoding)),
              ),
            );
      await importer?.initialize();
      final txt = importer == null ? null : LocalTxtReader(importer);
      await txt?.initialize();
      final epub = importer == null ? null : LocalEpubReader(importer);
      await epub?.initialize();
      final shelf = database.readOnly ? null : LocalShelf(library, importer);
      await shelf?.initialize();
      return AppDependencies(
        library: library,
        shelf: shelf,
        positions: library,
        access: access,
        discovery: discovery,
        files: documentFiles ?? platform,
        importer: importer,
        txt: txt,
        epub: epub,
        secrets: platform,
        speech: platform,
        windows: platform,
        storageReadOnly: database.readOnly,
        initialDark: dark,
        persistTheme: (value) =>
            library.saveSetting('theme', value ? 'dark' : 'light'),
        close: () async {
          await shelf?.dispose();
          await epub?.dispose();
          await txt?.dispose();
          await importer?.dispose();
          await discovery.dispose();
          await access.dispose();
          if (documentFiles is MacDocumentAccess) await documentFiles.dispose();
          await database.close();
        },
      );
    } catch (_) {
      await discovery.dispose();
      await access.dispose();
      if (documentFiles is MacDocumentAccess) await documentFiles.dispose();
      await opened?.close();
      rethrow;
    }
  }

  final ShelfRepository? shelf;
  final DocumentImporter? importer;
  final TxtDocumentReader? txt;
  final EpubDocumentReader? epub;
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
