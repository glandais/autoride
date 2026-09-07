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

    test('the cycling ramp clears a phone at rest by an order of magnitude', () {
      // T051 corrected the scale these were first set from: the 1 Hz `sens`
      // series T050 used is a series of *instants* and overstates the spread
      // within a second by roughly 2x. On the true 50 Hz figures, a phone lying
      // still for 93 minutes reads a median `asd` of 0.01 and a p99 of 0.34,
      // and its whole distribution has to sit under the foot of the ramp — that
      // margin is what produced zero false starts across those 93 minutes.
      expect(AppConstants.cyclingAccelStdMin, greaterThan(5 * 0.34));
      expect(AppConstants.cyclingGyroMeanMin, greaterThan(0.23));

      // The other side: a real ride's windows have to be able to reach the
      // plateau. p90 of the 2026-09-06 ride is 5.34 / 1.76.
      expect(AppConstants.cyclingAccelStdIdeal, lessThan(5.34));
      expect(AppConstants.cyclingGyroMeanIdeal, lessThan(1.76));

      // A single arm cannot start a ride on its own, whichever one it is.
      expect(0.5 * 1.0, lessThan(AppConstants.tripStartConfidenceThreshold));
    });

    test('the vehicle veto sits above a bicycle and below a car (T051)', () {
      // 2026-09-07, provider-measured speeds only: the night ride's fastest is
      // 31.6 km/h, the drive's cruise is five consecutive fixes at 38.0-39.3.
      // The threshold has to fit between them, and it must NOT be
      // `maxCyclingSpeedKmh` — the drive never came near 60, which is why a
      // "no bicycle goes this fast" rule catches nothing real.
      expect(AppConstants.vehicleSpeedKmh, greaterThan(31.6));
      expect(AppConstants.vehicleSpeedKmh, lessThan(38.0));
      expect(
        AppConstants.vehicleSpeedKmh,
        lessThan(AppConstants.maxCyclingSpeedKmh),
      );
      // The live arm needs a majority of its window, not one artefact.
      expect(
        AppConstants.vehicleSpeedMinFixes,
        greaterThan(AppConstants.vehicleSpeedWindowFixes / 2),
      );
      // And a drive must not be turned into a string of discarded trips.
      expect(
        AppConstants.vehicleCooldownPeriodSeconds,
        greaterThan(AppConstants.tripStartCooldownPeriodSeconds),
      );
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
