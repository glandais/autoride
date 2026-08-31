import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:autoride/features/trip_detection/domain/models/location_data.dart';
import 'package:autoride/features/trip_detection/data/services/location_service.dart';
import 'package:autoride/features/trip_detection/data/services/location_permission_service.dart';

/// Test double for [LocationPermissionService] that returns a fixed status
/// without touching the geolocator platform channels.
class _FakeLocationPermissionService extends LocationPermissionService {
  _FakeLocationPermissionService(this._status);

  final LocationPermissionStatus _status;

  @override
  Future<LocationPermissionStatus> build() async => _status;
}

void main() {
  // LocationService.build() now subscribes to the position stream so the
  // exposed "current location" stays fresh for the tracking screen's map
  // marker and re-center button. That touches a platform event channel, which
  // needs the test binding even though no data ever arrives here.
  TestWidgetsFlutterBinding.ensureInitialized();

  // ---------------------------------------------------------------------------
  // LocationData model (this file was previously mislabeled as a
  // "LocationService" test, but it only ever exercised the LocationData model).
  // These assert the freezed model conversions and extension methods.
  // ---------------------------------------------------------------------------
  group('LocationData model', () {
    test('fromPosition maps all fields correctly', () {
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

      final locationData = LocationData.fromPosition(position);

      expect(locationData.latitude, equals(48.8566));
      expect(locationData.longitude, equals(2.3522));
      expect(locationData.accuracy, equals(10.0));
      expect(locationData.altitude, equals(35.0));
      expect(locationData.heading, equals(90.0));
      expect(locationData.speed, equals(5.0));
      expect(locationData.speedKmh, equals(18.0)); // 5 m/s = 18 km/h
    });

    test('distanceTo returns great-circle distance between two locations', () {
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

      final distance = paris.distanceTo(london);

      // Paris to London is approximately 344 km.
      expect(distance, greaterThan(340000));
      expect(distance, lessThan(350000));
    });

    test('speedKmh converts m/s to km/h', () {
      final locationData = LocationData(
        latitude: 48.8566,
        longitude: 2.3522,
        accuracy: 10.0,
        altitude: 35.0,
        speed: 10.0, // 10 m/s
        heading: 0.0,
        timestamp: DateTime.now(),
      );

      expect(locationData.speedKmh, equals(36.0)); // 10 m/s = 36 km/h
    });
  });

  // ---------------------------------------------------------------------------
  // LocationService permission gating.
  //
  // getCurrentLocation() throws LocationServiceException *before* ever calling
  // the geolocator platform when permission is not granted, so this path is
  // fully unit-testable by overriding locationPermissionServiceProvider.
  // (The happy path requires a geolocator platform mock and is covered by
  // device/integration testing.)
  // ---------------------------------------------------------------------------
  group('LocationService permission gating', () {
    ProviderContainer containerFor(LocationPermissionStatus status) {
      return ProviderContainer(
        overrides: [
          locationPermissionServiceProvider.overrideWith(
            () => _FakeLocationPermissionService(status),
          ),
        ],
      );
    }

    for (final status in [
      LocationPermissionStatus.denied,
      LocationPermissionStatus.deniedForever,
      LocationPermissionStatus.notDetermined,
      LocationPermissionStatus.serviceDisabled,
    ]) {
      test('getCurrentLocation throws when permission is $status', () async {
        final container = containerFor(status);
        addTearDown(container.dispose);

        final service = container.read(locationServiceProvider.notifier);

        await expectLater(
          service.getCurrentLocation(),
          throwsA(
            isA<LocationServiceException>().having(
              (e) => e.permissionStatus,
              'permissionStatus',
              status,
            ),
          ),
        );
      });
    }

    test('LocationServiceException toString includes the message', () {
      final exception = LocationServiceException(
        'Location permission not granted',
        LocationPermissionStatus.denied,
      );

      expect(
        exception.toString(),
        contains('Location permission not granted'),
      );
    });

    test('initial build state is null', () async {
      final container = containerFor(LocationPermissionStatus.granted);
      addTearDown(container.dispose);

      final value = await container.read(locationServiceProvider.future);
      expect(value, isNull);
    });
  });
}
