import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:autoride/core/constants/app_constants.dart';

part 'database_service.g.dart';

/// Database service provider
///
/// Single owner of the app-wide database connection. Kept alive for the app
/// lifetime (opening SQLite is expensive and the handle is shared) and closed
/// when the provider is disposed. Going through [DatabaseService.database]
/// populates the singleton cache so [DatabaseService.close] actually has a
/// handle to close.
@Riverpod(keepAlive: true)
Future<Database> database(Ref ref) async {
  final dbService = DatabaseService();
  final db = await dbService.database;
  ref.onDispose(dbService.close);
  return db;
}

/// Status persisted for every trip row that predates the status column, and
/// the column default. Spelled out rather than referencing `TripStatus` so the
/// DDL stays a literal string (the shipped schema must not move when the enum
/// is reordered); `database_service_test` pins the two together.
const String _defaultTripStatus = 'completed';

/// Index backing the `status = 'completed'` filter every history/stats query
/// carries since L-068.
const String _createTripStatusIndex =
    'CREATE INDEX idx_trip_status ON trips(status)';

/// v1 -> v2 migration step. SQLite backfills the existing rows with the
/// column default, which is exactly the intended semantics: everything written
/// before the column existed is a finished trip.
const String _addTripStatusColumn =
    "ALTER TABLE trips ADD COLUMN status TEXT NOT NULL "
    "DEFAULT '$_defaultTripStatus'";

/// v2 -> v3 migration step (L-073). Rows written before the column existed
/// have no record of their stops, and the default says so honestly: 0 s of
/// pause. Their `duration` was already the moving time, so nothing about how
/// they read changes.
const String _addTripPauseDurationColumn =
    'ALTER TABLE trips ADD COLUMN pause_duration INTEGER NOT NULL DEFAULT 0';

/// Database service for AutoRide
/// Handles database initialization, schema creation, and migrations
class DatabaseService {
  static Database? _database;

  /// Get database instance (singleton pattern)
  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await initDatabase();
    return _database!;
  }

  /// Initialize database
  /// Creates database file and schema on first run
  Future<Database> initDatabase() async {
    try {
      final databasePath = await getDatabasesPath();
      final path = join(databasePath, AppConstants.databaseName);

      return await openDatabase(
        path,
        version: AppConstants.databaseVersion,
        onCreate: onCreate,
        onUpgrade: onUpgrade,
        onConfigure: onConfigure,
      );
    } catch (e, stackTrace) {
      // ignore: avoid_print
      print('Failed to initialize database: $e');
      // ignore: avoid_print
      print('Stack trace: $stackTrace');
      rethrow;
    }
  }

  /// Configure database settings
  /// Enables foreign key constraints
  ///
  /// Public so tests can open the *production* configuration against an
  /// in-memory database instead of re-declaring it (L-014).
  Future<void> onConfigure(Database db) async {
    await db.execute('PRAGMA foreign_keys = ON');
  }

  /// Create database schema
  /// Called when database is created for the first time
  ///
  /// Public so tests can execute the *production* DDL against an in-memory
  /// database instead of re-declaring it (L-014).
  Future<void> onCreate(Database db, int version) async {
    // Create trips table
    await db.execute('''
      CREATE TABLE trips (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        start_time INTEGER NOT NULL,
        end_time INTEGER NOT NULL,
        distance REAL NOT NULL,
        duration INTEGER NOT NULL,
        avg_speed REAL,
        max_speed REAL,
        detected_activity TEXT NOT NULL,
        confidence_score REAL NOT NULL,
        user_confirmed INTEGER DEFAULT 0,
        status TEXT NOT NULL DEFAULT '$_defaultTripStatus',
        pause_duration INTEGER NOT NULL DEFAULT 0
      )
    ''');

    // Create route_points table
    await db.execute('''
      CREATE TABLE route_points (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        trip_id INTEGER NOT NULL,
        latitude REAL NOT NULL,
        longitude REAL NOT NULL,
        altitude REAL,
        timestamp INTEGER NOT NULL,
        accuracy REAL,
        speed REAL,
        FOREIGN KEY (trip_id) REFERENCES trips(id) ON DELETE CASCADE
      )
    ''');

    // Create indexes for performance
    await db.execute('''
      CREATE INDEX idx_trip_start_time ON trips(start_time)
    ''');

    await db.execute('''
      CREATE INDEX idx_trip_end_time ON trips(end_time)
    ''');

    await db.execute('''
      CREATE INDEX idx_route_points_trip_id ON route_points(trip_id)
    ''');

    await db.execute('''
      CREATE INDEX idx_route_points_timestamp ON route_points(timestamp)
    ''');

    await db.execute(_createTripStatusIndex);
  }

  /// Upgrade database schema
  /// Called when database version changes
  ///
  /// Public so tests can drive the *production* migration path (L-014).
  Future<void> onUpgrade(Database db, int oldVersion, int newVersion) async {
    // v1 -> v2: trip lifecycle status (L-068).
    //
    // Every pre-existing row is a trip the user already sees in history, so
    // the default backfills them as `completed`. The column is NOT NULL with
    // that same default, which is also what SQLite writes into the existing
    // rows during the ALTER.
    if (oldVersion < 2) {
      await db.execute(_addTripStatusColumn);
      await db.execute(_createTripStatusIndex);
    }

    // v2 -> v3: time spent stopped (L-073).
    //
    // `duration` has always been the *moving* time (the recorder subtracts the
    // pauses before writing it), but the amount subtracted lived only in
    // memory, so "45 min ride, 8 min of stops" could never be shown after the
    // fact. This column stores that subtrahend. Existing rows default to 0,
    // which reads as "no stops recorded" rather than as a wrong number.
    if (oldVersion < 3) {
      await db.execute(_addTripPauseDurationColumn);
    }
  }

  /// Close database connection
  Future<void> close() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
    }
  }

  /// Delete database (for testing or reset)
  Future<void> deleteDatabase() async {
    final databasePath = await getDatabasesPath();
    final path = join(databasePath, AppConstants.databaseName);
    await databaseFactory.deleteDatabase(path);
    _database = null;
  }
}
