import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import 'package:autoride/core/constants/app_constants.dart';

/// Table holding one audit event per row.
///
/// `line` is the complete NDJSON line, already serialized. `t` and `type` are
/// duplicated out of it so retention and counting never have to parse JSON,
/// `lvl` so an export can drop verbose rows and retention can budget the
/// journal separately from the T034 training capture, and `sess` so a capture
/// session can be deleted or exported whole. The duplication costs ~19 %
/// before compression and ~2 % after — gzip barely notices a repeated key —
/// and it buys two things worth far more: exporting is a concatenation with no
/// re-encoding of 200 000 objects, and the field schema can change without a
/// migration, because the column is opaque text. A log written by an older
/// build stays readable next to a newer one in the same file.
const String _createAuditEventsTable = '''
      CREATE TABLE audit_events (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        t INTEGER NOT NULL,
        type TEXT NOT NULL,
        lvl INTEGER NOT NULL,
        line TEXT NOT NULL,
        sess INTEGER
      )
    ''';

/// One training-capture session (T034): a labelled recording, from the moment
/// the user picked an activity to the moment they stopped.
///
/// `id` is the session's start in epoch ms, allocated by the caller rather than
/// by the database: [AuditSink.write] is synchronous and on the recording path,
/// so it cannot await an AUTOINCREMENT id to stamp its rows with.
///
/// `exported_at` is what makes retention bearable. A session already exported
/// has served its purpose and is deleted first; one that has not is deleted
/// only when the byte budget leaves no choice, and says so in an `aud` line.
const String _createCaptureSessionsTable = '''
      CREATE TABLE capture_sessions (
        id INTEGER PRIMARY KEY,
        activity TEXT NOT NULL,
        started_at INTEGER NOT NULL,
        ended_at INTEGER,
        exported_at INTEGER
      )
    ''';

/// Index on `sess`, for the capture purge and the capture export.
///
/// Partial, on `lvl = 2` alone: every journal row has a null `sess`, and
/// indexing 200 000 nulls would cost write throughput on the hot path for
/// rows the index can never be used to find.
const String _createAuditSessionIndex =
    'CREATE INDEX idx_audit_sess ON audit_events(sess) WHERE lvl = 2';

/// Index on `t`, kept despite `id` being almost the same order.
///
/// Almost, not quite: the wall clock can go backwards (an NTP correction, a
/// user changing the date), and retention by date has to stay correct when it
/// does. There is deliberately no index on `type` — ~30 distinct values, no
/// query that needs it, and it would cost roughly 15 % of the write throughput
/// on the one path that must stay cheap.
const String _createAuditTimeIndex =
    'CREATE INDEX idx_audit_t ON audit_events(t)';

/// Opens and owns `autoride_audit.db`.
///
/// Separate from [DatabaseService] by design — see the comment on
/// [AppConstants.auditDatabaseName]. Not a provider: the sink opens it lazily
/// on the first event, so a user who never turns the log on never pays for a
/// database file at all.
class AuditDatabase {
  /// [directory] exists only so a test can put the file somewhere it owns:
  /// the byte bound and `auto_vacuum` are properties of a *file* database, and
  /// the in-memory seam cannot see either (WAL and auto_vacuum are both inert
  /// on `:memory:`). Production always uses `getDatabasesPath()`.
  AuditDatabase({@visibleForTesting String? directory})
    : _directoryOverride = directory;

  final String? _directoryOverride;

  Database? _database;

  /// Whether the database is currently open.
  bool get isOpen => _database != null;

  /// Open (or return) the audit database.
  Future<Database> get database async {
    return _database ??= await openAuditDatabase();
  }

  /// Path of the audit database file.
  Future<String> path() async {
    return join(
      _directoryOverride ?? await getDatabasesPath(),
      AppConstants.auditDatabaseName,
    );
  }

  /// Open the database with the production schema and pragmas.
  Future<Database> openAuditDatabase() async {
    return openDatabase(
      await path(),
      version: AppConstants.auditDatabaseVersion,
      onCreate: onCreate,
      onUpgrade: onUpgrade,
      onConfigure: onConfigure,
    );
  }

  /// Configure the connection.
  ///
  /// Public so tests drive the *production* configuration (L-014).
  ///
  /// Three deliberate choices. `auto_vacuum` is issued **first**, before
  /// anything writes a page — setting it after `journal_mode = WAL` leaves it
  /// at 0 permanently (see the inline comment). `journal_mode` goes through
  /// [Database.rawQuery] rather than `execute` because the pragma returns a
  /// row, and `execute` on a result-producing pragma fails on some platforms.
  /// And `synchronous = NORMAL` is what keeps the log from charging an fsync to
  /// every batch — see the note on [AppConstants.auditDatabaseName].
  ///
  /// No `foreign_keys`: there are no relations, and a trip id inside a JSON
  /// line is intentionally unconstrained. A journal has to outlive the trip it
  /// describes.
  Future<void> onConfigure(Database db) async {
    // Order matters: `auto_vacuum` has to be set before the database gets its
    // first page, and enabling WAL writes one. WAL first leaves `auto_vacuum`
    // at 0 for the life of the file, which makes
    // `PRAGMA incremental_vacuum` a no-op and the sink's byte bound
    // unsatisfiable — it would delete rows forever without the file shrinking.
    await db.execute('PRAGMA auto_vacuum = INCREMENTAL');
    await db.rawQuery('PRAGMA journal_mode = WAL');
    await db.execute('PRAGMA synchronous = NORMAL');
  }

  /// Create the schema. Public so tests run the production DDL (L-014).
  Future<void> onCreate(Database db, int version) async {
    await db.execute(_createAuditEventsTable);
    await db.execute(_createAuditTimeIndex);
    await db.execute(_createCaptureSessionsTable);
    await db.execute(_createAuditSessionIndex);
  }

  /// Migrate the schema. Public so tests drive the production path (L-014).
  ///
  /// Same cascading-`if` shape as [DatabaseService.onUpgrade].
  ///
  /// v2 (T034): `audit_events.sess` and the `capture_sessions` table. The
  /// journal rows an older build wrote keep a null `sess`, which is exactly
  /// what they are: not capture. Nothing is rewritten and nothing is dropped —
  /// a migration that erased a journal the user was about to export would be a
  /// worse bug than the one it fixes.
  Future<void> onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE audit_events ADD COLUMN sess INTEGER');
      await db.execute(_createCaptureSessionsTable);
      await db.execute(_createAuditSessionIndex);
    }
  }

  /// Close the connection if one is open.
  Future<void> close() async {
    final db = _database;
    _database = null;
    await db?.close();
  }

  /// Close and delete the database file.
  ///
  /// This is what "Clear log" does: the journal is disposable, so dropping the
  /// whole file is both the simplest and the most complete way to erase it —
  /// no `VACUUM`, no rows left in a freelist.
  Future<void> deleteAuditDatabase() async {
    await close();
    await databaseFactory.deleteDatabase(await path());
  }
}
