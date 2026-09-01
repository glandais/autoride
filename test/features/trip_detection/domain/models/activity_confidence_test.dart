import 'package:flutter_test/flutter_test.dart';
import 'package:autoride/core/constants/app_constants.dart';
import 'package:autoride/features/trip_detection/domain/models/activity_confidence.dart';

/// Moved out of `cycling_pattern_detector_test.dart`, which was named for a
/// service it never imported (L-011).
void main() {
  group('ActivityConfidence', () {
    test('should create cycling activity with high confidence', () {
      final confidence = ActivityConfidence.cycling(
        confidence: 0.85,
        motionScore: 0.9,
        speedScore: 0.8,
        frequencyScore: 0.85,
      );

      expect(confidence.activity, equals(ActivityType.cycling));
      expect(confidence.confidence, equals(0.85));
      expect(confidence.isCyclingDetected, isTrue);
      expect(confidence.level, equals(ConfidenceLevel.high));
    });

    test('should identify ambiguous detection', () {
      final confidence = ActivityConfidence.cycling(
        confidence: 0.5,
        motionScore: 0.6,
        speedScore: 0.4,
        frequencyScore: 0.5,
      );

      expect(confidence.isAmbiguous, isTrue);
      expect(confidence.level, equals(ConfidenceLevel.low));
    });

    test('should calculate correct confidence level', () {
      expect(
        ActivityConfidence.cycling(
          confidence: 0.95,
          motionScore: 1.0,
          speedScore: 0.9,
          frequencyScore: 0.95,
        ).level,
        equals(ConfidenceLevel.veryHigh),
      );

      expect(
        ActivityConfidence.cycling(
          confidence: 0.3,
          motionScore: 0.4,
          speedScore: 0.2,
          frequencyScore: 0.3,
        ).level,
        equals(ConfidenceLevel.veryLow),
      );
    });

    test('should create from scores and find best activity', () {
      final activityScores = {
        ActivityType.cycling: 0.85,
        ActivityType.walking: 0.3,
        ActivityType.stationary: 0.1,
        ActivityType.driving: 0.2,
        ActivityType.running: 0.25,
        ActivityType.unknown: 0.0,
      };

      final confidence = ActivityConfidence.fromScores(
        motionScore: 0.9,
        speedScore: 0.8,
        frequencyScore: 0.85,
        activityScores: activityScores,
      );

      expect(confidence.activity, equals(ActivityType.cycling));
      expect(confidence.secondBestActivity, equals(ActivityType.walking));
    });

    test('fromScores combines the layers with the documented weights', () {
      final confidence = ActivityConfidence.fromScores(
        motionScore: 1.0,
        speedScore: 0.5,
        frequencyScore: 0.0,
        activityScores: const {ActivityType.cycling: 0.9},
      );

      expect(
        confidence.confidence,
        closeTo(
          AppConstants.motionScoreWeight + 0.5 * AppConstants.speedScoreWeight,
          1e-9,
        ),
      );
    });

    test('unknown() has zero scores', () {
      final confidence = ActivityConfidence.unknown();

      expect(confidence.activity, equals(ActivityType.unknown));
      expect(confidence.confidence, equals(0.0));
      expect(confidence.isCyclingDetected, isFalse);
      expect(confidence.secondBestActivity, isNull);
    });
  });
}
