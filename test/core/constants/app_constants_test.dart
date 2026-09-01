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
