import 'package:freezed_annotation/freezed_annotation.dart';

part 'trip_state.freezed.dart';

/// Represents the current state of trip detection
@freezed
sealed class TripState with _$TripState {
  const TripState._();

  /// No activity detected, system is idle
  const factory TripState.idle() = _Idle;

  /// Motion detected, analyzing if it's cycling
  /// [detectionStartTime] when detection phase started
  const factory TripState.detecting({
    required DateTime detectionStartTime,
  }) = _Detecting;

  /// Active trip in progress
  /// [tripId] database ID of the trip
  /// [startTime] when trip started
  const factory TripState.active({
    required int tripId,
    required DateTime startTime,
  }) = _Active;

  /// Trip paused (stationary during active trip)
  /// [tripId] database ID of the trip
  /// [startTime] original trip start time
  /// [pauseStartTime] when pause began
  const factory TripState.paused({
    required int tripId,
    required DateTime startTime,
    required DateTime pauseStartTime,
  }) = _Paused;
}

/// Extensions for state queries
extension TripStateExtensions on TripState {
  /// Whether a trip is currently active (Active or Paused)
  bool get hasActiveTrip => map(
        idle: (_) => false,
        detecting: (_) => false,
        active: (_) => true,
        paused: (_) => true,
      );

  /// Whether system is currently recording location data
  bool get isRecording => map(
        idle: (_) => false,
        detecting: (_) => false,
        active: (_) => true,
        paused: (_) => false,
      );

  /// Get current trip ID if available
  int? get currentTripId => map(
        idle: (_) => null,
        detecting: (_) => null,
        active: (state) => state.tripId,
        paused: (state) => state.tripId,
      );
}
