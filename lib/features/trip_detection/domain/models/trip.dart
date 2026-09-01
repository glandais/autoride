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
  /// keeping them (route points cascade), so nothing writes this value today.
  /// It is kept in the schema so a row that ever carries it stays out of
  /// history instead of silently reappearing there.
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

  const factory Trip({
    required DateTime startTime,
    required DateTime endTime,
    required double distance, // meters
    required int duration, // seconds
    required ActivityType detectedActivity,
    required double confidenceScore, // 0.0-1.0
    int? id, // Nullable for new trips not yet saved
    double? avgSpeed, // km/h
    double? maxSpeed, // km/h
    @Default(false) bool userConfirmed,
    @Default(TripStatus.completed) TripStatus status,
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
    };
  }

  /// Calculate duration from start/end times
  Duration get tripDuration => endTime.difference(startTime);

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
