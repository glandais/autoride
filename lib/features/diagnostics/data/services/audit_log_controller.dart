import 'dart:async';

import 'package:flutter/widgets.dart';
// For `ProviderListenableSelect` — `riverpod_annotation` does not re-export it.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:sqflite/sqflite.dart';

import 'package:autoride/core/audit/audit_event.dart';
import 'package:autoride/core/audit/audit_level.dart';
import 'package:autoride/core/audit/audit_log.dart';
import 'package:autoride/core/audit/audit_schema.dart';
import 'package:autoride/core/constants/app_constants.dart';
import 'package:autoride/features/diagnostics/data/services/sqlite_audit_sink.dart';
import 'package:autoride/features/diagnostics/domain/models/audit_log_stats.dart';
import 'package:autoride/features/diagnostics/domain/models/capture_session.dart';
import 'package:autoride/features/settings/data/services/settings_service.dart';

part 'audit_log_controller.g.dart';

/// Owns the audit log's lifetime: reads the user's preference, installs or
/// removes the sink, and flushes at the moments the buffer would otherwise be
/// lost.
///
/// The emitting API ([AuditLog]) is static because it is called from stream
/// callbacks and from plain-Dart pipeline pieces that have no `Ref`. This is
/// the other half of that split — the part that legitimately belongs in
/// Riverpod, because it depends on settings and has to be disposed.
///
/// Kept alive for the app's lifetime: the log spans sessions, and a controller
/// disposed between two screens would tear the sink down mid-ride.
@Riverpod(keepAlive: true)
class AuditLogController extends _$AuditLogController {
  SqliteAuditSink? _sink;

  /// The T034 capture axis, which is runtime state rather than a setting: a
  /// capture session is started and stopped from the labelling control, not
  /// persisted. Held here (and not watched) so [setCapture] and a settings
  /// rebuild cannot undo one another — a rebuild triggered by any unrelated
  /// setting used to be enough to tear a live capture down.
  bool _capture = false;
  int? _captureSession;

  /// Whether *this controller* considers the sink installed, so the session
  /// header is emitted once per real off→on transition.
  ///
  /// Deliberately a field on the notifier rather than `AuditLog.installed`:
  /// every rebuild runs the `onDispose` above, which uninstalls before [build]
  /// reinstalls, so the port reads "off" in the middle of a rebuild that
  /// changed nothing. Trusting it there wrote a second `hdr` on every settings
  /// change, and the analysis skill counts `hdr` rows to bound process
  /// launches — one launch would have read as several.
  bool _recording = false;

  /// Whether a capture session is recording. Read by the UI through the
  /// capture controller, which owns the session's lifetime.
  bool get capturing => _capture;

  Stopwatch? _uptime;
  int _clockReferenceWall = 0;
  int _clockReferenceMono = 0;

  @override
  AuditLogLevel build() {
    // Selected rather than watched whole: the two audit fields are the only
    // ones this controller reacts to, and rebuilding on a theme or unit change
    // used to tear the log down mid-ride.
    final (enabled, storedLevel) = ref.watch(
      currentSettingsProvider.select(
        (settings) => (settings.auditLogEnabled, settings.auditLogLevel),
      ),
    );
    final level = enabled ? storedLevel : AuditLogLevel.off;

    // Runs on every *rebuild*, not only on a real disposal — so it must be
    // survivable. It deliberately does not close the sink: the sink is a
    // `keepAlive` provider shared with the exporter, closing it sets
    // `_closed` and every later write is silently dropped while the settings
    // screen still shows the log as on. Its own `onDispose` closes it when the
    // container really goes away.
    ref.onDispose(() {
      AuditLog.uninstall();
      unawaited(_sink?.flush());
    });

    _apply(level);
    return level;
  }

  void _apply(AuditLogLevel level) {
    if (!level.isOn && !_capture) {
      AuditLog.uninstall();
      _recording = false;
      // The sink is kept, not closed: turning the log off must not erase what
      // is already recorded — the user may well be turning it off precisely
      // because the interesting ride is over and they are about to export it.
      unawaited(_sink?.flush());
      return;
    }

    // Opened lazily, so a user who never turns the log on never gets a
    // database file at all.
    final sink = _sink ?? (_sink = ref.read(auditSinkProvider))!;
    final wasRecording = _recording;
    _recording = true;
    AuditLog.install(sink, level: level, capture: _capture);
    if (_capture) {
      AuditLog.setCapture(capture: true, session: _captureSession);
    }

    // Only on off→on, on either axis. The header carries the thresholds a
    // reader must judge the file against, and the analysis skill counts `hdr`
    // rows to bound process launches — emitting one per settings change would
    // make a single launch read as several and invert the verdict on
    // process-death items.
    // Not a remembered level: the header must be emitted once per off→on
    // transition of the *sink*, whichever of the two axes caused it.
    if (!wasRecording) _emitSessionHeader(level);
  }

  /// Turn the T034 capture axis on or off.
  ///
  /// Called synchronously by `CaptureController` rather than watched from
  /// [build]: the `lbl start` line must land on an installed sink, and a
  /// provider rebuild scheduled for some later microtask is not a guarantee of
  /// that ordering. [session] is the id every capture row is stamped with.
  ///
  /// Turning capture off leaves the sink installed when the journal is on, and
  /// removes it when the journal is off — a capture-only session that has
  /// ended must stop holding a database open.
  void setCapture({required bool active, int? session, String? activity}) {
    _capture = active;
    _captureSession = active ? session : null;

    if (active) {
      _apply(state);
      unawaited(_sink!.beginCaptureSession(id: session!, activity: activity!));
      return;
    }

    final ended = session;
    AuditLog.setCapture(capture: false);
    _apply(state);
    if (ended != null) unawaited(_sink?.endCaptureSession(ended));
  }

  /// Counts, span and size of the captured corpus (T034).
  Future<CaptureStats> captureStats() async {
    final sink = _sink;
    if (sink == null) return CaptureStats.empty();
    return sink.captureStats();
  }

  /// Every labelled capture session, newest first.
  Future<List<CaptureSession>> captureSessions() async {
    final sink = _sink;
    if (sink == null) return const <CaptureSession>[];
    return sink.captureSessions();
  }

  /// Record that the finished sessions have been exported, so retention drops
  /// them before it touches one the user still has nowhere else.
  Future<void> markCaptureExported() async =>
      _sink?.markCaptureSessionsExported();

  /// Delete the captured corpus, keeping the diagnostic journal.
  Future<int> clearCapture() async => await _sink?.clearCapture() ?? 0;

  /// A header per off→on transition, so a file spanning two builds carries
  /// both.
  ///
  /// The export rebuilds a full header of its own; this one exists because a
  /// log that covers an app update would otherwise be read entirely against
  /// the *newer* build's thresholds.
  void _emitSessionHeader(AuditLogLevel level) {
    final uptime = _uptime ??= (Stopwatch()..start());
    _clockReferenceWall = DateTime.now().millisecondsSinceEpoch;
    _clockReferenceMono = uptime.elapsedMilliseconds;

    AuditLog.emitAlways(
      AuditEvent.header,
      () => <String, Object?>{
        'sv': AuditSchema.version,
        'lvl': level.label,
        // A capture-only file has `lvl: off` and would otherwise read as a
        // file that recorded nothing.
        'cap': _capture,
        'clk': <String, Object?>{
          'wall': _clockReferenceWall,
          'mono': _clockReferenceMono,
        },
        'k': AuditSchema.thresholds(),
      },
      critical: true,
    );
  }

  /// Emit a fresh clock pair if the wall clock has drifted from the monotonic
  /// one — an NTP correction, or the user changing the date mid-session.
  ///
  /// Alignment against a Strava FIT uses the median of `t - gt` over a run of
  /// fixes; a jump in the middle poisons that median for the whole session
  /// unless the analysis can split the run at the jump.
  void checkClockDrift() {
    // `installed`, not `enabled`: aligning a capture-only file against a ride
    // recorded on a second device needs the clock pair just as much as a
    // diagnostic one does, and a capture session is exactly when the journal
    // may be off.
    if (!AuditLog.installed) return;
    final uptime = _uptime;
    if (uptime == null) return;

    final wall = DateTime.now().millisecondsSinceEpoch;
    final mono = uptime.elapsedMilliseconds;
    final drift = (wall - _clockReferenceWall) - (mono - _clockReferenceMono);

    if (drift.abs() < AppConstants.auditClockDriftThreshold.inMilliseconds) {
      return;
    }

    _clockReferenceWall = wall;
    _clockReferenceMono = mono;
    AuditLog.emitAlways(
      AuditEvent.clock,
      () => <String, Object?>{'wall': wall, 'mono': mono, 'drift': drift},
      critical: true,
    );
  }

  /// Record an app lifecycle change and, on the states that precede a
  /// suspension, get the buffer onto the disk.
  ///
  /// `paused` is the load-bearing one. Android kills a backgrounded process
  /// without `detached` and without running `ref.onDispose`, so a flush hung on
  /// disposal would simply never happen.
  Future<void> onLifecycleState(AppLifecycleState lifecycleState) async {
    // `installed`: the flush below is the whole point of this callback, and a
    // capture-only session backgrounded with a second of samples in the buffer
    // loses them just as surely as a journal one does.
    if (!AuditLog.installed) return;

    AuditLog.emitAlways(
      AuditEvent.lifecycle,
      () => <String, Object?>{'st': lifecycleState.name},
      critical: true,
    );

    if (lifecycleState == AppLifecycleState.paused ||
        lifecycleState == AppLifecycleState.detached ||
        lifecycleState == AppLifecycleState.hidden) {
      await flush();
    }
  }

  /// Write everything buffered so far.
  Future<void> flush() async => _sink?.flush();

  /// The database backing the log, opening it if the log has been on at all.
  ///
  /// Returns null when nothing was ever recorded — there is no file, and the
  /// export has nothing to say.
  Future<Database?> databaseForExport() async {
    final sink = _sink;
    if (sink == null) return null;
    return sink.databaseForExport();
  }

  /// Counts, span and size for the settings screen.
  Future<AuditLogStats> stats() async {
    final sink = _sink;
    if (sink == null) return AuditLogStats.empty(state);
    return sink.stats(state);
  }

  /// Erase the log, keeping the current on/off state.
  Future<void> clear() async {
    await _sink?.clear();
    if (state.isOn) _emitSessionHeader(state);
  }
}
