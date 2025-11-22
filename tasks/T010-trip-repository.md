# T010: Trip Repository Implementation - Detailed Task Document

## Overview

Implement the TripRepository class that provides CRUD operations and query methods for trip data persistence. This repository layer sits between the domain and data layers, providing a clean abstraction over the SQLite database created in T009. It handles all database interactions, error management, and provides Riverpod integration for dependency injection.

**Status**: ⏳ In Progress
**Dependencies**: T009 (SQLite Database Schema), T003 (Riverpod Code Generation Setup)
**Estimate**: 2-3 hours
**Phase**: Phase 3 - Data Management

## Prerequisites

Before starting this task, ensure:
- ✅ T009 completed (DatabaseService and schema implemented)
- ✅ T003 completed (Riverpod code generation configured)
- ✅ Understanding of Repository pattern
- ✅ Familiarity with sqflite CRUD operations
- ✅ Knowledge of Riverpod providers

## Objectives

1. Create TripRepository class with full CRUD operations
2. Implement trip query methods (getAll, getById, getByDateRange, search)
3. Handle route points persistence alongside trips
4. Provide proper error handling and transaction management
5. Integrate with Riverpod for dependency injection
6. Write comprehensive unit tests with database mocking
7. Ensure all operations are type-safe and use domain models

## Repository Design

### Responsibilities

The TripRepository is responsible for:
- **CRUD Operations**: Create, Read, Update, Delete trips
- **Query Methods**: Get all trips, filter by date, search by criteria
- **Route Management**: Handle route points with trips (composition)
- **Transaction Management**: Ensure atomic operations for trip + route points
- **Error Handling**: Convert database exceptions to domain errors
- **Type Safety**: Work with domain models (Trip, RoutePoint), not raw maps

### Architecture Position

```
┌─────────────────────┐
│   Presentation      │
│   (UI, Providers)   │
└──────────┬──────────┘
           │
┌──────────▼──────────┐
│   TripRepository    │ ← You are implementing this
│   (CRUD, Queries)   │
└──────────┬──────────┘
           │
┌──────────▼──────────┐
│  DatabaseService    │ ✅ Already exists (T009)
│  (Schema, Tables)   │
└─────────────────────┘
```

## Implementation Steps

### Step 1: Create TripRepository Class

**File**: `lib/features/trip_history/data/repositories/trip_repository.dart`

```dart
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:autoride/features/trip_detection/data/services/database_service.dart';
import 'package:autoride/features/trip_detection/domain/models/trip.dart';
import 'package:autoride/features/trip_detection/domain/models/activity_confidence.dart';

part 'trip_repository.g.dart';

/// Trip repository provider
/// Provides access to trip data persistence operations
@riverpod
TripRepository tripRepository(TripRepositoryRef ref) {
  final db = ref.watch(databaseProvider);
  return TripRepository(db);
}

/// Repository for trip data persistence
/// Handles CRUD operations and queries for trips and route points
class TripRepository {
  final Database _db;

  TripRepository(this._db);

  // ========== CREATE ==========

  /// Save a new trip with its route points
  /// Returns the trip with assigned ID
  Future<Trip> saveTrip(Trip trip) async {
    try {
      // Use transaction to ensure atomicity
      final tripId = await _db.transaction((txn) async {
        // Insert trip
        final id = await txn.insert('trips', trip.toMap());

        // Insert route points if present
        if (trip.routePoints.isNotEmpty) {
          final batch = txn.batch();
          for (final point in trip.routePoints) {
            batch.insert(
              'route_points',
              point.copyWith(tripId: id).toMap(),
            );
          }
          await batch.commit(noResult: true);
        }

        return id;
      });

      // Return trip with assigned ID
      return trip.copyWith(id: tripId);
    } catch (e) {
      throw TripRepositoryException('Failed to save trip: $e');
    }
  }

  /// Save a single route point for an existing trip
  Future<RoutePoint> saveRoutePoint(RoutePoint point) async {
    try {
      final id = await _db.insert('route_points', point.toMap());
      return point.copyWith(id: id);
    } catch (e) {
      throw TripRepositoryException('Failed to save route point: $e');
    }
  }

  /// Save multiple route points for an existing trip
  Future<void> saveRoutePoints(List<RoutePoint> points) async {
    if (points.isEmpty) return;

    try {
      final batch = _db.batch();
      for (final point in points) {
        batch.insert('route_points', point.toMap());
      }
      await batch.commit(noResult: true);
    } catch (e) {
      throw TripRepositoryException('Failed to save route points: $e');
    }
  }

  // ========== READ ==========

  /// Get trip by ID with its route points
  Future<Trip?> getTripById(int id) async {
    try {
      // Query trip
      final tripMaps = await _db.query(
        'trips',
        where: 'id = ?',
        whereArgs: [id],
      );

      if (tripMaps.isEmpty) return null;

      // Query route points
      final pointMaps = await _db.query(
        'route_points',
        where: 'trip_id = ?',
        whereArgs: [id],
        orderBy: 'timestamp ASC',
      );

      final points = pointMaps.map((map) => RoutePoint.fromMap(map)).toList();
      return Trip.fromMap(tripMaps.first, points);
    } catch (e) {
      throw TripRepositoryException('Failed to get trip by ID: $e');
    }
  }

  /// Get all trips (without route points for performance)
  /// Use getTripById to load route points for specific trip
  Future<List<Trip>> getAllTrips({
    int? limit,
    int? offset,
    String orderBy = 'start_time DESC',
  }) async {
    try {
      final tripMaps = await _db.query(
        'trips',
        orderBy: orderBy,
        limit: limit,
        offset: offset,
      );

      return tripMaps.map((map) => Trip.fromMap(map, [])).toList();
    } catch (e) {
      throw TripRepositoryException('Failed to get all trips: $e');
    }
  }

  /// Get trips within a date range
  Future<List<Trip>> getTripsByDateRange({
    required DateTime startDate,
    required DateTime endDate,
    bool includeRoutePoints = false,
  }) async {
    try {
      final tripMaps = await _db.query(
        'trips',
        where: 'start_time >= ? AND start_time <= ?',
        whereArgs: [
          startDate.millisecondsSinceEpoch,
          endDate.millisecondsSinceEpoch,
        ],
        orderBy: 'start_time DESC',
      );

      if (!includeRoutePoints) {
        return tripMaps.map((map) => Trip.fromMap(map, [])).toList();
      }

      // Load route points for each trip
      final trips = <Trip>[];
      for (final tripMap in tripMaps) {
        final tripId = tripMap['id'] as int;
        final pointMaps = await _db.query(
          'route_points',
          where: 'trip_id = ?',
          whereArgs: [tripId],
          orderBy: 'timestamp ASC',
        );
        final points = pointMaps.map((map) => RoutePoint.fromMap(map)).toList();
        trips.add(Trip.fromMap(tripMap, points));
      }

      return trips;
    } catch (e) {
      throw TripRepositoryException('Failed to get trips by date range: $e');
    }
  }

  /// Get trips by activity type
  Future<List<Trip>> getTripsByActivity(ActivityType activity) async {
    try {
      final tripMaps = await _db.query(
        'trips',
        where: 'detected_activity = ?',
        whereArgs: [activity.name],
        orderBy: 'start_time DESC',
      );

      return tripMaps.map((map) => Trip.fromMap(map, [])).toList();
    } catch (e) {
      throw TripRepositoryException('Failed to get trips by activity: $e');
    }
  }

  /// Get only user-confirmed trips
  Future<List<Trip>> getConfirmedTrips() async {
    try {
      final tripMaps = await _db.query(
        'trips',
        where: 'user_confirmed = ?',
        whereArgs: [1],
        orderBy: 'start_time DESC',
      );

      return tripMaps.map((map) => Trip.fromMap(map, [])).toList();
    } catch (e) {
      throw TripRepositoryException('Failed to get confirmed trips: $e');
    }
  }

  /// Get trip count
  Future<int> getTripCount() async {
    try {
      final result = await _db.rawQuery('SELECT COUNT(*) as count FROM trips');
      return Sqflite.firstIntValue(result) ?? 0;
    } catch (e) {
      throw TripRepositoryException('Failed to get trip count: $e');
    }
  }

  /// Get total distance across all trips
  Future<double> getTotalDistance() async {
    try {
      final result = await _db.rawQuery('SELECT SUM(distance) as total FROM trips');
      return (result.first['total'] as num?)?.toDouble() ?? 0.0;
    } catch (e) {
      throw TripRepositoryException('Failed to get total distance: $e');
    }
  }

  /// Get route points for a trip
  Future<List<RoutePoint>> getRoutePoints(int tripId) async {
    try {
      final pointMaps = await _db.query(
        'route_points',
        where: 'trip_id = ?',
        whereArgs: [tripId],
        orderBy: 'timestamp ASC',
      );

      return pointMaps.map((map) => RoutePoint.fromMap(map)).toList();
    } catch (e) {
      throw TripRepositoryException('Failed to get route points: $e');
    }
  }

  // ========== UPDATE ==========

  /// Update an existing trip
  Future<void> updateTrip(Trip trip) async {
    if (trip.id == null) {
      throw TripRepositoryException('Cannot update trip without ID');
    }

    try {
      await _db.update(
        'trips',
        trip.toMap(),
        where: 'id = ?',
        whereArgs: [trip.id],
      );
    } catch (e) {
      throw TripRepositoryException('Failed to update trip: $e');
    }
  }

  /// Mark trip as user confirmed
  Future<void> confirmTrip(int tripId) async {
    try {
      await _db.update(
        'trips',
        {'user_confirmed': 1},
        where: 'id = ?',
        whereArgs: [tripId],
      );
    } catch (e) {
      throw TripRepositoryException('Failed to confirm trip: $e');
    }
  }

  // ========== DELETE ==========

  /// Delete a trip (route points cascade deleted automatically)
  Future<void> deleteTrip(int tripId) async {
    try {
      final rowsDeleted = await _db.delete(
        'trips',
        where: 'id = ?',
        whereArgs: [tripId],
      );

      if (rowsDeleted == 0) {
        throw TripRepositoryException('Trip not found: $tripId');
      }
    } catch (e) {
      throw TripRepositoryException('Failed to delete trip: $e');
    }
  }

  /// Delete all trips (use with caution!)
  Future<void> deleteAllTrips() async {
    try {
      await _db.delete('trips');
    } catch (e) {
      throw TripRepositoryException('Failed to delete all trips: $e');
    }
  }

  /// Delete trips older than specified date
  Future<int> deleteTripsOlderThan(DateTime date) async {
    try {
      return await _db.delete(
        'trips',
        where: 'start_time < ?',
        whereArgs: [date.millisecondsSinceEpoch],
      );
    } catch (e) {
      throw TripRepositoryException('Failed to delete old trips: $e');
    }
  }
}

/// Exception thrown by TripRepository operations
class TripRepositoryException implements Exception {
  final String message;

  TripRepositoryException(this.message);

  @override
  String toString() => 'TripRepositoryException: $message';
}
```

**Key Implementation Details**:
- **Transactions**: saveTrip uses transaction to ensure trip + route points are saved atomically
- **Batch Operations**: Multiple route points saved using batch for performance
- **Performance**: getAllTrips excludes route points by default (load on demand)
- **Type Safety**: All methods work with domain models, not raw maps
- **Error Handling**: Custom exception type for repository-specific errors
- **Query Optimization**: Use indexes created in T009 for fast queries

### Step 2: Add Missing Freezed Methods

The repository uses `copyWith` on RoutePoint and Trip. Ensure these are available.

**File**: `lib/features/trip_detection/domain/models/trip.dart` (update if needed)

Freezed automatically generates `copyWith` for all fields, so no changes needed if T009 was implemented correctly.

### Step 3: Generate Riverpod Code

Run code generation to create the repository provider:

```bash
flutter pub run build_runner build --delete-conflicting-outputs
```

This generates `trip_repository.g.dart` with the `tripRepositoryProvider`.

### Step 4: Create Comprehensive Unit Tests

**File**: `test/features/trip_history/data/repositories/trip_repository_test.dart`

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:autoride/features/trip_detection/data/services/database_service.dart';
import 'package:autoride/features/trip_history/data/repositories/trip_repository.dart';
import 'package:autoride/features/trip_detection/domain/models/trip.dart';
import 'package:autoride/features/trip_detection/domain/models/activity_confidence.dart';
import 'package:autoride/features/trip_detection/domain/models/location_data.dart';

void main() {
  // Initialize FFI for desktop testing
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late DatabaseService dbService;
  late TripRepository repository;

  setUp(() async {
    dbService = DatabaseService();
    await dbService.deleteDatabase();
    final db = await dbService.database;
    repository = TripRepository(db);
  });

  tearDown(() async {
    await dbService.close();
    await dbService.deleteDatabase();
  });

  // Helper function to create test trip
  Trip createTestTrip({
    DateTime? startTime,
    int durationSeconds = 3600,
    double distance = 5000.0,
    List<RoutePoint>? routePoints,
  }) {
    final start = startTime ?? DateTime.now().subtract(const Duration(hours: 1));
    return Trip(
      startTime: start,
      endTime: start.add(Duration(seconds: durationSeconds)),
      distance: distance,
      duration: durationSeconds,
      avgSpeed: 18.0,
      maxSpeed: 25.0,
      detectedActivity: ActivityType.cycling,
      confidenceScore: 0.92,
      userConfirmed: false,
      routePoints: routePoints ?? [],
    );
  }

  // Helper function to create test route point
  RoutePoint createTestRoutePoint(int tripId, {DateTime? timestamp}) {
    return RoutePoint(
      tripId: tripId,
      latitude: 48.8566,
      longitude: 2.3522,
      altitude: 35.0,
      timestamp: timestamp ?? DateTime.now(),
      accuracy: 5.0,
      speed: 5.0,
    );
  }

  group('TripRepository - CREATE', () {
    test('should save trip without route points', () async {
      final trip = createTestTrip();

      final savedTrip = await repository.saveTrip(trip);

      expect(savedTrip.id, isNotNull);
      expect(savedTrip.id, greaterThan(0));
      expect(savedTrip.distance, equals(5000.0));
      expect(savedTrip.detectedActivity, equals(ActivityType.cycling));
    });

    test('should save trip with route points in transaction', () async {
      final routePoints = List.generate(5, (i) {
        return RoutePoint(
          tripId: 0, // Will be updated in transaction
          latitude: 48.8566 + i * 0.001,
          longitude: 2.3522 + i * 0.001,
          timestamp: DateTime.now().add(Duration(minutes: i)),
        );
      });

      final trip = createTestTrip(routePoints: routePoints);

      final savedTrip = await repository.saveTrip(trip);

      expect(savedTrip.id, isNotNull);

      // Verify route points were saved
      final loadedPoints = await repository.getRoutePoints(savedTrip.id!);
      expect(loadedPoints, hasLength(5));
      expect(loadedPoints.first.latitude, closeTo(48.8566, 0.0001));
    });

    test('should save route point for existing trip', () async {
      // First save a trip
      final trip = createTestTrip();
      final savedTrip = await repository.saveTrip(trip);

      // Then save a route point
      final point = createTestRoutePoint(savedTrip.id!);
      final savedPoint = await repository.saveRoutePoint(point);

      expect(savedPoint.id, isNotNull);
      expect(savedPoint.tripId, equals(savedTrip.id));
    });

    test('should save multiple route points in batch', () async {
      // First save a trip
      final trip = createTestTrip();
      final savedTrip = await repository.saveTrip(trip);

      // Create multiple route points
      final points = List.generate(10, (i) {
        return createTestRoutePoint(
          savedTrip.id!,
          timestamp: DateTime.now().add(Duration(minutes: i)),
        );
      });

      await repository.saveRoutePoints(points);

      // Verify all points were saved
      final loadedPoints = await repository.getRoutePoints(savedTrip.id!);
      expect(loadedPoints, hasLength(10));
    });
  });

  group('TripRepository - READ', () {
    test('should get trip by ID with route points', () async {
      // Save trip with route points
      final routePoints = List.generate(3, (i) {
        return RoutePoint(
          tripId: 0,
          latitude: 48.8566,
          longitude: 2.3522,
          timestamp: DateTime.now(),
        );
      });

      final trip = createTestTrip(routePoints: routePoints);
      final savedTrip = await repository.saveTrip(trip);

      // Retrieve trip
      final loadedTrip = await repository.getTripById(savedTrip.id!);

      expect(loadedTrip, isNotNull);
      expect(loadedTrip!.id, equals(savedTrip.id));
      expect(loadedTrip.distance, equals(5000.0));
      expect(loadedTrip.routePoints, hasLength(3));
    });

    test('should return null for non-existent trip ID', () async {
      final trip = await repository.getTripById(9999);
      expect(trip, isNull);
    });

    test('should get all trips without route points', () async {
      // Save multiple trips
      await repository.saveTrip(createTestTrip());
      await repository.saveTrip(createTestTrip());
      await repository.saveTrip(createTestTrip());

      final trips = await repository.getAllTrips();

      expect(trips, hasLength(3));
      expect(trips.first.routePoints, isEmpty); // No route points loaded
    });

    test('should get trips with limit and offset', () async {
      // Save 10 trips
      for (int i = 0; i < 10; i++) {
        await repository.saveTrip(createTestTrip());
      }

      final trips = await repository.getAllTrips(limit: 5, offset: 2);

      expect(trips, hasLength(5));
    });

    test('should get trips by date range', () async {
      final now = DateTime.now();
      final yesterday = now.subtract(const Duration(days: 1));
      final twoDaysAgo = now.subtract(const Duration(days: 2));

      // Save trips at different times
      await repository.saveTrip(createTestTrip(startTime: twoDaysAgo));
      await repository.saveTrip(createTestTrip(startTime: yesterday));
      await repository.saveTrip(createTestTrip(startTime: now));

      // Query trips from yesterday to now
      final trips = await repository.getTripsByDateRange(
        startDate: yesterday.subtract(const Duration(hours: 1)),
        endDate: now.add(const Duration(hours: 1)),
      );

      expect(trips, hasLength(2)); // Yesterday and today
    });

    test('should get trips by activity type', () async {
      // Save trips with different activities
      await repository.saveTrip(
        createTestTrip()..copyWith(detectedActivity: ActivityType.cycling),
      );
      await repository.saveTrip(
        createTestTrip()..copyWith(detectedActivity: ActivityType.cycling),
      );
      await repository.saveTrip(
        createTestTrip()..copyWith(detectedActivity: ActivityType.walking),
      );

      final cyclingTrips = await repository.getTripsByActivity(ActivityType.cycling);

      expect(cyclingTrips, hasLength(2));
      expect(
        cyclingTrips.every((t) => t.detectedActivity == ActivityType.cycling),
        isTrue,
      );
    });

    test('should get only confirmed trips', () async {
      // Save trips with different confirmation status
      final trip1 = await repository.saveTrip(createTestTrip());
      await repository.confirmTrip(trip1.id!);

      await repository.saveTrip(createTestTrip());
      await repository.saveTrip(createTestTrip());

      final confirmedTrips = await repository.getConfirmedTrips();

      expect(confirmedTrips, hasLength(1));
      expect(confirmedTrips.first.userConfirmed, isTrue);
    });

    test('should get trip count', () async {
      await repository.saveTrip(createTestTrip());
      await repository.saveTrip(createTestTrip());
      await repository.saveTrip(createTestTrip());

      final count = await repository.getTripCount();

      expect(count, equals(3));
    });

    test('should get total distance', () async {
      await repository.saveTrip(createTestTrip(distance: 5000.0));
      await repository.saveTrip(createTestTrip(distance: 3000.0));
      await repository.saveTrip(createTestTrip(distance: 2000.0));

      final totalDistance = await repository.getTotalDistance();

      expect(totalDistance, equals(10000.0));
    });

    test('should get route points for trip', () async {
      final routePoints = List.generate(5, (i) {
        return RoutePoint(
          tripId: 0,
          latitude: 48.8566,
          longitude: 2.3522,
          timestamp: DateTime.now(),
        );
      });

      final trip = createTestTrip(routePoints: routePoints);
      final savedTrip = await repository.saveTrip(trip);

      final loadedPoints = await repository.getRoutePoints(savedTrip.id!);

      expect(loadedPoints, hasLength(5));
    });
  });

  group('TripRepository - UPDATE', () {
    test('should update trip', () async {
      final trip = createTestTrip();
      final savedTrip = await repository.saveTrip(trip);

      // Update trip
      final updatedTrip = savedTrip.copyWith(
        distance: 10000.0,
        avgSpeed: 20.0,
      );

      await repository.updateTrip(updatedTrip);

      // Verify update
      final loadedTrip = await repository.getTripById(savedTrip.id!);
      expect(loadedTrip!.distance, equals(10000.0));
      expect(loadedTrip.avgSpeed, equals(20.0));
    });

    test('should throw exception when updating trip without ID', () async {
      final trip = createTestTrip();

      expect(
        () => repository.updateTrip(trip),
        throwsA(isA<TripRepositoryException>()),
      );
    });

    test('should confirm trip', () async {
      final trip = createTestTrip();
      final savedTrip = await repository.saveTrip(trip);

      expect(savedTrip.userConfirmed, isFalse);

      await repository.confirmTrip(savedTrip.id!);

      final loadedTrip = await repository.getTripById(savedTrip.id!);
      expect(loadedTrip!.userConfirmed, isTrue);
    });
  });

  group('TripRepository - DELETE', () {
    test('should delete trip and cascade delete route points', () async {
      // Save trip with route points
      final routePoints = List.generate(5, (i) {
        return RoutePoint(
          tripId: 0,
          latitude: 48.8566,
          longitude: 2.3522,
          timestamp: DateTime.now(),
        );
      });

      final trip = createTestTrip(routePoints: routePoints);
      final savedTrip = await repository.saveTrip(trip);

      // Verify trip and points exist
      var loadedTrip = await repository.getTripById(savedTrip.id!);
      expect(loadedTrip, isNotNull);
      expect(loadedTrip!.routePoints, hasLength(5));

      // Delete trip
      await repository.deleteTrip(savedTrip.id!);

      // Verify trip is deleted
      loadedTrip = await repository.getTripById(savedTrip.id!);
      expect(loadedTrip, isNull);

      // Verify route points are also deleted (CASCADE)
      final points = await repository.getRoutePoints(savedTrip.id!);
      expect(points, isEmpty);
    });

    test('should throw exception when deleting non-existent trip', () async {
      expect(
        () => repository.deleteTrip(9999),
        throwsA(isA<TripRepositoryException>()),
      );
    });

    test('should delete all trips', () async {
      await repository.saveTrip(createTestTrip());
      await repository.saveTrip(createTestTrip());
      await repository.saveTrip(createTestTrip());

      await repository.deleteAllTrips();

      final count = await repository.getTripCount();
      expect(count, equals(0));
    });

    test('should delete trips older than specified date', () async {
      final now = DateTime.now();
      final oldDate = now.subtract(const Duration(days: 10));

      // Save old trips
      await repository.saveTrip(createTestTrip(startTime: oldDate));
      await repository.saveTrip(createTestTrip(startTime: oldDate));

      // Save recent trip
      await repository.saveTrip(createTestTrip(startTime: now));

      // Delete trips older than 5 days
      final deletedCount = await repository.deleteTripsOlderThan(
        now.subtract(const Duration(days: 5)),
      );

      expect(deletedCount, equals(2));

      final remainingCount = await repository.getTripCount();
      expect(remainingCount, equals(1));
    });
  });

  group('TripRepository - Error Handling', () {
    test('should throw TripRepositoryException on database errors', () async {
      // Close database to cause errors
      await dbService.close();

      final trip = createTestTrip();

      expect(
        () => repository.saveTrip(trip),
        throwsA(isA<TripRepositoryException>()),
      );
    });
  });
}
```

**Testing Strategy**:
- **Helper Functions**: `createTestTrip()` and `createTestRoutePoint()` for consistent test data
- **Group Organization**: Separate groups for CREATE, READ, UPDATE, DELETE
- **Coverage**: Test all public methods and error cases
- **Database Isolation**: Each test uses clean database (setUp/tearDown)
- **Assertions**: Verify both direct results and side effects (e.g., cascade delete)

### Step 5: Run Quality Gates

```bash
# Generate Riverpod code
flutter pub run build_runner build --delete-conflicting-outputs

# Run static analysis (MUST pass)
flutter analyze

# Run all tests (MUST pass)
flutter test

# Run specific repository tests
flutter test test/features/trip_history/data/repositories/trip_repository_test.dart
```

## Usage Examples

### Save a Trip

```dart
final repository = ref.read(tripRepositoryProvider);

final trip = Trip(
  startTime: tripStartTime,
  endTime: DateTime.now(),
  distance: totalDistance,
  duration: duration,
  avgSpeed: avgSpeed,
  maxSpeed: maxSpeed,
  detectedActivity: ActivityType.cycling,
  confidenceScore: 0.92,
  routePoints: collectedRoutePoints,
);

final savedTrip = await repository.saveTrip(trip);
print('Trip saved with ID: ${savedTrip.id}');
```

### Load Trip History

```dart
final repository = ref.read(tripRepositoryProvider);

// Get all trips (summary only, no route points)
final trips = await repository.getAllTrips(limit: 20);

// Get specific trip with route points
final trip = await repository.getTripById(tripId);

// Get trips from last 7 days
final recentTrips = await repository.getTripsByDateRange(
  startDate: DateTime.now().subtract(Duration(days: 7)),
  endDate: DateTime.now(),
);
```

### Update and Delete

```dart
final repository = ref.read(tripRepositoryProvider);

// Confirm a trip
await repository.confirmTrip(tripId);

// Update trip details
final updatedTrip = trip.copyWith(distance: newDistance);
await repository.updateTrip(updatedTrip);

// Delete old trips
final deletedCount = await repository.deleteTripsOlderThan(
  DateTime.now().subtract(Duration(days: 30)),
);
```

## Common Pitfalls

### 1. Transaction Management

❌ **Wrong**: Saving trip and points separately (not atomic)
```dart
Future<Trip> saveTrip(Trip trip) async {
  final id = await _db.insert('trips', trip.toMap());  // ❌ Not in transaction

  for (final point in trip.routePoints) {
    await _db.insert('route_points', point.toMap());  // ❌ If this fails, trip remains
  }

  return trip.copyWith(id: id);
}
```

✅ **Correct**: Use transaction for atomicity
```dart
Future<Trip> saveTrip(Trip trip) async {
  final tripId = await _db.transaction((txn) async {  // ✅ Transaction ensures all-or-nothing
    final id = await txn.insert('trips', trip.toMap());

    if (trip.routePoints.isNotEmpty) {
      final batch = txn.batch();
      for (final point in trip.routePoints) {
        batch.insert('route_points', point.copyWith(tripId: id).toMap());
      }
      await batch.commit(noResult: true);
    }

    return id;
  });

  return trip.copyWith(id: tripId);
}
```

### 2. Performance with Route Points

❌ **Wrong**: Always loading route points (hundreds of points per trip)
```dart
Future<List<Trip>> getAllTrips() async {
  final tripMaps = await _db.query('trips');

  final trips = <Trip>[];
  for (final tripMap in tripMaps) {
    final points = await _db.query(  // ❌ N+1 query problem
      'route_points',
      where: 'trip_id = ?',
      whereArgs: [tripMap['id']],
    );
    trips.add(Trip.fromMap(tripMap, points));
  }

  return trips;
}
```

✅ **Correct**: Load route points on demand
```dart
Future<List<Trip>> getAllTrips() async {
  final tripMaps = await _db.query('trips');
  return tripMaps.map((map) => Trip.fromMap(map, [])).toList();  // ✅ No route points
}

// Load route points only when needed
Future<Trip?> getTripById(int id) async {
  final tripMaps = await _db.query('trips', where: 'id = ?', whereArgs: [id]);
  if (tripMaps.isEmpty) return null;

  final pointMaps = await _db.query(  // ✅ Load only for this trip
    'route_points',
    where: 'trip_id = ?',
    whereArgs: [id],
  );

  final points = pointMaps.map((map) => RoutePoint.fromMap(map)).toList();
  return Trip.fromMap(tripMaps.first, points);
}
```

### 3. Error Handling

❌ **Wrong**: Exposing database errors directly
```dart
Future<Trip?> getTripById(int id) async {
  final tripMaps = await _db.query(  // ❌ DatabaseException exposed to caller
    'trips',
    where: 'id = ?',
    whereArgs: [id],
  );
  return Trip.fromMap(tripMaps.first, []);
}
```

✅ **Correct**: Wrap in domain exception
```dart
Future<Trip?> getTripById(int id) async {
  try {
    final tripMaps = await _db.query(
      'trips',
      where: 'id = ?',
      whereArgs: [id],
    );

    if (tripMaps.isEmpty) return null;

    final points = await getRoutePoints(id);
    return Trip.fromMap(tripMaps.first, points);
  } catch (e) {
    throw TripRepositoryException('Failed to get trip by ID: $e');  // ✅ Domain exception
  }
}
```

### 4. Batch Operations

❌ **Wrong**: Individual inserts for multiple points
```dart
Future<void> saveRoutePoints(List<RoutePoint> points) async {
  for (final point in points) {
    await _db.insert('route_points', point.toMap());  // ❌ Slow for many points
  }
}
```

✅ **Correct**: Use batch for performance
```dart
Future<void> saveRoutePoints(List<RoutePoint> points) async {
  if (points.isEmpty) return;

  final batch = _db.batch();  // ✅ Batch operation
  for (final point in points) {
    batch.insert('route_points', point.toMap());
  }
  await batch.commit(noResult: true);
}
```

## Acceptance Criteria

- [ ] TripRepository class created with all CRUD methods
- [ ] saveTrip method uses transaction for atomicity
- [ ] getAllTrips excludes route points for performance
- [ ] getTripById loads trip with route points
- [ ] getTripsByDateRange filters correctly
- [ ] Query methods (getByActivity, getConfirmed) work correctly
- [ ] Aggregate methods (getTripCount, getTotalDistance) work correctly
- [ ] updateTrip and confirmTrip modify data correctly
- [ ] deleteTrip cascades to route points
- [ ] All methods throw TripRepositoryException on errors
- [ ] Riverpod provider generated (tripRepositoryProvider)
- [ ] All unit tests pass (25+ tests covering all methods)
- [ ] No flutter analyze warnings
- [ ] Code generation successful (trip_repository.g.dart created)

## Resources

**Official Documentation**:
- [sqflite CRUD Operations](https://pub.dev/packages/sqflite#insert-a-record) - Database operations
- [sqflite Transactions](https://pub.dev/packages/sqflite#transactions) - Transaction handling
- [Riverpod Providers](https://riverpod.dev/docs/providers/provider) - Provider patterns

**AutoRide Project References**:
- `lib/features/trip_detection/data/services/database_service.dart` - Database instance
- `lib/features/trip_detection/domain/models/trip.dart` - Trip domain model (T009)
- `lib/features/trip_detection/domain/models/activity_confidence.dart` - ActivityType enum

**Testing Resources**:
- [sqflite_common_ffi](https://pub.dev/packages/sqflite_common_ffi) - Desktop testing support
- [Flutter Testing Guide](https://docs.flutter.dev/testing) - Testing best practices

**Design Patterns**:
- [Repository Pattern](https://martinfowler.com/eaaCatalog/repository.html) - Architecture pattern
- [Unit of Work Pattern](https://martinfowler.com/eaaCatalog/unitOfWork.html) - Transaction management

## Next Steps

After completing T010, you'll be ready for:
- **T015**: Trip Data Recording (use repository to save trips during detection)
- **T023**: Trip History Screen (display trips from repository)
- **T024**: Trip Detail View (show trip with route visualization)

---

**Estimated Time**: 2-3 hours
**Last Updated**: 2025-11-22
