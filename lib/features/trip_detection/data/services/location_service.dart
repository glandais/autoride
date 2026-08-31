import 'package:geolocator/geolocator.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../domain/models/location_data.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/utils/logger.dart';
import 'location_permission_service.dart';

part 'location_service.g.dart';

const _logger = Logger('LocationService');

/// Default location settings for the continuous position stream.
///
/// Deliberately carries NO `timeLimit`: Geolocator terminates the stream with a
/// TimeoutException when no fix arrives inside the limit, which happens
/// routinely in a tunnel, an urban canyon or at a long red light. A terminated
/// stream used to leave a trip "recording" with a frozen distance for the rest
/// of the ride. Use [kSingleFixLocationSettings] for one-shot fixes, where a
/// timeout is the correct behaviour.
const LocationSettings kDefaultLocationSettings = LocationSettings(
  accuracy: LocationAccuracy.high,
  distanceFilter: 10, // Update every 10 meters
);

/// Settings for a single on-demand position fix (bounded by a timeout).
const LocationSettings kSingleFixLocationSettings = LocationSettings(
  accuracy: LocationAccuracy.high,
  distanceFilter: 10,
  timeLimit: Duration(seconds: AppConstants.locationTimeLimit),
);

@riverpod
class LocationService extends _$LocationService {
  @override
  Future<LocationData?> build() async {
    // Keep the exposed "current location" fed by the live position stream so
    // consumers (the tracking screen's map marker and re-center button) have a
    // value without every caller having to poll `getCurrentLocation()`.
    ref.listen(locationStreamProvider(), (previous, next) {
      next.whenData((location) {
        state = AsyncValue.data(location);
      });
    });

    // Return null initially; the stream (or an explicit request) populates it.
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
        locationSettings: settings ?? kSingleFixLocationSettings,
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

  // Stream position updates, resubscribing if the platform stream errors or
  // completes. Losing the GPS fix must not silently end tracking for the rest
  // of a ride; the delay is capped so a persistent failure does not spin.
  final effectiveSettings = settings ?? kDefaultLocationSettings;
  var consecutiveFailures = 0;

  while (true) {
    try {
      yield* Geolocator.getPositionStream(
        locationSettings: effectiveSettings,
      ).map((position) => LocationData.fromPosition(position));

      // Completed without error: still an interruption of a stream that is
      // supposed to run for the whole trip, so resubscribe.
      _logger.warning('Position stream completed; resubscribing');
    } catch (e, stackTrace) {
      _logger.error('Position stream error; resubscribing', e, stackTrace);
    }

    consecutiveFailures++;
    await Future<void>.delayed(_retryDelay(consecutiveFailures));
  }
}

/// Exponential backoff for stream resubscription, capped.
Duration _retryDelay(int failureCount) {
  final millis = AppConstants.locationStreamRetryDelay.inMilliseconds *
      (1 << (failureCount - 1).clamp(0, 5));
  final capped = millis.clamp(
    AppConstants.locationStreamRetryDelay.inMilliseconds,
    AppConstants.locationStreamMaxRetryDelay.inMilliseconds,
  );
  return Duration(milliseconds: capped);
}

/// Custom exception for location service errors
class LocationServiceException implements Exception {
  LocationServiceException(this.message, this.permissionStatus);

  final String message;
  final LocationPermissionStatus permissionStatus;

  @override
  String toString() => 'LocationServiceException: $message';
}
