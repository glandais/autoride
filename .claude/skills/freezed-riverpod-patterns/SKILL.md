---
name: freezed-riverpod-patterns
description: Freezed model and Riverpod provider patterns for AutoRide, plus the concrete mistakes made while building them and how to avoid repeating them. Use when writing or debugging freezed models, sealed classes, Riverpod providers (stream, class/notifier), code generation, or when hitting errors like "Undefined class XxxRef", missing-implementation errors on a freezed class, or sort_constructors_first lint warnings.
---

# Freezed & Riverpod Patterns (AutoRide)

Reference: `lib/features/trip_detection/domain/models/location_data.dart` (freezed),
`lib/features/trip_detection/data/services/location_service.dart:85-105` (stream provider).

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

### Mistake 5: Incorrect Constructor Ordering (Lint Rule)

**Problem**: Placing field declarations before constructors violates the `sort_constructors_first` lint rule.

❌ **Wrong**:
```dart
class ErrorView extends StatelessWidget {
  final ErrorType type;  // ❌ Fields before constructors
  final String? title;
  final String? message;

  const ErrorView({  // ❌ Constructor after fields
    super.key,
    this.type = ErrorType.unknown,
    this.title,
    this.message,
  });

  factory ErrorView.notFound() { /* ... */ }  // ❌ Factory after fields

  @override
  Widget build(BuildContext context) { /* ... */ }
}
```

**Error**:
```
info • Constructor declarations should be before non-constructor declarations
     • lib/shared/widgets/error_view.dart:20:9
     • sort_constructors_first
```

✅ **Correct**:
```dart
class ErrorView extends StatelessWidget {
  const ErrorView({  // ✅ Constructors FIRST
    super.key,
    this.type = ErrorType.unknown,
    this.title,
    this.message,
  });

  factory ErrorView.notFound() { /* ... */ }  // ✅ All constructors together

  final ErrorType type;  // ✅ Fields AFTER constructors
  final String? title;
  final String? message;

  @override
  Widget build(BuildContext context) { /* ... */ }
}
```

**Key Lessons**:
- The `sort_constructors_first` lint rule requires **all constructors** (const, factory, named) before **all other members** (fields, methods)
- Constructor order: const constructor → factory constructors → named constructors
- Then fields, then methods
- Run `flutter analyze` to catch these issues early
- This is opposite to some common Dart style guides, but matches Flutter lint rules

**Detection**: `flutter analyze` will show `sort_constructors_first` warnings

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

