import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:autoride/features/trip_detection/data/services/trip_recorder_service.dart';
import 'package:autoride/features/trip_detection/data/services/trip_state_machine.dart';
import 'package:autoride/features/trip_detection/data/services/notification_service.dart';
import 'package:autoride/features/trip_detection/data/services/location_permission_service.dart';
import 'package:autoride/features/trip_detection/domain/models/activity_confidence.dart';
import 'package:autoride/features/trip_detection/domain/models/trip.dart';
import 'package:autoride/features/trip_detection/domain/models/trip_state.dart';
import 'package:autoride/features/trip_history/data/repositories/trip_repository.dart';
import 'package:autoride/features/settings/data/services/settings_service.dart';

import '../../../../helpers/test_database.dart';

// ---------------------------------------------------------------------------
// COVERAGE NOTE / KNOWN LIMITATION
// ---------------------------------------------------------------------------
// TripRecorderService._startLocationStream() obtains its location source by
// calling the *top-level* function `locationStream(ref)` from
// location_service.dart directly (see trip_recorder_service.dart:265), NOT via
// `ref.watch(locationStreamProvider)`. Overriding `locationStreamProvider` on
// the ProviderContainer therefore has NO effect on the recorder: the raw
// function builds a real Geolocator stream that is unavailable in a unit-test
// environment.
//
// As a result the following behaviors CANNOT be unit-tested here without a
// production change (injecting the location stream through a provider the test
// can override):
//   * distance accumulation across points
//   * rejection of low-accuracy points (> maxLocationAccuracyMeters)
//   * speed-outlier rejection (> maxCyclingSpeedKmh)
//   * distance filter (skip points < minRoutePointDistanceMeters)
//   * max-speed tracking
//   * pause-excluded average speed (needs accumulated distance)
//   * route-point buffer flush at routePointBufferSize
//
// Everything reachable WITHOUT location injection is covered below:
//   * double-start StateError
//   * stopRecording with no active trip StateError
//   * pause / resume bookkeeping (no crash, state transitions)
//   * final trip persisted via repository.updateTrip on stop (zero points)
//   * buffer flush on stop is a no-op when buffer is empty (no saveRoutePoints)
//   * metrics reset after stop
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

  @override
  Future<Trip> saveTrip(Trip trip) async {
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

/// Mock LocationPermissionService that reports "denied" without touching the
/// Geolocator plugin.
///
/// Why this matters: the recorder's `_startLocationStream()` calls the
/// top-level `locationStream(ref)` which internally does
/// `ref.watch(locationPermissionServiceProvider.future)`. That provider IS
/// reachable via override (unlike the location *stream*, which the recorder
/// bypasses). By forcing a non-granted status, `locationStream` throws a
/// `LocationServiceException` *inside* its async* body, which the recorder's
/// stream `onError` handler swallows. No real plugin call ever happens, so the
/// start/stop lifecycle is exercisable. (See coverage note above for what this
/// still cannot test: actual location points.)
class _MockLocationPermissionService extends LocationPermissionService {
  @override
  Future<LocationPermissionStatus> build() async {
    return LocationPermissionStatus.denied;
  }
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

  setUp(() async {
    db = await createTestDatabase();
    fakeRepository = _FakeTripRepository(db);

    container = ProviderContainer(
      overrides: [
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
    await db.close();
  });

  /// Resolves the recorder notifier after its async build completes.
  ///
  /// Keeps the recorder and state-machine providers alive for the whole test
  /// (they are autoDispose) so transient reads + awaited event-queue pumps do
  /// not tear them down mid-test.
  Future<TripRecorderService> readRecorder() async {
    container.listen(tripRecorderServiceProvider, (_, _) {});
    container.listen(tripStateMachineProvider, (_, _) {});
    await container.read(tripRecorderServiceProvider.future);
    return container.read(tripRecorderServiceProvider.notifier);
  }

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
    // The recorder's location stream (built from the real top-level
    // locationStream function) emits a permission error asynchronously. Let it
    // drain so it is delivered to the recorder's still-attached onError handler
    // BEFORE the test ends and the subscription is cancelled on dispose;
    // otherwise the error escapes to the test zone as "uncaught".
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
}
