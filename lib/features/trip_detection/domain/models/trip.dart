import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:autoride/features/trip_detection/domain/models/activity_confidence.dart';
import 'package:autoride/features/trip_detection/domain/models/location_data.dart';
import 'package:autoride/core/constants/app_constants.dart';

part 'trip.freezed.dart';

/// Lifecycle status of a persisted trip.
///
/// A trip row is written as soon as recording starts (that is what gives the
/// route points a foreign key to point at), so an unfinished row is normal
/// while a ride is in progress and *stale* once the process dies. The status
/// column is what tells those two apart at the next launch.
enum TripStatus {
  /// Recording right now, or interrupted by an app kill before it could be
  /// finalized. Never shown in history; recovered at startup.
  active,

  /// Finalized with real metrics. The only status history and stats display.
  completed,

  /// Finalized but rejected (too short to be a real ride).
  ///
  /// The recorder and the startup recovery *delete* such trips rather than
  /// keeping them (route points cascade), so no database row ever carries this
  /// value today. It is kept in the schema so a row that ever did would stay
  /// out of history instead of silently reappearing there — and the finalized
  /// `Trip` the recorder returns in memory does carry it, which is how
  /// `TripDetectionCoordinator` tells a false start from a real ride and arms
  /// the start-detection cooldown (L-075).
  discarded;

  /// Parse a persisted value, falling back to [TripStatus.completed].
  ///
  /// The fallback matches the migration default: rows written before the
  /// status column existed are finished trips.
  static TripStatus fromName(Object? value) {
    return TripStatus.values.firstWhere(
      (status) => status.name == value,
      orElse: () => TripStatus.completed,
    );
  }
}

/// Trip model representing a recorded bike trip
@freezed
sealed class Trip with _$Trip {
  const Trip._();

  /// A recorded ride.
  ///
  /// Two duration fields, and they mean different things:
  ///
  /// * [duration] is the **moving time** in seconds — the wall clock between
  ///   [startTime] and [endTime] *minus* every pause. It is what the recorder
  ///   writes, what `avgSpeed` is computed against and what history shows as
  ///   "Duration".
  /// * [pauseDuration] is the **time spent stopped** in seconds, the amount
  ///   that was subtracted. 0 means "no stops recorded", which is also what
  ///   rows written before schema v3 (L-073) carry.
  ///
  /// `duration + pauseDuration` is the elapsed time, give or take the
  /// sub-second rounding of the final write; [tripDuration] measures the same
  /// span straight off the timestamps. See [TripExtensions.movingDuration] and
  /// [TripExtensions.totalDuration] for the typed accessors.
  const factory Trip({
    required DateTime startTime,
    required DateTime endTime,
    required double distance, // meters
    required int duration, // seconds MOVING (pauses already subtracted)
    required ActivityType detectedActivity,
    required double confidenceScore, // 0.0-1.0
    int? id, // Nullable for new trips not yet saved
    double? avgSpeed, // km/h
    double? maxSpeed, // km/h
    @Default(false) bool userConfirmed,
    @Default(TripStatus.completed) TripStatus status,
    @Default(0) int pauseDuration, // seconds STOPPED
    @Default([]) List<RoutePoint> routePoints,
  }) = _Trip;

  /// Create from database map
  factory Trip.fromMap(Map<String, dynamic> map, List<RoutePoint> points) {
    return Trip(
      startTime: DateTime.fromMillisecondsSinceEpoch(map['start_time'] as int),
      endTime: DateTime.fromMillisecondsSinceEpoch(map['end_time'] as int),
      distance: map['distance'] as double,
      duration: map['duration'] as int,
      detectedActivity: ActivityType.values.firstWhere(
        (e) => e.name == map['detected_activity'],
        orElse: () => ActivityType.unknown,
      ),
      confidenceScore: map['confidence_score'] as double,
      id: map['id'] as int?,
      avgSpeed: map['avg_speed'] as double?,
      maxSpeed: map['max_speed'] as double?,
      userConfirmed: (map['user_confirmed'] as int) == 1,
      status: TripStatus.fromName(map['status']),
      // Absent on a database that predates schema v3; NOT NULL DEFAULT 0
      // afterwards. `as int?` covers both without a separate code path.
      pauseDuration: (map['pause_duration'] as int?) ?? 0,
      routePoints: points,
    );
  }
}

/// Extension for Trip database operations
extension TripExtensions on Trip {
  /// Convert to database map (without route points)
  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'start_time': startTime.millisecondsSinceEpoch,
      'end_time': endTime.millisecondsSinceEpoch,
      'distance': distance,
      'duration': duration,
      'avg_speed': avgSpeed,
      'max_speed': maxSpeed,
      'detected_activity': detectedActivity.name,
      'confidence_score': confidenceScore,
      'user_confirmed': userConfirmed ? 1 : 0,
      'status': status.name,
      'pause_duration': pauseDuration,
    };
  }

  /// Elapsed wall-clock time, measured off the timestamps.
  ///
  /// Includes the pauses — this is *not* [movingDuration]. It is the
  /// timestamps' own view of [totalDuration] and can differ from it by the
  /// sub-second rounding of the persisted second counts.
  Duration get tripDuration => endTime.difference(startTime);

  /// Time actually spent moving: [duration], typed.
  ///
  /// This is the headline "Duration" in history, and the denominator of
  /// [Trip.avgSpeed].
  Duration get movingDuration => Duration(seconds: duration);

  /// Time spent stopped during the ride: [pauseDuration], typed.
  ///
  /// Zero for rides recorded before schema v3 (L-073) — "not recorded" and
  /// "no stops" are deliberately not distinguished, since neither is worth
  /// showing.
  Duration get pausedDuration => Duration(seconds: pauseDuration);

  /// Moving time plus stopped time — start to finish, from the persisted
  /// counters rather than the timestamps.
  Duration get totalDuration => movingDuration + pausedDuration;

  /// Check if the trip is long enough to be kept.
  ///
  /// Applied by the recorder when a recording stops and by the startup
  /// recovery of interrupted trips: anything shorter is a false start and is
  /// deleted rather than persisted. There is no minimum-distance rule — a slow
  /// or short ride is still a ride.
  bool get isValidTrip => duration >= AppConstants.minTripDurationSeconds;

  /// Format duration as HH:MM:SS
  String get formattedDuration {
    final hours = duration ~/ 3600;
    final minutes = (duration % 3600) ~/ 60;
    final seconds = duration % 60;
    return '${hours.toString().padLeft(2, '0')}:'
        '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }

  /// Format distance as km with 2 decimal places
  String get formattedDistance => '${(distance / 1000).toStringAsFixed(2)} km';
}

/// Route point model (GPS coordinate with metadata)
@freezed
sealed class RoutePoint with _$RoutePoint {
  const RoutePoint._();

  const factory RoutePoint({
    required int tripId,
    required double latitude,
    required double longitude,
    required DateTime timestamp,
    int? id,
    double? altitude,
    double? accuracy,
    double? speed, // m/s
  }) = _RoutePoint;

  /// Create from LocationData
  factory RoutePoint.fromLocationData(LocationData location, int tripId) {
    return RoutePoint(
      tripId: tripId,
      latitude: location.latitude,
      longitude: location.longitude,
      timestamp: location.timestamp,
      altitude: location.altitude,
      accuracy: location.accuracy,
      speed: location.speed,
    );
  }

  /// Create from database map
  factory RoutePoint.fromMap(Map<String, dynamic> map) {
    return RoutePoint(
      tripId: map['trip_id'] as int,
      latitude: map['latitude'] as double,
      longitude: map['longitude'] as double,
      timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestamp'] as int),
      id: map['id'] as int?,
      altitude: map['altitude'] as double?,
      accuracy: map['accuracy'] as double?,
      speed: map['speed'] as double?,
    );
  }
}

/// Extension for RoutePoint database operations
extension RoutePointExtensions on RoutePoint {
  /// Convert to database map
  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'trip_id': tripId,
      'latitude': latitude,
      'longitude': longitude,
      'altitude': altitude,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'accuracy': accuracy,
      'speed': speed,
    };
  }

  /// Convert to LocationData
  LocationData toLocationData() {
    return LocationData(
      latitude: latitude,
      longitude: longitude,
      accuracy: accuracy ?? 0.0,
      altitude: altitude ?? 0.0,
      speed: speed ?? 0.0,
      heading: 0.0, // Not stored in database
      timestamp: timestamp,
    );
  }

  /// Speed in km/h
  double get speedKmh => (speed ?? 0.0) * 3.6;
}
