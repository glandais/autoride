import 'dart:async';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../domain/models/motion_data.dart';
import '../../domain/models/activity_confidence.dart';
import '../../domain/models/location_data.dart';
import '../../../../core/constants/app_constants.dart';
import 'motion_detection_service.dart';
import 'sensor_utils.dart';

part 'cycling_pattern_detector.g.dart';

/// Cycling pattern detector service
/// Analyzes motion patterns to detect cycling activity
@riverpod
class CyclingPatternDetector extends _$CyclingPatternDetector {
  @override
  Stream<ActivityConfidence> build() async* {
    // Note: Location-based speed validation is currently optional
    // In future, integrate with location service for GPS speed validation
    LocationData? currentLocation;

    // Get motion detection service
    final motionService = ref.watch(motionDetectionServiceProvider.notifier);

    // Analyze motion window periodically
    await for (final _ in Stream.periodic(const Duration(seconds: 1))) {
      final window = motionService.getCurrentWindow();

      if (window != null && window.hasEnoughSamples) {
        final confidence = _analyzePattern(window, currentLocation);
        yield confidence;
      } else {
        yield ActivityConfidence.unknown();
      }
    }
  }

  /// Analyze motion pattern and classify activity
  ActivityConfidence _analyzePattern(
    MotionWindow window,
    LocationData? location,
  ) {
    // Layer 1: Motion pattern analysis
    final motionScore = _analyzeMotionPattern(window);

    // Layer 2: Pedaling frequency analysis
    final frequencyScore = _analyzePedalingFrequency(window);

    // Layer 3: GPS speed validation (if available)
    final speedScore = location != null
        ? _analyzeSpeedPattern(location)
        : 0.5; // Neutral score if no GPS

    // Calculate confidence scores for each activity
    final activityScores = _calculateActivityScores(
      motionScore,
      frequencyScore,
      speedScore,
      window,
    );

    return ActivityConfidence.fromScores(
      motionScore: motionScore,
      speedScore: speedScore,
      frequencyScore: frequencyScore,
      activityScores: activityScores,
    );
  }

  /// Analyze motion pattern (acceleration + rotation)
  double _analyzeMotionPattern(MotionWindow window) {
    final avgAccel = window.averageAcceleration;
    final avgRotation = window.averageRotation;

    double score = 0.0;

    // Check acceleration range for cycling
    if (avgAccel >= AppConstants.cyclingAccelerationMin &&
        avgAccel <= AppConstants.cyclingAccelerationMax) {
      score += 0.5;
    } else if (avgAccel < AppConstants.cyclingAccelerationMin) {
      score += 0.2; // Too low for cycling
    }

    // Check rotation for cycling
    if (avgRotation >= AppConstants.cyclingRotationMin &&
        avgRotation <= AppConstants.cyclingRotationMax) {
      score += 0.5;
    }

    return score.clamp(0.0, 1.0);
  }

  /// Analyze pedaling frequency
  double _analyzePedalingFrequency(MotionWindow window) {
    if (window.samples.length < AppConstants.minSamplesForPattern) {
      return 0.0;
    }

    // Extract acceleration magnitudes
    final accelMagnitudes = window.samples
        .map((s) => s.accelerometer.magnitude)
        .toList();

    // Detect peaks (pedaling cycles)
    final peaks = _detectPeaks(accelMagnitudes);

    if (peaks.length < 2) {
      return 0.0; // Not enough peaks to determine frequency
    }

    // Calculate average time between peaks (pedaling frequency)
    final avgTimeBetweenPeaks = window.duration.inMilliseconds /
        (peaks.length - 1);
    final frequency = 1000.0 / avgTimeBetweenPeaks; // Hz

    // Check if frequency matches cycling range
    if (frequency >= AppConstants.pedalingFrequencyMin &&
        frequency <= AppConstants.pedalingFrequencyMax) {
      // Calculate how close to typical cycling frequency
      final distanceFromTypical =
          (frequency - AppConstants.pedalingFrequencyTypical).abs();
      const maxDistance = AppConstants.pedalingFrequencyMax -
          AppConstants.pedalingFrequencyMin;
      final score = 1.0 - (distanceFromTypical / maxDistance);
      return score.clamp(0.6, 1.0); // Cycling frequency detected
    }

    return 0.3; // Periodic motion but not cycling frequency
  }

  /// Detect peaks in acceleration data (pedaling cycles)
  List<int> _detectPeaks(List<double> values) {
    final peaks = <int>[];

    for (var i = 1; i < values.length - 1; i++) {
      if (SensorUtils.isPeak(values, i, threshold: 10.0)) {
        peaks.add(i);
      }
    }

    return peaks;
  }

  /// Analyze GPS speed pattern
  double _analyzeSpeedPattern(LocationData location) {
    final speedKmh = location.speed * 3.6; // m/s to km/h

    // Check if speed is in cycling range
    if (speedKmh >= AppConstants.cyclingSpeedMin &&
        speedKmh <= AppConstants.cyclingSpeedMax) {
      // Calculate how typical the speed is for cycling
      final distanceFromTypical =
          (speedKmh - AppConstants.cyclingSpeedTypical).abs();
      const maxDistance = AppConstants.cyclingSpeedMax -
          AppConstants.cyclingSpeedMin;
      final score = 1.0 - (distanceFromTypical / maxDistance);
      return score.clamp(0.6, 1.0);
    } else if (speedKmh < AppConstants.cyclingSpeedMin) {
      return 0.3; // Too slow, likely walking
    } else {
      return 0.2; // Too fast, likely driving
    }
  }

  /// Calculate confidence scores for all activities
  Map<ActivityType, double> _calculateActivityScores(
    double motionScore,
    double frequencyScore,
    double speedScore,
    MotionWindow window,
  ) {
    final avgAccel = window.averageAcceleration;
    final avgRotation = window.averageRotation;

    // Cycling score (weighted average)
    final cyclingScore = (motionScore * AppConstants.motionScoreWeight) +
        (frequencyScore * AppConstants.frequencyScoreWeight) +
        (speedScore * AppConstants.speedScoreWeight);

    // Stationary score
    final stationaryScore = (avgAccel < 10.0 && avgRotation < 0.3) ? 0.9 : 0.1;

    // Walking score
    final walkingScore = (avgAccel >= 10.0 &&
            avgAccel < 12.0 &&
            frequencyScore < 0.5 &&
            speedScore < 0.4)
        ? 0.7
        : 0.2;

    // Driving score
    final drivingScore = (avgAccel > 10.0 &&
            avgRotation < 1.0 &&
            speedScore < 0.3) // High speed
        ? 0.6
        : 0.2;

    // Running score
    final runningScore = (avgAccel > 12.0 &&
            frequencyScore > 0.5 &&
            frequencyScore < 0.7 &&
            speedScore < 0.5)
        ? 0.6
        : 0.2;

    return {
      ActivityType.cycling: cyclingScore.clamp(0.0, 1.0),
      ActivityType.stationary: stationaryScore.clamp(0.0, 1.0),
      ActivityType.walking: walkingScore.clamp(0.0, 1.0),
      ActivityType.driving: drivingScore.clamp(0.0, 1.0),
      ActivityType.running: runningScore.clamp(0.0, 1.0),
      ActivityType.unknown: 0.0,
    };
  }

  /// Get current activity classification
  Future<ActivityConfidence> getCurrentActivity() async {
    final window = ref.read(motionDetectionServiceProvider.notifier)
        .getCurrentWindow();

    if (window == null || !window.hasEnoughSamples) {
      return ActivityConfidence.unknown();
    }

    // Get current location (simplified - use cached value or null)
    LocationData? location;
    // Note: In practice, you would get the latest location from a cache or stream

    return _analyzePattern(window, location);
  }

  /// Check if currently cycling with high confidence
  Future<bool> isCycling() async {
    final activity = await getCurrentActivity();
    return activity.isCyclingDetected;
  }
}
