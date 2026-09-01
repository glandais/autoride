import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// `LocationSettings` only: geolocator also exports an `ActivityType` that
// collides with the domain model's.
import 'package:geolocator/geolocator.dart' show LocationSettings;
// `Override` is not re-exported by flutter_riverpod.
import 'package:riverpod_annotation/riverpod_annotation.dart' show Override;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:autoride/features/trip_detection/data/services/adaptive_location_settings.dart';
import 'package:autoride/features/trip_detection/data/services/battery_optimizer.dart';
import 'package:autoride/features/trip_detection/data/services/location_service.dart';
import 'package:autoride/features/trip_detection/data/services/sensor_service.dart';
import 'package:autoride/features/trip_detection/data/services/trip_detection_coordinator.dart';
import 'package:autoride/features/trip_detection/data/services/trip_start_detector.dart';
import 'package:autoride/features/trip_detection/data/services/trip_state_machine.dart';
import 'package:autoride/features/trip_detection/data/services/trip_stop_detector.dart';
import 'package:autoride/features/trip_detection/data/services/trip_recorder_service.dart';
import 'package:autoride/features/trip_detection/data/services/notification_service.dart';
import 'package:autoride/features/trip_detection/data/services/location_permission_service.dart';
import 'package:autoride/features/trip_detection/domain/models/activity_confidence.dart';
import 'package:autoride/features/trip_detection/domain/models/location_data.dart';
import 'package:autoride/features/trip_detection/domain/models/motion_data.dart';
import 'package:autoride/features/trip_detection/domain/models/trip.dart';
import 'package:autoride/features/trip_detection/domain/models/trip_start_state.dart';
import 'package:autoride/features/trip_detection/domain/models/trip_state.dart';
import 'package:autoride/features/trip_detection/domain/models/trip_stop_state.dart';

// ===========================================================================
// The coordinator now consumes motion and location through
// `motionDataStreamProvider` / `locationStreamProvider` (T041 / audit #5), so
// both can be replaced with test controllers via ProviderContainer overrides.
// That makes its decision-routing surface — previously 0 % covered (L-015) —
// directly exercisable: every private analyze* branch is driven by feeding a
// motion sample while the state machine sits in a chosen state.
//
// The detectors are replaced with scripted doubles on purpose: what is under
// test here is the coordinator's ROUTING (which collaborator it calls for a
// given state and decision), not the detection maths, which has its own tests
// in trip_start_detector_test.dart / trip_stop_detector_test.dart.
// ===========================================================================

/// State-machine double that performs transitions without reading other
/// providers (avoids the recorder<->machine circular dependency the production
/// machine would create; see trip_recorder_service_test.dart for details).
class _TestTripStateMachine extends TripStateMachine {
  @override
  TripState build() => const TripState.idle();

  @override
  void startDetecting() {
    state.mapOrNull(
      idle: (_) =>
          state = TripState.detecting(detectionStartTime: DateTime.now()),
    );
  }

  @override
  void startTripWithId(int tripId) {
    state.mapOrNull(
      detecting: (_) =>
          state = TripState.active(tripId: tripId, startTime: DateTime.now()),
    );
  }

  @override
  void pauseTrip() {
    state.mapOrNull(
      active: (a) => state = TripState.paused(
        tripId: a.tripId,
        startTime: a.startTime,
        pauseStartTime: DateTime.now(),
      ),
    );
  }

  @override
  void resumeTrip() {
    state.mapOrNull(
      paused: (p) =>
          state = TripState.active(tripId: p.tripId, startTime: p.startTime),
    );
  }

  @override
  void stopTrip({bool discarded = false}) {
    state.mapOrNull(
      detecting: (_) => state = const TripState.idle(),
      active: (_) => state = const TripState.idle(),
      paused: (_) => state = const TripState.idle(),
    );
  }
}

/// Recorder double that records the calls the coordinator makes and drives the
/// state machine the way the real recorder does, without touching a database
/// or a location stream.
class _RecorderLog {
  final List<double> startedWithConfidence = [];
  final List<ActivityType> startedWithActivity = [];
  int stopCalls = 0;
  bool throwOnStart = false;
}

class _SpyTripRecorderService extends TripRecorderService {
  _SpyTripRecorderService(this.log);

  final _RecorderLog log;

  @override
  Future<TripMetrics> build() async {
    return const TripMetrics(
      distanceMeters: 0,
      durationSeconds: 0,
      routePointCount: 0,
    );
  }

  @override
  Future<void> startRecording({
    required double confidenceScore,
    required ActivityType activity,
  }) async {
    if (log.throwOnStart) {
      throw StateError('forced start failure');
    }
    log.startedWithConfidence.add(confidenceScore);
    log.startedWithActivity.add(activity);
    ref.read(tripStateMachineProvider.notifier).startTripWithId(1);
  }

  @override
  Future<Trip> stopRecording() async {
    log.stopCalls++;
    ref.read(tripStateMachineProvider.notifier).stopTrip();
    return Trip(
      id: 1,
      startTime: DateTime.now(),
      endTime: DateTime.now(),
      distance: 0,
      duration: 0,
      detectedActivity: ActivityType.cycling,
      confidenceScore: 0.9,
      routePoints: const [],
    );
  }
}

/// Start detector double with a scripted verdict.
class _StartDetectorScript {
  bool verdict = false;
  double reportedConfidence = 0.9;
  final List<LocationData?> seenLocations = [];
  int resetCalls = 0;
  int cooldownCalls = 0;
}

class _FakeTripStartDetector extends TripStartDetector {
  _FakeTripStartDetector(this.script);

  final _StartDetectorScript script;

  @override
  TripStartState build() => TripStartState.initial();

  @override
  Future<bool> analyzeForTripStart(
    MotionData motion,
    LocationData? location, {
    DateTime? now,
  }) async {
    script.seenLocations.add(location);
    state = state.copyWith(confidence: script.reportedConfidence);
    return script.verdict;
  }

  @override
  void reset() {
    script.resetCalls++;
    state = TripStartState.initial();
  }

  @override
  void activateCooldown() {
    script.cooldownCalls++;
  }
}

/// Stop detector double with a scripted decision.
class _StopDetectorScript {
  StopDecision decision = StopDecision.continueTrip;
  bool resumeVerdict = false;
  int resetCalls = 0;
}

class _FakeTripStopDetector extends TripStopDetector {
  _FakeTripStopDetector(this.script);

  final _StopDetectorScript script;

  @override
  TripStopState build() => TripStopState.initial();

  @override
  Future<StopDecision> analyzeForTripStop(
    MotionData motion,
    LocationData? location, {
    DateTime? now,
  }) async {
    return script.decision;
  }

  @override
  bool shouldResumeTrip(
    MotionData motion,
    LocationData? location, {
    DateTime? now,
  }) {
    return script.resumeVerdict;
  }

  @override
  void reset() {
    script.resetCalls++;
  }
}

/// Notification double that skips all plugin calls.
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

/// Permission double so nothing reaches the real Geolocator plugin.
class _MockLocationPermissionService extends LocationPermissionService {
  @override
  Future<LocationPermissionStatus> build() async {
    return LocationPermissionStatus.granted;
  }
}

/// Battery-optimizer double whose power mode can be changed at will, without
/// the battery_plus plugin.
class _FakeBatteryOptimizer extends BatteryOptimizer {
  @override
  Future<PowerModeConfig> build() async => PowerModeConfig.normal;

  void setMode(PowerModeConfig config) => state = AsyncValue.data(config);
}

/// Coordinator with a short GPS inactivity timeout so the gate's shutdown is
/// observable without a 30 s wait. Nothing else is overridden.
class _FastGateCoordinator extends TripDetectionCoordinator {
  static const timeout = Duration(milliseconds: 20);

  @override
  Duration get gpsInactivityTimeout => timeout;
}

/// Name of the current union case (the generated union classes are private).
String _stateName(TripState state) => state.map(
  idle: (_) => 'idle',
  detecting: (_) => 'detecting',
  active: (_) => 'active',
  paused: (_) => 'paused',
);

/// Motion sample with a unique timestamp so every emission notifies listeners
/// (Riverpod skips notifications for values that compare equal).
MotionData _motionSample(int index) {
  final timestamp = DateTime(2026, 1, 1).add(Duration(milliseconds: index));
  return MotionData(
    accelerometer: AccelerometerData(
      x: 3.0,
      y: 3.0,
      z: 10.0,
      timestamp: timestamp,
    ),
    gyroscope: GyroscopeData(x: 1.0, y: 0.5, z: 0.5, timestamp: timestamp),
    timestamp: timestamp,
  );
}

/// Motion sample a resting phone produces: gravity-only acceleration and no
/// rotation, so `MotionWindow.state` reads `stationary`.
MotionData _stationarySample(int index) {
  final timestamp = DateTime(2026, 1, 1).add(Duration(milliseconds: index));
  return MotionData(
    accelerometer: AccelerometerData(
      x: 0.0,
      y: 0.0,
      z: 9.8,
      timestamp: timestamp,
    ),
    gyroscope: GyroscopeData(x: 0.0, y: 0.0, z: 0.0, timestamp: timestamp),
    timestamp: timestamp,
  );
}

LocationData _location({double speed = 5.0, int index = 0}) {
  return LocationData(
    latitude: 48.8566 + index * 0.0002,
    longitude: 2.3522,
    accuracy: 5.0,
    altitude: 35.0,
    speed: speed,
    heading: 90.0,
    timestamp: DateTime(2026, 1, 1).add(Duration(seconds: index)),
  );
}

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({
      'tripNotificationsEnabled': true,
      'showOngoingNotification': true,
      'soundOnTripStartStop': false,
      'autoPauseEnabled': true,
      'minDistanceMeters': 500.0,
    });
  });

  late ProviderContainer container;
  late StreamController<MotionData> motionController;
  late StreamController<LocationData> locationController;
  late _RecorderLog recorder;
  late _StartDetectorScript startDetector;
  late _StopDetectorScript stopDetector;
  late ProviderSubscription<AsyncValue<TripState>> coordinatorSubscription;

  /// True while something is subscribed to the (overridden) location stream —
  /// i.e. while the coordinator's GPS gate is open.
  late bool gpsSubscribed;

  /// Number of times the location stream was (re)subscribed. A power-mode
  /// change rebuilds the provider, which increments this without the
  /// coordinator's session being interrupted.
  late int gpsSubscribeCount;

  List<Override> baseOverrides({
    Override? location,
    List<Override> extra = const [],
  }) => [
    motionDataStreamProvider.overrideWith((ref) => motionController.stream),
    location ??
        locationStreamProvider.overrideWith(
          (ref, settings) => locationController.stream,
        ),
    tripStateMachineProvider.overrideWith(_TestTripStateMachine.new),
    tripRecorderServiceProvider.overrideWith(
      () => _SpyTripRecorderService(recorder),
    ),
    tripStartDetectorProvider.overrideWith(
      () => _FakeTripStartDetector(startDetector),
    ),
    tripStopDetectorProvider.overrideWith(
      () => _FakeTripStopDetector(stopDetector),
    ),
    notificationServiceProvider.overrideWith(_MockNotificationService.new),
    locationPermissionServiceProvider.overrideWith(
      _MockLocationPermissionService.new,
    ),
    ...extra,
  ];

  setUp(() {
    gpsSubscribed = false;
    gpsSubscribeCount = 0;
    motionController = StreamController<MotionData>.broadcast();
    locationController = StreamController<LocationData>.broadcast(
      onListen: () {
        gpsSubscribed = true;
        gpsSubscribeCount++;
      },
      onCancel: () => gpsSubscribed = false,
    );
    recorder = _RecorderLog();
    startDetector = _StartDetectorScript();
    stopDetector = _StopDetectorScript();

    container = ProviderContainer(overrides: baseOverrides());
    coordinatorSubscription = container.listen(
      tripDetectionCoordinatorProvider,
      (_, _) {},
    );
  });

  tearDown(() async {
    container.dispose();
    await motionController.close();
    await locationController.close();
  });

  Future<TripDetectionCoordinator> readCoordinator() async {
    await container.read(tripDetectionCoordinatorProvider.future);
    return container.read(tripDetectionCoordinatorProvider.notifier);
  }

  /// Starts a listening session and lets the stream subscriptions settle.
  Future<TripDetectionCoordinator> startedCoordinator() async {
    final coordinator = await readCoordinator();
    await coordinator.startListening();
    await pumpEventQueue();
    return coordinator;
  }

  /// Pushes one motion sample and lets the coordinator process it.
  Future<void> pushMotion(int index) async {
    motionController.add(_motionSample(index));
    await pumpEventQueue();
  }

  group('TripDetectionCoordinator - build', () {
    test('initializes in idle state', () async {
      final state = await container.read(
        tripDetectionCoordinatorProvider.future,
      );

      state.when(
        idle: () => expect(true, isTrue),
        detecting: (_) => fail('Should be idle'),
        active: (_, _) => fail('Should be idle'),
        paused: (_, _, _) => fail('Should be idle'),
      );
    });

    test('coordinator does not auto-start a trip from build alone', () async {
      await readCoordinator();

      final tripState = container.read(tripStateMachineProvider);
      expect(tripState.isRecording, isFalse);
      expect(tripState.hasActiveTrip, isFalse);
    });
  });

  group('TripDetectionCoordinator - lifecycle', () {
    test('stopListening before any startListening is safe', () async {
      final coordinator = await readCoordinator();

      coordinator.stopListening();

      expect(container.read(tripDetectionCoordinatorProvider).hasValue, isTrue);
      expect(container.read(tripStateMachineProvider).hasActiveTrip, isFalse);
    });

    test(
      'repeated stopListening calls are safe (idempotent cleanup)',
      () async {
        final coordinator = await readCoordinator();

        coordinator.stopListening();
        coordinator.stopListening();

        expect(container.read(tripStateMachineProvider).hasActiveTrip, isFalse);
      },
    );
  });

  group('TripDetectionCoordinator - decision routing', () {
    test('idle: the first motion sample starts the detecting phase', () async {
      await startedCoordinator();

      await pushMotion(1);

      expect(_stateName(container.read(tripStateMachineProvider)), 'detecting');
      expect(startDetector.seenLocations, isNotEmpty);
    });

    test('location updates are handed to the start detector', () async {
      await startedCoordinator();

      // The GPS gate is closed until motion is detected (audit #3), so open it
      // with a moving sample before feeding a position.
      await pushMotion(1);

      locationController.add(_location(index: 1));
      await pumpEventQueue();

      await pushMotion(2);

      expect(startDetector.seenLocations.last, isNotNull);
      expect(startDetector.seenLocations.last!.speed, 5.0);
    });

    test(
      'positive start detection starts recording with the confidence score',
      () async {
        startDetector
          ..verdict = true
          ..reportedConfidence = 0.83;
        await startedCoordinator();

        await pushMotion(1);

        expect(recorder.startedWithConfidence, [0.83]);
        expect(recorder.startedWithActivity, [ActivityType.cycling]);
        expect(container.read(tripStateMachineProvider).currentTripId, 1);
      },
    );

    test(
      'a failing startRecording resets to idle and surfaces the error',
      () async {
        startDetector.verdict = true;
        recorder.throwOnStart = true;
        await startedCoordinator();

        await pushMotion(1);

        expect(_stateName(container.read(tripStateMachineProvider)), 'idle');
        expect(startDetector.resetCalls, greaterThan(0));
        expect(
          container.read(tripDetectionCoordinatorProvider).hasError,
          isTrue,
        );
      },
    );

    test('active + pauseTrip decision pauses the trip', () async {
      startDetector.verdict = true;
      await startedCoordinator();
      await pushMotion(1); // starts the trip -> active
      expect(_stateName(container.read(tripStateMachineProvider)), 'active');

      // No restart needed: the session keeps running across the trip start.
      stopDetector.decision = StopDecision.pauseTrip;
      await pushMotion(2);

      expect(_stateName(container.read(tripStateMachineProvider)), 'paused');
    });

    test('active + stopTrip decision finalizes the trip', () async {
      startDetector.verdict = true;
      await startedCoordinator();
      await pushMotion(1);

      stopDetector.decision = StopDecision.stopTrip;
      await pushMotion(2);

      expect(recorder.stopCalls, 1);
      expect(stopDetector.resetCalls, greaterThan(0));
      expect(_stateName(container.read(tripStateMachineProvider)), 'idle');
    });

    test(
      'paused + resume verdict resumes the trip and resets the detector',
      () async {
        startDetector.verdict = true;
        await startedCoordinator();
        await pushMotion(1);

        container.read(tripStateMachineProvider.notifier).pauseTrip();
        expect(_stateName(container.read(tripStateMachineProvider)), 'paused');

        stopDetector.resumeVerdict = true;
        await pushMotion(2);

        expect(_stateName(container.read(tripStateMachineProvider)), 'active');
        expect(stopDetector.resetCalls, greaterThan(0));
      },
    );

    test('paused + no resume + stopTrip decision finalizes the trip', () async {
      startDetector.verdict = true;
      await startedCoordinator();
      await pushMotion(1);

      container.read(tripStateMachineProvider.notifier).pauseTrip();

      stopDetector
        ..resumeVerdict = false
        ..decision = StopDecision.stopTrip;
      await pushMotion(2);

      expect(recorder.stopCalls, 1);
      expect(_stateName(container.read(tripStateMachineProvider)), 'idle');
    });

    // L-001: the coordinator used to suspend its streams the moment a trip
    // started, so nothing ever drove `_analyzeForTripStop` again — auto-pause
    // and auto-stop were unreachable in the shipped app.
    test(
      'motion keeps flowing after a trip starts, so auto-pause fires',
      () async {
        startDetector.verdict = true;
        await startedCoordinator();
        await pushMotion(1); // starts the trip
        expect(_stateName(container.read(tripStateMachineProvider)), 'active');

        // No restart, no manual intervention: a stationary run during the trip
        // reaches the stop detector and pauses it.
        stopDetector.decision = StopDecision.pauseTrip;
        motionController.add(_stationarySample(2));
        await pumpEventQueue();

        expect(_stateName(container.read(tripStateMachineProvider)), 'paused');
      },
    );

    test(
      'a trip that auto-stops returns the coordinator to detecting',
      () async {
        startDetector.verdict = true;
        await startedCoordinator();
        await pushMotion(1);

        stopDetector.decision = StopDecision.stopTrip;
        await pushMotion(2);
        expect(_stateName(container.read(tripStateMachineProvider)), 'idle');

        // The restart is scheduled 100 ms out.
        await Future<void>.delayed(const Duration(milliseconds: 150));
        await pumpEventQueue();

        startDetector.verdict = false;
        await pushMotion(3);
        expect(
          _stateName(container.read(tripStateMachineProvider)),
          'detecting',
        );
      },
    );

    test(
      'a motion stream error tears the session down and is surfaced',
      () async {
        await startedCoordinator();

        motionController.addError(StateError('sensor failure'));
        await pumpEventQueue();

        expect(
          container.read(tripDetectionCoordinatorProvider).hasError,
          isTrue,
        );

        // Session released: further samples are ignored.
        final before = startDetector.seenLocations.length;
        await pushMotion(1);
        expect(startDetector.seenLocations.length, before);
      },
    );
  });

  group('TripDetectionCoordinator - session ownership (audit #2)', () {
    test('an active session survives losing its last listener', () async {
      final coordinator = await startedCoordinator();

      // Simulate the tracking screen being unmounted / a tab switch.
      coordinatorSubscription.close();
      await pumpEventQueue();

      expect(
        container.read(tripDetectionCoordinatorProvider.notifier),
        same(coordinator),
      );

      // And it is still processing samples.
      await pushMotion(1);
      expect(_stateName(container.read(tripStateMachineProvider)), 'detecting');
    });

    // The user turning "Automatic detection" off mid-ride must not strand the
    // ride: the teardown waits for the trip to finish.
    test(
      'stopListening during a trip is deferred until the trip ends',
      () async {
        startDetector.verdict = true;
        final coordinator = await startedCoordinator();
        await pushMotion(1);
        expect(_stateName(container.read(tripStateMachineProvider)), 'active');

        coordinator.stopListening();
        await pumpEventQueue();

        // Still analyzing: auto-pause/auto-stop keep working.
        stopDetector.decision = StopDecision.pauseTrip;
        await pushMotion(2);
        expect(_stateName(container.read(tripStateMachineProvider)), 'paused');

        // The trip ends -> the deferred stop is honoured.
        stopDetector
          ..resumeVerdict = false
          ..decision = StopDecision.stopTrip;
        await pushMotion(3);
        expect(recorder.stopCalls, 1);

        await Future<void>.delayed(const Duration(milliseconds: 150));
        await pumpEventQueue();

        final before = startDetector.seenLocations.length;
        await pushMotion(4);
        expect(startDetector.seenLocations.length, before);
        expect(gpsSubscribed, isFalse);
      },
    );

    test('a manual stop also honours a deferred stopListening', () async {
      startDetector.verdict = true;
      final coordinator = await startedCoordinator();
      await pushMotion(1);

      coordinator.stopListening();
      await pumpEventQueue();

      // Stopped from the UI, not by the stop detector.
      await container
          .read(tripRecorderServiceProvider.notifier)
          .stopRecording();
      await pumpEventQueue();

      final before = startDetector.seenLocations.length;
      await pushMotion(2);
      expect(startDetector.seenLocations.length, before);
    });

    test(
      'stopListening releases the session so the provider can dispose',
      () async {
        final coordinator = await startedCoordinator();

        coordinator.stopListening();
        coordinatorSubscription.close();
        await pumpEventQueue();

        expect(
          container.read(tripDetectionCoordinatorProvider.notifier),
          isNot(same(coordinator)),
        );
      },
    );
  });

  // ===========================================================================
  // Motion-gated GPS (audit #3 / L-004).
  //
  // GPSController was deleted: it only flipped a private enum and had no
  // consumer. The gate now lives in the coordinator, which already owns both
  // inputs (motion samples and trip state). The behaviour the old
  // gps_controller_test.dart described — start on movement, stop after
  // `gpsInactivityTimeout` of stationary, idempotent start/stop — is asserted
  // here against the real GPS subscription instead of an enum field.
  // ===========================================================================
  group('TripDetectionCoordinator - motion-gated GPS (audit #3)', () {
    setUp(() {
      container.dispose();
      container = ProviderContainer(
        overrides: baseOverrides(
          extra: [
            tripDetectionCoordinatorProvider.overrideWith(
              _FastGateCoordinator.new,
            ),
          ],
        ),
      );
      coordinatorSubscription = container.listen(
        tripDetectionCoordinatorProvider,
        (_, _) {},
      );
    });

    /// Lets the fast inactivity timeout elapse.
    Future<void> waitOutInactivity() async {
      await Future<void>.delayed(_FastGateCoordinator.timeout * 3);
      await pumpEventQueue();
    }

    test('startListening alone does not subscribe to GPS', () async {
      await startedCoordinator();

      expect(gpsSubscribed, isFalse);
      expect(gpsSubscribeCount, 0);
    });

    test('stationary motion never opens the gate', () async {
      await startedCoordinator();

      motionController.add(_stationarySample(1));
      await pumpEventQueue();
      motionController.add(_stationarySample(2));
      await pumpEventQueue();

      expect(gpsSubscribed, isFalse);
    });

    test('moving motion opens the gate exactly once', () async {
      await startedCoordinator();

      await pushMotion(1);
      expect(gpsSubscribed, isTrue);

      // Repeated movement must not re-subscribe (the old controller's
      // "forceStartGPS is idempotent" case).
      await pushMotion(2);
      expect(gpsSubscribeCount, 1);
    });

    test(
      'the gate closes after gpsInactivityTimeout of stationary motion',
      () async {
        await startedCoordinator();
        await pushMotion(1);
        expect(gpsSubscribed, isTrue);

        motionController.add(_stationarySample(2));
        await pumpEventQueue();
        // Still open: the timeout has not elapsed yet.
        expect(gpsSubscribed, isTrue);

        await waitOutInactivity();

        expect(gpsSubscribed, isFalse);
      },
    );

    test('movement before the timeout elapses keeps the gate open', () async {
      await startedCoordinator();
      await pushMotion(1);

      motionController.add(_stationarySample(2));
      await pumpEventQueue();
      await pushMotion(3); // moving again: cancels the pending shutdown
      await waitOutInactivity();

      expect(gpsSubscribed, isTrue);
      expect(gpsSubscribeCount, 1);
    });

    test(
      'closing the gate drops the last fix so detection is motion-only',
      () async {
        await startedCoordinator();
        await pushMotion(1);
        locationController.add(_location(index: 1));
        await pumpEventQueue();
        await pushMotion(2);
        expect(startDetector.seenLocations.last, isNotNull);

        motionController.add(_stationarySample(3));
        await pumpEventQueue();
        await waitOutInactivity();
        motionController.add(_stationarySample(4));
        await pumpEventQueue();

        expect(startDetector.seenLocations.last, isNull);
      },
    );

    test('an active trip keeps GPS on regardless of stationary motion', () async {
      startDetector.verdict = true;
      await startedCoordinator();
      await pushMotion(1); // starts the trip
      expect(_stateName(container.read(tripStateMachineProvider)), 'active');

      // Go stationary: auto-pause/stop needs speed, so the gate must not close.
      expect(gpsSubscribed, isTrue);

      motionController.add(_stationarySample(2));
      await pumpEventQueue();
      await waitOutInactivity();

      expect(gpsSubscribed, isTrue);
    });

    test('stopListening closes the gate', () async {
      final coordinator = await startedCoordinator();
      await pushMotion(1);
      expect(gpsSubscribed, isTrue);

      coordinator.stopListening();
      await pumpEventQueue();

      expect(gpsSubscribed, isFalse);
    });
  });

  // ===========================================================================
  // Adaptive settings (audit #4 / L-006): the power mode must actually reach
  // the live location stream, and changing it must not drop the session.
  // ===========================================================================
  group('TripDetectionCoordinator - adaptive location settings (audit #4)', () {
    late List<LocationSettings> observedSettings;

    /// Change the power mode on the CURRENT optimizer instance: the whole
    /// battery -> settings -> location chain is autoDispose, so a stale
    /// reference kept across a gate close would be a disposed notifier.
    void setPowerMode(PowerModeConfig config) {
      (container.read(
        batteryOptimizerProvider.notifier,
      ) as _FakeBatteryOptimizer).setMode(config);
    }

    setUp(() {
      observedSettings = [];

      container.dispose();
      container = ProviderContainer(
        overrides: baseOverrides(
          // Mirrors production `locationStream`: the settings come from the
          // adaptive provider, so the stream is rebuilt on a power-mode change.
          location: locationStreamProvider.overrideWith((ref, settings) {
            observedSettings.add(
              settings ?? ref.watch(adaptiveLocationSettingsProvider),
            );
            return locationController.stream;
          }),
          extra: [
            batteryOptimizerProvider.overrideWith(_FakeBatteryOptimizer.new),
          ],
        ),
      );
      coordinatorSubscription = container.listen(
        tripDetectionCoordinatorProvider,
        (_, _) {},
      );
    });

    test(
      'the gated stream is configured from the current power mode',
      () async {
        await startedCoordinator();
        await pushMotion(1); // opens the gate

        expect(observedSettings, hasLength(1));
        expect(
          observedSettings.single.accuracy,
          PowerModeConfig.normal.locationAccuracy,
        );
        expect(
          observedSettings.single.distanceFilter,
          PowerModeConfig.normal.distanceFilter,
        );
        // Never a timeLimit on the continuous stream (L-009).
        expect(observedSettings.single.timeLimit, isNull);
      },
    );

    test('a power-mode change re-subscribes with new settings without losing '
        'the session', () async {
      final coordinator = await startedCoordinator();
      await pushMotion(1);
      expect(gpsSubscribed, isTrue);

      setPowerMode(PowerModeConfig.critical);
      await pumpEventQueue();

      expect(observedSettings, hasLength(2));
      expect(
        observedSettings.last.accuracy,
        PowerModeConfig.critical.locationAccuracy,
      );
      expect(
        observedSettings.last.distanceFilter,
        PowerModeConfig.critical.distanceFilter,
      );

      // Same coordinator, still gated on, still receiving fixes.
      expect(
        container.read(tripDetectionCoordinatorProvider.notifier),
        same(coordinator),
      );
      expect(gpsSubscribed, isTrue);

      locationController.add(_location(index: 2));
      await pumpEventQueue();
      await pushMotion(2);

      expect(startDetector.seenLocations.last, isNotNull);
    });

    test('a power-mode change does not interrupt an active trip', () async {
      startDetector.verdict = true;
      await startedCoordinator();
      await pushMotion(1);
      expect(_stateName(container.read(tripStateMachineProvider)), 'active');

      // Resume listening so the trip's GPS gate is open (the state the stop
      // detector runs in); that is when a power-mode change is disruptive.
      final coordinator = container.read(
        tripDetectionCoordinatorProvider.notifier,
      );
      await coordinator.startListening();
      await pumpEventQueue();
      expect(gpsSubscribed, isTrue);

      setPowerMode(PowerModeConfig.low);
      await pumpEventQueue();

      expect(_stateName(container.read(tripStateMachineProvider)), 'active');
      expect(container.read(tripStateMachineProvider).currentTripId, 1);
      expect(recorder.stopCalls, 0);
      expect(gpsSubscribed, isTrue);
      expect(
        observedSettings.last.distanceFilter,
        PowerModeConfig.low.distanceFilter,
      );
    });
  });
}
