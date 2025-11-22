import 'dart:async';
import 'package:battery_plus/battery_plus.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:geolocator/geolocator.dart';
import '../../../../core/constants/app_constants.dart';

part 'battery_optimizer.g.dart';

/// Battery level enum
enum BatteryLevel {
  critical,  // <10%
  low,       // 10-20%
  medium,    // 20-50%
  normal,    // >50%
}

/// Power mode configuration
class PowerModeConfig {
  const PowerModeConfig({
    required this.locationAccuracy,
    required this.sensorSamplingRate,
    required this.mlInferenceInterval,
    required this.locationUpdateInterval,
    required this.distanceFilter,
  });

  final LocationAccuracy locationAccuracy;
  final int sensorSamplingRate; // Hz
  final Duration mlInferenceInterval;
  final Duration locationUpdateInterval;
  final int distanceFilter; // meters

  /// Normal power mode (battery >50%)
  static const normal = PowerModeConfig(
    locationAccuracy: LocationAccuracy.medium,
    sensorSamplingRate: AppConstants.sensorSamplingRateNormal,
    mlInferenceInterval: Duration(seconds: 10),
    locationUpdateInterval: AppConstants.locationUpdateNormal,
    distanceFilter: AppConstants.distanceFilterCycling,
  );

  /// Medium power mode (battery 20-50%)
  static const medium = PowerModeConfig(
    locationAccuracy: LocationAccuracy.medium,
    sensorSamplingRate: AppConstants.sensorSamplingRateMedium,
    mlInferenceInterval: Duration(seconds: 12),
    locationUpdateInterval: AppConstants.locationUpdateMedium,
    distanceFilter: AppConstants.distanceFilterMoving,
  );

  /// Low power mode (battery 10-20%)
  static const low = PowerModeConfig(
    locationAccuracy: LocationAccuracy.low,
    sensorSamplingRate: AppConstants.sensorSamplingRateLow,
    mlInferenceInterval: Duration(seconds: 15),
    locationUpdateInterval: AppConstants.locationUpdateLow,
    distanceFilter: AppConstants.distanceFilterMoving + 10,
  );

  /// Critical power mode (battery <10%)
  static const critical = PowerModeConfig(
    locationAccuracy: LocationAccuracy.low,
    sensorSamplingRate: AppConstants.sensorSamplingRateCritical,
    mlInferenceInterval: Duration(seconds: 20),
    locationUpdateInterval: AppConstants.locationUpdateCritical,
    distanceFilter: AppConstants.distanceFilterStationary ~/ 2,
  );

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PowerModeConfig &&
        other.locationAccuracy == locationAccuracy &&
        other.sensorSamplingRate == sensorSamplingRate &&
        other.mlInferenceInterval == mlInferenceInterval &&
        other.locationUpdateInterval == locationUpdateInterval &&
        other.distanceFilter == distanceFilter;
  }

  @override
  int get hashCode {
    return Object.hash(
      locationAccuracy,
      sensorSamplingRate,
      mlInferenceInterval,
      locationUpdateInterval,
      distanceFilter,
    );
  }
}

/// Battery optimizer service
@riverpod
class BatteryOptimizer extends _$BatteryOptimizer {
  final Battery _battery = Battery();
  Timer? _batteryCheckTimer;
  int _currentBatteryLevel = 100;

  @override
  Future<PowerModeConfig> build() async {
    // Initialize battery monitoring
    await _initializeBatteryMonitoring();

    // Return initial power mode based on current battery level
    return _getPowerModeForBatteryLevel(_currentBatteryLevel);
  }

  /// Initialize battery level monitoring
  Future<void> _initializeBatteryMonitoring() async {
    // Get initial battery level
    _currentBatteryLevel = await _battery.batteryLevel;

    // Monitor battery level changes
    _battery.onBatteryStateChanged.listen((BatteryState batteryState) async {
      _currentBatteryLevel = await _battery.batteryLevel;
      await _updatePowerMode();
    });

    // Periodic battery check (every 5 minutes)
    _batteryCheckTimer = Timer.periodic(
      const Duration(minutes: AppConstants.batteryCheckIntervalMinutes),
      (_) async {
        _currentBatteryLevel = await _battery.batteryLevel;
        await _updatePowerMode();
      },
    );

    ref.onDispose(() {
      _batteryCheckTimer?.cancel();
    });
  }

  /// Update power mode based on battery level
  Future<void> _updatePowerMode() async {
    final newConfig = _getPowerModeForBatteryLevel(_currentBatteryLevel);
    state = AsyncValue.data(newConfig);
  }

  /// Get power mode configuration for battery level
  PowerModeConfig _getPowerModeForBatteryLevel(int batteryLevel) {
    if (batteryLevel < AppConstants.criticalBatteryThreshold) {
      return PowerModeConfig.critical;
    } else if (batteryLevel < AppConstants.lowBatteryThreshold) {
      return PowerModeConfig.low;
    } else if (batteryLevel < AppConstants.mediumBatteryThreshold) {
      return PowerModeConfig.medium;
    } else {
      return PowerModeConfig.normal;
    }
  }

  /// Get current battery level
  int getCurrentBatteryLevel() => _currentBatteryLevel;

  /// Get battery level category
  BatteryLevel getBatteryLevelCategory() {
    if (_currentBatteryLevel < AppConstants.criticalBatteryThreshold) {
      return BatteryLevel.critical;
    }
    if (_currentBatteryLevel < AppConstants.lowBatteryThreshold) {
      return BatteryLevel.low;
    }
    if (_currentBatteryLevel < AppConstants.mediumBatteryThreshold) {
      return BatteryLevel.medium;
    }
    return BatteryLevel.normal;
  }

  /// Check if in power saving mode
  bool isInPowerSavingMode() {
    return _currentBatteryLevel < AppConstants.lowBatteryThreshold;
  }
}

/// Provider for current power mode configuration
@riverpod
class CurrentPowerMode extends _$CurrentPowerMode {
  @override
  PowerModeConfig build() {
    final batteryOptimizer = ref.watch(batteryOptimizerProvider);
    return batteryOptimizer.when(
      data: (config) => config,
      loading: () => PowerModeConfig.normal,
      error: (_, _) => PowerModeConfig.normal,
    );
  }
}
