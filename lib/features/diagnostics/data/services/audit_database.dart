import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import 'package:autoride/core/constants/app_constants.dart';

/// Table holding one audit event per row.
///
/// `line` is the complete NDJSON line, already serialized. `t` and `type` are
/// duplicated out of it so retention and counting never have to parse JSON,
/// and `lvl` so an export can drop verbose rows. The duplication costs ~19 %
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
        line TEXT NOT NULL
      )
    ''';

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
  Database? _database;

  /// Whether the database is currently open.
  bool get isOpen => _database != null;

  /// Open (or return) the audit database.
  Future<Database> get database async {
    return _database ??= await openAuditDatabase();
  }

  /// Path of the audit database file.
  static Future<String> path() async {
    return join(await getDatabasesPath(), AppConstants.auditDatabaseName);
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
  /// Three deliberate choices. `journal_mode` goes through [Database.rawQuery]
  /// rather than `execute` because the pragma returns a row, and `execute` on a
  /// result-producing pragma fails on some platforms. `auto_vacuum` has to be
  /// set before the first table exists or it is inert for the life of the file.
  /// And `synchronous = NORMAL` is what keeps the log from charging an fsync to
  /// every batch — see the note on [AppConstants.auditDatabaseName].
  ///
  /// No `foreign_keys`: there are no relations, and a trip id inside a JSON
  /// line is intentionally unconstrained. A journal has to outlive the trip it
  /// describes.
  Future<void> onConfigure(Database db) async {
    await db.rawQuery('PRAGMA journal_mode = WAL');
    await db.execute('PRAGMA synchronous = NORMAL');
    await db.execute('PRAGMA auto_vacuum = INCREMENTAL');
  }

  /// Create the schema. Public so tests run the production DDL (L-014).
  Future<void> onCreate(Database db, int version) async {
    await db.execute(_createAuditEventsTable);
    await db.execute(_createAuditTimeIndex);
  }

  /// Migrate the schema. Public so tests drive the production path (L-014).
  ///
  /// Nothing to do at v1. Kept, with the same cascading-`if` shape as
  /// [DatabaseService.onUpgrade], so the first real migration has an obvious
  /// place to go.
  Future<void> onUpgrade(Database db, int oldVersion, int newVersion) async {}

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
