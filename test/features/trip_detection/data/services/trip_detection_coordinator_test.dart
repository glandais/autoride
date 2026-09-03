import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// `LocationSettings` only: geolocator also exports an `ActivityType` that
// collides with the domain model's.
import 'package:geolocator/geolocator.dart' show LocationSettings;
// `Override` is not re-exported by flutter_riverpod.
import 'package:riverpod_annotation/riverpod_annotation.dart' show Override;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:autoride/core/audit/audit_log.dart';
import 'package:autoride/core/audit/audit_sink.dart';
import 'package:autoride/core/constants/app_constants.dart';
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
  /// Drives `hasDetectionTimedOut` by hand. The production check measures
  /// `DateTime.now()` against `detectionTimeoutSeconds`, which no test can wait
  /// out; what the coordinator does *on* a timeout is the behaviour under test.
  bool forceDetectionTimeout = false;

  @override
  TripState build() => const TripState.idle();

  @override
  bool hasDetectionTimedOut() {
    return forceDetectionTimeout &&
        state.maybeMap(detecting: (_) => true, orElse: () => false);
  }

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
  void stopTrip({bool discarded = false, Trip? finalTrip}) {
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

  /// Pre-trip fixes handed over by the coordinator on each start (L-076).
  final List<List<LocationData>> startedWithPriorLocations = [];
  int stopCalls = 0;
  bool throwOnStart = false;

  /// Thrown by `startRecording` instead of the generic failure, so a test can
  /// script the recorder's own "someone else already owns this start"
  /// rejection (L-080) rather than a database error.
  Object? failStartWith;

  /// Holds `startRecording` open, the way the real one is held open by its
  /// `await saveTrip`. The window between the coordinator's decision and the
  /// state machine leaving `Detecting` is where the second trip of L-080 was
  /// born, and it exists only while that future is pending.
  Completer<void>? startGate;

  /// Makes `stopRecording` hand back a trip flagged `discarded`, as the real
  /// recorder does for a ride shorter than `minTripDurationSeconds` (L-068) or
  /// one with too few route points to be a record of anything (L-081).
  bool discardOnStop = false;

  /// Moving seconds carried by the trip `stopRecording` hands back. It is what
  /// separates the two discard reasons at the coordinator: only the short one
  /// is a false start.
  int durationOnStop = 0;
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
    List<LocationData> priorLocations = const [],
  }) async {
    if (log.throwOnStart) {
      throw StateError('forced start failure');
    }
    log.startedWithConfidence.add(confidenceScore);
    log.startedWithActivity.add(activity);
    log.startedWithPriorLocations.add(List<LocationData>.from(priorLocations));
    // Recorded before the wait, so a test can assert on the call while the
    // start is still in flight and the state machine still says `detecting`.
    await log.startGate?.future;
    final scripted = log.failStartWith;
    if (scripted != null) throw scripted;
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
      duration: log.durationOnStop,
      detectedActivity: ActivityType.cycling,
      confidenceScore: 0.9,
      status: log.discardOnStop ? TripStatus.discarded : TripStatus.completed,
      routePoints: const [],
    );
  }
}

/// Start detector double with a scripted verdict.
class _StartDetectorScript {
  bool verdict = false;
  double reportedConfidence = 0.9;

  /// Streak the double reports in its state. The coordinator opens the
  /// `Detecting` phase only once at least one detection has been counted
  /// (L-075), so 0 — the default — models a sample that scored below the
  /// confidence threshold.
  int countedDetections = 0;
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
    state = state.copyWith(
      confidence: script.reportedConfidence,
      consecutiveDetections: script.countedDetections,
    );
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

  /// Records the `tripIsPaused` flag of every `analyzeForTripStop` call, so a
  /// test can assert the paused path opts out of the movement hysteresis.
  final List<bool> analyzePausedFlags = <bool>[];
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
    bool tripIsPaused = false,
  }) async {
    script.analyzePausedFlags.add(tripIsPaused);
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
    int? tripId,
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

/// Timer double: never runs on the event loop, so the GPS gate's shutdown
/// happens exactly when the test asks for it.
class _ManualTimer implements Timer {
  _ManualTimer(this._onElapsed);

  final void Function() _onElapsed;
  bool _active = true;
  int _tick = 0;

  @override
  bool get isActive => _active;

  @override
  int get tick => _tick;

  @override
  void cancel() => _active = false;

  /// Fire as the real timer would: one-shot, and inert once cancelled.
  void fire() {
    if (!_active) return;
    _active = false;
    _tick++;
    _onElapsed();
  }
}

/// Coordinator whose GPS inactivity timeout never elapses on its own — the
/// test fires it through [fireInactivityTimeout]. Waiting out a shortened real
/// timeout instead made these tests race the event loop: the timeout could
/// elapse inside a `pumpEventQueue`, closing the gate before the assertion that
/// it is still open. Nothing else is overridden.
class _ManualGateCoordinator extends TripDetectionCoordinator {
  DateTime clock = DateTime(2026, 1, 1, 12);
  _ManualTimer? _lastTimer;

  /// The armed inactivity timer, or `null` if none was ever armed.
  _ManualTimer? get inactivityTimer => _lastTimer;

  /// Movable, like [_ScriptedCoordinator]'s: the motion window ages on this
  /// clock, so a test that wants a *windowed* stationary verdict has to let
  /// the earlier moving samples fall out of it.
  @override
  DateTime now() => clock;

  @override
  Timer startGpsInactivityTimer(void Function() onElapsed) {
    return _lastTimer = _ManualTimer(onElapsed);
  }

  void advance(Duration by) => clock = clock.add(by);
}

/// Start-detector double that reproduces just enough of the real streak rule
/// to make "one strong sample must not start a trip" observable at the
/// coordinator level: it says yes only on the
/// `tripStartMinConsecutiveDetections`-th sample, and [reset] clears the count.
class _StreakStartDetector extends TripStartDetector {
  _StreakStartDetector(this.script);

  final _StartDetectorScript script;

  int strongSamples = 0;

  @override
  TripStartState build() => TripStartState.initial();

  @override
  Future<bool> analyzeForTripStart(
    MotionData motion,
    LocationData? location, {
    DateTime? now,
  }) async {
    script.seenLocations.add(location);
    strongSamples++;
    state = state.copyWith(
      confidence: script.reportedConfidence,
      consecutiveDetections: strongSamples,
    );
    return strongSamples >= AppConstants.tripStartMinConsecutiveDetections;
  }

  @override
  void reset() {
    script.resetCalls++;
    strongSamples = 0;
    state = TripStartState.initial();
  }

  @override
  void activateCooldown() {
    script.cooldownCalls++;
  }
}

/// Coordinator with a frozen, movable clock and a hand-fired 1 Hz supervisor,
/// so the GPS-loss watchdog is asserted on state transitions instead of on ten
/// real minutes of wall clock. Same rationale as [_ManualGateCoordinator].
class _WatchdogCoordinator extends TripDetectionCoordinator {
  DateTime clock = DateTime(2026, 1, 1, 12);
  void Function()? _onTick;

  @override
  DateTime now() => clock;

  @override
  Timer startDetectionTimer(void Function() onTick) {
    _onTick = onTick;
    // Inert: nothing fires unless the test asks.
    return _ManualTimer(() {});
  }

  @override
  Timer startGpsInactivityTimer(void Function() onElapsed) =>
      _ManualTimer(onElapsed);

  /// Advance the clock as [by] would.
  void advance(Duration by) => clock = clock.add(by);

  /// Run one tick of the supervisor.
  void tick() => _onTick?.call();
}

/// Everything the audit assertions need in one double: a movable clock, a
/// hand-fired 1 Hz supervisor and an exposed GPS inactivity timer. The audit
/// group asserts on events that only exist at a timeout, so none of the three
/// may depend on real time.
class _ScriptedCoordinator extends TripDetectionCoordinator {
  DateTime clock = DateTime(2026, 1, 1, 12);
  void Function()? _onTick;
  _ManualTimer? _inactivityTimer;

  /// The armed GPS inactivity timer, or `null` if none was ever armed.
  _ManualTimer? get inactivityTimer => _inactivityTimer;

  @override
  DateTime now() => clock;

  @override
  Timer startDetectionTimer(void Function() onTick) {
    _onTick = onTick;
    return _ManualTimer(() {});
  }

  @override
  Timer startGpsInactivityTimer(void Function() onElapsed) =>
      _inactivityTimer = _ManualTimer(onElapsed);

  void advance(Duration by) => clock = clock.add(by);

  void tick() => _onTick?.call();
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
    Override? startDetectorOverride,
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
    startDetectorOverride ??
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

  /// Bring the *windowed* motion state to `stationary`.
  ///
  /// The gate averages over `stationaryWindowDuration` rather than trusting one
  /// sample, so a single calm reading right after movement does not — and must
  /// not — flip the verdict: that per-sample flapping is what kept GPS alive
  /// indefinitely. Advancing the clock past the window ages the moving samples
  /// out, which is what a rider actually coming to a halt does.
  ///
  /// A double with a movable clock gets the deterministic route: age the
  /// window out, then push one calm sample. Against the real coordinator the
  /// clock is wall time, so the window is instead *outweighed* — which is what
  /// a phone actually going still does, at the sensor rate, in well under the
  /// 1.5 s the window spans.
  Future<void> pushStationary(int index) async {
    final coordinator = container.read(
      tripDetectionCoordinatorProvider.notifier,
    );
    final advance =
        AppConstants.stationaryWindowDuration + const Duration(milliseconds: 1);

    if (coordinator is _ManualGateCoordinator) {
      coordinator.advance(advance);
    } else if (coordinator is _ScriptedCoordinator) {
      coordinator.advance(advance);
    } else {
      // One `_motionSample` carries 1.22 rad/s against a 0.2 rad/s ceiling, so
      // seven calm samples are what it takes to pull the mean under it.
      for (var i = 0; i < 7; i++) {
        motionController.add(_stationarySample(index * 100 + i));
        await pumpEventQueue();
      }
    }

    motionController.add(_stationarySample(index));
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
    test(
      'idle: a motion sample with no detection is analysed but stays idle',
      () async {
        await startedCoordinator();

        await pushMotion(1);

        // L-075: `Detecting` used to be entered on the first motion sample of
        // any kind, which put a merely-carried phone into a 30 s timeout cycle.
        expect(_stateName(container.read(tripStateMachineProvider)), 'idle');
        expect(startDetector.seenLocations, isNotEmpty);
      },
    );

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

    test(
      'the paused path tells the stop detector the trip is paused',
      () async {
        startDetector.verdict = true;
        await startedCoordinator();
        await pushMotion(1);

        // Active trip: the hysteresis stays enabled.
        stopDetector.decision = StopDecision.continueTrip;
        await pushMotion(2);
        expect(stopDetector.analyzePausedFlags, isNotEmpty);
        expect(stopDetector.analyzePausedFlags.last, isFalse);

        container.read(tripStateMachineProvider.notifier).pauseTrip();
        stopDetector.resumeVerdict = false;
        await pushMotion(3);

        // Paused trip: intermittent movement must not clear the pause (L-070).
        expect(stopDetector.analyzePausedFlags.last, isTrue);
      },
    );

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

        startDetector
          ..verdict = false
          ..countedDetections = 1;
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
      startDetector.countedDetections = 1;
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
              _ManualGateCoordinator.new,
            ),
          ],
        ),
      );
      coordinatorSubscription = container.listen(
        tripDetectionCoordinatorProvider,
        (_, _) {},
      );
    });

    /// The inactivity timer the coordinator armed, if any.
    _ManualTimer? armedInactivityTimer() {
      return (container.read(
        tripDetectionCoordinatorProvider.notifier,
      ) as _ManualGateCoordinator).inactivityTimer;
    }

    /// Makes the inactivity timeout elapse, deterministically. A cancelled or
    /// never-armed timer is a no-op, exactly like a real one.
    Future<void> elapseInactivity() async {
      armedInactivityTimer()?.fire();
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

        await pushStationary(2);
        // Still open: the timeout is armed but has not elapsed yet.
        expect(gpsSubscribed, isTrue);
        expect(armedInactivityTimer()?.isActive, isTrue);

        await elapseInactivity();

        expect(gpsSubscribed, isFalse);
      },
    );

    test('movement before the timeout elapses keeps the gate open', () async {
      await startedCoordinator();
      await pushMotion(1);

      await pushStationary(2);
      expect(armedInactivityTimer()?.isActive, isTrue);

      await pushMotion(3); // moving again: cancels the pending shutdown
      // Cancelled, not merely un-elapsed: firing it now must be a no-op.
      expect(armedInactivityTimer()?.isActive, isFalse);
      await elapseInactivity();

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

        await pushStationary(3);
        await elapseInactivity();
        await pushStationary(4);

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
      // No shutdown is even armed while a trip is being recorded.
      expect(armedInactivityTimer(), isNull);
      await elapseInactivity();

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

  group('TripDetectionCoordinator - GPS-loss auto-stop (L-074)', () {
    late _WatchdogCoordinator watchdog;

    setUp(() {
      container.dispose();
      container = ProviderContainer(
        overrides: baseOverrides(
          extra: [
            tripDetectionCoordinatorProvider.overrideWith(
              _WatchdogCoordinator.new,
            ),
          ],
        ),
      );
      coordinatorSubscription = container.listen(
        tripDetectionCoordinatorProvider,
        (_, _) {},
      );
    });

    /// Starts a session and a trip, and returns with the watchdog armed at the
    /// coordinator's frozen "now".
    Future<void> startTrip() async {
      startDetector.verdict = true;
      final coordinator = await startedCoordinator();
      watchdog = coordinator as _WatchdogCoordinator;
      await pushMotion(1);
      expect(_stateName(container.read(tripStateMachineProvider)), 'active');
    }

    Future<void> pushFix(int index) async {
      locationController.add(_location(index: index));
      await pumpEventQueue();
    }

    Future<void> tick() async {
      watchdog.tick();
      await pumpEventQueue();
    }

    test('a trip with no fix past the timeout is stopped', () async {
      await startTrip();

      watchdog.advance(
        AppConstants.gpsLossStopTimeout + const Duration(seconds: 1),
      );
      await tick();

      expect(recorder.stopCalls, 1);
      expect(_stateName(container.read(tripStateMachineProvider)), 'idle');
    });

    test('a trip that just started is not stopped before the timeout', () async {
      await startTrip();

      // The first fix legitimately takes a while; the grace period is the full
      // timeout, counted from the start of the trip.
      watchdog.advance(
        AppConstants.gpsLossStopTimeout - const Duration(seconds: 1),
      );
      await tick();

      expect(recorder.stopCalls, 0);
      expect(_stateName(container.read(tripStateMachineProvider)), 'active');
    });

    test('a fresh fix restarts the countdown', () async {
      await startTrip();

      // Nearly out of time, then a fix arrives.
      watchdog.advance(
        AppConstants.gpsLossStopTimeout - const Duration(seconds: 1),
      );
      await pushFix(1);
      await tick();
      expect(recorder.stopCalls, 0);

      // The same amount of time again: still short of the timeout measured
      // from the fix, so the trip survives.
      watchdog.advance(
        AppConstants.gpsLossStopTimeout - const Duration(seconds: 1),
      );
      await tick();
      expect(recorder.stopCalls, 0);
      expect(_stateName(container.read(tripStateMachineProvider)), 'active');

      // Past it now.
      watchdog.advance(const Duration(seconds: 2));
      await tick();
      expect(recorder.stopCalls, 1);
      expect(_stateName(container.read(tripStateMachineProvider)), 'idle');
    });

    test('the watchdog never stops a trip that is not running', () async {
      final coordinator = await startedCoordinator();
      watchdog = coordinator as _WatchdogCoordinator;

      await pushMotion(1); // analysed, but no trip started
      watchdog.advance(AppConstants.gpsLossStopTimeout * 3);
      await tick();

      expect(recorder.stopCalls, 0);
    });

    test('a paused trip is stopped on GPS loss too', () async {
      await startTrip();

      stopDetector.decision = StopDecision.pauseTrip;
      await pushMotion(2);
      expect(_stateName(container.read(tripStateMachineProvider)), 'paused');

      // Back to "continue" so the paused branch's own stop decision cannot be
      // what ends the trip - only the watchdog can.
      stopDetector.decision = StopDecision.continueTrip;
      watchdog.advance(
        AppConstants.gpsLossStopTimeout + const Duration(seconds: 1),
      );
      await tick();

      expect(recorder.stopCalls, 1);
      expect(_stateName(container.read(tripStateMachineProvider)), 'idle');
    });
  });

  group('TripDetectionCoordinator - detector resets (L-074)', () {
    late _StreakStartDetector streakDetector;

    setUp(() {
      container.dispose();
      container = ProviderContainer(
        overrides: baseOverrides(
          startDetectorOverride: tripStartDetectorProvider.overrideWith(
            () => _StreakStartDetector(startDetector),
          ),
        ),
      );
      coordinatorSubscription = container.listen(
        tripDetectionCoordinatorProvider,
        (_, _) {},
      );
    });

    /// Lets the 100 ms restart delay in `_finalizeAndStopTrip` elapse so the
    /// motion subscription is live again.
    Future<void> awaitSessionRestart() async {
      await Future<void>.delayed(const Duration(milliseconds: 150));
      await pumpEventQueue();
    }

    test(
      'a single strong sample after a trip ends does not start a new one',
      () async {
        await startedCoordinator();
        streakDetector = container.read(
          tripStartDetectorProvider.notifier,
        ) as _StreakStartDetector;

        // Three sustained samples start the trip, as the real streak rule
        // requires.
        await pushMotion(1);
        await pushMotion(2);
        expect(recorder.startedWithConfidence, isEmpty);
        await pushMotion(3);
        expect(recorder.startedWithConfidence, hasLength(1));

        // End it.
        stopDetector.decision = StopDecision.stopTrip;
        await pushMotion(4);
        expect(recorder.stopCalls, 1);
        expect(streakDetector.strongSamples, 0);

        await awaitSessionRestart();

        // One strong sample must NOT be enough: before the reset the streak
        // survived the ride and the very next sample restarted a trip.
        stopDetector.decision = StopDecision.continueTrip;
        await pushMotion(5);
        expect(recorder.startedWithConfidence, hasLength(1));
        expect(
          _stateName(container.read(tripStateMachineProvider)),
          'detecting',
        );
      },
    );

    test('starting a trip resets the stop detector', () async {
      startDetector.verdict = true;
      await startedCoordinator();
      final before = stopDetector.resetCalls;

      // The default fake start detector is not in play here, so drive the
      // streak one to a start.
      await pushMotion(1);
      await pushMotion(2);
      await pushMotion(3);

      expect(recorder.startedWithConfidence, hasLength(1));
      expect(stopDetector.resetCalls, greaterThan(before));
    });
  });

  // ==========================================================================
  // L-075. The detector used to spend roughly half its time blind: `Detecting`
  // was entered on the first motion sample of any kind, its 30 s timeout armed
  // `tripStartCooldownPeriodSeconds` of unconditional "no" AND tore the streams
  // down, and the cycle repeated for as long as anything moved the phone. These
  // tests pin the two halves of the fix: a timeout costs nothing but the streak,
  // and the cooldown is armed only where a trip really was started and thrown
  // away.
  // ==========================================================================
  group('TripDetectionCoordinator - detection duty cycle (L-075)', () {
    late _WatchdogCoordinator coordinator;

    setUp(() {
      container.dispose();
      container = ProviderContainer(
        overrides: baseOverrides(
          startDetectorOverride: tripStartDetectorProvider.overrideWith(
            () => _StreakStartDetector(startDetector),
          ),
          extra: [
            tripDetectionCoordinatorProvider.overrideWith(
              _WatchdogCoordinator.new,
            ),
          ],
        ),
      );
      coordinatorSubscription = container.listen(
        tripDetectionCoordinatorProvider,
        (_, _) {},
      );
    });

    _TestTripStateMachine machine() =>
        container.read(tripStateMachineProvider.notifier)
            as _TestTripStateMachine;

    Future<void> begin() async {
      coordinator = await startedCoordinator() as _WatchdogCoordinator;
    }

    Future<void> tick() async {
      coordinator.tick();
      await pumpEventQueue();
    }

    test(
      'the detecting phase is entered on a counted detection, not on motion',
      () async {
        await begin();

        // The streak detector counts every sample, so one sample is one
        // detection and the phase opens; a sample the real detector scored
        // below threshold would leave the machine idle (see the routing group).
        await pushMotion(1);

        expect(
          _stateName(container.read(tripStateMachineProvider)),
          'detecting',
        );
        expect(recorder.startedWithConfidence, isEmpty);
      },
    );

    test('a detecting timeout returns to idle and arms no cooldown', () async {
      await begin();
      await pushMotion(1);
      expect(_stateName(container.read(tripStateMachineProvider)), 'detecting');

      machine().forceDetectionTimeout = true;
      await tick();

      expect(_stateName(container.read(tripStateMachineProvider)), 'idle');
      // The streak is dropped...
      expect(startDetector.resetCalls, greaterThan(0));
      // ...but the detector is NOT blinded: this used to be 1, and the next
      // `tripStartCooldownPeriodSeconds` of real cycling were ignored.
      expect(startDetector.cooldownCalls, 0);
    });

    test(
      'a cycling pattern right after a timeout starts a trip immediately',
      () async {
        await begin();
        await pushMotion(1);
        await pushMotion(2);

        machine().forceDetectionTimeout = true;
        await tick();
        machine().forceDetectionTimeout = false;
        expect(_stateName(container.read(tripStateMachineProvider)), 'idle');

        // No `awaitSessionRestart()` here on purpose: the timeout no longer
        // suspends the motion subscription, so the very next samples are seen.
        // A full streak — the confirmation rule is untouched — starts the trip.
        for (
          var i = 3;
          i <= 2 + AppConstants.tripStartMinConsecutiveDetections;
          i++
        ) {
          await pushMotion(i);
        }

        expect(recorder.startedWithConfidence, hasLength(1));
        expect(_stateName(container.read(tripStateMachineProvider)), 'active');
      },
    );

    test('a discarded trip arms the start-detection cooldown', () async {
      recorder.discardOnStop = true;
      await begin();

      for (
        var i = 1;
        i <= AppConstants.tripStartMinConsecutiveDetections;
        i++
      ) {
        await pushMotion(i);
      }
      expect(_stateName(container.read(tripStateMachineProvider)), 'active');

      stopDetector.decision = StopDecision.stopTrip;
      await pushMotion(10);

      expect(recorder.stopCalls, 1);
      expect(startDetector.cooldownCalls, 1);
    });

    test('a long ride discarded for want of GPS is not a false start (L-081)', () async {
      // The other reason the recorder throws a recording away: eleven minutes
      // of real riding through an urban canyon whose fixes were all rejected by
      // the accuracy filter. The detector was right and GPS was not there, so
      // backing off would blind it for another 30 s just as the rider comes
      // back into the open — and would journal a false start that never was.
      recorder
        ..discardOnStop = true
        ..durationOnStop = AppConstants.minTripDurationSeconds * 11;
      await begin();

      for (
        var i = 1;
        i <= AppConstants.tripStartMinConsecutiveDetections;
        i++
      ) {
        await pushMotion(i);
      }
      stopDetector.decision = StopDecision.stopTrip;
      await pushMotion(10);

      expect(recorder.stopCalls, 1);
      expect(startDetector.cooldownCalls, 0);
    });

    test('a completed trip does not arm the cooldown', () async {
      await begin();

      for (
        var i = 1;
        i <= AppConstants.tripStartMinConsecutiveDetections;
        i++
      ) {
        await pushMotion(i);
      }
      expect(_stateName(container.read(tripStateMachineProvider)), 'active');

      stopDetector.decision = StopDecision.stopTrip;
      await pushMotion(10);

      expect(recorder.stopCalls, 1);
      expect(startDetector.cooldownCalls, 0);
    });
  });

  // -------------------------------------------------------------------------
  // One departure, one trip (L-080)
  // -------------------------------------------------------------------------
  group('TripDetectionCoordinator - one departure, one trip (L-080)', () {
    setUp(() {
      // The real recorder pins itself with `ref.keepAlive()` for the lifetime
      // of a recording; the spy does not, and these tests are the only ones
      // that hold a start open across several event-queue pumps — long enough
      // for autoDispose to collect the provider mid-call.
      container.listen(tripRecorderServiceProvider, (_, _) {});
    });

    test('samples arriving while a start is in flight do not start a second '
        'trip', () async {
      startDetector.verdict = true;
      recorder.startGate = Completer<void>();
      await startedCoordinator();

      // The departure. `startRecording` is now parked on the gate, exactly
      // where the real one is parked on its database write.
      await pushMotion(1);
      expect(recorder.startedWithConfidence, hasLength(1));
      expect(
        _stateName(container.read(tripStateMachineProvider)),
        'detecting',
        reason: 'the state machine only leaves Detecting on startTripWithId',
      );

      // The 50 Hz stream does not stop for the database, and the detector goes
      // on answering `shouldStart` for the rest of the evaluation interval.
      await pushMotion(2);
      await pushMotion(3);

      expect(
        recorder.startedWithConfidence,
        hasLength(1),
        reason:
            'trips 5 and 6 of the 2026-09-02 control run were two '
            'startRecording calls from one departure',
      );

      recorder.startGate!.complete();
      await pumpEventQueue();

      expect(_stateName(container.read(tripStateMachineProvider)), 'active');
      expect(recorder.startedWithConfidence, hasLength(1));
    });

    test(
      'the pre-trip buffer is handed over once, not once per sample',
      () async {
        startDetector.verdict = true;
        recorder.startGate = Completer<void>();
        await startedCoordinator();

        await pushMotion(1);
        await pushMotion(2);
        recorder.startGate!.complete();
        await pumpEventQueue();

        // A second hand-over would have found the buffer already cleared and
        // given the trip an empty prefix — or, worse, split one ride's fixes
        // across two rows.
        expect(recorder.startedWithPriorLocations, hasLength(1));
      },
    );

    test('a released departure can be retried on a later sample', () async {
      startDetector.verdict = true;
      recorder.throwOnStart = true;
      await startedCoordinator();

      await pushMotion(1);
      await pumpEventQueue();

      // The failed start released the claim: the guard must not wedge the
      // coordinator into never starting a trip again.
      expect(_stateName(container.read(tripStateMachineProvider)), 'idle');
      recorder.throwOnStart = false;

      await pushMotion(2);

      expect(recorder.startedWithConfidence, hasLength(1));
      expect(_stateName(container.read(tripStateMachineProvider)), 'active');
    });

    test(
      'a start rejected because another caller won leaves that trip alone',
      () async {
        startDetector.verdict = true;
        recorder.startGate = Completer<void>();
        await startedCoordinator();

        // The coordinator decides to start and parks on the recorder.
        await pushMotion(1);
        expect(recorder.startedWithConfidence, hasLength(1));

        // Meanwhile the manual button gets its trip through: the state machine
        // goes `active` with an id this coordinator never chose, and every
        // further `startRecording` is rejected by the recorder's own guard.
        container.read(tripStateMachineProvider.notifier).startTripWithId(7);
        recorder.failStartWith = TripAlreadyStartingError(
          'Trip already recording',
        );
        recorder.startGate!.complete();
        await pumpEventQueue();

        // The coordinator's own call is the one that was rejected. Its error
        // path used to answer that by stopping the state machine — ending the
        // ride the other caller had just begun.
        expect(_stateName(container.read(tripStateMachineProvider)), 'active');
        expect(container.read(tripStateMachineProvider).currentTripId, 7);
        expect(
          container.read(tripDetectionCoordinatorProvider).hasError,
          isFalse,
          reason: 'losing a race is not a failure to surface to the UI',
        );
      },
    );

    test('a claim is released even if the departure never reaches the '
        'recorder', () async {
      final coordinator = await startedCoordinator();
      startDetector.verdict = true;

      // `_analyzeForTripStart` claims the departure before the pre-trip buffer
      // hand-off; anything throwing in between used to leave the claim set for
      // the life of the process, with detection silently dead and no line in
      // the log to say so. Nothing here can be made to throw from the outside,
      // so the guarantee is asserted through the session boundary instead: a
      // restarted session always starts from an unclaimed coordinator.
      await pushMotion(1);
      expect(recorder.startedWithConfidence, hasLength(1));

      coordinator.stopListening();
      await pumpEventQueue();
      container.read(tripStateMachineProvider.notifier).stopTrip();
      await coordinator.startListening();
      await pumpEventQueue();

      await pushMotion(2);

      expect(recorder.startedWithConfidence, hasLength(2));
    });
  });

  // -------------------------------------------------------------------------
  // Pre-trip location buffer (L-076)
  // -------------------------------------------------------------------------
  group('TripDetectionCoordinator - pre-trip location buffer (L-076)', () {
    setUp(() {
      container.dispose();
      container = ProviderContainer(
        overrides: baseOverrides(
          extra: [
            tripDetectionCoordinatorProvider.overrideWith(
              _ManualGateCoordinator.new,
            ),
          ],
        ),
      );
      coordinatorSubscription = container.listen(
        tripDetectionCoordinatorProvider,
        (_, _) {},
      );
    });

    Future<void> elapseInactivity() async {
      (container.read(
        tripDetectionCoordinatorProvider.notifier,
      ) as _ManualGateCoordinator).inactivityTimer?.fire();
      await pumpEventQueue();
    }

    List<LocationData> buffered() => container
        .read(tripDetectionCoordinatorProvider.notifier)
        .debugPreTripLocations;

    /// Feeds one fix through the (gated) location stream.
    Future<void> pushLocation({required int index, double speed = 5.0}) async {
      locationController.add(_location(speed: speed, index: index));
      await pumpEventQueue();
    }

    test('fixes received while detecting reach startRecording', () async {
      await startedCoordinator();
      await pushMotion(1); // opens the GPS gate

      await pushLocation(index: 1);
      await pushLocation(index: 2);
      await pushLocation(index: 3);
      expect(buffered(), hasLength(3));

      startDetector.verdict = true;
      await pushMotion(2);

      expect(recorder.startedWithPriorLocations, hasLength(1));
      expect(
        recorder.startedWithPriorLocations.single.map((f) => f.timestamp),
        [
          _location(index: 1).timestamp,
          _location(index: 2).timestamp,
          _location(index: 3).timestamp,
        ],
      );
      // Handed over, so no longer pending.
      expect(buffered(), isEmpty);
    });

    test('a buffer of zero-speed fixes still yields a riding tail (T048)', () async {
      // The 2026-09-03 iPhone: every fix of the departure reported `sp` 0, so
      // the riding-tail cut found nothing at cycling speed and the trip was
      // back-dated by 3 s instead of the 1.3 km already ridden. The speed is
      // derived at ingestion now, so the tail is found from the same fixes.
      await startedCoordinator();
      await pushMotion(1);

      // 0.0002° of latitude ≈ 22 m; 22 m every 3 s ≈ 27 km/h.
      for (var index = 1; index <= 5; index++) {
        locationController.add(
          LocationData(
            latitude: 48.8566 + index * 0.0002,
            longitude: 2.3522,
            accuracy: 5.0,
            altitude: 35.0,
            speed: 0.0,
            heading: 90.0,
            timestamp: DateTime(
              2026,
              9,
              3,
              17,
              19,
            ).add(Duration(seconds: index * 3)),
          ),
        );
        await pumpEventQueue();
      }

      expect(
        buffered().map((fix) => fix.speedKmh > AppConstants.cyclingSpeedMin),
        // The first fix has nothing to be measured against and keeps its zero;
        // every one after it is anchored on its predecessor.
        [false, true, true, true, true],
      );

      startDetector.verdict = true;
      await pushMotion(2);

      expect(recorder.startedWithPriorLocations.single, hasLength(4));
    });

    test('the walk to the bike is skimmed off the front', () async {
      await startedCoordinator();
      await pushMotion(1);

      // 1 m/s = 3.6 km/h: below cyclingSpeedMin.
      await pushLocation(speed: 1.0, index: 1);
      await pushLocation(speed: 1.2, index: 2);
      // 5 m/s = 18 km/h: riding.
      await pushLocation(speed: 5.0, index: 3);
      await pushLocation(speed: 5.5, index: 4);

      startDetector.verdict = true;
      await pushMotion(2);

      expect(
        recorder.startedWithPriorLocations.single.map((f) => f.timestamp),
        [_location(index: 3).timestamp, _location(index: 4).timestamp],
      );
    });

    test(
      'a departure that never reached cycling speed prefixes nothing',
      () async {
        await startedCoordinator();
        await pushMotion(1);

        await pushLocation(speed: 1.0, index: 1);
        await pushLocation(speed: 1.5, index: 2);

        startDetector.verdict = true;
        await pushMotion(2);

        expect(recorder.startedWithPriorLocations.single, isEmpty);
      },
    );

    test('closing the GPS gate empties the buffer', () async {
      await startedCoordinator();
      await pushMotion(1);
      await pushLocation(index: 1);
      expect(buffered(), hasLength(1));

      await pushStationary(2);
      await elapseInactivity();

      expect(gpsSubscribed, isFalse);
      expect(buffered(), isEmpty);
    });

    test('nothing accumulates while a trip is recording', () async {
      startDetector.verdict = true;
      await startedCoordinator();
      await pushMotion(1);
      expect(container.read(tripStateMachineProvider).hasActiveTrip, isTrue);

      await pushLocation(index: 5);
      await pushLocation(index: 6);

      expect(buffered(), isEmpty);
    });

    test('a suspended session leaves nothing behind', () async {
      await startedCoordinator();
      await pushMotion(1);
      await pushLocation(index: 1);
      expect(buffered(), hasLength(1));

      container.read(tripDetectionCoordinatorProvider.notifier).stopListening();
      await pumpEventQueue();

      expect(buffered(), isEmpty);
    });
  });

  group('TripDetectionCoordinator - audit instrumentation', () {
    // The risk this group covers is not a subtle bug: it is an impeccable
    // instrumentation plan with three `emit` calls missing. A journal that is
    // silent about the very transition being investigated is worse than no
    // journal, because it looks like evidence.
    late _RecordingAuditSink sink;

    setUp(() {
      sink = _RecordingAuditSink();
      AuditLog.install(sink, verbose: true);
      addTearDown(AuditLog.uninstall);
    });

    Future<void> pushLocation({required int index, double speed = 5.0}) async {
      locationController.add(_location(speed: speed, index: index));
      await pumpEventQueue();
    }

    test('a session start is recorded', () async {
      await startedCoordinator();

      expect(sink.typesOf('sess'), isNotEmpty);
      expect(sink.field('sess', 'a'), 'start');
    });

    test(
      'the GPS gate is recorded opening and being scheduled to close',
      () async {
        await startedCoordinator();
        await pushMotion(1); // a moving sample opens the gate

        expect(sink.field('gate', 'a'), 'open');

        // A settled stationary window arms the inactivity timeout.
        await pushStationary(2);

        final actions = sink.fieldsOf('gate').map((f) => f['a']).toList();
        expect(actions, contains('sched'));
      },
    );

    test('every fix is recorded with the provider timestamp that aligns it '
        'against a FIT', () async {
      await startedCoordinator();
      await pushMotion(1);

      await pushLocation(index: 1, speed: 6.0);

      final fix = sink.fieldsOf('fix').single;
      expect(fix['lat'], isNotNull);
      expect(fix['lon'], isNotNull);
      // `gt` is the whole basis of the cross-reference: without it a log can
      // only be aligned to a second device by guesswork.
      expect(fix['gt'], isNotNull);
      expect(fix['sp'], isNotNull);
    });

    test('state transitions are recorded, with both ends named', () async {
      startDetector.verdict = true;
      await startedCoordinator();
      await pushMotion(1);

      final transitions = sink.fieldsOf('st');
      expect(transitions, isNotEmpty);
      expect(transitions.map((t) => t['to']), contains('active'));
    });

    test('the GPS-loss watchdog is recorded arming and firing', () async {
      startDetector.verdict = true;
      await startedCoordinator();
      await pushMotion(1);

      expect(
        sink.fieldsOf('gpsw').map((f) => f['a']),
        contains('arm'),
        reason: 'without an arm event the countdown has no known origin',
      );
    });

    test('a start evaluation carries the score and the streak', () async {
      await startedCoordinator();
      await pushMotion(1);

      final evaluation = sink.fieldsOf('start').first;
      expect(evaluation.containsKey('c'), isTrue);
      expect(evaluation.containsKey('n'), isTrue);
      expect(evaluation.containsKey('go'), isTrue);
    });

    test('a stop decision is recorded with its counters', () async {
      startDetector.verdict = true;
      await startedCoordinator();
      await pushMotion(1);
      startDetector.verdict = false;
      stopDetector.decision = StopDecision.pauseTrip;

      await pushMotion(2);

      final decision = sink.fieldsOf('stop').last;
      expect(decision['d'], 'pauseTrip');
      expect(decision.containsKey('cs'), isTrue);
      // `so`, not `pd`: seconds since the stationary onset, which is not the
      // trip's own `pau` (L-086, schema 2).
      expect(decision.containsKey('so'), isTrue);
    });

    test(
      'the heartbeat reports ticks, samples and real elapsed time',
      () async {
        // Needs a movable clock: the heartbeat covers 30 real seconds.
        container.dispose();
        container = ProviderContainer(
          overrides: baseOverrides(
            extra: [
              tripDetectionCoordinatorProvider.overrideWith(
                _WatchdogCoordinator.new,
              ),
            ],
          ),
        );
        coordinatorSubscription = container.listen(
          tripDetectionCoordinatorProvider,
          (_, _) {},
        );

        final coordinator = await startedCoordinator() as _WatchdogCoordinator;
        await pushMotion(1);

        for (var i = 0; i < 30; i++) {
          coordinator.advance(const Duration(seconds: 1));
          coordinator.tick();
        }
        await pumpEventQueue();

        final heartbeat = sink.fieldsOf('hb');
        expect(heartbeat, isNotEmpty);

        // 30 ticks over 30 s is a process that ran. Fewer ticks than seconds is
        // what an OS suspension looks like from the inside, and `mn` separates
        // "the process ran" from "the sensors delivered".
        expect(heartbeat.last['n'], 30);
        expect(heartbeat.last['mn'], greaterThan(0));
        expect(heartbeat.last['dt'], 30000);
        // `hz` is what `mn / (dt / 1000)` has to be read against: the sampling
        // period is a request the OS rounds to a rate of its own — 55.6 Hz
        // backgrounded and 83 Hz foregrounded for a configured 50 on the
        // 2026-09-02 Pixel (L-086).
        expect(heartbeat.last['hz'], PowerModeConfig.normal.sensorSamplingRate);
      },
    );

    test('nothing is recorded once the log is uninstalled', () async {
      AuditLog.uninstall();

      await startedCoordinator();
      await pushMotion(1);

      expect(sink.lines, isEmpty);
    });

    // -----------------------------------------------------------------------
    // The events above all happen on the happy path. These need a timeout, a
    // teardown or a trip ending, so they run against a coordinator whose
    // clock, supervisor tick and GPS inactivity timer are all fired by hand.
    // Each one pins an emit whose removal would make the log silent about a
    // transition an analyst has no other way to see.
    // -----------------------------------------------------------------------
    group('at the edges', () {
      late _ScriptedCoordinator coordinator;

      setUp(() {
        container.dispose();
        container = ProviderContainer(
          overrides: baseOverrides(
            extra: [
              tripDetectionCoordinatorProvider.overrideWith(
                _ScriptedCoordinator.new,
              ),
            ],
          ),
        );
        coordinatorSubscription = container.listen(
          tripDetectionCoordinatorProvider,
          (_, _) {},
        );
      });

      Future<void> begin() async {
        coordinator = await startedCoordinator() as _ScriptedCoordinator;
      }

      Future<void> tick() async {
        coordinator.tick();
        await pumpEventQueue();
      }

      Future<void> elapseInactivity() async {
        coordinator.inactivityTimer?.fire();
        await pumpEventQueue();
      }

      _TestTripStateMachine machine() =>
          container.read(tripStateMachineProvider.notifier)
              as _TestTripStateMachine;

      /// Opens the GPS gate with a moving sample, then buffers one fix.
      Future<void> openGateAndBuffer({double speed = 6.0}) async {
        await pushMotion(1);
        locationController.add(_location(speed: speed, index: 1));
        await pumpEventQueue();
      }

      Iterable<Object?> actionsOf(String type) =>
          sink.fieldsOf(type).map((f) => f['a']);

      // The `start` event fires on the detection hot path, so it is the one
      // event whose *volume* is a defect in itself. A T043 log came back with
      // 107 757 of them out of 108 870 lines — 99 % of the file, ~110 a second
      // — which buries every other event and makes the log's own write cost the
      // dominant term in the battery measurement it exists to support.
      group('the start evaluation is throttled', () {
        test(
          'samples inside one evaluation interval collapse to one',
          () async {
            await begin();

            for (var i = 0; i < 50; i++) {
              coordinator.advance(const Duration(milliseconds: 10));
              await pushMotion(i);
            }

            // Half a second of samples at 100 Hz: one interval, one line.
            expect(sink.fieldsOf('start'), hasLength(1));
          },
        );

        test('the interval elapsing lets the next one through', () async {
          await begin();
          await pushMotion(1);
          expect(sink.fieldsOf('start'), hasLength(1));

          coordinator.advance(AppConstants.detectionEvaluationInterval);
          await pushMotion(2);

          expect(sink.fieldsOf('start'), hasLength(2));
        });

        test('a streak change is never dropped', () async {
          await begin();
          await pushMotion(1);
          final before = sink.fieldsOf('start').length;

          // The streak advances inside the interval — the transition that
          // explains how the detector reached its verdict, and the reason
          // throttling cannot be a plain rate limit.
          startDetector.countedDetections = 1;
          await pushMotion(2);

          expect(sink.fieldsOf('start'), hasLength(before + 1));
          expect(sink.fieldsOf('start').last['n'], isNot(0));
        });

        test('the departure decision is never dropped', () async {
          await begin();
          startDetector.verdict = true;

          await pushMotion(1);

          final go = sink.fieldsOf('start').where((f) => f['go'] == true);
          expect(go, hasLength(1));
        });
      });

      // Same defect class as `start`, on the two paths `07fabee` did not
      // touch: 33 036 `stop` + 23 535 `res` lines in the 2026-09-02 Pixel log,
      // with inter-event gaps of 1–12 ms (L-085).
      group('the stop and resume evaluations are throttled', () {
        Future<void> startTrip() async {
          startDetector.verdict = true;
          await begin();
          await pushMotion(0);
          startDetector.verdict = false;
          expect(
            _stateName(container.read(tripStateMachineProvider)),
            'active',
          );
        }

        test('samples inside one evaluation interval collapse to one '
            '`stop` line', () async {
          await startTrip();
          sink.clear();

          for (var i = 0; i < 50; i++) {
            coordinator.advance(const Duration(milliseconds: 10));
            await pushMotion(i);
          }

          expect(sink.fieldsOf('stop'), hasLength(1));
        });

        test(
          'the interval elapsing lets the next `stop` line through',
          () async {
            await startTrip();
            sink.clear();
            await pushMotion(1);
            expect(sink.fieldsOf('stop'), hasLength(1));

            coordinator.advance(AppConstants.detectionEvaluationInterval);
            await pushMotion(2);

            expect(sink.fieldsOf('stop'), hasLength(2));
          },
        );

        test('a pause decision is never dropped', () async {
          await startTrip();
          sink.clear();
          await pushMotion(1);

          // Inside the same interval as the line above, so only the decision
          // itself can let it through.
          stopDetector.decision = StopDecision.pauseTrip;
          coordinator.advance(const Duration(milliseconds: 10));
          await pushMotion(2);

          final decisions = sink
              .fieldsOf('stop')
              .where((f) => f['d'] == 'pauseTrip');
          expect(decisions, hasLength(1));
        });

        test('samples inside one evaluation interval collapse to one '
            '`res` line', () async {
          await startTrip();
          container.read(tripStateMachineProvider.notifier).pauseTrip();
          sink.clear();

          for (var i = 0; i < 50; i++) {
            coordinator.advance(const Duration(milliseconds: 10));
            await pushMotion(i);
          }

          expect(sink.fieldsOf('res'), hasLength(1));
        });

        test('a trip ended by maxPause still says what decided it', () async {
          await startTrip();
          container.read(tripStateMachineProvider.notifier).pauseTrip();
          sink.clear();

          // The paused branch runs its own `analyzeForTripStop`, and its
          // decision used to reach `_finalizeAndStopTrip` without a single
          // `stop` line — the way trip 6 of the 2026-09-02 run ended (L-081).
          stopDetector.decision = StopDecision.stopTrip;
          await pushMotion(1);

          final stops = sink
              .fieldsOf('stop')
              .where((f) => f['d'] == 'stopTrip');
          expect(stops, hasLength(1));
        });

        test('a resume decision is never dropped', () async {
          await startTrip();
          container.read(tripStateMachineProvider.notifier).pauseTrip();
          sink.clear();
          await pushMotion(1);

          stopDetector.resumeVerdict = true;
          coordinator.advance(const Duration(milliseconds: 10));
          await pushMotion(2);

          final go = sink.fieldsOf('res').where((f) => f['go'] == true);
          expect(go, hasLength(1));
        });

        test('`res` carries the movement timer the decision is made on', () async {
          await startTrip();
          container.read(tripStateMachineProvider.notifier).pauseTrip();
          sink.clear();
          await pushMotion(1);

          // `cm` is not touched by the resume path: without `mv` the log shows
          // a flat `res {go:false}` once a second while the sustained-movement
          // timer starts and restarts underneath — the 100 ms defect L-082 is
          // read from.
          expect(sink.fieldsOf('res').last.containsKey('mv'), isTrue);
        });
      });

      test('the gate closing on a stationary timeout says so', () async {
        await begin();
        await pushMotion(1);
        await pushStationary(2);

        await elapseInactivity();

        final close = sink.fieldsOf('gate').where((f) => f['a'] == 'close');
        expect(close, hasLength(1));
        expect(close.single['why'], 'inactivityTimeout');
      });

      test('a gate closed by the session teardown is not journalled as a '
          'stationary rider', () async {
        await begin();
        await pushMotion(1);

        coordinator.stopListening();
        await pumpEventQueue();

        final close = sink.fieldsOf('gate').where((f) => f['a'] == 'close');
        expect(close, hasLength(1));
        // R-07: this used to read `inactivityTimeout`, i.e. a statement about
        // the rider standing still, for a gate the app itself closed.
        expect(close.single['why'], 'stop');
      });

      test(
        'a detection timeout is recorded with the streak it dropped',
        () async {
          startDetector.countedDetections = 1;
          await begin();
          await pushMotion(1);
          expect(
            _stateName(container.read(tripStateMachineProvider)),
            'detecting',
          );

          machine().forceDetectionTimeout = true;
          await tick();

          final timeout = sink.fieldsOf('dto').single;
          expect(timeout['el'], AppConstants.detectionTimeoutSeconds);
          expect(timeout.containsKey('n'), isTrue);
        },
      );

      test('the cooldown armed by a false start is recorded', () async {
        recorder.discardOnStop = true;
        startDetector.verdict = true;
        await begin();
        await pushMotion(1);

        stopDetector.decision = StopDecision.stopTrip;
        await pushMotion(2);

        final cooldown = sink.fieldsOf('cool').single;
        expect(cooldown['a'], 'arm');
        expect(cooldown['why'], 'falseStart');
        expect(cooldown['d'], AppConstants.tripStartCooldownPeriodSeconds);
      });

      test(
        'the GPS-loss watchdog is recorded disarming when the trip ends',
        () async {
          startDetector.verdict = true;
          await begin();
          await pushMotion(1);
          expect(actionsOf('gpsw'), contains('arm'));

          stopDetector.decision = StopDecision.stopTrip;
          await pushMotion(2);

          // Without this the log shows a countdown that was armed and never
          // ended, which reads as a watchdog that failed to fire.
          expect(actionsOf('gpsw'), contains('disarm'));
        },
      );

      test(
        'the pre-trip buffer is recorded filling and being handed over',
        () async {
          await begin();
          await openGateAndBuffer();

          final added = sink.fieldsOf('buf').where((f) => f['a'] == 'add');
          expect(added, hasLength(1));
          expect(added.single['n'], 1);

          startDetector.verdict = true;
          await pushMotion(2);

          final tail = sink.fieldsOf('buf').where((f) => f['a'] == 'tail');
          expect(tail, hasLength(1));
          // `n` buffered, `kp` kept by the riding-tail cut (L-076).
          expect(tail.single['n'], 1);
          expect(tail.single['kp'], 1);
        },
      );

      test('a discarded pre-trip buffer says what discarded it', () async {
        await begin();
        await openGateAndBuffer();

        await pushStationary(2);
        await elapseInactivity();

        final cleared = sink.fieldsOf('buf').where((f) => f['a'] == 'clear');
        expect(cleared, hasLength(1));
        expect(cleared.single['n'], 1);
        expect(cleared.single['why'], 'inactivityTimeout');
      });

      test(
        'enabling the log mid-session re-arms the heartbeat baseline',
        () async {
          AuditLog.uninstall();
          await begin();
          await pushMotion(1);

          // Five minutes of riding before the user flips the switch.
          for (var i = 0; i < 300; i++) {
            coordinator.advance(const Duration(seconds: 1));
            coordinator.tick();
          }

          AuditLog.install(sink, verbose: true);

          // 31 ticks: the first one re-arms the baseline, so the interval that
          // closes covers the 30 s after it.
          for (var i = 0; i < 31; i++) {
            coordinator.advance(const Duration(seconds: 1));
            coordinator.tick();
          }
          await pumpEventQueue();

          final heartbeat = sink.fieldsOf('hb');
          expect(heartbeat, isNotEmpty);
          // R-08: this used to be n:1 over a dt of 300 000 ms — the exact
          // signature the ledger defines as "the OS froze the 1 Hz timer".
          expect(heartbeat.first['n'], 31);
          expect(heartbeat.first['dt'], 30000);
        },
      );

      test('a stop records exactly one session event', () async {
        await begin();

        coordinator.stopListening();
        await pumpEventQueue();

        // R-17: `stop` immediately followed by `suspend` made one stop look
        // like two session events in the exported log.
        expect(actionsOf('sess'), ['start', 'stop']);
      });

      test('stopping a session that never started records nothing', () async {
        final coordinator = await readCoordinator();

        coordinator.stopListening();
        await pumpEventQueue();

        expect(sink.fieldsOf('sess'), isEmpty);
      });
    });
  });
}

/// Collects audit lines and decodes them on demand.
class _RecordingAuditSink implements AuditSink {
  final List<String> lines = <String>[];

  @override
  void write(
    String line, {
    required int t,
    required String type,
    required int lvl,
    required bool critical,
  }) => lines.add(line);

  @override
  Future<void> flush() async {}

  Iterable<Map<String, dynamic>> fieldsOf(String type) => lines
      .map((l) => jsonDecode(l) as Map<String, dynamic>)
      .where((m) => m['e'] == type);

  Iterable<String> typesOf(String type) =>
      fieldsOf(type).map((m) => m['e'] as String);

  Object? field(String type, String key) => fieldsOf(type).first[key];

  /// Forget everything recorded so far, so a throttling assertion counts the
  /// lines one phase produced rather than the ones that set it up.
  void clear() => lines.clear();
}
