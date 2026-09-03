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
/// ## Two axes, not one scale
///
/// The diagnostic journal has a linear level ([AuditLogLevel]); the training
/// capture of T034 is a **separate axis**. They share one sink and one file and
/// are otherwise independent: capture can run with diagnostics off, and the
/// journal can run without capture. Putting capture inside `verbose` would have
/// forced every diagnostic line along with it, and — since capture is ~8 MB/h
/// against the journal's ~2 — made the two impossible to budget separately.
///
/// So there are three emit entry points, and they answer three questions:
///
/// * [emit] / [emitVerbose] — what the pipeline did (`lvl` 0 and 1);
/// * [emitCapture] — training data (`lvl` 2), gated on [captureEnabled] alone;
/// * [emitAlways] — the things that must exist whenever *anything* is being
///   recorded, whichever axis turned the sink on: the session header and the
///   log's statements about itself.
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
///
/// [enabled] is that guard, and it means "the journal is recording" — not "a
/// sink is installed". The two stopped being the same thing when capture became
/// able to install a sink on its own: a guard reading "installed" would have
/// let every 1 Hz journal line through during a capture-only session, which is
/// the one session that must stay at ~8 MB/h and not ~10.
abstract final class AuditLog {
  static AuditSink? _sink;
  static AuditLogLevel _level = AuditLogLevel.off;
  static bool _capture = false;
  static int? _captureSession;

  /// Whether the diagnostic journal is recording. Test this explicitly before
  /// emitting on any path that runs at 1 Hz or more — see the class comment.
  static bool get enabled => _sink != null && _level.isOn;

  /// Whether verbose-level events are being recorded.
  static bool get verbose => _sink != null && _level.includesVerbose;

  /// The journal level currently in force, `off` when nothing is installed.
  static AuditLogLevel get level => _sink == null ? AuditLogLevel.off : _level;

  /// Whether raw training capture is being recorded. Independent of [enabled].
  static bool get captureEnabled => _sink != null && _capture;

  /// The capture session [emitCapture] stamps its lines with, or null.
  static int? get captureSession => _captureSession;

  /// Whether a sink is installed at all, on either axis. Only the log's own
  /// lifetime owner has any business asking.
  static bool get installed => _sink != null;

  /// The sink currently installed, or null. Exposed for the controller's flush.
  static AuditSink? get sink => _sink;

  /// Start recording into [sink] at [level], with capture on [capture].
  ///
  /// Replaces any sink already installed rather than failing: a hot restart in
  /// development would otherwise leave a zombie sink writing to a closed
  /// database.
  static void install(
    AuditSink sink, {
    required AuditLogLevel level,
    bool capture = false,
  }) {
    _sink = sink;
    _level = level;
    _capture = capture;
  }

  /// Change the journal level of an already-installed sink.
  static void setLevel(AuditLogLevel level) => _level = level;

  /// Turn raw capture on or off on an already-installed sink.
  ///
  /// [session] stamps every capture row so retention can delete a labelled
  /// session whole; it is required while capture is on and cleared with it.
  static void setCapture({required bool capture, int? session}) {
    _capture = capture;
    _captureSession = capture ? session : null;
  }

  /// Stop recording. Does not flush — the caller owns the sink's lifecycle.
  static void uninstall() {
    _sink = null;
    _level = AuditLogLevel.off;
    _capture = false;
    _captureSession = null;
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
    if (sink == null || !_level.isOn) return;
    _write(sink, type, fields, 0, critical);
  }

  /// Record a verbose-level event; a no-op unless the level is
  /// [AuditLogLevel.verbose].
  static void emitVerbose(String type, Map<String, Object?> Function() fields) {
    final sink = _sink;
    if (sink == null || !_level.includesVerbose) return;
    _write(sink, type, fields, 1, false);
  }

  /// Record a capture-level event (`lvl` 2); a no-op unless capture is on.
  ///
  /// Independent of [level]: this is the only emit that survives a
  /// capture-with-diagnostics-off session, and the only one that does *not*
  /// survive a diagnostics-only one.
  static void emitCapture(
    String type,
    Map<String, Object?> Function() fields, {
    bool critical = false,
  }) {
    final sink = _sink;
    if (sink == null || !_capture) return;
    _write(sink, type, fields, 2, critical, session: _captureSession);
  }

  /// Record an event that belongs to the file rather than to either axis.
  ///
  /// The session header and the log's own `aud` markers: a capture-only file
  /// with no `hdr` is read against whatever `AppConstants` the reader happens
  /// to have, which is exactly the mistake the header exists to prevent — and
  /// [emit] would drop it, because the journal is off.
  static void emitAlways(
    String type,
    Map<String, Object?> Function() fields, {
    bool critical = false,
  }) {
    final sink = _sink;
    if (sink == null) return;
    _write(sink, type, fields, 0, critical);
  }

  static void _write(
    AuditSink sink,
    String type,
    Map<String, Object?> Function() fields,
    int level,
    bool critical, {
    int? session,
  }) {
    final t = DateTime.now().millisecondsSinceEpoch;
    try {
      sink.write(
        AuditEvent.encode(t, type, fields()),
        t: t,
        type: type,
        lvl: level,
        critical: critical,
        session: session,
      );
    } catch (_) {
      // A field getter that throws, or a sink that fails, must not propagate
      // into the pipeline being observed. Losing one line is always preferable
      // to breaking a ride that is being recorded.
    }
  }
}
