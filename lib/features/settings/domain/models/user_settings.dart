import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:geolocator/geolocator.dart';

import 'package:autoride/core/audit/audit_level.dart';

import 'detection_settings.dart';

part 'user_settings.freezed.dart';
part 'user_settings.g.dart';

/// Battery optimization modes
enum BatteryOptimizationMode {
  aggressive, // Maximum battery saving
  balanced, // Balance between performance and battery
  performance, // Maximum performance, minimal battery optimization
}

/// Location accuracy preference levels
enum LocationAccuracyPreference { low, medium, high }

/// Distance units for display
enum DistanceUnit {
  metric, // Kilometers
  imperial, // Miles
}

/// Speed units for display
enum SpeedUnit {
  kmh, // Kilometers per hour
  mph, // Miles per hour
  ms, // Meters per second
}

/// Theme modes
enum ThemeMode { light, dark, system }

/// Complete user settings model
@freezed
sealed class UserSettings with _$UserSettings {
  const UserSettings._();

  const factory UserSettings({
    // Detection Settings
    @Default(DetectionSettings()) DetectionSettings detection,

    // Battery Optimization
    @Default(BatteryOptimizationMode.balanced)
    BatteryOptimizationMode batteryMode,

    // Location Settings
    @Default(LocationAccuracyPreference.medium)
    LocationAccuracyPreference locationAccuracy,
    @Default(15) int distanceFilterMeters,
    @Default(true) bool backgroundLocationEnabled,

    // Notification Settings
    @Default(true) bool tripNotificationsEnabled,
    @Default(true) bool showOngoingNotification,
    @Default(false) bool soundOnTripStartStop,

    // Data & Privacy
    @Default(false) bool dataCollectionConsent,
    @Default(false) bool anonymousUsageStats,

    // Display Settings
    @Default(DistanceUnit.metric) DistanceUnit distanceUnit,
    @Default(SpeedUnit.kmh) SpeedUnit speedUnit,
    @Default(ThemeMode.system) ThemeMode themeMode,

    // Diagnostics (T043) — the opt-in audit log
    //
    // Replaces the former `debugLoggingEnabled`, which nothing ever read. Not
    // gated on `kDebugMode`: the whole point is that a tester running a release
    // build can turn it on, ride, and export what the pipeline actually did.
    @Default(false) bool auditLogEnabled,
    @Default(AuditLogLevel.normal) AuditLogLevel auditLogLevel,

    // Developer Settings (debug mode only)
    @Default(false) bool showSensorOverlay,

    // Metadata
    @Default(1) int version,
    DateTime? lastModified,
  }) = _UserSettings;

  factory UserSettings.fromJson(Map<String, dynamic> json) =>
      _$UserSettingsFromJson(json);
}

/// Extensions for UserSettings
extension UserSettingsExtensions on UserSettings {
  /// Convert distance from meters to user's preferred unit
  /// Returns kilometers for metric, miles for imperial
  double convertDistance(double meters) {
    switch (distanceUnit) {
      case DistanceUnit.metric:
        return meters / 1000; // Convert to kilometers
      case DistanceUnit.imperial:
        return meters * 0.000621371; // Convert to miles
    }
  }

  /// Convert speed from m/s to user's preferred unit
  double convertSpeed(double metersPerSecond) {
    switch (speedUnit) {
      case SpeedUnit.kmh:
        return metersPerSecond * 3.6;
      case SpeedUnit.mph:
        return metersPerSecond * 2.23694;
      case SpeedUnit.ms:
        return metersPerSecond;
    }
  }

  /// Get distance unit label
  String get distanceUnitLabel {
    switch (distanceUnit) {
      case DistanceUnit.metric:
        return 'km';
      case DistanceUnit.imperial:
        return 'mi';
    }
  }

  /// Get speed unit label
  String get speedUnitLabel {
    switch (speedUnit) {
      case SpeedUnit.kmh:
        return 'km/h';
      case SpeedUnit.mph:
        return 'mph';
      case SpeedUnit.ms:
        return 'm/s';
    }
  }

  /// Map user's location accuracy preference to geolocator's LocationAccuracy
  LocationAccuracy get geolocatorAccuracy {
    switch (locationAccuracy) {
      case LocationAccuracyPreference.low:
        return LocationAccuracy.low;
      case LocationAccuracyPreference.medium:
        return LocationAccuracy.medium;
      case LocationAccuracyPreference.high:
        return LocationAccuracy.high;
    }
  }
}
