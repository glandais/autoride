import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart' show AndroidSettings, AppleSettings;

import 'package:autoride/core/constants/app_constants.dart';
import 'package:autoride/features/trip_detection/data/services/adaptive_location_settings.dart';
import 'package:autoride/features/trip_detection/data/services/battery_optimizer.dart';

// ===========================================================================
// Audit #4 / L-006: PowerModeConfig must actually become GPS configuration.
// The end-to-end wiring (power mode -> settings -> live position stream, and
// re-subscription on a mode change) is covered in
// trip_detection_coordinator_test.dart; this file pins the mapping itself.
// ===========================================================================

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  group('locationSettingsForPowerMode - Android', () {
    setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.android);

    test('carries accuracy, distance filter and update interval per mode', () {
      const modes = [
        PowerModeConfig.normal,
        PowerModeConfig.medium,
        PowerModeConfig.low,
        PowerModeConfig.critical,
      ];

      for (final mode in modes) {
        final settings = locationSettingsForPowerMode(mode) as AndroidSettings;

        expect(settings.accuracy, mode.locationAccuracy);
        expect(settings.distanceFilter, mode.distanceFilter);
        expect(settings.intervalDuration, mode.locationUpdateInterval);
        // A timeLimit would terminate the stream in a tunnel or at a red
        // light and freeze a trip's distance for the rest of the ride (L-009).
        expect(settings.timeLimit, isNull);
      }
    });

    test('the documented per-mode distance filters are the ones applied', () {
      expect(
        PowerModeConfig.normal.distanceFilter,
        AppConstants.distanceFilterCycling,
      ); // 15 m
      expect(
        PowerModeConfig.medium.distanceFilter,
        AppConstants.distanceFilterMoving,
      ); // 20 m
      expect(
        PowerModeConfig.low.distanceFilter,
        AppConstants.distanceFilterLowPower,
      ); // 30 m
      expect(
        PowerModeConfig.critical.distanceFilter,
        AppConstants.distanceFilterCriticalPower,
      ); // 50 m
    });

    test('lower power modes are never more expensive than higher ones', () {
      expect(
        PowerModeConfig.critical.distanceFilter,
        greaterThan(PowerModeConfig.normal.distanceFilter),
      );
      expect(
        PowerModeConfig.critical.locationUpdateInterval,
        greaterThan(PowerModeConfig.normal.locationUpdateInterval),
      );
      expect(
        PowerModeConfig.critical.sensorSamplingRate,
        lessThan(PowerModeConfig.normal.sensorSamplingRate),
      );
    });
  });

  group('locationSettingsForPowerMode - Apple', () {
    setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.iOS);

    test('uses the cycling activity profile and never auto-pauses', () {
      final settings =
          locationSettingsForPowerMode(PowerModeConfig.low) as AppleSettings;

      expect(settings.accuracy, PowerModeConfig.low.locationAccuracy);
      expect(settings.distanceFilter, PowerModeConfig.low.distanceFilter);
      expect(settings.pauseLocationUpdatesAutomatically, isFalse);
      expect(settings.timeLimit, isNull);
    });
  });
}
