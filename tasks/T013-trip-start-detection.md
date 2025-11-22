# T013: Automatic Trip Start Detection

**Status**: ☐ Pending
**Phase**: 4 - Trip Detection Logic
**Dependencies**: T004 (Location Service), T008 (Cycling Detection), T012 (Trip State Machine)
**Estimate**: 3-4 hours

---

## Overview

Implement intelligent automatic trip start detection by combining motion sensor analysis with GPS speed validation. This task creates the core logic that automatically starts tracking when the user begins cycling, without requiring manual trip start.

**Goal**: Seamlessly detect cycling activity onset and trigger trip recording with minimal false positives.

---

## Objectives

- [x] Combine motion pattern detection with GPS speed validation
- [x] Implement confidence-based trip start logic
- [x] Handle edge cases (false starts, brief movements)
- [x] Integrate with trip state machine (Idle → Detecting → Active)
- [x] Add configurable sensitivity thresholds
- [x] Implement cooldown logic to prevent rapid start/stop cycles

---

## Technical Specification

### 1. Trip Start Detector Service

**Location**: `lib/features/trip_detection/data/services/trip_start_detector.dart`

**Purpose**: Analyze motion and GPS data to determine when a cycling trip should start.

**Key Components**:

#### 1.1 Detection Logic
```dart
@riverpod
class TripStartDetector extends _$TripStartDetector {
  @override
  TripStartState build() {
    return TripStartState.initial();
  }

  // Analyze motion and GPS to determine trip start
  Future<void> analyzeForTripStart(
    MotionData motion,
    LocationData? location,
  ) async {
    // 1. Check motion patterns for cycling
    // 2. Validate with GPS speed if available
    // 3. Update confidence score
    // 4. Trigger start if confidence exceeds threshold
  }

  // Calculate confidence score (0.0-1.0)
  double _calculateStartConfidence(
    MotionData motion,
    LocationData? location,
  ) {
    // Combine motion score and speed score
  }
}
```

#### 1.2 State Model
```dart
@freezed
sealed class TripStartState with _$TripStartState {
  const TripStartState._();

  const factory TripStartState({
    required double confidence,
    required int consecutiveDetections,
    required DateTime? lastDetectionTime,
    required bool cooldownActive,
  }) = _TripStartState;

  factory TripStartState.initial() {
    return TripStartState(
      confidence: 0.0,
      consecutiveDetections: 0,
      lastDetectionTime: null,
      cooldownActive: false,
    );
  }
}
```

### 2. Detection Algorithm

**Multi-Stage Detection**:

#### Stage 1: Motion Analysis
- Use `CyclingPatternDetector` to get motion confidence
- Require minimum motion score (from `AppConstants.cyclingDetection.minimumConfidence`)
- Track consecutive positive detections

#### Stage 2: GPS Validation (if available)
- Check GPS speed is in cycling range (8-40 km/h)
- Validate speed consistency over time
- Handle GPS unavailability gracefully (motion-only mode)

#### Stage 3: Confidence Calculation
```dart
double _calculateStartConfidence(MotionData motion, LocationData? location) {
  double motionScore = _getMotionScore(motion);
  double speedScore = location != null ? _getSpeedScore(location) : 0.0;

  // Weight motion more heavily if GPS unavailable
  if (location == null) {
    return motionScore;
  } else {
    return (motionScore * 0.6) + (speedScore * 0.4);
  }
}
```

#### Stage 4: Trigger Conditions
```dart
bool _shouldStartTrip() {
  final settings = ref.read(settingsProvider);

  return state.confidence >= settings.tripStartConfidenceThreshold
      && state.consecutiveDetections >= settings.minimumConsecutiveDetections
      && !state.cooldownActive;
}
```

### 3. Integration with Trip State Machine

**Provider Integration**:
```dart
@riverpod
class TripDetectionCoordinator extends _$TripDetectionCoordinator {
  @override
  Stream<TripState> build() async* {
    // Listen to motion and location streams
    final motionStream = motionDataStream(ref);
    final locationStream = locationStream(ref);

    // Combine streams
    await for (final data in _combineStreams(motionStream, locationStream)) {
      // Analyze for trip start
      await ref.read(tripStartDetectorProvider.notifier)
        .analyzeForTripStart(data.motion, data.location);

      // Check if should start trip
      final startState = ref.read(tripStartDetectorProvider);
      if (_shouldTransitionToActive(startState)) {
        yield* _startTrip();
      }
    }
  }
}
```

### 4. Configuration Constants

**Add to** `lib/core/constants/app_constants.dart`:

```dart
class TripStartDetection {
  // Confidence threshold to trigger trip start (0.0-1.0)
  static const double confidenceThreshold = 0.7;

  // Minimum consecutive detections before starting
  static const int minimumConsecutiveDetections = 3;

  // Time window for consecutive detection counting (seconds)
  static const int detectionWindowSeconds = 5;

  // Cooldown period after false start (seconds)
  static const int cooldownPeriodSeconds = 30;

  // GPS speed range for cycling validation (km/h)
  static const double minimumCyclingSpeed = 8.0;
  static const double maximumCyclingSpeed = 40.0;

  // Grace period before GPS required (seconds)
  // Allow motion-only detection for first N seconds
  static const int gpsGracePeriodSeconds = 10;
}
```

---

## Implementation Steps

### Step 1: Create State Model
```bash
# File: lib/features/trip_detection/domain/models/trip_start_state.dart
```

1. Create freezed model for `TripStartState`
2. Include: confidence, consecutive detections, timing, cooldown
3. Add factory constructor for initial state
4. Run code generation

**Test**:
```bash
flutter pub run build_runner build --delete-conflicting-outputs
flutter analyze
```

### Step 2: Implement Trip Start Detector Service
```bash
# File: lib/features/trip_detection/data/services/trip_start_detector.dart
```

1. Create Riverpod notifier provider
2. Implement `analyzeForTripStart()` method
3. Implement confidence calculation logic
4. Add consecutive detection tracking
5. Implement cooldown logic
6. Add logging for debugging

**Test**:
```bash
flutter analyze
flutter test test/features/trip_detection/data/services/trip_start_detector_test.dart
```

### Step 3: Add Configuration Constants
```bash
# File: lib/core/constants/app_constants.dart
```

1. Add `TripStartDetection` class with all thresholds
2. Ensure values are tuned for real-world cycling

### Step 4: Create Trip Detection Coordinator
```bash
# File: lib/features/trip_detection/data/services/trip_detection_coordinator.dart
```

1. Create coordinator that listens to motion + location streams
2. Call trip start detector on each data update
3. Transition state machine from Idle → Detecting → Active
4. Handle edge cases (GPS unavailable, sensor failures)

**Test**:
```bash
flutter analyze
```

### Step 5: Write Unit Tests
```bash
# File: test/features/trip_detection/data/services/trip_start_detector_test.dart
```

**Test Cases**:
1. ✅ Detects trip start with high motion + valid GPS speed
2. ✅ Does NOT start with high motion but no GPS (within grace period)
3. ✅ Requires consecutive detections (prevents single spike triggers)
4. ✅ Respects cooldown period after false start
5. ✅ Handles GPS unavailability gracefully
6. ✅ Confidence calculation is correct
7. ✅ Walking speed does not trigger trip (8 km/h threshold)
8. ✅ Driving speed does not trigger trip (40 km/h threshold)

**Example Test**:
```dart
test('should start trip with cycling motion and valid GPS speed', () async {
  final detector = TripStartDetector();

  // Create cycling motion data (meets thresholds)
  final motion = MotionData(
    accelerometer: AccelerometerData(x: 3.0, y: 3.0, z: 10.0), // ~10.86 m/s²
    gyroscope: GyroscopeData(x: 1.0, y: 0.5, z: 0.5), // ~1.22 rad/s
    timestamp: DateTime.now(),
  );

  // Create cycling speed GPS data (18 km/h)
  final location = LocationData(
    latitude: 48.8566,
    longitude: 2.3522,
    accuracy: 10.0,
    altitude: 35.0,
    speed: 5.0, // m/s = 18 km/h
    heading: 90.0,
    timestamp: DateTime.now(),
  );

  // Analyze 3 times for consecutive detection
  await detector.analyzeForTripStart(motion, location);
  await Future.delayed(Duration(seconds: 1));
  await detector.analyzeForTripStart(motion, location);
  await Future.delayed(Duration(seconds: 1));
  await detector.analyzeForTripStart(motion, location);

  final state = detector.state;
  expect(state.confidence, greaterThanOrEqualTo(0.7));
  expect(state.consecutiveDetections, greaterThanOrEqualTo(3));
  expect(detector.shouldStartTrip(), isTrue);
});
```

### Step 6: Integration Testing
```bash
# Physical device required!
```

1. Test on physical device (sensors required)
2. Start cycling and verify automatic trip start
3. Test edge cases:
   - Walking (should NOT trigger)
   - Brief movement (should NOT trigger)
   - Driving (should NOT trigger)
   - Indoor cycling (GPS unavailable)
4. Verify cooldown prevents rapid start/stop

---

## Edge Cases & Error Handling

### 1. GPS Unavailable
- **Scenario**: Indoors, tunnels, poor signal
- **Handling**: Use motion-only detection with higher confidence threshold
- **Implementation**: Grace period before requiring GPS validation

### 2. False Starts (Brief Movement)
- **Scenario**: User moves bike without riding, bumpy surface
- **Handling**: Require consecutive detections over time window
- **Implementation**: Track detection timestamps, reset if gap too long

### 3. Sensor Data Gaps
- **Scenario**: Sensor stream interruption
- **Handling**: Reset detection state if data gap exceeds threshold
- **Implementation**: Track last data timestamp, reset if stale

### 4. Battery Optimization Interference
- **Scenario**: Android Doze mode throttles sensors
- **Handling**: Use foreground service to maintain sensor access
- **Implementation**: Rely on background service (T005)

### 5. Walking vs Cycling Ambiguity
- **Scenario**: Slow cycling (<8 km/h) might resemble walking
- **Handling**: Tune motion pattern thresholds to distinguish
- **Implementation**: Pedaling frequency detection (from T008)

---

## Quality Gates

**Before marking complete**:

1. ✅ Code generation successful (`build_runner`)
2. ✅ `flutter analyze` passes with no errors
3. ✅ All unit tests pass
4. ✅ Physical device testing completed:
   - ✅ Automatic start during actual cycling
   - ✅ No false positives during walking
   - ✅ No false positives during driving
   - ✅ Cooldown prevents rapid cycles
5. ✅ Edge cases handled gracefully
6. ✅ Constants tuned for real-world usage
7. ✅ Code follows existing patterns (freezed, Riverpod)
8. ✅ Documentation comments added

---

## Testing Checklist

### Unit Tests
- [ ] Trip start with valid cycling motion + GPS
- [ ] Trip start with motion only (GPS unavailable)
- [ ] No trip start with single detection (consecutive required)
- [ ] No trip start during cooldown period
- [ ] Walking speed does not trigger (< 8 km/h)
- [ ] Driving speed does not trigger (> 40 km/h)
- [ ] Confidence calculation is correct
- [ ] Consecutive detection counting works
- [ ] Data gap resets detection state

### Physical Device Tests
- [ ] Actual cycling triggers automatic start (within 5-10 seconds)
- [ ] Walking does NOT trigger trip start
- [ ] Brief bike movement does NOT trigger (push bike, adjust position)
- [ ] Driving does NOT trigger trip start
- [ ] Indoor cycling (no GPS) triggers after grace period
- [ ] Cooldown prevents immediate restart after false positive

---

## File Checklist

**Files to Create**:
- [x] `lib/features/trip_detection/domain/models/trip_start_state.dart`
- [x] `lib/features/trip_detection/data/services/trip_start_detector.dart`
- [x] `lib/features/trip_detection/data/services/trip_detection_coordinator.dart`
- [x] `test/features/trip_detection/data/services/trip_start_detector_test.dart`

**Files to Modify**:
- [x] `lib/core/constants/app_constants.dart` (add TripStartDetection class)
- [x] `tasks/TASKS.md` (update progress: T013 ☐ → ⏳ → ✅)

---

## Dependencies Check

**Required Completed Tasks**:
- ✅ T004: Basic Location Service (provides `LocationData`)
- ✅ T008: Cycling Motion Pattern Detection (provides `CyclingPatternDetector`)
- ✅ T012: Trip State Machine (provides state transitions)

**Required Packages** (already installed):
- ✅ `riverpod_annotation` (providers)
- ✅ `freezed` (immutable models)
- ✅ `geolocator` (location data)
- ✅ `sensors_plus` (motion data)

---

## Common Mistakes to Avoid

### Mistake 1: Triggering on Single Detection
❌ **Wrong**: Start trip on first positive detection
✅ **Correct**: Require N consecutive detections over time window

**Rationale**: Prevents false positives from brief movements, bumps, adjustments.

### Mistake 2: Requiring GPS Immediately
❌ **Wrong**: Don't start trip if GPS unavailable
✅ **Correct**: Allow grace period for GPS lock, fall back to motion-only

**Rationale**: GPS takes time to acquire lock; indoor cycling has no GPS.

### Mistake 3: No Cooldown After False Start
❌ **Wrong**: Allow immediate restart after trip ends quickly
✅ **Correct**: Enforce cooldown period (30s) after false starts

**Rationale**: Prevents rapid start/stop cycles from confusing edge-case scenarios.

### Mistake 4: Hard-Coded Thresholds
❌ **Wrong**: Magic numbers in detection logic
✅ **Correct**: All thresholds in `AppConstants.TripStartDetection`

**Rationale**: Easy tuning, single source of truth, user customization (future).

### Mistake 5: Ignoring Stream Timing
❌ **Wrong**: Assume motion and GPS data arrive simultaneously
✅ **Correct**: Handle asynchronous streams, allow location to be null

**Rationale**: Streams update at different rates; GPS may be delayed or unavailable.

---

## Performance Considerations

### Battery Impact
- **Concern**: Continuous motion + GPS analysis drains battery
- **Mitigation**:
  - Motion sensors already running (from T007)
  - GPS already motion-gated (from T006)
  - No additional battery cost from detection logic

### CPU Usage
- **Concern**: Frequent confidence calculations
- **Mitigation**:
  - Simple arithmetic (no ML inference yet)
  - Calculations only on sensor data updates (10-50Hz)
  - Minimal CPU impact

### Memory
- **Concern**: Storing detection history
- **Mitigation**:
  - Only track last N detections (small buffer)
  - No persistent storage needed
  - Cleanup on state transitions

---

## Next Steps After Completion

Once T013 is complete:
1. Update `tasks/TASKS.md` (T013: ☐ → ✅)
2. Commit with message: `T013: Implement automatic trip start detection`
3. Proceed to **T014: Automatic Trip Stop Detection**
4. Physical device testing to validate real-world performance

---

## Reference Examples

### CyclingPatternDetector Usage
```dart
// From T008
final detector = ref.read(cyclingPatternDetectorProvider);
final cyclingScore = detector.analyze(motionWindow);
// Returns confidence score (0.0-1.0)
```

### GPS Speed Validation
```dart
bool _isValidCyclingSpeed(LocationData location) {
  final speedKmh = location.speedKmh;
  return speedKmh >= AppConstants.TripStartDetection.minimumCyclingSpeed
      && speedKmh <= AppConstants.TripStartDetection.maximumCyclingSpeed;
}
```

### State Machine Transition
```dart
// From T012
if (shouldStartTrip) {
  ref.read(tripStateMachineProvider.notifier)
    .transitionTo(TripState.active);
}
```

---

## Acceptance Criteria

**Definition of Done**:
- [x] Trip automatically starts when user begins cycling
- [x] False positives minimized (walking, brief movement, driving)
- [x] Works with and without GPS (graceful degradation)
- [x] Consecutive detection requirement prevents single-spike triggers
- [x] Cooldown prevents rapid start/stop cycles
- [x] All unit tests pass
- [x] Physical device validation successful
- [x] Code follows project patterns (freezed, Riverpod, extensions)
- [x] flutter analyze passes
- [x] Constants in AppConstants, not hard-coded

---

**Task Created**: 2025-11-22
**Estimated Completion**: 3-4 hours
**Difficulty**: Medium-High (requires real-world tuning)
