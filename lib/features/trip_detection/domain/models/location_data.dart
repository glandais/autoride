import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:geolocator/geolocator.dart';

import '../../../../core/constants/app_constants.dart';

part 'location_data.freezed.dart';

@freezed
sealed class LocationData with _$LocationData {
  const LocationData._(); // Private constructor for custom methods

  const factory LocationData({
    required double latitude,
    required double longitude,
    required double accuracy,
    required double altitude,
    required double speed, // m/s
    required double heading,
    required DateTime timestamp,
  }) = _LocationData;

  factory LocationData.fromPosition(Position position) {
    return LocationData(
      latitude: position.latitude,
      longitude: position.longitude,
      accuracy: position.accuracy,
      altitude: position.altitude,
      speed: position.speed,
      heading: position.heading,
      timestamp: position.timestamp,
    );
  }
}

// Extension for convenience
extension LocationDataExtensions on LocationData {
  /// Speed in km/h
  double get speedKmh => speed * 3.6;

  /// Whether the provider actually reported a speed with this fix.
  ///
  /// iOS routinely delivers exactly 0 on a fix taken at 19 km/h — 88 % of the
  /// fixes of the 2026-09-03 ride — and a plugin can hand back a negative
  /// sentinel or a NaN. None of those are a measurement of standing still;
  /// they are the absence of a measurement, and [GpsSpeedEstimator] replaces
  /// them with the speed the positions themselves imply (T048, L-087).
  bool get hasReportedSpeed => speed.isFinite && speed > 0;

  /// Whether this fix's speed may be believed at [now], and so is entitled to
  /// vote on trip start.
  ///
  /// One predicate for the two arms of the same question (T048, L-088 and
  /// L-089), because a caller that checks only one of them is checking half a
  /// fix:
  ///
  /// * **accuracy** — a 300 m network fix from Android's cell/wifi ladder
  ///   carries no speed information, whatever number rides along with it;
  /// * **age** — a fix from 34 seconds ago describes where the rider *was*.
  ///
  /// A fix failing either arm must be treated as *no fix at all* rather than as
  /// a fix reporting zero, which is the whole of L-087: the motion-only path
  /// scores up to 1.0, while `speedScore` 0 caps the confidence at 0.60 and
  /// vetoes a real departure.
  bool speedIsTrustworthyAt(DateTime now) {
    if (!accuracy.isFinite ||
        accuracy > AppConstants.speedTrustMaxAccuracyMeters) {
      return false;
    }
    return now.difference(timestamp).abs() <= AppConstants.speedTrustMaxAge;
  }

  /// Calculate distance to another location in meters
  double distanceTo(LocationData other) {
    return Geolocator.distanceBetween(
      latitude,
      longitude,
      other.latitude,
      other.longitude,
    );
  }
}
