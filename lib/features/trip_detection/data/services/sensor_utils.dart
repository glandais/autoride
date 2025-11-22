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
