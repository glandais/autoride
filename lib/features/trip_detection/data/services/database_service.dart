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
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
        onConfigure: _onConfigure,
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
  Future<void> _onConfigure(Database db) async {
    await db.execute('PRAGMA foreign_keys = ON');
  }

  /// Create database schema
  /// Called when database is created for the first time
  Future<void> _onCreate(Database db, int version) async {
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
        user_confirmed INTEGER DEFAULT 0
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
  }

  /// Upgrade database schema
  /// Called when database version changes
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // Future migrations will go here
    // Example:
    // if (oldVersion < 2) {
    //   await db.execute('ALTER TABLE trips ADD COLUMN new_field TEXT');
    // }
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
