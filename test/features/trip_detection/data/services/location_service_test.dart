import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:autoride/features/trip_detection/domain/models/location_data.dart';

void main() {
  group('LocationData', () {
    test('should convert from Position correctly', () {
      // Arrange
      final position = Position(
        latitude: 48.8566,
        longitude: 2.3522,
        timestamp: DateTime.now(),
        accuracy: 10.0,
        altitude: 35.0,
        heading: 90.0,
        speed: 5.0,
        speedAccuracy: 1.0,
        altitudeAccuracy: 1.0,
        headingAccuracy: 1.0,
      );

      // Act
      final locationData = LocationData.fromPosition(position);

      // Assert
      expect(locationData.latitude, equals(48.8566));
      expect(locationData.longitude, equals(2.3522));
      expect(locationData.speed, equals(5.0));
      expect(locationData.speedKmh, equals(18.0)); // 5 m/s = 18 km/h
    });

    test('should calculate distance between two locations', () {
      // Arrange
      final paris = LocationData(
        latitude: 48.8566,
        longitude: 2.3522,
        accuracy: 10.0,
        altitude: 35.0,
        speed: 0.0,
        heading: 0.0,
        timestamp: DateTime.now(),
      );

      final london = LocationData(
        latitude: 51.5074,
        longitude: -0.1278,
        accuracy: 10.0,
        altitude: 11.0,
        speed: 0.0,
        heading: 0.0,
        timestamp: DateTime.now(),
      );

      // Act
      final distance = paris.distanceTo(london);

      // Assert
      // Paris to London is approximately 344 km
      expect(distance, greaterThan(340000));
      expect(distance, lessThan(350000));
    });

    test('should convert speed to km/h correctly', () {
      // Arrange
      final locationData = LocationData(
        latitude: 48.8566,
        longitude: 2.3522,
        accuracy: 10.0,
        altitude: 35.0,
        speed: 10.0, // 10 m/s
        heading: 0.0,
        timestamp: DateTime.now(),
      );

      // Act & Assert
      expect(locationData.speedKmh, equals(36.0)); // 10 m/s = 36 km/h
    });
  });
}
