import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../data/services/location_permission_service.dart';
import '../../services/background_location_service.dart';
import '../../domain/models/location_data.dart';

part 'location_tracking_provider.g.dart';

@riverpod
class LocationTracking extends _$LocationTracking {
  @override
  Stream<LocationData?> build() async* {
    // Listen to background service updates
    final backgroundService = ref.watch(backgroundLocationServiceProvider.notifier);

    await for (final update in backgroundService.locationUpdates) {
      if (update != null) {
        yield LocationData(
          latitude: update['latitude'] as double,
          longitude: update['longitude'] as double,
          accuracy: update['accuracy'] as double,
          altitude: 0.0, // Not available in simplified update
          speed: update['speed'] as double,
          heading: 0.0, // Not available in simplified update
          timestamp: DateTime.fromMillisecondsSinceEpoch(
            update['timestamp'] as int,
          ),
        );
      }
    }
  }

  /// Start background location tracking
  /// Requests background permission if not granted
  Future<void> startBackgroundTracking() async {
    // Check and request background permission
    final permissionService = ref.read(locationPermissionServiceProvider.notifier);

    // First check if we have foreground permission
    final currentStatus = await permissionService.checkPermission();
    if (currentStatus != LocationPermissionStatus.granted) {
      // Request foreground permission first
      final foregroundStatus = await permissionService.requestPermission();
      if (foregroundStatus != LocationPermissionStatus.granted) {
        throw LocationTrackingException(
          'Foreground location permission required',
          LocationTrackingErrorType.permissionDenied,
        );
      }
    }

    // Now request background permission
    final backgroundStatus = await permissionService.requestBackgroundPermission();
    if (backgroundStatus != LocationPermissionStatus.granted) {
      throw LocationTrackingException(
        'Background location permission required for trip tracking',
        LocationTrackingErrorType.backgroundPermissionDenied,
      );
    }

    // Initialize and start background service
    final backgroundService = ref.read(backgroundLocationServiceProvider.notifier);
    await backgroundService.initialize();
    await backgroundService.startTracking();
  }

  /// Stop background location tracking
  Future<void> stopBackgroundTracking() async {
    final backgroundService = ref.read(backgroundLocationServiceProvider.notifier);
    await backgroundService.stopTracking();
  }

  /// Check if background tracking is currently active
  Future<bool> isTrackingActive() async {
    final backgroundService = ref.read(backgroundLocationServiceProvider);
    return backgroundService.value ?? false;
  }
}

/// Exception types for location tracking
enum LocationTrackingErrorType {
  permissionDenied,
  backgroundPermissionDenied,
  serviceNotAvailable,
  unknown,
}

/// Custom exception for location tracking errors
class LocationTrackingException implements Exception {
  LocationTrackingException(this.message, this.type);

  final String message;
  final LocationTrackingErrorType type;

  @override
  String toString() => 'LocationTrackingException: $message';
}
