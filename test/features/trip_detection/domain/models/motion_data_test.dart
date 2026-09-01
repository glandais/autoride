import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:autoride/features/trip_detection/domain/models/motion_data.dart';

/// Model tests for the sensor value objects.
///
/// These previously lived in `sensor_service_test.dart` and
/// `cycling_pattern_detector_test.dart`, neither of which exercised the service
/// they were named for (L-026 / L-011). They are kept here, under the name of
/// the unit they actually test.
void main() {
  group('AccelerometerData', () {
    test('should calculate magnitude correctly', () {
      final data = AccelerometerData(
        x: 3.0,
        y: 4.0,
        z: 0.0,
        timestamp: DateTime.now(),
      );

      expect(data.magnitude, equals(5.0)); // sqrt(9 + 16 + 0) = 5
    });

    test('should detect stationary state', () {
      final data = AccelerometerData(
        x: 0.0,
        y: 0.0,
        z: 9.8, // Standard gravity
        timestamp: DateTime.now(),
      );

      expect(data.isStationary(), isTrue);
    });

    test('should detect significant movement', () {
      final data = AccelerometerData(
        x: 5.0,
        y: 5.0,
        z: 9.8,
        timestamp: DateTime.now(),
      );

      expect(data.hasSignificantMovement(), isTrue);
    });
  });

  group('GyroscopeData', () {
    test('should calculate rotation magnitude correctly', () {
      final data = GyroscopeData(
        x: 0.0,
        y: 3.0,
        z: 4.0,
        timestamp: DateTime.now(),
      );

      expect(data.magnitude, equals(5.0)); // sqrt(0 + 9 + 16) = 5
    });

    test('should detect rotation', () {
      final data = GyroscopeData(
        x: 1.0,
        y: 1.0,
        z: 1.0,
        timestamp: DateTime.now(),
      );

      expect(data.hasRotation(), isTrue);
    });
  });

  group('MotionData', () {
    test('should detect stationary state', () {
      final motion = MotionData(
        accelerometer: AccelerometerData(
          x: 0.0,
          y: 0.0,
          z: 9.8,
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

      expect(motion.isStationary, isTrue);
    });

    test('should detect cycling indication', () {
      final motion = MotionData(
        accelerometer: AccelerometerData(
          x: 5.0,
          y: 5.0,
          z: 9.8,
          timestamp: DateTime.now(),
        ),
        gyroscope: GyroscopeData(
          x: 1.0,
          y: 1.0,
          z: 0.5,
          timestamp: DateTime.now(),
        ),
        timestamp: DateTime.now(),
      );

      expect(motion.indicatesCycling, isTrue);
    });
  });

  group('MotionWindow', () {
    test('should calculate average acceleration', () {
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

      final avg = window.averageAcceleration;

      expect(avg, greaterThan(10.0));
      expect(avg, lessThan(20.0));
    });

    test('should determine motion state from samples', () {
      // Need avgAccel > 10.5 and avgRotation > 0.5
      final samples = List.generate(100, (i) {
        return MotionData(
          accelerometer: AccelerometerData(
            x: 3.0,
            y: 3.0,
            z: 10.0, // magnitude = sqrt(9 + 9 + 100) ≈ 10.86
            timestamp: DateTime.now(),
          ),
          gyroscope: GyroscopeData(
            x: 1.0,
            y: 0.5,
            z: 0.5, // magnitude ≈ 1.22
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

      expect(window.state, equals(MotionState.cycling));
    });

    test('should detect stationary pattern', () {
      final samples = List.generate(150, (i) {
        return MotionData(
          accelerometer: AccelerometerData(
            x: 0.0,
            y: 0.0,
            z: 9.8, // Only gravity
            timestamp: DateTime.now().add(Duration(milliseconds: i * 20)),
          ),
          gyroscope: GyroscopeData(
            x: 0.0,
            y: 0.0,
            z: 0.0,
            timestamp: DateTime.now().add(Duration(milliseconds: i * 20)),
          ),
          timestamp: DateTime.now().add(Duration(milliseconds: i * 20)),
        );
      });

      final window = MotionWindow(
        samples: samples,
        startTime: samples.first.timestamp,
        endTime: samples.last.timestamp,
      );

      expect(window.averageAcceleration, lessThan(10.0));
      expect(window.averageRotation, lessThan(0.3));
      expect(window.state, equals(MotionState.stationary));
    });

    test('indicatesCyclingEnhanced accepts a periodic pedaling pattern', () {
      final samples = <MotionData>[];
      final baseTime = DateTime.now();

      for (var i = 0; i < 200; i++) {
        final t = i * 0.01; // 100 Hz sampling
        final accelValue = 11.0 + 2.0 * sin(2 * pi * 1.0 * t); // 1 Hz
        final stamp = baseTime.add(Duration(milliseconds: (t * 1000).round()));

        samples.add(
          MotionData(
            accelerometer: AccelerometerData(
              x: accelValue * 0.5,
              y: accelValue * 0.5,
              z: accelValue,
              timestamp: stamp,
            ),
            gyroscope: GyroscopeData(x: 1.0, y: 0.5, z: 0.5, timestamp: stamp),
            timestamp: stamp,
          ),
        );
      }

      final window = MotionWindow(
        samples: samples,
        startTime: samples.first.timestamp,
        endTime: samples.last.timestamp,
      );

      expect(window.indicatesCyclingEnhanced, isTrue);
    });

    test('random motion does not look like pedaling', () {
      final samples = List.generate(150, (i) {
        final random = Random(i); // Seeded for consistency
        return MotionData(
          accelerometer: AccelerometerData(
            x: random.nextDouble() * 2,
            y: random.nextDouble() * 2,
            z: 9.0 + random.nextDouble() * 2,
            timestamp: DateTime.now().add(Duration(milliseconds: i * 20)),
          ),
          gyroscope: GyroscopeData(
            x: random.nextDouble() * 0.5,
            y: random.nextDouble() * 0.5,
            z: random.nextDouble() * 0.5,
            timestamp: DateTime.now().add(Duration(milliseconds: i * 20)),
          ),
          timestamp: DateTime.now().add(Duration(milliseconds: i * 20)),
        );
      });

      final window = MotionWindow(
        samples: samples,
        startTime: samples.first.timestamp,
        endTime: samples.last.timestamp,
      );

      expect(window.averageRotation, lessThan(0.5));
      expect(window.indicatesCyclingEnhanced, isFalse);
    });

    test('hasEnoughSamples follows AppConstants.pedalingCycleSamples', () {
      MotionWindow windowOf(int count) {
        final samples = List.generate(
          count,
          (i) => MotionData(
            accelerometer: AccelerometerData(
              x: 0.0,
              y: 0.0,
              z: 12.0,
              timestamp: DateTime.now(),
            ),
            gyroscope: GyroscopeData(
              x: 1.0,
              y: 0.0,
              z: 0.0,
              timestamp: DateTime.now(),
            ),
            timestamp: DateTime.now(),
          ),
        );
        return MotionWindow(
          samples: samples,
          startTime: DateTime.now(),
          endTime: DateTime.now(),
        );
      }

      expect(windowOf(49).hasEnoughSamples, isFalse);
      expect(windowOf(50).hasEnoughSamples, isTrue);
    });
  });
}
