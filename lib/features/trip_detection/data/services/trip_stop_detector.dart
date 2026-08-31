import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../domain/models/location_data.dart';
import '../../domain/models/motion_data.dart';
import '../../domain/models/trip_stop_state.dart';
import '../../../../core/constants/app_constants.dart';

part 'trip_stop_detector.g.dart';

/// Service that detects when a cycling trip should pause or stop
///
/// Analyzes motion and GPS data to distinguish between:
/// - Brief stops (traffic lights): Keep trip active
/// - Moderate pauses (rest stops): Pause trip, allow resume
/// - Extended stops (trip end): Stop trip and finalize
@riverpod
class TripStopDetector extends _$TripStopDetector {
  @override
  TripStopState build() {
    return TripStopState.initial();
  }

  /// Analyze motion and GPS data to determine trip stop decision
  ///
  /// Returns [StopDecision] indicating whether to continue, pause, or stop trip.
  ///
  /// Called for every motion sample (50 Hz). The stationary and movement
  /// counters only advance once per
  /// [AppConstants.detectionEvaluationInterval], so
  /// `minConsecutiveStationaryDetections` and
  /// `tripStopMovementHysteresisSamples` mean seconds rather than a few tens of
  /// milliseconds. Uncounted samples still keep the pause timer up to date.
  ///
  /// [now] exists so tests can drive the clock deterministically; production
  /// callers omit it.
  Future<StopDecision> analyzeForTripStop(
    MotionData motion,
    LocationData? location, {
    DateTime? now,
  }) async {
    final timestamp = now ?? DateTime.now();

    // Check if currently stationary
    final isStationary = _isStationary(motion, location);

    final canCount = state.canCountDetection(
      timestamp,
      AppConstants.detectionEvaluationInterval,
    );

    if (isStationary) {
      // Increment consecutive stationary detections.
      // A stationary reading also clears the movement hysteresis counter so a
      // single transient spike between two stationary readings is forgiven.
      if (state.consecutiveStationaryDetections == 0) {
        // First stationary detection - start pause timer
        state = state.startPause(timestamp);
      } else if (canCount) {
        // Continue tracking stationary state
        state = state.incrementStationary(timestamp);
      }

      // Update pause duration
      state = state.updatePauseDuration(timestamp);

      // Determine decision based on pause duration
      return _evaluatePauseDuration();
    } else {
      // Movement detected. GPS speed at a true standstill is noisy, so we
      // debounce: only reset the accumulated pause once movement is sustained
      // across `tripStopMovementHysteresisSamples` counted readings. A single
      // transient reading must not zero the pause timer.
      if (state.isStationary) {
        if (canCount) {
          state = state.incrementMovement(timestamp);
        }

        if (state.consecutiveMovementDetections >=
            AppConstants.tripStopMovementHysteresisSamples) {
          // Sustained movement confirmed - reset the pause.
          state = state.resetPause();
          return StopDecision.continueTrip;
        }

        // Not yet confirmed as movement: keep the pause accumulating so the
        // auto-stop / auto-pause logic still applies despite the noisy sample.
        state = state.updatePauseDuration(timestamp);
        return _evaluatePauseDuration();
      }
      return StopDecision.continueTrip;
    }
  }

  /// Check if trip should resume after pause
  ///
  /// Returns true only once movement has been sustained for
  /// [AppConstants.resumeMovementThresholdSeconds]; a single non-stationary
  /// sample (a bump, a GPS speed spike) must not resume a paused trip.
  ///
  /// [now] exists so tests can drive the clock deterministically.
  bool shouldResumeTrip(
    MotionData motion,
    LocationData? location, {
    DateTime? now,
  }) {
    final timestamp = now ?? DateTime.now();

    if (_isStationary(motion, location)) {
      // Movement interrupted - restart the sustained-movement timer.
      if (state.movementStartTime != null) {
        state = state.copyWith(movementStartTime: null);
      }
      return false;
    }

    final movementStart = state.movementStartTime;
    if (movementStart == null) {
      state = state.copyWith(movementStartTime: timestamp);
      return false;
    }

    return timestamp.difference(movementStart) >=
        const Duration(seconds: AppConstants.resumeMovementThresholdSeconds);
  }

  /// Reset detection state
  void reset() {
    state = TripStopState.initial();
  }

  /// Check if motion and GPS indicate stationary state
  bool _isStationary(MotionData motion, LocationData? location) {
    // Check motion thresholds.
    // Accelerometer magnitude includes gravity, so a stationary device reads
    // ~standardGravity. Compare the deviation from gravity, not the raw value.
    final accelDeviation =
        (motion.accelerometer.magnitude - AppConstants.standardGravity).abs();
    final gyroMagnitude = motion.gyroscope.magnitude;

    final isMotionStationary =
        accelDeviation <= AppConstants.stationaryAccelerationMax &&
            gyroMagnitude <= AppConstants.stationaryRotationMax;

    // If GPS available, validate with speed
    if (location != null) {
      final speedKmh = location.speedKmh;
      final isSpeedStationary =
          speedKmh < 2.0; // Less than 2 km/h is stationary

      // Both motion and speed must indicate stationary
      return isMotionStationary && isSpeedStationary;
    }

    // GPS unavailable - use motion only (without consecutive requirement)
    // Consecutive detections are tracked separately in analyzeForTripStop
    return isMotionStationary;
  }

  /// Evaluate pause duration and return appropriate decision
  StopDecision _evaluatePauseDuration() {
    final pauseSeconds = state.pauseDuration.inSeconds;

    // Check if should stop trip (extended pause)
    if (pauseSeconds >= AppConstants.maxPauseDurationSeconds) {
      return StopDecision.stopTrip;
    }

    // Check if should pause trip (moderate pause)
    if (pauseSeconds >= AppConstants.minPauseDurationSeconds &&
        state.consecutiveStationaryDetections >=
            AppConstants.minConsecutiveStationaryDetections) {
      return StopDecision.pauseTrip;
    }

    // Brief pause - continue trip
    return StopDecision.continueTrip;
  }
}
