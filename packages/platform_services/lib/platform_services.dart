/// Portable contracts only. Adapters own paths, permissions and native handles.
library;

enum PlatformFailure { unsupported, permissionDenied, unavailable, cancelled }

sealed class PlatformResult<T> {
  const PlatformResult();
}

final class PlatformSuccess<T> extends PlatformResult<T> {
  const PlatformSuccess(this.value);
  final T value;
}

final class PlatformUnavailable<T> extends PlatformResult<T> {
  const PlatformUnavailable(this.reason);
  final PlatformFailure reason;
}

/// Opaque, local adapter references. Neither URIs nor credentials belong here.
final class FileGrant {
  const FileGrant({required this.id, required this.displayName});
  final String id;
  final String displayName;
}

abstract interface class FileAccess {
  Future<PlatformResult<FileGrant?>> chooseDocument();
  Future<PlatformResult<FileGrant>> restoreGrant(String grantId);
}

/// Secrets never cross this boundary as printable strings or export data.
final class CredentialRef {
  const CredentialRef(this.id);
  final String id;
}

abstract interface class SecureStore {
  Future<PlatformResult<CredentialRef?>> lookup(String serviceId);
  Future<PlatformResult<void>> remove(CredentialRef credential);
}

enum SpeechOffsetUnit { utf16CodeUnit, unicodeScalar, unavailable }

final class SpeechCapabilities {
  const SpeechCapabilities({required this.pause, required this.offsetUnit});
  final bool pause;
  final SpeechOffsetUnit offsetUnit;
}

final class SpeechVoice {
  const SpeechVoice({
    required this.id,
    required this.language,
    required this.offline,
  });
  final String id;
  final String language;
  final bool offline;
}

final class SpeechEvent {
  const SpeechEvent({
    required this.sessionId,
    required this.finished,
    this.offset,
  });
  final String sessionId;
  final bool finished;
  final int? offset;
}

abstract interface class SpeechService {
  SpeechCapabilities get capabilities;
  Stream<SpeechEvent> get events;
  Future<PlatformResult<List<SpeechVoice>>> voices();
  Future<PlatformResult<void>> speak({
    required String sessionId,
    required String voiceId,
    required String text,
  });
  Future<PlatformResult<void>> pause(String sessionId);
  Future<PlatformResult<void>> resume(String sessionId);
  Future<PlatformResult<void>> stop(String sessionId);
}

enum ReaderSurface { normal, menubar, strip, mini }

abstract interface class WindowIntegration {
  Future<PlatformResult<void>> showSurface(ReaderSurface surface);
  Future<PlatformResult<void>> hideReading();
}

/// Honest fallback, shared by unimplemented/unsupported platform adapters.
final class UnavailablePlatform
    implements FileAccess, SecureStore, SpeechService, WindowIntegration {
  const UnavailablePlatform();
  PlatformResult<T> _unsupported<T>() =>
      const PlatformUnavailable(PlatformFailure.unsupported);
  @override
  Future<PlatformResult<FileGrant?>> chooseDocument() async => _unsupported();
  @override
  Future<PlatformResult<FileGrant>> restoreGrant(String grantId) async =>
      _unsupported();
  @override
  Future<PlatformResult<CredentialRef?>> lookup(String serviceId) async =>
      _unsupported();
  @override
  Future<PlatformResult<void>> remove(CredentialRef credential) async =>
      _unsupported();
  @override
  SpeechCapabilities get capabilities => const SpeechCapabilities(
    pause: false,
    offsetUnit: SpeechOffsetUnit.unavailable,
  );
  @override
  Stream<SpeechEvent> get events => const Stream.empty();
  @override
  Future<PlatformResult<List<SpeechVoice>>> voices() async => _unsupported();
  @override
  Future<PlatformResult<void>> speak({
    required String sessionId,
    required String voiceId,
    required String text,
  }) async => _unsupported();
  @override
  Future<PlatformResult<void>> pause(String sessionId) async => _unsupported();
  @override
  Future<PlatformResult<void>> resume(String sessionId) async => _unsupported();
  @override
  Future<PlatformResult<void>> stop(String sessionId) async => _unsupported();
  @override
  Future<PlatformResult<void>> showSurface(ReaderSurface surface) async =>
      _unsupported();
  @override
  Future<PlatformResult<void>> hideReading() async => _unsupported();
}
