import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../../../core/permissions/services/permission_handler_service.dart';
import '../../../../core/permissions/exceptions/permission_exceptions.dart';
import '../../../../core/utils/logger.dart';
import '../../services/background_location_service.dart';
import '../../domain/models/location_data.dart';

part 'location_tracking_provider.g.dart';

// TODO(T041): `locationTrackingProvider` has no consumer in lib/. It is the
// only subscriber to the background isolate's `update` events, so the isolate's
// output currently reaches no code at all. See BLOCKED-pipeline-refactor.md #7/#8.
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

  static const _log = Logger('LocationTracking');

  /// Start background location tracking
  /// Requests background permission if not granted
  Future<void> startBackgroundTracking() async {
    _log.info('Starting background tracking - checking permissions');
    final permissionHandler = ref.read(permissionHandlerServiceProvider.notifier);

    // First check if we have foreground permission
    final foregroundStatus = await permissionHandler.checkPermission(
      AppPermission.locationWhenInUse,
    );
    _log.debug('Foreground permission status: granted=${foregroundStatus.isGranted}');
    if (!foregroundStatus.isGranted) {
      _log.info('Requesting foreground location permission (locationWhenInUse)');
      final requested = await permissionHandler.requestPermission(
        AppPermission.locationWhenInUse,
      );
      _log.info('Foreground permission request result: granted=${requested.isGranted}');
      if (!requested.isGranted) {
        _log.warning('Foreground location permission denied');
        throw LocationTrackingException(
          'Foreground location permission required',
          LocationTrackingErrorType.permissionDenied,
        );
      }
    }

    // Now request background permission
    _log.info('Requesting background location permission (locationAlways)');
    final backgroundStatus = await permissionHandler.requestPermission(
      AppPermission.locationAlways,
    );
    _log.info('Background permission result: granted=${backgroundStatus.isGranted}');
    if (!backgroundStatus.isGranted) {
      _log.warning('Background location permission denied');
      throw LocationTrackingException(
        'Background location permission required for trip tracking',
        LocationTrackingErrorType.backgroundPermissionDenied,
      );
    }

    // Initialize and start background service
    _log.info('Permissions granted, initializing background service');
    final backgroundService = ref.read(backgroundLocationServiceProvider.notifier);
    await backgroundService.initialize();
    await backgroundService.startTracking();
    _log.info('Background tracking started successfully');
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
