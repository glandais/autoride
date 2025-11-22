import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../domain/models/location_data.dart';
import '../../domain/models/motion_data.dart';
import '../../domain/models/trip_start_state.dart';
import '../../../../core/constants/app_constants.dart';

part 'trip_start_detector.g.dart';

/// Service that detects when a cycling trip should start
///
/// Combines motion pattern analysis with GPS speed validation
/// to determine trip start with high confidence and minimal false positives.
@riverpod
class TripStartDetector extends _$TripStartDetector {
  @override
  TripStartState build() {
    return TripStartState.initial();
  }

  /// Analyze motion and GPS data to determine if trip should start
  ///
  /// Updates internal state and returns whether trip start should be triggered.
  Future<bool> analyzeForTripStart(
    MotionData motion,
    LocationData? location,
  ) async {
    final now = DateTime.now();

    // Check if cooldown is still active
    if (state.cooldownActive) {
      if (state.isCooldownExpired(
        now,
        const Duration(seconds: AppConstants.tripStartCooldownPeriodSeconds),
      )) {
        // Cooldown expired, deactivate it
        state = state.deactivateCooldown();
      } else {
        // Still in cooldown, don't detect
        return false;
      }
    }

    // Calculate confidence score
    final confidence = _calculateStartConfidence(motion, location);

    // Check if detection is within time window
    final withinWindow = state.isWithinDetectionWindow(
      now,
      const Duration(seconds: AppConstants.tripStartDetectionWindowSeconds),
    );

    // Update state based on confidence and timing
    if (confidence >= AppConstants.tripStartConfidenceThreshold) {
      // Positive detection
      if (withinWindow) {
        // Within window, increment consecutive count
        state = state.copyWith(
          confidence: confidence,
          consecutiveDetections: state.consecutiveDetections + 1,
          lastDetectionTime: now,
        );
      } else {
        // Outside window, reset consecutive count
        state = state.copyWith(
          confidence: confidence,
          consecutiveDetections: 1,
          lastDetectionTime: now,
        );
      }
    } else {
      // Negative detection - reset if outside window
      if (!withinWindow) {
        state = state.reset();
      } else {
        // Within window but low confidence - just update confidence
        state = state.copyWith(
          confidence: confidence,
          lastDetectionTime: now,
        );
      }
    }

    // Check if should trigger trip start
    return shouldStartTrip();
  }

  /// Check if conditions are met to start trip
  bool shouldStartTrip() {
    return state.confidence >= AppConstants.tripStartConfidenceThreshold &&
        state.consecutiveDetections >=
            AppConstants.tripStartMinConsecutiveDetections &&
        !state.cooldownActive;
  }

  /// Activate cooldown period (e.g., after false start)
  void activateCooldown() {
    state = state.activateCooldown(DateTime.now());
  }

  /// Reset detection state
  void reset() {
    state = TripStartState.initial();
  }

  /// Calculate confidence score for trip start (0.0-1.0)
  ///
  /// Combines motion pattern score with GPS speed validation.
  /// If GPS unavailable, uses motion-only detection.
  double _calculateStartConfidence(
    MotionData motion,
    LocationData? location,
  ) {
    // Get motion pattern score from cycling detector
    final motionScore = _getMotionScore(motion);

    // If no GPS data, use motion-only
    if (location == null) {
      return motionScore;
    }

    // Get speed score from GPS
    final speedScore = _getSpeedScore(location);

    // Combine scores with weighted average
    final confidence = (motionScore * AppConstants.tripStartMotionWeight) +
        (speedScore * AppConstants.tripStartSpeedWeight);

    return confidence.clamp(0.0, 1.0);
  }

  /// Calculate motion pattern score (0.0-1.0)
  double _getMotionScore(MotionData motion) {
    // Calculate motion metrics
    final accelMagnitude = motion.accelerometer.magnitude;
    final gyroMagnitude = motion.gyroscope.magnitude;

    // Score based on cycling thresholds
    double accelScore = 0.0;
    if (accelMagnitude >= AppConstants.cyclingAccelerationMin &&
        accelMagnitude <= AppConstants.cyclingAccelerationMax) {
      // Within cycling range - calculate how well it fits
      const accelMid =
          (AppConstants.cyclingAccelerationMin + AppConstants.cyclingAccelerationMax) / 2;
      const accelRange =
          AppConstants.cyclingAccelerationMax - AppConstants.cyclingAccelerationMin;
      final deviation = (accelMagnitude - accelMid).abs();
      accelScore = 1.0 - (deviation / (accelRange / 2)).clamp(0.0, 1.0);
    }

    double gyroScore = 0.0;
    if (gyroMagnitude >= AppConstants.cyclingRotationMin &&
        gyroMagnitude <= AppConstants.cyclingRotationMax) {
      // Within cycling range - calculate how well it fits
      const gyroMid =
          (AppConstants.cyclingRotationMin + AppConstants.cyclingRotationMax) / 2;
      const gyroRange =
          AppConstants.cyclingRotationMax - AppConstants.cyclingRotationMin;
      final deviation = (gyroMagnitude - gyroMid).abs();
      gyroScore = 1.0 - (deviation / (gyroRange / 2)).clamp(0.0, 1.0);
    }

    // Combine acceleration and gyroscope scores
    return ((accelScore * 0.5) + (gyroScore * 0.5)).clamp(0.0, 1.0);
  }

  /// Calculate GPS speed score (0.0-1.0)
  double _getSpeedScore(LocationData location) {
    final speedKmh = location.speedKmh;

    // Check if speed is in cycling range
    if (speedKmh < AppConstants.cyclingSpeedMin) {
      // Too slow (likely walking or stationary)
      return 0.0;
    } else if (speedKmh > AppConstants.cyclingSpeedMax) {
      // Too fast (likely driving)
      return 0.0;
    }

    // Within cycling range - calculate how well it fits
    // Highest score at typical cycling speed (18 km/h)
    const typicalSpeed = AppConstants.cyclingSpeedTypical;
    const speedRange = AppConstants.cyclingSpeedMax - AppConstants.cyclingSpeedMin;
    final deviation = (speedKmh - typicalSpeed).abs();

    // Score decreases as deviation from typical speed increases
    return (1.0 - (deviation / speedRange)).clamp(0.0, 1.0);
  }
}
