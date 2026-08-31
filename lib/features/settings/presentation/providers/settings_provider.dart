import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../domain/models/detection_settings.dart';
import '../../domain/models/user_settings.dart';
import '../../data/services/settings_service.dart';

part 'settings_provider.g.dart';

/// Provider for detection settings updates
/// Provides convenient methods for updating detection-specific settings
@riverpod
class DetectionSettingsNotifier extends _$DetectionSettingsNotifier {
  @override
  DetectionSettings build() {
    return ref.watch(currentSettingsProvider).detection;
  }

  /// Enable or disable automatic detection.
  ///
  /// This is the setting the app root watches: turning it on starts the
  /// detection coordinator (permissions permitting), turning it off stops it.
  Future<void> updateAutomaticDetection(bool enabled) async {
    await ref.read(settingsServiceProvider.notifier).updatePartial(
          (settings) => settings.copyWith(
            detection: settings.detection.copyWith(
              automaticDetectionEnabled: enabled,
            ),
          ),
        );
  }

  /// Update auto-start detection enabled state
  Future<void> updateAutoStart(bool enabled) async {
    await ref.read(settingsServiceProvider.notifier).updatePartial(
          (settings) => settings.copyWith(
            detection: settings.detection.copyWith(autoStartEnabled: enabled),
          ),
        );
  }

  /// Update cycling detection sensitivity
  Future<void> updateSensitivity(CyclingSensitivity sensitivity) async {
    await ref.read(settingsServiceProvider.notifier).updatePartial(
          (settings) => settings.copyWith(
            detection: settings.detection.copyWith(sensitivity: sensitivity),
          ),
        );
  }

  /// Update minimum trip duration
  Future<void> updateMinimumDuration(int seconds) async {
    await ref.read(settingsServiceProvider.notifier).updatePartial(
          (settings) => settings.copyWith(
            detection: settings.detection.copyWith(
              minimumTripDurationSeconds: seconds,
            ),
          ),
        );
  }

  /// Update stationary timeout
  Future<void> updateStationaryTimeout(int seconds) async {
    await ref.read(settingsServiceProvider.notifier).updatePartial(
          (settings) => settings.copyWith(
            detection: settings.detection.copyWith(
              stationaryTimeoutSeconds: seconds,
            ),
          ),
        );
  }
}

/// Provider for display settings updates
/// Provides convenient methods for updating display-related settings
@riverpod
class DisplaySettingsNotifier extends _$DisplaySettingsNotifier {
  @override
  UserSettings build() {
    return ref.watch(currentSettingsProvider);
  }

  /// Update distance unit preference
  Future<void> updateDistanceUnit(DistanceUnit unit) async {
    await ref.read(settingsServiceProvider.notifier).updatePartial(
          (settings) => settings.copyWith(distanceUnit: unit),
        );
  }

  /// Update speed unit preference
  Future<void> updateSpeedUnit(SpeedUnit unit) async {
    await ref.read(settingsServiceProvider.notifier).updatePartial(
          (settings) => settings.copyWith(speedUnit: unit),
        );
  }

  /// Update theme mode
  Future<void> updateThemeMode(ThemeMode mode) async {
    await ref.read(settingsServiceProvider.notifier).updatePartial(
          (settings) => settings.copyWith(themeMode: mode),
        );
  }
}

/// Provider for battery settings updates
// TODO(T041): no consumer in lib/ - the settings widgets call
// `settingsServiceProvider` directly. Same for the location and
// notification notifiers below; keep them or fold the widgets onto them.
@riverpod
class BatterySettingsNotifier extends _$BatterySettingsNotifier {
  @override
  BatteryOptimizationMode build() {
    return ref.watch(currentSettingsProvider).batteryMode;
  }

  /// Update battery optimization mode
  Future<void> updateBatteryMode(BatteryOptimizationMode mode) async {
    await ref.read(settingsServiceProvider.notifier).updatePartial(
          (settings) => settings.copyWith(batteryMode: mode),
        );
  }
}

/// Provider for location settings updates
@riverpod
class LocationSettingsNotifier extends _$LocationSettingsNotifier {
  @override
  UserSettings build() {
    return ref.watch(currentSettingsProvider);
  }

  /// Update location accuracy preference
  Future<void> updateLocationAccuracy(LocationAccuracyPreference accuracy) async {
    await ref.read(settingsServiceProvider.notifier).updatePartial(
          (settings) => settings.copyWith(locationAccuracy: accuracy),
        );
  }

  /// Update distance filter
  Future<void> updateDistanceFilter(int meters) async {
    await ref.read(settingsServiceProvider.notifier).updatePartial(
          (settings) => settings.copyWith(distanceFilterMeters: meters),
        );
  }

  /// Update background location enabled
  Future<void> updateBackgroundLocation(bool enabled) async {
    await ref.read(settingsServiceProvider.notifier).updatePartial(
          (settings) => settings.copyWith(backgroundLocationEnabled: enabled),
        );
  }
}

/// Provider for notification settings updates
@riverpod
class NotificationSettingsNotifier extends _$NotificationSettingsNotifier {
  @override
  UserSettings build() {
    return ref.watch(currentSettingsProvider);
  }

  /// Update trip notifications enabled
  Future<void> updateTripNotifications(bool enabled) async {
    await ref.read(settingsServiceProvider.notifier).updatePartial(
          (settings) => settings.copyWith(tripNotificationsEnabled: enabled),
        );
  }

  /// Update ongoing notification display
  Future<void> updateOngoingNotification(bool show) async {
    await ref.read(settingsServiceProvider.notifier).updatePartial(
          (settings) => settings.copyWith(showOngoingNotification: show),
        );
  }

  /// Update sound on trip events
  Future<void> updateTripSounds(bool enabled) async {
    await ref.read(settingsServiceProvider.notifier).updatePartial(
          (settings) => settings.copyWith(soundOnTripStartStop: enabled),
        );
  }
}
