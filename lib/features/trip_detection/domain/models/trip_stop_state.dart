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
  }) = _TripStopState;

  /// Create initial state
  factory TripStopState.initial() {
    return const TripStopState(
      isStationary: false,
      pauseStartTime: null,
      pauseDuration: Duration.zero,
      consecutiveStationaryDetections: 0,
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

  /// Start pause tracking
  TripStopState startPause(DateTime now) {
    return copyWith(
      isStationary: true,
      pauseStartTime: now,
      pauseDuration: Duration.zero,
      consecutiveStationaryDetections: consecutiveStationaryDetections + 1,
    );
  }

  /// Reset pause (movement detected)
  TripStopState resetPause() {
    return copyWith(
      isStationary: false,
      pauseStartTime: null,
      pauseDuration: Duration.zero,
      consecutiveStationaryDetections: 0,
    );
  }

  /// Increment consecutive stationary detections
  TripStopState incrementStationary() {
    return copyWith(
      consecutiveStationaryDetections: consecutiveStationaryDetections + 1,
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
