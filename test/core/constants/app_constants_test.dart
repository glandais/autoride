import 'package:flutter_test/flutter_test.dart';
import 'package:autoride/core/constants/app_constants.dart';

/// Threshold-consistency checks. Moved out of
/// `cycling_pattern_detector_test.dart`, which was named for a service it never
/// imported (L-011); these assert on `AppConstants`, not on the detector.
void main() {
  group('AppConstants - cycling thresholds', () {
    test('should have valid acceleration thresholds', () {
      expect(AppConstants.cyclingAccelerationMin, equals(10.0));
      expect(AppConstants.cyclingAccelerationMax, equals(20.0));
      expect(AppConstants.walkingAccelerationMax, equals(12.0));
      expect(
        AppConstants.cyclingAccelerationMin,
        lessThan(AppConstants.cyclingAccelerationMax),
      );
    });

    test('should have valid rotation thresholds', () {
      expect(AppConstants.cyclingRotationMin, equals(0.5));
      expect(AppConstants.cyclingRotationMax, equals(3.0));
      expect(
        AppConstants.cyclingRotationMin,
        lessThan(AppConstants.cyclingRotationMax),
      );
    });

    test('the windowed cycling fit ramps in the right order (T050)', () {
      // A ramp that is not ordered min < ideal <= max would either score a
      // still phone or never score a bicycle, and neither would be visible in
      // any test that only reads the detector's verdict.
      expect(
        AppConstants.cyclingAccelStdMin,
        lessThan(AppConstants.cyclingAccelStdIdeal),
      );
      expect(
        AppConstants.cyclingAccelStdIdeal,
        lessThan(AppConstants.cyclingAccelStdMax),
      );
      expect(
        AppConstants.cyclingGyroMeanMin,
        lessThan(AppConstants.cyclingGyroMeanIdeal),
      );
      expect(
        AppConstants.cyclingGyroMeanIdeal,
        lessThan(AppConstants.cyclingGyroMeanMax),
      );
      expect(AppConstants.tripStartMotionWindowMinSamples, greaterThan(1));
    });

    test('the cycling ramp starts above what a carried phone produces', () {
      // The 2026-09-06 log, 1 Hz `sens` samples: walking about with the phone
      // in a pocket reads std 1.86 and mean |gyro| 0.65, the ride 3.4-3.9 and
      // 1.08-1.32.
      //
      // The *acceleration* minimum is the one that has to clear the walking
      // figure, and it is what a walk fails on. The gyroscope minimum
      // deliberately does not: a pocket swings, so a walk scores about half
      // that arm, and half of half a score has never started anything. Erring
      // low on the acceleration arm is what would start a ride on a walk —
      // the failure T049 was opened for.
      expect(AppConstants.cyclingAccelStdMin, greaterThan(1.86));
      // …and the ideal has to be reachable by an actual bicycle.
      expect(AppConstants.cyclingAccelStdIdeal, lessThan(3.39));
      expect(AppConstants.cyclingGyroMeanIdeal, lessThan(1.08));
      // A walk cannot reach the threshold on the gyroscope arm alone.
      expect(0.5 * 1.0, lessThan(AppConstants.tripStartConfidenceThreshold));
    });

    test('should have valid frequency thresholds', () {
      expect(AppConstants.pedalingFrequencyMin, equals(0.5)); // 30 RPM
      expect(AppConstants.pedalingFrequencyMax, equals(2.0)); // 120 RPM
      expect(
        AppConstants.pedalingFrequencyMin,
        lessThan(AppConstants.pedalingFrequencyTypical),
      );
      expect(
        AppConstants.pedalingFrequencyTypical,
        lessThan(AppConstants.pedalingFrequencyMax),
      );
    });

    test('should have valid speed thresholds', () {
      expect(AppConstants.cyclingSpeedMin, equals(8.0));
      expect(AppConstants.cyclingSpeedMax, equals(40.0));
      expect(AppConstants.cyclingSpeedTypical, equals(18.0));
      expect(
        AppConstants.cyclingSpeedMin,
        lessThan(AppConstants.cyclingSpeedTypical),
      );
      expect(
        AppConstants.cyclingSpeedTypical,
        lessThan(AppConstants.cyclingSpeedMax),
      );
    });

    test('should have valid confidence thresholds', () {
      expect(AppConstants.minConfidenceForDetection, equals(0.6));
      expect(AppConstants.highConfidenceThreshold, equals(0.8));
      expect(
        AppConstants.minConfidenceForDetection,
        lessThan(AppConstants.highConfidenceThreshold),
      );
    });

    test('should have valid classification weights', () {
      expect(AppConstants.motionScoreWeight, equals(0.4));
      expect(AppConstants.speedScoreWeight, equals(0.35));
      expect(AppConstants.frequencyScoreWeight, equals(0.25));

      const total =
          AppConstants.motionScoreWeight +
          AppConstants.speedScoreWeight +
          AppConstants.frequencyScoreWeight;
      expect(total, closeTo(1.0, 0.01));
    });
  });
}
