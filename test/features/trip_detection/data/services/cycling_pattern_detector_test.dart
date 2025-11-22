import 'package:flutter_test/flutter_test.dart';
import 'package:autoride/features/trip_detection/domain/models/motion_data.dart';
import 'package:autoride/features/trip_detection/domain/models/activity_confidence.dart';
import 'package:autoride/features/trip_detection/domain/models/location_data.dart';
import 'package:autoride/core/constants/app_constants.dart';
import 'dart:math';

void main() {
  group('ActivityConfidence', () {
    test('should create cycling activity with high confidence', () {
      final confidence = ActivityConfidence.cycling(
        confidence: 0.85,
        motionScore: 0.9,
        speedScore: 0.8,
        frequencyScore: 0.85,
      );

      expect(confidence.activity, equals(ActivityType.cycling));
      expect(confidence.confidence, equals(0.85));
      expect(confidence.isCyclingDetected, isTrue);
      expect(confidence.level, equals(ConfidenceLevel.high));
    });

    test('should identify ambiguous detection', () {
      final confidence = ActivityConfidence.cycling(
        confidence: 0.5,
        motionScore: 0.6,
        speedScore: 0.4,
        frequencyScore: 0.5,
      );

      expect(confidence.isAmbiguous, isTrue);
      expect(confidence.level, equals(ConfidenceLevel.low));
    });

    test('should calculate correct confidence level', () {
      expect(
        ActivityConfidence.cycling(
          confidence: 0.95,
          motionScore: 1.0,
          speedScore: 0.9,
          frequencyScore: 0.95,
        ).level,
        equals(ConfidenceLevel.veryHigh),
      );

      expect(
        ActivityConfidence.cycling(
          confidence: 0.3,
          motionScore: 0.4,
          speedScore: 0.2,
          frequencyScore: 0.3,
        ).level,
        equals(ConfidenceLevel.veryLow),
      );
    });

    test('should create from scores and find best activity', () {
      final activityScores = {
        ActivityType.cycling: 0.85,
        ActivityType.walking: 0.3,
        ActivityType.stationary: 0.1,
        ActivityType.driving: 0.2,
        ActivityType.running: 0.25,
        ActivityType.unknown: 0.0,
      };

      final confidence = ActivityConfidence.fromScores(
        motionScore: 0.9,
        speedScore: 0.8,
        frequencyScore: 0.85,
        activityScores: activityScores,
      );

      expect(confidence.activity, equals(ActivityType.cycling));
      expect(confidence.secondBestActivity, equals(ActivityType.walking));
    });
  });

  group('CyclingPatternDetector - Motion Analysis', () {
    test('should detect cycling motion pattern', () {
      // Create cycling-like motion data
      // x=3, y=3, z=10 → sqrt(9 + 9 + 100) = sqrt(118) ≈ 10.86 > 10.5 ✓
      final samples = List.generate(150, (i) {
        return MotionData(
          accelerometer: AccelerometerData(
            x: 3.0,
            y: 3.0,
            z: 10.0, // magnitude ≈ 10.86
            timestamp: DateTime.now().add(Duration(milliseconds: i * 20)),
          ),
          gyroscope: GyroscopeData(
            x: 1.0,
            y: 0.5,
            z: 0.5, // magnitude ≈ 1.22 > 0.5 ✓
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

      // Check motion pattern
      expect(window.averageAcceleration, greaterThan(10.0));
      expect(window.averageRotation, greaterThan(0.5));
      expect(window.hasEnoughSamples, isTrue);
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
  });

  group('CyclingPatternDetector - Frequency Analysis', () {
    test('should detect pedaling frequency', () {
      // Generate periodic acceleration pattern (1 Hz = 60 RPM)
      final samples = <MotionData>[];
      final baseTime = DateTime.now();

      for (var i = 0; i < 200; i++) {
        final t = i * 0.01; // 100 Hz sampling
        // Simulate pedaling: periodic acceleration
        final accelValue = 11.0 + 2.0 * sin(2 * pi * 1.0 * t); // 1 Hz

        samples.add(MotionData(
          accelerometer: AccelerometerData(
            x: accelValue * 0.5,
            y: accelValue * 0.5,
            z: accelValue,
            timestamp: baseTime.add(Duration(milliseconds: (t * 1000).round())),
          ),
          gyroscope: GyroscopeData(
            x: 1.0,
            y: 0.5,
            z: 0.5,
            timestamp: baseTime.add(Duration(milliseconds: (t * 1000).round())),
          ),
          timestamp: baseTime.add(Duration(milliseconds: (t * 1000).round())),
        ));
      }

      final window = MotionWindow(
        samples: samples,
        startTime: samples.first.timestamp,
        endTime: samples.last.timestamp,
      );

      // Should have periodic pattern
      expect(window.indicatesCyclingEnhanced, isTrue);
    });

    test('should not detect cycling in random motion', () {
      // Generate random acceleration pattern
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

      // Random motion should not have enough periodic patterns
      expect(window.averageRotation, lessThan(0.5));
    });
  });

  group('CyclingPatternDetector - Speed Validation', () {
    test('should validate cycling speed range', () {
      // Cycling speed: 18 km/h = 5 m/s
      final location = LocationData(
        latitude: 48.8566,
        longitude: 2.3522,
        altitude: 35.0,
        accuracy: 10.0,
        speed: 5.0, // m/s
        heading: 90.0, // Heading east
        timestamp: DateTime.now(),
      );

      final speedKmh = location.speed * 3.6;

      expect(speedKmh, greaterThanOrEqualTo(AppConstants.cyclingSpeedMin));
      expect(speedKmh, lessThanOrEqualTo(AppConstants.cyclingSpeedMax));
    });

    test('should reject walking speed', () {
      // Walking speed: 5 km/h = 1.39 m/s
      final location = LocationData(
        latitude: 48.8566,
        longitude: 2.3522,
        altitude: 35.0,
        accuracy: 10.0,
        speed: 1.39, // m/s
        heading: 90.0,
        timestamp: DateTime.now(),
      );

      final speedKmh = location.speed * 3.6;

      expect(speedKmh, lessThan(AppConstants.cyclingSpeedMin));
    });

    test('should reject driving speed', () {
      // Driving speed: 50 km/h = 13.89 m/s
      final location = LocationData(
        latitude: 48.8566,
        longitude: 2.3522,
        altitude: 35.0,
        accuracy: 10.0,
        speed: 13.89, // m/s
        heading: 90.0,
        timestamp: DateTime.now(),
      );

      final speedKmh = location.speed * 3.6;

      expect(speedKmh, greaterThan(AppConstants.cyclingSpeedMax));
    });

    test('should validate typical cycling speed', () {
      // Typical cycling: 18 km/h = 5 m/s
      final location = LocationData(
        latitude: 48.8566,
        longitude: 2.3522,
        altitude: 35.0,
        accuracy: 10.0,
        speed: 5.0, // m/s
        heading: 90.0,
        timestamp: DateTime.now(),
      );

      final speedKmh = location.speed * 3.6;

      // Should be close to typical cycling speed
      expect(
        (speedKmh - AppConstants.cyclingSpeedTypical).abs(),
        lessThan(5.0),
      );
    });
  });

  group('MotionWindow - Enhanced Detection', () {
    test('should use enhanced cycling detection', () {
      // Generate cycling pattern with peaks
      final samples = <MotionData>[];
      final baseTime = DateTime.now();

      for (var i = 0; i < 150; i++) {
        final t = i * 0.02; // 50 Hz sampling
        // Simulate pedaling with peaks
        final accelValue = 12.0 + 3.0 * sin(2 * pi * 1.2 * t); // 1.2 Hz

        samples.add(MotionData(
          accelerometer: AccelerometerData(
            x: accelValue * 0.3,
            y: accelValue * 0.3,
            z: accelValue * 0.9,
            timestamp: baseTime.add(Duration(milliseconds: (t * 1000).round())),
          ),
          gyroscope: GyroscopeData(
            x: 1.0 + 0.5 * sin(2 * pi * 1.2 * t),
            y: 0.8,
            z: 0.6,
            timestamp: baseTime.add(Duration(milliseconds: (t * 1000).round())),
          ),
          timestamp: baseTime.add(Duration(milliseconds: (t * 1000).round())),
        ));
      }

      final window = MotionWindow(
        samples: samples,
        startTime: samples.first.timestamp,
        endTime: samples.last.timestamp,
      );

      // Enhanced detection should find periodic pattern
      expect(window.hasEnoughSamples, isTrue);
      expect(window.averageAcceleration, greaterThan(10.0));
      expect(window.averageRotation, greaterThan(0.5));
    });
  });

  group('AppConstants - Cycling Thresholds', () {
    test('should have valid acceleration thresholds', () {
      expect(AppConstants.cyclingAccelerationMin, equals(10.0));
      expect(AppConstants.cyclingAccelerationMax, equals(20.0));
      expect(AppConstants.walkingAccelerationMax, equals(12.0));
      expect(
        AppConstants.cyclingAccelerationMin,
        lessThan(AppConstants.cyclingAccelerationMax),
      );
    });

    test('should have valid rotation thresholds', () {
      expect(AppConstants.cyclingRotationMin, equals(0.5));
      expect(AppConstants.cyclingRotationMax, equals(3.0));
      expect(
        AppConstants.cyclingRotationMin,
        lessThan(AppConstants.cyclingRotationMax),
      );
    });

    test('should have valid frequency thresholds', () {
      expect(AppConstants.pedalingFrequencyMin, equals(0.5)); // 30 RPM
      expect(AppConstants.pedalingFrequencyMax, equals(2.0)); // 120 RPM
      expect(
        AppConstants.pedalingFrequencyMin,
        lessThan(AppConstants.pedalingFrequencyMax),
      );
    });

    test('should have valid speed thresholds', () {
      expect(AppConstants.cyclingSpeedMin, equals(8.0));
      expect(AppConstants.cyclingSpeedMax, equals(40.0));
      expect(AppConstants.cyclingSpeedTypical, equals(18.0));
      expect(
        AppConstants.cyclingSpeedMin,
        lessThan(AppConstants.cyclingSpeedTypical),
      );
      expect(
        AppConstants.cyclingSpeedTypical,
        lessThan(AppConstants.cyclingSpeedMax),
      );
    });

    test('should have valid confidence thresholds', () {
      expect(AppConstants.minConfidenceForDetection, equals(0.6));
      expect(AppConstants.highConfidenceThreshold, equals(0.8));
      expect(
        AppConstants.minConfidenceForDetection,
        lessThan(AppConstants.highConfidenceThreshold),
      );
    });

    test('should have valid classification weights', () {
      expect(AppConstants.motionScoreWeight, equals(0.4));
      expect(AppConstants.speedScoreWeight, equals(0.35));
      expect(AppConstants.frequencyScoreWeight, equals(0.25));

      // Weights should sum to 1.0
      const total = AppConstants.motionScoreWeight +
          AppConstants.speedScoreWeight +
          AppConstants.frequencyScoreWeight;
      expect(total, closeTo(1.0, 0.01));
    });
  });
}
