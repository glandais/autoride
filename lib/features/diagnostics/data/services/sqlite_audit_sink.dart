import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:sqflite/sqflite.dart';

import 'package:autoride/core/audit/audit_event.dart';
import 'package:autoride/core/audit/audit_level.dart';
import 'package:autoride/core/audit/audit_sink.dart';
import 'package:autoride/core/constants/app_constants.dart';
import 'package:autoride/features/diagnostics/data/services/audit_database.dart';
import 'package:autoride/features/diagnostics/domain/models/audit_log_stats.dart';
import 'package:autoride/features/diagnostics/domain/models/capture_session.dart';

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
///
/// [seq] is a per-sink monotonic id. It is what lets a finished flush remove
/// exactly the records it committed: removing "the first N" instead would
/// discard newer, never-committed lines whenever the overflow backstop trimmed
/// the buffer while the batch was in flight.
class _Record {
  const _Record(this.seq, this.t, this.type, this.lvl, this.line, this.sess);

  final int seq;
  final int t;
  final String type;
  final int lvl;
  final String line;

  /// The capture session this row belongs to; null on every journal row.
  final int? sess;
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
    @visibleForTesting int? maxBytes,
    @visibleForTesting int? maxEvents,
    @visibleForTesting Duration? retention,
    @visibleForTesting int? purgeChunkSize,
    @visibleForTesting int? captureMaxBytes,
    @visibleForTesting Duration? captureRetention,
  }) : _database = database ?? AuditDatabase(),
       _now = now ?? DateTime.now,
       _maxBytes = maxBytes ?? AppConstants.auditMaxBytes,
       _maxEvents = maxEvents ?? AppConstants.auditMaxEvents,
       _retention = retention ?? AppConstants.auditRetention,
       _captureMaxBytes = captureMaxBytes ?? AppConstants.captureMaxBytes,
       _captureRetention = captureRetention ?? AppConstants.captureRetention,
       _purgeChunkSize = purgeChunkSize ?? AppConstants.auditPurgeChunkSize,
       _startPeriodicTimer =
           startPeriodicTimer ??
           ((duration, onTick) => Timer.periodic(duration, (_) => onTick()));

  final AuditDatabase _database;
  final DateTime Function() _now;
  final Timer Function(Duration, void Function()) _startPeriodicTimer;

  /// The three retention bounds. Injectable only so a test can reach the byte
  /// bound without writing 20 MB; production always gets the [AppConstants]
  /// values.
  final int _maxBytes;
  final int _maxEvents;
  final Duration _retention;
  final int _purgeChunkSize;

  /// The capture bounds (T034), deliberately separate from the journal's: a
  /// corpus and a journal have opposite retention semantics, and one shared
  /// budget would let an hour of capture purge a day of journal.
  final int _captureMaxBytes;
  final Duration _captureRetention;

  /// The capture session currently recording, if any.
  ///
  /// Set by `AuditLogController` around a session. Capture retention will not
  /// delete a session that is still being written unless it is the only thing
  /// left to delete — the alternative is an unbounded file.
  int? activeCaptureSession;

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
  int _nextSeq = 0;

  /// Bumped by [clear]. A flush that started before the erase must not put the
  /// erased batch back into the fresh database, so it compares this against the
  /// value it captured, both after the database resolves and after the commit.
  int _generation = 0;

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
    int? session,
  }) {
    if (_closed) return;

    _buffer.add(_Record(_nextSeq++, t, type, lvl, line, session));
    // Recreated lazily: the timer is cancelled whenever the buffer drains, so
    // a log that has been turned off does not keep a 5 s wakeup alive for the
    // rest of the process in the app whose whole thesis is battery.
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

    if (critical) {
      // Unconditionally chained, not `_requestFlush()`: a critical event that
      // arrives while a batch is committing is not in that batch's `pending`
      // copy, so skipping here would leave it waiting on the 5 s timer — the
      // exact window `critical` exists to close.
      unawaited(flush());
    } else if (_buffer.length >= AppConstants.auditFlushBatchSize) {
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
    if (_buffer.isEmpty) {
      _stopTimerIfIdle();
      return;
    }

    final generation = _generation;

    // Report a gap before copying, so the marker is committed with the batch
    // it precedes. Emitted here rather than at the moment of the drop: the
    // buffer is full at that point, and adding a line to a full buffer would
    // trip the backstop again on the very next write.
    if (_droppedSinceReport > 0) {
      final at = _now().millisecondsSinceEpoch;
      _buffer.add(
        _Record(
          _nextSeq++,
          at,
          AuditEvent.audit,
          0,
          AuditEvent.encode(at, AuditEvent.audit, <String, Object?>{
            'a': 'overflow',
            'n': _droppedSinceReport,
          }),
          null,
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
      // `clear()` ran while the file was being opened: the batch belongs to a
      // journal the user just erased.
      if (generation != _generation) return;

      final batch = db.batch();
      for (final record in pending) {
        batch.insert('audit_events', <String, Object?>{
          't': record.t,
          'type': record.type,
          'lvl': record.lvl,
          'line': record.line,
          'sess': record.sess,
        });
      }
      // noResult: the insert ids are of no interest, and asking for them
      // allocates one result map per row.
      await batch.commit(noResult: true);

      // Erased mid-commit: the buffer is already empty and the rows went with
      // the file, so there is nothing to remove and nothing to count.
      if (generation != _generation) return;

      // Committed, so they can go — by sequence, not by count. Anything the
      // overflow backstop trimmed while the batch was in flight is already
      // gone from the buffer and already counted into `_droppedSinceReport`;
      // removing "the first `pending.length`" would additionally throw away
      // newer lines that were never written.
      final lastSeq = pending.last.seq;
      final firstKept = _buffer.indexWhere((record) => record.seq > lastSeq);
      _buffer.removeRange(0, firstKept < 0 ? _buffer.length : firstKept);

      _stopTimerIfIdle();

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

  /// Drop the periodic flush timer once there is nothing left to flush.
  ///
  /// [write] recreates it on the next line, so this costs one `Timer.periodic`
  /// per idle→busy transition and saves a wakeup every 5 s for the whole time
  /// the log is off.
  void _stopTimerIfIdle() {
    if (_buffer.isNotEmpty) return;
    _flushTimer?.cancel();
    _flushTimer = null;
  }

  /// Apply both retention policies: the journal's three bounds, then the
  /// capture budget.
  ///
  /// Public so the controller can force one after a level change, and so the
  /// tests can drive it without writing 20 000 rows.
  ///
  /// The two classes of row never touch each other. A journal bound may only
  /// delete `lvl < 2`, and the capture budget only `lvl = 2`: sharing them
  /// would mean one hour of capture (~8 MB) erasing a day of journal, or a
  /// week-old journal line deleting the middle of a labelled corpus session.
  ///
  /// Every bound that actually deletes something leaves an `aud a:purge` line
  /// behind it. A purge used to be silent — it is retention, not an incident,
  /// which was the L-077 reasoning — and the 2026-09-02 Pixel file is what
  /// that costs: the byte bound erased the launch header, the `sess start`,
  /// the `fgs` and the `perm` lines, and nothing in the file said so, leaving
  /// a reader to conclude the session had never started (L-085). The marker is
  /// written *after* the deletion, so it survives its own purge.
  Future<void> purge(Database db) async {
    await _purgeJournal(db);
    await _purgeCapture(db);
  }

  Future<void> _purgeJournal(Database db) async {
    final cutoff = _now().subtract(_retention).millisecondsSinceEpoch;
    final byAge = await db.delete(
      'audit_events',
      where: 't < ? AND lvl < 2',
      whereArgs: <Object?>[cutoff],
    );
    await _reportPurge(db, byAge, 'age');

    // The id below the newest `_maxEvents` journal rows, found through the
    // primary key index. The obvious `NOT IN (SELECT ... ORDER BY t DESC LIMIT
    // N)` would sort the whole table on every purge; this walks the index
    // backwards and stops. `lvl < 2` is what keeps a capture session — which
    // can be 100 000 rows on its own — from pushing the journal out of its own
    // bound.
    final byRows = await db.rawDelete(
      'DELETE FROM audit_events WHERE lvl < 2 AND id <= ('
      'SELECT id FROM audit_events WHERE lvl < 2 '
      'ORDER BY id DESC LIMIT 1 OFFSET ?)',
      <Object?>[_maxEvents],
    );
    await _reportPurge(db, byRows, 'rows');

    // The byte bound is not implied by the row bound: ~130 bytes a line makes
    // 200 000 rows ~26 MB, past the 20 MB the log may occupy.
    //
    // Measured as the sum of the stored lines rather than as the file's page
    // count, which is what this used to do. Since T034 the file also holds
    // capture rows, and a page count cannot be attributed to either class — a
    // 200 MB corpus would have made the journal delete itself line by line for
    // ever without the file ever shrinking below 20 MB.
    var guard = 0;
    var byBytes = 0;
    while (await _classBytes(db, capture: false) > _maxBytes) {
      final deleted = await db.rawDelete(
        'DELETE FROM audit_events WHERE lvl < 2 AND id <= ('
        'SELECT MIN(id) FROM audit_events WHERE lvl < 2) + ?',
        <Object?>[_purgeChunkSize],
      );
      if (deleted == 0 || ++guard > 100) break;
      byBytes += deleted;
      // Incremental rather than a full VACUUM: a full one blocks and
      // temporarily doubles the file. "Clear log" deletes the file outright,
      // which makes the question moot in the case that actually matters.
      await db.rawQuery('PRAGMA incremental_vacuum(256)');
    }
    await _reportPurge(db, byBytes, 'bytes');
  }

  /// Capture retention (T034): by *labelled session*, oldest first, never mid
  /// session.
  ///
  /// A corpus is not a rolling journal. Half a session is not half as useful:
  /// its windows are labelled by a `lbl` line that the deletion may have taken
  /// with it, so what is left is unlabelled data that still costs 8 MB an hour.
  /// Sessions therefore go whole, and in an order that reflects what they are
  /// still worth — already exported first, then the oldest.
  ///
  /// The one exception is a byte budget that can only be satisfied by touching
  /// the session being recorded right now. Truncating its oldest rows is the
  /// least bad answer available: refusing to delete would let the file grow
  /// without bound on the device of a user who left capture on for a week.
  Future<void> _purgeCapture(Database db) async {
    final cutoff = _now().subtract(_captureRetention).millisecondsSinceEpoch;
    final expired = await db.query(
      'capture_sessions',
      columns: <String>['id'],
      where: 'ended_at IS NOT NULL AND ended_at < ?',
      whereArgs: <Object?>[cutoff],
    );
    var byAge = 0;
    for (final row in expired) {
      byAge += await _deleteCaptureSession(db, row['id']! as int);
    }
    await _reportPurge(db, byAge, 'captureAge');

    var guard = 0;
    var byBytes = 0;
    while (await _classBytes(db, capture: true) > _captureMaxBytes) {
      final deleted = await _deleteOldestCaptureSession(db);
      if (deleted == 0 || ++guard > 100) break;
      byBytes += deleted;
      await db.rawQuery('PRAGMA incremental_vacuum(256)');
    }
    // A distinct `why` from the journal's `bytes`: losing a corpus session the
    // user had not exported yet is a different event from a journal rolling
    // over, and the two must not read alike in the file (L-085).
    await _reportPurge(db, byBytes, 'capture');
  }

  /// Delete the least valuable capture session, and return the rows it cost.
  ///
  /// Exported sessions first (oldest of them), then unexported ones (oldest
  /// first). The session currently recording is the last resort, and is
  /// truncated rather than deleted — ending it here would strand a `lbl start`
  /// with no `lbl stop`.
  Future<int> _deleteOldestCaptureSession(Database db) async {
    final active = activeCaptureSession;
    final candidates = await db.query(
      'capture_sessions',
      columns: <String>['id'],
      where: active == null ? null : 'id != ?',
      whereArgs: active == null ? null : <Object?>[active],
      orderBy: 'exported_at IS NULL, started_at',
      limit: 1,
    );

    if (candidates.isNotEmpty) {
      return _deleteCaptureSession(db, candidates.first['id']! as int);
    }
    if (active == null) return 0;

    return db.rawDelete(
      'DELETE FROM audit_events WHERE lvl = 2 AND sess = ? AND id <= ('
      'SELECT MIN(id) FROM audit_events WHERE lvl = 2 AND sess = ?) + ?',
      <Object?>[active, active, _purgeChunkSize],
    );
  }

  /// Remove a session's rows and the session row itself, in that order: a
  /// session row without its data is a promise of a corpus that is not there.
  Future<int> _deleteCaptureSession(Database db, int id) async {
    final rows = await db.delete(
      'audit_events',
      where: 'lvl = 2 AND sess = ?',
      whereArgs: <Object?>[id],
    );
    await db.delete(
      'capture_sessions',
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
    return rows;
  }

  /// Bytes of stored NDJSON in one class of row.
  ///
  /// This replaced a `PRAGMA page_count × page_size` measurement of the whole
  /// file, which stopped being attributable to a class of row the moment
  /// capture started sharing the database. It is still deliberately not
  /// `File.length()`: reading the file's attributes would drag
  /// `NSPrivacyAccessedAPICategoryDiskSpace` / `FileTimestamp` reasoning into
  /// `ios/Runner/PrivacyInfo.xcprivacy` for a number the database already
  /// knows. The trade is that it undercounts the file by SQLite's own page and
  /// index overhead, so both budgets are budgets of *content*.
  ///
  /// `LENGTH` on a `TEXT` column is characters, not bytes; the lines are
  /// overwhelmingly ASCII, so the two agree to within a rounding error, and
  /// the alternative (`LENGTH(CAST(line AS BLOB))`) reads every page twice for
  /// a bound that is a budget rather than a hard limit.
  Future<int> _classBytes(Database db, {required bool capture}) async {
    final rows = await db.rawQuery(
      'SELECT SUM(LENGTH(line)) AS n FROM audit_events '
      'WHERE lvl ${capture ? '=' : '<'} 2',
    );
    return (rows.first['n'] as int?) ?? 0;
  }

  /// Declare a retention deletion, written straight to the database rather
  /// than through [write].
  ///
  /// Buffering it would put the marker at the mercy of the next flush, and the
  /// byte bound bites when the log is at its largest — under exactly the memory
  /// pressure that gets an Android process killed. A kill in that window would
  /// leave the file truncated and unmarked all over again, which is the whole
  /// defect (L-085). Inserting here makes the marker as durable as the deletion
  /// it describes, and it also survives the final purge of [close], whose
  /// buffer is never flushed again.
  Future<void> _reportPurge(Database db, int rows, String why) async {
    if (rows <= 0) return;
    final at = _now().millisecondsSinceEpoch;
    try {
      await db.insert('audit_events', <String, Object?>{
        't': at,
        'type': AuditEvent.audit,
        'lvl': 0,
        'line': AuditEvent.encode(at, AuditEvent.audit, <String, Object?>{
          'a': 'purge',
          'n': rows,
          'why': why,
        }),
      });
    } catch (_) {
      // The marker is worth less than the purge that produced it: a failed
      // insert must not propagate out of a flush.
    }
  }

  /// Counts, span and size of the **journal**, for the settings screen.
  ///
  /// Capture rows are excluded on both counts. They are budgeted separately
  /// and are two orders of magnitude more numerous, so folding them in would
  /// turn a row the user reads as "how much diagnostics have I recorded" into
  /// a number dominated by something else entirely.
  Future<AuditLogStats> stats(AuditLogLevel level) async {
    if (!_database.isOpen && _buffer.isEmpty) {
      return AuditLogStats.empty(level);
    }

    try {
      final db = await _database.database;
      final rows = await db.rawQuery(
        'SELECT COUNT(*) AS n, MIN(t) AS lo, MAX(t) AS hi FROM audit_events '
        'WHERE lvl < 2',
      );
      final row = rows.first;
      final buffered = _buffer.where((record) => record.lvl < 2).length;
      final count = (row['n'] as int? ?? 0) + buffered;
      final lo = row['lo'] as int?;
      final hi = row['hi'] as int?;

      return AuditLogStats(
        eventCount: count,
        sizeBytes: await _classBytes(db, capture: false),
        oldestAt: lo == null ? null : DateTime.fromMillisecondsSinceEpoch(lo),
        newestAt: hi == null ? null : DateTime.fromMillisecondsSinceEpoch(hi),
        level: level,
      );
    } catch (_) {
      return AuditLogStats.empty(level);
    }
  }

  /// Counts, span and size of the captured corpus (T034).
  Future<CaptureStats> captureStats() async {
    if (!_database.isOpen && _buffer.isEmpty) return CaptureStats.empty();

    try {
      final db = await _database.database;
      final rows = await db.rawQuery(
        'SELECT COUNT(*) AS n, MIN(t) AS lo, MAX(t) AS hi FROM audit_events '
        'WHERE lvl = 2',
      );
      final row = rows.first;
      final sessions = await db.rawQuery(
        'SELECT COUNT(*) AS n, SUM(exported_at IS NULL) AS pending '
        'FROM capture_sessions',
      );
      final buffered = _buffer.where((record) => record.lvl == 2).length;
      final lo = row['lo'] as int?;
      final hi = row['hi'] as int?;

      return CaptureStats(
        sessionCount: sessions.first['n'] as int? ?? 0,
        rowCount: (row['n'] as int? ?? 0) + buffered,
        sizeBytes: await _classBytes(db, capture: true),
        unexportedSessionCount: sessions.first['pending'] as int? ?? 0,
        oldestAt: lo == null ? null : DateTime.fromMillisecondsSinceEpoch(lo),
        newestAt: hi == null ? null : DateTime.fromMillisecondsSinceEpoch(hi),
      );
    } catch (_) {
      return CaptureStats.empty();
    }
  }

  /// Open a capture session.
  ///
  /// [id] is the session's start in epoch ms and is chosen by the caller, which
  /// is what lets [write] stamp rows with it synchronously. `INSERT OR REPLACE`
  /// rather than a plain insert so a restart that reuses an id — two sessions
  /// begun inside the same millisecond, or a hot restart in development —
  /// cannot fail the whole flush.
  Future<void> beginCaptureSession({
    required int id,
    required String activity,
  }) async {
    activeCaptureSession = id;
    try {
      final db = await _database.database;
      await db.insert('capture_sessions', <String, Object?>{
        'id': id,
        'activity': activity,
        'started_at': id,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    } catch (_) {
      // The session row is bookkeeping; the `lbl` line in the log is the
      // record of ground truth, and it has already been written.
    }
  }

  /// Close a capture session, so retention may consider it.
  Future<void> endCaptureSession(int id) async {
    if (activeCaptureSession == id) activeCaptureSession = null;
    try {
      final db = await _database.database;
      await db.update(
        'capture_sessions',
        <String, Object?>{'ended_at': _now().millisecondsSinceEpoch},
        where: 'id = ? AND ended_at IS NULL',
        whereArgs: <Object?>[id],
      );
    } catch (_) {
      // See [beginCaptureSession].
    }
  }

  /// Every capture session, newest first.
  Future<List<CaptureSession>> captureSessions() async {
    if (!_database.isOpen) return const <CaptureSession>[];
    try {
      final db = await _database.database;
      final rows = await db.query(
        'capture_sessions',
        orderBy: 'started_at DESC',
      );
      return rows.map(_sessionFromRow).toList(growable: false);
    } catch (_) {
      return const <CaptureSession>[];
    }
  }

  /// Mark every finished session as exported, so retention may drop them
  /// before it touches one the user has not saved anywhere yet.
  ///
  /// Finished only: a session still recording has not been exported in full,
  /// whatever the file that was just written contains.
  Future<void> markCaptureSessionsExported() async {
    try {
      final db = await _database.database;
      await db.update('capture_sessions', <String, Object?>{
        'exported_at': _now().millisecondsSinceEpoch,
      }, where: 'ended_at IS NOT NULL');
    } catch (_) {
      // Worst case the session is deleted later than it could have been.
    }
  }

  /// Delete every captured row and session, leaving the journal intact.
  ///
  /// Deliberately not `clear()`: the corpus is the expensive thing on the
  /// device, and a user who wants their 200 MB back should not have to throw
  /// away the diagnostic journal to get it.
  Future<int> clearCapture() async {
    _buffer.removeWhere((record) => record.lvl == 2);
    if (!_database.isOpen) return 0;
    try {
      final db = await _database.database;
      final rows = await db.delete('audit_events', where: 'lvl = 2');
      await db.delete('capture_sessions');
      await db.rawQuery('PRAGMA incremental_vacuum(4096)');
      return rows;
    } catch (_) {
      return 0;
    }
  }

  static CaptureSession _sessionFromRow(Map<String, Object?> row) {
    final ended = row['ended_at'] as int?;
    final exported = row['exported_at'] as int?;
    return CaptureSession(
      id: row['id']! as int,
      activity: CaptureActivity.values.firstWhere(
        (value) => value.name == row['activity'],
        orElse: () => CaptureActivity.other,
      ),
      startedAt: DateTime.fromMillisecondsSinceEpoch(row['started_at']! as int),
      endedAt: ended == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(ended),
      exportedAt: exported == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(exported),
    );
  }

  /// The open connection, for the exporter.
  ///
  /// Exported through the sink rather than by opening a second connection to
  /// the same file: the log is being written while it is read, and one handle
  /// avoids having to reason about two of them sharing a WAL.
  Future<Database> databaseForExport() => _database.database;

  /// Erase everything, by dropping the database file.
  ///
  /// The generation bump comes first and is what makes this safe against a
  /// flush already in flight: that flush will find the counter changed and
  /// return without committing into — or removing from — a journal the user
  /// asked to be gone. Without it, a "Clear log" during a commit reopened a
  /// fresh database and re-inserted the batch it had just erased.
  Future<void> clear() async {
    _generation++;
    _buffer.clear();
    // The capture session, if one is recording, loses its rows with the file.
    // Leaving the id set would have retention looking for a session that no
    // longer exists, and the next `lbl stop` updating nothing.
    activeCaptureSession = null;
    _droppedSinceReport = 0;
    _writtenSincePurge = 0;
    _flushTimer?.cancel();
    _flushTimer = null;
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
