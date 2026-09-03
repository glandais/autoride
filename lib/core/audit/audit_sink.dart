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
  /// index and purge without parsing it, and [lvl] (0 normal, 1 verbose, 2
  /// training capture) so an export can filter and retention can treat the two
  /// classes separately. [critical] asks for an immediate flush: the event is
  /// one whose absence would make the log inconclusive, so it must reach the
  /// disk before whatever it announces happens.
  ///
  /// [session] is the capture session a `lvl` 2 line belongs to, and is null on
  /// every journal line. Capture retention deletes a *labelled session* whole
  /// — half a session is a corpus whose windows are labelled by a `lbl` line
  /// that no longer exists — and that is the column it groups on.
  ///
  /// Must never throw: the log may not take down the app it observes.
  void write(
    String line, {
    required int t,
    required String type,
    required int lvl,
    required bool critical,
    int? session,
  });

  /// Write everything buffered so far.
  Future<void> flush();
}
