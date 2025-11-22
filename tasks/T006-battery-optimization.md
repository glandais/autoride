# T006: Battery-Optimized Location Strategy

## Overview

Implement intelligent battery optimization strategies for location tracking by integrating motion detection with GPS management. This task creates the critical bridge between the location service (T005) and motion detection (T007) to ensure the app can track trips all day without significant battery drain.

**Status**: ⏳ In Progress
**Dependencies**: T005 (Background Location Tracking), T007 (Sensor Integration)
**Estimate**: 2-3 hours
**Phase**: Phase 2 - Core Location & Sensors
**Target**: <5% battery drain per hour of active tracking

## Prerequisites

Before starting this task, ensure:
- ✅ T005 completed (Background location tracking with BackgroundLocationService)
- ✅ T007 completed (Motion detection with MotionDetectionService)
- ✅ Physical Android and iOS devices for battery profiling
- ✅ Understanding of power management best practices

## Objectives

1. Implement motion-gated GPS activation (only run GPS when moving)
2. Create adaptive location accuracy based on detected activity
3. Optimize distance-based filtering for cycling speeds
4. Add power state awareness (battery level monitoring)
5. Integrate battery optimizer with existing services
6. Achieve <5% battery drain per hour during active tracking
7. Maintain acceptable GPS accuracy for route recording

## Battery Optimization Principles

### Key Strategies

**Motion-Gated GPS**:
- Don't run GPS continuously
- Use accelerometer (low power) to detect movement first
- Only activate GPS when significant movement detected
- Stop GPS when stationary for >30 seconds

**Adaptive Accuracy**:
- Use lowest acceptable accuracy for each state
- Stationary/Detecting: No GPS or low accuracy
- Moving (non-cycling): Medium accuracy
- Cycling (active trip): Medium-high accuracy
- High accuracy only for critical moments (trip start/end)

**Distance Filtering**:
- Update location only when device moves >15m (optimal for cycling)
- Reduces GPS polling frequency by 50-70%
- Maintains route accuracy while saving battery

**Power State Awareness**:
- Monitor battery level continuously
- Reduce sampling rates when battery <20%
- Disable non-essential features in low power mode
- Gracefully degrade service quality vs. complete failure

## Implementation Steps

### Step 1: Create Battery Optimizer Service

**File**: `lib/features/trip_detection/data/services/battery_optimizer.dart`

```dart
import 'dart:async';
import 'package:battery_plus/battery_plus.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:geolocator/geolocator.dart';
import '../../../../core/constants/app_constants.dart';
import 'motion_detection_service.dart';

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
  final LocationAccuracy locationAccuracy;
  final int sensorSamplingRate; // Hz
  final Duration mlInferenceInterval;
  final Duration locationUpdateInterval;
  final int distanceFilter; // meters

  const PowerModeConfig({
    required this.locationAccuracy,
    required this.sensorSamplingRate,
    required this.mlInferenceInterval,
    required this.locationUpdateInterval,
    required this.distanceFilter,
  });

  /// Normal power mode (battery >50%)
  static const normal = PowerModeConfig(
    locationAccuracy: LocationAccuracy.medium,
    sensorSamplingRate: 50, // Hz
    mlInferenceInterval: Duration(seconds: 10),
    locationUpdateInterval: Duration(seconds: 30),
    distanceFilter: 15, // meters
  );

  /// Medium power mode (battery 20-50%)
  static const medium = PowerModeConfig(
    locationAccuracy: LocationAccuracy.medium,
    sensorSamplingRate: 40, // Hz
    mlInferenceInterval: Duration(seconds: 12),
    locationUpdateInterval: Duration(seconds: 40),
    distanceFilter: 20, // meters
  );

  /// Low power mode (battery 10-20%)
  static const low = PowerModeConfig(
    locationAccuracy: LocationAccuracy.low,
    sensorSamplingRate: 25, // Hz
    mlInferenceInterval: Duration(seconds: 15),
    locationUpdateInterval: Duration(seconds: 60),
    distanceFilter: 30, // meters
  );

  /// Critical power mode (battery <10%)
  static const critical = PowerModeConfig(
    locationAccuracy: LocationAccuracy.low,
    sensorSamplingRate: 20, // Hz
    mlInferenceInterval: Duration(seconds: 20),
    locationUpdateInterval: Duration(seconds: 90),
    distanceFilter: 50, // meters
  );
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
    _battery.onBatteryStateChanged.listen((BatteryState state) async {
      _currentBatteryLevel = await _battery.batteryLevel;
      await _updatePowerMode();
    });

    // Periodic battery check (every 5 minutes)
    _batteryCheckTimer = Timer.periodic(
      const Duration(minutes: 5),
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
    if (batteryLevel < 10) {
      return PowerModeConfig.critical;
    } else if (batteryLevel < 20) {
      return PowerModeConfig.low;
    } else if (batteryLevel < 50) {
      return PowerModeConfig.medium;
    } else {
      return PowerModeConfig.normal;
    }
  }

  /// Get current battery level
  int getCurrentBatteryLevel() => _currentBatteryLevel;

  /// Get battery level category
  BatteryLevel getBatteryLevelCategory() {
    if (_currentBatteryLevel < 10) return BatteryLevel.critical;
    if (_currentBatteryLevel < 20) return BatteryLevel.low;
    if (_currentBatteryLevel < 50) return BatteryLevel.medium;
    return BatteryLevel.normal;
  }

  /// Check if in power saving mode
  bool isInPowerSavingMode() {
    return _currentBatteryLevel < 20;
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
      error: (_, __) => PowerModeConfig.normal,
    );
  }
}
```

### Step 2: Create Motion-Gated GPS Controller

**File**: `lib/features/trip_detection/data/services/gps_controller.dart`

```dart
import 'dart:async';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:geolocator/geolocator.dart';
import '../../domain/models/motion_data.dart';
import 'motion_detection_service.dart';
import 'battery_optimizer.dart';
import 'location_service.dart';

part 'gps_controller.g.dart';

/// GPS state
enum GPSState {
  inactive,    // GPS not running
  activating,  // GPS starting up
  active,      // GPS running
  stopping,    // GPS shutting down
}

/// Motion-gated GPS controller
/// Only activates GPS when movement is detected by sensors
@riverpod
class GPSController extends _$GPSController {
  Timer? _inactivityTimer;
  GPSState _gpsState = GPSState.inactive;
  DateTime? _lastMovementTime;

  @override
  Stream<GPSState> build() async* {
    // Listen to motion state changes
    final motionStream = ref.watch(motionDetectionServiceProvider);

    await for (final motionStateAsync in motionStream) {
      await motionStateAsync.when(
        data: (motionState) async {
          final newGPSState = await _handleMotionState(motionState);
          if (newGPSState != _gpsState) {
            _gpsState = newGPSState;
            yield _gpsState;
          }
        },
        loading: () async {},
        error: (_, __) async {},
      );
    }
  }

  /// Handle motion state changes and determine GPS state
  Future<GPSState> _handleMotionState(MotionState motionState) async {
    switch (motionState) {
      case MotionState.stationary:
        return await _handleStationary();

      case MotionState.moving:
      case MotionState.cycling:
        return await _handleMovement();

      case MotionState.unknown:
        return _gpsState; // Maintain current state
    }
  }

  /// Handle stationary state
  Future<GPSState> _handleStationary() async {
    // Cancel any existing inactivity timer
    _inactivityTimer?.cancel();

    // Start inactivity timer (30 seconds)
    _inactivityTimer = Timer(const Duration(seconds: 30), () {
      _stopGPS();
    });

    return _gpsState;
  }

  /// Handle movement detected
  Future<GPSState> _handleMovement() async {
    _lastMovementTime = DateTime.now();

    // Cancel inactivity timer
    _inactivityTimer?.cancel();

    // Start GPS if not already active
    if (_gpsState == GPSState.inactive) {
      await _startGPS();
      return GPSState.active;
    }

    return _gpsState;
  }

  /// Start GPS tracking
  Future<void> _startGPS() async {
    if (_gpsState != GPSState.inactive) return;

    _gpsState = GPSState.activating;

    // Get current power mode
    final powerMode = ref.read(currentPowerModeProvider);

    // Configure location settings based on power mode
    final locationSettings = LocationSettings(
      accuracy: powerMode.locationAccuracy,
      distanceFilter: powerMode.distanceFilter,
      timeLimit: Duration(seconds: powerMode.locationUpdateInterval.inSeconds),
    );

    // Notify location service to start
    // (Implementation depends on how BackgroundLocationService is structured)

    _gpsState = GPSState.active;
  }

  /// Stop GPS tracking
  Future<void> _stopGPS() async {
    if (_gpsState == GPSState.inactive) return;

    _gpsState = GPSState.stopping;

    // Notify location service to stop
    // (Implementation depends on how BackgroundLocationService is structured)

    _gpsState = GPSState.inactive;
  }

  /// Force GPS activation (for manual trip start)
  Future<void> forceStartGPS() async {
    await _startGPS();
  }

  /// Force GPS deactivation (for manual trip stop)
  Future<void> forceStopGPS() async {
    await _stopGPS();
  }

  /// Get current GPS state
  GPSState getCurrentState() => _gpsState;

  /// Check if GPS is currently active
  bool isGPSActive() {
    return _gpsState == GPSState.active || _gpsState == GPSState.activating;
  }

  @override
  void dispose() {
    _inactivityTimer?.cancel();
    super.dispose();
  }
}
```

### Step 3: Create Adaptive Location Settings Provider

**File**: `lib/features/trip_detection/data/services/adaptive_location_settings.dart`

```dart
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:geolocator/geolocator.dart';
import '../../domain/models/motion_data.dart';
import 'motion_detection_service.dart';
import 'battery_optimizer.dart';

part 'adaptive_location_settings.g.dart';

/// Adaptive location settings based on motion state and battery level
@riverpod
class AdaptiveLocationSettings extends _$AdaptiveLocationSettings {
  @override
  LocationSettings build() {
    final motionState = ref.watch(currentMotionStateProvider);
    final powerMode = ref.read(currentPowerModeProvider);

    return motionState.when(
      data: (state) => _getSettingsForMotionState(state, powerMode),
      loading: () => _getDefaultSettings(powerMode),
      error: (_, __) => _getDefaultSettings(powerMode),
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
        return LocationSettings(
          accuracy: LocationAccuracy.low,
          distanceFilter: 100, // Only update if moved 100m
          timeLimit: const Duration(minutes: 5),
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
        return LocationSettings(
          accuracy: LocationAccuracy.medium,
          distanceFilter: 15, // 15m is optimal for cycling
          timeLimit: const Duration(seconds: 30),
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
```

### Step 4: Update AppConstants with Battery Optimization Values

**File**: `lib/core/constants/app_constants.dart` (update existing file)

```dart
// Add to existing AppConstants class

class AppConstants {
  // ... existing constants ...

  // Battery Optimization Constants
  static const int batteryCheckIntervalMinutes = 5;
  static const int criticalBatteryThreshold = 10; // %
  static const int lowBatteryThreshold = 20; // %
  static const int mediumBatteryThreshold = 50; // %

  // GPS Inactivity Timeout
  static const Duration gpsInactivityTimeout = Duration(seconds: 30);

  // Distance Filters by State
  static const int distanceFilterStationary = 100; // meters
  static const int distanceFilterMoving = 20; // meters
  static const int distanceFilterCycling = 15; // meters (optimal for cycling)

  // Location Update Intervals by Power Mode
  static const Duration locationUpdateNormal = Duration(seconds: 30);
  static const Duration locationUpdateMedium = Duration(seconds: 40);
  static const Duration locationUpdateLow = Duration(seconds: 60);
  static const Duration locationUpdateCritical = Duration(seconds: 90);

  // Sensor Sampling Rates by Power Mode (Hz)
  static const int sensorSamplingRateNormal = 50;
  static const int sensorSamplingRateMedium = 40;
  static const int sensorSamplingRateLow = 25;
  static const int sensorSamplingRateCritical = 20;
}
```

### Step 5: Update pubspec.yaml for Battery Monitoring

**File**: `pubspec.yaml` (add battery_plus dependency)

```yaml
dependencies:
  # ... existing dependencies ...

  # Battery monitoring
  battery_plus: ^6.0.0
```

Then run:
```bash
flutter pub get
```

### Step 6: Create Unit Tests for Battery Optimizer

**File**: `test/features/trip_detection/data/services/battery_optimizer_test.dart`

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:autoride/features/trip_detection/data/services/battery_optimizer.dart';

void main() {
  group('BatteryOptimizer', () {
    test('should return critical power mode for battery <10%', () {
      final optimizer = BatteryOptimizer();
      final config = optimizer.getPowerModeForBatteryLevel(5);

      expect(config, equals(PowerModeConfig.critical));
      expect(config.sensorSamplingRate, equals(20));
      expect(config.distanceFilter, equals(50));
    });

    test('should return low power mode for battery 10-20%', () {
      final optimizer = BatteryOptimizer();
      final config = optimizer.getPowerModeForBatteryLevel(15);

      expect(config, equals(PowerModeConfig.low));
      expect(config.sensorSamplingRate, equals(25));
      expect(config.distanceFilter, equals(30));
    });

    test('should return medium power mode for battery 20-50%', () {
      final optimizer = BatteryOptimizer();
      final config = optimizer.getPowerModeForBatteryLevel(35);

      expect(config, equals(PowerModeConfig.medium));
      expect(config.sensorSamplingRate, equals(40));
      expect(config.distanceFilter, equals(20));
    });

    test('should return normal power mode for battery >50%', () {
      final optimizer = BatteryOptimizer();
      final config = optimizer.getPowerModeForBatteryLevel(75);

      expect(config, equals(PowerModeConfig.normal));
      expect(config.sensorSamplingRate, equals(50));
      expect(config.distanceFilter, equals(15));
    });

    test('should identify power saving mode correctly', () {
      final optimizer = BatteryOptimizer();

      expect(optimizer.isInPowerSavingMode(15), isTrue);
      expect(optimizer.isInPowerSavingMode(25), isFalse);
    });
  });

  group('PowerModeConfig', () {
    test('normal config should have highest performance', () {
      const config = PowerModeConfig.normal;

      expect(config.sensorSamplingRate, equals(50));
      expect(config.distanceFilter, equals(15));
      expect(config.locationUpdateInterval, equals(Duration(seconds: 30)));
    });

    test('critical config should have lowest power consumption', () {
      const config = PowerModeConfig.critical;

      expect(config.sensorSamplingRate, equals(20));
      expect(config.distanceFilter, equals(50));
      expect(config.locationUpdateInterval, equals(Duration(seconds: 90)));
    });
  });
}
```

### Step 7: Create Integration Tests for GPS Controller

**File**: `test/features/trip_detection/data/services/gps_controller_test.dart`

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:autoride/features/trip_detection/data/services/gps_controller.dart';
import 'package:autoride/features/trip_detection/domain/models/motion_data.dart';

void main() {
  group('GPSController', () {
    test('should activate GPS when movement detected', () async {
      final controller = GPSController();

      // Simulate movement detection
      await controller.handleMotionState(MotionState.moving);

      expect(controller.isGPSActive(), isTrue);
      expect(controller.getCurrentState(), equals(GPSState.active));
    });

    test('should deactivate GPS after 30 seconds of inactivity', () async {
      final controller = GPSController();

      // Activate GPS with movement
      await controller.handleMotionState(MotionState.cycling);
      expect(controller.isGPSActive(), isTrue);

      // Simulate stationary state
      await controller.handleMotionState(MotionState.stationary);

      // Wait for inactivity timeout (30 seconds)
      await Future.delayed(const Duration(seconds: 31));

      expect(controller.isGPSActive(), isFalse);
      expect(controller.getCurrentState(), equals(GPSState.inactive));
    });

    test('should cancel inactivity timer when movement resumes', () async {
      final controller = GPSController();

      // Activate GPS
      await controller.handleMotionState(MotionState.cycling);

      // Stationary (starts timer)
      await controller.handleMotionState(MotionState.stationary);

      // Movement resumes before timeout
      await Future.delayed(const Duration(seconds: 10));
      await controller.handleMotionState(MotionState.moving);

      // Wait past original timeout
      await Future.delayed(const Duration(seconds: 25));

      // GPS should still be active (timer was cancelled)
      expect(controller.isGPSActive(), isTrue);
    });

    test('should support manual GPS control', () async {
      final controller = GPSController();

      // Force start
      await controller.forceStartGPS();
      expect(controller.isGPSActive(), isTrue);

      // Force stop
      await controller.forceStopGPS();
      expect(controller.isGPSActive(), isFalse);
    });
  });
}
```

## Testing Criteria

### Unit Tests
- [ ] Battery optimizer correctly selects power mode for each battery level
- [ ] Power mode configurations have correct values
- [ ] GPS controller activates/deactivates based on motion state
- [ ] Inactivity timer works correctly
- [ ] Adaptive location settings adjust based on motion and power state

### Integration Tests
- [ ] Battery level changes trigger power mode updates
- [ ] Motion state changes trigger GPS activation/deactivation
- [ ] Location settings adapt to motion state and battery level
- [ ] System works correctly across all power modes

### Physical Device Testing
- [ ] **Battery Profiling** (Critical):
  - Android: Use Android Studio Battery Profiler
  - iOS: Use Xcode Energy Log
  - Test scenario: 1-hour continuous cycling simulation
  - Target: <5% battery drain per hour

- [ ] **GPS Accuracy**:
  - Verify route accuracy with motion-gated GPS
  - Compare with always-on GPS baseline
  - Ensure no significant degradation

- [ ] **State Transitions**:
  - Stationary → Moving: GPS activates within 5 seconds
  - Moving → Stationary (30s): GPS deactivates correctly
  - Low battery mode: Reduced sampling rates applied

- [ ] **Battery Level Scenarios**:
  - Normal (>50%): Full performance
  - Medium (20-50%): Reduced but acceptable
  - Low (<20%): Minimal features, still functional
  - Critical (<10%): Essential features only

## Acceptance Criteria

### Functional Requirements
- ✅ GPS only runs when movement is detected
- ✅ GPS stops after 30 seconds of inactivity
- ✅ Location accuracy adapts to motion state
- ✅ Battery level monitoring works correctly
- ✅ Power mode configurations applied properly
- ✅ Manual GPS control available for testing

### Performance Requirements
- ✅ Battery drain <5% per hour during active cycling
- ✅ GPS accuracy within 15m for cycling routes
- ✅ State transitions happen within 5 seconds
- ✅ No significant lag or performance issues

### Quality Requirements
- ✅ All unit tests pass
- ✅ All integration tests pass
- ✅ Battery profiling shows acceptable power consumption
- ✅ No memory leaks or resource issues
- ✅ Graceful degradation in low battery mode

## Common Pitfalls

### Pitfall 1: GPS Takes Too Long to Activate

**Problem**: GPS cold start can take 30+ seconds, causing missed trip starts.

**Solution**:
```dart
// Pre-warm GPS periodically when movement detected
if (motionState == MotionState.moving && !isGPSActive) {
  // Quick position check to warm up GPS
  await Geolocator.getCurrentPosition(
    desiredAccuracy: LocationAccuracy.low,
    timeLimit: const Duration(seconds: 5),
  );
  // Then start full tracking
  await _startGPS();
}
```

### Pitfall 2: Battery Drain Still High

**Investigation Steps**:
1. Profile with Android Studio Battery Profiler
2. Check if GPS is stopping correctly when stationary
3. Verify sensor sampling rates are being reduced
4. Ensure location updates use distance filtering
5. Check for location listener leaks

**Common Causes**:
- GPS not stopping when stationary
- Sensor sampling rate too high (should be 25-50 Hz, not 100 Hz)
- No distance filtering (causes constant updates)
- Multiple location listeners active

### Pitfall 3: Location Accuracy Degraded

**Problem**: Motion-gated GPS causes gaps in route tracking.

**Solution**:
```dart
// Use buffering strategy
final locationBuffer = <Position>[];

// When GPS reactivates, get recent positions if available
if (_gpsState == GPSState.activating) {
  // Some devices cache recent positions
  final lastKnownPosition = await Geolocator.getLastKnownPosition();
  if (lastKnownPosition != null) {
    locationBuffer.add(lastKnownPosition);
  }
}
```

### Pitfall 4: Inactivity Timer Not Canceling

**Problem**: GPS stops during brief pauses (e.g., red light).

**Solution**:
```dart
// Adjust timer duration based on context
Duration getInactivityTimeout(MotionState previousState) {
  if (previousState == MotionState.cycling) {
    return const Duration(seconds: 60); // Longer timeout for cycling
  }
  return const Duration(seconds: 30); // Normal timeout
}
```

## Battery Profiling Guide

### Android Battery Profiling

1. **Enable Profiler in Android Studio**:
   - Run app in debug mode
   - Open Profiler tab (View → Tool Windows → Profiler)
   - Select Energy profiler

2. **Test Scenario**:
   - Start app with full battery (or note starting percentage)
   - Simulate 1-hour cycling trip:
     - Shake device periodically to simulate motion
     - Move outdoors for real GPS tracking
   - Record battery percentage before/after

3. **Analysis**:
   - Check "Energy usage" graph
   - Look for GPS, Sensors, CPU spikes
   - Identify high consumption periods
   - Target: <5% battery drain per hour

### iOS Battery Profiling

1. **Enable Energy Log in Xcode**:
   - Run app on physical device
   - Open Debug Navigator (⌘+7)
   - Select "Energy Impact"

2. **Test Scenario**:
   - Same as Android (1-hour cycling simulation)
   - Monitor "Energy Impact" graph
   - Note "Overhead" and "Average" values

3. **Analysis**:
   - "Very High" impact is bad
   - "Low" or "Medium" is acceptable
   - Check location, motion, and processing usage

## Integration with Existing Services

### Update BackgroundLocationService (T005)

**File**: `lib/features/trip_detection/data/services/background_location_service.dart`

```dart
// Add to existing BackgroundLocationService

@riverpod
class BackgroundLocationService extends _$BackgroundLocationService {
  // ... existing code ...

  // Add GPS controller integration
  void initializeGPSController() {
    ref.listen(gpsControllerProvider, (previous, next) {
      next.when(
        data: (gpsState) {
          if (gpsState == GPSState.active) {
            _startLocationTracking();
          } else if (gpsState == GPSState.inactive) {
            _stopLocationTracking();
          }
        },
        loading: () {},
        error: (_, __) {},
      );
    });
  }

  // Add adaptive location settings
  LocationSettings getAdaptiveSettings() {
    return ref.read(adaptiveLocationSettingsProvider);
  }
}
```

### Update MotionDetectionService (T007)

**File**: `lib/features/trip_detection/data/services/motion_detection_service.dart`

```dart
// Add to existing MotionDetectionService

@riverpod
class MotionDetectionService extends _$MotionDetectionService {
  // ... existing code ...

  // Add power mode awareness
  int getAdaptiveSamplingRate() {
    final powerMode = ref.read(currentPowerModeProvider);
    return powerMode.sensorSamplingRate;
  }

  // Adjust buffer size based on power mode
  int getAdaptiveBufferSize() {
    final powerMode = ref.read(currentPowerModeProvider);
    final samplingRate = powerMode.sensorSamplingRate;
    return samplingRate * 60; // 60 seconds of data
  }
}
```

## Performance Targets

### Battery Consumption
- **Target**: <5% per hour of active tracking
- **Acceptable**: <8% per hour
- **Unacceptable**: >10% per hour

### GPS Accuracy
- **Target**: 90% of points within 15m of actual route
- **Acceptable**: 80% of points within 20m
- **Unacceptable**: <70% accuracy

### State Transition Speed
- **Target**: <3 seconds from motion detection to GPS activation
- **Acceptable**: <5 seconds
- **Unacceptable**: >10 seconds

### Memory Usage
- **Target**: <50 MB additional memory for battery optimization
- **Acceptable**: <75 MB
- **Unacceptable**: >100 MB

## Success Metrics

After implementing T006, the app should achieve:
- ✅ All-day tracking capability (8+ hours on a single charge)
- ✅ Minimal battery impact when not cycling
- ✅ Accurate route tracking despite GPS gating
- ✅ Graceful performance degradation in low battery scenarios
- ✅ No user-visible lag or delays
- ✅ Passes battery profiling tests on both platforms

## Next Steps

After completing T006, you will be ready to:
- **T008**: Cycling Motion Pattern Detection - Refine cycling-specific patterns for better accuracy
- **T012**: Trip State Machine - Build on optimized location/motion to create trip detection logic

## Resources

### Battery Optimization Best Practices
- [Android Battery Optimization](https://developer.android.com/topic/performance/power)
- [iOS Energy Efficiency](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/EnergyGuide-iOS/)
- [Flutter Battery Plugin](https://pub.dev/packages/battery_plus)

### Location Services
- [Geolocator Documentation](https://pub.dev/packages/geolocator)
- [Android Location Best Practices](https://developer.android.com/training/location)
- [iOS Location Best Practices](https://developer.apple.com/documentation/corelocation/choosing_the_location_services_authorization_to_request)

### Performance Profiling
- [Android Studio Profiler](https://developer.android.com/studio/profile)
- [Xcode Energy Log](https://developer.apple.com/documentation/xcode/gathering-information-about-energy-usage)

---

**Last Updated**: 2025-11-22
**Version**: 1.0
