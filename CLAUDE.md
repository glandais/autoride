# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Quick Start

**Essential Commands**:
```bash
# Code generation (MUST run during development)
flutter pub run build_runner watch

# Quality gates (run in order)
flutter analyze                  # MUST pass before testing
flutter test                     # All tests must pass
flutter test test/path/to/specific_test.dart  # Run single test
flutter run --release            # Test on physical device (sensors/GPS)
```

**Critical Rules**:
- **NEVER commit autonomously** - Only commit when user executes `/commit` command
- Always use `sealed class` with freezed models (see `location_data.dart`)
- Stream providers use `Ref ref`, not specific ref types
- Run `flutter analyze` BEFORE `flutter test`
- Test sensor/location features on **physical devices only** (not emulators)
- Check `AppConstants` for all thresholds before implementation
- Follow existing patterns in the codebase

**Current Branch**: `feat/claude-md`
**Main Branch**: `develop` (use for PRs)
**Task Tracker**: `tasks/TASKS.md` (8/40 complete, Phase 3)

---

## Key Files Reference

| Purpose | Location |
|---------|----------|
| **All Constants/Thresholds** | `lib/core/constants/app_constants.dart` |
| **Task Tracker** | `tasks/TASKS.md` (authoritative progress) |
| **Freezed Pattern Example** | `lib/features/trip_detection/domain/models/location_data.dart` |
| **Stream Provider Pattern** | `lib/features/trip_detection/data/services/location_service.dart:85-105` |
| **Cycling Detection Logic** | `lib/features/trip_detection/data/services/cycling_pattern_detector.dart` |
| **GPS Motion-Gating** | `lib/features/trip_detection/data/services/gps_controller.dart` |
| **Battery Optimization** | `lib/features/trip_detection/data/services/battery_optimizer.dart` |
| **Android Permissions** | `android/app/src/main/AndroidManifest.xml` |

---

## Task Workflow

**Task System**: This project uses a structured task tracking system in `tasks/TASKS.md`.

**Progress**: 8/40 tasks complete, currently at **Phase 3 - Data Management**

**Quick Flow**:
1. Check `tasks/TASKS.md` for next pending (☐) task
2. Request detailed guide: "Create detailed task for T009"
3. Update status: ☐ → ⏳ → ✅
4. Implement following quality gates below
5. Commit with task ID: `git commit -m "T009: Brief description"`
6. Update progress summary in `tasks/TASKS.md`

**Quality Gates** (run in this order):
1. Code generation: `flutter pub run build_runner build`
2. Static analysis: `flutter analyze` (MUST pass)
3. Unit tests: `flutter test`
4. Physical device test (for sensor/location tasks)
5. Wait for user to run `/commit` (NEVER commit autonomously)

**Task Dependencies**: Never start a task before its dependencies are complete. See `tasks/TASKS.md` for dependency tree.

**Commit Format**:
```
T###: Brief description

- Detailed change 1
- Detailed change 2
- Testing notes
```

---

## Architecture Overview

**Project**: AutoRide - Automatic bike trip detection using motion sensors and ML

**Core Tech Stack**:
- **Flutter**: 3.10.1+
- **State Management**: Riverpod with code generation (`@riverpod` annotation)
- **Data Models**: Freezed with `sealed class` pattern
- **Location**: Geolocator (GPS with background support)
- **Sensors**: sensors_plus (accelerometer, gyroscope)
- **ML**: TensorFlow Lite for activity recognition (future)
- **Database**: sqflite (local SQLite)
- **Persistence**: shared_preferences (settings)

**Project Structure** (Feature-First):
```
lib/
├── core/
│   ├── constants/        # AppConstants - all thresholds
│   ├── utils/
│   └── theme/
├── features/
│   ├── trip_detection/   # Core trip tracking
│   │   ├── data/         # Services, repositories
│   │   ├── domain/       # Models (freezed)
│   │   ├── presentation/ # UI providers
│   │   └── services/     # Background service
│   ├── trip_history/
│   ├── settings/
│   └── onboarding/
└── shared/
    ├── models/
    ├── providers/
    └── widgets/
```

**Key Architecture Decisions**:
- **Battery-First Design**: Motion-gated GPS (sensors trigger location, not continuous)
- **Separation of Concerns**: Data → Domain → Presentation
- **Feature Isolation**: Each feature is self-contained
- **Background Tracking**: Foreground service with notification (required for reliability)

---

## Critical Patterns

### Freezed Models

**Pattern** (use `sealed class` with extensions):
```dart
@freezed
sealed class ModelName with _$ModelName {
  const ModelName._();  // ✅ Private constructor BEFORE factory

  const factory ModelName({
    required Type field1,
    required Type field2,
  }) = _ModelName;

  factory ModelName.fromSomething(Something obj) {
    return ModelName(field1: obj.x, field2: obj.y);
  }
}

// ✅ Methods in extensions OUTSIDE the class
extension ModelNameExtensions on ModelName {
  double get calculatedValue => field1 * field2;
  bool isValid() => field1 > 0;
}
```

**Reference**: See `lib/features/trip_detection/domain/models/location_data.dart`

### Riverpod Providers

**Stream Providers**:
```dart
@riverpod
Stream<Data> dataStream(
  Ref ref,  // ✅ Use plain 'Ref', NOT DataStreamRef
) async* {
  // ✅ Call provider function directly (no .stream property)
  final otherStream = otherStreamProvider(ref);

  await for (final data in otherStream) {
    yield processedData;
  }
}
```

**Class Providers** (Notifiers):
```dart
@riverpod
class MyService extends _$MyService {
  @override
  State build() {
    // Initialize
    return State.initial();
  }

  void doSomething() {
    state = state.copyWith(updated: true);
  }
}
```

**Reference**: See `lib/features/trip_detection/data/services/location_service.dart:85-105`

### Code Generation

**Required for**: Riverpod providers, Freezed models

**Workflow**:
```bash
# Watch mode (auto-regenerate on file changes)
flutter pub run build_runner watch

# One-time generation
flutter pub run build_runner build --delete-conflicting-outputs

# Clean and rebuild
flutter pub run build_runner clean
flutter pub run build_runner build --delete-conflicting-outputs
```

**Required directives**:
```dart
import 'package:riverpod_annotation/riverpod_annotation.dart';
part 'filename.g.dart';  // ✅ Must match filename

@riverpod
class MyProvider extends _$MyProvider { /* ... */ }
```

---

## Lessons Learned & Common Mistakes

**This section documents concrete mistakes from development. Learn from these to avoid repeating them.**

### Mistake 1: Incorrect Freezed Class Structure (T007)

**Problem**: Using `class` instead of `sealed class` and placing methods inside the freezed class body.

❌ **Wrong**:
```dart
@freezed
class AccelerometerData with _$AccelerometerData {
  const factory AccelerometerData({
    required double x,
    required double y,
    required double z,
  }) = _AccelerometerData;

  const AccelerometerData._();

  // ❌ Methods inside - causes compilation errors
  double get magnitude => sqrt(x * x + y * y + z * z);
}
```

**Error**:
```
Error: The non-abstract class 'AccelerometerData' is missing implementations...
```

✅ **Correct**:
```dart
@freezed
sealed class AccelerometerData with _$AccelerometerData {
  const AccelerometerData._();  // ✅ Private constructor BEFORE factory

  const factory AccelerometerData({
    required double x,
    required double y,
    required double z,
  }) = _AccelerometerData;
}

// ✅ Extensions OUTSIDE the class
extension AccelerometerDataExtensions on AccelerometerData {
  double get magnitude => sqrt(x * x + y * y + z * z);
}
```

**Key Lessons**:
- Use `sealed class` with freezed (matches existing `LocationData` pattern)
- Private constructor goes **before** factory constructors
- Methods go in **extensions**, not in class body
- Check `location_data.dart` for reference

---

### Mistake 2: Incorrect Riverpod Stream Provider Usage (T007)

**Problem**: Trying to access `.stream` property and using wrong Ref types.

❌ **Wrong**:
```dart
@riverpod
Stream<MotionData> motionDataStream(
  MotionDataStreamRef ref,  // ❌ Specific ref type doesn't exist
) async* {
  final accelStream = ref.watch(accelerometerStreamProvider.stream);  // ❌ No .stream property
}
```

✅ **Correct**:
```dart
@riverpod
Stream<MotionData> motionDataStream(
  Ref ref,  // ✅ Plain 'Ref'
) async* {
  // ✅ Call the function directly
  final accelStream = accelerometerStream(ref);
  await for (final data in accelStream) {
    yield processedData;
  }
}
```

**Key Lessons**:
- Stream providers use `Ref ref`, not specific ref types
- Call provider functions directly: `streamProvider(ref)`
- No `.stream` property exists
- `ref.watch(streamProvider)` returns `AsyncValue<T>`, not `Stream<T>`

---

### Mistake 3: Unused Variables and Imports (T007)

**Problem**: Declaring variables/fields that aren't used.

❌ **Wrong**:
```dart
import 'package:sensors_plus/sensors_plus.dart';  // ❌ Unused

@riverpod
class Service extends _$Service {
  Timer? _timer;  // ❌ Declared but never used
}

final window = MotionWindow(
  startTime: DateTime.now().subtract(Duration(seconds: 1)),  // ❌ Should be const
);
```

✅ **Correct**:
```dart
// ✅ Only import what you use
import 'package:autoride/features/trip_detection/domain/models/motion_data.dart';

@riverpod
class Service extends _$Service {
  // ✅ Removed unused field
}

final window = MotionWindow(
  startTime: DateTime.now().subtract(const Duration(seconds: 1)),  // ✅ const
);
```

**Key Lessons**:
- Run `flutter analyze` frequently
- Remove unused imports/variables immediately
- Use `const` constructors where possible
- Don't declare fields "just in case"

---

### Mistake 4: Test Data Not Meeting Detection Thresholds (T007)

**Problem**: Writing tests with data that doesn't meet the conditions being tested.

❌ **Wrong**:
```dart
test('should detect cycling', () {
  final samples = List.generate(100, (i) {
    return MotionData(
      accelerometer: AccelerometerData(
        x: 2.0, y: 2.0, z: 10.0,  // ❌ magnitude ≈ 10.39, needs > 10.5
      ),
    );
  });

  expect(window.state, equals(MotionState.cycling));  // ❌ Fails!
});
```

✅ **Correct**:
```dart
test('should detect cycling', () {
  // ✅ Calculate values that meet thresholds
  // Need: avgAccel > 10.5 (from AppConstants)
  final samples = List.generate(100, (i) {
    return MotionData(
      accelerometer: AccelerometerData(
        x: 3.0, y: 3.0, z: 10.0,  // ✅ magnitude = sqrt(118) ≈ 10.86 > 10.5
      ),
    );
  });

  expect(window.state, equals(MotionState.cycling));  // ✅ Passes!
});
```

**Key Lessons**:
- **Verify test data meets thresholds** before writing assertions
- Calculate expected values manually: `// magnitude = sqrt(118) ≈ 10.86`
- Check `AppConstants` for actual threshold values
- When tests fail, verify test data is correct first

---

### Best Practices Summary

**Before Starting**:
1. Check existing similar code for patterns
2. Review `AppConstants` for relevant configuration
3. Read generated `.g.dart` files to understand provider types

**During Implementation**:
1. Run `flutter pub run build_runner watch` in separate terminal
2. Write tests with calculated values that meet thresholds
3. Run `flutter analyze` before `flutter test`
4. Test on physical devices for sensor/location features

**When Encountering Errors**:
1. Read full error message carefully
2. Check generated `.g.dart` and `.freezed.dart` files
3. Compare with working examples in codebase
4. Verify test data mathematically

---

## Battery Optimization Strategy

**Core Principle**: Motion-gated GPS (don't run GPS continuously)

**Implementation**:
1. **Sensors first**: Use accelerometer to detect movement
2. **GPS on demand**: Only activate GPS when motion detected
3. **Adaptive accuracy**: Adjust based on battery level and activity
4. **Distance filtering**: Update every 15m for cycling (not every meter)
5. **Foreground service**: Required for reliable background tracking

**Battery States** (see `AppConstants`):
- **Normal** (>50%): 50Hz sensors, 30s location updates, 15m distance filter
- **Medium** (20-50%): 40Hz sensors, 40s updates, 20m filter
- **Low** (10-20%): 25Hz sensors, 60s updates, 20m filter
- **Critical** (<10%): 20Hz sensors, 90s updates, 100m filter

**Target**: <5% battery drain per hour of active tracking

**Key Files**:
- `lib/features/trip_detection/data/services/battery_optimizer.dart`
- `lib/features/trip_detection/data/services/gps_controller.dart`
- `lib/features/trip_detection/data/services/adaptive_location_settings.dart`

---

## Cycling Detection Logic

**Multi-Layer Approach**:

1. **Motion Pattern Analysis** (Layer 1)
   - Acceleration range: 10-20 m/s² (cycling range)
   - Rotation range: 0.5-3.0 rad/s (pedaling motion)
   - Score: 0-1 based on how well values fit cycling profile

2. **Pedaling Frequency Analysis** (Layer 2)
   - Detect peaks in acceleration (pedaling cycles)
   - Expected frequency: 0.5-2.0 Hz (30-120 RPM)
   - Typical: 1.2 Hz (72 RPM)

3. **GPS Speed Validation** (Layer 3 - when available)
   - Cycling speed range: 8-40 km/h
   - Typical: 18 km/h
   - Too slow (<8): likely walking
   - Too fast (>40): likely driving

**Final Confidence Score**:
- Motion score: 40% weight
- Speed score: 35% weight
- Frequency score: 25% weight
- Threshold: 0.6 minimum for detection

**All thresholds defined in**: `lib/core/constants/app_constants.dart`

**Implementation**: `lib/features/trip_detection/data/services/cycling_pattern_detector.dart`

---

## Testing Strategy

### Test Types

**Unit Tests** (business logic):
```bash
flutter test test/features/trip_detection/data/services/
```

**Widget Tests** (UI with mocked providers):
```bash
flutter test test/features/trip_detection/presentation/
```

**Integration Tests** (not yet implemented)

### Physical Device Testing

**Critical**: Sensor and location features **MUST** be tested on physical devices.

**Test Scenarios**:
- [ ] Cycling trip (10+ minutes)
- [ ] Walking trip (false positive check)
- [ ] Driving trip (false positive check)
- [ ] Stationary (no false detection)
- [ ] App backgrounded during trip
- [ ] Low battery scenario (<20%)

### Mocking Providers in Tests

```dart
testWidgets('test description', (tester) async {
  final container = ProviderContainer(
    overrides: [
      myServiceProvider.overrideWith((ref) => MockMyService()),
    ],
  );

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MyApp(),
    ),
  );

  // Test implementation
});
```

---

## Common Issues Quick Reference

| Issue | Quick Fix | Reference |
|-------|-----------|-----------|
| `Undefined class XxxRef` | Use `Ref ref`, not specific types | Mistake #2 |
| Freezed compilation errors | Check `sealed class`, constructor order | Mistake #1 |
| Tests fail unexpectedly | Verify test data meets thresholds | Mistake #4 |
| Unused import/variable warnings | Run `flutter analyze`, remove them | Mistake #3 |
| Code generation not working | Check `part 'file.g.dart';` directive | - |
| Build runner conflicts | Run with `--delete-conflicting-outputs` | - |
| Sensor data in emulator | Use physical device, emulators don't work | - |

---

## Development Workflow

### Daily Pattern

```bash
# Terminal 1: Code generation watcher
flutter pub run build_runner watch

# Terminal 2: Run app on physical device
flutter run --release  # Test battery in release mode

# Check logs
flutter logs --verbose

# Profile battery (critical!)
# Android: Android Studio → Profiler → Energy
# iOS: Xcode → Debug Navigator → Energy Impact
```

### Before Committing

**IMPORTANT**: Never create commits autonomously. Only commit when user executes `/commit` command.

```bash
flutter analyze          # Must pass
flutter test            # All tests must pass
git status              # Check what's staged
git diff               # Review changes

# Wait for user to run /commit - DO NOT run git commit yourself
```

### Creating New Features

```bash
mkdir -p lib/features/feature_name/{data,domain,presentation,services}
```

---

## Platform-Specific Notes

### Android Permissions

Required permissions configured in `android/app/src/main/AndroidManifest.xml`:
- `ACCESS_FINE_LOCATION`
- `ACCESS_BACKGROUND_LOCATION` (Android 10+)
- `FOREGROUND_SERVICE`
- `FOREGROUND_SERVICE_LOCATION` (Android 9+)
- `WAKE_LOCK`

**Background service**:
```xml
<service
    android:name="id.flutter.flutter_background_service.BackgroundService"
    android:foregroundServiceType="location"
    android:exported="false" />
```

### iOS Permissions

Configure in `ios/Runner/Info.plist`:
- `NSLocationWhenInUseUsageDescription`
- `NSLocationAlwaysAndWhenInUseUsageDescription`
- `UIBackgroundModes` (location)

### Permission Strategy

**Progressive approach**:
1. Request basic location on first launch (with rationale)
2. Request background location when user starts first trip
3. Handle denials gracefully (allow manual tracking)

**Platform differences**:
- Android 10+: Two-step (foreground → background)
- Android 11+: User must select "Allow all the time" in settings
- iOS 14+: "Allow Once" vs "While Using" vs "Always"

---

## Reference Examples

### Complete Freezed Model Example

```dart
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:geolocator/geolocator.dart';

part 'location_data.freezed.dart';

@freezed
sealed class LocationData with _$LocationData {
  const LocationData._();

  const factory LocationData({
    required double latitude,
    required double longitude,
    required double accuracy,
    required double altitude,
    required double speed, // m/s
    required double heading,
    required DateTime timestamp,
  }) = _LocationData;

  factory LocationData.fromPosition(Position position) {
    return LocationData(
      latitude: position.latitude,
      longitude: position.longitude,
      accuracy: position.accuracy,
      altitude: position.altitude,
      speed: position.speed,
      heading: position.heading,
      timestamp: position.timestamp,
    );
  }
}

extension LocationDataExtensions on LocationData {
  double get speedKmh => speed * 3.6;

  double distanceTo(LocationData other) {
    return Geolocator.distanceBetween(
      latitude, longitude,
      other.latitude, other.longitude,
    );
  }
}
```

### Complete Stream Provider Example

```dart
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:geolocator/geolocator.dart';
import '../../domain/models/location_data.dart';

part 'location_service.g.dart';

@riverpod
Stream<LocationData> locationStream(Ref ref) async* {
  const settings = LocationSettings(
    accuracy: LocationAccuracy.medium,
    distanceFilter: 15,
  );

  await for (final position in Geolocator.getPositionStream(locationSettings: settings)) {
    yield LocationData.fromPosition(position);
  }
}

@riverpod
class LocationService extends _$LocationService {
  @override
  Stream<LocationData> build() async* {
    final stream = locationStream(ref);
    await for (final location in stream) {
      yield location;
    }
  }

  Future<LocationData> getCurrentLocation() async {
    final position = await Geolocator.getCurrentPosition();
    return LocationData.fromPosition(position);
  }
}
```

### Complete Test Example

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:autoride/features/trip_detection/domain/models/motion_data.dart';
import 'package:autoride/features/trip_detection/data/services/sensor_utils.dart';

void main() {
  group('MotionWindow', () {
    test('should calculate average acceleration correctly', () {
      final samples = List.generate(100, (i) {
        return MotionData(
          accelerometer: AccelerometerData(
            x: 3.0, y: 3.0, z: 10.0,  // magnitude ≈ 10.86
            timestamp: DateTime.now(),
          ),
          gyroscope: GyroscopeData(
            x: 1.0, y: 0.5, z: 0.5,
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

      expect(window.averageAcceleration, closeTo(10.86, 0.1));
    });

    test('should determine cycling state correctly', () {
      // Create data that meets cycling thresholds:
      // avgAccel > 10.5, avgRotation > 0.5 (from AppConstants)
      final samples = List.generate(100, (i) {
        return MotionData(
          accelerometer: AccelerometerData(
            x: 3.0, y: 3.0, z: 10.0,  // ✅ sqrt(118) ≈ 10.86 > 10.5
            timestamp: DateTime.now(),
          ),
          gyroscope: GyroscopeData(
            x: 1.0, y: 0.5, z: 0.5,  // ✅ sqrt(1.5) ≈ 1.22 > 0.5
            timestamp: DateTime.now(),
          ),
          timestamp: DateTime.now(),
        );
      });

      final window = MotionWindow(samples: samples);
      expect(window.state, equals(MotionState.cycling));
    });
  });
}
```

---

## Resources

### Official Documentation
- [Flutter](https://flutter.dev) - Framework
- [Riverpod](https://riverpod.dev) - State management
- [Freezed](https://pub.dev/packages/freezed) - Immutable models
- [Geolocator](https://pub.dev/packages/geolocator) - Location services
- [Sensors Plus](https://pub.dev/packages/sensors_plus) - Motion sensors
- [Flutter Background Service](https://pub.dev/packages/flutter_background_service) - Background tasks

### External Resources
- [Battery Optimization Guide](https://kotlincodes.com/flutter-dart/advanced-concepts/handling-battery-optimization-for-background-tasks-in-flutter/)
- [Background Location Best Practices](https://vibe-studio.ai/insights/handling-background-location-tracking-responsibly-in-flutter)

---

**Last Updated**: 2025-11-22
**Flutter Version**: 3.10.1+
**Target SDK**: iOS 13+, Android 8+ (API 26+)
**Project Status**: Phase 3 - Data Management (8/40 tasks complete)
