# T015 - Trip Data Recording

**Status**: ⏳ In Progress
**Priority**: High
**Estimated Time**: 2-3 hours
**Dependencies**: T010 (Trip Repository), T013 (Trip Start Detection)

---

## Overview

Implement the trip recording service that captures GPS route points during active trips and calculates real-time metrics (distance, duration, average speed, max speed). This is the core functionality that turns motion detection into actual trip data.

---

## Goals

1. **Record route points** during active trips with efficient buffering
2. **Calculate metrics** in real-time (distance, duration, speeds)
3. **Handle pause/resume** correctly (exclude pause from duration)
4. **Optimize performance** with batch database saves and memory management
5. **Ensure accuracy** with GPS filtering and outlier rejection

---

## Architecture

### Data Flow

```
TripStartDetector (T013)
  ↓ shouldStartTrip() == true
TripRecorderService.startRecording()
  ↓ repository.saveTrip() → get DB trip ID
  ↓ stateMachine.state = active(dbTripId)
  ↓ locationStream subscription starts
  ↓
FOR EACH location update:
  ↓ filter by distance (15m) and accuracy (50m)
  ↓ convert LocationData → RoutePoint
  ↓ add to buffer
  ↓ update metrics (distance, duration, speeds)
  ↓ IF buffer full OR 60s elapsed: batch save to DB
  ↓
TripStopDetector (T014)
  ↓ shouldStopTrip() == true
TripRecorderService.stopRecording()
  ↓ flush remaining buffer
  ↓ calculate final metrics
  ↓ repository.updateTrip(finalTrip)
  ↓ stateMachine.stopTrip()
  ↓ cancel location subscription
```

### Component Responsibilities

**TripRecorderService** (NEW):
- Coordinate recording lifecycle
- Manage location stream subscription
- Buffer route points and batch save
- Calculate real-time metrics
- Handle pause/resume state

**TripStateMachine** (ENHANCED):
- Accept database trip ID (not temp ID)
- Provide `isRecording` flag
- Manage state transitions

**TripRepository** (EXISTING):
- Save/update trips
- Batch save route points
- Query trip history

**LocationService** (EXISTING):
- Stream GPS location updates
- Provide location accuracy data

---

## Implementation Steps

### Step 1: Add Constants to AppConstants

**File**: `lib/core/constants/app_constants.dart`

**Add to class**:
```dart
// Trip Recording Configuration
static const double minRoutePointDistanceMeters = 15.0; // Cycling optimal
static const int routePointBufferSize = 100; // Buffer before batch save
static const int maxRecordingIntervalSeconds = 30; // Fallback flush interval
static const double maxLocationAccuracyMeters = 50.0; // Reject poor GPS
static const double maxCyclingSpeedKmh = 60.0; // Outlier rejection
```

**Rationale**:
- 15m distance filter: Optimal for cycling, prevents GPS drift duplicates
- 100 route points: ~2KB memory, saves every ~1.5km at 15m intervals
- 30s interval: Ensures data persistence even if distance filter not triggered
- 50m accuracy: Reject poor GPS fixes
- 60 km/h max: Cycling trips shouldn't exceed this (outlier detection)

---

### Step 2: Enhance TripStateMachine

**File**: `lib/features/trip_detection/data/services/trip_state_machine.dart`

**Current signature** (uses temp ID):
```dart
Future<int> startTrip() async {
  final tripId = DateTime.now().millisecondsSinceEpoch; // ❌ Not DB ID
  state = TripState.active(tripId: tripId, startTime: DateTime.now());
  return tripId;
}
```

**Updated signature** (accepts DB ID):
```dart
void startTripWithId(int tripId) {
  state = TripState.active(
    tripId: tripId,
    startTime: DateTime.now(),
  );
}
```

**Key changes**:
- Remove ID generation logic (handled by database)
- Accept trip ID as parameter
- Change return type to `void` (ID comes from caller)
- Rename to `startTripWithId` for clarity

**Note**: The recorder service will create the trip in the database first, then call this method with the real database ID.

---

### Step 3: Create TripRecorderService

**File**: `lib/features/trip_detection/data/services/trip_recorder_service.dart`

#### Full Implementation

```dart
import 'dart:async';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../domain/models/location_data.dart';
import '../../domain/models/trip.dart';
import '../../../trip_history/data/repositories/trip_repository.dart';
import '../../../../core/constants/app_constants.dart';
import 'trip_state_machine.dart';
import 'location_service.dart';

part 'trip_recorder_service.g.dart';

/// Real-time trip metrics exposed to UI
class TripMetrics {
  final double distanceMeters;
  final int durationSeconds;
  final double? avgSpeedKmh;
  final double? maxSpeedKmh;
  final int routePointCount;

  const TripMetrics({
    required this.distanceMeters,
    required this.durationSeconds,
    this.avgSpeedKmh,
    this.maxSpeedKmh,
    required this.routePointCount,
  });

  TripMetrics copyWith({
    double? distanceMeters,
    int? durationSeconds,
    double? avgSpeedKmh,
    double? maxSpeedKmh,
    int? routePointCount,
  }) {
    return TripMetrics(
      distanceMeters: distanceMeters ?? this.distanceMeters,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      avgSpeedKmh: avgSpeedKmh ?? this.avgSpeedKmh,
      maxSpeedKmh: maxSpeedKmh ?? this.maxSpeedKmh,
      routePointCount: routePointCount ?? this.routePointCount,
    );
  }

  double get distanceKm => distanceMeters / 1000.0;

  String get formattedDistance {
    if (distanceKm < 1) {
      return '${distanceMeters.toStringAsFixed(0)} m';
    }
    return '${distanceKm.toStringAsFixed(2)} km';
  }

  String get formattedDuration {
    final hours = durationSeconds ~/ 3600;
    final minutes = (durationSeconds % 3600) ~/ 60;
    final seconds = durationSeconds % 60;

    if (hours > 0) {
      return '${hours}h ${minutes}m ${seconds}s';
    } else if (minutes > 0) {
      return '${minutes}m ${seconds}s';
    }
    return '${seconds}s';
  }
}

@riverpod
class TripRecorderService extends _$TripRecorderService {
  // Dependencies
  late TripRepository _repository;
  late TripStateMachine _stateMachine;

  // State
  Trip? _activeTrip;
  List<RoutePoint> _routePointBuffer = [];
  StreamSubscription<LocationData>? _locationSubscription;
  LocationData? _lastLocation;
  Timer? _flushTimer;

  // Pause tracking
  DateTime? _pauseStartTime;
  int _totalPauseDurationSeconds = 0;

  // Metrics
  double _totalDistanceMeters = 0.0;
  double _maxSpeedKmh = 0.0;

  @override
  TripMetrics build() {
    // Initialize dependencies
    _repository = ref.read(tripRepositoryProvider);
    _stateMachine = ref.read(tripStateMachineProvider.notifier);

    // Listen to state machine changes
    ref.listen(tripStateMachineProvider, (previous, next) {
      _handleStateChange(previous, next);
    });

    return const TripMetrics(
      distanceMeters: 0.0,
      durationSeconds: 0,
      avgSpeedKmh: null,
      maxSpeedKmh: null,
      routePointCount: 0,
    );
  }

  /// Start recording a new trip
  Future<void> startRecording({
    required double confidenceScore,
    required ActivityType activity,
  }) async {
    if (_activeTrip != null) {
      throw StateError('Trip already recording');
    }

    // Create initial trip in database
    final initialTrip = Trip(
      startTime: DateTime.now(),
      endTime: DateTime.now(), // Temporary
      distance: 0.0,
      duration: 0,
      avgSpeed: null,
      maxSpeed: null,
      detectedActivity: activity,
      confidenceScore: confidenceScore,
      routePoints: [],
    );

    // Save to database to get real ID
    _activeTrip = await _repository.saveTrip(initialTrip);

    // Update state machine with database ID
    _stateMachine.startTripWithId(_activeTrip!.id!);

    // Reset metrics
    _totalDistanceMeters = 0.0;
    _maxSpeedKmh = 0.0;
    _totalPauseDurationSeconds = 0;
    _lastLocation = null;
    _routePointBuffer.clear();

    // Start location stream
    _startLocationStream();

    // Start flush timer (backup for distance filter)
    _startFlushTimer();

    // Update UI state
    _updateMetrics();
  }

  /// Pause trip recording
  Future<void> pauseRecording() async {
    if (_activeTrip == null) return;

    _pauseStartTime = DateTime.now();
    _stateMachine.pauseTrip();

    // Don't cancel location stream, just stop recording points
    // This allows us to detect resume (motion) faster
  }

  /// Resume trip recording
  Future<void> resumeRecording() async {
    if (_activeTrip == null || _pauseStartTime == null) return;

    // Calculate pause duration
    final pauseDuration = DateTime.now().difference(_pauseStartTime!);
    _totalPauseDurationSeconds += pauseDuration.inSeconds;
    _pauseStartTime = null;

    _stateMachine.resumeTrip();
    _updateMetrics();
  }

  /// Stop recording and save final trip
  Future<Trip> stopRecording() async {
    if (_activeTrip == null) {
      throw StateError('No active trip to stop');
    }

    // If still paused, calculate final pause duration
    if (_pauseStartTime != null) {
      final pauseDuration = DateTime.now().difference(_pauseStartTime!);
      _totalPauseDurationSeconds += pauseDuration.inSeconds;
      _pauseStartTime = null;
    }

    // Flush remaining route points
    await _flushRoutePointBuffer();

    // Calculate final metrics
    final endTime = DateTime.now();
    final totalDuration = endTime.difference(_activeTrip!.startTime).inSeconds;
    final activeDuration = totalDuration - _totalPauseDurationSeconds;
    final avgSpeed = activeDuration > 0
        ? (_totalDistanceMeters / activeDuration) * 3.6 // m/s to km/h
        : null;

    // Update trip with final metrics
    final finalTrip = _activeTrip!.copyWith(
      endTime: endTime,
      distance: _totalDistanceMeters,
      duration: activeDuration,
      avgSpeed: avgSpeed,
      maxSpeed: _maxSpeedKmh > 0 ? _maxSpeedKmh : null,
    );

    await _repository.updateTrip(finalTrip);

    // Cleanup
    _stopLocationStream();
    _stopFlushTimer();
    _activeTrip = null;
    _routePointBuffer.clear();
    _lastLocation = null;
    _totalDistanceMeters = 0.0;
    _maxSpeedKmh = 0.0;
    _totalPauseDurationSeconds = 0;

    // Update state machine
    _stateMachine.stopTrip();

    // Reset UI metrics
    state = const TripMetrics(
      distanceMeters: 0.0,
      durationSeconds: 0,
      avgSpeedKmh: null,
      maxSpeedKmh: null,
      routePointCount: 0,
    );

    return finalTrip;
  }

  /// Handle state machine changes
  void _handleStateChange(TripState? previous, TripState next) {
    // This allows external state changes to trigger recording actions
    // For example, manual pause/resume from UI
    if (previous?.isRecording == true && next.isRecording == false) {
      // Paused
      if (_pauseStartTime == null) {
        _pauseStartTime = DateTime.now();
      }
    } else if (previous?.isRecording == false && next.isRecording == true) {
      // Resumed
      if (_pauseStartTime != null) {
        final pauseDuration = DateTime.now().difference(_pauseStartTime!);
        _totalPauseDurationSeconds += pauseDuration.inSeconds;
        _pauseStartTime = null;
      }
    }
  }

  /// Start location stream subscription
  void _startLocationStream() {
    // Get location stream with appropriate settings
    final stream = ref.read(locationStreamProvider());

    _locationSubscription = stream.listen(
      _handleLocationUpdate,
      onError: (error) {
        // Log error but continue recording
        // TODO: Add proper error logging
      },
    );
  }

  /// Stop location stream subscription
  void _stopLocationStream() {
    _locationSubscription?.cancel();
    _locationSubscription = null;
  }

  /// Handle new location update
  void _handleLocationUpdate(LocationData location) {
    if (_activeTrip == null) return;

    // Don't record during pause
    final currentState = ref.read(tripStateMachineProvider);
    if (!currentState.isRecording) return;

    // Filter by accuracy
    if (location.accuracy > AppConstants.maxLocationAccuracyMeters) {
      return; // Poor GPS fix, skip
    }

    // Filter by speed (outlier rejection)
    if (location.speedKmh > AppConstants.maxCyclingSpeedKmh) {
      return; // Unlikely for cycling, probably GPS error
    }

    // Filter by distance
    if (_lastLocation != null) {
      final distance = location.distanceTo(_lastLocation!);

      // Skip if too close (GPS drift)
      if (distance < AppConstants.minRoutePointDistanceMeters) {
        return;
      }

      // Update total distance
      _totalDistanceMeters += distance;
    }

    // Update max speed
    if (location.speedKmh > _maxSpeedKmh) {
      _maxSpeedKmh = location.speedKmh;
    }

    // Create route point
    final routePoint = RoutePoint.fromLocationData(
      location,
      _activeTrip!.id!,
    );

    // Add to buffer
    _routePointBuffer.add(routePoint);
    _lastLocation = location;

    // Update UI metrics
    _updateMetrics();

    // Flush if buffer full
    if (_routePointBuffer.length >= AppConstants.routePointBufferSize) {
      _flushRoutePointBuffer();
    }
  }

  /// Flush route point buffer to database
  Future<void> _flushRoutePointBuffer() async {
    if (_routePointBuffer.isEmpty) return;

    try {
      await _repository.saveRoutePoints(_routePointBuffer);
      _routePointBuffer.clear();
    } catch (e) {
      // TODO: Add proper error handling
      // For now, keep points in buffer and retry on next flush
    }
  }

  /// Start periodic flush timer
  void _startFlushTimer() {
    _flushTimer = Timer.periodic(
      Duration(seconds: AppConstants.maxRecordingIntervalSeconds),
      (_) => _flushRoutePointBuffer(),
    );
  }

  /// Stop flush timer
  void _stopFlushTimer() {
    _flushTimer?.cancel();
    _flushTimer = null;
  }

  /// Update UI metrics
  void _updateMetrics() {
    if (_activeTrip == null) return;

    final now = DateTime.now();
    final totalDuration = now.difference(_activeTrip!.startTime).inSeconds;

    // Calculate active duration (exclude pauses)
    int activeDuration = totalDuration - _totalPauseDurationSeconds;
    if (_pauseStartTime != null) {
      // Currently paused - exclude current pause duration
      final currentPauseDuration = now.difference(_pauseStartTime!).inSeconds;
      activeDuration -= currentPauseDuration;
    }

    final avgSpeed = activeDuration > 0
        ? (_totalDistanceMeters / activeDuration) * 3.6 // m/s to km/h
        : null;

    state = TripMetrics(
      distanceMeters: _totalDistanceMeters,
      durationSeconds: activeDuration,
      avgSpeedKmh: avgSpeed,
      maxSpeedKmh: _maxSpeedKmh > 0 ? _maxSpeedKmh : null,
      routePointCount: _routePointBuffer.length,
    );
  }

  @override
  void dispose() {
    _stopLocationStream();
    _stopFlushTimer();
    super.dispose();
  }
}
```

---

### Step 4: Integration with Trip Start/Stop Detection

**Update Trip Start Detection Integration**:

The `TripStartDetector` (T013) already provides the trigger. We need to wire it to the recorder service.

**Example integration** (in main trip detection coordinator):
```dart
// When trip start is detected
if (tripStartDetector.shouldStartTrip()) {
  await ref.read(tripRecorderServiceProvider.notifier).startRecording(
    confidenceScore: detector.confidence,
    activity: ActivityType.cycling,
  );
}
```

**Update Trip Stop Detection Integration**:

The `TripStopDetector` (T014) already provides the trigger. Wire it similarly:

```dart
// When trip stop is detected
if (tripStopDetector.shouldStopTrip()) {
  final trip = await ref.read(tripRecorderServiceProvider.notifier).stopRecording();

  // Optionally show trip summary to user
  if (trip.isValidTrip) {
    // Navigate to trip summary screen
  }
}
```

---

### Step 5: Write Tests

**File**: `test/features/trip_detection/data/services/trip_recorder_service_test.dart`

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:autoride/features/trip_detection/domain/models/location_data.dart';
import 'package:autoride/features/trip_detection/domain/models/trip.dart';
import 'package:autoride/features/trip_detection/data/services/trip_recorder_service.dart';
import 'package:autoride/features/trip_history/data/repositories/trip_repository.dart';

@GenerateMocks([TripRepository])
import 'trip_recorder_service_test.mocks.dart';

void main() {
  late MockTripRepository mockRepository;
  late ProviderContainer container;

  setUp(() {
    mockRepository = MockTripRepository();

    container = ProviderContainer(
      overrides: [
        tripRepositoryProvider.overrideWithValue(mockRepository),
      ],
    );
  });

  tearDown(() {
    container.dispose();
  });

  group('TripRecorderService', () {
    test('should start recording with database trip ID', () async {
      // Arrange
      final expectedTrip = Trip(
        id: 123, // Database assigned ID
        startTime: DateTime.now(),
        endTime: DateTime.now(),
        distance: 0.0,
        duration: 0,
        detectedActivity: ActivityType.cycling,
        confidenceScore: 0.85,
        routePoints: [],
      );

      when(mockRepository.saveTrip(any))
          .thenAnswer((_) async => expectedTrip);

      // Act
      final service = container.read(tripRecorderServiceProvider.notifier);
      await service.startRecording(
        confidenceScore: 0.85,
        activity: ActivityType.cycling,
      );

      // Assert
      verify(mockRepository.saveTrip(any)).called(1);
      final state = container.read(tripStateMachineProvider);
      expect(state.currentTripId, equals(123));
    });

    test('should calculate distance correctly', () async {
      // Create test locations with known distance
      final location1 = LocationData(
        latitude: 48.8566,  // Paris
        longitude: 2.3522,
        accuracy: 10.0,
        altitude: 35.0,
        speed: 5.0, // m/s
        heading: 90.0,
        timestamp: DateTime.now(),
      );

      final location2 = LocationData(
        latitude: 48.8576,  // ~111m north
        longitude: 2.3522,
        accuracy: 10.0,
        altitude: 35.0,
        speed: 5.0,
        heading: 90.0,
        timestamp: DateTime.now().add(const Duration(seconds: 20)),
      );

      // Distance should be approximately 111 meters
      final distance = location1.distanceTo(location2);
      expect(distance, greaterThan(100));
      expect(distance, lessThan(120));
    });

    test('should exclude pause duration from trip duration', () async {
      // TODO: Implement pause/resume test
      // 1. Start recording
      // 2. Record for 60s
      // 3. Pause for 30s
      // 4. Resume for 60s
      // 5. Stop
      // Expected: duration = 120s (not 150s)
    });

    test('should calculate average speed correctly', () async {
      // TODO: Implement average speed test
      // distance = 1000m, duration = 200s
      // avgSpeed = 18 km/h
    });

    test('should batch save route points when buffer full', () async {
      // TODO: Implement buffer flush test
      // Add 100 route points
      // Verify saveRoutePoints called once with 100 points
    });

    test('should handle poor GPS accuracy', () async {
      // TODO: Implement accuracy filter test
      // Send location with accuracy > 50m
      // Verify route point not added
    });

    test('should handle speed outliers', () async {
      // TODO: Implement speed outlier test
      // Send location with speed > 60 km/h
      // Verify route point not added
    });
  });
}
```

---

## Testing Strategy

### Unit Tests
1. **Distance calculation**: Verify `LocationData.distanceTo()` accuracy
2. **Duration calculation**: Test pause/resume duration logic
3. **Speed calculations**: Verify avg and max speed formulas
4. **Buffer management**: Test flush triggers (count, time, stop)
5. **GPS filtering**: Test distance, accuracy, speed filters

### Integration Tests
1. **Full lifecycle**: Start → record → pause → resume → stop
2. **State transitions**: Verify state machine coordination
3. **Database persistence**: Verify trip and route points saved correctly
4. **Metrics accuracy**: Record real locations, verify calculations

### Physical Device Tests (Critical!)
1. **Actual cycling trip**: Record 10+ minute ride
2. **GPS accuracy**: Verify route follows actual path
3. **Battery impact**: Monitor battery drain during recording
4. **Pause detection**: Verify stops don't record route points
5. **App backgrounding**: Verify recording continues in background

---

## Edge Cases to Handle

### GPS Issues
- **No GPS fix on start**: Delay first route point, don't fail
- **GPS signal loss mid-trip**: Continue recording when signal returns
- **Poor accuracy spikes**: Filter out with accuracy threshold
- **Speed outliers**: Reject unrealistic speeds (>60 km/h for cycling)

### Trip Scenarios
- **Very short trip (<60s)**: Save but mark as invalid via `isValidTrip`
- **Zero distance trip**: GPS drift while stationary, mark as invalid
- **Multiple pause/resume cycles**: Track all pause periods correctly
- **App termination mid-trip**: Handle gracefully, consider auto-save on app resume

### State Issues
- **Stop during pause**: Calculate pause duration correctly
- **Rapid pause/resume**: Debounce state changes
- **State machine mismatch**: Sync recorder with state machine on init

### Database Issues
- **Save fails**: Retry with exponential backoff
- **Buffer flush fails**: Keep points in memory, retry next flush
- **Transaction conflicts**: Use database transactions for atomicity

---

## Performance Considerations

### Memory Management
- **Buffer size**: 100 route points = ~2KB (safe for mobile)
- **Flush strategy**: Hybrid (count OR time OR stop)
- **Clear after save**: Prevent memory leaks

### Battery Optimization
- **Distance filter**: 15m minimum (reduces updates by ~50%)
- **Accuracy filter**: Reject poor GPS (saves processing)
- **Batch saves**: Reduce database I/O
- **Reuse settings**: Use existing battery-optimized location settings

### Database Performance
- **Batch inserts**: 100 points at once (faster than 100 individual)
- **Transactions**: Ensure atomicity and speed
- **Indexes**: Already exist on trip_id and timestamp

### CPU Optimization
- **Lazy calculations**: Only calculate metrics when UI requests
- **Debounce updates**: Don't update UI every GPS fix
- **Efficient distance**: Use Geolocator's optimized haversine formula

---

## Success Criteria

### Functional Requirements
✅ Route points saved to database during active trips
✅ Distance calculated accurately (±5% of actual)
✅ Duration excludes pause periods correctly
✅ Average speed calculated: `distance / activeDuration`
✅ Max speed tracks highest speed from route points
✅ Buffer flushes at 100 points OR 60s OR trip stop
✅ State machine uses real database trip ID

### Quality Requirements
✅ All unit tests pass
✅ Integration tests verify full lifecycle
✅ `flutter analyze` shows no warnings
✅ Code follows freezed/Riverpod patterns from CLAUDE.md
✅ Physical device test shows accurate recording

### Performance Requirements
✅ Memory: Route point buffer <5KB at any time
✅ Battery: Uses existing optimized location settings
✅ Database: Batch saves every 100 points or 60s
✅ UI: Metrics update without lag (<100ms)

---

## Common Mistakes to Avoid

### From CLAUDE.md Lessons Learned

**1. Freezed Pattern** (Mistake #1):
- ✅ Use `sealed class` for Trip and RoutePoint
- ✅ Private constructor before factory
- ✅ Methods in extensions, not in class body

**2. Riverpod Providers** (Mistake #2):
- ✅ Use `Ref ref`, not specific ref types
- ✅ Call provider functions directly: `locationStream(ref)`
- ✅ No `.stream` property exists

**3. State Management**:
- ❌ Don't use temp trip IDs from state machine
- ✅ Create trip in database first, then update state machine
- ✅ Always sync recorder service with state machine state

**4. Test Data** (Mistake #4):
- ✅ Verify GPS coordinates create expected distances
- ✅ Use real haversine distance calculations
- ✅ Test data must meet filtering thresholds

**5. Code Quality** (Mistake #3):
- ✅ Run `flutter analyze` frequently
- ✅ Remove unused imports/variables immediately
- ✅ Use `const` constructors where possible

---

## Implementation Checklist

### Phase 1: Foundation
- [ ] Add constants to `AppConstants`
- [ ] Update `TripStateMachine.startTrip()` signature
- [ ] Create `TripRecorderService` file skeleton
- [ ] Run `flutter pub run build_runner build`

### Phase 2: Core Recording
- [ ] Implement `startRecording()` with DB trip creation
- [ ] Implement location stream subscription
- [ ] Implement route point creation and buffering
- [ ] Implement distance calculation
- [ ] Test basic recording flow

### Phase 3: Metrics & State
- [ ] Implement duration calculation with pause tracking
- [ ] Implement speed calculations (avg, max)
- [ ] Implement `stopRecording()` with trip update
- [ ] Implement pause/resume handlers
- [ ] Test metrics accuracy

### Phase 4: Optimization
- [ ] Implement buffer flush logic (hybrid strategy)
- [ ] Implement GPS filtering (distance, accuracy, speed)
- [ ] Implement periodic flush timer
- [ ] Test memory usage

### Phase 5: Testing
- [ ] Write unit tests for calculations
- [ ] Write integration tests for lifecycle
- [ ] Test edge cases (GPS loss, short trips, etc.)
- [ ] Run `flutter analyze` and fix warnings
- [ ] Run `flutter test` and ensure all pass

### Phase 6: Physical Device Testing
- [ ] Test actual cycling trip (10+ minutes)
- [ ] Verify GPS accuracy on map
- [ ] Monitor battery usage
- [ ] Test pause/resume scenarios
- [ ] Test app backgrounding

---

## Resources

### Existing Code References
- **Trip Model**: `lib/features/trip_detection/domain/models/trip.dart`
- **RoutePoint Model**: Same file as Trip (embedded)
- **LocationData**: `lib/features/trip_detection/domain/models/location_data.dart`
- **TripRepository**: `lib/features/trip_history/data/repositories/trip_repository.dart`
- **TripStateMachine**: `lib/features/trip_detection/data/services/trip_state_machine.dart`
- **LocationService**: `lib/features/trip_detection/data/services/location_service.dart`
- **AppConstants**: `lib/core/constants/app_constants.dart`

### External Documentation
- [Riverpod Code Generation](https://riverpod.dev/docs/concepts/about_code_generation)
- [Geolocator Distance Calculation](https://pub.dev/packages/geolocator#distance-between-locations)
- [Flutter Background Service Best Practices](https://pub.dev/packages/flutter_background_service)

---

**Created**: 2025-11-22
**Estimated Time**: 2-3 hours
**Complexity**: Medium (requires coordination across services)
**Risk Level**: Medium (GPS accuracy, state synchronization critical)
