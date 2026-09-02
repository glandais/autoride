import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:sqflite/sqflite.dart';

import 'package:autoride/core/audit/audit_event.dart';
import 'package:autoride/core/audit/audit_level.dart';
import 'package:autoride/core/audit/audit_sink.dart';
import 'package:autoride/core/constants/app_constants.dart';
import 'package:autoride/features/diagnostics/data/services/audit_database.dart';
import 'package:autoride/features/diagnostics/domain/models/audit_log_stats.dart';

part 'sqlite_audit_sink.g.dart';

/// The sink the controller installs when the user turns the log on.
///
/// A provider rather than a direct construction so tests can substitute one
/// backed by an in-memory database — the real one reaches for
/// `getDatabasesPath()`, which needs a platform channel. Nothing reads this
/// until the log is actually switched on, so a user who never enables it never
/// causes a database file to exist.
@Riverpod(keepAlive: true)
SqliteAuditSink auditSink(Ref ref) {
  final sink = SqliteAuditSink();
  ref.onDispose(() => unawaited(sink.close()));
  return sink;
}

/// One buffered event, kept as the already-serialized line plus the columns
/// retention and export need.
class _Record {
  const _Record(this.t, this.type, this.lvl, this.line);

  final int t;
  final String type;
  final int lvl;
  final String line;
}

/// Writes audit lines into `autoride_audit.db` in batches.
///
/// The contract [write] has to honour is unusual: it is called from inside
/// stream callbacks on the recording path, so it must be synchronous, cheap,
/// and incapable of throwing. Everything expensive — opening the database,
/// committing, purging — happens off that call, on a batch.
class SqliteAuditSink implements AuditSink {
  SqliteAuditSink({
    AuditDatabase? database,
    @visibleForTesting DateTime Function()? now,
    @visibleForTesting
    Timer Function(Duration, void Function())? startPeriodicTimer,
  }) : _database = database ?? AuditDatabase(),
       _now = now ?? DateTime.now,
       _startPeriodicTimer =
           startPeriodicTimer ??
           ((duration, onTick) => Timer.periodic(duration, (_) => onTick()));

  final AuditDatabase _database;
  final DateTime Function() _now;
  final Timer Function(Duration, void Function()) _startPeriodicTimer;

  final List<_Record> _buffer = <_Record>[];

  Timer? _flushTimer;

  /// The flush currently running, if any. Flushes are chained rather than
  /// skipped so that `await flush()` really means "my lines are on disk" — the
  /// export depends on that, and a version that returned early while another
  /// flush was in flight silently shipped a file missing its last batch.
  Future<void>? _flushInFlight;
  bool _closed = false;
  int _writtenSincePurge = 0;
  int _droppedSinceReport = 0;

  /// Events waiting to be written. Exposed for tests and for the settings
  /// screen's counter, which would otherwise under-report by up to a batch.
  @visibleForTesting
  int get bufferedCount => _buffer.length;

  @override
  void write(
    String line, {
    required int t,
    required String type,
    required int lvl,
    required bool critical,
  }) {
    if (_closed) return;

    _buffer.add(_Record(t, type, lvl, line));
    _flushTimer ??= _startPeriodicTimer(
      AppConstants.auditFlushInterval,
      _requestFlush,
    );

    // Backstop: a wedged or full disk must not turn the log into a memory leak
    // inside the app it is observing. Drop the oldest and say so — a declared
    // gap can be read correctly later, a silent one cannot.
    if (_buffer.length > AppConstants.auditMaxBufferedEvents) {
      final excess = _buffer.length - AppConstants.auditMaxBufferedEvents;
      _buffer.removeRange(0, excess);
      _droppedSinceReport += excess;
    }

    if (critical || _buffer.length >= AppConstants.auditFlushBatchSize) {
      _requestFlush();
    }
  }

  /// Start a flush unless one is already running.
  ///
  /// This is the path `write` takes: it must never queue work, or a database
  /// that has stopped responding would accumulate one pending flush per event.
  void _requestFlush() {
    if (_flushInFlight != null) return;
    unawaited(flush());
  }

  @override
  Future<void> flush() {
    late final Future<void> tracked;
    tracked = (_flushInFlight ?? Future<void>.value())
        .then((_) => _flush())
        .whenComplete(() {
          if (identical(_flushInFlight, tracked)) _flushInFlight = null;
        });
    _flushInFlight = tracked;
    return tracked;
  }

  Future<void> _flush() async {
    if (_buffer.isEmpty) return;

    // Report a gap before copying, so the marker is committed with the batch
    // it precedes. Emitted here rather than at the moment of the drop: the
    // buffer is full at that point, and adding a line to a full buffer would
    // trip the backstop again on the very next write.
    if (_droppedSinceReport > 0) {
      final at = _now().millisecondsSinceEpoch;
      _buffer.add(
        _Record(
          at,
          AuditEvent.audit,
          0,
          AuditEvent.encode(at, AuditEvent.audit, <String, Object?>{
            'a': 'overflow',
            'n': _droppedSinceReport,
          }),
        ),
      );
      _droppedSinceReport = 0;
    }

    // Copied, not removed: the lines stay in the buffer until the commit
    // succeeds. That way a failed write costs nothing, and `stats()` — which
    // the settings screen calls at any moment — never under-reports by a batch
    // that happens to be in flight.
    final pending = List<_Record>.of(_buffer);

    try {
      final db = await _database.database;
      final batch = db.batch();
      for (final record in pending) {
        batch.insert('audit_events', <String, Object?>{
          't': record.t,
          'type': record.type,
          'lvl': record.lvl,
          'line': record.line,
        });
      }
      // noResult: the insert ids are of no interest, and asking for them
      // allocates one result map per row.
      await batch.commit(noResult: true);

      // Committed, so they can go. `min` guards the one case where the
      // overflow backstop trimmed the buffer while this batch was in flight —
      // a situation that is already reported as a declared gap.
      _buffer.removeRange(0, math.min(pending.length, _buffer.length));

      _writtenSincePurge += pending.length;
      if (_writtenSincePurge >= AppConstants.auditPurgeWriteInterval) {
        _writtenSincePurge = 0;
        await purge(db);
      }
    } catch (_) {
      // A failed write must not propagate out of a stream callback. The lines
      // are still in the buffer, so a transient failure (a locked database, a
      // momentarily full disk) costs nothing; the overflow backstop is what
      // bounds this if the failure turns out to be permanent.
    }
  }

  /// Apply the three retention bounds, whichever bites first.
  ///
  /// Public so the controller can force one after a level change, and so the
  /// tests can drive it without writing 20 000 rows.
  Future<void> purge(Database db) async {
    final cutoff = _now()
        .subtract(AppConstants.auditRetention)
        .millisecondsSinceEpoch;
    await db.delete(
      'audit_events',
      where: 't < ?',
      whereArgs: <Object?>[cutoff],
    );

    // `id <= MAX(id) - N` is a primary-key range scan. The obvious
    // `NOT IN (SELECT ... ORDER BY t DESC LIMIT N)` would sort the whole table
    // on every purge.
    await db.rawDelete(
      'DELETE FROM audit_events WHERE id <= '
      '(SELECT MAX(id) FROM audit_events) - ?',
      <Object?>[AppConstants.auditMaxEvents],
    );

    // The byte bound is not implied by the row bound: ~130 bytes a line makes
    // 200 000 rows ~26 MB, past the 20 MB the log may occupy.
    var guard = 0;
    while (await _sizeBytes(db) > AppConstants.auditMaxBytes) {
      final deleted = await db.rawDelete(
        'DELETE FROM audit_events WHERE id <= '
        '(SELECT MIN(id) FROM audit_events) + ?',
        <Object?>[AppConstants.auditPurgeChunkSize],
      );
      if (deleted == 0 || ++guard > 100) break;
      // Incremental rather than a full VACUUM: a full one blocks and
      // temporarily doubles the file. "Clear log" deletes the file outright,
      // which makes the question moot in the case that actually matters.
      await db.rawQuery('PRAGMA incremental_vacuum(256)');
    }
  }

  /// Counts, span and size, for the settings screen.
  Future<AuditLogStats> stats(AuditLogLevel level) async {
    if (!_database.isOpen && _buffer.isEmpty) {
      return AuditLogStats.empty(level);
    }

    try {
      final db = await _database.database;
      final rows = await db.rawQuery(
        'SELECT COUNT(*) AS n, MIN(t) AS lo, MAX(t) AS hi FROM audit_events',
      );
      final row = rows.first;
      final count = (row['n'] as int? ?? 0) + _buffer.length;
      final lo = row['lo'] as int?;
      final hi = row['hi'] as int?;

      return AuditLogStats(
        eventCount: count,
        sizeBytes: await _sizeBytes(db),
        oldestAt: lo == null ? null : DateTime.fromMillisecondsSinceEpoch(lo),
        newestAt: hi == null ? null : DateTime.fromMillisecondsSinceEpoch(hi),
        level: level,
      );
    } catch (_) {
      return AuditLogStats.empty(level);
    }
  }

  /// Size of the database, from SQLite's own page accounting.
  ///
  /// Deliberately not `File.length()`: reading the file's attributes would drag
  /// `NSPrivacyAccessedAPICategoryDiskSpace` / `FileTimestamp` reasoning into
  /// `ios/Runner/PrivacyInfo.xcprivacy` for a number the database already knows.
  Future<int> _sizeBytes(Database db) async {
    final pages = await db.rawQuery('PRAGMA page_count');
    final size = await db.rawQuery('PRAGMA page_size');
    final count = pages.first.values.first as int? ?? 0;
    final bytes = size.first.values.first as int? ?? 0;
    return count * bytes;
  }

  /// The open connection, for the exporter.
  ///
  /// Exported through the sink rather than by opening a second connection to
  /// the same file: the log is being written while it is read, and one handle
  /// avoids having to reason about two of them sharing a WAL.
  Future<Database> databaseForExport() => _database.database;

  /// Erase everything, by dropping the database file.
  Future<void> clear() async {
    _buffer.clear();
    _droppedSinceReport = 0;
    _writtenSincePurge = 0;
    await _database.deleteAuditDatabase();
  }

  /// Flush what is buffered and release the connection.
  Future<void> close() async {
    await flush();
    _closed = true;
    _flushTimer?.cancel();
    _flushTimer = null;
    await _database.close();
  }
}
