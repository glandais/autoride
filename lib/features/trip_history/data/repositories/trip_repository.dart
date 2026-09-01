import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:autoride/features/trip_detection/data/services/database_service.dart';
import 'package:autoride/features/trip_detection/domain/models/trip.dart';
import 'package:autoride/features/trip_detection/domain/models/activity_confidence.dart';

part 'trip_repository.g.dart';

/// Trip repository provider
/// Provides access to trip data persistence operations
@riverpod
Future<TripRepository> tripRepository(Ref ref) async {
  final db = await ref.watch(databaseProvider.future);
  return TripRepository(db);
}

/// Repository for trip data persistence
/// Handles CRUD operations and queries for trips and route points
class TripRepository {
  TripRepository(this._db);

  /// Only finished trips belong in history and statistics.
  ///
  /// A row is written the moment recording starts, so the table always holds
  /// in-progress rows (0 m / 0 s) while a ride is running, and stale ones after
  /// an app kill until [TripRecoveryService] closes them. Filtering here — the
  /// single place every read goes through — is what keeps those out of the UI.
  static const String _completedFilter = 'status = ?';
  static final List<Object?> _completedArgs = [TripStatus.completed.name];

  final Database _db;

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
            batch.insert('route_points', point.copyWith(tripId: id).toMap());
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
        where: _completedFilter,
        whereArgs: _completedArgs,
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
        where: 'start_time >= ? AND start_time <= ? AND $_completedFilter',
        whereArgs: [
          startDate.millisecondsSinceEpoch,
          endDate.millisecondsSinceEpoch,
          ..._completedArgs,
        ],
        orderBy: 'start_time DESC',
      );

      if (!includeRoutePoints || tripMaps.isEmpty) {
        return tripMaps.map((map) => Trip.fromMap(map, [])).toList();
      }

      // Load route points for all trips in a single query to avoid N+1 queries.
      final tripIds = tripMaps.map((map) => map['id'] as int).toList();
      final placeholders = List.filled(tripIds.length, '?').join(', ');
      final pointMaps = await _db.query(
        'route_points',
        where: 'trip_id IN ($placeholders)',
        whereArgs: tripIds,
        orderBy: 'trip_id ASC, timestamp ASC',
      );

      // Group route points by trip_id, preserving per-trip timestamp ordering.
      final pointsByTripId = <int, List<RoutePoint>>{};
      for (final map in pointMaps) {
        final point = RoutePoint.fromMap(map);
        (pointsByTripId[point.tripId] ??= <RoutePoint>[]).add(point);
      }

      return tripMaps.map((tripMap) {
        final tripId = tripMap['id'] as int;
        final points = pointsByTripId[tripId] ?? const <RoutePoint>[];
        return Trip.fromMap(tripMap, points);
      }).toList();
    } catch (e) {
      throw TripRepositoryException('Failed to get trips by date range: $e');
    }
  }

  /// Get trips by activity type
  Future<List<Trip>> getTripsByActivity(ActivityType activity) async {
    try {
      final tripMaps = await _db.query(
        'trips',
        where: 'detected_activity = ? AND $_completedFilter',
        whereArgs: [activity.name, ..._completedArgs],
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
        where: 'user_confirmed = ? AND $_completedFilter',
        whereArgs: [1, ..._completedArgs],
        orderBy: 'start_time DESC',
      );

      return tripMaps.map((map) => Trip.fromMap(map, [])).toList();
    } catch (e) {
      throw TripRepositoryException('Failed to get confirmed trips: $e');
    }
  }

  /// Get every trip with the given [status], oldest first.
  ///
  /// Deliberately unfiltered by [_completedFilter]: this is the seam the
  /// startup recovery uses to find recordings an app kill left `active`.
  /// Route points are not loaded (callers fetch them per trip).
  Future<List<Trip>> getTripsByStatus(TripStatus status) async {
    try {
      final tripMaps = await _db.query(
        'trips',
        where: 'status = ?',
        whereArgs: [status.name],
        orderBy: 'start_time ASC',
      );

      return tripMaps.map((map) => Trip.fromMap(map, [])).toList();
    } catch (e) {
      throw TripRepositoryException('Failed to get trips by status: $e');
    }
  }

  /// Get trip count
  Future<int> getTripCount() async {
    try {
      final result = await _db.rawQuery(
        'SELECT COUNT(*) as count FROM trips WHERE $_completedFilter',
        _completedArgs,
      );
      return Sqflite.firstIntValue(result) ?? 0;
    } catch (e) {
      throw TripRepositoryException('Failed to get trip count: $e');
    }
  }

  /// Get total distance across all trips
  Future<double> getTotalDistance() async {
    try {
      final result = await _db.rawQuery(
        'SELECT SUM(distance) as total FROM trips WHERE $_completedFilter',
        _completedArgs,
      );
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
  TripRepositoryException(this.message);

  final String message;

  @override
  String toString() => 'TripRepositoryException: $message';
}
