# T008: Cycling Motion Pattern Detection

## Overview

Implement rule-based cycling motion pattern detection using accelerometer and gyroscope data analysis. This task builds on T007's sensor integration to create a reliable cycling detection system that distinguishes cycling from other activities (walking, driving, running). The implementation uses threshold-based pattern matching and will be replaced by ML-based detection (T016-T019) in a later phase.

**Status**: ⏳ In Progress
**Dependencies**: T007 (Sensor Integration)
**Estimate**: 3-4 hours
**Phase**: Phase 2 - Core Location & Sensors
**Target Accuracy**: 80-85% overall detection accuracy

## Prerequisites

Before starting this task, ensure:
- ✅ T007 completed (Sensor integration with MotionData, MotionWindow, SensorService)
- ✅ Physical Android and iOS devices for testing (sensors don't work in emulators)
- ✅ Understanding of cycling motion characteristics
- ✅ Access to GPS data from T004 (for speed validation)

## Objectives

1. Create ActivityConfidence model for multi-activity classification
2. Implement cycling-specific pattern detection algorithms
3. Build pedaling frequency detection (0.5-2 Hz typical for cycling)
4. Create multi-layer confidence scoring system
5. Integrate GPS speed validation (8-35 km/h cycling range)
6. Distinguish cycling from walking, driving, and running
7. Design for easy replacement with ML system (T016-T019)
8. Achieve 80-85% detection accuracy (acceptable for MVP)

## Cycling Motion Characteristics

### What Makes Cycling Unique

**Acceleration Patterns**:
- Sustained acceleration: 10-15 m/s² (higher than walking, periodic)
- Periodic patterns from pedaling motion
- Vertical oscillation from bike movement
- Different from walking: more sustained, less spiky

**Rotation Patterns**:
- Gyroscope detects handlebar adjustments
- Periodic rotation from body/bike movement
- Rotation magnitude: 0.5-3 rad/s typical
- Different from driving: less smooth, more periodic

**Pedaling Frequency**:
- Typical cycling: 60-90 RPM (1-1.5 Hz)
- Casual: 50-70 RPM (0.83-1.17 Hz)
- Athletic: 80-120 RPM (1.33-2 Hz)
- Detectable through periodic peaks in acceleration

**Speed Range**:
- Casual cycling: 10-15 km/h
- Commuting: 15-25 km/h
- Athletic cycling: 25-35 km/h
- Outside range (<8 km/h or >40 km/h) likely not cycling

## Implementation Steps

### Step 1: Create ActivityConfidence Domain Model

**File**: `lib/features/trip_detection/domain/models/activity_confidence.dart`

```dart
import 'package:freezed_annotation/freezed_annotation.dart';

part 'activity_confidence.freezed.dart';

/// Activity types that can be detected
enum ActivityType {
  stationary,   // Not moving
  walking,      // Walking or slow movement
  cycling,      // Cycling (target activity)
  driving,      // In vehicle
  running,      // Running or fast movement
  unknown,      // Insufficient data
}

/// Confidence level for activity classification
enum ConfidenceLevel {
  veryLow,   // 0-0.4
  low,       // 0.4-0.6
  medium,    // 0.6-0.8
  high,      // 0.8-0.9
  veryHigh,  // 0.9-1.0
}

/// Activity classification with confidence scores
@freezed
class ActivityConfidence with _$ActivityConfidence {
  const factory ActivityConfidence({
    required ActivityType activity,
    required double confidence,  // 0.0-1.0
    required double motionScore,  // Motion pattern score
    required double speedScore,   // GPS speed validation score
    required double frequencyScore, // Pedaling frequency score
    Map<ActivityType, double>? allScores, // Scores for all activities
  }) = _ActivityConfidence;

  const ActivityConfidence._();

  /// Create from individual scores
  factory ActivityConfidence.fromScores({
    required double motionScore,
    required double speedScore,
    required double frequencyScore,
    required Map<ActivityType, double> activityScores,
  }) {
    // Find activity with highest score
    ActivityType bestActivity = ActivityType.unknown;
    double bestScore = 0.0;

    activityScores.forEach((activity, score) {
      if (score > bestScore) {
        bestActivity = activity;
        bestScore = score;
      }
    });

    // Calculate combined confidence
    final combinedConfidence = (motionScore + speedScore + frequencyScore) / 3;

    return ActivityConfidence(
      activity: bestActivity,
      confidence: combinedConfidence,
      motionScore: motionScore,
      speedScore: speedScore,
      frequencyScore: frequencyScore,
      allScores: activityScores,
    );
  }

  /// Create unknown activity
  factory ActivityConfidence.unknown() {
    return const ActivityConfidence(
      activity: ActivityType.unknown,
      confidence: 0.0,
      motionScore: 0.0,
      speedScore: 0.0,
      frequencyScore: 0.0,
    );
  }

  /// Create cycling activity with confidence
  factory ActivityConfidence.cycling({
    required double confidence,
    required double motionScore,
    required double speedScore,
    required double frequencyScore,
  }) {
    return ActivityConfidence(
      activity: ActivityType.cycling,
      confidence: confidence,
      motionScore: motionScore,
      speedScore: speedScore,
      frequencyScore: frequencyScore,
    );
  }

  /// Get confidence level category
  ConfidenceLevel get level {
    if (confidence < 0.4) return ConfidenceLevel.veryLow;
    if (confidence < 0.6) return ConfidenceLevel.low;
    if (confidence < 0.8) return ConfidenceLevel.medium;
    if (confidence < 0.9) return ConfidenceLevel.high;
    return ConfidenceLevel.veryHigh;
  }

  /// Check if cycling is detected with reasonable confidence
  bool get isCyclingDetected {
    return activity == ActivityType.cycling && confidence >= 0.6;
  }

  /// Check if activity is ambiguous (low confidence)
  bool get isAmbiguous {
    return confidence < 0.6;
  }

  /// Get second most likely activity
  ActivityType? get secondBestActivity {
    if (allScores == null || allScores!.length < 2) return null;

    final sorted = allScores!.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return sorted.length > 1 ? sorted[1].key : null;
  }
}
```

### Step 2: Update AppConstants with Cycling Thresholds

**File**: `lib/core/constants/app_constants.dart` (add to existing file)

```dart
// Add to existing AppConstants class

class AppConstants {
  // ... existing constants ...

  // Cycling Detection Thresholds

  // Acceleration thresholds (m/s²)
  static const double cyclingAccelerationMin = 10.0;  // Minimum for cycling
  static const double cyclingAccelerationMax = 20.0;  // Maximum typical cycling
  static const double walkingAccelerationMax = 12.0;  // Walking typically <12

  // Rotation thresholds (rad/s)
  static const double cyclingRotationMin = 0.5;   // Minimum rotation for cycling
  static const double cyclingRotationMax = 3.0;   // Maximum typical rotation

  // Pedaling frequency (Hz)
  static const double pedalingFrequencyMin = 0.5;   // 30 RPM minimum
  static const double pedalingFrequencyMax = 2.0;   // 120 RPM maximum
  static const double pedalingFrequencyTypical = 1.2; // 72 RPM typical

  // Speed validation (km/h)
  static const double cyclingSpeedMin = 8.0;   // Slower than this = likely walking
  static const double cyclingSpeedMax = 40.0;  // Faster than this = likely driving
  static const double cyclingSpeedTypical = 18.0; // Typical commuting speed

  // Pattern analysis
  static const int minSamplesForPattern = 100;  // ~2 seconds at 50Hz
  static const int pedalingCycleSamples = 50;   // ~1 second for one pedal cycle

  // Confidence thresholds
  static const double minConfidenceForDetection = 0.6;  // Minimum to trigger
  static const double highConfidenceThreshold = 0.8;    // High confidence

  // Activity classification weights
  static const double motionScoreWeight = 0.4;     // 40% weight
  static const double speedScoreWeight = 0.35;     // 35% weight
  static const double frequencyScoreWeight = 0.25; // 25% weight
}
```

### Step 3: Create Cycling Pattern Detector Service

**File**: `lib/features/trip_detection/data/services/cycling_pattern_detector.dart`

```dart
import 'dart:async';
import 'dart:math';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../domain/models/motion_data.dart';
import '../../domain/models/activity_confidence.dart';
import '../../domain/models/location_data.dart';
import '../../../../core/constants/app_constants.dart';
import 'motion_detection_service.dart';
import 'location_service.dart';
import 'sensor_utils.dart';

part 'cycling_pattern_detector.g.dart';

/// Cycling pattern detector service
/// Analyzes motion patterns to detect cycling activity
@riverpod
class CyclingPatternDetector extends _$CyclingPatternDetector {
  @override
  Stream<ActivityConfidence> build() async* {
    // Get motion detection service
    final motionService = ref.watch(motionDetectionServiceProvider);

    // Get location stream for speed validation
    final locationStream = ref.watch(locationStreamProvider);

    LocationData? currentLocation;

    // Listen to location updates
    locationStream.listen((locationAsync) {
      locationAsync.whenData((location) {
        currentLocation = location;
      });
    });

    // Analyze motion state changes
    await for (final motionStateAsync in motionService) {
      await motionStateAsync.when(
        data: (motionState) async {
          final window = ref.read(motionDetectionServiceProvider.notifier)
              .getCurrentWindow();

          if (window != null && window.hasEnoughSamples) {
            final confidence = _analyzePattern(window, currentLocation);
            yield confidence;
          } else {
            yield ActivityConfidence.unknown();
          }
        },
        loading: () async {
          yield ActivityConfidence.unknown();
        },
        error: (_, __) async {
          yield ActivityConfidence.unknown();
        },
      );
    }
  }

  /// Analyze motion pattern and classify activity
  ActivityConfidence _analyzePattern(
    MotionWindow window,
    LocationData? location,
  ) {
    // Layer 1: Motion pattern analysis
    final motionScore = _analyzeMotionPattern(window);

    // Layer 2: Pedaling frequency analysis
    final frequencyScore = _analyzePedalingFrequency(window);

    // Layer 3: GPS speed validation (if available)
    final speedScore = location != null
        ? _analyzeSpeedPattern(location)
        : 0.5; // Neutral score if no GPS

    // Calculate confidence scores for each activity
    final activityScores = _calculateActivityScores(
      motionScore,
      frequencyScore,
      speedScore,
      window,
    );

    return ActivityConfidence.fromScores(
      motionScore: motionScore,
      speedScore: speedScore,
      frequencyScore: frequencyScore,
      activityScores: activityScores,
    );
  }

  /// Analyze motion pattern (acceleration + rotation)
  double _analyzeMotionPattern(MotionWindow window) {
    final avgAccel = window.averageAcceleration;
    final avgRotation = window.averageRotation;

    double score = 0.0;

    // Check acceleration range for cycling
    if (avgAccel >= AppConstants.cyclingAccelerationMin &&
        avgAccel <= AppConstants.cyclingAccelerationMax) {
      score += 0.5;
    } else if (avgAccel < AppConstants.cyclingAccelerationMin) {
      score += 0.2; // Too low for cycling
    }

    // Check rotation for cycling
    if (avgRotation >= AppConstants.cyclingRotationMin &&
        avgRotation <= AppConstants.cyclingRotationMax) {
      score += 0.5;
    }

    return score.clamp(0.0, 1.0);
  }

  /// Analyze pedaling frequency
  double _analyzePedalingFrequency(MotionWindow window) {
    if (window.samples.length < AppConstants.minSamplesForPattern) {
      return 0.0;
    }

    // Extract acceleration magnitudes
    final accelMagnitudes = window.samples
        .map((s) => s.accelerometer.magnitude)
        .toList();

    // Detect peaks (pedaling cycles)
    final peaks = _detectPeaks(accelMagnitudes);

    if (peaks.length < 2) {
      return 0.0; // Not enough peaks to determine frequency
    }

    // Calculate average time between peaks (pedaling frequency)
    final avgTimeBetweenPeaks = window.duration.inMilliseconds /
        (peaks.length - 1);
    final frequency = 1000.0 / avgTimeBetweenPeaks; // Hz

    // Check if frequency matches cycling range
    if (frequency >= AppConstants.pedalingFrequencyMin &&
        frequency <= AppConstants.pedalingFrequencyMax) {
      // Calculate how close to typical cycling frequency
      final distanceFromTypical =
          (frequency - AppConstants.pedalingFrequencyTypical).abs();
      final maxDistance = AppConstants.pedalingFrequencyMax -
          AppConstants.pedalingFrequencyMin;
      final score = 1.0 - (distanceFromTypical / maxDistance);
      return score.clamp(0.6, 1.0); // Cycling frequency detected
    }

    return 0.3; // Periodic motion but not cycling frequency
  }

  /// Detect peaks in acceleration data (pedaling cycles)
  List<int> _detectPeaks(List<double> values) {
    final peaks = <int>[];

    for (var i = 1; i < values.length - 1; i++) {
      if (SensorUtils.isPeak(values, i, threshold: 10.0)) {
        peaks.add(i);
      }
    }

    return peaks;
  }

  /// Analyze GPS speed pattern
  double _analyzeSpeedPattern(LocationData location) {
    final speedKmh = location.speed * 3.6; // m/s to km/h

    // Check if speed is in cycling range
    if (speedKmh >= AppConstants.cyclingSpeedMin &&
        speedKmh <= AppConstants.cyclingSpeedMax) {
      // Calculate how typical the speed is for cycling
      final distanceFromTypical =
          (speedKmh - AppConstants.cyclingSpeedTypical).abs();
      final maxDistance = AppConstants.cyclingSpeedMax -
          AppConstants.cyclingSpeedMin;
      final score = 1.0 - (distanceFromTypical / maxDistance);
      return score.clamp(0.6, 1.0);
    } else if (speedKmh < AppConstants.cyclingSpeedMin) {
      return 0.3; // Too slow, likely walking
    } else {
      return 0.2; // Too fast, likely driving
    }
  }

  /// Calculate confidence scores for all activities
  Map<ActivityType, double> _calculateActivityScores(
    double motionScore,
    double frequencyScore,
    double speedScore,
    MotionWindow window,
  ) {
    final avgAccel = window.averageAcceleration;
    final avgRotation = window.averageRotation;

    // Cycling score (weighted average)
    final cyclingScore = (motionScore * AppConstants.motionScoreWeight) +
        (frequencyScore * AppConstants.frequencyScoreWeight) +
        (speedScore * AppConstants.speedScoreWeight);

    // Stationary score
    final stationaryScore = (avgAccel < 10.0 && avgRotation < 0.3) ? 0.9 : 0.1;

    // Walking score
    final walkingScore = (avgAccel >= 10.0 &&
            avgAccel < 12.0 &&
            frequencyScore < 0.5 &&
            speedScore < 0.4)
        ? 0.7
        : 0.2;

    // Driving score
    final drivingScore = (avgAccel > 10.0 &&
            avgRotation < 1.0 &&
            speedScore < 0.3) // High speed
        ? 0.6
        : 0.2;

    // Running score
    final runningScore = (avgAccel > 12.0 &&
            frequencyScore > 0.5 &&
            frequencyScore < 0.7 &&
            speedScore < 0.5)
        ? 0.6
        : 0.2;

    return {
      ActivityType.cycling: cyclingScore.clamp(0.0, 1.0),
      ActivityType.stationary: stationaryScore.clamp(0.0, 1.0),
      ActivityType.walking: walkingScore.clamp(0.0, 1.0),
      ActivityType.driving: drivingScore.clamp(0.0, 1.0),
      ActivityType.running: runningScore.clamp(0.0, 1.0),
      ActivityType.unknown: 0.0,
    };
  }

  /// Get current activity classification
  Future<ActivityConfidence> getCurrentActivity() async {
    final window = ref.read(motionDetectionServiceProvider.notifier)
        .getCurrentWindow();

    if (window == null || !window.hasEnoughSamples) {
      return ActivityConfidence.unknown();
    }

    // Get current location
    final locationAsync = await ref.read(locationStreamProvider.future);
    final location = locationAsync;

    return _analyzePattern(window, location);
  }

  /// Check if currently cycling with high confidence
  Future<bool> isCycling() async {
    final activity = await getCurrentActivity();
    return activity.isCyclingDetected;
  }
}

/// Provider for current activity classification
@riverpod
Stream<ActivityConfidence> currentActivity(CurrentActivityRef ref) {
  return ref.watch(cyclingPatternDetectorProvider);
}
```

### Step 4: Update MotionData with Enhanced Detection

**File**: `lib/features/trip_detection/domain/models/motion_data.dart` (update existing)

Add to the existing `MotionWindow` class:

```dart
// Add to MotionWindow class (after existing methods)

/// Analyze if pattern indicates cycling (enhanced)
/// Uses multi-factor analysis for better accuracy
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
```

### Step 5: Create Unit Tests

**File**: `test/features/trip_detection/data/services/cycling_pattern_detector_test.dart`

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:autoride/features/trip_detection/domain/models/motion_data.dart';
import 'package:autoride/features/trip_detection/domain/models/activity_confidence.dart';
import 'package:autoride/features/trip_detection/domain/models/location_data.dart';
import 'package:autoride/core/constants/app_constants.dart';

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
  });

  group('CyclingPatternDetector - Motion Analysis', () {
    test('should detect cycling motion pattern', () {
      // Create cycling-like motion data
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
            z: 0.5, // magnitude ≈ 1.22
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
        timestamp: DateTime.now(),
      );

      final speedKmh = location.speed * 3.6;

      expect(speedKmh, greaterThan(AppConstants.cyclingSpeedMax));
    });
  });
}
```

## Testing Strategy

### Unit Tests Checklist

- [ ] ActivityConfidence model tests
  - [ ] Confidence level calculation
  - [ ] Activity classification
  - [ ] Ambiguity detection

- [ ] Pattern detection tests
  - [ ] Motion pattern analysis
  - [ ] Pedaling frequency detection
  - [ ] Periodic pattern recognition

- [ ] Speed validation tests
  - [ ] Cycling speed range validation
  - [ ] Walking speed detection
  - [ ] Driving speed detection

- [ ] Integration tests
  - [ ] Combined score calculation
  - [ ] Activity classification accuracy
  - [ ] Edge cases handling

### Physical Device Testing

**Critical: Test on Real Devices During Real Activities**

#### Cycling Test Scenarios

1. **Casual Cycling** (10-15 km/h):
   - [ ] Flat terrain, steady pace
   - [ ] Expected: High confidence cycling detection
   - [ ] Verify frequency in range (0.8-1.2 Hz)

2. **Commuting Cycling** (15-25 km/h):
   - [ ] Mixed terrain, typical commute
   - [ ] Expected: Very high confidence
   - [ ] Verify speed validation working

3. **Athletic Cycling** (25-35 km/h):
   - [ ] Fast pace, road cycling
   - [ ] Expected: High confidence
   - [ ] Verify doesn't confuse with driving

4. **Stops and Starts**:
   - [ ] Red lights, traffic stops
   - [ ] Expected: Cycling detection pauses correctly
   - [ ] Resumes detection when cycling resumes

#### False Positive Testing

1. **Walking** (4-6 km/h):
   - [ ] Normal walking pace
   - [ ] Expected: NOT detected as cycling
   - [ ] Should classify as walking

2. **Running** (8-12 km/h):
   - [ ] Jogging pace
   - [ ] Expected: LOW confidence or walking
   - [ ] Should not trigger cycling

3. **Driving** (30-60 km/h):
   - [ ] Car, bus, train
   - [ ] Expected: NOT cycling (speed too high)
   - [ ] Should classify as driving

4. **Stationary**:
   - [ ] Sitting, standing still
   - [ ] Expected: Stationary classification
   - [ ] No cycling detection

### Accuracy Validation

**Target Metrics**:
- Overall accuracy: 80-85%
- Cycling vs Stationary: >95%
- Cycling vs Walking: >85%
- Cycling vs Driving (with GPS): >75%

**Data Collection** (for later ML training):
```dart
// Log detection results for analysis
void logDetectionResult({
  required ActivityConfidence detected,
  required ActivityType actual, // User-confirmed
  required MotionWindow window,
  required LocationData? location,
}) {
  // Save to local database for later analysis
  // This data will be used to improve ML model in T016-T019
}
```

## Acceptance Criteria

### Functional Requirements
- [ ] ActivityConfidence model created with freezed
- [ ] CyclingPatternDetector service implemented
- [ ] Multi-layer confidence scoring (motion + frequency + speed)
- [ ] Pedaling frequency detection working (0.5-2 Hz)
- [ ] Activity classification for all activity types
- [ ] GPS speed validation integrated
- [ ] AppConstants updated with cycling thresholds
- [ ] MotionWindow enhanced with cycling detection methods

### Quality Requirements
- [ ] All unit tests pass (>80% coverage)
- [ ] Physical device testing completed successfully
- [ ] Detection accuracy meets targets (80-85% overall)
- [ ] No false positives during walking/stationary tests
- [ ] Cycling detection triggers correctly during real cycling
- [ ] Code follows existing patterns (Riverpod, freezed)
- [ ] Flutter analyze passes with no errors

### Performance Requirements
- [ ] Detection latency <2 seconds
- [ ] No significant battery impact vs T007
- [ ] Pattern analysis doesn't block UI thread
- [ ] Memory usage reasonable (<20 MB additional)

## Common Pitfalls

### Pitfall 1: Over-Tuned Thresholds

**Problem**: Thresholds work perfectly in testing but fail in real-world scenarios.

**Solution**:
```dart
// ❌ Wrong: Too specific thresholds
if (avgAccel == 12.5 && frequency == 1.2) {
  return cycling;
}

// ✅ Right: Range-based detection
if (avgAccel >= 10.0 && avgAccel <= 20.0 &&
    frequency >= 0.5 && frequency <= 2.0) {
  return cycling;
}
```

### Pitfall 2: Ignoring Phone Position

**Problem**: Detection works in pocket but fails in backpack or on handlebar mount.

**Solution**:
```dart
// Use magnitude (orientation-independent) instead of raw x, y, z
final magnitude = sqrt(x * x + y * y + z * z);

// Magnitude works regardless of phone orientation
```

### Pitfall 3: No GPS Fallback

**Problem**: Detection fails when GPS is unavailable (tunnels, indoors).

**Solution**:
```dart
// Provide neutral score when GPS unavailable
final speedScore = location != null
    ? _analyzeSpeedPattern(location)
    : 0.5; // Neutral score, rely on motion only
```

### Pitfall 4: Missing Edge Cases

**Problem**: Doesn't handle unusual cycling scenarios (hills, wind, fatigue).

**Solution**:
```dart
// Use confidence ranges, not binary detection
if (confidence >= 0.8) {
  return "Very likely cycling";
} else if (confidence >= 0.6) {
  return "Probably cycling";
} else {
  return "Uncertain - need more data";
}
```

### Pitfall 5: Test Data Doesn't Match Reality

**Problem**: Test data has perfect periodic patterns; real cycling doesn't.

**Solution**:
```dart
// Add noise to test data to simulate reality
final accelValue = 11.0 +
    2.0 * sin(2 * pi * 1.0 * t) +
    Random().nextDouble() * 0.5; // Add noise
```

## Design for ML Replacement

### Interface Contract

The CyclingPatternDetector provides a clean interface that ML can replace:

```dart
// Current: Rule-based implementation
@riverpod
class CyclingPatternDetector extends _$CyclingPatternDetector {
  @override
  Stream<ActivityConfidence> build() async* {
    // Rule-based pattern analysis
  }
}

// Future (T016-T019): ML-based implementation
@riverpod
class MLActivityClassifier extends _$MLActivityClassifier {
  @override
  Stream<ActivityConfidence> build() async* {
    // TensorFlow Lite inference
    // Same output: ActivityConfidence
  }
}
```

**What Stays the Same**:
- Input: MotionWindow + LocationData (optional)
- Output: ActivityConfidence with scores
- Stream-based reactive updates
- Confidence scoring (0.0-1.0)

**What Changes in ML Version**:
- Pattern analysis replaced by neural network inference
- No manual threshold tuning
- Better accuracy (90%+ vs 80-85%)
- Handles edge cases automatically

## Resources

### Pattern Recognition
- [Cycling Detection Algorithms](https://www.mdpi.com/1424-8220/20/11/3208)
- [Peak Detection Methods](https://en.wikipedia.org/wiki/Peak_detection)
- [Frequency Analysis](https://en.wikipedia.org/wiki/Frequency_domain)

### Human Activity Recognition
- [HAR with Smartphone Sensors](https://link.springer.com/article/10.1007/s12243-023-00962-x)
- [Activity Classification Techniques](https://www.sciencedirect.com/topics/computer-science/activity-classification)

### Testing Best Practices
- [Flutter Testing Documentation](https://docs.flutter.dev/testing)
- [Physical Activity Testing](https://www.polar.com/blog/cycling-cadence/)

## Next Steps

After completing T008, you'll be ready for:

1. **T012**: Trip State Machine
   - Use ActivityConfidence to trigger state transitions
   - Integrate cycling detection into trip logic

2. **T013**: Automatic Trip Start Detection
   - Combine motion + GPS + cycling confidence
   - Automatic trip recording when cycling detected

3. **T016-T019**: ML Enhancement (Phase 5)
   - Replace rule-based detector with TensorFlow Lite
   - Improve accuracy to 90%+
   - Use collected data to train model

## Notes

- **Real Device Testing is Mandatory**: Test during actual cycling, not just simulation
- **Accuracy Target is Realistic**: 80-85% is acceptable for MVP, ML will improve later
- **Design for Replacement**: Keep interface clean for ML swap in Phase 5
- **Collect Data**: Log detections for future ML training
- **User Feedback Essential**: Add confirmation dialogs to learn from mistakes
- **Battery Impact**: Should not increase battery usage vs T007 baseline
- **GPS Optional**: System should work (with reduced confidence) without GPS

## Implementation Tips

1. **Start with Simple Thresholds**: Get basic cycling detection working first
2. **Test Incrementally**: Test each layer separately before combining
3. **Use Real Cycling Data**: Simulate or collect actual cycling motion patterns
4. **Tune Iteratively**: Adjust thresholds based on real-world testing
5. **Document Findings**: Note any surprising patterns or edge cases
6. **Keep It Simple**: Remember this will be replaced by ML - don't over-engineer

---

**Created**: 2025-11-22
**Status**: Ready for implementation
**Will be replaced by**: T016-T019 (ML-based classification) in Phase 5
