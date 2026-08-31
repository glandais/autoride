import 'package:freezed_annotation/freezed_annotation.dart';

part 'trip_stop_state.freezed.dart';

/// Represents the state of trip stop detection
///
/// Tracks stationary status, pause timing, and consecutive detections
/// to determine when a cycling trip should pause or stop.
@freezed
sealed class TripStopState with _$TripStopState {
  const TripStopState._();

  const factory TripStopState({
    /// Whether the user is currently stationary
    required bool isStationary,

    /// Timestamp when pause started (null if not paused)
    required DateTime? pauseStartTime,

    /// Current pause duration
    required Duration pauseDuration,

    /// Number of consecutive stationary detections
    required int consecutiveStationaryDetections,

    /// Number of consecutive non-stationary (movement) detections.
    /// Used for hysteresis: the pause is only reset once sustained movement is
    /// observed, so a single noisy GPS speed spike doesn't clear the timer.
    @Default(0) int consecutiveMovementDetections,

    /// Timestamp of the last reading that was *counted* towards the
    /// stationary/movement counters. Motion samples arrive at 50 Hz, so
    /// counters only advance once per evaluation interval — otherwise
    /// "3 consecutive detections" would mean ~60 ms.
    @Default(null) DateTime? lastEvaluationTime,

    /// Timestamp when uninterrupted movement started while paused.
    /// Resuming requires movement sustained for
    /// `AppConstants.resumeMovementThresholdSeconds`, not a single sample.
    @Default(null) DateTime? movementStartTime,
  }) = _TripStopState;

  /// Create initial state
  factory TripStopState.initial() {
    return const TripStopState(
      isStationary: false,
      pauseStartTime: null,
      pauseDuration: Duration.zero,
      consecutiveStationaryDetections: 0,
      consecutiveMovementDetections: 0,
    );
  }
}

/// Decision enum for trip stop detection
enum StopDecision {
  /// Continue trip - keep active (brief pause or moving)
  continueTrip,

  /// Pause trip - stationary for moderate duration
  pauseTrip,

  /// Stop trip - stationary for extended duration
  stopTrip,
}

/// Extension methods for TripStopState
extension TripStopStateExtensions on TripStopState {
  /// Update pause duration based on current time
  TripStopState updatePauseDuration(DateTime now) {
    if (pauseStartTime == null) {
      return copyWith(pauseDuration: Duration.zero);
    }

    final duration = now.difference(pauseStartTime!);
    return copyWith(pauseDuration: duration);
  }

  /// Whether a new reading may be counted towards the stationary/movement
  /// counters, i.e. whether a full evaluation interval has elapsed.
  bool canCountDetection(DateTime now, Duration interval) {
    if (lastEvaluationTime == null) return true;
    return now.difference(lastEvaluationTime!) >= interval;
  }

  /// Start pause tracking
  TripStopState startPause(DateTime now) {
    return copyWith(
      isStationary: true,
      pauseStartTime: now,
      pauseDuration: Duration.zero,
      consecutiveStationaryDetections: consecutiveStationaryDetections + 1,
      consecutiveMovementDetections: 0,
      lastEvaluationTime: now,
      movementStartTime: null,
    );
  }

  /// Reset pause (sustained movement detected)
  TripStopState resetPause() {
    return copyWith(
      isStationary: false,
      pauseStartTime: null,
      pauseDuration: Duration.zero,
      consecutiveStationaryDetections: 0,
      consecutiveMovementDetections: 0,
      lastEvaluationTime: null,
    );
  }

  /// Increment consecutive stationary detections.
  /// Any stationary reading clears the movement (hysteresis) counter.
  TripStopState incrementStationary(DateTime now) {
    return copyWith(
      consecutiveStationaryDetections: consecutiveStationaryDetections + 1,
      consecutiveMovementDetections: 0,
      lastEvaluationTime: now,
      movementStartTime: null,
    );
  }

  /// Increment consecutive movement detections (hysteresis counter).
  /// Used while paused to debounce noisy non-stationary readings before the
  /// pause is reset.
  TripStopState incrementMovement(DateTime now) {
    return copyWith(
      consecutiveMovementDetections: consecutiveMovementDetections + 1,
      lastEvaluationTime: now,
    );
  }

  /// Check if pause duration exceeds threshold for pausing trip
  bool shouldPauseTrip(int minPauseDurationSeconds) {
    return pauseDuration.inSeconds >= minPauseDurationSeconds;
  }

  /// Check if pause duration exceeds threshold for stopping trip
  bool shouldStopTrip(int maxPauseDurationSeconds) {
    return pauseDuration.inSeconds >= maxPauseDurationSeconds;
  }
}
