import 'dart:async';

import '../domain/access.dart';

/// Publishes restrictions synchronously; grants become visible only after the
/// current desired state is durably saved. Queued old writes cannot reopen it.
final class AccessController {
  AccessController(this.store, {AccessState initial = const AccessState()})
    : _state = initial,
      _desired = initial;
  final DeviceAccessStore store;
  AccessState _state, _desired;
  final _events = StreamController<AccessState>.broadcast(sync: true);
  final _stops = <void Function()>{};
  Future<void> _tail = Future.value();
  bool _disposed = false;
  int _request = 0;
  AccessState get state => _state;
  Stream<AccessState> get changes => _events.stream;
  static Future<AccessController> open(DeviceAccessStore store) async =>
      AccessController(store, initial: await store.read());
  void _publish(AccessState next) {
    if (_disposed) return;
    final visibility =
        next.acknowledged != _state.acknowledged ||
        next.privacyLocked != _state.privacyLocked;
    final concealed = _state.adultVisible && !next.adultVisible;
    _state = next.copy(
      revision: _state.revision + 1,
      visibilityRevision: _state.visibilityRevision + (visibility ? 1 : 0),
    );
    if (concealed) {
      for (final stop in List.of(_stops)) {
        try {
          stop();
        } catch (_) {
          /* no untrusted callback may prevent concealment */
        }
      }
    }
    _events.add(_state);
  }

  AccessState _safe(AccessState a, AccessState b) => a.copy(
    acknowledged: a.acknowledged && b.acknowledged,
    includeAdultSources: a.includeAdultSources && b.includeAdultSources,
    privacyLocked: a.privacyLocked || b.privacyLocked,
  );
  Future<void> _change(AccessState Function(AccessState) change) {
    if (_disposed) return Future.error(StateError('disposed'));
    _desired = change(_desired);
    final request = ++_request;
    _publish(_safe(_state, _desired));
    final operation = _tail.then((_) async {
      final target = _desired;
      try {
        await store.write(target);
        if (request == _request) _publish(target);
      } catch (_) {
        _desired = _safe(_state, _desired);
        _publish(_desired);
        rethrow;
      }
    });
    _tail = operation.catchError((Object _) {});
    return operation;
  }

  Future<void> acknowledge() => _change((s) => s.copy(acknowledged: true));
  Future<void> clearAcknowledgement() => _change(
    (s) => s.copy(
      acknowledged: false,
      includeAdultSources: false,
      privacyLocked: true,
    ),
  );
  Future<void> setDiscovery(bool value) {
    if (value && !_state.acknowledged) {
      return Future.error(StateError('acknowledgement_required'));
    }
    return _change((s) => s.copy(includeAdultSources: value));
  }

  Future<void> lock() => _change((s) => s.copy(privacyLocked: true));
  Future<void> unlock() => _change((s) => s.copy(privacyLocked: false));

  /// Rendering/readers/TTS/windows/notifications register synchronous invalidation.
  /// Native shutdown may finish later, but no old session may publish afterwards.
  void Function() registerProtectedStop(void Function() stop) {
    _stops.add(stop);
    return () => _stops.remove(stop);
  }

  void invalidateProtected() {
    if (_disposed) return;
    for (final stop in List.of(_stops)) {
      try {
        stop();
      } catch (_) {}
    }
    _state = _state.copy(
      revision: _state.revision + 1,
      visibilityRevision: _state.visibilityRevision + 1,
    );
    _events.add(_state);
  }

  Future<void> dispose() async {
    await _tail;
    _disposed = true;
    _stops.clear();
    await _events.close();
  }
}

final class MemoryAccessStore implements DeviceAccessStore {
  MemoryAccessStore([this.value = const AccessState()]);
  AccessState value;
  @override
  Future<AccessState> read() async => value;
  @override
  Future<void> write(AccessState state) async {
    value = state;
  }
}
