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
  Future<StopDecision> analyzeForTripStop(
    MotionData motion,
    LocationData? location,
  ) async {
    final now = DateTime.now();

    // Check if currently stationary
    final isStationary = _isStationary(motion, location);

    if (isStationary) {
      // Increment consecutive stationary detections
      if (state.consecutiveStationaryDetections == 0) {
        // First stationary detection - start pause timer
        state = state.startPause(now);
      } else {
        // Continue tracking stationary state
        state = state.incrementStationary();
      }

      // Update pause duration
      state = state.updatePauseDuration(now);

      // Determine decision based on pause duration
      return _evaluatePauseDuration();
    } else {
      // Movement detected - reset pause state
      if (state.isStationary) {
        state = state.resetPause();
      }
      return StopDecision.continueTrip;
    }
  }

  /// Check if trip should resume after pause
  ///
  /// Returns true if sustained movement detected.
  bool shouldResumeTrip(MotionData motion, LocationData? location) {
    return !_isStationary(motion, location);
  }

  /// Reset detection state
  void reset() {
    state = TripStopState.initial();
  }

  /// Check if motion and GPS indicate stationary state
  bool _isStationary(MotionData motion, LocationData? location) {
    // Check motion thresholds
    final accelMagnitude = motion.accelerometer.magnitude;
    final gyroMagnitude = motion.gyroscope.magnitude;

    final isMotionStationary =
        accelMagnitude <= AppConstants.stationaryAccelerationMax &&
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
