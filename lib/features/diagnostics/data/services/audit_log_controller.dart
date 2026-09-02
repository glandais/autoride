import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:sqflite/sqflite.dart';

import 'package:autoride/core/audit/audit_event.dart';
import 'package:autoride/core/audit/audit_level.dart';
import 'package:autoride/core/audit/audit_log.dart';
import 'package:autoride/core/audit/audit_schema.dart';
import 'package:autoride/core/constants/app_constants.dart';
import 'package:autoride/features/diagnostics/data/services/sqlite_audit_sink.dart';
import 'package:autoride/features/diagnostics/domain/models/audit_log_stats.dart';
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
  Stopwatch? _uptime;
  int _clockReferenceWall = 0;
  int _clockReferenceMono = 0;

  @override
  AuditLogLevel build() {
    final settings = ref.watch(currentSettingsProvider);
    final level = settings.auditLogEnabled
        ? settings.auditLogLevel
        : AuditLogLevel.off;

    ref.onDispose(() {
      AuditLog.uninstall();
      unawaited(_sink?.close());
      _sink = null;
    });

    _apply(level);
    return level;
  }

  void _apply(AuditLogLevel level) {
    if (!level.isOn) {
      AuditLog.uninstall();
      // The sink is kept, not closed: turning the log off must not erase what
      // is already recorded — the user may well be turning it off precisely
      // because the interesting ride is over and they are about to export it.
      unawaited(_sink?.flush());
      return;
    }

    // Opened lazily, so a user who never turns the log on never gets a
    // database file at all.
    final sink = _sink ?? (_sink = ref.read(auditSinkProvider))!;
    AuditLog.install(sink, verbose: level.includesVerbose);
    _emitSessionHeader(level);
  }

  /// A header per process launch, so a file spanning two builds carries both.
  ///
  /// The export rebuilds a full header of its own; this one exists because a
  /// log that covers an app update would otherwise be read entirely against
  /// the *newer* build's thresholds.
  void _emitSessionHeader(AuditLogLevel level) {
    final uptime = _uptime ??= (Stopwatch()..start());
    _clockReferenceWall = DateTime.now().millisecondsSinceEpoch;
    _clockReferenceMono = uptime.elapsedMilliseconds;

    AuditLog.emit(
      AuditEvent.header,
      () => <String, Object?>{
        'sv': AuditSchema.version,
        'lvl': level.label,
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
    if (!AuditLog.enabled) return;
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
    AuditLog.emit(
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
    if (!AuditLog.enabled) return;

    AuditLog.emit(
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
