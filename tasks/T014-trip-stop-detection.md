# T014: Automatic Trip Stop Detection

**Status**: ☐ Pending
**Phase**: 4 - Trip Detection Logic
**Dependencies**: T013 (Automatic Trip Start Detection)
**Estimate**: 2-3 hours

---

## Overview

Implement intelligent automatic trip stop detection that distinguishes between brief stops (traffic lights, intersections) and actual trip endings. This task creates the logic that automatically ends trip tracking when the user has finished cycling.

**Goal**: Seamlessly detect cycling activity cessation and trigger trip completion, avoiding false stops from brief pauses while preventing runaway trips.

---

## Objectives

- [ ] Detect stationary state using motion sensors and GPS
- [ ] Implement pause vs. stop logic (brief pause → resume, extended pause → stop)
- [ ] Handle timeout scenarios (max pause duration)
- [ ] Integrate with trip state machine (Active → Paused → Stopped)
- [ ] Trigger trip data finalization on stop
- [ ] Add configurable threshold parameters
- [ ] Prevent false stops from traffic lights and brief pauses

---

## Technical Specification

### 1. Trip Stop Detector Service

**Location**: `lib/features/trip_detection/data/services/trip_stop_detector.dart`

**Purpose**: Analyze motion and GPS data to determine when a cycling trip should end.

**Key Components**:

#### 1.1 Detection Logic
```dart
@riverpod
class TripStopDetector extends _$TripStopDetector {
  @override
  TripStopState build() {
    return TripStopState.initial();
  }

  // Analyze motion and GPS to determine trip stop
  Future<StopDecision> analyzeForTripStop(
    MotionData motion,
    LocationData? location,
    Duration tripDuration,
  ) async {
    // 1. Check if stationary (no motion)
    // 2. Track pause duration
    // 3. Distinguish pause vs. stop
    // 4. Return decision: Continue, Pause, or Stop
  }

  // Check if motion indicates stationary state
  bool _isStationary(MotionData motion) {
    // Low acceleration and low rotation
  }

  // Check if pause has exceeded stop threshold
  bool _shouldStopTrip(Duration pauseDuration) {
    // Compare against maxPauseDurationSeconds
  }
}
```

#### 1.2 State Model
```dart
@freezed
sealed class TripStopState with _$TripStopState {
  const TripStopState._();

  const factory TripStopState({
    required bool isStationary,
    required DateTime? pauseStartTime,
    required Duration pauseDuration,
    required int consecutiveStationaryDetections,
  }) = _TripStopState;

  factory TripStopState.initial() {
    return const TripStopState(
      isStationary: false,
      pauseStartTime: null,
      pauseDuration: Duration.zero,
      consecutiveStationaryDetections: 0,
    );
  }
}

enum StopDecision {
  continueTrp,  // Keep trip active
  pauseTrip,     // Pause trip (brief stop)
  stopTrip,      // End trip (extended stop)
}
```

### 2. Detection Algorithm

**Multi-Stage Detection**:

#### Stage 1: Stationary Detection
- Check acceleration magnitude < stationary threshold
- Check rotation magnitude < stationary threshold
- Require consecutive stationary detections (prevent single spike)
- Use motion thresholds from `AppConstants.stationaryAccelerationMax` and `stationaryRotationMax`

#### Stage 2: GPS Validation (if available)
- Check GPS speed < minimum cycling speed (< 2 km/h)
- Validate speed consistency over time
- Handle GPS unavailability gracefully

#### Stage 3: Pause Duration Tracking
```dart
Duration _calculatePauseDuration(DateTime pauseStart, DateTime now) {
  if (pauseStart == null) return Duration.zero;
  return now.difference(pauseStart);
}

StopDecision _evaluatePauseDuration(Duration pauseDuration) {
  // Brief pause (< minPauseDurationSeconds): Keep active
  if (pauseDuration.inSeconds < AppConstants.minPauseDurationSeconds) {
    return StopDecision.continueTrip;
  }

  // Medium pause (< maxPauseDurationSeconds): Pause trip
  if (pauseDuration.inSeconds < AppConstants.maxPauseDurationSeconds) {
    return StopDecision.pauseTrip;
  }

  // Extended pause: Stop trip
  return StopDecision.stopTrip;
}
```

#### Stage 4: Resume Detection
```dart
bool _shouldResumeTrip(MotionData motion, LocationData? location) {
  // Check for movement after pause
  final hasMotion = !_isStationary(motion);
  final hasSpeed = location != null && location.speedKmh > 2.0;

  return hasMotion || hasSpeed;
}
```

### 3. Integration with Trip State Machine

**State Transitions**:
```dart
@riverpod
class TripDetectionCoordinator extends _$TripDetectionCoordinator {
  Future<void> _handleStopDetection(MotionData motion, LocationData? location) async {
    final currentState = ref.read(tripStateMachineProvider);

    await currentState.mapOrNull(
      active: (_) async {
        // In active state, check for pause
        final decision = await ref
            .read(tripStopDetectorProvider.notifier)
            .analyzeForTripStop(motion, location, _.duration);

        if (decision == StopDecision.pauseTrip) {
          // Transition to paused state
          ref.read(tripStateMachineProvider.notifier).pauseTrip();
        }
      },
      paused: (pausedState) async {
        // In paused state, check for resume or stop
        final shouldResume = ref
            .read(tripStopDetectorProvider.notifier)
            .shouldResumeTrip(motion, location);

        if (shouldResume) {
          // Resume trip
          ref.read(tripStateMachineProvider.notifier).resumeTrip();
        } else {
          // Check if pause exceeded max duration
          final decision = await ref
              .read(tripStopDetectorProvider.notifier)
              .analyzeForTripStop(motion, location, pausedState.totalDuration);

          if (decision == StopDecision.stopTrip) {
            // Stop trip and finalize data
            await _finalizeTrip(pausedState);
            ref.read(tripStateMachineProvider.notifier).stopTrip();
          }
        }
      },
    );
  }

  Future<void> _finalizeTrip(TripState state) async {
    // Save trip to database
    // Calculate final statistics
    // Notify user of trip completion
  }
}
```

### 4. Configuration Constants

**Add to** `lib/core/constants/app_constants.dart`:

```dart
// Trip Stop Detection Configuration (T014)

// Minimum pause duration before considering pause (seconds)
// Brief stops (< this value) keep trip active
static const int minPauseDurationSeconds = 30; // 30s - traffic lights, intersections

// Maximum pause duration before auto-stop (seconds)
// Already defined above as maxPauseDurationSeconds = 300 (5 min)

// Minimum consecutive stationary detections before pause
static const int minConsecutiveStationaryDetections = 3;

// Stationary thresholds (already defined in T007)
// - stationaryAccelerationMax
// - stationaryRotationMax

// Minimum movement duration to resume trip (seconds)
// Already defined above as resumeMovementThresholdSeconds = 5
```

---

## Implementation Steps

### Step 1: Create State Model
```bash
# File: lib/features/trip_detection/domain/models/trip_stop_state.dart
```

1. Create freezed model for `TripStopState`
2. Include: stationary flag, pause timing, consecutive detections
3. Add `StopDecision` enum
4. Add factory constructor for initial state
5. Run code generation

**Test**:
```bash
flutter pub run build_runner build --delete-conflicting-outputs
flutter analyze
```

### Step 2: Implement Trip Stop Detector Service
```bash
# File: lib/features/trip_detection/data/services/trip_stop_detector.dart
```

1. Create Riverpod notifier provider
2. Implement `analyzeForTripStop()` method
3. Implement stationary detection logic
4. Add pause duration tracking
5. Implement resume detection logic
6. Add logging for debugging

**Test**:
```bash
flutter analyze
```

### Step 3: Update Trip Detection Coordinator
```bash
# File: lib/features/trip_detection/data/services/trip_detection_coordinator.dart
```

1. Add stop detection to coordinator
2. Implement state transition logic (Active → Paused → Stopped)
3. Add resume detection (Paused → Active)
4. Implement trip finalization on stop
5. Handle edge cases (GPS unavailable, sensor failures)

**Test**:
```bash
flutter analyze
```

### Step 4: Write Unit Tests
```bash
# File: test/features/trip_detection/data/services/trip_stop_detector_test.dart
```

**Test Cases**:
1. ✅ Detects stationary state with low motion + low GPS speed
2. ✅ Does NOT pause for brief stops (< 30s)
3. ✅ Pauses trip after 30s of stationary
4. ✅ Stops trip after 5 minutes of pause
5. ✅ Resumes trip when movement detected
6. ✅ Requires consecutive stationary detections
7. ✅ Handles GPS unavailability gracefully
8. ✅ Traffic light scenario: 15s stop → resume (no pause)
9. ✅ Rest stop scenario: 2 min stop → pause → resume
10. ✅ Trip end scenario: 10 min stationary → stop

**Example Test**:
```dart
test('should pause trip after 30 seconds of stationary', () async {
  final detector = TripStopDetector();

  // Create stationary motion data (low acceleration and rotation)
  final stationaryMotion = MotionData(
    accelerometer: AccelerometerData(
      x: 0.1, y: 0.1, z: 9.8, // ~9.8 m/s² (gravity only)
      timestamp: DateTime.now(),
    ),
    gyroscope: GyroscopeData(
      x: 0.05, y: 0.05, z: 0.05, // ~0.086 rad/s (very low rotation)
      timestamp: DateTime.now(),
    ),
    timestamp: DateTime.now(),
  );

  // Create stationary GPS data (0 km/h)
  final stationaryLocation = LocationData(
    latitude: 48.8566,
    longitude: 2.3522,
    accuracy: 10.0,
    altitude: 35.0,
    speed: 0.0, // m/s = 0 km/h
    heading: 90.0,
    timestamp: DateTime.now(),
  );

  // Analyze for 35 seconds (exceeds 30s threshold)
  final startTime = DateTime.now();
  while (DateTime.now().difference(startTime).inSeconds < 35) {
    await detector.analyzeForTripStop(
      stationaryMotion,
      stationaryLocation,
      Duration(minutes: 5), // Trip has been 5 minutes
    );
    await Future.delayed(Duration(seconds: 1));
  }

  // Should return pause decision
  final decision = await detector.analyzeForTripStop(
    stationaryMotion,
    stationaryLocation,
    Duration(minutes: 5),
  );

  expect(decision, equals(StopDecision.pauseTrip));
});

test('should NOT pause for brief traffic light stop', () async {
  final detector = TripStopDetector();

  // Stationary for 15 seconds (below 30s threshold)
  // ... analyze stationary motion for 15s ...

  final decision = await detector.analyzeForTripStop(
    stationaryMotion,
    stationaryLocation,
    Duration(minutes: 2),
  );

  // Should continue trip (brief pause)
  expect(decision, equals(StopDecision.continueTrip));
});

test('should stop trip after 5 minutes of pause', () async {
  final detector = TripStopDetector();

  // Simulate 5+ minutes of stationary
  // ... (use mock time or fast-forward) ...

  final decision = await detector.analyzeForTripStop(
    stationaryMotion,
    stationaryLocation,
    Duration(minutes: 10), // Trip total duration
  );

  expect(decision, equals(StopDecision.stopTrip));
});

test('should resume trip when movement detected after pause', () async {
  final detector = TripStopDetector();

  // First: Pause trip (stationary for 35s)
  // ... (similar to pause test) ...

  // Then: Detect movement
  final movingMotion = MotionData(
    accelerometer: AccelerometerData(
      x: 3.0, y: 3.0, z: 10.0, // Cycling motion
      timestamp: DateTime.now(),
    ),
    gyroscope: GyroscopeData(
      x: 1.0, y: 0.5, z: 0.5, // Pedaling rotation
      timestamp: DateTime.now(),
    ),
    timestamp: DateTime.now(),
  );

  final shouldResume = detector.shouldResumeTrip(movingMotion, null);
  expect(shouldResume, isTrue);
});
```

### Step 5: Integration Testing
```bash
# Physical device required!
```

1. Test on physical device (sensors required)
2. Test scenarios:
   - **Traffic light stop** (15-20s): Trip should remain active
   - **Intersection stop** (10s): Trip should remain active
   - **Brief rest** (1-2 min): Trip should pause, then resume when moving
   - **Lunch break** (10+ min): Trip should auto-stop
   - **Resume after pause**: Verify trip resumes correctly
3. Verify trip data is saved correctly on stop

---

## Edge Cases & Error Handling

### 1. GPS Unavailable During Stop Detection
- **Scenario**: No GPS signal (tunnel, indoors)
- **Handling**: Use motion-only detection with stricter thresholds
- **Implementation**: Require higher consecutive stationary detections

### 2. Brief Movement During Pause (Adjusting Bike)
- **Scenario**: User moves bike while stopped
- **Handling**: Brief motion doesn't immediately resume trip
- **Implementation**: Require sustained movement (5+ seconds) to resume

### 3. Sensor Data Gaps During Pause
- **Scenario**: Sensor stream interruption while paused
- **Handling**: Don't reset pause timer, continue tracking
- **Implementation**: Track last known state, resume on reconnect

### 4. Battery Died During Trip
- **Scenario**: Device powered off during active trip
- **Handling**: Auto-stop trip on next app launch
- **Implementation**: Check for incomplete trips on startup

### 5. Long Downhill (Low Motion, High Speed)
- **Scenario**: Coasting downhill - low pedaling but high speed
- **Handling**: GPS speed prevents false stop
- **Implementation**: Speed validation overrides motion thresholds

### 6. Bike Transport (In Car/Train)
- **Scenario**: Bike moved without cycling (high speed, no pedaling motion)
- **Handling**: Already handled by T013 (won't start), but if mid-trip, detect anomaly
- **Implementation**: Speed > 40 km/h triggers anomaly check

---

## Quality Gates

**Before marking complete**:

1. ✅ Code generation successful (`build_runner`)
2. ✅ `flutter analyze` passes with no errors
3. ✅ All unit tests pass
4. ✅ Physical device testing completed:
   - ✅ Traffic light stops don't pause trip
   - ✅ Brief rest pauses and resumes correctly
   - ✅ Extended pause auto-stops trip
   - ✅ Trip data saved correctly on stop
   - ✅ Resume works after pause
5. ✅ Edge cases handled gracefully
6. ✅ Constants tuned for real-world usage
7. ✅ Code follows existing patterns (freezed, Riverpod)
8. ✅ Documentation comments added
9. ✅ Integration with trip state machine working
10. ✅ Trip finalization triggers correctly

---

## Testing Checklist

### Unit Tests
- [ ] Stationary detection with low motion + GPS
- [ ] Brief stop (< 30s) does not pause trip
- [ ] Pause triggered after 30s stationary
- [ ] Stop triggered after 5 minutes pause
- [ ] Resume detection with movement
- [ ] Consecutive stationary detection counting
- [ ] GPS unavailable handled correctly
- [ ] Pause duration calculation accurate

### Physical Device Tests
- [ ] **Traffic light scenario**: 15s stop → continue (no pause)
- [ ] **Intersection scenario**: 10s stop → continue (no pause)
- [ ] **Brief rest scenario**: 1 min stop → pause → resume when moving
- [ ] **Extended rest scenario**: 5+ min stop → auto-stop trip
- [ ] **Downhill coasting**: Low motion, high speed → no false stop
- [ ] Trip data correctly saved to database on stop
- [ ] Pause/resume transitions smooth
- [ ] Notification updates on pause/resume/stop

---

## File Checklist

**Files to Create**:
- [ ] `lib/features/trip_detection/domain/models/trip_stop_state.dart`
- [ ] `lib/features/trip_detection/data/services/trip_stop_detector.dart`
- [ ] `test/features/trip_detection/data/services/trip_stop_detector_test.dart`

**Files to Modify**:
- [ ] `lib/core/constants/app_constants.dart` (add TripStopDetection constants)
- [ ] `lib/features/trip_detection/data/services/trip_detection_coordinator.dart` (add stop detection logic)
- [ ] `lib/features/trip_detection/data/services/trip_state_machine.dart` (ensure pause/resume/stop transitions)

**Files to Generate**:
- [ ] `lib/features/trip_detection/domain/models/trip_stop_state.freezed.dart` (freezed)
- [ ] `lib/features/trip_detection/data/services/trip_stop_detector.g.dart` (riverpod)

---

## Integration Points

### With Trip State Machine (T012)
- Active → Paused transition (30s stationary)
- Paused → Active transition (movement detected)
- Paused → Stopped transition (5 min pause)
- Stopped state triggers trip finalization

### With Trip Repository (T010)
- Save trip to database on stop
- Calculate final statistics (distance, duration, avg speed)
- Mark trip as complete

### With Battery Optimizer (T006)
- Reduce sensor/GPS frequency during pause
- Restore normal frequency on resume

### With Background Service (T005)
- Update foreground notification on pause/resume/stop
- Handle service lifecycle during state transitions

---

## Success Criteria

**Functional**:
- ✅ Trip automatically pauses after 30s stationary
- ✅ Trip automatically stops after 5 min pause
- ✅ Trip resumes correctly when movement detected
- ✅ Brief stops (traffic lights) don't trigger pause
- ✅ Trip data saved correctly on stop

**Technical**:
- ✅ Clean state transitions (no race conditions)
- ✅ Accurate pause duration tracking
- ✅ Efficient resource usage during pause
- ✅ Proper error handling and edge cases

**User Experience**:
- ✅ Intuitive behavior (matches user expectations)
- ✅ Clear notifications for pause/resume/stop
- ✅ No false stops during normal cycling
- ✅ Reasonable auto-stop timeout (5 min)

---

## Constants Reference

**From `AppConstants`**:
```dart
// Pause/Stop Thresholds
static const int minPauseDurationSeconds = 30;           // T014 - brief pause threshold
static const int maxPauseDurationSeconds = 300;          // Existing - auto-stop timeout
static const int resumeMovementThresholdSeconds = 5;     // Existing - resume threshold

// Stationary Detection (from T007)
static const double stationaryAccelerationMax = 1.0;     // m/s²
static const double stationaryRotationMax = 0.2;         // rad/s

// Consecutive Detections
static const int minConsecutiveStationaryDetections = 3; // T014 - prevent spikes
```

---

## Related Tasks

**Dependencies**:
- ✅ T013: Automatic Trip Start Detection (provides detection patterns)
- ✅ T012: Trip State Machine (provides state transitions)
- ✅ T010: Trip Repository (for saving trip data)
- ✅ T007: Sensor Integration (provides motion data)
- ✅ T004: Location Service (provides GPS data)

**Depends On This**:
- T015: Trip Data Recording (uses stop detection to finalize trips)
- T022: Trip Tracking Screen (shows pause/resume/stop states)
- T025: Notifications (updates notification on state changes)

---

## Notes

**Design Philosophy**:
- **User Intent First**: Brief stops (traffic lights) are part of the trip
- **Battery Aware**: Reduce resource usage during pause
- **Fail Safe**: Better to auto-stop late than stop mid-trip
- **Clear Feedback**: User knows when trip paused vs. stopped

**Tuning Parameters** (may require adjustment):
- `minPauseDurationSeconds = 30`: Prevents traffic light false pauses
- `maxPauseDurationSeconds = 300`: 5 min is reasonable break threshold
- `resumeMovementThresholdSeconds = 5`: Ensures intentional resume

**Future Enhancements** (out of scope):
- Manual pause/resume controls (UI task)
- Pause location marking (show where pauses occurred)
- Trip splitting (split long trip into segments)
- Smart timeout based on trip duration

---

**Last Updated**: 2025-11-22
**Author**: Claude Code
**Related Commit**: (to be added on completion)
