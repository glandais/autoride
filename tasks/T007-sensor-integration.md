# T007: Sensor Integration (Accelerometer/Gyroscope)

## Overview

Implement motion sensor integration using sensors_plus to detect movement patterns and provide the foundation for automatic cycling detection. This task focuses on creating a clean abstraction over raw sensor data and implementing basic movement detection logic that will be used by the trip detection system.

**Status**: ⏳ In Progress
**Dependencies**: T003 (Riverpod Setup)
**Estimate**: 2-3 hours
**Phase**: Phase 2 - Core Location & Sensors

## Prerequisites

Before starting this task, ensure:
- ✅ T003 completed (Riverpod code generation configured)
- ✅ sensors_plus dependency in pubspec.yaml (version 7.0.0+)
- ✅ Physical Android and iOS devices for testing (sensors don't work properly in emulators)
- ✅ AppConstants defined with sensor thresholds

## Objectives

1. Create motion data models for accelerometer and gyroscope
2. Implement Riverpod providers for sensor streams
3. Build motion detection service for basic movement detection
4. Implement sliding window buffer for pattern analysis
5. Create utility functions for sensor data processing
6. Ensure battery-efficient sensor sampling (<1% per hour)

## Implementation Steps

### Step 1: Create Motion Data Domain Models

**File**: `lib/features/trip_detection/domain/models/motion_data.dart`

```dart
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'dart:math';

part 'motion_data.freezed.dart';

/// Accelerometer data model
@freezed
class AccelerometerData with _$AccelerometerData {
  const factory AccelerometerData({
    required double x,
    required double y,
    required double z,
    required DateTime timestamp,
  }) = _AccelerometerData;

  const AccelerometerData._();

  factory AccelerometerData.fromEvent(AccelerometerEvent event) {
    return AccelerometerData(
      x: event.x,
      y: event.y,
      z: event.z,
      timestamp: DateTime.now(),
    );
  }

  /// Calculate magnitude (total acceleration)
  /// Formula: sqrt(x² + y² + z²)
  double get magnitude => sqrt(x * x + y * y + z * z);

  /// Check if device is stationary (within threshold)
  bool isStationary({double threshold = 9.8}) {
    // Standard gravity is ~9.8 m/s²
    // Stationary device should be close to gravity magnitude
    return (magnitude - threshold).abs() < 0.5;
  }

  /// Check if significant movement detected
  bool hasSignificantMovement({double threshold = 1.5}) {
    // Movement above threshold indicates acceleration beyond gravity
    return (magnitude - 9.8).abs() > threshold;
  }
}

/// Gyroscope data model
@freezed
class GyroscopeData with _$GyroscopeData {
  const factory GyroscopeData({
    required double x,
    required double y,
    required double z,
    required DateTime timestamp,
  }) = _GyroscopeData;

  const GyroscopeData._();

  factory GyroscopeData.fromEvent(GyroscopeEvent event) {
    return GyroscopeData(
      x: event.x,
      y: event.y,
      z: event.z,
      timestamp: DateTime.now(),
    );
  }

  /// Calculate rotation magnitude (angular velocity)
  /// Formula: sqrt(x² + y² + z²)
  double get magnitude => sqrt(x * x + y * y + z * z);

  /// Check if rotational movement detected (cycling has repetitive rotation)
  bool hasRotation({double threshold = 0.5}) {
    return magnitude > threshold; // rad/s
  }
}

/// Combined motion data (accelerometer + gyroscope)
@freezed
class MotionData with _$MotionData {
  const factory MotionData({
    required AccelerometerData accelerometer,
    required GyroscopeData gyroscope,
    required DateTime timestamp,
  }) = _MotionData;

  const MotionData._();

  /// Check if motion pattern indicates cycling activity
  /// Cycling typically has:
  /// - Sustained acceleration (pedaling)
  /// - Repetitive rotation (wheel spinning, pedaling motion)
  bool get indicatesCycling {
    // Basic heuristic - will be refined in T008
    final hasMovement = accelerometer.hasSignificantMovement();
    final hasRotation = gyroscope.hasRotation();
    return hasMovement && hasRotation;
  }

  /// Check if device is stationary
  bool get isStationary {
    return accelerometer.isStationary() && !gyroscope.hasRotation();
  }

  /// Total motion intensity (combined acceleration and rotation)
  double get intensity {
    return accelerometer.magnitude + gyroscope.magnitude;
  }
}

/// Motion state enumeration
enum MotionState {
  stationary,   // Device not moving
  moving,       // Device moving (could be walking, cycling, driving)
  cycling,      // Detected cycling pattern (requires T008 for accuracy)
  unknown,      // Insufficient data
}

/// Motion window for pattern analysis
@freezed
class MotionWindow with _$MotionWindow {
  const factory MotionWindow({
    required List<MotionData> samples,
    required DateTime startTime,
    required DateTime endTime,
  }) = _MotionWindow;

  const MotionWindow._();

  /// Window duration
  Duration get duration => endTime.difference(startTime);

  /// Average acceleration magnitude
  double get averageAcceleration {
    if (samples.isEmpty) return 0.0;
    final sum = samples.fold<double>(
      0.0,
      (sum, sample) => sum + sample.accelerometer.magnitude,
    );
    return sum / samples.length;
  }

  /// Average rotation magnitude
  double get averageRotation {
    if (samples.isEmpty) return 0.0;
    final sum = samples.fold<double>(
      0.0,
      (sum, sample) => sum + sample.gyroscope.magnitude,
    );
    return sum / samples.length;
  }

  /// Determine motion state based on window data
  MotionState get state {
    if (samples.isEmpty) return MotionState.unknown;

    final avgAccel = averageAcceleration;
    final avgRotation = averageRotation;

    // Stationary: low acceleration and rotation
    if (avgAccel < 10.0 && avgRotation < 0.3) {
      return MotionState.stationary;
    }

    // Movement detected - basic classification
    // Note: Refined cycling detection will be in T008
    if (avgAccel > 10.5 && avgRotation > 0.5) {
      return MotionState.cycling; // Preliminary detection
    }

    return MotionState.moving;
  }

  /// Check if window has enough samples for analysis
  bool get hasEnoughSamples => samples.length >= 50; // ~1 second at 50Hz
}
```

### Step 2: Create Sensor Service

**File**: `lib/features/trip_detection/data/services/sensor_service.dart`

```dart
import 'dart:async';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:sensors_plus/sensors_plus.dart';
import '../../domain/models/motion_data.dart';
import '../../../../core/constants/app_constants.dart';

part 'sensor_service.g.dart';

/// Accelerometer stream provider
/// Streams raw accelerometer data at configured sampling rate
@riverpod
Stream<AccelerometerData> accelerometerStream(
  AccelerometerStreamRef ref,
) async* {
  // Convert Hz to Duration for sampling period
  final samplingPeriod = Duration(
    microseconds: (1000000 / AppConstants.sensorSamplingRate).round(),
  );

  yield* accelerometerEventStream(samplingPeriod: samplingPeriod)
      .map((event) => AccelerometerData.fromEvent(event));
}

/// Gyroscope stream provider
/// Streams raw gyroscope data at configured sampling rate
@riverpod
Stream<GyroscopeData> gyroscopeStream(
  GyroscopeStreamRef ref,
) async* {
  // Convert Hz to Duration for sampling period
  final samplingPeriod = Duration(
    microseconds: (1000000 / AppConstants.sensorSamplingRate).round(),
  );

  yield* gyroscopeEventStream(samplingPeriod: samplingPeriod)
      .map((event) => GyroscopeData.fromEvent(event));
}

/// Combined motion data stream provider
/// Combines accelerometer and gyroscope into single stream
@riverpod
Stream<MotionData> motionDataStream(
  MotionDataStreamRef ref,
) async* {
  // Watch both sensor streams
  final accelStream = ref.watch(accelerometerStreamProvider.stream);
  final gyroStream = ref.watch(gyroscopeStreamProvider.stream);

  // Combine the streams
  // Note: This is a simplified combination - both streams emit at similar rates
  AccelerometerData? lastAccel;
  GyroscopeData? lastGyro;

  await for (final accelOrGyro in _mergeStreams(accelStream, gyroStream)) {
    if (accelOrGyro is AccelerometerData) {
      lastAccel = accelOrGyro;
    } else if (accelOrGyro is GyroscopeData) {
      lastGyro = accelOrGyro;
    }

    // Yield combined data when both sensors have data
    if (lastAccel != null && lastGyro != null) {
      yield MotionData(
        accelerometer: lastAccel,
        gyroscope: lastGyro,
        timestamp: DateTime.now(),
      );
    }
  }
}

/// Helper to merge two streams
Stream<dynamic> _mergeStreams(
  Stream<AccelerometerData> stream1,
  Stream<GyroscopeData> stream2,
) async* {
  final controller = StreamController<dynamic>();

  final sub1 = stream1.listen(controller.add);
  final sub2 = stream2.listen(controller.add);

  try {
    yield* controller.stream;
  } finally {
    await sub1.cancel();
    await sub2.cancel();
    await controller.close();
  }
}

@riverpod
class SensorService extends _$SensorService {
  @override
  Future<bool> build() async {
    // Check if sensors are available
    return await _checkSensorAvailability();
  }

  /// Check if accelerometer and gyroscope are available
  Future<bool> _checkSensorAvailability() async {
    try {
      // Try to get a single reading from each sensor
      await accelerometerEventStream()
          .timeout(const Duration(seconds: 2))
          .first;
      await gyroscopeEventStream()
          .timeout(const Duration(seconds: 2))
          .first;
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Test if sensors are responding
  Future<bool> areSensorsWorking() async {
    return await _checkSensorAvailability();
  }
}
```

### Step 3: Create Motion Detection Service

**File**: `lib/features/trip_detection/data/services/motion_detection_service.dart`

```dart
import 'dart:async';
import 'dart:collection';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../domain/models/motion_data.dart';
import 'sensor_service.dart';
import '../../../../core/constants/app_constants.dart';

part 'motion_detection_service.g.dart';

@riverpod
class MotionDetectionService extends _$MotionDetectionService {
  // Sliding window buffer for pattern analysis
  final Queue<MotionData> _buffer = Queue<MotionData>();
  Timer? _analysisTimer;

  @override
  Stream<MotionState> build() async* {
    // Listen to motion data stream
    final motionStream = ref.watch(motionDataStreamProvider.stream);

    await for (final motionData in motionStream) {
      // Add to buffer
      _addToBuffer(motionData);

      // Periodically analyze buffer (every 1 second)
      if (_buffer.length >= 50) { // ~1 second at 50Hz
        final state = _analyzeBuffer();
        yield state;
      }
    }
  }

  /// Add motion data to sliding window buffer
  void _addToBuffer(MotionData data) {
    _buffer.add(data);

    // Maintain buffer size limit (60 seconds at 50Hz = 3000 samples)
    while (_buffer.length > AppConstants.sensorBufferSize) {
      _buffer.removeFirst();
    }
  }

  /// Analyze buffer to determine motion state
  MotionState _analyzeBuffer() {
    if (_buffer.isEmpty) return MotionState.unknown;

    // Create motion window from recent samples
    final samples = _buffer.toList();
    final window = MotionWindow(
      samples: samples,
      startTime: samples.first.timestamp,
      endTime: samples.last.timestamp,
    );

    return window.state;
  }

  /// Get current motion window for analysis
  MotionWindow? getCurrentWindow() {
    if (_buffer.isEmpty) return null;

    final samples = _buffer.toList();
    return MotionWindow(
      samples: samples,
      startTime: samples.first.timestamp,
      endTime: samples.last.timestamp,
    );
  }

  /// Clear buffer (useful when stopping detection)
  void clearBuffer() {
    _buffer.clear();
  }

  /// Check if currently moving (any movement detected)
  Future<bool> isMoving() async {
    final window = getCurrentWindow();
    if (window == null) return false;

    return window.state != MotionState.stationary;
  }

  /// Check if potentially cycling (preliminary detection)
  Future<bool> isPotentiallyCycling() async {
    final window = getCurrentWindow();
    if (window == null) return false;

    return window.state == MotionState.cycling;
  }
}

/// Provider for current motion state (latest value)
@riverpod
Stream<MotionState> currentMotionState(CurrentMotionStateRef ref) {
  return ref.watch(motionDetectionServiceProvider.stream);
}
```

### Step 4: Create Sensor Utilities

**File**: `lib/features/trip_detection/data/services/sensor_utils.dart`

```dart
import 'dart:math';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../domain/models/motion_data.dart';

part 'sensor_utils.g.dart';

/// Utility class for sensor data processing
class SensorUtils {
  SensorUtils._(); // Prevent instantiation

  /// Calculate magnitude from 3D vector
  static double magnitude(double x, double y, double z) {
    return sqrt(x * x + y * y + z * z);
  }

  /// Apply low-pass filter to smooth sensor data
  /// alpha: smoothing factor (0-1), lower = more smoothing
  static double lowPassFilter(double current, double previous, double alpha) {
    return alpha * current + (1 - alpha) * previous;
  }

  /// Detect peaks in sensor data (for pattern recognition)
  /// Returns true if value is a local maximum
  static bool isPeak(
    List<double> values,
    int index, {
    double threshold = 0.0,
  }) {
    if (index <= 0 || index >= values.length - 1) return false;

    final current = values[index];
    final prev = values[index - 1];
    final next = values[index + 1];

    return current > prev &&
        current > next &&
        current > threshold;
  }

  /// Calculate standard deviation of values
  static double standardDeviation(List<double> values) {
    if (values.isEmpty) return 0.0;

    final mean = values.reduce((a, b) => a + b) / values.length;
    final variance = values
        .map((x) => pow(x - mean, 2))
        .reduce((a, b) => a + b) / values.length;

    return sqrt(variance);
  }

  /// Downsample data by taking every nth sample
  static List<T> downsample<T>(List<T> data, int factor) {
    if (factor <= 1) return data;
    return [
      for (var i = 0; i < data.length; i += factor) data[i]
    ];
  }
}

/// Provider for sensor data statistics
@riverpod
class SensorStatistics extends _$SensorStatistics {
  @override
  Map<String, double> build() {
    return {
      'avgAcceleration': 0.0,
      'avgRotation': 0.0,
      'stdDevAcceleration': 0.0,
      'stdDevRotation': 0.0,
    };
  }

  /// Calculate statistics from motion window
  void updateStatistics(MotionWindow window) {
    if (window.samples.isEmpty) return;

    final accelValues = window.samples
        .map((s) => s.accelerometer.magnitude)
        .toList();
    final gyroValues = window.samples
        .map((s) => s.gyroscope.magnitude)
        .toList();

    state = {
      'avgAcceleration': window.averageAcceleration,
      'avgRotation': window.averageRotation,
      'stdDevAcceleration': SensorUtils.standardDeviation(accelValues),
      'stdDevRotation': SensorUtils.standardDeviation(gyroValues),
    };
  }
}
```

### Step 5: Run Code Generation

Generate the required files:

```bash
flutter pub run build_runner build --delete-conflicting-outputs
```

Or start the watcher for continuous generation:

```bash
flutter pub run build_runner watch
```

### Step 6: Create Unit Tests

**File**: `test/features/trip_detection/data/services/sensor_service_test.dart`

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:autoride/features/trip_detection/domain/models/motion_data.dart';
import 'package:autoride/features/trip_detection/data/services/sensor_utils.dart';

void main() {
  group('AccelerometerData', () {
    test('should calculate magnitude correctly', () {
      // Arrange
      final data = AccelerometerData(
        x: 3.0,
        y: 4.0,
        z: 0.0,
        timestamp: DateTime.now(),
      );

      // Act & Assert
      expect(data.magnitude, equals(5.0)); // sqrt(9 + 16 + 0) = 5
    });

    test('should detect stationary state', () {
      // Arrange - device at rest, only gravity
      final data = AccelerometerData(
        x: 0.0,
        y: 0.0,
        z: 9.8, // Standard gravity
        timestamp: DateTime.now(),
      );

      // Act & Assert
      expect(data.isStationary(), isTrue);
    });

    test('should detect significant movement', () {
      // Arrange - device with acceleration beyond gravity
      final data = AccelerometerData(
        x: 5.0,
        y: 5.0,
        z: 9.8,
        timestamp: DateTime.now(),
      );

      // Act & Assert
      expect(data.hasSignificantMovement(), isTrue);
    });
  });

  group('GyroscopeData', () {
    test('should calculate rotation magnitude correctly', () {
      // Arrange
      final data = GyroscopeData(
        x: 0.0,
        y: 3.0,
        z: 4.0,
        timestamp: DateTime.now(),
      );

      // Act & Assert
      expect(data.magnitude, equals(5.0)); // sqrt(0 + 9 + 16) = 5
    });

    test('should detect rotation', () {
      // Arrange
      final data = GyroscopeData(
        x: 1.0,
        y: 1.0,
        z: 1.0,
        timestamp: DateTime.now(),
      );

      // Act & Assert
      expect(data.hasRotation(), isTrue);
    });
  });

  group('MotionData', () {
    test('should detect stationary state', () {
      // Arrange
      final accel = AccelerometerData(
        x: 0.0,
        y: 0.0,
        z: 9.8,
        timestamp: DateTime.now(),
      );
      final gyro = GyroscopeData(
        x: 0.0,
        y: 0.0,
        z: 0.0,
        timestamp: DateTime.now(),
      );
      final motion = MotionData(
        accelerometer: accel,
        gyroscope: gyro,
        timestamp: DateTime.now(),
      );

      // Act & Assert
      expect(motion.isStationary, isTrue);
    });

    test('should detect cycling indication', () {
      // Arrange - movement + rotation
      final accel = AccelerometerData(
        x: 5.0,
        y: 5.0,
        z: 9.8,
        timestamp: DateTime.now(),
      );
      final gyro = GyroscopeData(
        x: 1.0,
        y: 1.0,
        z: 0.5,
        timestamp: DateTime.now(),
      );
      final motion = MotionData(
        accelerometer: accel,
        gyroscope: gyro,
        timestamp: DateTime.now(),
      );

      // Act & Assert
      expect(motion.indicatesCycling, isTrue);
    });
  });

  group('MotionWindow', () {
    test('should calculate average acceleration', () {
      // Arrange
      final samples = List.generate(10, (i) {
        return MotionData(
          accelerometer: AccelerometerData(
            x: 0.0,
            y: 0.0,
            z: 10.0 + i, // Varying acceleration
            timestamp: DateTime.now(),
          ),
          gyroscope: GyroscopeData(
            x: 0.0,
            y: 0.0,
            z: 0.0,
            timestamp: DateTime.now(),
          ),
          timestamp: DateTime.now(),
        );
      });

      final window = MotionWindow(
        samples: samples,
        startTime: DateTime.now().subtract(Duration(seconds: 1)),
        endTime: DateTime.now(),
      );

      // Act
      final avg = window.averageAcceleration;

      // Assert - average should be around middle of range
      expect(avg, greaterThan(10.0));
      expect(avg, lessThan(20.0));
    });

    test('should determine motion state from samples', () {
      // Arrange - cycling-like motion
      final samples = List.generate(100, (i) {
        return MotionData(
          accelerometer: AccelerometerData(
            x: 2.0,
            y: 2.0,
            z: 10.0,
            timestamp: DateTime.now(),
          ),
          gyroscope: GyroscopeData(
            x: 1.0,
            y: 0.5,
            z: 0.5,
            timestamp: DateTime.now(),
          ),
          timestamp: DateTime.now(),
        );
      });

      final window = MotionWindow(
        samples: samples,
        startTime: DateTime.now().subtract(Duration(seconds: 2)),
        endTime: DateTime.now(),
      );

      // Act
      final state = window.state;

      // Assert
      expect(state, equals(MotionState.cycling));
    });
  });

  group('SensorUtils', () {
    test('should calculate magnitude from 3D vector', () {
      // Act & Assert
      expect(SensorUtils.magnitude(3.0, 4.0, 0.0), equals(5.0));
      expect(SensorUtils.magnitude(0.0, 0.0, 0.0), equals(0.0));
    });

    test('should apply low-pass filter', () {
      // Act - apply filter with alpha = 0.5
      final filtered = SensorUtils.lowPassFilter(10.0, 0.0, 0.5);

      // Assert - should be halfway between current and previous
      expect(filtered, equals(5.0));
    });

    test('should detect peaks in data', () {
      // Arrange
      final values = [1.0, 2.0, 5.0, 3.0, 1.0]; // Peak at index 2

      // Act & Assert
      expect(SensorUtils.isPeak(values, 2), isTrue);
      expect(SensorUtils.isPeak(values, 1), isFalse);
    });

    test('should calculate standard deviation', () {
      // Arrange
      final values = [2.0, 4.0, 4.0, 4.0, 5.0, 5.0, 7.0, 9.0];

      // Act
      final stdDev = SensorUtils.standardDeviation(values);

      // Assert - should be around 2.0 for this dataset
      expect(stdDev, greaterThan(1.5));
      expect(stdDev, lessThan(2.5));
    });

    test('should downsample data correctly', () {
      // Arrange
      final data = List.generate(100, (i) => i);

      // Act - downsample by factor of 10
      final downsampled = SensorUtils.downsample(data, 10);

      // Assert
      expect(downsampled.length, equals(10));
      expect(downsampled.first, equals(0));
      expect(downsampled.last, equals(90));
    });
  });
}
```

## Testing

### Manual Testing Checklist

**Critical: Test on Physical Devices Only** (sensors don't work in emulators)

#### Android Testing

1. **Sensor Availability**:
   - [ ] Install app on physical Android device
   - [ ] Verify accelerometer and gyroscope are detected
   - [ ] Check sensor data streams are working

2. **Stationary Detection**:
   - [ ] Place device on table
   - [ ] Verify motion state shows "stationary"
   - [ ] Check acceleration magnitude ~9.8 m/s² (gravity only)

3. **Movement Detection**:
   - [ ] Pick up device and shake gently
   - [ ] Verify motion state changes to "moving"
   - [ ] Check acceleration increases above threshold

4. **Rotation Detection**:
   - [ ] Rotate device in hand
   - [ ] Verify gyroscope detects rotation
   - [ ] Check rotation magnitude > 0.5 rad/s

5. **Cycling Simulation**:
   - [ ] Simulate cycling motion (arm swinging while walking)
   - [ ] Verify preliminary cycling detection works
   - [ ] Note: Full cycling detection comes in T008

6. **Battery Usage**:
   - [ ] Run sensor service for 1 hour
   - [ ] Check battery drain (should be <1% per hour)
   - [ ] Monitor with Android Battery Profiler

#### iOS Testing

1. **Sensor Availability**:
   - [ ] Install app on physical iOS device
   - [ ] Verify sensors work without special permissions
   - [ ] Check data quality and sampling rate

2. **Motion Detection**:
   - [ ] Test same scenarios as Android
   - [ ] Verify consistent behavior across platforms

3. **Battery Usage**:
   - [ ] Monitor energy impact in Xcode
   - [ ] Should show "Low" energy impact

### Automated Testing

Run unit tests:

```bash
flutter test test/features/trip_detection/data/services/sensor_service_test.dart
```

### Battery Profiling

**Android**:
```bash
# Run app in release mode
flutter run --release

# Monitor with Android Studio:
# 1. View → Tool Windows → Profiler
# 2. Select device and app
# 3. Energy profiler
# 4. Run sensors for 30 minutes
# 5. Verify <1% battery drain per hour
```

**iOS**:
```bash
# Run app in release mode
flutter run --release

# Monitor with Xcode:
# 1. Window → Devices and Simulators
# 2. Select device
# 3. View Device Logs → Energy
# 4. Should show "Low" impact
```

## Acceptance Criteria

- [ ] MotionData models created with freezed (AccelerometerData, GyroscopeData, MotionData)
- [ ] MotionWindow model for pattern analysis
- [ ] SensorService provider streams accelerometer and gyroscope data
- [ ] MotionDetectionService implements basic movement detection
- [ ] Sliding window buffer maintains last 60 seconds of data
- [ ] Motion state detection (stationary, moving, cycling) works
- [ ] SensorUtils provides data processing functions
- [ ] Code generation files created (.g.dart, .freezed.dart)
- [ ] Unit tests pass with >80% coverage
- [ ] Manual testing on physical devices successful
- [ ] Battery usage <1% per hour background
- [ ] Flutter analyze passes with no errors
- [ ] Sensor sampling rate follows AppConstants (50 Hz)

## Common Pitfalls

### 1. Testing on Emulators
**Problem**: Emulators don't have real sensors, simulated data is unreliable.

**Solution**: Always test on physical devices. For emulator testing, mock sensor streams.

### 2. Excessive Sampling Rate
**Problem**: Sampling at 100+ Hz drains battery quickly.

**Solution**: Use AppConstants.sensorSamplingRate (50 Hz) - optimal for cycling detection with good battery life.

### 3. Buffer Memory Leak
**Problem**: Unbounded buffer grows infinitely, consuming memory.

**Solution**: Maintain buffer size limit (AppConstants.sensorBufferSize = 3000 samples).

```dart
// ✅ Right - bounded buffer
while (_buffer.length > AppConstants.sensorBufferSize) {
  _buffer.removeFirst();
}

// ❌ Wrong - unbounded buffer
_buffer.add(data); // Never removes old data
```

### 4. Synchronization Issues
**Problem**: Accelerometer and gyroscope streams not aligned in time.

**Solution**: Use stream merging with latest values from both sensors.

### 5. Sensor Coordinate System Confusion
**Problem**: Different devices have different sensor orientations.

**Solution**: Use magnitude calculations instead of raw x, y, z values for detection.

### 6. Battery Drain from Continuous Processing
**Problem**: Processing every sensor sample in real-time.

**Solution**: Batch process samples periodically (every 1 second) instead of real-time.

## Resources

### Official Documentation
- [sensors_plus Package](https://pub.dev/packages/sensors_plus)
- [Android Sensor Documentation](https://developer.android.com/guide/topics/sensors/sensors_overview)
- [iOS Core Motion](https://developer.apple.com/documentation/coremotion)

### Sensor Concepts
- [Accelerometer Basics](https://developer.android.com/guide/topics/sensors/sensors_motion#sensors-motion-accel)
- [Gyroscope Basics](https://developer.android.com/guide/topics/sensors/sensors_motion#sensors-motion-gyro)
- [Motion Detection Algorithms](https://www.sciencedirect.com/topics/computer-science/motion-detection-algorithm)

### Human Activity Recognition
- [HAR with Smartphone Sensors](https://link.springer.com/article/10.1007/s12243-023-00962-x)
- [Cycling Detection Patterns](https://www.mdpi.com/1424-8220/20/11/3208)

### Related Tasks
- **Previous**: T003 - Riverpod Code Generation Setup
- **Next**: T008 - Cycling Motion Pattern Detection (depends on T007)
- **Related**: T006 - Battery-Optimized Location Strategy (will use T007 for motion-gated GPS)

## Next Steps

After completing T007, you'll be ready for:

1. **T008**: Cycling Motion Pattern Detection
   - Advanced pattern recognition for cycling
   - Pedaling frequency detection
   - Distinguish cycling from other activities

2. **T006**: Battery-Optimized Location Strategy
   - Use motion detection to gate GPS activation
   - Only turn on GPS when movement is detected
   - Adaptive location accuracy based on motion intensity

## Notes

- **Physical Device Testing is Mandatory**: Sensors don't work properly in emulators
- **Battery Efficiency is Critical**: Users will uninstall if battery drain is excessive
- **This is Foundation for T008**: Keep detection logic simple here, refinement comes in T008
- **Sampling Rate Balance**: 50 Hz is sweet spot for cycling detection vs battery life
- **Buffer Management**: Critical for memory efficiency and performance
- **Stream Combination**: Accelerometer + Gyroscope provides better detection than either alone

## Implementation Tips

1. **Start Simple**: Get basic sensor data flowing first, add complexity later
2. **Test Continuously**: Run on device frequently during development
3. **Monitor Battery**: Profile early and often to catch battery drain
4. **Debug Logging**: Add logging to understand sensor data patterns
5. **Document Observations**: Note any platform-specific behaviors

---

**Created**: 2025-11-22
**Status**: Ready for implementation
**Assigned**: Current session
