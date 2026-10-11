import 'package:freezed_annotation/freezed_annotation.dart';

part 'trip_start_state.freezed.dart';

/// Represents the state of trip start detection
///
/// Tracks the confidence, the duty-cycle window it is corroborated over
/// (T054 §3.1), and the cooldown status that decide when a cycling trip should
/// automatically start. The window's per-interval history lives in the
/// detector; this state carries what it adds up to.
@freezed
sealed class TripStartState with _$TripStartState {
  const TripStartState._();

  const factory TripStartState({
    /// Current confidence score (0.0-1.0) that cycling is occurring
    required double confidence,

    /// Evaluation intervals inside the start window that scored above the
    /// threshold.
    required int windowDetections,

    /// Evaluation intervals the start window holds, positive or not.
    required int windowIntervals,

    /// When the current stretch of continuous evaluation began — the window is
    /// full, and may decide, once it is `tripStartDutyWindow` old. Null after a
    /// reset, before the first interval.
    required DateTime? coverageStart,

    /// When the last evaluation interval was counted.
    required DateTime? lastEvaluationTime,

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
      windowDetections: 0,
      windowIntervals: 0,
      coverageStart: null,
      lastEvaluationTime: null,
      cooldownActive: false,
      cooldownStartTime: null,
      cooldownDuration: null,
    );
  }
}

/// Extension methods for TripStartState
extension TripStartStateExtensions on TripStartState {
  /// Whether the start window has covered a full [window] of continuous
  /// evaluation, from [coverageStart] to the last interval counted, and may
  /// therefore decide.
  ///
  /// The interval that opened the coverage is itself one interval long, hence
  /// the [interval] subtracted: 120 intervals one second apart span 119 s.
  bool isWindowFull(Duration window, Duration interval) {
    final start = coverageStart;
    final last = lastEvaluationTime;
    if (start == null || last == null) return false;
    return last.difference(start) >= window - interval;
  }

  /// Share of the window's intervals that scored above the threshold.
  double get windowShare =>
      windowIntervals == 0 ? 0.0 : windowDetections / windowIntervals;

  /// Check if cooldown period has expired
  ///
  /// [defaultDuration] applies unless this cooldown was armed with one of its
  /// own — see the field.
  bool isCooldownExpired(DateTime now, Duration defaultDuration) {
    if (!cooldownActive || cooldownStartTime == null) return true;
    final period = cooldownDuration ?? defaultDuration;
    return now.difference(cooldownStartTime!).inSeconds >= period.inSeconds;
  }

  /// Reset detection state (empties the window and clears the confidence)
  TripStartState reset() {
    return copyWith(
      confidence: 0.0,
      windowDetections: 0,
      windowIntervals: 0,
      coverageStart: null,
      lastEvaluationTime: null,
    );
  }

  /// Activate cooldown, optionally for a [period] other than the default.
  TripStartState activateCooldown(DateTime now, {Duration? period}) {
    return copyWith(
      cooldownActive: true,
      cooldownStartTime: now,
      cooldownDuration: period,
      confidence: 0.0,
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
