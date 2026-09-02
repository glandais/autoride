/// Verbosity of the opt-in audit log.
///
/// Lives in `core/` rather than next to the sink so `UserSettings` can store it
/// without `core/` having to know about `features/settings`.
enum AuditLogLevel {
  /// Nothing is recorded. The sink is not installed and no database is opened.
  off,

  /// State transitions, detector decisions, GPS fixes (~1 Hz), battery,
  /// permissions and lifecycle. Roughly 1.4 MB per hour of riding.
  ///
  /// This is the level to use when measuring battery drain
  /// (`tasks/T041-device-validation.md` item 4): the log is an observer, and a
  /// verbose one is not a neutral observer.
  normal,

  /// Everything in [normal] plus 1 Hz sensor aggregates (accelerometer
  /// std-dev, mean gyroscope), the stationary window verdicts and the route
  /// points that were *rejected*. Roughly 3.7 MB per hour of riding.
  ///
  /// Raw 50 Hz sensor samples are never recorded at any level: they would be
  /// ~50 MB/h and would cost more battery than the pipeline being observed.
  verbose,
}

/// Extension methods for [AuditLogLevel].
extension AuditLogLevelExtensions on AuditLogLevel {
  /// Whether verbose-only events are recorded at this level.
  bool get includesVerbose => this == AuditLogLevel.verbose;

  /// Whether anything at all is recorded at this level.
  bool get isOn => this != AuditLogLevel.off;

  /// Short label written into the exported file's header.
  String get label => name;
}
