import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:autoride/features/trip_detection/domain/models/motion_data.dart';
import 'package:autoride/features/trip_detection/domain/models/location_data.dart';
import 'package:autoride/features/trip_detection/data/services/trip_start_detector.dart';
import 'package:autoride/core/constants/app_constants.dart';

/// How these tests feed the detector, and why it changed in T050.
///
/// The motion half of the confidence is no longer a property of one sample: it
/// is the spread of |a| and the mean |gyro| over the last
/// `detectionEvaluationInterval` (L-079). So a single `MotionData` is not a
/// scenario any more — "cycling" is a *second* of samples with a bicycle's
/// vibration in it, and a constant sample, however perfectly it sits inside the
/// old instantaneous bands, is by definition a phone that is not moving.
///
/// Every test therefore drives the detector through `evaluate`, which delivers
/// the samples of the second ending at the evaluation instant, exactly as the
/// 50 Hz stream does in production.
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

  group('TripStartDetector', () {
    /// Helper to create a fresh provider container for each test
    ProviderContainer createContainer() {
      return ProviderContainer();
    }

    /// One sample of a bicycle, [i] being its index in the window.
    ///
    /// |a| alternates 9.81 ± 3.5 m/s², i.e. a standard deviation of 3.5 —
    /// between `cyclingAccelStdIdeal` (3.0) and `cyclingAccelStdMax`, and close
    /// to the 3.4–3.9 measured on the 2026-09-06 ride. |gyro| is a steady
    /// 1.2 rad/s, past `cyclingGyroMeanIdeal` (0.9) and in the range that ride
    /// held (1.08–1.32). Both arms therefore score 1.0.
    MotionData cyclingSample(int i, DateTime at) {
      return MotionData(
        accelerometer: AccelerometerData(
          x: 0.0,
          y: 0.0,
          z: i.isEven ? 9.81 + 3.5 : 9.81 - 3.5,
          timestamp: at,
        ),
        gyroscope: GyroscopeData(x: 0.0, y: 0.0, z: 1.2, timestamp: at),
        timestamp: at,
      );
    }

    /// A bicycle whose window sits on the ramp rather than on the plateau:
    /// std 2.5 (against a 2.0–3.0 ramp) and |gyro| 0.65 (against 0.4–0.9), so
    /// each arm scores 0.5 and the motion half comes out at 0.5.
    ///
    /// Needed wherever a test compares two confidences: on the plateau the
    /// motion score saturates at 1.0 and GPS corroboration has nothing left to
    /// add.
    MotionData marginalCyclingSample(int i, DateTime at) {
      return MotionData(
        accelerometer: AccelerometerData(
          x: 0.0,
          y: 0.0,
          z: i.isEven ? 9.81 + 2.5 : 9.81 - 2.5,
          timestamp: at,
        ),
        gyroscope: GyroscopeData(x: 0.0, y: 0.0, z: 0.65, timestamp: at),
        timestamp: at,
      );
    }

    /// A phone being carried: |a| barely leaves gravity (std 0.2, under
    /// `cyclingAccelStdMin`) and |gyro| averages 0.2 rad/s, under
    /// `cyclingGyroMeanMin`. Both arms score 0.
    MotionData walkingSample(int i, DateTime at) {
      return MotionData(
        accelerometer: AccelerometerData(
          x: 0.0,
          y: 0.0,
          z: i.isEven ? 10.01 : 9.61,
          timestamp: at,
        ),
        gyroscope: GyroscopeData(x: 0.0, y: 0.0, z: 0.2, timestamp: at),
        timestamp: at,
      );
    }

    /// A sample whose *instantaneous* magnitudes sit dead centre of the old
    /// bands — |a| 14.8 m/s² in [10, 20], |gyro| 1.5 rad/s in [0.5, 3.0] — and
    /// which never changes.
    ///
    /// This is what `createCyclingMotion` used to be, and under the
    /// pre-T050 fit a second of it scored 1.0. It is a phone held perfectly
    /// still at an odd angle.
    MotionData constantInBandSample(int i, DateTime at) {
      return MotionData(
        accelerometer: AccelerometerData(
          x: 5.0,
          y: 5.0,
          z: 13.0, // magnitude ≈ 14.8
          timestamp: at,
        ),
        gyroscope: GyroscopeData(
          x: 1.2,
          y: 0.8,
          z: 0.9, // magnitude ≈ 1.51
          timestamp: at,
        ),
        timestamp: at,
      );
    }

    /// Samples per evaluation interval, and their spacing.
    ///
    /// 25 samples 40 ms apart is 960 ms — a full interval, comfortably past
    /// `tripStartMotionWindowMinSamples`, and cheap enough to run in a unit
    /// test at every evaluation.
    const samplesPerInterval = 25;
    const sampleSpacing = Duration(milliseconds: 40);

    /// One evaluation *at* [at], preceded by the window it is computed over.
    ///
    /// Returns the verdict of the last sample, which is the one landing on the
    /// evaluation instant. [location] is offered to every sample, as the
    /// coordinator does with its `_lastLocation`.
    Future<bool> evaluate(
      TripStartDetector detector, {
      required DateTime at,
      required MotionData Function(int i, DateTime at) sample,
      LocationData? Function(DateTime at)? location,
    }) async {
      var started = false;
      for (var i = samplesPerInterval - 1; i >= 0; i--) {
        final t = at.subtract(sampleSpacing * i);
        started = await detector.analyzeForTripStart(
          sample(i, t),
          location?.call(t),
          now: t,
        );
      }
      return started;
    }

    /// [count] consecutive evaluations one interval apart, starting at [from].
    Future<bool> evaluateRepeatedly(
      TripStartDetector detector, {
      required DateTime from,
      required MotionData Function(int i, DateTime at) sample,
      LocationData? Function(DateTime at)? location,
      int count = AppConstants.tripStartMinConsecutiveDetections,
    }) async {
      var started = false;
      for (var i = 0; i < count; i++) {
        started =
            await evaluate(
              detector,
              at: from.add(AppConstants.detectionEvaluationInterval * i),
              sample: sample,
              location: location,
            ) ||
            started;
      }
      return started;
    }

    /// Helper to create cycling speed GPS data (18 km/h)
    LocationData createCyclingLocation() {
      return LocationData(
        latitude: 48.8566,
        longitude: 2.3522,
        accuracy: 10.0,
        altitude: 35.0,
        speed: 5.0, // m/s = 18 km/h
        heading: 90.0,
        timestamp: DateTime.now(),
      );
    }

    /// Helper to create walking speed GPS data (4 km/h)
    LocationData walkingLocationAt(DateTime now) {
      return LocationData(
        latitude: 48.8566,
        longitude: 2.3522,
        accuracy: 10.0,
        altitude: 35.0,
        speed: 1.1, // m/s ≈ 4 km/h (< 8 km/h minimum)
        heading: 90.0,
        timestamp: now,
      );
    }

    /// Helper to create driving speed GPS data (60 km/h)
    LocationData drivingLocationAt(DateTime now) {
      return LocationData(
        latitude: 48.8566,
        longitude: 2.3522,
        accuracy: 10.0,
        altitude: 35.0,
        speed: 16.7, // m/s ≈ 60 km/h (> 40 km/h maximum)
        heading: 90.0,
        timestamp: now,
      );
    }

    /// A fix at cycling speed, stamped against the injected clock.
    LocationData cyclingLocationAt(DateTime now) =>
        createCyclingLocation().copyWith(timestamp: now);

    test('should start trip with cycling motion and valid GPS speed', () async {
      final container = createContainer();

      final detector = container.read(tripStartDetectorProvider.notifier);
      final start = DateTime(2026, 9, 6, 23, 20);

      // Three consecutive evaluation intervals. Detections are counted at most
      // once per interval, so the seconds must be spread over real time - three
      // back-to-back samples are ~60ms of motion, not a trip.
      await evaluateRepeatedly(
        detector,
        from: start,
        sample: cyclingSample,
        location: cyclingLocationAt,
      );

      final state = container.read(tripStartDetectorProvider);
      expect(
        state.confidence,
        greaterThanOrEqualTo(AppConstants.tripStartConfidenceThreshold),
      );
      expect(
        state.consecutiveDetections,
        greaterThanOrEqualTo(AppConstants.tripStartMinConsecutiveDetections),
      );
      expect(detector.shouldStartTrip(), isTrue);

      container.dispose();
    });

    test('should NOT start trip with walking motion and GPS', () async {
      final container = createContainer();

      final detector = container.read(tripStartDetectorProvider.notifier);
      final start = DateTime(2026, 9, 6, 23, 20);

      await evaluateRepeatedly(
        detector,
        from: start,
        sample: walkingSample,
        location: walkingLocationAt,
      );

      expect(detector.shouldStartTrip(), isFalse);

      container.dispose();
    });

    test('should NOT start trip with driving speed GPS', () async {
      final container = createContainer();

      final detector = container.read(tripStartDetectorProvider.notifier);
      final start = DateTime(2026, 9, 6, 23, 20);

      await evaluateRepeatedly(
        detector,
        from: start,
        sample: cyclingSample, // Good motion
        location: drivingLocationAt, // But driving speed
      );

      // Should not trigger due to excessive speed
      expect(detector.shouldStartTrip(), isFalse);

      container.dispose();
    });

    group('the fit is windowed, not instantaneous (T050, L-079)', () {
      test('a constant sample in the middle of the old bands scores 0', () async {
        // The regression this whole change is about, stated as a test. Under
        // the pre-T050 fit this sample scored 1.0 on both arms — it is |a| 14.8
        // and |gyro| 1.5, the exact centre of `cyclingAcceleration*` and
        // `cyclingRotation*` — while describing a phone that is not moving at
        // all. What actually distinguishes a bicycle is the *spread*.
        final container = createContainer();
        final detector = container.read(tripStartDetectorProvider.notifier);

        final started = await evaluateRepeatedly(
          detector,
          from: DateTime(2026, 9, 6, 23, 20),
          sample: constantInBandSample,
        );

        expect(started, isFalse);
        // The acceleration arm — the one that carried the old fit — reads
        // exactly zero, because there is no spread to read. What is left is
        // half a score from a gyroscope pinned at a constant 1.5 rad/s, which
        // no pocket produces for a second on end, and half a score has never
        // started a trip.
        expect(detector.accelerationStdDev, closeTo(0.0, 1e-9));
        expect(
          container.read(tripStartDetectorProvider).confidence,
          lessThan(AppConstants.tripStartConfidenceThreshold),
        );

        container.dispose();
      });

      test('an unfilled window scores 0 rather than an accident', () async {
        // A standard deviation over two samples is noise, and the first samples
        // of a session (or of a stream coming back from a stall) must not be
        // able to confirm anything on their own.
        final container = createContainer();
        final detector = container.read(tripStartDetectorProvider.notifier);
        final start = DateTime(2026, 9, 6, 23, 20);

        for (
          var i = 0;
          i < AppConstants.tripStartMotionWindowMinSamples - 1;
          i++
        ) {
          await detector.analyzeForTripStart(
            cyclingSample(i, start),
            null,
            now: start.add(sampleSpacing * i),
          );
        }

        expect(container.read(tripStartDetectorProvider).confidence, 0.0);
        expect(
          detector.motionWindowSamples,
          lessThan(AppConstants.tripStartMotionWindowMinSamples),
        );

        container.dispose();
      });

      test('the window reports the statistics the audit prints', () async {
        // `asd`/`gav` are what makes a refusal to start readable in a log, so
        // they have to be the numbers the score was actually computed from.
        final container = createContainer();
        final detector = container.read(tripStartDetectorProvider.notifier);

        await evaluate(
          detector,
          at: DateTime(2026, 9, 6, 23, 20),
          sample: cyclingSample,
        );

        expect(detector.accelerationStdDev, closeTo(3.5, 0.1));
        expect(detector.averageRotation, closeTo(1.2, 0.01));
        expect(detector.motionWindowSamples, samplesPerInterval);

        container.dispose();
      });

      test('a reset empties the window', () async {
        final container = createContainer();
        final detector = container.read(tripStartDetectorProvider.notifier);

        await evaluate(
          detector,
          at: DateTime(2026, 9, 6, 23, 20),
          sample: cyclingSample,
        );
        expect(detector.motionWindowSamples, greaterThan(0));

        detector.reset();

        expect(detector.motionWindowSamples, 0);
        expect(detector.accelerationStdDev, 0.0);

        container.dispose();
      });
    });

    test('should require consecutive detections (no single spike)', () async {
      final container = createContainer();

      final detector = container.read(tripStartDetectorProvider.notifier);

      // A single second of cycling
      await evaluate(
        detector,
        at: DateTime(2026, 9, 6, 23, 20),
        sample: cyclingSample,
        location: cyclingLocationAt,
      );

      final state = container.read(tripStartDetectorProvider);
      expect(state.consecutiveDetections, equals(1));
      expect(detector.shouldStartTrip(), isFalse);

      container.dispose();
    });

    test(
      'regression: a burst of samples inside one interval is NOT a trip start',
      () async {
        // Guards L-022: detections used to be counted per 50Hz sample, so
        // `tripStartMinConsecutiveDetections = 3` meant ~60ms of motion and a
        // single bump or hand movement could start a trip.
        final container = createContainer();
        addTearDown(container.dispose);

        final detector = container.read(tripStartDetectorProvider.notifier);

        // 50 samples at 50Hz = 1 second's worth of data delivered inside a
        // single evaluation interval.
        final start = DateTime(2026, 9, 6, 23, 20);
        for (int i = 0; i < 50; i++) {
          final at = start.add(Duration(milliseconds: i * 20));
          await detector.analyzeForTripStart(
            cyclingSample(i, at),
            cyclingLocationAt(at),
            now: at,
          );
        }

        final state = container.read(tripStartDetectorProvider);
        expect(
          state.confidence,
          greaterThanOrEqualTo(AppConstants.tripStartConfidenceThreshold),
          reason: 'confidence still tracks every sample',
        );
        expect(
          state.consecutiveDetections,
          lessThan(AppConstants.tripStartMinConsecutiveDetections),
          reason:
              'counters advance once per evaluation interval, not per sample',
        );
        expect(detector.shouldStartTrip(), isFalse);
      },
    );

    test('should work with motion-only (no GPS)', () async {
      final container = createContainer();

      final detector = container.read(tripStartDetectorProvider.notifier);

      await evaluateRepeatedly(
        detector,
        from: DateTime(2026, 9, 6, 23, 20),
        sample: cyclingSample,
      );

      final state = container.read(tripStartDetectorProvider);
      // Should have some confidence based on motion alone
      expect(state.confidence, greaterThan(0.0));
      expect(state.consecutiveDetections, greaterThanOrEqualTo(3));

      container.dispose();
    });

    test('should respect cooldown period', () async {
      final container = createContainer();

      final detector = container.read(tripStartDetectorProvider.notifier);

      // Activate cooldown
      detector.activateCooldown();

      // Verify cooldown blocks trip start
      final state = container.read(tripStartDetectorProvider);
      expect(state.cooldownActive, isTrue);
      expect(state.consecutiveDetections, equals(0));
      expect(detector.shouldStartTrip(), isFalse);

      container.dispose();
    });

    test('should deactivate cooldown after timeout', () async {
      final container = createContainer();

      final detector = container.read(tripStartDetectorProvider.notifier);

      // Activate cooldown
      detector.activateCooldown();
      final state = container.read(tripStartDetectorProvider);
      expect(state.cooldownActive, isTrue);
      expect(state.cooldownStartTime, isNotNull);

      // Verify cooldown is active
      expect(detector.shouldStartTrip(), isFalse);

      container.dispose();
    });

    test('should calculate correct confidence score', () async {
      final container = createContainer();

      final detector = container.read(tripStartDetectorProvider.notifier);

      await evaluate(
        detector,
        at: DateTime(2026, 9, 6, 23, 20),
        sample: cyclingSample,
        location: cyclingLocationAt,
      );

      final state = container.read(tripStartDetectorProvider);
      // Confidence should be > 0 and <= 1.0
      expect(state.confidence, greaterThan(0.0));
      expect(state.confidence, lessThanOrEqualTo(1.0));

      container.dispose();
    });

    test('a reset with no cooldown lets the very next cycling burst confirm '
        '(L-075)', () async {
      final container = createContainer();

      final detector = container.read(tripStartDetectorProvider.notifier);
      final start = DateTime(2026, 9, 6, 23, 20);

      Future<bool> burst(DateTime from) =>
          evaluateRepeatedly(detector, from: from, sample: cyclingSample);

      expect(await burst(start), isTrue);

      // What the coordinator does when a `Detecting` phase times out: drop
      // the streak, and nothing else. No cooldown is armed, so the detector
      // is immediately available again — a real departure one second later
      // must not have to wait out `tripStartCooldownPeriodSeconds`.
      detector.reset();
      expect(container.read(tripStartDetectorProvider).cooldownActive, isFalse);

      expect(await burst(start.add(const Duration(seconds: 4))), isTrue);

      container.dispose();
    });

    test(
      'an armed cooldown blocks detection until it expires (L-075)',
      () async {
        final container = createContainer();

        final detector = container.read(tripStartDetectorProvider.notifier);

        // What the coordinator does after a *discarded* trip: reset, then arm
        // the cooldown. This is the one path that is still allowed to blind the
        // detector, because a trip really was started and thrown away.
        detector.reset();
        detector.activateCooldown();
        final armedAt = container
            .read(tripStartDetectorProvider)
            .cooldownStartTime!;

        // Sustained cycling inside the cooldown confirms nothing.
        expect(
          await evaluateRepeatedly(
            detector,
            from: armedAt.add(AppConstants.detectionEvaluationInterval),
            sample: cyclingSample,
          ),
          isFalse,
        );
        expect(
          container.read(tripStartDetectorProvider).consecutiveDetections,
          equals(0),
        );

        // Past the cooldown the same burst confirms again.
        final after = armedAt.add(
          const Duration(
            seconds: AppConstants.tripStartCooldownPeriodSeconds + 1,
          ),
        );
        expect(
          await evaluateRepeatedly(
            detector,
            from: after,
            sample: cyclingSample,
          ),
          isTrue,
        );

        container.dispose();
      },
    );

    /// A fix that is present and says nothing usable about speed — the case
    /// L-087 is about. [accuracy] and [ageSeconds] are the two arms of the
    /// trust predicate that T048 shipped; the third, added by T050, is whether
    /// there is a speed measurement at all.
    LocationData createZeroSpeedLocation({
      required DateTime now,
      double accuracy = 10.0,
      int ageSeconds = 0,
    }) {
      return LocationData(
        latitude: 48.8566,
        longitude: 2.3522,
        accuracy: accuracy,
        altitude: 35.0,
        speed: 0.0,
        heading: 90.0,
        timestamp: now.subtract(Duration(seconds: ageSeconds)),
      );
    }

    group('a fix only vetoes a departure when its speed can be believed', () {
      // T048. The arithmetic being defended against: with a fix present,
      // confidence is motion*0.6 + speed*0.4, so `speedScore` 0 caps it at 0.60
      // under a 0.7 threshold — and no fix at all would have scored higher.
      test('a fix reporting no speed at all does not veto (L-098)', () async {
        // Was the opposite assertion until T050, on the reading that a fix
        // reading 0 might genuinely mean "standing still". It cannot: iOS
        // reports exactly 0 on fixes taken at 20 km/h, and nothing in the fix
        // distinguishes the two. 155 of the 2026-09-06 ride's 751 evaluations
        // were capped at 0.60 by this, at 20 km/h. What keeps a stationary
        // phone from starting a ride is now the motion window, which reads a
        // standing bicycle as calm — see the walking cases below.
        final container = createContainer();
        final detector = container.read(tripStartDetectorProvider.notifier);

        final started = await evaluateRepeatedly(
          detector,
          from: DateTime(2026, 9, 6, 23, 20),
          sample: cyclingSample,
          location: (now) => createZeroSpeedLocation(now: now),
        );

        expect(started, isTrue);
        expect(
          container.read(tripStartDetectorProvider).confidence,
          greaterThanOrEqualTo(AppConstants.tripStartConfidenceThreshold),
        );

        container.dispose();
      });

      test('a fix too coarse for its speed does not (L-088)', () async {
        // The Pixel: 40 fixes, 30 of them above 50 m, every one reading 0 km/h,
        // and a ride that was arithmetically undetectable for 25 minutes.
        final container = createContainer();
        final detector = container.read(tripStartDetectorProvider.notifier);

        final started = await evaluateRepeatedly(
          detector,
          from: DateTime(2026, 9, 3, 17, 19),
          sample: cyclingSample,
          location: (now) => createZeroSpeedLocation(now: now, accuracy: 300.0),
        );

        expect(started, isTrue);
        expect(
          container.read(tripStartDetectorProvider).confidence,
          greaterThanOrEqualTo(AppConstants.tripStartConfidenceThreshold),
        );

        container.dispose();
      });

      test('a fix older than the freshness bound does not (L-089)', () async {
        // 80 % of the Pixel's evaluations were scored against a fix whose mean
        // age was 33.6 s, against a 10 s bound the stop detector already had.
        final container = createContainer();
        final detector = container.read(tripStartDetectorProvider.notifier);

        final started = await evaluateRepeatedly(
          detector,
          from: DateTime(2026, 9, 3, 17, 19),
          sample: cyclingSample,
          location: (now) => createZeroSpeedLocation(
            now: now,
            ageSeconds: AppConstants.speedTrustMaxAge.inSeconds + 1,
          ),
        );

        expect(started, isTrue);

        container.dispose();
      });

      test('an untrusted fix does not raise a walk to a departure', () async {
        // The other half of the trade-off, and the reason acceptance needs both
        // device runs: dropping the veto must not turn the motion-only path
        // into a licence to start on anything.
        final container = createContainer();
        final detector = container.read(tripStartDetectorProvider.notifier);

        final started = await evaluateRepeatedly(
          detector,
          from: DateTime(2026, 9, 3, 17, 19),
          sample: walkingSample,
          location: (now) => createZeroSpeedLocation(now: now, accuracy: 300.0),
        );

        expect(started, isFalse);

        container.dispose();
      });

      test('a trusted fix at cycling speed still scores highest', () async {
        // Read on a window that sits on the *ramp* of both motion arms: on the
        // plateau the motion score is already 1.0 and corroboration has nothing
        // left to add, which is a property of the score, not of the evidence.
        final container = createContainer();
        final detector = container.read(tripStartDetectorProvider.notifier);
        final start = DateTime(2026, 9, 3, 17, 19);

        await evaluateRepeatedly(
          detector,
          from: start,
          sample: marginalCyclingSample,
          location: cyclingLocationAt,
        );
        final withSpeed = container.read(tripStartDetectorProvider).confidence;

        final other = createContainer();
        await evaluateRepeatedly(
          other.read(tripStartDetectorProvider.notifier),
          from: start,
          sample: marginalCyclingSample,
          location: (now) => createZeroSpeedLocation(now: now, accuracy: 300.0),
        );
        final motionOnly = other.read(tripStartDetectorProvider).confidence;

        expect(
          withSpeed,
          greaterThan(motionOnly),
          reason: 'corroborated evidence must beat absent evidence',
        );

        container.dispose();
        other.dispose();
      });
    });

    test('should reset state correctly', () async {
      final container = createContainer();

      final detector = container.read(tripStartDetectorProvider.notifier);

      // Build up some state
      await evaluateRepeatedly(
        detector,
        from: DateTime(2026, 9, 6, 23, 20),
        sample: cyclingSample,
        location: cyclingLocationAt,
        count: 2,
      );

      final stateBefore = container.read(tripStartDetectorProvider);
      expect(stateBefore.consecutiveDetections, greaterThan(0));

      // Reset
      detector.reset();

      final stateAfter = container.read(tripStartDetectorProvider);
      expect(stateAfter.confidence, equals(0.0));
      expect(stateAfter.consecutiveDetections, equals(0));
      expect(stateAfter.lastDetectionTime, isNull);
      expect(stateAfter.cooldownActive, isFalse);

      container.dispose();
    });

    // L-093. The streak used to slide: `lastDetectionTime` was refreshed on
    // every positive detection and the window comparison truncated to whole
    // seconds, so "3 consecutive detections" meant three spikes each within
    // 5.99 s of the previous one — up to 18 s of wall clock, with any number of
    // near-zero samples in between. All ten false starts of the 2026-09-03
    // kitchen run are that signature.
    group('the streak counts consecutive intervals (L-093)', () {
      test('Pixel trip 3 replayed: five flat seconds break the streak', () async {
        final container = createContainer();
        final detector = container.read(tripStartDetectorProvider.notifier);
        final start = DateTime(2026, 9, 3, 21, 33, 22);

        // `c=0.834 n=2` at 21:33:22, then 0.203 / 0 / 0 / 0.273 / 0.156 across
        // five consecutive seconds with `n` unchanged at 2, then `c=0.803 n=3
        // go` 5.35 s later. Two firm gestures, a meal cooked in between, and a
        // ride in the database.
        var started = await evaluate(
          detector,
          at: start,
          sample: cyclingSample,
        );
        for (var s = 1; s <= 5; s++) {
          started =
              await evaluate(
                detector,
                at: start.add(Duration(seconds: s)),
                sample: walkingSample,
              ) ||
              started;
        }
        started =
            await evaluate(
              detector,
              at: start.add(const Duration(milliseconds: 5350)),
              sample: cyclingSample,
            ) ||
            started;

        expect(started, isFalse);
        // Back to the first detection of a new streak, not the third of an old
        // one.
        expect(
          container.read(tripStartDetectorProvider).consecutiveDetections,
          1,
        );

        container.dispose();
      });

      test('three consecutive seconds of cycling still start a trip', () async {
        final container = createContainer();
        final detector = container.read(tripStartDetectorProvider.notifier);

        expect(
          await evaluateRepeatedly(
            detector,
            from: DateTime(2026, 9, 3, 21, 33, 22),
            sample: cyclingSample,
          ),
          isTrue,
        );

        container.dispose();
      });

      test('a few calm samples inside a cycling second do not break it', () async {
        // The streak counts intervals, not samples, and a windowed fit is meant
        // to be indifferent to a handful of quiet instants inside a second —
        // a freewheel, a smooth patch of tarmac. Five calm samples in
        // twenty-five leave the spread at ~3.1, still on the plateau.
        final container = createContainer();
        final detector = container.read(tripStartDetectorProvider.notifier);

        final started = await evaluateRepeatedly(
          detector,
          from: DateTime(2026, 9, 3, 21, 33, 22),
          sample: (i, at) =>
              i % 5 == 0 ? walkingSample(i, at) : cyclingSample(i, at),
        );

        expect(started, isTrue);

        container.dispose();
      });

      test(
        'a gap in which nothing was evaluated starts a new streak',
        () async {
          // The staleness bound is all `tripStartDetectionWindowSeconds` still
          // does: a suspended process must not come back and finish a streak it
          // began before the gap. 6.5 s also pins the truncation fix — the old
          // `.inSeconds <= 5` comparison read 5.5 s as within a 5 s window.
          final container = createContainer();
          final detector = container.read(tripStartDetectorProvider.notifier);
          final start = DateTime(2026, 9, 3, 21, 33, 22);

          await evaluateRepeatedly(
            detector,
            from: start,
            sample: cyclingSample,
            count: 2,
          );
          expect(
            container.read(tripStartDetectorProvider).consecutiveDetections,
            2,
          );

          final started = await evaluate(
            detector,
            at: start.add(const Duration(milliseconds: 7500)),
            sample: cyclingSample,
          );

          expect(started, isFalse);
          expect(
            container.read(tripStartDetectorProvider).consecutiveDetections,
            1,
          );

          container.dispose();
        },
      );
    });
  });
}
