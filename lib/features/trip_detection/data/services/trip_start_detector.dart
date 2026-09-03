import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../domain/models/location_data.dart';
import '../../domain/models/motion_data.dart';
import '../../domain/models/trip_start_state.dart';
import '../../../../core/audit/audit_event.dart';
import '../../../../core/audit/audit_log.dart';
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
  ///
  /// This is called for every motion sample (50 Hz), but a *detection* is
  /// counted at most once per [AppConstants.detectionEvaluationInterval], so
  /// `tripStartMinConsecutiveDetections` means seconds of sustained cycling
  /// rather than a few tens of milliseconds. Samples arriving inside the
  /// current interval still refresh the confidence score.
  ///
  /// "Sustained" is now literal (L-093): the streak requires a positive
  /// detection in *every* interval, and one interval passing without one
  /// resets it to zero. `tripStartDetectionWindowSeconds` no longer bounds the
  /// streak — it only guards against resuming a stale one across a gap in
  /// which nothing was evaluated at all.
  ///
  /// [now] exists so tests can drive the clock deterministically; production
  /// callers omit it.
  Future<bool> analyzeForTripStart(
    MotionData motion,
    LocationData? location, {
    DateTime? now,
  }) async {
    final timestamp = now ?? DateTime.now();
    return _analyze(motion, location, timestamp);
  }

  Future<bool> _analyze(
    MotionData motion,
    LocationData? location,
    DateTime now,
  ) async {
    // Check if cooldown is still active
    if (state.cooldownActive) {
      if (state.isCooldownExpired(
        now,
        const Duration(seconds: AppConstants.tripStartCooldownPeriodSeconds),
      )) {
        // Cooldown expired, deactivate it. Journalled because the blind
        // window it opened is a reason a departure could be missed, and its
        // end is what makes the window measurable against `cool a:"arm"`.
        AuditLog.emit(
          AuditEvent.cooldown,
          () => <String, Object?>{
            'a': 'expire',
            'd': AppConstants.tripStartCooldownPeriodSeconds,
          },
          critical: true,
        );
        state = state.deactivateCooldown();
      } else {
        // Still in cooldown, don't detect
        return false;
      }
    }

    // Calculate confidence score
    final confidence = _calculateStartConfidence(motion, location, now);

    // A new detection is only counted once per evaluation interval, and the
    // same boundary decides when the streak has missed one.
    final lastDetection = state.lastDetectionTime;
    final intervalElapsed =
        lastDetection == null ||
        now.difference(lastDetection) >=
            AppConstants.detectionEvaluationInterval;

    // Update state based on confidence and timing
    if (confidence >= AppConstants.tripStartConfidenceThreshold) {
      // Positive detection
      if (!intervalElapsed) {
        // Same evaluation interval: refresh confidence only. Do NOT advance
        // the streak or the detection timestamp, otherwise 50 Hz sampling
        // would satisfy the consecutive-detection threshold in ~60 ms.
        state = state.copyWith(confidence: confidence);
      } else {
        // A gap with no evaluation at all — the process was suspended, the
        // sensor stream stalled — leaves a streak that describes a moment that
        // is over. Start a new one rather than continuing it.
        final stale = !state.isWithinDetectionWindow(
          now,
          const Duration(seconds: AppConstants.tripStartDetectionWindowSeconds),
        );
        state = state.copyWith(
          confidence: confidence,
          consecutiveDetections: stale ? 1 : state.consecutiveDetections + 1,
          lastDetectionTime: now,
        );
      }
    } else {
      // Negative detection. The streak means *consecutive* evaluation
      // intervals, so it dies as soon as one of them has gone by without a
      // positive detection in it — which is precisely what `intervalElapsed`
      // says here, the last positive being more than one interval old (L-093).
      //
      // The previous rule kept the streak alive for as long as a positive
      // landed within `tripStartDetectionWindowSeconds` of the previous one:
      // Pixel trip 3 of the 2026-09-03 run held `n=2` through five consecutive
      // sub-threshold seconds and started a ride on the sixth. Three firm
      // gestures inside twelve seconds of cooking were enough.
      //
      // Sub-threshold samples *inside* the current interval only refresh the
      // confidence: at 50 Hz an instantaneous single-sample fit dips below the
      // threshold constantly, and one positive sample per second is what the
      // streak is counting.
      if (intervalElapsed) {
        // `confidence` is carried rather than zeroed, unlike `reset()`: the
        // audit's `c` is the reason the reset happened and reading a flat 0
        // cannot distinguish a near miss from no motion at all.
        state = state.copyWith(
          confidence: confidence,
          consecutiveDetections: 0,
          lastDetectionTime: null,
        );
      } else {
        state = state.copyWith(confidence: confidence);
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
  ///
  /// "Unavailable" means *no usable speed*, not *no object*: a fix too coarse
  /// or too old for its speed to be believed takes the motion-only path as
  /// well (T048). The alternative is the arithmetic of L-087 — such a fix
  /// scores `speedScore` 0, caps the total at `tripStartMotionWeight` (0.60)
  /// below the 0.7 threshold, and no fix at all ends up scoring higher than a
  /// bad one.
  double _calculateStartConfidence(
    MotionData motion,
    LocationData? location,
    DateTime now,
  ) {
    // Get motion pattern score from cycling detector
    final motionScore = _getMotionScore(motion);

    // If no usable GPS speed, use motion-only
    if (location == null || !location.speedIsTrustworthyAt(now)) {
      return motionScore;
    }

    // Get speed score from GPS
    final speedScore = _getSpeedScore(location);

    // Combine scores with weighted average
    final confidence =
        (motionScore * AppConstants.tripStartMotionWeight) +
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
          (AppConstants.cyclingAccelerationMin +
              AppConstants.cyclingAccelerationMax) /
          2;
      const accelRange =
          AppConstants.cyclingAccelerationMax -
          AppConstants.cyclingAccelerationMin;
      final deviation = (accelMagnitude - accelMid).abs();
      accelScore = 1.0 - (deviation / (accelRange / 2)).clamp(0.0, 1.0);
    }

    double gyroScore = 0.0;
    if (gyroMagnitude >= AppConstants.cyclingRotationMin &&
        gyroMagnitude <= AppConstants.cyclingRotationMax) {
      // Within cycling range - calculate how well it fits
      const gyroMid =
          (AppConstants.cyclingRotationMin + AppConstants.cyclingRotationMax) /
          2;
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
    const speedRange =
        AppConstants.cyclingSpeedMax - AppConstants.cyclingSpeedMin;
    final deviation = (speedKmh - typicalSpeed).abs();

    // Score decreases as deviation from typical speed increases
    return (1.0 - (deviation / speedRange)).clamp(0.0, 1.0);
  }
}
