import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:autoride/features/trip_detection/data/services/trip_recorder_service.dart';
import 'package:autoride/features/trip_detection/data/services/trip_state_machine.dart';
import 'package:autoride/features/trip_detection/data/services/notification_service.dart';
import 'package:autoride/features/trip_detection/data/services/location_permission_service.dart';
import 'package:autoride/features/trip_detection/data/services/location_service.dart';
import 'package:autoride/features/trip_detection/domain/models/location_data.dart';
import 'package:autoride/features/trip_detection/domain/models/activity_confidence.dart';
import 'package:autoride/features/trip_detection/domain/models/trip.dart';
import 'package:autoride/features/trip_detection/domain/models/trip_state.dart';
import 'package:autoride/features/trip_history/data/repositories/trip_repository.dart';
import 'package:autoride/features/settings/data/services/settings_service.dart';
import 'package:autoride/core/constants/app_constants.dart';

import '../../../../helpers/test_database.dart';

// ---------------------------------------------------------------------------
// NOTE (T041 / audit #5)
// ---------------------------------------------------------------------------
// TripRecorderService now subscribes to `locationStreamProvider` instead of
// calling the top-level `locationStream(ref)` function, so the whole location
// handling path — distance accumulation, accuracy/speed/distance filters, max
// speed, buffer flushing and the L-008 retry — is injectable and covered below
// via a ProviderContainer override.
// ---------------------------------------------------------------------------

/// Fake repository that captures persistence calls in memory.
///
/// Passes a real in-memory database to `super()` so the [TripRepository]
/// contract is satisfied, but overrides every method the recorder uses so the
/// underlying DB is never actually touched. This lets us assert exactly what
/// was saved/updated and assign deterministic IDs.
class _FakeTripRepository extends TripRepository {
  _FakeTripRepository(super.db);

  final List<Trip> savedTrips = [];
  final List<Trip> updatedTrips = [];
  final List<List<RoutePoint>> savedRoutePointBatches = [];

  int _nextId = 1;
  bool throwOnSaveRoutePoints = false;
  bool throwOnSaveTrip = false;

  @override
  Future<Trip> saveTrip(Trip trip) async {
    if (throwOnSaveTrip) {
      throw TripRepositoryException('forced save failure');
    }
    final withId = trip.copyWith(id: _nextId++);
    savedTrips.add(withId);
    return withId;
  }

  @override
  Future<void> updateTrip(Trip trip) async {
    updatedTrips.add(trip);
  }

  @override
  Future<void> saveRoutePoints(List<RoutePoint> points) async {
    if (throwOnSaveRoutePoints) {
      throw TripRepositoryException('forced failure');
    }
    // Copy the list because the recorder clears its buffer after this returns.
    savedRoutePointBatches.add(List<RoutePoint>.from(points));
  }
}

/// Test double for the state machine that performs the same state transitions
/// as the real one but WITHOUT reading other providers.
///
/// The production [TripStateMachine.stopTrip] (and startTripWithId) read
/// `tripRecorderServiceProvider` / `notificationServiceProvider`. Since the
/// recorder under test reads `tripStateMachineProvider.notifier` in its own
/// build, the real machine creates a circular provider dependency
/// (recorder -> machine -> recorder) that Riverpod rejects at runtime. This
/// double exposes the exact transition surface the recorder relies on
/// (startTripWithId / pauseTrip / resumeTrip / stopTrip) so we can still verify
/// the recorder's persistence and bookkeeping behavior.
class _TestTripStateMachine extends TripStateMachine {
  @override
  TripState build() => const TripState.idle();

  @override
  void startDetecting() {
    state.mapOrNull(
      idle: (_) {
        state = TripState.detecting(detectionStartTime: DateTime.now());
      },
    );
  }

  @override
  void startTripWithId(int tripId) {
    state.mapOrNull(
      detecting: (_) {
        state = TripState.active(tripId: tripId, startTime: DateTime.now());
      },
    );
  }

  @override
  void pauseTrip() {
    state.mapOrNull(
      active: (activeState) {
        state = TripState.paused(
          tripId: activeState.tripId,
          startTime: activeState.startTime,
          pauseStartTime: DateTime.now(),
        );
      },
    );
  }

  @override
  void resumeTrip() {
    state.mapOrNull(
      paused: (pausedState) {
        state = TripState.active(
          tripId: pausedState.tripId,
          startTime: pausedState.startTime,
        );
      },
    );
  }

  @override
  void stopTrip() {
    state.mapOrNull(
      detecting: (_) => state = const TripState.idle(),
      active: (_) => state = const TripState.idle(),
      paused: (_) => state = const TripState.idle(),
    );
  }
}

/// Mock LocationPermissionService so nothing reaches the Geolocator plugin even
/// if a code path bypasses the overridden location stream.
class _MockLocationPermissionService extends LocationPermissionService {
  @override
  Future<LocationPermissionStatus> build() async {
    return LocationPermissionStatus.granted;
  }
}

/// A GPS fix `latIndex` * ~11.1 m north of the reference point.
LocationData _fix(
  int latIndex, {
  double speed = 5.0,
  double accuracy = 5.0,
}) {
  return LocationData(
    latitude: 48.8566 + latIndex * 0.0001,
    longitude: 2.3522,
    accuracy: accuracy,
    altitude: 35.0,
    speed: speed,
    heading: 90.0,
    timestamp: DateTime(2026, 1, 1).add(Duration(seconds: latIndex)),
  );
}

/// Mock NotificationService that skips all plugin calls.
class _MockNotificationService extends NotificationService {
  @override
  Future<void> build() async {}

  @override
  Future<void> showTripStartNotification() async {}

  @override
  Future<void> showTripStopNotification({
    required double distance,
    required Duration duration,
    required double avgSpeed,
  }) async {}

  @override
  Future<void> cancelForegroundNotification() async {}
}

void main() {
  // FFI required for the in-memory database backing the fake repository.
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    SharedPreferences.setMockInitialValues({
      'tripNotificationsEnabled': true,
      'showOngoingNotification': true,
      'soundOnTripStartStop': false,
      'autoPauseEnabled': true,
      'minDistanceMeters': 500.0,
    });
  });

  late Database db;
  late _FakeTripRepository fakeRepository;
  late ProviderContainer container;
  late StreamController<LocationData> locationController;
  late List<ProviderSubscription<Object?>> externalListeners;

  setUp(() async {
    db = await createTestDatabase();
    fakeRepository = _FakeTripRepository(db);
    locationController = StreamController<LocationData>.broadcast();
    externalListeners = [];

    container = ProviderContainer(
      overrides: [
        // Inject the location stream the recorder subscribes to.
        locationStreamProvider
            .overrideWith((ref, settings) => locationController.stream),
        // Inject the fake repository (provider is async -> return a Future).
        tripRepositoryProvider.overrideWith((ref) async => fakeRepository),
        // Mock NotificationService: the real TripStateMachine (used by the
        // recorder) triggers notifications on start/stop.
        notificationServiceProvider.overrideWith(_MockNotificationService.new),
        // Force location permission "denied" so the recorder's location stream
        // errors cleanly (handled by its onError) instead of hitting the
        // unavailable Geolocator plugin.
        locationPermissionServiceProvider
            .overrideWith(_MockLocationPermissionService.new),
        // Break the recorder <-> state-machine circular provider dependency.
        tripStateMachineProvider.overrideWith(_TestTripStateMachine.new),
      ],
    );

    // Settings must be ready before notification-dependent code runs.
    await container.read(settingsServiceProvider.future);
  });

  tearDown(() async {
    container.dispose();
    await locationController.close();
    await db.close();
  });

  /// Resolves the recorder notifier after its async build completes.
  ///
  /// Keeps the recorder and state-machine providers alive for the whole test
  /// (they are autoDispose) so transient reads + awaited event-queue pumps do
  /// not tear them down mid-test.
  Future<TripRecorderService> readRecorder() async {
    externalListeners
      ..add(container.listen(tripRecorderServiceProvider, (_, _) {}))
      ..add(container.listen(tripStateMachineProvider, (_, _) {}));
    await container.read(tripRecorderServiceProvider.future);
    return container.read(tripRecorderServiceProvider.notifier);
  }

  /// Simulates the tracking screen unmounting / a tab switch: every listener
  /// outside the recorder's own session goes away.
  Future<void> dropExternalListeners() async {
    for (final subscription in externalListeners) {
      subscription.close();
    }
    externalListeners.clear();
    await pumpEventQueue();
  }

  /// Feeds one GPS fix through the overridden location stream.
  Future<void> pushFix(LocationData fix) async {
    locationController.add(fix);
    await pumpEventQueue();
  }

  double currentDistance() =>
      container.read(tripRecorderServiceProvider).value!.distanceMeters;

  /// Drives the (test) state machine into `detecting` so that the recorder's
  /// internal `startTripWithId` transition (which only fires from `detecting`)
  /// succeeds, then starts recording. Mirrors what the coordinator does in
  /// production before the recorder runs.
  Future<void> startTrip(
    TripRecorderService recorder, {
    double confidenceScore = 0.85,
    ActivityType activity = ActivityType.cycling,
  }) async {
    container.read(tripStateMachineProvider.notifier).startDetecting();
    await recorder.startRecording(
      confidenceScore: confidenceScore,
      activity: activity,
    );
    await pumpEventQueue();
  }

  group('TripRecorderService - lifecycle', () {
    test('build returns zeroed metrics', () async {
      final metrics =
          await container.read(tripRecorderServiceProvider.future);

      expect(metrics.distanceMeters, 0.0);
      expect(metrics.durationSeconds, 0);
      expect(metrics.routePointCount, 0);
      expect(metrics.avgSpeedKmh, isNull);
      expect(metrics.maxSpeedKmh, isNull);
    });

    test('startRecording persists an initial trip and updates state machine',
        () async {
      final recorder = await readRecorder();

      await startTrip(recorder, confidenceScore: 0.85);

      // Initial trip saved exactly once with an assigned ID.
      expect(fakeRepository.savedTrips, hasLength(1));
      final saved = fakeRepository.savedTrips.first;
      expect(saved.id, 1);
      expect(saved.detectedActivity, ActivityType.cycling);
      expect(saved.confidenceScore, 0.85);

      // State machine advanced to active with the DB id.
      final tripState = container.read(tripStateMachineProvider);
      expect(tripState.isRecording, isTrue);
      expect(tripState.currentTripId, 1);
    });

    test('double startRecording throws StateError', () async {
      final recorder = await readRecorder();

      await startTrip(recorder, confidenceScore: 0.7);

      expect(
        () => recorder.startRecording(
          confidenceScore: 0.7,
          activity: ActivityType.cycling,
        ),
        throwsStateError,
      );
    });

    test('stopRecording with no active trip throws StateError', () async {
      final recorder = await readRecorder();

      expect(recorder.stopRecording, throwsStateError);
    });

    test('stopRecording persists final trip and resets metrics', () async {
      final recorder = await readRecorder();

      await startTrip(recorder, confidenceScore: 0.9);

      final finalTrip = await recorder.stopRecording();

      // Final trip persisted via updateTrip exactly once.
      expect(fakeRepository.updatedTrips, hasLength(1));
      final updated = fakeRepository.updatedTrips.first;
      expect(updated.id, 1);
      // No location points were injected, so distance stays zero and
      // speed metrics remain null.
      expect(updated.distance, 0.0);
      expect(updated.maxSpeed, isNull);
      expect(updated.endTime.isAfter(updated.startTime) ||
          updated.endTime.isAtSameMomentAs(updated.startTime), isTrue);

      // Returned trip matches the persisted one.
      expect(finalTrip.id, updated.id);
      expect(finalTrip.distance, 0.0);

      // No route points were ever buffered, so none were flushed.
      expect(fakeRepository.savedRoutePointBatches, isEmpty);

      // State machine back to idle and UI metrics reset.
      final tripState = container.read(tripStateMachineProvider);
      expect(tripState.hasActiveTrip, isFalse);

      final metrics = container.read(tripRecorderServiceProvider).value!;
      expect(metrics.distanceMeters, 0.0);
      expect(metrics.durationSeconds, 0);
      expect(metrics.routePointCount, 0);
    });

    test('can start a new trip after stopping the previous one', () async {
      final recorder = await readRecorder();

      await startTrip(recorder, confidenceScore: 0.8);
      await recorder.stopRecording();

      // Second trip should succeed and get a fresh id.
      await startTrip(recorder, confidenceScore: 0.8);

      expect(fakeRepository.savedTrips, hasLength(2));
      expect(fakeRepository.savedTrips[1].id, 2);
      expect(container.read(tripStateMachineProvider).currentTripId, 2);
    });
  });

  group('TripRecorderService - pause/resume bookkeeping', () {
    test('pauseRecording before any trip is a no-op', () async {
      final recorder = await readRecorder();

      // Should not throw and should not change repository state.
      await recorder.pauseRecording();
      expect(fakeRepository.savedTrips, isEmpty);
    });

    test('resumeRecording before any trip is a no-op', () async {
      final recorder = await readRecorder();

      await recorder.resumeRecording();
      expect(fakeRepository.savedTrips, isEmpty);
    });

    test('pause then resume keeps trip active and recording', () async {
      final recorder = await readRecorder();

      await startTrip(recorder, confidenceScore: 0.9);

      await recorder.pauseRecording();
      // After pause the state machine should no longer report recording.
      expect(container.read(tripStateMachineProvider).isRecording, isFalse);
      expect(container.read(tripStateMachineProvider).hasActiveTrip, isTrue);

      await recorder.resumeRecording();
      // After resume it should be recording again.
      expect(container.read(tripStateMachineProvider).isRecording, isTrue);
    });

    test('stop while paused still finalizes the trip', () async {
      final recorder = await readRecorder();

      await startTrip(recorder, confidenceScore: 0.9);
      await recorder.pauseRecording();

      final finalTrip = await recorder.stopRecording();

      expect(fakeRepository.updatedTrips, hasLength(1));
      expect(finalTrip.id, 1);
      expect(container.read(tripStateMachineProvider).hasActiveTrip, isFalse);
    });
  });

  group('TripRecorderService - location handling', () {
    test('accumulates distance across accepted fixes', () async {
      final recorder = await readRecorder();
      await startTrip(recorder);

      // ~11.1 m per 0.0001 degree of latitude, so 2 steps is ~22.3 m: above
      // AppConstants.minRoutePointDistanceMeters (15 m).
      await pushFix(_fix(0));
      expect(currentDistance(), 0.0, reason: 'first fix has no predecessor');

      await pushFix(_fix(2));
      expect(currentDistance(), closeTo(22.3, 1.0));

      await pushFix(_fix(4));
      expect(currentDistance(), closeTo(44.5, 1.5));
    });

    test('skips fixes closer than minRoutePointDistanceMeters', () async {
      final recorder = await readRecorder();
      await startTrip(recorder);

      await pushFix(_fix(0));
      await pushFix(_fix(1)); // ~11.1 m < 15 m -> GPS drift, ignored

      expect(currentDistance(), 0.0);
      expect(
        container.read(tripRecorderServiceProvider).value!.routePointCount,
        1,
      );
    });

    test('rejects fixes worse than maxLocationAccuracyMeters', () async {
      final recorder = await readRecorder();
      await startTrip(recorder);

      await pushFix(_fix(0));
      await pushFix(_fix(4, accuracy: 100.0)); // > 50 m accuracy

      expect(currentDistance(), 0.0);
      expect(
        container.read(tripRecorderServiceProvider).value!.routePointCount,
        1,
      );
    });

    test('rejects speed outliers above maxCyclingSpeedKmh', () async {
      final recorder = await readRecorder();
      await startTrip(recorder);

      await pushFix(_fix(0));
      await pushFix(_fix(4, speed: 20.0)); // 72 km/h > 60 km/h

      expect(currentDistance(), 0.0);
    });

    test('tracks max speed across accepted fixes', () async {
      final recorder = await readRecorder();
      await startTrip(recorder);

      await pushFix(_fix(0, speed: 4.0)); // 14.4 km/h
      await pushFix(_fix(2, speed: 8.0)); // 28.8 km/h
      await pushFix(_fix(4, speed: 5.0)); // 18.0 km/h

      final metrics = container.read(tripRecorderServiceProvider).value!;
      expect(metrics.maxSpeedKmh, closeTo(28.8, 0.1));

      final finalTrip = await recorder.stopRecording();
      expect(finalTrip.maxSpeed, closeTo(28.8, 0.1));
      expect(finalTrip.distance, closeTo(44.5, 1.5));
    });

    test('does not record fixes while the trip is paused', () async {
      final recorder = await readRecorder();
      await startTrip(recorder);

      await pushFix(_fix(0));
      await recorder.pauseRecording();
      await pushFix(_fix(4));

      expect(currentDistance(), 0.0);
    });

    test('flushes the buffer once it reaches routePointBufferSize', () async {
      final recorder = await readRecorder();
      await startTrip(recorder);

      for (var i = 0; i <= AppConstants.routePointBufferSize; i++) {
        locationController.add(_fix(i * 2));
      }
      await pumpEventQueue();

      expect(fakeRepository.savedRoutePointBatches, hasLength(1));
      expect(
        fakeRepository.savedRoutePointBatches.first,
        hasLength(AppConstants.routePointBufferSize),
      );
    });

    test('final flush on stop persists the tail of the ride', () async {
      final recorder = await readRecorder();
      await startTrip(recorder);

      await pushFix(_fix(0));
      await pushFix(_fix(2));

      await recorder.stopRecording();

      expect(fakeRepository.savedRoutePointBatches, hasLength(1));
      expect(fakeRepository.savedRoutePointBatches.first, hasLength(2));
      expect(
        fakeRepository.savedRoutePointBatches.first.every((p) => p.tripId == 1),
        isTrue,
      );
    });

    test(
        'L-008: a failing final flush keeps the tail buffered and the next trip '
        'retries it', () async {
      final recorder = await readRecorder();
      await startTrip(recorder);

      await pushFix(_fix(0));
      await pushFix(_fix(2));

      fakeRepository.throwOnSaveRoutePoints = true;
      final finalTrip = await recorder.stopRecording();

      // Nothing persisted, but the trip itself was finalized.
      expect(fakeRepository.savedRoutePointBatches, isEmpty);
      expect(finalTrip.distance, closeTo(22.3, 1.0));

      // Next trip retries the buffered points, which carry the OLD trip id.
      fakeRepository.throwOnSaveRoutePoints = false;
      await startTrip(recorder);

      expect(fakeRepository.savedRoutePointBatches, hasLength(1));
      expect(fakeRepository.savedRoutePointBatches.first, hasLength(2));
      expect(
        fakeRepository.savedRoutePointBatches.first.every((p) => p.tripId == 1),
        isTrue,
      );
    });
  });

  group('TripRecorderService - session ownership (audit #2)', () {
    test('an active recording survives losing its last listener', () async {
      final recorder = await readRecorder();
      await startTrip(recorder);
      await pushFix(_fix(0));

      await dropExternalListeners();

      // Same notifier instance: the session keepAlive link held it.
      expect(container.read(tripRecorderServiceProvider.notifier),
          same(recorder));

      // And it is still consuming GPS fixes.
      await pushFix(_fix(2));
      expect(currentDistance(), closeTo(22.3, 1.0));

      final finalTrip = await recorder.stopRecording();
      expect(finalTrip.distance, closeTo(22.3, 1.0));
    });

    test('L-010: a dependency change does not kill a live recording', () async {
      final recorder = await readRecorder();
      await startTrip(recorder);
      await pushFix(_fix(0));

      // Before the fix the recorder `watch`ed this provider inside a build that
      // registered its teardown, so invalidating it cancelled the location
      // subscription and both timers of a still-"active" trip.
      container.invalidate(tripRepositoryProvider);
      await pumpEventQueue();

      expect(container.read(tripRecorderServiceProvider.notifier),
          same(recorder));

      await pushFix(_fix(2));
      expect(currentDistance(), closeTo(22.3, 1.0));
    });

    test('stopRecording releases the session so the provider can dispose',
        () async {
      final recorder = await readRecorder();
      await startTrip(recorder);
      await recorder.stopRecording();

      await dropExternalListeners();

      expect(container.read(tripRecorderServiceProvider.notifier),
          isNot(same(recorder)));
    });

    test('a failed startRecording does not pin the session', () async {
      final recorder = await readRecorder();

      fakeRepository.throwOnSaveTrip = true;
      container.read(tripStateMachineProvider.notifier).startDetecting();
      await expectLater(
        recorder.startRecording(
          confidenceScore: 0.8,
          activity: ActivityType.cycling,
        ),
        throwsA(isA<TripRepositoryException>()),
      );

      await dropExternalListeners();

      expect(container.read(tripRecorderServiceProvider.notifier),
          isNot(same(recorder)));
    });
  });
}
