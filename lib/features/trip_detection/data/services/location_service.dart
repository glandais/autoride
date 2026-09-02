import 'package:geolocator/geolocator.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../domain/models/location_data.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/audit/audit_event.dart';
import '../../../../core/audit/audit_log.dart';
import '../../../../core/utils/logger.dart';
import 'adaptive_location_settings.dart';
import 'location_permission_service.dart';

part 'location_service.g.dart';

const _logger = Logger('LocationService');

/// Settings for a single on-demand position fix (bounded by a timeout).
///
/// The CONTINUOUS stream deliberately carries no `timeLimit` and is configured
/// per power mode instead — see `locationSettingsForPowerMode`.
const LocationSettings kSingleFixLocationSettings = LocationSettings(
  accuracy: LocationAccuracy.high,
  distanceFilter: 10,
  timeLimit: Duration(seconds: AppConstants.locationTimeLimit),
);

@riverpod
class LocationService extends _$LocationService {
  @override
  Future<LocationData?> build() async {
    // Deliberately does NOT subscribe to `locationStreamProvider`: doing so
    // (L-025's first fix) kept the GPS receiver on for as long as the tracking
    // screen was mounted, defeating the motion gate this provider is supposed
    // to live behind (audit #3). The marker is fed from the stream that the
    // recorder already holds during a trip; this state only carries on-demand
    // fixes (the re-center button, `getLastKnownLocation`).
    return null;
  }

  /// Get current location (one-time)
  Future<LocationData?> getCurrentLocation({LocationSettings? settings}) async {
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

/// Stream provider for continuous location updates.
///
/// When no explicit [settings] are passed the stream is configured from the
/// current power mode through `adaptiveLocationSettingsProvider` (audit #4).
/// Watching it here means a power-mode change rebuilds this provider — and with
/// it the underlying `Geolocator.getPositionStream` — while consumers that
/// listen through `locationStreamProvider` keep their subscription, so neither
/// an active trip nor a detection session is dropped.
@riverpod
Stream<LocationData> locationStream(
  Ref ref, {
  LocationSettings? settings,
}) async* {
  // Resolved before the first await so the dependency is registered eagerly.
  final effectiveSettings =
      settings ?? ref.watch(adaptiveLocationSettingsProvider);

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
  var consecutiveFailures = 0;

  while (true) {
    try {
      yield* Geolocator.getPositionStream(locationSettings: effectiveSettings)
          .map((position) => LocationData.fromPosition(position));

      // Completed without error: still an interruption of a stream that is
      // supposed to run for the whole trip, so resubscribe.
      _logger.warning('Position stream completed; resubscribing');
    } catch (e, stackTrace) {
      _logger.error('Position stream error; resubscribing', e, stackTrace);
    }

    consecutiveFailures++;
    final delay = _retryDelay(consecutiveFailures);

    // A backoff that has grown to tens of seconds is the difference between
    // "the OS stopped delivering" and "the app stopped asking" — the exact
    // question item 1 of the device checklist puts.
    AuditLog.emit(
      AuditEvent.gpsResubscribe,
      () => <String, Object?>{
        'a': 'resub',
        'n': consecutiveFailures,
        'in': delay.inMilliseconds,
      },
      critical: true,
    );

    await Future<void>.delayed(delay);
  }
}

/// Exponential backoff for stream resubscription, capped.
Duration _retryDelay(int failureCount) {
  final millis =
      AppConstants.locationStreamRetryDelay.inMilliseconds *
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
