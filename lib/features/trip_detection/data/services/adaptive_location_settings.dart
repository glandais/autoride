import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:geolocator/geolocator.dart';
import '../../domain/models/motion_data.dart';
import 'motion_detection_service.dart';
import 'battery_optimizer.dart';
import '../../../../core/constants/app_constants.dart';

part 'adaptive_location_settings.g.dart';

/// Adaptive location settings based on motion state and battery level
@riverpod
class AdaptiveLocationSettings extends _$AdaptiveLocationSettings {
  @override
  LocationSettings build() {
    // Watch current motion state
    final motionStateAsync = ref.watch(currentMotionStateProvider);
    final powerMode = ref.watch(currentPowerModeProvider);

    return motionStateAsync.when(
      data: (motionState) => _getSettingsForMotionState(motionState, powerMode),
      loading: () => _getDefaultSettings(powerMode),
      error: (_, _) => _getDefaultSettings(powerMode),
    );
  }

  /// Get location settings for current motion state
  LocationSettings _getSettingsForMotionState(
    MotionState motionState,
    PowerModeConfig powerMode,
  ) {
    switch (motionState) {
      case MotionState.stationary:
        // Minimal GPS usage when stationary
        return const LocationSettings(
          accuracy: LocationAccuracy.low,
          distanceFilter: AppConstants.distanceFilterStationary,
          timeLimit: Duration(minutes: 5),
        );

      case MotionState.moving:
        // Medium accuracy for general movement
        return LocationSettings(
          accuracy: LocationAccuracy.medium,
          distanceFilter: powerMode.distanceFilter,
          timeLimit: Duration(seconds: powerMode.locationUpdateInterval.inSeconds),
        );

      case MotionState.cycling:
        // Optimized for cycling speed and accuracy
        return const LocationSettings(
          accuracy: LocationAccuracy.medium,
          distanceFilter: AppConstants.distanceFilterCycling,
          timeLimit: Duration(seconds: 30),
        );

      case MotionState.unknown:
        // Default settings
        return _getDefaultSettings(powerMode);
    }
  }

  /// Get default location settings
  LocationSettings _getDefaultSettings(PowerModeConfig powerMode) {
    return LocationSettings(
      accuracy: powerMode.locationAccuracy,
      distanceFilter: powerMode.distanceFilter,
      timeLimit: Duration(seconds: powerMode.locationUpdateInterval.inSeconds),
    );
  }

  /// Get high accuracy settings (for critical moments)
  LocationSettings getHighAccuracySettings() {
    return const LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10,
      timeLimit: Duration(seconds: 20),
    );
  }

  /// Get low power settings (for background idle state)
  LocationSettings getLowPowerSettings() {
    return const LocationSettings(
      accuracy: LocationAccuracy.low,
      distanceFilter: 50,
      timeLimit: Duration(minutes: 2),
    );
  }
}
