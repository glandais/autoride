import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:autoride/core/constants/app_constants.dart';
import 'package:autoride/features/diagnostics/data/services/audit_database.dart';
import 'package:autoride/features/trip_detection/data/services/database_service.dart';

/// Opens an in-memory database using the **production** schema.
///
/// This is a thin wrapper around [DatabaseService]'s own `onCreate` /
/// `onUpgrade` / `onConfigure` callbacks — it deliberately declares no DDL of
/// its own. Duplicating the schema here (as this helper used to) made prod/test
/// drift invisible: the DDL real users get would never have executed in a test
/// (L-014).
///
/// In-memory is used so tests can run in parallel without file conflicts.
Future<Database> createTestDatabase() async {
  final service = DatabaseService();

  return await databaseFactory.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(
      version: AppConstants.databaseVersion,
      onCreate: service.onCreate,
      onUpgrade: service.onUpgrade,
      onConfigure: service.onConfigure,
    ),
  );
}

/// Opens an in-memory **audit** database using the production schema.
///
/// Same reasoning as [createTestDatabase]: the DDL and pragmas come from
/// [AuditDatabase] itself, never re-declared here (L-014).
///
/// One caveat worth knowing when reading these tests: WAL and `auto_vacuum`
/// are both inert on an in-memory database, so `onConfigure` running
/// successfully is what can be asserted here, not the resulting journal mode
/// or the byte bound. Those need a real file — see the `pragmas on a real
/// file` group in `audit_database_test.dart` and the byte-bound test in
/// `sqlite_audit_sink_test.dart`, which is how the pragma-order defect (R-02)
/// went unnoticed.
Future<Database> createTestAuditDatabase() async {
  final auditDatabase = AuditDatabase();

  return await databaseFactory.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(
      version: AppConstants.auditDatabaseVersion,
      onCreate: auditDatabase.onCreate,
      onUpgrade: auditDatabase.onUpgrade,
      onConfigure: auditDatabase.onConfigure,
    ),
  );
}
