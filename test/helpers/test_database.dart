import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:autoride/core/constants/app_constants.dart';

/// Creates an in-memory test database with the AutoRide schema
/// This avoids file conflicts when tests run in parallel
Future<Database> createTestDatabase() async {
  return await databaseFactory.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(
      version: AppConstants.databaseVersion,
      onCreate: (db, version) async {
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
        await db.execute('CREATE INDEX idx_trip_start_time ON trips(start_time)');
        await db.execute('CREATE INDEX idx_trip_end_time ON trips(end_time)');
        await db.execute('CREATE INDEX idx_route_points_trip_id ON route_points(trip_id)');
        await db.execute('CREATE INDEX idx_route_points_timestamp ON route_points(timestamp)');
      },
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
    ),
  );
}
