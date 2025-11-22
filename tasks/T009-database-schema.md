# T009: SQLite Database Schema - Detailed Task Document

## Overview

Implement the SQLite database schema for persisting trip data using sqflite. This task creates the foundational database structure that will store trip records and route points for the AutoRide application. The database will support CRUD operations for trip history, route visualization, and analytics.

**Status**: ☐ Pending
**Dependencies**: T001 (Project Setup - sqflite dependency)
**Estimate**: 2 hours
**Phase**: Phase 3 - Data Management

## Prerequisites

Before starting this task, ensure:
- ✅ T001 completed (sqflite dependency added to pubspec.yaml)
- ✅ Understanding of existing domain models (LocationData, MotionData, ActivityConfidence)
- ✅ Familiarity with SQL and database design
- ✅ Riverpod code generation configured (for database service provider)

## Objectives

1. Create database initialization service with schema migration support
2. Define trips and route_points table schemas
3. Implement database helper with CRUD utilities
4. Add proper indexes for query performance
5. Handle database versioning and migrations
6. Provide Riverpod provider for database access
7. Write comprehensive tests for database operations

## Database Design

### Entity Relationship

```
┌─────────────┐       1:N        ┌──────────────────┐
│   trips     │──────────────────│  route_points    │
└─────────────┘                  └──────────────────┘
```

### Schema Details

**trips table**: Stores trip metadata and summary statistics
- Primary key: Auto-incrementing integer ID
- Timestamps stored as millisecondsSinceEpoch (INTEGER for efficient queries)
- Distances in meters (REAL for precision)
- Speeds in km/h (REAL)
- Confidence scores 0.0-1.0 (REAL)

**route_points table**: Stores GPS coordinates for trip routes
- Foreign key to trips with CASCADE DELETE (deleting trip removes all points)
- Lat/lon as REAL for precision
- Indexed on trip_id for fast route retrieval

## Implementation Steps

### Step 1: Create Domain Model for Trip

First, we need a Trip domain model that maps to/from database records.

**File**: `lib/features/trip_detection/domain/models/trip.dart`

```dart
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:autoride/features/trip_detection/domain/models/activity_confidence.dart';
import 'package:autoride/features/trip_detection/domain/models/location_data.dart';

part 'trip.freezed.dart';

/// Trip model representing a recorded bike trip
@freezed
sealed class Trip with _$Trip {
  const Trip._();

  const factory Trip({
    int? id, // Nullable for new trips not yet saved
    required DateTime startTime,
    required DateTime endTime,
    required double distance, // meters
    required int duration, // seconds
    double? avgSpeed, // km/h
    double? maxSpeed, // km/h
    required ActivityType detectedActivity,
    required double confidenceScore, // 0.0-1.0
    @Default(false) bool userConfirmed,
    @Default([]) List<RoutePoint> routePoints,
  }) = _Trip;

  /// Create from database map
  factory Trip.fromMap(Map<String, dynamic> map, List<RoutePoint> points) {
    return Trip(
      id: map['id'] as int?,
      startTime: DateTime.fromMillisecondsSinceEpoch(map['start_time'] as int),
      endTime: DateTime.fromMillisecondsSinceEpoch(map['end_time'] as int),
      distance: map['distance'] as double,
      duration: map['duration'] as int,
      avgSpeed: map['avg_speed'] as double?,
      maxSpeed: map['max_speed'] as double?,
      detectedActivity: ActivityType.values.firstWhere(
        (e) => e.name == map['detected_activity'],
        orElse: () => ActivityType.unknown,
      ),
      confidenceScore: map['confidence_score'] as double,
      userConfirmed: (map['user_confirmed'] as int) == 1,
      routePoints: points,
    );
  }
}

/// Extension for Trip database operations
extension TripExtensions on Trip {
  /// Convert to database map (without route points)
  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'start_time': startTime.millisecondsSinceEpoch,
      'end_time': endTime.millisecondsSinceEpoch,
      'distance': distance,
      'duration': duration,
      'avg_speed': avgSpeed,
      'max_speed': maxSpeed,
      'detected_activity': detectedActivity.name,
      'confidence_score': confidenceScore,
      'user_confirmed': userConfirmed ? 1 : 0,
    };
  }

  /// Calculate duration from start/end times
  Duration get tripDuration => endTime.difference(startTime);

  /// Check if trip meets minimum duration threshold (e.g., 1 minute)
  bool get isValidTrip => duration >= 60;

  /// Format duration as HH:MM:SS
  String get formattedDuration {
    final hours = duration ~/ 3600;
    final minutes = (duration % 3600) ~/ 60;
    final seconds = duration % 60;
    return '${hours.toString().padLeft(2, '0')}:'
        '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }

  /// Format distance as km with 2 decimal places
  String get formattedDistance => '${(distance / 1000).toStringAsFixed(2)} km';
}

/// Route point model (GPS coordinate with metadata)
@freezed
sealed class RoutePoint with _$RoutePoint {
  const RoutePoint._();

  const factory RoutePoint({
    int? id,
    required int tripId,
    required double latitude,
    required double longitude,
    double? altitude,
    required DateTime timestamp,
    double? accuracy,
    double? speed, // m/s
  }) = _RoutePoint;

  /// Create from LocationData
  factory RoutePoint.fromLocationData(LocationData location, int tripId) {
    return RoutePoint(
      tripId: tripId,
      latitude: location.latitude,
      longitude: location.longitude,
      altitude: location.altitude,
      timestamp: location.timestamp,
      accuracy: location.accuracy,
      speed: location.speed,
    );
  }

  /// Create from database map
  factory RoutePoint.fromMap(Map<String, dynamic> map) {
    return RoutePoint(
      id: map['id'] as int?,
      tripId: map['trip_id'] as int,
      latitude: map['latitude'] as double,
      longitude: map['longitude'] as double,
      altitude: map['altitude'] as double?,
      timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestamp'] as int),
      accuracy: map['accuracy'] as double?,
      speed: map['speed'] as double?,
    );
  }
}

/// Extension for RoutePoint database operations
extension RoutePointExtensions on RoutePoint {
  /// Convert to database map
  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'trip_id': tripId,
      'latitude': latitude,
      'longitude': longitude,
      'altitude': altitude,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'accuracy': accuracy,
      'speed': speed,
    };
  }

  /// Convert to LocationData
  LocationData toLocationData() {
    return LocationData(
      latitude: latitude,
      longitude: longitude,
      accuracy: accuracy ?? 0.0,
      altitude: altitude ?? 0.0,
      speed: speed ?? 0.0,
      heading: 0.0, // Not stored in database
      timestamp: timestamp,
    );
  }

  /// Speed in km/h
  double get speedKmh => (speed ?? 0.0) * 3.6;
}
```

**Important Pattern Notes**:
- Use `sealed class` with freezed (matches existing LocationData pattern)
- Private constructor `const Trip._();` goes BEFORE factory constructors
- Put custom methods in **extensions**, not in the class body
- Nullable `id` field for new trips not yet saved to database
- Use `DateTime.millisecondsSinceEpoch` for INTEGER storage (efficient for queries)
- Boolean stored as INTEGER (0/1) for SQLite compatibility

### Step 2: Create Database Service

**File**: `lib/features/trip_detection/data/services/database_service.dart`

```dart
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:autoride/core/constants/app_constants.dart';

part 'database_service.g.dart';

/// Database service provider
/// Provides initialized database instance
@riverpod
Future<Database> database(DatabaseRef ref) async {
  final dbService = DatabaseService();
  return await dbService.initDatabase();
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
```

**Key Implementation Details**:
- Singleton pattern for database instance (_database static field)
- Riverpod provider for dependency injection
- PRAGMA foreign_keys = ON enables CASCADE DELETE
- Indexes on frequently queried columns (start_time, trip_id)
- Migration support via onUpgrade callback
- Comprehensive logging for debugging
- Delete database method for testing

### Step 3: Add path package dependency

The database service uses the `path` package for path joining. Ensure it's in dependencies.

**File**: `pubspec.yaml` (check if already present, if not add)

```yaml
dependencies:
  path: ^1.9.0  # Add if not present
```

Run:
```bash
flutter pub get
```

### Step 4: Generate Riverpod Code

Run code generation to create the database provider:

```bash
flutter pub run build_runner build --delete-conflicting-outputs
```

This generates `database_service.g.dart` with the `databaseProvider`.

### Step 5: Create Database Tests

**File**: `test/features/trip_detection/data/services/database_service_test.dart`

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:autoride/features/trip_detection/data/services/database_service.dart';
import 'package:autoride/features/trip_detection/domain/models/trip.dart';
import 'package:autoride/features/trip_detection/domain/models/activity_confidence.dart';

void main() {
  // Initialize FFI for desktop testing
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late DatabaseService dbService;

  setUp(() async {
    dbService = DatabaseService();
    // Use in-memory database for tests
    await dbService.deleteDatabase();
  });

  tearDown(() async {
    await dbService.close();
    await dbService.deleteDatabase();
  });

  group('DatabaseService', () {
    test('should initialize database successfully', () async {
      final db = await dbService.database;

      expect(db, isNotNull);
      expect(db.isOpen, isTrue);
    });

    test('should create trips table', () async {
      final db = await dbService.database;

      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='trips'",
      );

      expect(tables, isNotEmpty);
      expect(tables.first['name'], equals('trips'));
    });

    test('should create route_points table', () async {
      final db = await dbService.database;

      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='route_points'",
      );

      expect(tables, isNotEmpty);
      expect(tables.first['name'], equals('route_points'));
    });

    test('should create indexes', () async {
      final db = await dbService.database;

      final indexes = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='index'",
      );

      final indexNames = indexes.map((e) => e['name'] as String).toList();

      expect(indexNames, contains('idx_trip_start_time'));
      expect(indexNames, contains('idx_trip_end_time'));
      expect(indexNames, contains('idx_route_points_trip_id'));
      expect(indexNames, contains('idx_route_points_timestamp'));
    });

    test('should enable foreign keys', () async {
      final db = await dbService.database;

      final result = await db.rawQuery('PRAGMA foreign_keys');

      expect(result.first['foreign_keys'], equals(1));
    });

    test('should insert and retrieve trip', () async {
      final db = await dbService.database;

      final trip = Trip(
        startTime: DateTime.now().subtract(const Duration(hours: 1)),
        endTime: DateTime.now(),
        distance: 5000.0,
        duration: 3600,
        avgSpeed: 18.0,
        maxSpeed: 25.0,
        detectedActivity: ActivityType.cycling,
        confidenceScore: 0.92,
        userConfirmed: false,
      );

      // Insert trip
      final tripId = await db.insert('trips', trip.toMap());

      expect(tripId, greaterThan(0));

      // Retrieve trip
      final result = await db.query(
        'trips',
        where: 'id = ?',
        whereArgs: [tripId],
      );

      expect(result, hasLength(1));
      expect(result.first['distance'], equals(5000.0));
      expect(result.first['detected_activity'], equals('cycling'));
    });

    test('should insert and retrieve route points', () async {
      final db = await dbService.database;

      // First insert a trip
      final tripMap = {
        'start_time': DateTime.now().millisecondsSinceEpoch,
        'end_time': DateTime.now().millisecondsSinceEpoch,
        'distance': 5000.0,
        'duration': 3600,
        'detected_activity': 'cycling',
        'confidence_score': 0.92,
        'user_confirmed': 0,
      };

      final tripId = await db.insert('trips', tripMap);

      // Insert route points
      final point = RoutePoint(
        tripId: tripId,
        latitude: 48.8566,
        longitude: 2.3522,
        altitude: 35.0,
        timestamp: DateTime.now(),
        accuracy: 5.0,
        speed: 5.0,
      );

      final pointId = await db.insert('route_points', point.toMap());

      expect(pointId, greaterThan(0));

      // Retrieve route points
      final result = await db.query(
        'route_points',
        where: 'trip_id = ?',
        whereArgs: [tripId],
      );

      expect(result, hasLength(1));
      expect(result.first['latitude'], equals(48.8566));
      expect(result.first['longitude'], equals(2.3522));
    });

    test('should cascade delete route points when trip is deleted', () async {
      final db = await dbService.database;

      // Insert trip
      final tripMap = {
        'start_time': DateTime.now().millisecondsSinceEpoch,
        'end_time': DateTime.now().millisecondsSinceEpoch,
        'distance': 5000.0,
        'duration': 3600,
        'detected_activity': 'cycling',
        'confidence_score': 0.92,
        'user_confirmed': 0,
      };

      final tripId = await db.insert('trips', tripMap);

      // Insert route points
      final point = RoutePoint(
        tripId: tripId,
        latitude: 48.8566,
        longitude: 2.3522,
        timestamp: DateTime.now(),
      );

      await db.insert('route_points', point.toMap());

      // Verify route point exists
      var routePoints = await db.query(
        'route_points',
        where: 'trip_id = ?',
        whereArgs: [tripId],
      );
      expect(routePoints, hasLength(1));

      // Delete trip
      await db.delete('trips', where: 'id = ?', whereArgs: [tripId]);

      // Verify route points are also deleted (CASCADE)
      routePoints = await db.query(
        'route_points',
        where: 'trip_id = ?',
        whereArgs: [tripId],
      );
      expect(routePoints, isEmpty);
    });
  });
}
```

**Testing Requirements**:
- Install `sqflite_common_ffi` for desktop testing:

```yaml
# In pubspec.yaml dev_dependencies
dev_dependencies:
  sqflite_common_ffi: ^2.3.0  # For desktop testing
```

Run tests:
```bash
flutter pub get
flutter test test/features/trip_detection/data/services/database_service_test.dart
```

## Schema Documentation

### trips Table

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| id | INTEGER | PRIMARY KEY AUTOINCREMENT | Unique trip identifier |
| start_time | INTEGER | NOT NULL | Trip start timestamp (millisecondsSinceEpoch) |
| end_time | INTEGER | NOT NULL | Trip end timestamp (millisecondsSinceEpoch) |
| distance | REAL | NOT NULL | Total distance in meters |
| duration | INTEGER | NOT NULL | Trip duration in seconds |
| avg_speed | REAL | NULL | Average speed in km/h (calculated) |
| max_speed | REAL | NULL | Maximum speed in km/h |
| detected_activity | TEXT | NOT NULL | Activity type (cycling, walking, etc.) |
| confidence_score | REAL | NOT NULL | ML confidence score (0.0-1.0) |
| user_confirmed | INTEGER | DEFAULT 0 | User validation flag (0=unconfirmed, 1=confirmed) |

**Indexes**:
- `idx_trip_start_time` on start_time (for date range queries)
- `idx_trip_end_time` on end_time (for date range queries)

### route_points Table

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| id | INTEGER | PRIMARY KEY AUTOINCREMENT | Unique point identifier |
| trip_id | INTEGER | NOT NULL, FOREIGN KEY | Reference to trips.id |
| latitude | REAL | NOT NULL | GPS latitude |
| longitude | REAL | NOT NULL | GPS longitude |
| altitude | REAL | NULL | Altitude in meters |
| timestamp | INTEGER | NOT NULL | Point timestamp (millisecondsSinceEpoch) |
| accuracy | REAL | NULL | GPS accuracy in meters |
| speed | REAL | NULL | Speed at point in m/s |

**Indexes**:
- `idx_route_points_trip_id` on trip_id (for route retrieval)
- `idx_route_points_timestamp` on timestamp (for time-based queries)

**Foreign Key**:
- trip_id → trips.id ON DELETE CASCADE (deleting trip removes all route points)

## Acceptance Criteria

- [ ] Database service initializes successfully
- [ ] trips table created with correct schema
- [ ] route_points table created with correct schema
- [ ] All indexes created (4 indexes total)
- [ ] Foreign key constraints enabled
- [ ] CASCADE DELETE works (deleting trip removes route points)
- [ ] Trip model converts to/from database map correctly
- [ ] RoutePoint model converts to/from database map correctly
- [ ] All unit tests pass (8 tests minimum)
- [ ] Database provider works with Riverpod
- [ ] No flutter analyze warnings
- [ ] Code generation successful (database_service.g.dart created)

## Common Pitfalls

### 1. Freezed Model Structure

❌ **Wrong**:
```dart
@freezed
class Trip with _$Trip {
  const factory Trip({...}) = _Trip;

  const Trip._(); // ❌ Private constructor after factory

  Map<String, dynamic> toMap() {...} // ❌ Method inside class
}
```

✅ **Correct**:
```dart
@freezed
sealed class Trip with _$Trip {
  const Trip._(); // ✅ Private constructor BEFORE factory

  const factory Trip({...}) = _Trip;
}

// ✅ Methods in extension
extension TripExtensions on Trip {
  Map<String, dynamic> toMap() {...}
}
```

### 2. DateTime Storage

❌ **Wrong**: Storing DateTime as TEXT
```sql
CREATE TABLE trips (
  start_time TEXT NOT NULL  -- ❌ Inefficient for queries
)
```

✅ **Correct**: Store as INTEGER (millisecondsSinceEpoch)
```sql
CREATE TABLE trips (
  start_time INTEGER NOT NULL  -- ✅ Efficient for range queries
)
```

### 3. Foreign Key Constraints

❌ **Wrong**: Forgetting to enable foreign keys
```dart
Future<Database> openDatabase() async {
  return await openDatabase(path);  // ❌ Foreign keys disabled by default
}
```

✅ **Correct**: Enable in onConfigure
```dart
Future<void> _onConfigure(Database db) async {
  await db.execute('PRAGMA foreign_keys = ON');  // ✅ Required
}
```

### 4. Boolean Storage

❌ **Wrong**: Using BOOLEAN type (not supported)
```sql
CREATE TABLE trips (
  user_confirmed BOOLEAN DEFAULT false  -- ❌ Not valid in SQLite
)
```

✅ **Correct**: Use INTEGER (0/1)
```sql
CREATE TABLE trips (
  user_confirmed INTEGER DEFAULT 0  -- ✅ 0 = false, 1 = true
)
```

## Resources

**Official Documentation**:
- [sqflite package](https://pub.dev/packages/sqflite) - SQLite plugin
- [SQLite Documentation](https://www.sqlite.org/docs.html) - SQL syntax reference
- [Freezed package](https://pub.dev/packages/freezed) - Immutable models

**AutoRide Project References**:
- `lib/features/trip_detection/domain/models/location_data.dart` - Freezed model example
- `lib/core/constants/app_constants.dart` - Database constants

**Testing Resources**:
- [sqflite_common_ffi](https://pub.dev/packages/sqflite_common_ffi) - Desktop testing support
- [Flutter Testing Guide](https://docs.flutter.dev/testing) - Testing best practices

## Next Steps

After completing T009, you'll be ready for:
- **T010**: Trip Repository Implementation (CRUD operations using this schema)
- **T015**: Trip Data Recording (save trips during detection)
- **T023**: Trip History Screen (display saved trips from database)

---

**Estimated Time**: 2 hours
**Last Updated**: 2025-11-22
