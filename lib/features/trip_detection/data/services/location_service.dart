import 'package:geolocator/geolocator.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../domain/models/location_data.dart';
import 'location_permission_service.dart';

part 'location_service.g.dart';

/// Default location settings for basic tracking
const LocationSettings kDefaultLocationSettings = LocationSettings(
  accuracy: LocationAccuracy.high,
  distanceFilter: 10, // Update every 10 meters
  timeLimit: Duration(seconds: 30),
);

@riverpod
class LocationService extends _$LocationService {
  @override
  Future<LocationData?> build() async {
    // Return null initially, will be populated when location is requested
    return null;
  }

  /// Get current location (one-time)
  Future<LocationData?> getCurrentLocation({
    LocationSettings? settings,
  }) async {
    try {
      // Check permission
      final permissionStatus = await ref.read(
        locationPermissionServiceProvider.future,
      );

      if (permissionStatus != LocationPermissionStatus.granted) {
        throw LocationServiceException(
          'Location permission not granted',
          permissionStatus,
        );
      }

      // Get position
      final position = await Geolocator.getCurrentPosition(
        locationSettings: settings ?? kDefaultLocationSettings,
      );

      final locationData = LocationData.fromPosition(position);

      // Update state
      state = AsyncValue.data(locationData);

      return locationData;
    } on LocationServiceDisabledException {
      throw LocationServiceException(
        'Location services are disabled',
        LocationPermissionStatus.serviceDisabled,
      );
    } on PermissionDeniedException {
      throw LocationServiceException(
        'Location permission denied',
        LocationPermissionStatus.denied,
      );
    } catch (e) {
      state = AsyncValue.error(e, StackTrace.current);
      rethrow;
    }
  }

  /// Get last known location (cached, fast)
  Future<LocationData?> getLastKnownLocation() async {
    try {
      final position = await Geolocator.getLastKnownPosition();
      if (position == null) return null;

      final locationData = LocationData.fromPosition(position);
      state = AsyncValue.data(locationData);
      return locationData;
    } catch (e) {
      // Silently fail for last known location
      return null;
    }
  }
}

/// Stream provider for continuous location updates
@riverpod
Stream<LocationData> locationStream(
  Ref ref, {
  LocationSettings? settings,
}) async* {
  // Check permission first
  final permissionStatus = await ref.watch(
    locationPermissionServiceProvider.future,
  );

  if (permissionStatus != LocationPermissionStatus.granted) {
    throw LocationServiceException(
      'Location permission not granted',
      permissionStatus,
    );
  }

  // Stream position updates
  yield* Geolocator.getPositionStream(
    locationSettings: settings ?? kDefaultLocationSettings,
  ).map((position) => LocationData.fromPosition(position));
}

/// Custom exception for location service errors
class LocationServiceException implements Exception {
  LocationServiceException(this.message, this.permissionStatus);

  final String message;
  final LocationPermissionStatus permissionStatus;

  @override
  String toString() => 'LocationServiceException: $message';
}
