import 'audit_event.dart';
import 'audit_level.dart';
import 'audit_sink.dart';

/// The opt-in audit log's emitting API.
///
/// Deliberately static, like [Logger]. The call sites are inside stream
/// callbacks, inside plain-Dart pipeline pieces (`stationary_window.dart`,
/// `pre_trip_location_buffer.dart`) and inside `core/utils/logger.dart` —
/// threading a `Ref` through them would pollute a dozen signatures and make the
/// pure pieces un-instrumentable. The *lifetime* is owned by
/// `AuditLogController` (a `keepAlive` provider), which installs a sink when the
/// user turns the log on and removes it when they turn it off.
///
/// ## Cost when the log is off
///
/// [emit] is a static field load, a null test and a return. The cost that is
/// easy to get wrong is at the *call site*: a closure that captures locals
/// allocates a context object every time it is evaluated — **including when the
/// log is off** — because the allocation happens in building the argument, not
/// in the call. Only a non-capturing closure is canonicalised.
///
/// So: pass a lazy closure everywhere, and on anything running at 1 Hz or more
/// (`fix`, `start`, `stop`, `res`, `win`, `sens`, `rp`, `hb`) also guard the
/// call:
///
/// ```dart
/// if (AuditLog.enabled) {
///   AuditLog.emit(AuditEvent.fix, () => {'lat': location.latitude});
/// }
/// ```
abstract final class AuditLog {
  static AuditSink? _sink;
  static bool _verbose = false;

  /// Whether a sink is installed. Test this explicitly before emitting on any
  /// path that runs at 1 Hz or more — see the class comment.
  static bool get enabled => _sink != null;

  /// Whether verbose-level events are being recorded.
  static bool get verbose => _verbose;

  /// The sink currently installed, or null. Exposed for the controller's flush.
  static AuditSink? get sink => _sink;

  /// Start recording into [sink].
  ///
  /// Replaces any sink already installed rather than failing: a hot restart in
  /// development would otherwise leave a zombie sink writing to a closed
  /// database.
  static void install(AuditSink sink, {required bool verbose}) {
    _sink = sink;
    _verbose = verbose;
  }

  /// Change the verbosity of an already-installed sink.
  static void setVerbose({required bool verbose}) => _verbose = verbose;

  /// Stop recording. Does not flush — the caller owns the sink's lifecycle.
  static void uninstall() {
    _sink = null;
    _verbose = false;
  }

  /// Record a normal-level event.
  ///
  /// [fields] is a closure so nothing is built when the log is off. Set
  /// [critical] on any event whose absence would make the log inconclusive —
  /// it forces an immediate flush, so the event reaches the disk before the
  /// thing it announces happens (and before a kill can take the buffer).
  static void emit(
    String type,
    Map<String, Object?> Function() fields, {
    bool critical = false,
  }) {
    final sink = _sink;
    if (sink == null) return;
    _write(sink, type, fields, 0, critical);
  }

  /// Record a verbose-level event; a no-op unless the level is
  /// [AuditLogLevel.verbose].
  static void emitVerbose(String type, Map<String, Object?> Function() fields) {
    final sink = _sink;
    if (sink == null || !_verbose) return;
    _write(sink, type, fields, 1, false);
  }

  static void _write(
    AuditSink sink,
    String type,
    Map<String, Object?> Function() fields,
    int level,
    bool critical,
  ) {
    final t = DateTime.now().millisecondsSinceEpoch;
    try {
      sink.write(
        AuditEvent.encode(t, type, fields()),
        t: t,
        type: type,
        lvl: level,
        critical: critical,
      );
    } catch (_) {
      // A field getter that throws, or a sink that fails, must not propagate
      // into the pipeline being observed. Losing one line is always preferable
      // to breaking a ride that is being recorded.
    }
  }
}
