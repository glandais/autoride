/// Destination for audit lines.
///
/// The port half of the audit feature: `lib/core/audit/` defines it, and
/// `lib/features/diagnostics/` provides the SQLite implementation and installs
/// it at startup. The indirection exists because `core/utils/logger.dart` and
/// the plain-Dart pipeline pieces must be able to emit — if the emitting API
/// lived in a feature, `core/` would have to import one.
abstract interface class AuditSink {
  /// Accept one already-serialized NDJSON [line].
  ///
  /// [t] (epoch ms) and [type] are duplicated out of the line so the store can
  /// index and purge without parsing it, and [lvl] (0 normal, 1 verbose) so an
  /// export can filter. [critical] asks for an immediate flush: the event is
  /// one whose absence would make the log inconclusive, so it must reach the
  /// disk before whatever it announces happens.
  ///
  /// Must never throw: the log may not take down the app it observes.
  void write(
    String line, {
    required int t,
    required String type,
    required int lvl,
    required bool critical,
  });

  /// Write everything buffered so far.
  Future<void> flush();
}
