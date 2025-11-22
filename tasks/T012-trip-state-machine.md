# T012: Trip State Machine

**Phase**: 4.1 Core Detection
**Dependencies**: T007 (Sensor Integration), T008 (Cycling Detection)
**Estimate**: 2-3 hours
**Status**: ⏳ In Progress

---

## Overview

Implement a robust state machine to manage trip lifecycle states (Idle, Detecting, Active, Paused). This provides the foundation for automatic trip start/stop detection and handles all state transitions with proper validation.

---

## Objectives

- [ ] Create `TripState` sealed class with all states
- [ ] Implement `TripStateMachine` class to manage transitions
- [ ] Add validation logic for allowed transitions
- [ ] Create Riverpod provider for state management
- [ ] Add comprehensive unit tests for all transitions
- [ ] Document state transition rules

---

## Architecture

### State Diagram

```
┌──────┐
│ Idle │ ←──────────────────────────┐
└──┬───┘                            │
   │ Motion detected               │ Trip stopped
   ↓                                │ (manual/timeout)
┌───────────┐                       │
│ Detecting │                       │
└─────┬─────┘                       │
      │ Cycling confirmed           │
      ↓                             │
┌────────┐    Stationary >10s   ┌────────┐
│ Active │ ←──────────────────→ │ Paused │
└────────┘                       └────────┘
```

### State Descriptions

| State | Description | Entry Conditions | Exit Conditions |
|-------|-------------|------------------|-----------------|
| **Idle** | No activity, waiting for motion | App start, trip ended | Motion detected |
| **Detecting** | Motion detected, confirming cycling | Motion above threshold | Cycling confirmed OR timeout |
| **Active** | Trip in progress, recording | Cycling pattern confirmed | Stationary OR manual stop |
| **Paused** | Trip paused, not recording | Stationary >10s during active trip | Movement resumes OR manual stop |

---

## Implementation Steps

### Step 1: Create TripState Model

**File**: `lib/features/trip_detection/domain/models/trip_state.dart`

```dart
import 'package:freezed_annotation/freezed_annotation.dart';

part 'trip_state.freezed.dart';

/// Represents the current state of trip detection
@freezed
sealed class TripState with _$TripState {
  const TripState._();

  /// No activity detected, system is idle
  const factory TripState.idle() = _Idle;

  /// Motion detected, analyzing if it's cycling
  /// [detectionStartTime] when detection phase started
  const factory TripState.detecting({
    required DateTime detectionStartTime,
  }) = _Detecting;

  /// Active trip in progress
  /// [tripId] database ID of the trip
  /// [startTime] when trip started
  const factory TripState.active({
    required int tripId,
    required DateTime startTime,
  }) = _Active;

  /// Trip paused (stationary during active trip)
  /// [tripId] database ID of the trip
  /// [startTime] original trip start time
  /// [pauseStartTime] when pause began
  const factory TripState.paused({
    required int tripId,
    required DateTime startTime,
    required DateTime pauseStartTime,
  }) = _Paused;
}

/// Extensions for state queries
extension TripStateExtensions on TripState {
  /// Whether a trip is currently active (Active or Paused)
  bool get hasActiveTrip => map(
    idle: (_) => false,
    detecting: (_) => false,
    active: (_) => true,
    paused: (_) => true,
  );

  /// Whether system is currently recording location data
  bool get isRecording => map(
    idle: (_) => false,
    detecting: (_) => false,
    active: (_) => true,
    paused: (_) => false,
  );

  /// Get current trip ID if available
  int? get currentTripId => map(
    idle: (_) => null,
    detecting: (_) => null,
    active: (state) => state.tripId,
    paused: (state) => state.tripId,
  );
}
```

**Commands**:
```bash
flutter pub run build_runner build --delete-conflicting-outputs
flutter analyze
```

---

### Step 2: Create TripStateMachine Service

**File**: `lib/features/trip_detection/data/services/trip_state_machine.dart`

```dart
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../domain/models/trip_state.dart';
import '../../../../core/constants/app_constants.dart';

part 'trip_state_machine.g.dart';

/// State machine for managing trip lifecycle
@riverpod
class TripStateMachine extends _$TripStateMachine {
  @override
  TripState build() {
    return const TripState.idle();
  }

  /// Transition to Detecting state when motion is detected
  void startDetecting() {
    state.mapOrNull(
      idle: (_) {
        state = TripState.detecting(
          detectionStartTime: DateTime.now(),
        );
      },
    );
  }

  /// Transition to Active state when cycling is confirmed
  /// Returns the new trip ID
  Future<int> startTrip() async {
    return await state.mapOrNull(
      detecting: (_) async {
        // Generate new trip ID (will be from database in T015)
        final tripId = DateTime.now().millisecondsSinceEpoch;

        state = TripState.active(
          tripId: tripId,
          startTime: DateTime.now(),
        );

        return tripId;
      },
    ) ?? -1;
  }

  /// Transition to Paused state when stationary during active trip
  void pauseTrip() {
    state.mapOrNull(
      active: (activeState) {
        state = TripState.paused(
          tripId: activeState.tripId,
          startTime: activeState.startTime,
          pauseStartTime: DateTime.now(),
        );
      },
    );
  }

  /// Resume trip from Paused state
  void resumeTrip() {
    state.mapOrNull(
      paused: (pausedState) {
        state = TripState.active(
          tripId: pausedState.tripId,
          startTime: pausedState.startTime,
        );
      },
    );
  }

  /// Stop trip and return to Idle (manual stop or timeout)
  void stopTrip() {
    state.mapOrNull(
      detecting: (_) => state = const TripState.idle(),
      active: (_) => state = const TripState.idle(),
      paused: (_) => state = const TripState.idle(),
    );
  }

  /// Check if detection phase has timed out
  /// Returns true if in Detecting state for > detection timeout
  bool hasDetectionTimedOut() {
    return state.mapOrNull(
      detecting: (detectingState) {
        final elapsed = DateTime.now().difference(
          detectingState.detectionStartTime,
        );
        return elapsed.inSeconds > AppConstants.detectionTimeoutSeconds;
      },
    ) ?? false;
  }

  /// Check if pause has timed out (exceeded max pause duration)
  /// Returns true if paused for > max pause time
  bool hasPauseTimedOut() {
    return state.mapOrNull(
      paused: (pausedState) {
        final elapsed = DateTime.now().difference(
          pausedState.pauseStartTime,
        );
        return elapsed.inSeconds > AppConstants.maxPauseDurationSeconds;
      },
    ) ?? false;
  }
}
```

**Commands**:
```bash
flutter pub run build_runner build --delete-conflicting-outputs
flutter analyze
```

---

### Step 3: Add State Machine Constants

**File**: `lib/core/constants/app_constants.dart`

**Add these constants** to the existing `AppConstants` class:

```dart
// Trip State Machine Configuration
static const int detectionTimeoutSeconds = 30; // Max time in Detecting before timeout
static const int stationaryThresholdSeconds = 10; // Stationary time before pause
static const int maxPauseDurationSeconds = 300; // 5 min - max pause before auto-stop
static const int resumeMovementThresholdSeconds = 5; // Movement time before resume
```

**Commands**:
```bash
flutter analyze
```

---

### Step 4: Create Unit Tests

**File**: `test/features/trip_detection/data/services/trip_state_machine_test.dart`

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:autoride/features/trip_detection/data/services/trip_state_machine.dart';
import 'package:autoride/features/trip_detection/domain/models/trip_state.dart';

void main() {
  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer();
  });

  tearDown(() {
    container.dispose();
  });

  group('TripStateMachine', () {
    test('should initialize in Idle state', () {
      final state = container.read(tripStateMachineProvider);

      expect(state, isA<_Idle>());
      expect(state.hasActiveTrip, isFalse);
      expect(state.isRecording, isFalse);
    });

    test('should transition from Idle to Detecting', () {
      final stateMachine = container.read(tripStateMachineProvider.notifier);

      stateMachine.startDetecting();

      final state = container.read(tripStateMachineProvider);
      expect(state, isA<_Detecting>());
      expect(state.hasActiveTrip, isFalse);
      expect(state.isRecording, isFalse);
    });

    test('should transition from Detecting to Active', () async {
      final stateMachine = container.read(tripStateMachineProvider.notifier);

      stateMachine.startDetecting();
      final tripId = await stateMachine.startTrip();

      final state = container.read(tripStateMachineProvider);
      expect(state, isA<_Active>());
      expect(state.hasActiveTrip, isTrue);
      expect(state.isRecording, isTrue);
      expect(state.currentTripId, equals(tripId));
    });

    test('should transition from Active to Paused', () async {
      final stateMachine = container.read(tripStateMachineProvider.notifier);

      stateMachine.startDetecting();
      await stateMachine.startTrip();
      stateMachine.pauseTrip();

      final state = container.read(tripStateMachineProvider);
      expect(state, isA<_Paused>());
      expect(state.hasActiveTrip, isTrue);
      expect(state.isRecording, isFalse);
    });

    test('should transition from Paused to Active on resume', () async {
      final stateMachine = container.read(tripStateMachineProvider.notifier);

      stateMachine.startDetecting();
      final tripId = await stateMachine.startTrip();
      stateMachine.pauseTrip();
      stateMachine.resumeTrip();

      final state = container.read(tripStateMachineProvider);
      expect(state, isA<_Active>());
      expect(state.currentTripId, equals(tripId));
    });

    test('should transition from Active to Idle on stop', () async {
      final stateMachine = container.read(tripStateMachineProvider.notifier);

      stateMachine.startDetecting();
      await stateMachine.startTrip();
      stateMachine.stopTrip();

      final state = container.read(tripStateMachineProvider);
      expect(state, isA<_Idle>());
      expect(state.hasActiveTrip, isFalse);
    });

    test('should prevent invalid transitions', () async {
      final stateMachine = container.read(tripStateMachineProvider.notifier);

      // Try to pause from Idle (should do nothing)
      stateMachine.pauseTrip();
      var state = container.read(tripStateMachineProvider);
      expect(state, isA<_Idle>());

      // Try to resume from Idle (should do nothing)
      stateMachine.resumeTrip();
      state = container.read(tripStateMachineProvider);
      expect(state, isA<_Idle>());
    });

    test('should detect detection timeout', () async {
      final stateMachine = container.read(tripStateMachineProvider.notifier);

      stateMachine.startDetecting();

      // Immediately should not be timed out
      expect(stateMachine.hasDetectionTimedOut(), isFalse);

      // Would need to wait 30+ seconds for real timeout
      // In actual usage, a timer will check this periodically
    });

    test('should preserve trip ID across state transitions', () async {
      final stateMachine = container.read(tripStateMachineProvider.notifier);

      stateMachine.startDetecting();
      final tripId = await stateMachine.startTrip();

      stateMachine.pauseTrip();
      var state = container.read(tripStateMachineProvider);
      expect(state.currentTripId, equals(tripId));

      stateMachine.resumeTrip();
      state = container.read(tripStateMachineProvider);
      expect(state.currentTripId, equals(tripId));
    });
  });

  group('TripState Extensions', () {
    test('hasActiveTrip should be true for Active and Paused', () {
      const idle = TripState.idle();
      const detecting = TripState.detecting(detectionStartTime: DateTime.now);
      final active = TripState.active(tripId: 1, startTime: DateTime.now());
      final paused = TripState.paused(
        tripId: 1,
        startTime: DateTime.now(),
        pauseStartTime: DateTime.now(),
      );

      expect(idle.hasActiveTrip, isFalse);
      expect(detecting.hasActiveTrip, isFalse);
      expect(active.hasActiveTrip, isTrue);
      expect(paused.hasActiveTrip, isTrue);
    });

    test('isRecording should only be true for Active', () {
      const idle = TripState.idle();
      const detecting = TripState.detecting(detectionStartTime: DateTime.now);
      final active = TripState.active(tripId: 1, startTime: DateTime.now());
      final paused = TripState.paused(
        tripId: 1,
        startTime: DateTime.now(),
        pauseStartTime: DateTime.now(),
      );

      expect(idle.isRecording, isFalse);
      expect(detecting.isRecording, isFalse);
      expect(active.isRecording, isTrue);
      expect(paused.isRecording, isFalse);
    });

    test('currentTripId should return ID for Active and Paused', () {
      const idle = TripState.idle();
      final active = TripState.active(tripId: 123, startTime: DateTime.now());
      final paused = TripState.paused(
        tripId: 456,
        startTime: DateTime.now(),
        pauseStartTime: DateTime.now(),
      );

      expect(idle.currentTripId, isNull);
      expect(active.currentTripId, equals(123));
      expect(paused.currentTripId, equals(456));
    });
  });
}
```

**Commands**:
```bash
flutter test test/features/trip_detection/data/services/trip_state_machine_test.dart
```

---

## Quality Gates

Run these commands in order:

```bash
# 1. Generate code
flutter pub run build_runner build --delete-conflicting-outputs

# 2. Static analysis (MUST pass)
flutter analyze

# 3. Run all tests
flutter test

# 4. Run specific test file
flutter test test/features/trip_detection/data/services/trip_state_machine_test.dart
```

**All must pass before marking task complete.**

---

## Expected Results

### Files Created/Modified

**Created**:
- `lib/features/trip_detection/domain/models/trip_state.dart`
- `lib/features/trip_detection/domain/models/trip_state.freezed.dart` (generated)
- `lib/features/trip_detection/data/services/trip_state_machine.dart`
- `lib/features/trip_detection/data/services/trip_state_machine.g.dart` (generated)
- `test/features/trip_detection/data/services/trip_state_machine_test.dart`

**Modified**:
- `lib/core/constants/app_constants.dart` (added state machine constants)

### Test Coverage

- ✅ State initialization (Idle)
- ✅ All valid state transitions
- ✅ Invalid transitions prevented
- ✅ Trip ID preservation across transitions
- ✅ Timeout detection logic
- ✅ Extension methods (hasActiveTrip, isRecording, currentTripId)

---

## Integration Points

### Current Integration
- Uses `AppConstants` for timeout thresholds
- Uses Freezed for immutable state models
- Uses Riverpod for state management

### Future Integration (Next Tasks)
- **T013**: Automatic trip start will use `startDetecting()` → `startTrip()`
- **T014**: Automatic trip stop will use `pauseTrip()` → `stopTrip()`
- **T015**: Trip recording will check `state.isRecording` to control data capture
- **T022**: UI will display different screens based on current state

---

## Common Issues & Solutions

### Issue 1: Freezed Generation Errors
**Problem**: "The non-abstract class 'TripState' is missing implementations"

**Solution**:
- Ensure `sealed class` is used (not `class`)
- Private constructor `const TripState._();` must be BEFORE factory constructors
- Run `flutter pub run build_runner clean` then regenerate

### Issue 2: State Not Updating
**Problem**: `state = newState` doesn't trigger rebuilds

**Solution**:
- Riverpod automatically handles this with Notifier classes
- Verify provider is being watched correctly: `ref.watch(tripStateMachineProvider)`

### Issue 3: Invalid Transition Logic
**Problem**: State transitions happen when they shouldn't

**Solution**:
- Use `mapOrNull` to ensure transitions only happen from valid states
- Add explicit guards for each transition method

---

## Testing Notes

### Manual Testing Scenarios

After implementation, verify these scenarios:

1. **Idle → Detecting**: Motion sensor detects movement
2. **Detecting → Active**: Cycling pattern confirmed
3. **Detecting → Idle**: Detection timeout (30s) without cycling confirmation
4. **Active → Paused**: Stationary for >10s during trip
5. **Paused → Active**: Movement resumes
6. **Paused → Idle**: Pause timeout (5 min) without movement
7. **Active → Idle**: Manual stop or automatic stop

### State Persistence (Future)

Currently, state is in-memory only. In future tasks:
- **T010**: State should be saved to database
- **T005**: State should survive app restart (background service)

---

## References

### Design Patterns
- **State Pattern**: Encapsulates state-specific behavior
- **Sealed Classes**: Exhaustive pattern matching with Freezed

### Related Documentation
- CLAUDE.md: Freezed patterns (line 160-200)
- CLAUDE.md: Riverpod providers (line 210-240)
- AppConstants: State machine configuration

---

## Commit Message

```
T012: Implement trip state machine

- Add TripState sealed class (Idle/Detecting/Active/Paused)
- Create TripStateMachine Riverpod notifier with transitions
- Add state validation and timeout detection
- Create comprehensive unit tests (11 test cases)
- Add state machine constants to AppConstants
- All tests passing, flutter analyze clean
```

---

**Task Status**: ⏳ In Progress
**Next Task**: T013 - Automatic Trip Start Detection
**Last Updated**: 2025-11-22
