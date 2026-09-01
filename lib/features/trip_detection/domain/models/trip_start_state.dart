import 'package:freezed_annotation/freezed_annotation.dart';

part 'trip_start_state.freezed.dart';

/// Represents the state of trip start detection
///
/// Tracks confidence levels, consecutive detections, and cooldown status
/// to determine when a cycling trip should automatically start.
@freezed
sealed class TripStartState with _$TripStartState {
  const TripStartState._();

  const factory TripStartState({
    /// Current confidence score (0.0-1.0) that cycling is occurring
    required double confidence,

    /// Number of consecutive positive detections
    required int consecutiveDetections,

    /// Timestamp of the last detection
    required DateTime? lastDetectionTime,

    /// Whether cooldown is active (prevents immediate restart after false start)
    required bool cooldownActive,

    /// Timestamp when cooldown was activated
    required DateTime? cooldownStartTime,
  }) = _TripStartState;

  /// Create initial state
  factory TripStartState.initial() {
    return const TripStartState(
      confidence: 0.0,
      consecutiveDetections: 0,
      lastDetectionTime: null,
      cooldownActive: false,
      cooldownStartTime: null,
    );
  }
}

/// Extension methods for TripStartState
extension TripStartStateExtensions on TripStartState {
  /// Check if enough time has passed since last detection
  /// to consider detections as consecutive
  bool isWithinDetectionWindow(DateTime now, Duration windowDuration) {
    if (lastDetectionTime == null) return true;
    return now.difference(lastDetectionTime!).inSeconds <=
        windowDuration.inSeconds;
  }

  /// Check if cooldown period has expired
  bool isCooldownExpired(DateTime now, Duration cooldownDuration) {
    if (!cooldownActive || cooldownStartTime == null) return true;
    return now.difference(cooldownStartTime!).inSeconds >=
        cooldownDuration.inSeconds;
  }

  /// Reset detection state (clears consecutive detections and confidence)
  TripStartState reset() {
    return copyWith(
      confidence: 0.0,
      consecutiveDetections: 0,
      lastDetectionTime: null,
    );
  }

  /// Activate cooldown
  TripStartState activateCooldown(DateTime now) {
    return copyWith(
      cooldownActive: true,
      cooldownStartTime: now,
      confidence: 0.0,
      consecutiveDetections: 0,
    );
  }

  /// Deactivate cooldown
  TripStartState deactivateCooldown() {
    return copyWith(cooldownActive: false, cooldownStartTime: null);
  }
}
