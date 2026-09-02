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
  final List<int> deletedTripIds = [];
  final List<List<RoutePoint>> savedRoutePointBatches = [];

  int _nextId = 1;
  bool throwOnSaveRoutePoints = false;
  bool throwOnSaveTrip = false;

  /// Holds `saveTrip` open. The recorder publishes `_activeTrip` only from that
  /// future's result, so this is the exact window in which a second caller used
  /// to read `null` and write a second row (L-080).
  Completer<void>? saveTripGate;

  /// Pushes the started trip's `startTime` this far into the past.
  ///
  /// The recorder computes a ride's duration from the trip it got back from
  /// `saveTrip`, so backdating here is how a test gets a recording that is
  /// longer than `AppConstants.minTripDurationSeconds` without waiting a
  /// minute. Without it every test ride lasts 0 s and is (correctly) discarded.
  Duration? backdateStartBy;

  @override
  Future<Trip> saveTrip(Trip trip) async {
    if (throwOnSaveTrip) {
      throw TripRepositoryException('forced save failure');
    }
    await saveTripGate?.future;
    final backdate = backdateStartBy;
    final withId = trip.copyWith(
      id: _nextId++,
      startTime: backdate == null
          ? trip.startTime
          : trip.startTime.subtract(backdate),
    );
    savedTrips.add(withId);
    return withId;
  }

  @override
  Future<void> deleteTrip(int tripId) async {
    deletedTripIds.add(tripId);
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

  /// Every `discarded` flag the recorder passed to [stopTrip], newest last.
  /// A discarded ride must not trigger the "trip recorded" notification, and
  /// this flag is how the recorder says so.
  final List<bool> stopTripDiscardedFlags = [];

  /// Every `finalTrip` the recorder handed to [stopTrip], newest last. The
  /// notification is built from this, so it must carry the finalized metrics.
  final List<Trip?> stopTripFinalTrips = [];

  @override
  void stopTrip({bool discarded = false, Trip? finalTrip}) {
    stopTripDiscardedFlags.add(discarded);
    stopTripFinalTrips.add(finalTrip);
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
LocationData _fix(int latIndex, {double speed = 5.0, double accuracy = 5.0}) {
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
    int? tripId,
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
        locationStreamProvider.overrideWith(
          (ref, settings) => locationController.stream,
        ),
        // Inject the fake repository (provider is async -> return a Future).
        tripRepositoryProvider.overrideWith((ref) async => fakeRepository),
        // Mock NotificationService: the real TripStateMachine (used by the
        // recorder) triggers notifications on start/stop.
        notificationServiceProvider.overrideWith(_MockNotificationService.new),
        // Force location permission "denied" so the recorder's location stream
        // errors cleanly (handled by its onError) instead of hitting the
        // unavailable Geolocator plugin.
        locationPermissionServiceProvider.overrideWith(
          _MockLocationPermissionService.new,
        ),
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
    List<LocationData> priorLocations = const [],
  }) async {
    container.read(tripStateMachineProvider.notifier).startDetecting();
    await recorder.startRecording(
      confidenceScore: confidenceScore,
      activity: activity,
      priorLocations: priorLocations,
    );
    await pumpEventQueue();
  }

  group('TripRecorderService - lifecycle', () {
    test('build returns zeroed metrics', () async {
      final metrics = await container.read(tripRecorderServiceProvider.future);

      expect(metrics.distanceMeters, 0.0);
      expect(metrics.durationSeconds, 0);
      expect(metrics.routePointCount, 0);
      expect(metrics.avgSpeedKmh, isNull);
      expect(metrics.maxSpeedKmh, isNull);
    });

    test(
      'startRecording persists an initial trip and updates state machine',
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
      },
    );

    test('a second startRecording during the first one\'s database write is '
        'rejected (L-080)', () async {
      final recorder = await readRecorder();
      fakeRepository.saveTripGate = Completer<void>();
      container.read(tripStateMachineProvider.notifier).startDetecting();

      final first = recorder.startRecording(
        confidenceScore: 0.85,
        activity: ActivityType.cycling,
      );
      await pumpEventQueue();

      // Where trips 5 and 6 came from: `_activeTrip` is still null, the state
      // machine is still `detecting`, and the detector is still saying go.
      expect(fakeRepository.savedTrips, isEmpty);
      await expectLater(
        recorder.startRecording(
          confidenceScore: 0.85,
          activity: ActivityType.cycling,
        ),
        throwsStateError,
      );

      fakeRepository.saveTripGate!.complete();
      await first;
      await pumpEventQueue();

      expect(fakeRepository.savedTrips, hasLength(1));
      expect(container.read(tripStateMachineProvider).currentTripId, 1);
    });

    test('a rejected concurrent start does not release the first one\'s '
        'session (L-080)', () async {
      final recorder = await readRecorder();
      fakeRepository.saveTripGate = Completer<void>();
      container.read(tripStateMachineProvider.notifier).startDetecting();

      final first = recorder.startRecording(
        confidenceScore: 0.85,
        activity: ActivityType.cycling,
      );
      await pumpEventQueue();
      await expectLater(
        recorder.startRecording(
          confidenceScore: 0.85,
          activity: ActivityType.cycling,
        ),
        throwsStateError,
      );

      fakeRepository.saveTripGate!.complete();
      await first;
      await pumpEventQueue();

      // The rejection returns before the session is claimed, so its `catch`
      // cannot unpin the recording that is actually running: dropping every
      // external listener must still leave the same notifier alive.
      await dropExternalListeners();
      expect(
        container.read(tripRecorderServiceProvider.notifier),
        same(recorder),
      );
      expect(container.read(tripStateMachineProvider).isRecording, isTrue);
    });

    test('a failed start can be retried (L-080 guard releases)', () async {
      final recorder = await readRecorder();
      fakeRepository.throwOnSaveTrip = true;
      container.read(tripStateMachineProvider.notifier).startDetecting();

      await expectLater(
        recorder.startRecording(
          confidenceScore: 0.85,
          activity: ActivityType.cycling,
        ),
        throwsA(isA<TripRepositoryException>()),
      );

      fakeRepository.throwOnSaveTrip = false;
      await startTrip(recorder);

      expect(fakeRepository.savedTrips, hasLength(1));
      expect(container.read(tripStateMachineProvider).currentTripId, 1);
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

    test(
      'stopRecording with no active trip returns null and is a no-op',
      () async {
        final recorder = await readRecorder();
        final machine = container.read(
          tripStateMachineProvider.notifier,
        ) as _TestTripStateMachine;

        // A double tap on Stop, or the notification's Stop action on a trip the
        // coordinator already finalized, is an ordinary race — not an error to
        // throw at three call sites that all swallow it (L-074).
        await expectLater(recorder.stopRecording(), completion(isNull));
        expect(fakeRepository.savedTrips, isEmpty);
        expect(fakeRepository.updatedTrips, isEmpty);
        expect(machine.stopTripDiscardedFlags, isEmpty);
      },
    );

    test('stopRecording persists final trip and resets metrics', () async {
      final recorder = await readRecorder();

      // Long enough to be a real ride, and with enough route points to be one:
      // a 0 s recording is discarded (L-068) and a 0-point one is too (L-081),
      // both covered by their own group below.
      fakeRepository.backdateStartBy = const Duration(minutes: 5);
      await startTrip(recorder, confidenceScore: 0.9);
      await pushFix(_fix(0));
      await pushFix(_fix(2));

      final finalTrip = (await recorder.stopRecording())!;

      // Final trip persisted via updateTrip exactly once.
      expect(fakeRepository.updatedTrips, hasLength(1));
      final updated = fakeRepository.updatedTrips.first;
      expect(updated.id, 1);
      expect(updated.distance, closeTo(22.3, 1.0));
      expect(updated.maxSpeed, closeTo(18.0, 0.1));
      expect(
        updated.endTime.isAfter(updated.startTime) ||
            updated.endTime.isAtSameMomentAs(updated.startTime),
        isTrue,
      );

      expect(updated.status, TripStatus.completed);
      expect(fakeRepository.deletedTripIds, isEmpty);

      // Returned trip matches the persisted one.
      expect(finalTrip.id, updated.id);
      expect(finalTrip.distance, closeTo(22.3, 1.0));

      // The two points were flushed on the way out.
      expect(
        fakeRepository.savedRoutePointBatches.expand((b) => b),
        hasLength(2),
      );

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

    test('startRecording before the async build completes does not crash '
        '(regression: null-check on _repository, first on-device iOS run '
        '2026-09-01)', () async {
      // A repository that resolves slowly, like the real database open on a
      // fresh install — the recorder's build() is still awaiting it when the
      // manual start button fires.
      final slowContainer = ProviderContainer(
        overrides: [
          locationStreamProvider.overrideWith(
            (ref, settings) => locationController.stream,
          ),
          tripRepositoryProvider.overrideWith((ref) async {
            await Future<void>.delayed(const Duration(milliseconds: 200));
            return fakeRepository;
          }),
          notificationServiceProvider.overrideWith(
            _MockNotificationService.new,
          ),
          locationPermissionServiceProvider.overrideWith(
            _MockLocationPermissionService.new,
          ),
          tripStateMachineProvider.overrideWith(_TestTripStateMachine.new),
        ],
      );
      addTearDown(slowContainer.dispose);
      await slowContainer.read(settingsServiceProvider.future);
      // Same keep-alive pattern as readRecorder(): in the real app the
      // tracking screen and AutoDetectionController hold these listeners.
      final keepAlive = slowContainer.listen(
        tripRecorderServiceProvider,
        (_, _) {},
      );
      addTearDown(keepAlive.close);
      final keepAliveSm = slowContainer.listen(
        tripStateMachineProvider,
        (_, _) {},
      );
      addTearDown(keepAliveSm.close);

      // Deliberately NOT awaiting tripRecorderServiceProvider.future — the
      // manual-start path reads the notifier and calls startRecording right
      // after startDetecting, exactly as AutoDetectionController does.
      slowContainer.read(tripStateMachineProvider.notifier).startDetecting();
      await slowContainer
          .read(tripRecorderServiceProvider.notifier)
          .startRecording(confidenceScore: 1.0, activity: ActivityType.cycling);

      expect(fakeRepository.savedTrips, hasLength(1));
      expect(
        slowContainer.read(tripStateMachineProvider).hasActiveTrip,
        isTrue,
      );
      await slowContainer
          .read(tripRecorderServiceProvider.notifier)
          .stopRecording();
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

    test('the finalized trip carries the pause total (L-073)', () async {
      final recorder = await readRecorder();

      fakeRepository.backdateStartBy = const Duration(minutes: 5);
      await startTrip(recorder, confidenceScore: 0.9);
      await pushFix(_fix(0));
      await pushFix(_fix(2));

      // A real pause: paused, some wall-clock time passes, resumed.
      await recorder.pauseRecording();
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      await recorder.resumeRecording();

      final finalTrip = (await recorder.stopRecording())!;

      expect(finalTrip.pauseDuration, greaterThanOrEqualTo(1));
      expect(finalTrip.pauseDuration, lessThan(5));
      expect(
        fakeRepository.updatedTrips.single.pauseDuration,
        equals(finalTrip.pauseDuration),
        reason: 'the pause total must reach the database, not just the model',
      );

      // `duration` is the MOVING time, so the pause is out of it; the two
      // together account for the elapsed wall clock (± the 1 s rounding of
      // each counter).
      final elapsed = finalTrip.tripDuration.inSeconds;
      expect(finalTrip.duration, lessThanOrEqualTo(elapsed));
      expect(finalTrip.duration + finalTrip.pauseDuration, closeTo(elapsed, 1));
    });

    test('a trip with no pause records a zero pause total', () async {
      final recorder = await readRecorder();

      fakeRepository.backdateStartBy = const Duration(minutes: 5);
      await startTrip(recorder, confidenceScore: 0.9);
      await pushFix(_fix(0));
      await pushFix(_fix(2));

      final finalTrip = (await recorder.stopRecording())!;

      expect(finalTrip.pauseDuration, equals(0));
      expect(finalTrip.duration, equals(finalTrip.tripDuration.inSeconds));
    });

    test('a pause still open at stop is counted (L-073)', () async {
      final recorder = await readRecorder();

      fakeRepository.backdateStartBy = const Duration(minutes: 5);
      await startTrip(recorder, confidenceScore: 0.9);
      await pushFix(_fix(0));
      await pushFix(_fix(2));
      await recorder.pauseRecording();
      await Future<void>.delayed(const Duration(milliseconds: 1100));

      // Stopped without resuming first: the in-progress pause is closed by
      // the stop path itself.
      final finalTrip = (await recorder.stopRecording())!;

      expect(finalTrip.pauseDuration, greaterThanOrEqualTo(1));
    });

    test(
      'many short pauses do not inflate the moving time (rounding, L-073)',
      () async {
        final recorder = await readRecorder();

        fakeRepository.backdateStartBy = const Duration(minutes: 5);
        await startTrip(recorder, confidenceScore: 0.9);
        await pushFix(_fix(0));
        await pushFix(_fix(2));

        // Ten sub-second pauses. The old `+= pauseDuration.inSeconds` counted
        // every one of them as 0 s, so ~2 s of stopping vanished into the
        // moving time; keeping a Duration and rounding once recovers it.
        for (var i = 0; i < 10; i++) {
          await recorder.pauseRecording();
          await Future<void>.delayed(const Duration(milliseconds: 200));
          await recorder.resumeRecording();
        }

        final finalTrip = (await recorder.stopRecording())!;

        expect(
          finalTrip.pauseDuration,
          greaterThanOrEqualTo(1),
          reason: '10 x 200 ms of stopping must not round away to 0 s',
        );
      },
    );

    test('stop while paused still finalizes the trip', () async {
      final recorder = await readRecorder();

      fakeRepository.backdateStartBy = const Duration(minutes: 5);
      await startTrip(recorder, confidenceScore: 0.9);
      await pushFix(_fix(0));
      await pushFix(_fix(2));
      await recorder.pauseRecording();

      final finalTrip = (await recorder.stopRecording())!;

      expect(fakeRepository.updatedTrips, hasLength(1));
      expect(finalTrip.id, 1);
      expect(container.read(tripStateMachineProvider).hasActiveTrip, isFalse);
    });
  });

  group('TripRecorderService - a ride with no record of itself (L-081)', () {
    /// A recording long enough to pass the L-068 duration rule, so the point
    /// count is the only thing left deciding.
    Future<Trip> longRecording(
      TripRecorderService recorder, {
      List<LocationData> fixes = const [],
    }) async {
      fakeRepository.backdateStartBy = const Duration(minutes: 11);
      await startTrip(recorder, confidenceScore: 0.9);
      for (final fix in fixes) {
        await pushFix(fix);
      }
      return (await recorder.stopRecording())!;
    }

    test('a long recording that never got a fix is deleted, not saved', () async {
      final recorder = await readRecorder();

      // Trip 6 of the 2026-09-02 control run: 134 s, no fix at all, 0 m, and it
      // went into History as a ride.
      final finalTrip = await longRecording(recorder);

      expect(finalTrip.status, TripStatus.discarded);
      expect(fakeRepository.deletedTripIds, equals([1]));
      expect(fakeRepository.updatedTrips, isEmpty);
    });

    test('fixes the filters rejected do not count as a record of the ride', () async {
      final recorder = await readRecorder();

      // Trip 4: 627 s on one fix, and that fix read 100 m accuracy — dropped by
      // `maxLocationAccuracyMeters`, so nothing was ever recorded. Two fixes
      // here, only one of them usable: a counter that incremented before the
      // filters would read 2 and keep this recording, which is exactly the
      // mistake the count is meant to avoid.
      final finalTrip = await longRecording(
        recorder,
        fixes: [_fix(0), _fix(2, accuracy: 100.0)],
      );

      expect(finalTrip.status, TripStatus.discarded);
      expect(fakeRepository.deletedTripIds, equals([1]));
    });

    test('a single point is a position, not a ride', () async {
      final recorder = await readRecorder();

      final finalTrip = await longRecording(recorder, fixes: [_fix(0)]);

      expect(
        finalTrip.status,
        TripStatus.discarded,
        reason:
            'one point yields 0 m — the same nothing, and the recovery '
            'path has always refused to rebuild a ride from fewer than two',
      );
    });

    test('two points are enough, however short the distance', () async {
      final recorder = await readRecorder();

      // Deliberately not a distance rule: this is 22 m, well under anything one
      // would call a ride, and it is kept.
      final finalTrip = await longRecording(
        recorder,
        fixes: [_fix(0), _fix(2)],
      );

      expect(finalTrip.status, TripStatus.completed);
      expect(fakeRepository.deletedTripIds, isEmpty);
      expect(fakeRepository.updatedTrips, hasLength(1));
    });

    test('fixes the distance filter dropped do not count either', () async {
      final recorder = await readRecorder();

      // `minRoutePointDistanceMeters` rejects the majority of fixes on a real
      // ride, so it is the filter most likely to make an honest recording look
      // like an empty one: three fixes, two of them within the filter, one
      // point kept.
      final finalTrip = await longRecording(
        recorder,
        fixes: [_fix(0), _fix(0), _fix(0)],
      );

      expect(finalTrip.status, TripStatus.discarded);
    });

    test('a ride recorded entirely from the pre-trip buffer is kept (L-076)', () async {
      final recorder = await readRecorder();
      fakeRepository.backdateStartBy = const Duration(minutes: 11);
      container.read(tripStateMachineProvider.notifier).startDetecting();

      // The replayed prefix goes through `_recordLocation` like a live fix, so
      // it counts. A departure confirmed late — the whole ride already in the
      // buffer and no live fix after it — must not be thrown away by the new
      // rule.
      await recorder.startRecording(
        confidenceScore: 0.9,
        activity: ActivityType.cycling,
        priorLocations: [_fix(0), _fix(2), _fix(4)],
      );
      await pumpEventQueue();

      final finalTrip = (await recorder.stopRecording())!;

      expect(finalTrip.status, TripStatus.completed);
      expect(fakeRepository.deletedTripIds, isEmpty);
    });

    test('the count does not leak from one recording to the next', () async {
      final recorder = await readRecorder();

      // Trip 1: a real ride.
      await longRecording(recorder, fixes: [_fix(0), _fix(2)]);
      expect(fakeRepository.deletedTripIds, isEmpty);

      // Trip 2 on the same recorder, with no fix at all. It must be judged on
      // its own points, not on the ones trip 1 collected.
      final second = await longRecording(recorder);

      expect(second.status, TripStatus.discarded);
      expect(fakeRepository.deletedTripIds, equals([2]));
    });

    test('the count survives a flush, so a long ride is not discarded at the '
        'end of it', () async {
      final recorder = await readRecorder();
      fakeRepository.backdateStartBy = const Duration(minutes: 11);
      await startTrip(recorder, confidenceScore: 0.9);

      // Enough fixes to empty the buffer at least once: the count the discard
      // decision reads must be cumulative, not the buffer's length, which is 0
      // for most of a real ride.
      for (var i = 0; i <= AppConstants.routePointBufferSize * 2; i += 2) {
        await pushFix(_fix(i));
      }
      expect(fakeRepository.savedRoutePointBatches, isNotEmpty);

      final finalTrip = (await recorder.stopRecording())!;

      expect(finalTrip.status, TripStatus.completed);
      expect(fakeRepository.deletedTripIds, isEmpty);
    });

    test(
      'the live metrics report the ride\'s points, not the buffer\'s',
      () async {
        final recorder = await readRecorder();
        await startTrip(recorder);

        for (var i = 0; i <= AppConstants.routePointBufferSize * 2; i += 2) {
          await pushFix(_fix(i));
        }

        // Before this counter existed the UI read `_routePointBuffer.length`,
        // which sawtooths back to zero on every flush.
        final metrics = container.read(tripRecorderServiceProvider).value!;
        expect(metrics.routePointCount, AppConstants.routePointBufferSize + 1);
      },
    );
  });

  group('TripRecorderService - short trips are discarded (L-068)', () {
    test(
      'a recording under the minimum duration is deleted, not saved',
      () async {
        final recorder = await readRecorder();

        await startTrip(recorder, confidenceScore: 0.9);
        final finalTrip = (await recorder.stopRecording())!;

        // Nothing was kept: the row (and its route points, by cascade) is gone.
        expect(fakeRepository.deletedTripIds, equals([1]));
        expect(fakeRepository.updatedTrips, isEmpty);
        expect(finalTrip.status, TripStatus.discarded);
        expect(finalTrip.isRideWorthKeeping(0), isFalse);
      },
    );

    test(
      'a discarded trip does not fire the "trip recorded" notification',
      () async {
        final recorder = await readRecorder();
        final machine = container.read(
          tripStateMachineProvider.notifier,
        ) as _TestTripStateMachine;

        await startTrip(recorder, confidenceScore: 0.9);
        await recorder.stopRecording();

        expect(machine.stopTripDiscardedFlags, equals([true]));
      },
    );

    test(
      'the state machine is handed the finalized metrics, not the reset ones',
      () async {
        final recorder = await readRecorder();
        final machine = container.read(
          tripStateMachineProvider.notifier,
        ) as _TestTripStateMachine;

        fakeRepository.backdateStartBy = const Duration(minutes: 5);
        await startTrip(recorder, confidenceScore: 0.9);
        await pushFix(_fix(0));
        await pushFix(_fix(2)); // ~22 m further north

        final returned = (await recorder.stopRecording())!;

        // The trip handed over is the one written to the database, complete
        // with its distance and its active (pause-excluded) duration — not the
        // recorder's live metrics, which are zeroed by this point (L-069).
        final handed = machine.stopTripFinalTrips.single;
        expect(handed, isNotNull);
        expect(handed, same(returned));
        expect(handed!.distance, greaterThan(0.0));
        expect(
          handed.distance,
          equals(fakeRepository.updatedTrips.single.distance),
        );
        expect(handed.duration, equals(returned.duration));
        expect(handed.duration, greaterThan(0));
        expect(handed.avgSpeed, isNotNull);

        // Meanwhile the recorder's own metrics really are back to zero.
        final metrics = container.read(tripRecorderServiceProvider).value!;
        expect(metrics.distanceMeters, 0.0);
        expect(metrics.durationSeconds, 0);
      },
    );

    test('a real ride is completed and does notify', () async {
      final recorder = await readRecorder();
      final machine = container.read(
        tripStateMachineProvider.notifier,
      ) as _TestTripStateMachine;

      fakeRepository.backdateStartBy = const Duration(minutes: 5);
      await startTrip(recorder, confidenceScore: 0.9);
      await pushFix(_fix(0));
      await pushFix(_fix(2));
      await recorder.stopRecording();

      expect(fakeRepository.deletedTripIds, isEmpty);
      expect(fakeRepository.updatedTrips.single.status, TripStatus.completed);
      expect(machine.stopTripDiscardedFlags, equals([false]));
    });

    test(
      'the trip is inserted as active so history ignores it mid-ride',
      () async {
        final recorder = await readRecorder();

        await startTrip(recorder, confidenceScore: 0.9);

        expect(fakeRepository.savedTrips.single.status, TripStatus.active);
      },
    );

    test(
      'the periodic flush snapshots the metrics onto the active row',
      () async {
        final recorder = await readRecorder();
        await startTrip(recorder);

        await pushFix(_fix(0));
        await pushFix(_fix(2));

        // What the 30 s flush timer calls.
        await recorder.debugFlushProgress();

        final snapshot = fakeRepository.updatedTrips.single;
        expect(snapshot.status, TripStatus.active);
        expect(snapshot.pauseDuration, equals(0));
        expect(snapshot.distance, closeTo(22.3, 1.0));
        expect(snapshot.maxSpeed, isNotNull);
        expect(snapshot.endTime.isAfter(snapshot.startTime), isTrue);
        expect(fakeRepository.savedRoutePointBatches.single, hasLength(2));
      },
    );

    test('the periodic flush snapshots the pause total too (L-073)', () async {
      final recorder = await readRecorder();
      fakeRepository.backdateStartBy = const Duration(minutes: 5);
      await startTrip(recorder);

      await recorder.pauseRecording();
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      await recorder.resumeRecording();

      await recorder.debugFlushProgress();

      final snapshot = fakeRepository.updatedTrips.last;
      expect(snapshot.status, TripStatus.active);
      expect(snapshot.pauseDuration, greaterThanOrEqualTo(1));
      expect(
        snapshot.duration + snapshot.pauseDuration,
        closeTo(snapshot.tripDuration.inSeconds, 1),
        reason: 'the interrupted-trip recovery relies on these adding up',
      );
    });

    test(
      'a snapshot taken mid-pause already counts the open pause (L-073)',
      () async {
        final recorder = await readRecorder();
        fakeRepository.backdateStartBy = const Duration(minutes: 5);
        await startTrip(recorder);

        await recorder.pauseRecording();
        await Future<void>.delayed(const Duration(milliseconds: 1100));

        // Killed while stopped at a light: this is the row recovery sees.
        await recorder.debugFlushProgress();

        final snapshot = fakeRepository.updatedTrips.last;
        expect(snapshot.pauseDuration, greaterThanOrEqualTo(1));
      },
    );
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

      final finalTrip = (await recorder.stopRecording())!;
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
      'retries it',
      () async {
        final recorder = await readRecorder();
        await startTrip(recorder);

        await pushFix(_fix(0));
        await pushFix(_fix(2));

        fakeRepository.throwOnSaveRoutePoints = true;
        final finalTrip = (await recorder.stopRecording())!;

        // Nothing persisted, but the trip itself was finalized.
        expect(fakeRepository.savedRoutePointBatches, isEmpty);
        expect(finalTrip.distance, closeTo(22.3, 1.0));

        // Next trip retries the buffered points, which carry the OLD trip id.
        fakeRepository.throwOnSaveRoutePoints = false;
        await startTrip(recorder);

        expect(fakeRepository.savedRoutePointBatches, hasLength(1));
        expect(fakeRepository.savedRoutePointBatches.first, hasLength(2));
        expect(
          fakeRepository.savedRoutePointBatches.first.every(
            (p) => p.tripId == 1,
          ),
          isTrue,
        );
      },
    );
  });

  group('TripRecorderService - session ownership (audit #2)', () {
    test('an active recording survives losing its last listener', () async {
      final recorder = await readRecorder();
      await startTrip(recorder);
      await pushFix(_fix(0));

      await dropExternalListeners();

      // Same notifier instance: the session keepAlive link held it.
      expect(
        container.read(tripRecorderServiceProvider.notifier),
        same(recorder),
      );

      // And it is still consuming GPS fixes.
      await pushFix(_fix(2));
      expect(currentDistance(), closeTo(22.3, 1.0));

      final finalTrip = (await recorder.stopRecording())!;
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

      expect(
        container.read(tripRecorderServiceProvider.notifier),
        same(recorder),
      );

      await pushFix(_fix(2));
      expect(currentDistance(), closeTo(22.3, 1.0));
    });

    test(
      'stopRecording releases the session so the provider can dispose',
      () async {
        final recorder = await readRecorder();
        await startTrip(recorder);
        await recorder.stopRecording();

        await dropExternalListeners();

        expect(
          container.read(tripRecorderServiceProvider.notifier),
          isNot(same(recorder)),
        );
      },
    );

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

      expect(
        container.read(tripRecorderServiceProvider.notifier),
        isNot(same(recorder)),
      );
    });
  });

  // -------------------------------------------------------------------------
  // Pre-trip replay (L-076)
  // -------------------------------------------------------------------------
  group('TripRecorderService - priorLocations replay', () {
    test('a prefixed trip starts with distance already on the clock', () async {
      final recorder = await readRecorder();

      // ~22 m apart each, so both gaps clear minRoutePointDistanceMeters.
      await startTrip(recorder, priorLocations: [_fix(0), _fix(2), _fix(4)]);

      // Two accumulated gaps of ~22.2 m.
      expect(currentDistance(), greaterThan(40.0));
      expect(currentDistance(), lessThan(50.0));
      expect(
        container.read(tripRecorderServiceProvider).value!.routePointCount,
        3,
      );
    });

    test('startTime becomes the first retained point timestamp', () async {
      final recorder = await readRecorder();

      await startTrip(recorder, priorLocations: [_fix(0), _fix(2)]);

      // Persisted right away, so a process death in the first 30 s still
      // recovers the real start.
      expect(fakeRepository.updatedTrips, hasLength(1));
      expect(fakeRepository.updatedTrips.single.startTime, _fix(0).timestamp);

      final finalTrip = (await recorder.stopRecording())!;
      expect(finalTrip.startTime, _fix(0).timestamp);
    });

    test('the prefixed points reach the database on the next flush', () async {
      final recorder = await readRecorder();

      await startTrip(recorder, priorLocations: [_fix(0), _fix(2), _fix(4)]);
      await recorder.debugFlushProgress();

      expect(fakeRepository.savedRoutePointBatches, hasLength(1));
      final batch = fakeRepository.savedRoutePointBatches.single;
      expect(batch, hasLength(3));
      expect(batch.every((point) => point.tripId == 1), isTrue);
      expect(batch.map((point) => point.timestamp), [
        _fix(0).timestamp,
        _fix(2).timestamp,
        _fix(4).timestamp,
      ]);
    });

    test('the live filters apply to the prefix too', () async {
      final recorder = await readRecorder();

      await startTrip(
        recorder,
        priorLocations: [
          // Rejected: accuracy above maxLocationAccuracyMeters. It must not
          // become the trip's start either.
          _fix(0, accuracy: AppConstants.maxLocationAccuracyMeters + 10),
          _fix(2),
          // Rejected: closer than minRoutePointDistanceMeters to the previous.
          _fix(3),
          // Rejected: faster than maxCyclingSpeedKmh (GPS outlier).
          _fix(6, speed: AppConstants.maxCyclingSpeedKmh),
          _fix(8),
        ],
      );

      expect(
        container.read(tripRecorderServiceProvider).value!.routePointCount,
        2,
      );
      expect(fakeRepository.updatedTrips.single.startTime, _fix(2).timestamp);
      // Only the 2 -> 8 gap (~66 m); the rejected points contribute nothing.
      expect(currentDistance(), greaterThan(60.0));
      expect(currentDistance(), lessThan(72.0));
    });

    test('replayed points are ordered chronologically', () async {
      final recorder = await readRecorder();

      await startTrip(recorder, priorLocations: [_fix(4), _fix(0), _fix(2)]);

      // `.first`: the flush below snapshots the row a second time.
      expect(fakeRepository.updatedTrips.first.startTime, _fix(0).timestamp);

      await recorder.debugFlushProgress();
      expect(
        fakeRepository.savedRoutePointBatches.single.map((p) => p.timestamp),
        [_fix(0).timestamp, _fix(2).timestamp, _fix(4).timestamp],
      );
    });

    test('the live stream continues from the last prefixed point', () async {
      final recorder = await readRecorder();

      await startTrip(recorder, priorLocations: [_fix(0), _fix(2)]);
      final prefixDistance = currentDistance();

      // Too close to the last prefixed fix: filtered, exactly as it would be
      // between two live fixes.
      await pushFix(_fix(3));
      expect(currentDistance(), prefixDistance);

      await pushFix(_fix(4));
      expect(currentDistance(), greaterThan(prefixDistance));
    });

    test('no priorLocations leaves the previous behaviour intact', () async {
      final recorder = await readRecorder();

      final before = DateTime.now();
      await startTrip(recorder);
      final after = DateTime.now();

      // No back-dating write, no points, no distance.
      expect(fakeRepository.updatedTrips, isEmpty);
      expect(currentDistance(), 0.0);
      expect(
        container.read(tripRecorderServiceProvider).value!.routePointCount,
        0,
      );

      final started = fakeRepository.savedTrips.single.startTime;
      expect(started.isBefore(before), isFalse);
      expect(started.isAfter(after), isFalse);
    });

    test('an all-rejected prefix leaves the start at now', () async {
      final recorder = await readRecorder();

      final before = DateTime.now();
      await startTrip(
        recorder,
        priorLocations: [
          _fix(0, accuracy: AppConstants.maxLocationAccuracyMeters + 1),
          _fix(2, accuracy: AppConstants.maxLocationAccuracyMeters + 1),
        ],
      );

      expect(fakeRepository.updatedTrips, isEmpty);
      expect(currentDistance(), 0.0);
      expect(
        fakeRepository.savedTrips.single.startTime.isBefore(before),
        isFalse,
      );
    });
  });
}
