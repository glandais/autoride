import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:autoride/features/trip_detection/domain/models/motion_data.dart';
import 'package:autoride/features/trip_detection/data/services/sensor_service.dart';
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
        startTime: DateTime.now().subtract(const Duration(seconds: 1)),
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
      // Need avgAccel > 10.5 and avgRotation > 0.5
      final samples = List.generate(100, (i) {
        return MotionData(
          accelerometer: AccelerometerData(
            x: 3.0,
            y: 3.0,
            z: 10.0, // magnitude = sqrt(9 + 9 + 100) = sqrt(118) ≈ 10.86
            timestamp: DateTime.now(),
          ),
          gyroscope: GyroscopeData(
            x: 1.0,
            y: 0.5,
            z: 0.5, // magnitude = sqrt(1 + 0.25 + 0.25) ≈ 1.22
            timestamp: DateTime.now(),
          ),
          timestamp: DateTime.now(),
        );
      });

      final window = MotionWindow(
        samples: samples,
        startTime: DateTime.now().subtract(const Duration(seconds: 2)),
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

  // ---------------------------------------------------------------------------
  // motionDataStream now merges the accelerometer and gyroscope PROVIDERS
  // (T041 / audit #5), so the merge itself is testable and each sensor is
  // subscribed to exactly once instead of once per consumer.
  // ---------------------------------------------------------------------------
  group('motionDataStream merge', () {
    late StreamController<AccelerometerData> accelController;
    late StreamController<GyroscopeData> gyroController;
    late ProviderContainer container;

    setUp(() {
      accelController = StreamController<AccelerometerData>.broadcast();
      gyroController = StreamController<GyroscopeData>.broadcast();
      container = ProviderContainer(
        overrides: [
          accelerometerStreamProvider
              .overrideWith((ref) => accelController.stream),
          gyroscopeStreamProvider.overrideWith((ref) => gyroController.stream),
        ],
      );
    });

    tearDown(() async {
      container.dispose();
      await accelController.close();
      await gyroController.close();
    });

    test('emits nothing until both sensors have produced a sample', () async {
      final emitted = <MotionData>[];
      container.listen(motionDataStreamProvider, (previous, next) {
        next.whenData(emitted.add);
      });
      await pumpEventQueue();

      accelController.add(AccelerometerData(
          x: 3.0, y: 3.0, z: 10.0, timestamp: DateTime(2026)));
      await pumpEventQueue();
      expect(emitted, isEmpty);

      gyroController.add(
          GyroscopeData(x: 1.0, y: 0.5, z: 0.5, timestamp: DateTime(2026)));
      await pumpEventQueue();

      expect(emitted, hasLength(1));
      expect(emitted.single.accelerometer.z, 10.0);
      expect(emitted.single.gyroscope.x, 1.0);
    });

    test('forwards sensor errors to the merged stream', () async {
      container.listen(motionDataStreamProvider, (_, _) {});
      await pumpEventQueue();

      accelController.addError(StateError('accelerometer failure'));
      await pumpEventQueue();

      expect(container.read(motionDataStreamProvider).hasError, isTrue);
    });
  });
}
