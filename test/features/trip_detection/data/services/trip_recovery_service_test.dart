import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:autoride/core/constants/app_constants.dart';
import 'package:autoride/features/trip_detection/data/services/trip_recovery_service.dart';
import 'package:autoride/features/trip_detection/domain/models/activity_confidence.dart';
import 'package:autoride/features/trip_detection/domain/models/trip.dart';
import 'package:autoride/features/trip_history/data/repositories/trip_repository.dart';

import '../../../../helpers/test_database.dart';

/// These tests drive the real [TripRepository] against the production schema in
/// memory, so what they assert about recovery is what the app does on a real
/// database: statuses, cascade deletes and recomputed metrics included.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Database db;
  late TripRepository repository;
  late TripRecoveryService recovery;

  setUp(() async {
    db = await createTestDatabase();
    repository = TripRepository(db);
    recovery = TripRecoveryService(repository);
  });

  tearDown(() async {
    await db.close();
  });

  /// Base time all fixtures hang off, so durations are exact.
  final start = DateTime(2026, 9, 1, 8, 0, 0);

  Future<int> insertActiveTrip({
    DateTime? startTime,
    int pauseDuration = 0,
  }) async {
    final trip = Trip(
      startTime: startTime ?? start,
      // What `_startRecording` writes: end == start, no metrics yet.
      endTime: startTime ?? start,
      distance: 0.0,
      duration: 0,
      detectedActivity: ActivityType.cycling,
      confidenceScore: 0.8,
      status: TripStatus.active,
      pauseDuration: pauseDuration,
    );
    final saved = await repository.saveTrip(trip);
    return saved.id!;
  }

  /// Appends [count] points ~11.1 m apart, one per [spacing].
  Future<void> insertPoints(
    int tripId, {
    required int count,
    Duration spacing = const Duration(seconds: 10),
    double speed = 5.0,
  }) async {
    await repository.saveRoutePoints([
      for (var i = 0; i < count; i++)
        RoutePoint(
          tripId: tripId,
          latitude: 48.8566 + i * 0.0001,
          longitude: 2.3522,
          timestamp: start.add(spacing * i),
          accuracy: 5.0,
          speed: speed,
        ),
    ]);
  }

  group('TripRecoveryService.recoverInterruptedTrips', () {
    test('does nothing when no trip was interrupted', () async {
      final report = await recovery.recoverInterruptedTrips();

      expect(report.isEmpty, isTrue);
      expect(report.completed, isEmpty);
      expect(report.deleted, isEmpty);
    });

    test(
      'completes an interrupted trip with metrics from its points',
      () async {
        final tripId = await insertActiveTrip();
        // 10 points, 10 s apart -> 90 s span, ~100 m.
        await insertPoints(tripId, count: 10);

        final report = await recovery.recoverInterruptedTrips();

        expect(report.completed, hasLength(1));
        expect(report.deleted, isEmpty);
        expect(report.failed, 0);

        final recovered = (await repository.getTripById(tripId))!;
        expect(recovered.status, TripStatus.completed);
        expect(recovered.duration, 90, reason: '9 gaps of 10 s');
        expect(
          recovered.endTime,
          equals(start.add(const Duration(seconds: 90))),
          reason: 'the last point, not the time the app was reopened',
        );
        expect(recovered.distance, closeTo(100.0, 5.0));
        expect(recovered.maxSpeed, closeTo(18.0, 0.1)); // 5 m/s
        expect(
          recovered.avgSpeed,
          closeTo(recovered.distance / 90 * 3.6, 0.01),
        );
      },
    );

    test(
      'a recovered trip appears in history; an interrupted one does not',
      () async {
        final tripId = await insertActiveTrip();
        await insertPoints(tripId, count: 10);

        expect(
          await repository.getAllTrips(),
          isEmpty,
          reason: 'an active trip must never reach history',
        );

        await recovery.recoverInterruptedTrips();

        final history = await repository.getAllTrips();
        expect(history, hasLength(1));
        expect(history.single.id, tripId);
        expect(await repository.getTripCount(), 1);
      },
    );

    test('deletes an interrupted trip that has no points', () async {
      final tripId = await insertActiveTrip();

      final report = await recovery.recoverInterruptedTrips();

      expect(report.deleted, equals([tripId]));
      expect(report.completed, isEmpty);
      expect(await repository.getTripById(tripId), isNull);
    });

    test('deletes an interrupted trip with a single point', () async {
      final tripId = await insertActiveTrip();
      await insertPoints(tripId, count: 1);

      final report = await recovery.recoverInterruptedTrips();

      expect(report.deleted, equals([tripId]));
      expect(await repository.getTripById(tripId), isNull);
    });

    test(
      'deletes an interrupted trip shorter than the minimum, points and all',
      () async {
        final tripId = await insertActiveTrip();
        // 4 points 2 s apart -> a 6 s span, well under 60 s.
        await insertPoints(
          tripId,
          count: 4,
          spacing: const Duration(seconds: 2),
        );

        final report = await recovery.recoverInterruptedTrips();

        expect(report.deleted, equals([tripId]));
        expect(await repository.getTripById(tripId), isNull);
        expect(
          await db.query(
            'route_points',
            where: 'trip_id = ?',
            whereArgs: [tripId],
          ),
          isEmpty,
          reason: 'route_points cascade on the trip delete',
        );
      },
    );

    test(
      'an interrupted trip keeps its snapshotted pause total (L-073)',
      () async {
        // 20 points, 10 s apart: 190 s of elapsed ride, of which the recorder
        // had already snapshotted 100 s as stopped.
        final tripId = await insertActiveTrip(pauseDuration: 100);
        await insertPoints(tripId, count: 20);

        final report = await recovery.recoverInterruptedTrips();

        expect(report.completed, hasLength(1));
        final recovered = report.completed.single;
        expect(recovered.pauseDuration, equals(100));
        expect(recovered.duration, equals(190 - 100));

        // And it is what the database now holds, not just what was returned.
        final persisted = await repository.getTripById(tripId);
        expect(persisted!.pauseDuration, equals(100));
        expect(persisted.duration, equals(90));
        expect(persisted.status, TripStatus.completed);
      },
    );

    test('leaves completed trips untouched', () async {
      final finished = await repository.saveTrip(
        Trip(
          startTime: start,
          endTime: start.add(const Duration(minutes: 30)),
          distance: 8000.0,
          duration: 1800,
          detectedActivity: ActivityType.cycling,
          confidenceScore: 0.9,
          maxSpeed: 30.0,
        ),
      );

      final report = await recovery.recoverInterruptedTrips();

      expect(report.isEmpty, isTrue);
      final untouched = (await repository.getTripById(finished.id!))!;
      expect(untouched.distance, 8000.0);
      expect(untouched.duration, 1800);
      expect(untouched.status, TripStatus.completed);
    });

    test('handles several interrupted trips in one pass', () async {
      final keeper = await insertActiveTrip();
      await insertPoints(keeper, count: 10);
      final falseStart = await insertActiveTrip(
        startTime: start.add(const Duration(hours: 2)),
      );

      final report = await recovery.recoverInterruptedTrips();

      expect(report.completed.map((t) => t.id), equals([keeper]));
      expect(report.deleted, equals([falseStart]));
      expect(await repository.getAllTrips(), hasLength(1));
    });
  });

  group('TripRecoveryService.rebuildFromRoutePoints', () {
    Trip tripAt(DateTime startTime) => Trip(
      startTime: startTime,
      endTime: startTime,
      distance: 0.0,
      duration: 0,
      detectedActivity: ActivityType.cycling,
      confidenceScore: 0.8,
      status: TripStatus.active,
    );

    Trip pausedTripAt(DateTime startTime, int pauseSeconds) =>
        tripAt(startTime).copyWith(pauseDuration: pauseSeconds);

    RoutePoint point(int index, {double speed = 5.0}) => RoutePoint(
      tripId: 1,
      latitude: 48.8566 + index * 0.0001,
      longitude: 2.3522,
      timestamp: start.add(Duration(seconds: index * 10)),
      speed: speed,
    );

    test('returns null below two points', () {
      expect(
        TripRecoveryService.rebuildFromRoutePoints(tripAt(start), const []),
        isNull,
      );
      expect(
        TripRecoveryService.rebuildFromRoutePoints(tripAt(start), [point(0)]),
        isNull,
      );
    });

    test('orders points by timestamp before measuring', () {
      final shuffled = [point(2), point(0), point(1)];

      final rebuilt = TripRecoveryService.rebuildFromRoutePoints(
        tripAt(start),
        shuffled,
      )!;

      expect(rebuilt.endTime, equals(start.add(const Duration(seconds: 20))));
      expect(rebuilt.distance, closeTo(22.2, 1.0));
    });

    test('an unsnapshotted gap counts as ride time', () {
      // Nothing was snapshotted onto the row (pre-v3, or killed inside the
      // first 30 s), and a 10-minute gap between two points is
      // indistinguishable from a pause after the fact, so it counts as ride
      // time — the safe direction.
      final rebuilt = TripRecoveryService.rebuildFromRoutePoints(
        tripAt(start),
        [
          point(0),
          RoutePoint(
            tripId: 1,
            latitude: 48.8576,
            longitude: 2.3522,
            timestamp: start.add(const Duration(minutes: 10)),
            speed: 5.0,
          ),
        ],
      )!;

      expect(rebuilt.duration, 600);
      expect(rebuilt.pauseDuration, 0);
      expect(rebuilt.isRideWorthKeeping(2), isTrue);
    });

    test('subtracts the snapshotted pause total (L-073)', () {
      // The same 10-minute gap, but this time the recorder's 30 s flush had
      // written 8 minutes of pause onto the row before the process died.
      final rebuilt = TripRecoveryService.rebuildFromRoutePoints(
        pausedTripAt(start, 480),
        [
          point(0),
          RoutePoint(
            tripId: 1,
            latitude: 48.8576,
            longitude: 2.3522,
            timestamp: start.add(const Duration(minutes: 10)),
            speed: 5.0,
          ),
        ],
      )!;

      expect(rebuilt.duration, equals(600 - 480));
      expect(rebuilt.pauseDuration, equals(480));
      expect(rebuilt.duration + rebuilt.pauseDuration, equals(600));
    });

    test('avgSpeed is computed against the moving time (L-073)', () {
      final rebuilt = TripRecoveryService.rebuildFromRoutePoints(
        pausedTripAt(start, 100),
        [point(0), point(20)],
      )!;

      // 200 s elapsed, 100 s of it stopped.
      expect(rebuilt.duration, equals(100));
      expect(rebuilt.avgSpeed, closeTo((rebuilt.distance / 100) * 3.6, 0.001));
    });

    test('a pause longer than the surviving span is floored, not negative', () {
      // The snapshot can outlive the last route point that reached the disk.
      final rebuilt = TripRecoveryService.rebuildFromRoutePoints(
        pausedTripAt(start, 9999),
        [point(0), point(2)],
      )!;

      expect(rebuilt.duration, equals(0));
      expect(rebuilt.pauseDuration, equals(20));
      expect(rebuilt.isRideWorthKeeping(2), isFalse);
    });

    test('keeps the trip identity and marks it completed', () {
      final rebuilt = TripRecoveryService.rebuildFromRoutePoints(
        tripAt(start),
        [point(0), point(9)],
      )!;

      expect(rebuilt.status, TripStatus.completed);
      expect(rebuilt.pauseDuration, equals(0));
      expect(rebuilt.startTime, equals(start));
      expect(rebuilt.detectedActivity, ActivityType.cycling);
      expect(
        rebuilt.duration,
        greaterThanOrEqualTo(AppConstants.minTripDurationSeconds),
      );
    });
  });

  group('tripRecoveryProvider', () {
    test('runs the recovery once against the injected repository', () async {
      final tripId = await insertActiveTrip();
      await insertPoints(tripId, count: 10);

      final container = ProviderContainer(
        overrides: [
          tripRepositoryProvider.overrideWith((ref) async => repository),
        ],
      );
      addTearDown(container.dispose);

      final report = await container.read(tripRecoveryProvider.future);

      expect(report.completed, hasLength(1));
      expect(
        (await repository.getTripById(tripId))!.status,
        TripStatus.completed,
      );

      // Cached: a second read must not re-run the pass.
      final again = await container.read(tripRecoveryProvider.future);
      expect(identical(again, report), isTrue);
    });
  });
}
