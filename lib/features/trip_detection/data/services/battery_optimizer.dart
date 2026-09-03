import 'dart:async';

import 'package:battery_plus/battery_plus.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:geolocator/geolocator.dart';

import '../../../../core/audit/audit_event.dart';
import '../../../../core/audit/audit_log.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../settings/data/services/settings_service.dart';
import '../../../settings/domain/models/user_settings.dart';

part 'battery_optimizer.g.dart';

/// Battery level enum
enum BatteryLevel {
  critical, // <10%
  low, // 10-20%
  medium, // 20-50%
  normal, // >50%
}

/// Power mode configuration
class PowerModeConfig {
  const PowerModeConfig({
    required this.name,
    required this.locationAccuracy,
    required this.sensorSamplingRate,
    required this.mlInferenceInterval,
    required this.locationUpdateInterval,
    required this.distanceFilter,
  });

  /// Which of the four modes this is, for logs and the audit journal.
  final String name;

  final LocationAccuracy locationAccuracy;
  final int sensorSamplingRate; // Hz
  final Duration mlInferenceInterval;
  final Duration locationUpdateInterval;
  final int distanceFilter; // meters

  /// Longest gap between two fixes this mode may derive a speed from (T048).
  ///
  /// Scaled from [locationUpdateInterval] rather than fixed, because a bound at
  /// or below the interval the mode itself asks for can never fire — which is
  /// exactly how the first version of T048 derived nothing at all on Android.
  /// See [AppConstants.derivedSpeedMaxGapFactor].
  Duration get derivedSpeedMaxGap =>
      locationUpdateInterval * AppConstants.derivedSpeedMaxGapFactor;

  /// Normal power mode (battery >50%)
  static const normal = PowerModeConfig(
    name: 'normal',
    locationAccuracy: LocationAccuracy.medium,
    sensorSamplingRate: AppConstants.sensorSamplingRateNormal,
    mlInferenceInterval: Duration(seconds: 10),
    locationUpdateInterval: AppConstants.locationUpdateNormal,
    distanceFilter: AppConstants.distanceFilterCycling,
  );

  /// Medium power mode (battery 20-50%)
  static const medium = PowerModeConfig(
    name: 'medium',
    locationAccuracy: LocationAccuracy.medium,
    sensorSamplingRate: AppConstants.sensorSamplingRateMedium,
    mlInferenceInterval: Duration(seconds: 12),
    locationUpdateInterval: AppConstants.locationUpdateMedium,
    distanceFilter: AppConstants.distanceFilterMoving,
  );

  /// Low power mode (battery 10-20%)
  static const low = PowerModeConfig(
    name: 'low',
    locationAccuracy: LocationAccuracy.low,
    sensorSamplingRate: AppConstants.sensorSamplingRateLow,
    mlInferenceInterval: Duration(seconds: 15),
    locationUpdateInterval: AppConstants.locationUpdateLow,
    distanceFilter: AppConstants.distanceFilterLowPower,
  );

  /// Critical power mode (battery <10%)
  static const critical = PowerModeConfig(
    name: 'critical',
    locationAccuracy: LocationAccuracy.low,
    sensorSamplingRate: AppConstants.sensorSamplingRateCritical,
    mlInferenceInterval: Duration(seconds: 20),
    locationUpdateInterval: AppConstants.locationUpdateCritical,
    distanceFilter: AppConstants.distanceFilterCriticalPower,
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
  StreamSubscription<BatteryState>? _batterySubscription;
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
    _batterySubscription = _battery.onBatteryStateChanged.listen((
      BatteryState batteryState,
    ) async {
      _currentBatteryLevel = await _battery.batteryLevel;
      _auditBatteryLevel(batteryState);
      await _updatePowerMode();
    });

    // Periodic battery check (every 5 minutes)
    _batteryCheckTimer = Timer.periodic(
      const Duration(minutes: AppConstants.batteryCheckIntervalMinutes),
      (_) async {
        _currentBatteryLevel = await _battery.batteryLevel;
        _auditBatteryLevel(await _battery.batteryState);
        await _updatePowerMode();
      },
    );

    ref.onDispose(() {
      _batteryCheckTimer?.cancel();
      _batterySubscription?.cancel();
    });
  }

  /// Update power mode based on battery level
  Future<void> _updatePowerMode() async {
    final newConfig = _getPowerModeForBatteryLevel(_currentBatteryLevel);
    final previous = state.value;
    state = AsyncValue.data(newConfig);

    // The power mode is the denominator of the battery-drain measurement
    // (`tasks/T041-device-validation.md` item 4): a drain figure means nothing
    // without knowing which sampling rate and distance filter were in force.
    if (previous != newConfig) {
      AuditLog.emit(
        AuditEvent.powerMode,
        () => <String, Object?>{
          'm': newConfig.name,
          'b': _currentBatteryLevel,
          'hz': newConfig.sensorSamplingRate,
          'df': newConfig.distanceFilter,
          'ui': newConfig.locationUpdateInterval.inSeconds,
          'la': newConfig.locationAccuracy.name,
        },
        critical: true,
      );
    }
  }

  /// A battery reading, on the existing 5-minute tick and on every OS-reported
  /// battery-state change. Two of these bracket a ride and give the %/hour
  /// figure item 4 asks for, without a profiler attached.
  ///
  /// A reading identical to the last one and taken within the same 5-minute
  /// tick is dropped — see [BatteryAuditThrottle].
  void _auditBatteryLevel(BatteryState batteryState) {
    // Before the throttle, not after: a reading taken while the log is off is
    // not a line, and letting it advance the throttle would suppress the first
    // real `bat` line for up to a tick — the one that opens the %/hour figure
    // of `tasks/T041-device-validation.md` item 4.
    if (!AuditLog.enabled) return;

    final charging =
        batteryState == BatteryState.charging ||
        batteryState == BatteryState.full;
    if (!batteryAuditThrottle.accept(
      level: _currentBatteryLevel,
      charging: charging,
      at: DateTime.now(),
    )) {
      return;
    }

    AuditLog.emit(
      AuditEvent.battery,
      () => <String, Object?>{'b': _currentBatteryLevel, 'ch': charging},
    );
  }

  /// Get power mode configuration for battery level
  /// Respects user's battery optimization mode preference
  PowerModeConfig _getPowerModeForBatteryLevel(int batteryLevel) {
    final settings = ref.read(currentSettingsProvider);

    // Performance mode: always use normal/medium mode for best performance
    if (settings.batteryMode == BatteryOptimizationMode.performance) {
      // Still respect critical battery level for safety
      if (batteryLevel < AppConstants.criticalBatteryThreshold) {
        return PowerModeConfig
            .low; // Use low instead of critical in performance mode
      }
      return PowerModeConfig.normal; // Maximum performance otherwise
    }

    // Aggressive mode: switch to battery saving earlier
    if (settings.batteryMode == BatteryOptimizationMode.aggressive) {
      if (batteryLevel < AppConstants.criticalBatteryThreshold) {
        return PowerModeConfig.critical;
      } else if (batteryLevel < AppConstants.mediumBatteryThreshold) {
        // Start saving battery earlier (at 50% instead of 20%)
        return PowerModeConfig.low;
      } else if (batteryLevel < 70) {
        return PowerModeConfig.medium;
      } else {
        return PowerModeConfig.normal;
      }
    }

    // Balanced mode (default): standard thresholds from AppConstants
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

/// Which `bat` readings are worth a line.
///
/// `onBatteryStateChanged` replays the current state to every fresh
/// subscriber, and [BatteryOptimizer] is rebuilt whenever a detection session
/// restarts, so a restart wrote two `bat` lines in the same second carrying the
/// same level and the same charging flag — which reads as a battery that moved
/// and came back (L-086). A repeat says nothing: the %/hour figure the log
/// exists to support (`tasks/T041-device-validation.md` item 4) is computed
/// from the changes.
///
/// Not suppressed forever, though: after [AppConstants.batteryCheckIntervalMinutes]
/// an unchanged level is written again, so a flat battery still leaves proof
/// that it was being read at all.
///
/// Owned as a single [batteryAuditThrottle] rather than a field of the
/// notifier, because it has to outlive the notifier being disposed and rebuilt.
class BatteryAuditThrottle {
  int? _level;
  bool? _charging;
  DateTime? _at;

  /// Whether this reading should be journalled, recording it if so.
  bool accept({
    required int level,
    required bool charging,
    required DateTime at,
  }) {
    final since = _at;
    if (level == _level &&
        charging == _charging &&
        since != null &&
        at.difference(since) <
            const Duration(minutes: AppConstants.batteryCheckIntervalMinutes)) {
      return false;
    }
    _level = level;
    _charging = charging;
    _at = at;
    return true;
  }
}

/// The process-wide battery-audit throttle. See [BatteryAuditThrottle].
final BatteryAuditThrottle batteryAuditThrottle = BatteryAuditThrottle();
