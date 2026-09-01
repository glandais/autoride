import 'package:flutter_test/flutter_test.dart';
import 'package:autoride/features/trip_detection/data/services/sensor_utils.dart';

/// Moved out of `sensor_service_test.dart`, which was named for a service it
/// never imported (L-026).
void main() {
  group('SensorUtils', () {
    test('should calculate magnitude from 3D vector', () {
      expect(SensorUtils.magnitude(3.0, 4.0, 0.0), equals(5.0));
      expect(SensorUtils.magnitude(0.0, 0.0, 0.0), equals(0.0));
    });

    test('should apply low-pass filter', () {
      final filtered = SensorUtils.lowPassFilter(10.0, 0.0, 0.5);

      expect(filtered, equals(5.0));
    });

    test('should detect peaks in data', () {
      final values = [1.0, 2.0, 5.0, 3.0, 1.0]; // Peak at index 2

      expect(SensorUtils.isPeak(values, 2), isTrue);
      expect(SensorUtils.isPeak(values, 1), isFalse);
    });

    test('isPeak honours the amplitude threshold', () {
      final values = [1.0, 2.0, 5.0, 3.0, 1.0];

      expect(SensorUtils.isPeak(values, 2, threshold: 4.0), isTrue);
      expect(SensorUtils.isPeak(values, 2, threshold: 10.0), isFalse);
    });

    test('isPeak rejects the boundary indices', () {
      final values = [9.0, 1.0, 9.0];

      expect(SensorUtils.isPeak(values, 0), isFalse);
      expect(SensorUtils.isPeak(values, 2), isFalse);
    });

    test('should calculate standard deviation', () {
      final values = [2.0, 4.0, 4.0, 4.0, 5.0, 5.0, 7.0, 9.0];

      final stdDev = SensorUtils.standardDeviation(values);

      expect(stdDev, greaterThan(1.5));
      expect(stdDev, lessThan(2.5));
    });

    test('should downsample data correctly', () {
      final data = List.generate(100, (i) => i);

      final downsampled = SensorUtils.downsample(data, 10);

      expect(downsampled.length, equals(10));
      expect(downsampled.first, equals(0));
      expect(downsampled.last, equals(90));
    });
  });
}
