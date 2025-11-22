import 'package:geolocator/geolocator.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'location_permission_service.g.dart';

/// Location permission status
enum LocationPermissionStatus {
  granted,
  denied,
  deniedForever,
  notDetermined,
  serviceDisabled,
}

@riverpod
class LocationPermissionService extends _$LocationPermissionService {
  @override
  Future<LocationPermissionStatus> build() async {
    return await checkPermission();
  }

  /// Check current permission status
  Future<LocationPermissionStatus> checkPermission() async {
    // Check if location services are enabled
    final bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return LocationPermissionStatus.serviceDisabled;
    }

    // Check permission
    final LocationPermission permission = await Geolocator.checkPermission();

    return switch (permission) {
      LocationPermission.denied => LocationPermissionStatus.denied,
      LocationPermission.deniedForever => LocationPermissionStatus.deniedForever,
      LocationPermission.whileInUse || LocationPermission.always =>
        LocationPermissionStatus.granted,
      _ => LocationPermissionStatus.notDetermined,
    };
  }

  /// Request location permission
  Future<LocationPermissionStatus> requestPermission() async {
    // First check if service is enabled
    final bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      // Request user to enable location service
      // Note: Can't programmatically enable, user must do it manually
      return LocationPermissionStatus.serviceDisabled;
    }

    // Request permission
    final LocationPermission permission = await Geolocator.requestPermission();

    final status = switch (permission) {
      LocationPermission.denied => LocationPermissionStatus.denied,
      LocationPermission.deniedForever => LocationPermissionStatus.deniedForever,
      LocationPermission.whileInUse || LocationPermission.always =>
        LocationPermissionStatus.granted,
      _ => LocationPermissionStatus.notDetermined,
    };

    // Update state
    state = AsyncValue.data(status);
    return status;
  }

  /// Open app settings (for when permission is denied forever)
  Future<bool> openLocationSettings() async {
    return await Geolocator.openLocationSettings();
  }

  /// Open app settings (for permission management)
  Future<bool> openAppSettings() async {
    return await Geolocator.openAppSettings();
  }
}
