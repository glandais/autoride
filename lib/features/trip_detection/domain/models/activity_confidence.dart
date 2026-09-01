import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:autoride/core/constants/app_constants.dart';

part 'activity_confidence.freezed.dart';

/// Activity types that can be detected
enum ActivityType {
  stationary, // Not moving
  walking, // Walking or slow movement
  cycling, // Cycling (target activity)
  driving, // In vehicle
  running, // Running or fast movement
  unknown, // Insufficient data
}

/// Confidence level for activity classification
enum ConfidenceLevel {
  veryLow, // 0-0.4
  low, // 0.4-0.6
  medium, // 0.6-0.8
  high, // 0.8-0.9
  veryHigh, // 0.9-1.0
}

/// Activity classification with confidence scores
@freezed
sealed class ActivityConfidence with _$ActivityConfidence {
  const ActivityConfidence._();

  const factory ActivityConfidence({
    required ActivityType activity,
    required double confidence, // 0.0-1.0
    required double motionScore, // Motion pattern score
    required double speedScore, // GPS speed validation score
    required double frequencyScore, // Pedaling frequency score
    Map<ActivityType, double>? allScores, // Scores for all activities
  }) = _ActivityConfidence;

  /// Create from individual scores
  factory ActivityConfidence.fromScores({
    required double motionScore,
    required double speedScore,
    required double frequencyScore,
    required Map<ActivityType, double> activityScores,
  }) {
    // Find activity with highest score
    ActivityType bestActivity = ActivityType.unknown;
    double bestScore = 0.0;

    activityScores.forEach((activity, score) {
      if (score > bestScore) {
        bestActivity = activity;
        bestScore = score;
      }
    });

    // Calculate combined confidence using the documented weights
    // (motion 40%, speed 35%, frequency 25%) for consistency with the
    // per-activity cycling score in CyclingPatternDetector.
    final combinedConfidence =
        (motionScore * AppConstants.motionScoreWeight) +
        (speedScore * AppConstants.speedScoreWeight) +
        (frequencyScore * AppConstants.frequencyScoreWeight);

    return ActivityConfidence(
      activity: bestActivity,
      confidence: combinedConfidence,
      motionScore: motionScore,
      speedScore: speedScore,
      frequencyScore: frequencyScore,
      allScores: activityScores,
    );
  }

  /// Create unknown activity
  factory ActivityConfidence.unknown() {
    return const ActivityConfidence(
      activity: ActivityType.unknown,
      confidence: 0.0,
      motionScore: 0.0,
      speedScore: 0.0,
      frequencyScore: 0.0,
    );
  }

  /// Create cycling activity with confidence
  factory ActivityConfidence.cycling({
    required double confidence,
    required double motionScore,
    required double speedScore,
    required double frequencyScore,
  }) {
    return ActivityConfidence(
      activity: ActivityType.cycling,
      confidence: confidence,
      motionScore: motionScore,
      speedScore: speedScore,
      frequencyScore: frequencyScore,
    );
  }
}

/// Extension for ActivityConfidence functionality
extension ActivityConfidenceExtensions on ActivityConfidence {
  /// Get confidence level category
  ConfidenceLevel get level {
    if (confidence < 0.4) return ConfidenceLevel.veryLow;
    if (confidence < 0.6) return ConfidenceLevel.low;
    if (confidence < 0.8) return ConfidenceLevel.medium;
    if (confidence < 0.9) return ConfidenceLevel.high;
    return ConfidenceLevel.veryHigh;
  }

  /// Check if cycling is detected with reasonable confidence
  bool get isCyclingDetected {
    return activity == ActivityType.cycling && confidence >= 0.6;
  }

  /// Check if activity is ambiguous (low confidence)
  bool get isAmbiguous {
    return confidence < 0.6;
  }

  /// Get second most likely activity
  ActivityType? get secondBestActivity {
    if (allScores == null || allScores!.length < 2) return null;

    final sorted = allScores!.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return sorted.length > 1 ? sorted[1].key : null;
  }
}
