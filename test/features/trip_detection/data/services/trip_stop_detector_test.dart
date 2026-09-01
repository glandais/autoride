import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:autoride/features/trip_detection/data/services/trip_stop_detector.dart';
import 'package:autoride/features/trip_detection/domain/models/motion_data.dart';
import 'package:autoride/features/trip_detection/domain/models/location_data.dart';
import 'package:autoride/features/trip_detection/domain/models/trip_stop_state.dart';
import 'package:autoride/core/constants/app_constants.dart';

void main() {
  setUpAll(() {
    // Mock SharedPreferences for all tests
    SharedPreferences.setMockInitialValues({
      'tripNotificationsEnabled': true,
      'showOngoingNotification': true,
      'soundOnTripStartStop': false,
      'autoPauseEnabled': true,
      'minDistanceMeters': 500.0,
    });
  });

  group('TripStopDetector', () {
    /// Helper to create a fresh provider container for each test
    ProviderContainer createContainer() {
      return ProviderContainer();
    }

    // Helper: Create stationary motion data
    // Accelerometer includes gravity, so a resting device reads ~9.8 m/s².
    MotionData createStationaryMotion() {
      return MotionData(
        accelerometer: AccelerometerData(
          x: 0.1,
          y: 0.1,
          z: 9.8, // Resting on gravity (magnitude ≈ 9.801, deviation ≈ 0.001 < 1.0)
          timestamp: DateTime.now(),
        ),
        gyroscope: GyroscopeData(
          x: 0.05,
          y: 0.05,
          z: 0.05, // Very low rotation (magnitude ≈ 0.087 < 0.2)
          timestamp: DateTime.now(),
        ),
        timestamp: DateTime.now(),
      );
    }

    // Helper: Create cycling motion data
    MotionData createCyclingMotion() {
      return MotionData(
        accelerometer: AccelerometerData(
          x: 3.0,
          y: 3.0,
          z: 10.0, // Cycling motion (~10.86 m/s²)
          timestamp: DateTime.now(),
        ),
        gyroscope: GyroscopeData(
          x: 1.0,
          y: 0.5,
          z: 0.5, // Pedaling rotation (~1.22 rad/s)
          timestamp: DateTime.now(),
        ),
        timestamp: DateTime.now(),
      );
    }

    // Helper: Create stationary GPS location
    LocationData createStationaryLocation() {
      return LocationData(
        latitude: 48.8566,
        longitude: 2.3522,
        accuracy: 10.0,
        altitude: 35.0,
        speed: 0.0, // 0 m/s = 0 km/h
        heading: 90.0,
        timestamp: DateTime.now(),
      );
    }

    // Helper: Create cycling GPS location
    LocationData createCyclingLocation() {
      return LocationData(
        latitude: 48.8566,
        longitude: 2.3522,
        accuracy: 10.0,
        altitude: 35.0,
        speed: 5.0, // 5 m/s = 18 km/h
        heading: 90.0,
        timestamp: DateTime.now(),
      );
    }

    /// Feeds movement samples until the sustained-movement threshold is
    /// reached, returning whether the detector agreed to resume.
    ///
    /// Resuming is time-based (`resumeMovementThresholdSeconds`) rather than
    /// per-sample, so a single non-stationary reading must never resume a
    /// paused trip.
    bool resumesAfterSustainedMovement(
      TripStopDetector detector,
      MotionData motion,
      LocationData? location, {
      DateTime? from,
    }) {
      final start = from ?? DateTime.now();
      var resumed = false;
      for (
        var second = 0;
        second <= AppConstants.resumeMovementThresholdSeconds;
        second++
      ) {
        resumed = detector.shouldResumeTrip(
          motion,
          location,
          now: start.add(Duration(seconds: second)),
        );
      }
      return resumed;
    }

    /// Feeds [count] readings one evaluation interval apart, so each one is
    /// actually counted by the detector's stationary/movement counters.
    Future<StopDecision> feedCountedReadings(
      TripStopDetector detector,
      MotionData motion,
      LocationData? location, {
      required int count,
      DateTime? from,
    }) async {
      final start = from ?? DateTime.now();
      var decision = StopDecision.continueTrip;
      for (var i = 0; i < count; i++) {
        decision = await detector.analyzeForTripStop(
          motion,
          location,
          now: start.add(AppConstants.detectionEvaluationInterval * (i + 1)),
        );
      }
      return decision;
    }

    test('initial state should be not stationary', () {
      final container = createContainer();
      addTearDown(container.dispose);

      final state = container.read(tripStopDetectorProvider);

      expect(state.isStationary, isFalse);
      expect(state.pauseStartTime, isNull);
      expect(state.pauseDuration, equals(Duration.zero));
      expect(state.consecutiveStationaryDetections, equals(0));
    });

    test('regression: gravity-inclusive resting data is detected as stationary', () async {
      // Guards against the bug where stationary detection compared raw
      // gravity-inclusive magnitude (~9.8) against a gravity-removed threshold
      // (1.0), so auto-pause/stop never triggered on real devices.
      final container = createContainer();
      addTearDown(container.dispose);

      final detector = container.read(tripStopDetectorProvider.notifier);

      // Phone resting flat: ~9.8 m/s² on one axis, zero GPS speed.
      final resting = MotionData(
        accelerometer: AccelerometerData(
          x: 0.0,
          y: 0.0,
          z: 9.81,
          timestamp: DateTime.now(),
        ),
        gyroscope: GyroscopeData(
          x: 0.0,
          y: 0.0,
          z: 0.0,
          timestamp: DateTime.now(),
        ),
        timestamp: DateTime.now(),
      );

      await detector.analyzeForTripStop(resting, createStationaryLocation());
      expect(container.read(tripStopDetectorProvider).isStationary, isTrue);

      // A clearly-moving device (magnitude far from gravity) is NOT stationary,
      // so sustained movement resumes the trip.
      final moving = createCyclingMotion();
      expect(
        resumesAfterSustainedMovement(
          detector,
          moving,
          createCyclingLocation(),
        ),
        isTrue,
      );
    });

    test(
      'should detect stationary state with low motion and GPS speed',
      () async {
        final container = createContainer();
        addTearDown(container.dispose);

        final detector = container.read(tripStopDetectorProvider.notifier);
        final motion = createStationaryMotion();
        final location = createStationaryLocation();

        await detector.analyzeForTripStop(motion, location);

        final state = container.read(tripStopDetectorProvider);
        expect(state.isStationary, isTrue);
        expect(state.consecutiveStationaryDetections, greaterThan(0));
      },
    );

    test('should pause trip after 30 seconds of stationary', () async {
      final container = createContainer();
      addTearDown(container.dispose);

      final detector = container.read(tripStopDetectorProvider.notifier);
      final motion = createStationaryMotion();
      final location = createStationaryLocation();

      // First detection - start pause
      await detector.analyzeForTripStop(motion, location);

      final state = container.read(tripStopDetectorProvider);
      expect(state.pauseStartTime, isNotNull);

      // Set pause start time to 35 seconds ago (exceeds threshold)
      final pauseStart = DateTime.now().subtract(const Duration(seconds: 35));
      detector.state = state.copyWith(
        pauseStartTime: pauseStart,
        consecutiveStationaryDetections:
            AppConstants.minConsecutiveStationaryDetections,
      );

      final decision = await detector.analyzeForTripStop(motion, location);

      // Should pause trip
      expect(decision, equals(StopDecision.pauseTrip));
    });

    test('should stop trip after 5 minutes of stationary', () async {
      final container = createContainer();
      addTearDown(container.dispose);

      final detector = container.read(tripStopDetectorProvider.notifier);
      final motion = createStationaryMotion();
      final location = createStationaryLocation();

      // First detection - start pause
      await detector.analyzeForTripStop(motion, location);

      // Set pause start time to 6 minutes ago (exceeds maxPauseDurationSeconds)
      final pauseStart = DateTime.now().subtract(const Duration(minutes: 6));
      detector.state = detector.state.copyWith(
        pauseStartTime: pauseStart,
        consecutiveStationaryDetections:
            AppConstants.minConsecutiveStationaryDetections,
      );

      final decision = await detector.analyzeForTripStop(motion, location);

      // Should stop trip
      expect(decision, equals(StopDecision.stopTrip));
    });

    test('should resume trip when movement detected', () async {
      final container = createContainer();
      addTearDown(container.dispose);

      final detector = container.read(tripStopDetectorProvider.notifier);
      final cyclingMotion = createCyclingMotion();
      final location = createCyclingLocation();

      // Simulate paused state first
      await detector.analyzeForTripStop(
        createStationaryMotion(),
        createStationaryLocation(),
      );
      detector.state = detector.state.copyWith(
        pauseDuration: const Duration(seconds: 35),
        consecutiveStationaryDetections:
            AppConstants.minConsecutiveStationaryDetections,
      );

      // A single movement sample is not enough; sustained movement resumes.
      expect(detector.shouldResumeTrip(cyclingMotion, location), isFalse);
      expect(
        resumesAfterSustainedMovement(detector, cyclingMotion, location),
        isTrue,
      );
    });

    test('should require consecutive stationary detections', () async {
      final container = createContainer();
      addTearDown(container.dispose);

      final detector = container.read(tripStopDetectorProvider.notifier);
      final motion = createStationaryMotion();
      final location = createStationaryLocation();

      // First detection
      final start = DateTime.now();
      await detector.analyzeForTripStop(motion, location, now: start);
      var state = container.read(tripStopDetectorProvider);
      expect(state.consecutiveStationaryDetections, equals(1));

      // A second reading inside the SAME evaluation interval must NOT count.
      await detector.analyzeForTripStop(
        motion,
        location,
        now: start.add(const Duration(milliseconds: 20)),
      );
      expect(
        container
            .read(tripStopDetectorProvider)
            .consecutiveStationaryDetections,
        equals(1),
        reason: 'counters advance once per interval, not per 50Hz sample',
      );

      // Second detection
      await feedCountedReadings(
        detector,
        motion,
        location,
        count: 1,
        from: start,
      );
      state = container.read(tripStopDetectorProvider);
      expect(state.consecutiveStationaryDetections, equals(2));

      // Third detection
      await feedCountedReadings(
        detector,
        motion,
        location,
        count: 1,
        from: start.add(AppConstants.detectionEvaluationInterval),
      );
      state = container.read(tripStopDetectorProvider);
      expect(
        state.consecutiveStationaryDetections,
        greaterThanOrEqualTo(AppConstants.minConsecutiveStationaryDetections),
      );
    });

    test('should reset pause state when movement detected', () async {
      final container = createContainer();
      addTearDown(container.dispose);

      final detector = container.read(tripStopDetectorProvider.notifier);
      final stationaryMotion = createStationaryMotion();
      final cyclingMotion = createCyclingMotion();
      final location = createCyclingLocation();

      // Start pause
      await detector.analyzeForTripStop(
        stationaryMotion,
        createStationaryLocation(),
      );
      var state = container.read(tripStopDetectorProvider);
      expect(state.isStationary, isTrue);
      expect(state.consecutiveStationaryDetections, greaterThan(0));

      // Detect SUSTAINED movement. Hysteresis requires
      // tripStopMovementHysteresisSamples consecutive counted non-stationary
      // readings before the pause is reset, so feed that many.
      await feedCountedReadings(
        detector,
        cyclingMotion,
        location,
        count: AppConstants.tripStopMovementHysteresisSamples,
      );

      // State should be reset
      state = container.read(tripStopDetectorProvider);
      expect(state.isStationary, isFalse);
      expect(state.consecutiveStationaryDetections, equals(0));
      expect(state.pauseStartTime, isNull);
    });

    test('should handle GPS unavailable gracefully', () async {
      final container = createContainer();
      addTearDown(container.dispose);

      final detector = container.read(tripStopDetectorProvider.notifier);
      final motion = createStationaryMotion();

      // Analyze without GPS (null location)
      final decision = await detector.analyzeForTripStop(motion, null);

      // Should still work with motion-only detection
      expect(
        decision,
        isIn([StopDecision.continueTrip, StopDecision.pauseTrip]),
      );
    });

    test('traffic light scenario: 15s stop should not pause', () async {
      final container = createContainer();
      addTearDown(container.dispose);

      final detector = container.read(tripStopDetectorProvider.notifier);
      final motion = createStationaryMotion();
      final location = createStationaryLocation();

      // Start stationary
      await detector.analyzeForTripStop(motion, location);

      // Simulate 15 seconds (below 30s threshold)
      detector.state = detector.state.copyWith(
        pauseDuration: const Duration(seconds: 15),
        consecutiveStationaryDetections:
            AppConstants.minConsecutiveStationaryDetections,
      );

      final decision = await detector.analyzeForTripStop(motion, location);

      // Should continue trip (brief stop)
      expect(decision, equals(StopDecision.continueTrip));
    });

    test('rest stop scenario: 2 min pause should allow resume', () async {
      final container = createContainer();
      addTearDown(container.dispose);

      final detector = container.read(tripStopDetectorProvider.notifier);
      final stationaryMotion = createStationaryMotion();
      final cyclingMotion = createCyclingMotion();
      final cyclingLocation = createCyclingLocation();

      // Pause for 2 minutes (exceeds 30s, below 5 min)
      await detector.analyzeForTripStop(
        stationaryMotion,
        createStationaryLocation(),
      );

      // Set pause start time to 2 minutes ago
      final pauseStart = DateTime.now().subtract(const Duration(minutes: 2));
      detector.state = detector.state.copyWith(
        pauseStartTime: pauseStart,
        consecutiveStationaryDetections:
            AppConstants.minConsecutiveStationaryDetections,
      );

      final pauseDecision = await detector.analyzeForTripStop(
        stationaryMotion,
        createStationaryLocation(),
      );
      expect(pauseDecision, equals(StopDecision.pauseTrip));

      // Resume with sustained movement
      expect(
        resumesAfterSustainedMovement(detector, cyclingMotion, cyclingLocation),
        isTrue,
      );
    });

    test('trip end scenario: 10 min stationary should stop', () async {
      final container = createContainer();
      addTearDown(container.dispose);

      final detector = container.read(tripStopDetectorProvider.notifier);
      final motion = createStationaryMotion();
      final location = createStationaryLocation();

      // Stationary for 10 minutes (exceeds maxPauseDurationSeconds)
      await detector.analyzeForTripStop(motion, location);

      // Set pause start time to 10 minutes ago
      final pauseStart = DateTime.now().subtract(const Duration(minutes: 10));
      detector.state = detector.state.copyWith(
        pauseStartTime: pauseStart,
        consecutiveStationaryDetections:
            AppConstants.minConsecutiveStationaryDetections,
      );

      final decision = await detector.analyzeForTripStop(motion, location);

      // Should stop trip
      expect(decision, equals(StopDecision.stopTrip));
    });

    // Helper: stationary motion paired with a GPS speed spike well above
    // `movingSpeedMinKmh`. A fresh fix that fast forces a "moving" verdict
    // whatever the sensors say, which is exactly the transient the hysteresis
    // has to absorb. (A 3 km/h reading is now correctly read as a standstill:
    // it is below `stationarySpeedMaxKmh`.)
    LocationData createSpikeLocation() {
      return LocationData(
        latitude: 48.8566,
        longitude: 2.3522,
        accuracy: 10.0,
        altitude: 35.0,
        speed: 9.0 / 3.6, // 9 km/h in m/s - one bogus fix at a standstill
        heading: 90.0,
        timestamp: DateTime.now(),
      );
    }

    test('hysteresis: single transient GPS speed spike does NOT reset accumulated pause', () async {
      final container = createContainer();
      addTearDown(container.dispose);

      final detector = container.read(tripStopDetectorProvider.notifier);
      final stationaryMotion = createStationaryMotion();

      // Start a pause and pretend we've already been stationary long enough to
      // be near the auto-stop threshold (6 minutes ago > maxPauseDurationSeconds).
      await detector.analyzeForTripStop(
        stationaryMotion,
        createStationaryLocation(),
      );
      final pauseStart = DateTime.now().subtract(const Duration(minutes: 6));
      detector.state = detector.state.copyWith(
        pauseStartTime: pauseStart,
        consecutiveStationaryDetections:
            AppConstants.minConsecutiveStationaryDetections,
      );

      // One noisy reading (3 km/h while motion is stationary) is non-stationary,
      // but a SINGLE spike must not reset the pause.
      final decision = await detector.analyzeForTripStop(
        stationaryMotion,
        createSpikeLocation(),
      );

      final state = container.read(tripStopDetectorProvider);
      // Pause timer is preserved (not zeroed) and the auto-stop is still reached.
      expect(
        state.isStationary,
        isTrue,
        reason: 'transient spike should not flip out of paused state',
      );
      expect(
        state.pauseStartTime,
        isNotNull,
        reason: 'pause timer must not be reset by a single noisy sample',
      );
      expect(
        state.consecutiveStationaryDetections,
        greaterThanOrEqualTo(AppConstants.minConsecutiveStationaryDetections),
      );
      expect(
        decision,
        equals(StopDecision.stopTrip),
        reason: 'auto-stop must still trigger despite the noisy reading',
      );
    });

    test('hysteresis: sustained movement (N consecutive samples) DOES reset the pause', () async {
      final container = createContainer();
      addTearDown(container.dispose);

      final detector = container.read(tripStopDetectorProvider.notifier);
      final stationaryMotion = createStationaryMotion();
      final cyclingMotion = createCyclingMotion();
      final cyclingLocation = createCyclingLocation();

      // Accumulate a pause near the auto-stop threshold.
      await detector.analyzeForTripStop(
        stationaryMotion,
        createStationaryLocation(),
      );
      final pauseStart = DateTime.now().subtract(const Duration(minutes: 6));
      detector.state = detector.state.copyWith(
        pauseStartTime: pauseStart,
        consecutiveStationaryDetections:
            AppConstants.minConsecutiveStationaryDetections,
      );

      // Feed N-1 counted movement readings: not yet enough to confirm
      // movement, so the pause must still be accumulating (auto-stop still
      // reachable).
      final movementStart = DateTime.now();
      final decision = await feedCountedReadings(
        detector,
        cyclingMotion,
        cyclingLocation,
        count: AppConstants.tripStopMovementHysteresisSamples - 1,
        from: movementStart,
      );
      expect(
        container.read(tripStopDetectorProvider).pauseStartTime,
        isNotNull,
        reason: 'pause should still be accumulating before hysteresis is met',
      );
      expect(
        decision,
        equals(StopDecision.stopTrip),
        reason: 'auto-stop still applies while movement is unconfirmed',
      );

      // The Nth counted movement reading confirms sustained movement and
      // resets the pause.
      final resetDecision = await feedCountedReadings(
        detector,
        cyclingMotion,
        cyclingLocation,
        count: 1,
        from: movementStart.add(
          AppConstants.detectionEvaluationInterval *
              (AppConstants.tripStopMovementHysteresisSamples - 1),
        ),
      );

      final state = container.read(tripStopDetectorProvider);
      expect(state.isStationary, isFalse);
      expect(
        state.pauseStartTime,
        isNull,
        reason: 'sustained movement must reset the pause timer',
      );
      expect(state.consecutiveStationaryDetections, equals(0));
      expect(state.consecutiveMovementDetections, equals(0));
      expect(resetDecision, equals(StopDecision.continueTrip));
    });

    // ---------------------------------------------------------------
    // Realistic carried-phone scenarios (T041 / L-070).
    //
    // These drive the detector the way the coordinator does: a stream of
    // samples with injected timestamps, several per second, so the sliding
    // window sees a real spread instead of one repeated reading.
    // ---------------------------------------------------------------

    const sampleInterval = Duration(milliseconds: 100);
    const samplesPerSecond = 10;

    /// Motion with a controllable acceleration spread and rotation level.
    /// [index] alternates the acceleration around gravity so the window's
    /// standard deviation is exactly [accelStdDev].
    MotionData noisyMotion(
      int index, {
      required double accelStdDev,
      required double gyro,
    }) {
      final at = DateTime(2026, 1, 1).add(sampleInterval * index);
      final delta = index.isEven ? accelStdDev : -accelStdDev;
      return MotionData(
        accelerometer: AccelerometerData(
          x: 0.0,
          y: 0.0,
          z: AppConstants.standardGravity + delta,
          timestamp: at,
        ),
        gyroscope: GyroscopeData(x: gyro, y: 0.0, z: 0.0, timestamp: at),
        timestamp: at,
      );
    }

    LocationData locationAt(DateTime now, double speedKmh) {
      return LocationData(
        latitude: 48.8566,
        longitude: 2.3522,
        accuracy: 8.0,
        altitude: 35.0,
        speed: speedKmh / 3.6,
        heading: 90.0,
        timestamp: now,
      );
    }

    test('traffic light with a pocketed phone: pauses after 30s despite gyro noise', () async {
      final container = createContainer();
      addTearDown(container.dispose);

      final detector = container.read(tripStopDetectorProvider.notifier);
      final start = DateTime(2026, 1, 1);

      // Phone in a pocket at a red light: the body sways (gyro ~0.3 rad/s,
      // far above the old instantaneous 0.2 rad/s ceiling) and the bike
      // shivers a little (accel std-dev 0.3 m/s²). GPS reads a standstill.
      var decision = StopDecision.continueTrip;
      var pausedAtSecond = -1;
      for (var i = 0; i < 35 * samplesPerSecond; i++) {
        final now = start.add(sampleInterval * i);
        decision = await detector.analyzeForTripStop(
          noisyMotion(i, accelStdDev: 0.3, gyro: 0.3),
          locationAt(now, 0.0),
          now: now,
        );
        if (decision == StopDecision.pauseTrip && pausedAtSecond < 0) {
          pausedAtSecond = i ~/ samplesPerSecond;
        }
      }

      expect(
        container.read(tripStopDetectorProvider).isStationary,
        isTrue,
        reason: 'gyro noise at a standstill must not read as movement',
      );
      expect(decision, equals(StopDecision.pauseTrip));
      expect(
        pausedAtSecond,
        inInclusiveRange(
          AppConstants.minPauseDurationSeconds - 1,
          AppConstants.minPauseDurationSeconds + 2,
        ),
        reason:
            'pause fires at minPauseDurationSeconds, not before or long after',
      );
    });

    test(
      'traffic light without GPS: still pauses on windowed sensors',
      () async {
        final container = createContainer();
        addTearDown(container.dispose);

        final detector = container.read(tripStopDetectorProvider.notifier);
        final start = DateTime(2026, 1, 1);

        var decision = StopDecision.continueTrip;
        for (var i = 0; i < 35 * samplesPerSecond; i++) {
          decision = await detector.analyzeForTripStop(
            noisyMotion(i, accelStdDev: 0.3, gyro: 0.3),
            null,
            now: start.add(sampleInterval * i),
          );
        }

        expect(decision, equals(StopDecision.pauseTrip));
      },
    );

    test('steady riding: never pauses', () async {
      final container = createContainer();
      addTearDown(container.dispose);

      final detector = container.read(tripStopDetectorProvider.notifier);
      final start = DateTime(2026, 1, 1);

      // Road vibration: accel std-dev 1.5 m/s², gyro 0.8 rad/s, 18 km/h.
      for (var i = 0; i < 60 * samplesPerSecond; i++) {
        final now = start.add(sampleInterval * i);
        final decision = await detector.analyzeForTripStop(
          noisyMotion(i, accelStdDev: 1.5, gyro: 0.8),
          locationAt(now, 18.0),
          now: now,
        );
        expect(decision, equals(StopDecision.continueTrip));
      }

      final state = container.read(tripStopDetectorProvider);
      expect(state.isStationary, isFalse);
      expect(state.pauseStartTime, isNull);
    });

    test('phone lying still in a basket at 15 km/h: never pauses', () async {
      final container = createContainer();
      addTearDown(container.dispose);

      final detector = container.read(tripStopDetectorProvider.notifier);
      final start = DateTime(2026, 1, 1);

      // Sensors are calm (a phone wedged in a basket barely moves) but GPS is
      // unambiguous: 15 km/h is above `movingSpeedMinKmh`.
      for (var i = 0; i < 60 * samplesPerSecond; i++) {
        final now = start.add(sampleInterval * i);
        final decision = await detector.analyzeForTripStop(
          noisyMotion(i, accelStdDev: 0.02, gyro: 0.02),
          locationAt(now, 15.0),
          now: now,
        );
        expect(decision, equals(StopDecision.continueTrip));
      }

      expect(container.read(tripStopDetectorProvider).isStationary, isFalse);
    });

    test('zombie pause: intermittent movement while paused still reaches auto-stop', () async {
      final container = createContainer();
      addTearDown(container.dispose);

      final detector = container.read(tripStopDetectorProvider.notifier);
      final start = DateTime(2026, 1, 1);

      // Enter the pause (35 s stationary), then behave the way the
      // coordinator's paused branch does: shouldResumeTrip first, then
      // analyzeForTripStop(tripIsPaused: true).
      var decision = StopDecision.continueTrip;
      var resumed = false;
      var stoppedAtSecond = -1;

      for (var i = 0; i < 320 * samplesPerSecond; i++) {
        final now = start.add(sampleInterval * i);
        final second = i ~/ samplesPerSecond;

        // After the pause is established, move for 2 s out of every 10 -
        // never the 5 s of continuous movement a resume needs.
        final moving = second >= 35 && second % 10 < 2;
        final motion = moving
            ? noisyMotion(i, accelStdDev: 1.5, gyro: 0.8)
            : noisyMotion(i, accelStdDev: 0.3, gyro: 0.3);
        final location = locationAt(now, moving ? 12.0 : 0.0);

        final paused = second >= 35;
        if (paused) {
          resumed =
              resumed || detector.shouldResumeTrip(motion, location, now: now);
        }

        decision = await detector.analyzeForTripStop(
          motion,
          location,
          now: now,
          tripIsPaused: paused,
        );

        if (decision == StopDecision.stopTrip && stoppedAtSecond < 0) {
          stoppedAtSecond = second;
        }
      }

      expect(
        resumed,
        isFalse,
        reason: '2 s bursts never satisfy resumeMovementThresholdSeconds',
      );
      expect(
        stoppedAtSecond,
        inInclusiveRange(
          AppConstants.maxPauseDurationSeconds - 1,
          AppConstants.maxPauseDurationSeconds + 3,
        ),
        reason:
            'the pause must run out at maxPauseDurationSeconds instead of '
            'being reset forever by intermittent movement',
      );
      expect(decision, equals(StopDecision.stopTrip));
    });

    test('paused + 5 s of continuous movement resumes', () async {
      final container = createContainer();
      addTearDown(container.dispose);

      final detector = container.read(tripStopDetectorProvider.notifier);
      final start = DateTime(2026, 1, 1);

      // Establish the pause.
      for (var i = 0; i < 35 * samplesPerSecond; i++) {
        final now = start.add(sampleInterval * i);
        await detector.analyzeForTripStop(
          noisyMotion(i, accelStdDev: 0.3, gyro: 0.3),
          locationAt(now, 0.0),
          now: now,
        );
      }

      // Then ride away continuously.
      var resumed = false;
      for (var i = 35 * samplesPerSecond; i < 42 * samplesPerSecond; i++) {
        final now = start.add(sampleInterval * i);
        final motion = noisyMotion(i, accelStdDev: 1.5, gyro: 0.8);
        final location = locationAt(now, 15.0);
        resumed = detector.shouldResumeTrip(motion, location, now: now);
        if (resumed) {
          expect(
            (i ~/ samplesPerSecond) - 35,
            greaterThanOrEqualTo(AppConstants.resumeMovementThresholdSeconds),
            reason: 'resume must need sustained movement, not one sample',
          );
          break;
        }
        await detector.analyzeForTripStop(
          motion,
          location,
          now: now,
          tripIsPaused: true,
        );
      }

      expect(resumed, isTrue);
    });

    test('reset should clear all state', () async {
      final container = createContainer();
      addTearDown(container.dispose);

      final detector = container.read(tripStopDetectorProvider.notifier);
      final motion = createStationaryMotion();
      final location = createStationaryLocation();

      // Build up some state
      await detector.analyzeForTripStop(motion, location);
      detector.state = detector.state.copyWith(
        pauseDuration: const Duration(seconds: 35),
        consecutiveStationaryDetections: 5,
      );

      // Reset
      detector.reset();

      // Should be back to initial state
      final state = container.read(tripStopDetectorProvider);
      expect(state.isStationary, isFalse);
      expect(state.pauseStartTime, isNull);
      expect(state.pauseDuration, equals(Duration.zero));
      expect(state.consecutiveStationaryDetections, equals(0));
    });
  });
}
