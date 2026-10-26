import 'dart:async';
import 'dart:convert';

import 'package:platform_services/platform_services.dart';

import '../domain/documents.dart';
import '../domain/reading.dart';

class ReadingObservable {
  final _changes = StreamController<void>.broadcast(sync: true);
  Stream<void> get changes => _changes.stream;
  void notifyListeners() {
    if (!_changes.isClosed) _changes.add(null);
  }

  void dispose() {
    unawaited(_changes.close());
  }
}

/// Single foreground cursor. Future native surfaces attach to this same object.
final class ReadingSession extends ReadingObservable {
  ReadingSession(
    this.owner,
    this.identity,
    this.preferences,
    this.overridden,
    this.sequence,
    this.anchor,
    this.needsReview,
  ) {
    _durable = needsReview ? null : anchor;
  }
  final ReadingCoordinator owner;
  final ReadingIdentity identity;
  ReadingPreferences preferences;
  bool overridden, needsReview;
  int sequence;
  DocumentAnchor? anchor;
  final history = <DocumentAnchor>[];
  ReaderSurface surface = ReaderSurface.normal;
  bool visible = true, advancing = false, focus = false, active = true;
  String? error;
  Timer? _timer;
  DocumentAnchor? _pending, _durable;
  Future<void>? _ending;
  bool _rebase = false;
  int _saving = 0, _epoch = 0;
  Future<DocumentAnchor?> Function()? capture;
  Future<bool> Function(DocumentAnchor)? navigate;
  Future<bool> jumpTo(DocumentAnchor target, {bool remember = true}) async {
    if (!active || !identity.admits(target) || navigate == null) return false;
    if (remember) rememberJump();
    await flush();
    if (!active) return false;
    return navigate!(target);
  }

  Future<void> captureLatest() async {
    if (!active) return;
    try {
      final value = await capture?.call();
      if (value != null && active) observe(value);
    } catch (_) {
      /* Last validated observation remains pending. */
    }
  }

  bool _same(DocumentAnchor? a, DocumentAnchor? b) =>
      jsonEncode(a?.toJson()) == jsonEncode(b?.toJson());
  void observe(DocumentAnchor value, {bool explicit = false}) {
    if (!active || !visible || _ending != null || !identity.admits(value)) {
      return;
    }
    anchor = value;
    if (explicit) needsReview = false;
    if (needsReview || _same(_pending, value)) return;
    if (!explicit && _saving == 0 && _same(_durable, value)) {
      _pending = null;
      _timer?.cancel();
      _timer = null;
      return;
    }
    _pending = value;
    _timer ??= Timer(
      const Duration(milliseconds: 500),
      () => unawaited(flush()),
    );
  }

  void rememberJump() {
    if (anchor case final a?) {
      history.add(a);
      if (history.length > 20) history.removeAt(0);
    }
  }

  DocumentAnchor? popHistory() => history.isEmpty ? null : history.removeLast();
  void attach(ReaderSurface next) {
    surface = next;
    visible = true;
    advancing = false;
    notifyListeners();
  }

  void hide() {
    visible = false;
    advancing = false;
    unawaited(flush());
    notifyListeners();
  }

  void restore() {
    visible = true;
    advancing = false;
    notifyListeners();
  }

  void setFocus(bool value) {
    focus = value;
    notifyListeners();
  }

  Future<void> setPreferences(
    ReadingPreferences value, {
    bool global = false,
    bool reset = false,
  }) async {
    if (!active) return;
    final validated = ReadingPreferences.fromJson(value.toJson());
    try {
      if (global) {
        await owner.preferences?.saveReadingPreferences(null, validated);
      }
      await owner.preferences?.saveReadingPreferences(
        identity.bookId,
        reset || global ? null : validated,
      );
      if (!active) return;
      preferences = reset
          ? (await owner.preferences?.loadReadingPreferences(null) ??
                const ReadingPreferences())
          : validated;
      overridden = !reset && !global;
      notifyListeners();
    } catch (_) {
      error = '排版设置未能保存，请重试。';
      notifyListeners();
    }
  }

  Future<void> flush() {
    _timer?.cancel();
    _timer = null;
    final next = _pending;
    _pending = null;
    if (next == null || !active || needsReview) return owner._queue;
    _saving++;
    final epoch = _epoch;
    return owner._enqueue(() async {
      if (!active || needsReview || epoch != _epoch) {
        _saving--;
        return;
      }
      try {
        if (_rebase) {
          sequence =
              (await owner.positions.loadPosition(
                identity.bookId,
                PositionChannel.reading,
              ))?.sequence ??
              0;
          _rebase = false;
        }
        if (!active) {
          _saving--;
          return;
        }
        final stored = await owner.positions.savePosition(
          identity.bookId,
          PositionChannel.reading,
          next,
          expectedSequence: sequence,
        );
        sequence = stored.sequence;
        _durable = next;
        error = null;
      } catch (_) {
        // A CAS conflict must not silently replace another session/deletion.
        needsReview = true;
        _rebase = true;
        _epoch++;
        error = '自动进度未保存，旧位置保留；请核对后主动保存。';
      }
      _saving--;
      if (active) notifyListeners();
    });
  }

  Future<void> finish() => _ending ??= _finish();
  Future<void> _finish() async {
    if (!active) return;
    await flush();
    active = false;
    _timer?.cancel();
    if (owner.current == this) {
      await owner._relay?.cancel();
      owner._relay = null;
      owner.current = null;
      owner.notifyListeners();
    }
  }

  void revoke() {
    active = false;
    _pending = null;
    _timer?.cancel();
    focus = false;
    visible = false;
    advancing = false;
    notifyListeners();
  }
}

final class ReadingCoordinator extends ReadingObservable {
  ReadingCoordinator(this.positions, this.preferences);
  final PositionRepository positions;
  final ReadingPreferenceRepository? preferences;
  ReadingSession? current;
  Future<void> _queue = Future.value();
  bool _closed = false;
  int _opening = 0;
  StreamSubscription<void>? _relay;
  Future<void> _enqueue(Future<void> Function() action) {
    final next = _queue.then((_) => action());
    _queue = next.catchError((Object _) {});
    return next;
  }

  Future<ReadingSession> open(
    ReadingIdentity identity, {
    required bool Function() isCurrent,
  }) async {
    final ticket = ++_opening;
    await current?.finish();
    await _queue;
    final saved = await positions.loadPosition(
      identity.bookId,
      PositionChannel.reading,
    );
    var defaults = const ReadingPreferences();
    ReadingPreferences? override;
    var damaged = false;
    try {
      defaults = await preferences?.loadReadingPreferences(null) ?? defaults;
    } on FormatException {
      damaged = true;
    } on ArgumentError {
      damaged = true;
    }
    try {
      override = await preferences?.loadReadingPreferences(identity.bookId);
    } on FormatException {
      damaged = true;
    } on ArgumentError {
      damaged = true;
    }
    if (_closed || ticket != _opening || !isCurrent()) {
      throw StateError('reading_session_expired');
    }
    final session = ReadingSession(
      this,
      identity,
      override ?? defaults,
      override != null,
      saved?.sequence ?? 0,
      saved?.anchor,
      saved != null && !identity.admits(saved.anchor),
    );
    if (damaged) session.error = '排版偏好损坏，已使用默认值；原记录保留。';
    current = session;
    _relay = session.changes.listen((_) => notifyListeners());
    notifyListeners();
    return session;
  }

  void revoke() {
    _opening++;
    unawaited(_relay?.cancel());
    _relay = null;
    current?.revoke();
    current = null;
    notifyListeners();
  }

  Future<void> flush() async {
    await current?.captureLatest();
    await current?.flush();
    await _queue;
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await current?.finish();
    await _queue;
    super.dispose();
  }
}
