import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:autoride/features/trip_history/data/repositories/trip_repository.dart';
import 'package:autoride/features/trip_detection/domain/models/trip.dart';
import 'package:autoride/features/trip_detection/domain/models/activity_confidence.dart';

import '../../../../helpers/test_database.dart';

void main() {
  // Initialize FFI for desktop testing
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Database db;
  late TripRepository repository;

  setUp(() async {
    // Create in-memory database to avoid file conflicts
    db = await createTestDatabase();
    repository = TripRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  // Helper function to create test trip
  Trip createTestTrip({
    DateTime? startTime,
    int durationSeconds = 3600,
    double distance = 5000.0,
    List<RoutePoint>? routePoints,
  }) {
    final start =
        startTime ?? DateTime.now().subtract(const Duration(hours: 1));
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

    test('should load route points for each trip in date range '
        'with correct association and order', () async {
      final base = DateTime(2026, 1, 1, 12);

      // Trip A: 3 route points (latitudes 1, 2, 3).
      final tripA = await repository.saveTrip(createTestTrip(startTime: base));
      // Trip B: 2 route points (latitudes 10, 11).
      final tripB = await repository.saveTrip(
        createTestTrip(startTime: base.add(const Duration(hours: 1))),
      );

      // Insert points out of timestamp order to verify ordering is applied.
      await repository.saveRoutePoints([
        RoutePoint(
          tripId: tripA.id!,
          latitude: 3.0,
          longitude: 0,
          timestamp: base.add(const Duration(minutes: 30)),
        ),
        RoutePoint(
          tripId: tripA.id!,
          latitude: 1.0,
          longitude: 0,
          timestamp: base.add(const Duration(minutes: 10)),
        ),
        RoutePoint(
          tripId: tripA.id!,
          latitude: 2.0,
          longitude: 0,
          timestamp: base.add(const Duration(minutes: 20)),
        ),
        RoutePoint(
          tripId: tripB.id!,
          latitude: 11.0,
          longitude: 0,
          timestamp: base.add(const Duration(minutes: 50)),
        ),
        RoutePoint(
          tripId: tripB.id!,
          latitude: 10.0,
          longitude: 0,
          timestamp: base.add(const Duration(minutes: 40)),
        ),
      ]);

      final trips = await repository.getTripsByDateRange(
        startDate: base.subtract(const Duration(days: 1)),
        endDate: base.add(const Duration(days: 1)),
        includeRoutePoints: true,
      );

      expect(trips, hasLength(2));

      final loadedA = trips.firstWhere((t) => t.id == tripA.id);
      final loadedB = trips.firstWhere((t) => t.id == tripB.id);

      // Correct count per trip.
      expect(loadedA.routePoints, hasLength(3));
      expect(loadedB.routePoints, hasLength(2));

      // Correct association: every point belongs to its own trip.
      expect(loadedA.routePoints.every((p) => p.tripId == tripA.id), isTrue);
      expect(loadedB.routePoints.every((p) => p.tripId == tripB.id), isTrue);

      // Correct order: points ordered by timestamp ASC within each trip.
      expect(
        loadedA.routePoints.map((p) => p.latitude).toList(),
        equals([1.0, 2.0, 3.0]),
      );
      expect(
        loadedB.routePoints.map((p) => p.latitude).toList(),
        equals([10.0, 11.0]),
      );
    });

    test('should get trips by activity type', () async {
      // Save trips with different activities
      await repository.saveTrip(createTestTrip());
      await repository.saveTrip(createTestTrip());
      final walkingTrip = createTestTrip().copyWith(
        detectedActivity: ActivityType.walking,
      );
      await repository.saveTrip(walkingTrip);

      final cyclingTrips = await repository.getTripsByActivity(
        ActivityType.cycling,
      );

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
      final updatedTrip = savedTrip.copyWith(distance: 10000.0, avgSpeed: 20.0);

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

  group('TripRepository - status filtering (L-068)', () {
    /// The row shape the recorder writes when a ride starts: 0 m / 0 s and
    /// `active`. Before L-068 these showed up in history as phantom trips.
    Future<Trip> saveActiveTrip({DateTime? startTime}) {
      final start = startTime ?? DateTime.now();
      return repository.saveTrip(
        Trip(
          startTime: start,
          endTime: start,
          distance: 0.0,
          duration: 0,
          detectedActivity: ActivityType.cycling,
          confidenceScore: 0.8,
          status: TripStatus.active,
        ),
      );
    }

    test('a trip defaults to completed and is visible', () async {
      final saved = await repository.saveTrip(createTestTrip());

      expect(saved.status, TripStatus.completed);
      expect(await repository.getAllTrips(), hasLength(1));
    });

    test('getAllTrips hides active and discarded trips', () async {
      await repository.saveTrip(createTestTrip());
      await saveActiveTrip();
      await repository.saveTrip(
        createTestTrip().copyWith(status: TripStatus.discarded),
      );

      final trips = await repository.getAllTrips();

      expect(trips, hasLength(1));
      expect(trips.single.status, TripStatus.completed);
    });

    test('every other list query hides them too', () async {
      final now = DateTime.now();
      await repository.saveTrip(
        createTestTrip(startTime: now).copyWith(userConfirmed: true),
      );
      await saveActiveTrip(startTime: now);

      expect(
        await repository.getTripsByActivity(ActivityType.cycling),
        hasLength(1),
      );
      expect(await repository.getConfirmedTrips(), hasLength(1));
      expect(
        await repository.getTripsByDateRange(
          startDate: now.subtract(const Duration(days: 1)),
          endDate: now.add(const Duration(days: 1)),
        ),
        hasLength(1),
      );
    });

    test('stats count only completed trips', () async {
      await repository.saveTrip(createTestTrip(distance: 5000.0));
      await saveActiveTrip();
      await repository.saveTrip(
        createTestTrip(distance: 9000.0).copyWith(status: TripStatus.discarded),
      );

      expect(await repository.getTripCount(), equals(1));
      expect(await repository.getTotalDistance(), equals(5000.0));
    });

    test(
      'getTripById still resolves an active trip (recovery needs it)',
      () async {
        final active = await saveActiveTrip();

        final fetched = await repository.getTripById(active.id!);

        expect(fetched, isNotNull);
        expect(fetched!.status, TripStatus.active);
      },
    );

    test(
      'getTripsByStatus returns only the requested status, oldest first',
      () async {
        final now = DateTime.now();
        await repository.saveTrip(createTestTrip());
        final second = await saveActiveTrip(startTime: now);
        final first = await saveActiveTrip(
          startTime: now.subtract(const Duration(hours: 3)),
        );

        final active = await repository.getTripsByStatus(TripStatus.active);

        expect(active.map((t) => t.id), equals([first.id, second.id]));
      },
    );
  });

  group('TripRepository - Error Handling', () {
    test('should throw TripRepositoryException on database errors', () async {
      // Close database to cause errors
      await db.close();

      final trip = createTestTrip();

      expect(
        () => repository.saveTrip(trip),
        throwsA(isA<TripRepositoryException>()),
      );
    });
  });
}
