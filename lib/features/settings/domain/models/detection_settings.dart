import 'package:freezed_annotation/freezed_annotation.dart';

part 'detection_settings.freezed.dart';
part 'detection_settings.g.dart';

/// Cycling detection sensitivity levels
enum CyclingSensitivity {
  low,
  medium,
  high,
}

/// Detection-specific settings for trip tracking
@freezed
sealed class DetectionSettings with _$DetectionSettings {
  const DetectionSettings._();

  const factory DetectionSettings({
    /// Enable automatic trip start detection
    @Default(true) bool autoStartEnabled,

    /// Cycling detection sensitivity level
    @Default(CyclingSensitivity.medium) CyclingSensitivity sensitivity,

    /// Minimum trip duration in seconds to be recorded
    @Default(120) int minimumTripDurationSeconds,

    /// Stationary timeout in seconds before trip ends
    @Default(300) int stationaryTimeoutSeconds,
  }) = _DetectionSettings;

  factory DetectionSettings.fromJson(Map<String, dynamic> json) =>
      _$DetectionSettingsFromJson(json);
}

/// Extensions for DetectionSettings
extension DetectionSettingsExtensions on DetectionSettings {
  /// Convert sensitivity to threshold multiplier
  /// Low: 0.8 (more lenient, easier to trigger)
  /// Medium: 1.0 (standard)
  /// High: 1.2 (stricter, harder to trigger)
  double get sensitivityMultiplier {
    switch (sensitivity) {
      case CyclingSensitivity.low:
        return 0.8;
      case CyclingSensitivity.medium:
        return 1.0;
      case CyclingSensitivity.high:
        return 1.2;
    }
  }

  /// Get minimum trip duration as Duration object
  Duration get minimumTripDuration =>
      Duration(seconds: minimumTripDurationSeconds);

  /// Get stationary timeout as Duration object
  Duration get stationaryTimeout =>
      Duration(seconds: stationaryTimeoutSeconds);
}
