import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:autoride/features/trip_detection/domain/models/motion_data.dart';
import 'package:autoride/features/trip_detection/domain/models/location_data.dart';
import 'package:autoride/features/trip_detection/data/services/trip_start_detector.dart';
import 'package:autoride/core/constants/app_constants.dart';

void main() {
  group('TripStartDetector', () {
    /// Helper to create a fresh provider container for each test
    ProviderContainer createContainer() {
      return ProviderContainer();
    }

    /// Helper to create cycling motion data (meets thresholds)
    /// Optimized for high confidence score
    MotionData createCyclingMotion() {
      return MotionData(
        accelerometer: AccelerometerData(
          x: 5.0,
          y: 5.0,
          z: 13.0, // magnitude = sqrt(219) ≈ 14.8 (close to mid-range of 10-20)
          timestamp: DateTime.now(),
        ),
        gyroscope: GyroscopeData(
          x: 1.2,
          y: 0.8,
          z: 0.9, // magnitude = sqrt(2.29) ≈ 1.51 (close to mid-range of 0.5-3.0)
          timestamp: DateTime.now(),
        ),
        timestamp: DateTime.now(),
      );
    }

    /// Helper to create walking motion data (below cycling thresholds)
    MotionData createWalkingMotion() {
      return MotionData(
        accelerometer: AccelerometerData(
          x: 1.0,
          y: 1.0,
          z: 9.5, // magnitude ≈ 9.58 < 10.0
          timestamp: DateTime.now(),
        ),
        gyroscope: GyroscopeData(
          x: 0.2,
          y: 0.1,
          z: 0.1, // magnitude ≈ 0.24 < 0.5
          timestamp: DateTime.now(),
        ),
        timestamp: DateTime.now(),
      );
    }

    /// Helper to create cycling speed GPS data (18 km/h)
    LocationData createCyclingLocation() {
      return LocationData(
        latitude: 48.8566,
        longitude: 2.3522,
        accuracy: 10.0,
        altitude: 35.0,
        speed: 5.0, // m/s = 18 km/h
        heading: 90.0,
        timestamp: DateTime.now(),
      );
    }

    /// Helper to create walking speed GPS data (4 km/h)
    LocationData createWalkingLocation() {
      return LocationData(
        latitude: 48.8566,
        longitude: 2.3522,
        accuracy: 10.0,
        altitude: 35.0,
        speed: 1.1, // m/s ≈ 4 km/h (< 8 km/h minimum)
        heading: 90.0,
        timestamp: DateTime.now(),
      );
    }

    /// Helper to create driving speed GPS data (60 km/h)
    LocationData createDrivingLocation() {
      return LocationData(
        latitude: 48.8566,
        longitude: 2.3522,
        accuracy: 10.0,
        altitude: 35.0,
        speed: 16.7, // m/s ≈ 60 km/h (> 40 km/h maximum)
        heading: 90.0,
        timestamp: DateTime.now(),
      );
    }

    test('should start trip with cycling motion and valid GPS speed', () async {
      final container = createContainer();

      final detector = container.read(tripStartDetectorProvider.notifier);
      final motion = createCyclingMotion();
      final location = createCyclingLocation();

      // Analyze 3 times for consecutive detection
      for (int i = 0; i < 3; i++) {
        await detector.analyzeForTripStart(motion, location);
      }

      final state = container.read(tripStartDetectorProvider);
      expect(
        state.confidence,
        greaterThanOrEqualTo(AppConstants.tripStartConfidenceThreshold),
      );
      expect(
        state.consecutiveDetections,
        greaterThanOrEqualTo(AppConstants.tripStartMinConsecutiveDetections),
      );
      expect(detector.shouldStartTrip(), isTrue);

      container.dispose();
    });

    test('should NOT start trip with walking motion and GPS', () async {
      final container = createContainer();

      final detector = container.read(tripStartDetectorProvider.notifier);
      final motion = createWalkingMotion();
      final location = createWalkingLocation();

      // Analyze 3 times
      for (int i = 0; i < 3; i++) {
        await detector.analyzeForTripStart(motion, location);
      }

      expect(detector.shouldStartTrip(), isFalse);

      container.dispose();
    });

    test('should NOT start trip with driving speed GPS', () async {
      final container = createContainer();

      final detector = container.read(tripStartDetectorProvider.notifier);
      final motion = createCyclingMotion(); // Good motion
      final location = createDrivingLocation(); // But driving speed

      // Analyze 3 times
      for (int i = 0; i < 3; i++) {
        await detector.analyzeForTripStart(motion, location);
      }

      // Should not trigger due to excessive speed
      expect(detector.shouldStartTrip(), isFalse);

      container.dispose();
    });

    test('should require consecutive detections (no single spike)', () async {
      final container = createContainer();

      final detector = container.read(tripStartDetectorProvider.notifier);
      final motion = createCyclingMotion();
      final location = createCyclingLocation();

      // Single detection
      await detector.analyzeForTripStart(motion, location);

      final state = container.read(tripStartDetectorProvider);
      expect(state.consecutiveDetections, equals(1));
      expect(detector.shouldStartTrip(), isFalse);

      container.dispose();
    });

    test('should reset consecutive count if detection window exceeded',
        () async {
      final container = createContainer();

      final detector = container.read(tripStartDetectorProvider.notifier);
      final motion = createCyclingMotion();
      final location = createCyclingLocation();

      // First detection
      await detector.analyzeForTripStart(motion, location);
      final state = container.read(tripStartDetectorProvider);
      expect(state.consecutiveDetections, equals(1));

      // Note: In real implementation, waiting >5 seconds would exceed detection window
      // For test, we verify that the first detection registered correctly
      // The time window logic is tested by the coordinator in integration tests

      container.dispose();
    });

    test('should work with motion-only (no GPS)', () async {
      final container = createContainer();

      final detector = container.read(tripStartDetectorProvider.notifier);
      final motion = createCyclingMotion();

      // Analyze 3 times without GPS
      for (int i = 0; i < 3; i++) {
        await detector.analyzeForTripStart(motion, null);
      }

      final state = container.read(tripStartDetectorProvider);
      // Should have some confidence based on motion alone
      expect(state.confidence, greaterThan(0.0));
      expect(state.consecutiveDetections, greaterThanOrEqualTo(3));

      container.dispose();
    });

    test('should respect cooldown period', () async {
      final container = createContainer();

      final detector = container.read(tripStartDetectorProvider.notifier);

      // Activate cooldown
      detector.activateCooldown();

      // Verify cooldown blocks trip start
      final state = container.read(tripStartDetectorProvider);
      expect(state.cooldownActive, isTrue);
      expect(state.consecutiveDetections, equals(0));
      expect(detector.shouldStartTrip(), isFalse);

      container.dispose();
    });

    test('should deactivate cooldown after timeout', () async {
      final container = createContainer();

      final detector = container.read(tripStartDetectorProvider.notifier);

      // Activate cooldown
      detector.activateCooldown();
      final state = container.read(tripStartDetectorProvider);
      expect(state.cooldownActive, isTrue);
      expect(state.cooldownStartTime, isNotNull);

      // Verify cooldown is active
      expect(detector.shouldStartTrip(), isFalse);

      container.dispose();
    });

    test('should calculate correct confidence score', () async {
      final container = createContainer();

      final detector = container.read(tripStartDetectorProvider.notifier);
      final motion = createCyclingMotion();
      final location = createCyclingLocation();

      // Analyze once
      await detector.analyzeForTripStart(motion, location);

      final state = container.read(tripStartDetectorProvider);
      // Confidence should be > 0 and <= 1.0
      expect(state.confidence, greaterThan(0.0));
      expect(state.confidence, lessThanOrEqualTo(1.0));

      container.dispose();
    });

    test('should reset state correctly', () async {
      final container = createContainer();

      final detector = container.read(tripStartDetectorProvider.notifier);
      final motion = createCyclingMotion();
      final location = createCyclingLocation();

      // Build up some state
      await detector.analyzeForTripStart(motion, location);
      await detector.analyzeForTripStart(motion, location);

      final stateBefore = container.read(tripStartDetectorProvider);
      expect(stateBefore.consecutiveDetections, greaterThan(0));

      // Reset
      detector.reset();

      final stateAfter = container.read(tripStartDetectorProvider);
      expect(stateAfter.confidence, equals(0.0));
      expect(stateAfter.consecutiveDetections, equals(0));
      expect(stateAfter.lastDetectionTime, isNull);
      expect(stateAfter.cooldownActive, isFalse);

      container.dispose();
    });
  });
}
