import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'dart:math';

part 'motion_data.freezed.dart';

/// Accelerometer data model
@freezed
sealed class AccelerometerData with _$AccelerometerData {
  const AccelerometerData._();

  const factory AccelerometerData({
    required double x,
    required double y,
    required double z,
    required DateTime timestamp,
  }) = _AccelerometerData;

  factory AccelerometerData.fromEvent(AccelerometerEvent event) {
    return AccelerometerData(
      x: event.x,
      y: event.y,
      z: event.z,
      timestamp: DateTime.now(),
    );
  }
}

/// Extension methods for AccelerometerData
extension AccelerometerDataExtensions on AccelerometerData {
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
sealed class GyroscopeData with _$GyroscopeData {
  const GyroscopeData._();

  const factory GyroscopeData({
    required double x,
    required double y,
    required double z,
    required DateTime timestamp,
  }) = _GyroscopeData;

  factory GyroscopeData.fromEvent(GyroscopeEvent event) {
    return GyroscopeData(
      x: event.x,
      y: event.y,
      z: event.z,
      timestamp: DateTime.now(),
    );
  }
}

/// Extension methods for GyroscopeData
extension GyroscopeDataExtensions on GyroscopeData {
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
sealed class MotionData with _$MotionData {
  const MotionData._();

  const factory MotionData({
    required AccelerometerData accelerometer,
    required GyroscopeData gyroscope,
    required DateTime timestamp,
  }) = _MotionData;
}

/// Extension methods for MotionData
extension MotionDataExtensions on MotionData {
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
sealed class MotionWindow with _$MotionWindow {
  const MotionWindow._();

  const factory MotionWindow({
    required List<MotionData> samples,
    required DateTime startTime,
    required DateTime endTime,
  }) = _MotionWindow;
}

/// Extension methods for MotionWindow
extension MotionWindowExtensions on MotionWindow {
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

  /// Analyze if pattern indicates cycling (enhanced)
  /// Uses multi-factor analysis for better accuracy (T008)
  bool get indicatesCyclingEnhanced {
    if (samples.isEmpty) return false;

    // Check minimum samples
    if (samples.length < 100) return false;

    // Basic thresholds
    final avgAccel = averageAcceleration;
    final avgRotation = averageRotation;

    // Must meet basic acceleration and rotation criteria
    if (avgAccel < 10.0 || avgRotation < 0.5) {
      return false;
    }

    // Check for periodic patterns (pedaling)
    final hasPeriodicPattern = _hasPeriodicAcceleration();

    return hasPeriodicPattern;
  }

  /// Check for periodic acceleration patterns (pedaling motion)
  bool _hasPeriodicAcceleration() {
    final magnitudes = samples
        .map((s) => s.accelerometer.magnitude)
        .toList();

    // Count peaks
    int peakCount = 0;
    for (var i = 1; i < magnitudes.length - 1; i++) {
      if (magnitudes[i] > magnitudes[i - 1] &&
          magnitudes[i] > magnitudes[i + 1] &&
          magnitudes[i] > 10.0) {
        peakCount++;
      }
    }

    // Expect at least 2-3 peaks in a window for cycling
    return peakCount >= 2;
  }
}
