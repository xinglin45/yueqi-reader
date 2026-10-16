import 'package:platform_services/platform_services.dart';

import '../domain/library.dart';
import '../infrastructure/session_library.dart';

final class AppDependencies {
  const AppDependencies({
    required this.library,
    required this.files,
    required this.secrets,
    required this.speech,
    required this.windows,
  });
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
  final LibraryRepository library;
  final FileAccess files;
  final SecureStore secrets;
  final SpeechService speech;
  final WindowIntegration windows;
}
