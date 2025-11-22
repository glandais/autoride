import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:geolocator/geolocator.dart';

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
