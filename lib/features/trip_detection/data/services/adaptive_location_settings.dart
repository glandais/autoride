import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'battery_optimizer.dart';

part 'adaptive_location_settings.g.dart';

/// Location settings for the continuous position stream, derived from the
/// current power mode (audit #4).
///
/// This is the single place where a [PowerModeConfig] becomes actual GPS
/// configuration. `locationStream` watches this provider, so a power-mode
/// change rebuilds the position stream with the new accuracy, distance filter
/// and update interval; consumers listening through `locationStreamProvider`
/// keep their subscription across that rebuild and therefore never lose an
/// in-progress trip or detection session.
///
/// Motion is deliberately NOT an input here: whether GPS runs at all is decided
/// by the coordinator's motion gate (audit #3). This provider only decides how
/// expensive it is while it runs.
@riverpod
class AdaptiveLocationSettings extends _$AdaptiveLocationSettings {
  @override
  LocationSettings build() {
    return locationSettingsForPowerMode(ref.watch(currentPowerModeProvider));
  }
}

/// Build the platform-specific [LocationSettings] for [config].
///
/// The update interval is a platform-specific concept (`intervalDuration` on
/// Android; on Apple platforms the OS schedules updates itself and only the
/// accuracy/distance filter and activity type are tunable), so the settings are
/// built per platform rather than through the lowest common denominator.
///
/// Deliberately carries NO `timeLimit`: Geolocator terminates the stream with a
/// TimeoutException when no fix arrives inside the limit, which happens
/// routinely in a tunnel, an urban canyon or at a long red light. A terminated
/// stream used to leave a trip "recording" with a frozen distance for the rest
/// of the ride. Use `kSingleFixLocationSettings` for one-shot fixes, where a
/// timeout is the correct behaviour.
LocationSettings locationSettingsForPowerMode(PowerModeConfig config) {
  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
      return AndroidSettings(
        accuracy: config.locationAccuracy,
        distanceFilter: config.distanceFilter,
        intervalDuration: config.locationUpdateInterval,
      );

    case TargetPlatform.iOS:
    case TargetPlatform.macOS:
      return AppleSettings(
        accuracy: config.locationAccuracy,
        distanceFilter: config.distanceFilter,
        // Cycling profile; never let the OS auto-pause updates, that is the
        // motion gate's job and it must stay observable from Dart.
        activityType: ActivityType.fitness,
        pauseLocationUpdatesAutomatically: false,
      );

    case _:
      return LocationSettings(
        accuracy: config.locationAccuracy,
        distanceFilter: config.distanceFilter,
      );
  }
}
