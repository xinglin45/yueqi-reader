enum DiagnosticCode { framework, unhandled }

/// Bounded, session-only codes. No exception strings, stacks, paths or tokens.
final class SafeDiagnostics {
  SafeDiagnostics._();
  static final _codes = <DiagnosticCode>[];
  static List<DiagnosticCode> get codes => List.unmodifiable(_codes);
  static void record(DiagnosticCode code) {
    if (_codes.length == 20) _codes.removeAt(0);
    _codes.add(code);
  }
}
