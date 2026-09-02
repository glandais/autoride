import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:autoride/core/constants/app_constants.dart';
import 'package:autoride/features/trip_detection/data/services/cycling_pattern_detector.dart';
import 'package:autoride/features/trip_detection/data/services/motion_detection_service.dart';
import 'package:autoride/features/trip_detection/domain/models/activity_confidence.dart';
import 'package:autoride/features/trip_detection/domain/models/motion_data.dart';

/// Tests for the real [CyclingPatternDetector] — the three-layer detector
/// specified in `tasks/T041-device-validation.md` (appendix).
///
/// NOTE: this service is still deliberately **unwired**. `TripStartDetector`
/// is what actually decides a trip start; `cyclingPatternDetectorProvider` has no
/// consumer in `lib/` pending a product decision (L-011). These tests therefore
/// characterise the detector as it stands — including the layer-3 defect below —
/// rather than assert the pipeline uses it.
void main() {
  // ---------------------------------------------------------------------------
  // Fixtures
  // ---------------------------------------------------------------------------

  /// Builds a window of [count] samples, 20 ms apart (50 Hz).
  ///
  /// [accelMagnitude] is placed on z alone so `magnitude == accelMagnitude`.
  /// If [peakEvery] is set, every n-th sample is raised to [peakMagnitude],
  /// producing exactly one detectable local maximum per n samples — i.e. a
  /// pedaling frequency of `1000 / (peakEvery * 20)` Hz.
  MotionWindow buildWindow({
    required int count,
    double accelMagnitude = 12.0,
    double gyroMagnitude = 1.0,
    int? peakEvery,
    double peakMagnitude = 15.0,
    int samplePeriodMs = 20,
    bool identicalTimestamps = false,
  }) {
    final base = DateTime(2026, 1, 1);
    final samples = List.generate(count, (i) {
      final stamp = identicalTimestamps
          ? base
          : base.add(Duration(milliseconds: i * samplePeriodMs));
      final isPeak = peakEvery != null && i > 0 && i % peakEvery == 0;
      return MotionData(
        accelerometer: AccelerometerData(
          x: 0.0,
          y: 0.0,
          z: isPeak ? peakMagnitude : accelMagnitude,
          timestamp: stamp,
        ),
        gyroscope: GyroscopeData(
          x: gyroMagnitude,
          y: 0.0,
          z: 0.0,
          timestamp: stamp,
        ),
        timestamp: stamp,
      );
    });

    return MotionWindow(
      samples: samples,
      startTime: samples.first.timestamp,
      endTime: samples.last.timestamp,
    );
  }

  ProviderContainer containerFor(MotionWindow? window) {
    final container = ProviderContainer(
      overrides: [
        motionDetectionServiceProvider.overrideWith(
          () => _FakeMotionDetectionService(window),
        ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  Future<ActivityConfidence> analyse(MotionWindow? window) {
    return containerFor(window)
        .read(cyclingPatternDetectorProvider.notifier)
        .getCurrentActivity();
  }

  // ---------------------------------------------------------------------------
  // Gating
  // ---------------------------------------------------------------------------

  group('CyclingPatternDetector - window gating', () {
    test('returns unknown when there is no motion window', () async {
      final result = await analyse(null);

      expect(result.activity, equals(ActivityType.unknown));
      expect(result.confidence, equals(0.0));
    });

    test('returns unknown below AppConstants.pedalingCycleSamples', () async {
      final result = await analyse(
        buildWindow(count: AppConstants.pedalingCycleSamples - 1),
      );

      expect(result.activity, equals(ActivityType.unknown));
      expect(result.confidence, equals(0.0));
    });

    test('analyses once the window has enough samples', () async {
      final result = await analyse(
        buildWindow(count: AppConstants.pedalingCycleSamples),
      );

      expect(result.activity, isNot(equals(ActivityType.unknown)));
    });
  });

  // ---------------------------------------------------------------------------
  // Layer 1 — motion pattern (accel + rotation), 40% of the final score
  // ---------------------------------------------------------------------------

  group('CyclingPatternDetector - layer 1 (motion pattern)', () {
    test(
      'scores 1.0 when accel and rotation are both in cycling range',
      () async {
        final result = await analyse(
          buildWindow(
            count: 150,
            accelMagnitude: 12.0, // within [10, 20]
            gyroMagnitude: 1.0, // within [0.5, 3.0]
          ),
        );

        expect(result.motionScore, equals(1.0));
      },
    );

    test('scores 0.5 when only the acceleration fits', () async {
      final result = await analyse(
        buildWindow(
          count: 150,
          accelMagnitude: 12.0,
          gyroMagnitude: 0.1, // below cyclingRotationMin
        ),
      );

      expect(result.motionScore, equals(0.5));
    });

    test('scores 0.5 when only the rotation fits', () async {
      final result = await analyse(
        buildWindow(
          count: 150,
          accelMagnitude: 25.0, // above cyclingAccelerationMax
          gyroMagnitude: 1.0,
        ),
      );

      expect(result.motionScore, equals(0.5));
    });

    test('gives the below-range accel consolation 0.2', () async {
      final result = await analyse(
        buildWindow(
          count: 150,
          accelMagnitude: 9.0, // below cyclingAccelerationMin
          gyroMagnitude: 0.1,
        ),
      );

      expect(result.motionScore, closeTo(0.2, 1e-9));
    });

    test('scores 0.0 when accel is above range and rotation is not', () async {
      final result = await analyse(
        buildWindow(
          count: 150,
          accelMagnitude: 25.0,
          gyroMagnitude: 5.0, // above cyclingRotationMax
        ),
      );

      expect(result.motionScore, equals(0.0));
    });
  });

  // ---------------------------------------------------------------------------
  // Layer 2 — pedaling frequency, 25% of the final score
  // ---------------------------------------------------------------------------

  group('CyclingPatternDetector - layer 2 (pedaling frequency)', () {
    test('scores 0.0 below AppConstants.minSamplesForPattern', () async {
      // Enough to be analysed (>= 50) but not to look for a cadence (< 100).
      final result = await analyse(
        buildWindow(
          count: AppConstants.minSamplesForPattern - 1,
          peakEvery: 42,
        ),
      );

      expect(result.frequencyScore, equals(0.0));
    });

    test('scores 0.0 when the signal has no peaks at all', () async {
      final result = await analyse(buildWindow(count: 150));

      expect(result.frequencyScore, equals(0.0));
    });

    test('scores 0.0 when fewer than two peaks are found', () async {
      // A single peak at index 100 of 150.
      final result = await analyse(buildWindow(count: 150, peakEvery: 100));

      expect(result.frequencyScore, equals(0.0));
    });

    test('ignores peaks below the 10.0 m/s² amplitude threshold', () async {
      final result = await analyse(
        buildWindow(
          count: 150,
          accelMagnitude: 8.0,
          peakEvery: 42,
          peakMagnitude: 9.5, // still under the isPeak threshold of 10.0
        ),
      );

      expect(result.frequencyScore, equals(0.0));
    });

    test('scores near 1.0 at the typical cadence (~1.2 Hz)', () async {
      // 42 samples * 20 ms = 840 ms between peaks ≈ 1.19 Hz.
      final result = await analyse(buildWindow(count: 300, peakEvery: 42));

      expect(result.frequencyScore, greaterThan(0.98));
      expect(result.frequencyScore, lessThanOrEqualTo(1.0));
    });

    test('clamps to 0.6 at the edge of the cycling cadence band', () async {
      // 25 samples * 20 ms = 500 ms → 2.0 Hz == pedalingFrequencyMax.
      final result = await analyse(buildWindow(count: 300, peakEvery: 25));

      expect(result.frequencyScore, closeTo(0.6, 1e-9));
    });

    test('scores 0.3 for periodic motion outside the cadence band', () async {
      // 5 samples * 20 ms = 100 ms → 10 Hz, far above pedalingFrequencyMax.
      final result = await analyse(buildWindow(count: 300, peakEvery: 5));

      expect(result.frequencyScore, closeTo(0.3, 1e-9));
    });

    test('scores 0.0 on a degenerate (zero-length) peak span', () async {
      final result = await analyse(
        buildWindow(count: 300, peakEvery: 42, identicalTimestamps: true),
      );

      expect(result.frequencyScore, equals(0.0));
    });
  });

  // ---------------------------------------------------------------------------
  // Layer 3 — GPS speed. Known defect, pinned deliberately.
  // ---------------------------------------------------------------------------

  group('CyclingPatternDetector - layer 3 (GPS speed) is never fed', () {
    // `build()` declares `LocationData? currentLocation` and never assigns it,
    // and `getCurrentActivity()` declares a `location` local it never assigns
    // either. So `_analyzeSpeedPattern` — the code that would map 8-40 km/h to
    // 0.6-1.0, <8 km/h to 0.3 and >40 km/h to 0.2 — is unreachable, and the
    // 35%-weighted speed term is hardcoded to the neutral 0.5 for every input.
    //
    // These tests pin that behaviour so wiring GPS in later is a visible,
    // deliberate change rather than a silent one. There is no seam that lets a
    // test drive `_analyzeSpeedPattern`; it stays uncovered until the detector
    // is wired to a location source (L-011).

    test('speedScore is the neutral 0.5 for a cycling-shaped window', () async {
      final result = await analyse(buildWindow(count: 300, peakEvery: 42));

      expect(result.speedScore, equals(0.5));
    });

    test('speedScore is the neutral 0.5 for a stationary window too', () async {
      final result = await analyse(
        buildWindow(count: 150, accelMagnitude: 9.8, gyroMagnitude: 0.0),
      );

      expect(result.speedScore, equals(0.5));
    });
  });

  // ---------------------------------------------------------------------------
  // Fusion — the documented 40/35/25 weighting and per-activity scores
  // ---------------------------------------------------------------------------

  group('CyclingPatternDetector - classification', () {
    test('classifies a full cycling signature as cycling', () async {
      final result = await analyse(buildWindow(count: 300, peakEvery: 42));

      expect(result.activity, equals(ActivityType.cycling));
      expect(result.isCyclingDetected, isTrue);
      expect(
        result.confidence,
        greaterThanOrEqualTo(AppConstants.minConfidenceForDetection),
      );
    });

    test('combines the layers with the documented 40/35/25 weights', () async {
      final result = await analyse(buildWindow(count: 300, peakEvery: 42));

      final expected =
          result.motionScore * AppConstants.motionScoreWeight +
          result.speedScore * AppConstants.speedScoreWeight +
          result.frequencyScore * AppConstants.frequencyScoreWeight;

      expect(result.confidence, closeTo(expected, 1e-9));
      expect(result.allScores?[ActivityType.cycling], closeTo(expected, 1e-9));
    });

    test('classifies a resting device as stationary', () async {
      final result = await analyse(
        buildWindow(count: 150, accelMagnitude: 9.8, gyroMagnitude: 0.0),
      );

      expect(result.activity, equals(ActivityType.stationary));
      expect(result.isCyclingDetected, isFalse);
      expect(result.allScores?[ActivityType.stationary], equals(0.9));
    });

    test('scores walking above the default when the shape fits', () async {
      // accel in [10, 12), no cadence, speed 0.5 -> walking arm requires
      // speedScore < 0.4, which the hardcoded 0.5 can never satisfy. This pins
      // the second consequence of the layer-3 defect: the walking branch of
      // `_calculateActivityScores` is dead too.
      final result = await analyse(
        buildWindow(count: 150, accelMagnitude: 11.0, gyroMagnitude: 0.1),
      );

      expect(result.allScores?[ActivityType.walking], equals(0.2));
    });

    test('never selects unknown once a window is analysed', () async {
      final result = await analyse(buildWindow(count: 150));

      expect(result.allScores?[ActivityType.unknown], equals(0.0));
      expect(result.activity, isNot(equals(ActivityType.unknown)));
    });
  });

  group('CyclingPatternDetector - isCycling()', () {
    test('is true for a cycling signature', () async {
      final container = containerFor(buildWindow(count: 300, peakEvery: 42));

      expect(
        await container
            .read(cyclingPatternDetectorProvider.notifier)
            .isCycling(),
        isTrue,
      );
    });

    test('is false for a resting device', () async {
      final container = containerFor(
        buildWindow(count: 150, accelMagnitude: 9.8, gyroMagnitude: 0.0),
      );

      expect(
        await container
            .read(cyclingPatternDetectorProvider.notifier)
            .isCycling(),
        isFalse,
      );
    });

    test('is false when no window is available', () async {
      final container = containerFor(null);

      expect(
        await container
            .read(cyclingPatternDetectorProvider.notifier)
            .isCycling(),
        isFalse,
      );
    });
  });

  // ---------------------------------------------------------------------------
  // The stream itself (polls the motion service once a second)
  // ---------------------------------------------------------------------------

  group('CyclingPatternDetector - stream', () {
    test('emits a classification about once a second', () async {
      final container = containerFor(buildWindow(count: 300, peakEvery: 42));
      // Hold a subscription so the auto-dispose provider stays alive while the
      // 1 s poll ticks.
      final sub = container.listen(cyclingPatternDetectorProvider, (_, _) {});
      addTearDown(sub.close);

      final first = await container
          .read(cyclingPatternDetectorProvider.future)
          .timeout(const Duration(seconds: 5));

      expect(first.activity, equals(ActivityType.cycling));
    });

    test('emits unknown while the motion buffer is empty', () async {
      final container = containerFor(null);
      final sub = container.listen(cyclingPatternDetectorProvider, (_, _) {});
      addTearDown(sub.close);

      final first = await container
          .read(cyclingPatternDetectorProvider.future)
          .timeout(const Duration(seconds: 5));

      expect(first.activity, equals(ActivityType.unknown));
    });
  });
}

/// Feeds the detector a fixed motion window.
///
/// Overriding `build()` keeps the real service's `ref.listen` on the sensor
/// stream out of the way; `getCurrentWindow()` is the only thing the detector
/// actually calls.
class _FakeMotionDetectionService extends MotionDetectionService {
  _FakeMotionDetectionService(this._window);

  final MotionWindow? _window;

  @override
  Stream<MotionState> build() => const Stream<MotionState>.empty();

  @override
  MotionWindow? getCurrentWindow() => _window;
}
