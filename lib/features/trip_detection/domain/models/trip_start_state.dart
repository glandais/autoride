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

    /// How long the active cooldown lasts, when it is not the caller's default.
    ///
    /// `null` means "whatever the detector passes to [isCooldownExpired]",
    /// i.e. `tripStartCooldownPeriodSeconds`, which is what a false start arms.
    /// A ride discarded as a *vehicle* arms a much longer one (T051): a drive
    /// lasts half an hour, and at 30 s the rest of it would be a string of
    /// started-and-discarded trips, each with its own notification.
    Duration? cooldownDuration,
  }) = _TripStartState;

  /// Create initial state
  factory TripStartState.initial() {
    return const TripStartState(
      confidence: 0.0,
      consecutiveDetections: 0,
      lastDetectionTime: null,
      cooldownActive: false,
      cooldownStartTime: null,
      cooldownDuration: null,
    );
  }
}

/// Extension methods for TripStartState
extension TripStartStateExtensions on TripStartState {
  /// Whether the streak is still current, i.e. whether the stream of samples
  /// has been continuous enough for [consecutiveDetections] to mean anything.
  ///
  /// This is a *staleness* test, not the streak rule: the streak itself is
  /// broken by [TripStartDetector] on the first evaluation interval scoring
  /// below threshold (L-093). It only decides what to do with a positive
  /// detection arriving after a gap in which nothing was evaluated at all — a
  /// suspended process, a stalled sensor stream — where resuming an old streak
  /// would start a trip on one sample.
  ///
  /// Compares [Duration]s. The `.inSeconds <= windowDuration.inSeconds` it
  /// replaces truncated both sides, so a 5 s window silently meant 5.99 s.
  bool isWithinDetectionWindow(DateTime now, Duration windowDuration) {
    if (lastDetectionTime == null) return true;
    return now.difference(lastDetectionTime!) <= windowDuration;
  }

  /// Check if cooldown period has expired
  ///
  /// [defaultDuration] applies unless this cooldown was armed with one of its
  /// own — see the field.
  bool isCooldownExpired(DateTime now, Duration defaultDuration) {
    if (!cooldownActive || cooldownStartTime == null) return true;
    final period = cooldownDuration ?? defaultDuration;
    return now.difference(cooldownStartTime!).inSeconds >= period.inSeconds;
  }

  /// Reset detection state (clears consecutive detections and confidence)
  TripStartState reset() {
    return copyWith(
      confidence: 0.0,
      consecutiveDetections: 0,
      lastDetectionTime: null,
    );
  }

  /// Activate cooldown, optionally for a [period] other than the default.
  TripStartState activateCooldown(DateTime now, {Duration? period}) {
    return copyWith(
      cooldownActive: true,
      cooldownStartTime: now,
      cooldownDuration: period,
      confidence: 0.0,
      consecutiveDetections: 0,
    );
  }

  /// Deactivate cooldown
  TripStartState deactivateCooldown() {
    return copyWith(
      cooldownActive: false,
      cooldownStartTime: null,
      cooldownDuration: null,
    );
  }
}
