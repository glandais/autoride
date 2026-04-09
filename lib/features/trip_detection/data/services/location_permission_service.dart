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

    // Update state only if still mounted
    if (ref.mounted) {
      state = AsyncValue.data(status);
    }
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

  /// Request background location permission (Android 10+, iOS Always)
  /// Must be called AFTER foreground permission is granted
  Future<LocationPermissionStatus> requestBackgroundPermission() async {
    // First ensure foreground permission is granted
    final currentStatus = await checkPermission();
    if (currentStatus != LocationPermissionStatus.granted) {
      // Must have foreground permission first
      return currentStatus;
    }

    // Request always permission (includes background)
    final LocationPermission permission = await Geolocator.requestPermission();

    final status = switch (permission) {
      LocationPermission.always => LocationPermissionStatus.granted,
      LocationPermission.whileInUse => LocationPermissionStatus.denied, // Needs always for background
      LocationPermission.denied => LocationPermissionStatus.denied,
      LocationPermission.deniedForever => LocationPermissionStatus.deniedForever,
      _ => LocationPermissionStatus.notDetermined,
    };

    // Update state only if still mounted
    if (ref.mounted) {
      state = AsyncValue.data(status);
    }
    return status;
  }

  /// Check if background location permission is granted
  Future<bool> hasBackgroundPermission() async {
    final LocationPermission permission = await Geolocator.checkPermission();
    return permission == LocationPermission.always;
  }
}
