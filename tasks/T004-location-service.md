# T004: Basic Location Service

## Overview

Implement the foundational location service that integrates the `geolocator` package with Riverpod state management. This service will provide location data to the rest of the application and handle basic permission checking.

**Status**: ☐ Pending
**Dependencies**: T001 (Project Setup), T003 (Riverpod Setup)
**Estimate**: 2-3 hours
**Phase**: Phase 2 - Core Location & Sensors

## Prerequisites

Before starting this task, ensure:
- ✅ T001 completed (geolocator dependency added to pubspec.yaml)
- ✅ T003 completed (Riverpod code generation configured)
- ✅ Physical device available for testing (location services don't work well in emulator)

## Objectives

1. Create a location service wrapper around geolocator
2. Implement Riverpod providers for location data
3. Add basic permission checking
4. Provide current location and location stream capabilities
5. Handle location service errors gracefully

## Implementation Steps

### Step 1: Create Location Service Infrastructure

Create the feature structure:

```bash
mkdir -p lib/features/trip_detection/data/services
mkdir -p lib/features/trip_detection/domain/models
```

### Step 2: Create Location Model

**File**: `lib/features/trip_detection/domain/models/location_data.dart`

```dart
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:geolocator/geolocator.dart';

part 'location_data.freezed.dart';

@freezed
class LocationData with _$LocationData {
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

// Extension for convenience
extension LocationDataExtensions on LocationData {
  /// Speed in km/h
  double get speedKmh => speed * 3.6;

  /// Calculate distance to another location in meters
  double distanceTo(LocationData other) {
    return Geolocator.distanceBetween(
      latitude,
      longitude,
      other.latitude,
      other.longitude,
    );
  }
}
```

### Step 3: Create Location Permission Provider

**File**: `lib/features/trip_detection/data/services/location_permission_service.dart`

```dart
import 'package:geolocator/geolocator.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'location_permission_service.g.dart';

/// Location permission status
enum LocationPermissionStatus {
  granted,
  denied,
  deniedForever,
  notDetermined,
  serviceDisabled,
}

@riverpod
class LocationPermissionService extends _$LocationPermissionService {
  @override
  Future<LocationPermissionStatus> build() async {
    return await checkPermission();
  }

  /// Check current permission status
  Future<LocationPermissionStatus> checkPermission() async {
    // Check if location services are enabled
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return LocationPermissionStatus.serviceDisabled;
    }

    // Check permission
    LocationPermission permission = await Geolocator.checkPermission();

    return switch (permission) {
      LocationPermission.denied => LocationPermissionStatus.denied,
      LocationPermission.deniedForever => LocationPermissionStatus.deniedForever,
      LocationPermission.whileInUse || LocationPermission.always =>
        LocationPermissionStatus.granted,
      _ => LocationPermissionStatus.notDetermined,
    };
  }

  /// Request location permission
  Future<LocationPermissionStatus> requestPermission() async {
    // First check if service is enabled
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      // Request user to enable location service
      // Note: Can't programmatically enable, user must do it manually
      return LocationPermissionStatus.serviceDisabled;
    }

    // Request permission
    LocationPermission permission = await Geolocator.requestPermission();

    final status = switch (permission) {
      LocationPermission.denied => LocationPermissionStatus.denied,
      LocationPermission.deniedForever => LocationPermissionStatus.deniedForever,
      LocationPermission.whileInUse || LocationPermission.always =>
        LocationPermissionStatus.granted,
      _ => LocationPermissionStatus.notDetermined,
    };

    // Update state
    state = AsyncValue.data(status);
    return status;
  }

  /// Open app settings (for when permission is denied forever)
  Future<bool> openLocationSettings() async {
    return await Geolocator.openLocationSettings();
  }

  /// Open app settings (for permission management)
  Future<bool> openAppSettings() async {
    return await Geolocator.openAppSettings();
  }
}
```

### Step 4: Create Location Service

**File**: `lib/features/trip_detection/data/services/location_service.dart`

```dart
import 'package:geolocator/geolocator.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../domain/models/location_data.dart';
import 'location_permission_service.dart';

part 'location_service.g.dart';

/// Default location settings for basic tracking
const LocationSettings kDefaultLocationSettings = LocationSettings(
  accuracy: LocationAccuracy.high,
  distanceFilter: 10, // Update every 10 meters
  timeLimit: Duration(seconds: 30),
);

@riverpod
class LocationService extends _$LocationService {
  @override
  Future<LocationData?> build() async {
    // Return null initially, will be populated when location is requested
    return null;
  }

  /// Get current location (one-time)
  Future<LocationData?> getCurrentLocation({
    LocationSettings? settings,
  }) async {
    try {
      // Check permission
      final permissionStatus = await ref.read(
        locationPermissionServiceProvider.future,
      );

      if (permissionStatus != LocationPermissionStatus.granted) {
        throw LocationServiceException(
          'Location permission not granted',
          permissionStatus,
        );
      }

      // Get position
      final position = await Geolocator.getCurrentPosition(
        locationSettings: settings ?? kDefaultLocationSettings,
      );

      final locationData = LocationData.fromPosition(position);

      // Update state
      state = AsyncValue.data(locationData);

      return locationData;
    } on LocationServiceDisabledException {
      throw LocationServiceException(
        'Location services are disabled',
        LocationPermissionStatus.serviceDisabled,
      );
    } on PermissionDeniedException {
      throw LocationServiceException(
        'Location permission denied',
        LocationPermissionStatus.denied,
      );
    } catch (e) {
      state = AsyncValue.error(e, StackTrace.current);
      rethrow;
    }
  }

  /// Get last known location (cached, fast)
  Future<LocationData?> getLastKnownLocation() async {
    try {
      final position = await Geolocator.getLastKnownPosition();
      if (position == null) return null;

      final locationData = LocationData.fromPosition(position);
      state = AsyncValue.data(locationData);
      return locationData;
    } catch (e) {
      // Silently fail for last known location
      return null;
    }
  }
}

/// Stream provider for continuous location updates
@riverpod
Stream<LocationData> locationStream(
  LocationStreamRef ref, {
  LocationSettings? settings,
}) async* {
  // Check permission first
  final permissionStatus = await ref.watch(
    locationPermissionServiceProvider.future,
  );

  if (permissionStatus != LocationPermissionStatus.granted) {
    throw LocationServiceException(
      'Location permission not granted',
      permissionStatus,
    );
  }

  // Stream position updates
  yield* Geolocator.getPositionStream(
    locationSettings: settings ?? kDefaultLocationSettings,
  ).map((position) => LocationData.fromPosition(position));
}

/// Custom exception for location service errors
class LocationServiceException implements Exception {
  final String message;
  final LocationPermissionStatus permissionStatus;

  LocationServiceException(this.message, this.permissionStatus);

  @override
  String toString() => 'LocationServiceException: $message';
}
```

### Step 5: Create Utility Providers

**File**: `lib/features/trip_detection/data/services/location_utils.dart`

```dart
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../domain/models/location_data.dart';

part 'location_utils.g.dart';

/// Calculate distance between two locations in meters
@riverpod
double distanceBetween(
  DistanceBetweenRef ref,
  LocationData start,
  LocationData end,
) {
  return start.distanceTo(end);
}

/// Format speed for display (km/h with 1 decimal)
@riverpod
String formatSpeed(FormatSpeedRef ref, double speedMs) {
  final speedKmh = speedMs * 3.6;
  return '${speedKmh.toStringAsFixed(1)} km/h';
}

/// Format distance for display
@riverpod
String formatDistance(FormatDistanceRef ref, double meters) {
  if (meters < 1000) {
    return '${meters.toStringAsFixed(0)} m';
  } else {
    final km = meters / 1000;
    return '${km.toStringAsFixed(2)} km';
  }
}
```

### Step 6: Run Code Generation

Generate the required files:

```bash
flutter pub run build_runner build --delete-conflicting-outputs
```

Or start the watcher for continuous generation:

```bash
flutter pub run build_runner watch
```

### Step 7: Create Basic Test

**File**: `test/features/trip_detection/data/services/location_service_test.dart`

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:autoride/features/trip_detection/domain/models/location_data.dart';

void main() {
  group('LocationData', () {
    test('should convert from Position correctly', () {
      // Arrange
      final position = Position(
        latitude: 48.8566,
        longitude: 2.3522,
        timestamp: DateTime.now(),
        accuracy: 10.0,
        altitude: 35.0,
        heading: 90.0,
        speed: 5.0,
        speedAccuracy: 1.0,
        altitudeAccuracy: 1.0,
        headingAccuracy: 1.0,
      );

      // Act
      final locationData = LocationData.fromPosition(position);

      // Assert
      expect(locationData.latitude, equals(48.8566));
      expect(locationData.longitude, equals(2.3522));
      expect(locationData.speed, equals(5.0));
      expect(locationData.speedKmh, equals(18.0)); // 5 m/s = 18 km/h
    });

    test('should calculate distance between two locations', () {
      // Arrange
      final paris = LocationData(
        latitude: 48.8566,
        longitude: 2.3522,
        accuracy: 10.0,
        altitude: 35.0,
        speed: 0.0,
        heading: 0.0,
        timestamp: DateTime.now(),
      );

      final london = LocationData(
        latitude: 51.5074,
        longitude: -0.1278,
        accuracy: 10.0,
        altitude: 11.0,
        speed: 0.0,
        heading: 0.0,
        timestamp: DateTime.now(),
      );

      // Act
      final distance = paris.distanceTo(london);

      // Assert
      // Paris to London is approximately 344 km
      expect(distance, greaterThan(340000));
      expect(distance, lessThan(350000));
    });

    test('should convert speed to km/h correctly', () {
      // Arrange
      final locationData = LocationData(
        latitude: 48.8566,
        longitude: 2.3522,
        accuracy: 10.0,
        altitude: 35.0,
        speed: 10.0, // 10 m/s
        heading: 0.0,
        timestamp: DateTime.now(),
      );

      // Act & Assert
      expect(locationData.speedKmh, equals(36.0)); // 10 m/s = 36 km/h
    });
  });
}
```

## Testing

### Manual Testing Checklist

**On Physical Device** (critical - emulators don't have real GPS):

1. **Permission Flow**:
   - [ ] Launch app and request location permission
   - [ ] Grant permission - verify service works
   - [ ] Deny permission - verify error handling
   - [ ] Deny forever - verify "open settings" option works

2. **Location Accuracy**:
   - [ ] Get current location - compare with Google Maps
   - [ ] Verify accuracy is within reasonable range (<50m)
   - [ ] Check altitude is populated

3. **Location Stream**:
   - [ ] Start location stream
   - [ ] Walk around with device
   - [ ] Verify updates happen at reasonable intervals
   - [ ] Stop stream - verify no battery drain

4. **Service Disabled**:
   - [ ] Disable location services in device settings
   - [ ] Try to get location - verify error handling
   - [ ] Re-enable services - verify recovery

5. **Last Known Location**:
   - [ ] Get last known location immediately after app launch
   - [ ] Verify it returns cached location (if available)

### Automated Testing

Run unit tests:

```bash
flutter test test/features/trip_detection/data/services/
```

### Performance Testing

Check for battery drain:

```bash
# Run app on physical device
flutter run --release

# Monitor battery usage after 10 minutes of location streaming
# Should be minimal since we're not running GPS continuously yet
```

## Acceptance Criteria

- [ ] LocationData model created with freezed
- [ ] LocationPermissionService provider implemented
- [ ] LocationService provider implemented with current location capability
- [ ] Location stream provider created
- [ ] Basic permission checking works
- [ ] Error handling for denied permissions
- [ ] Error handling for disabled location services
- [ ] Unit tests pass
- [ ] Manual testing on physical device successful
- [ ] Code generation files committed (.g.dart, .freezed.dart)
- [ ] No flutter analyze warnings

## Common Pitfalls

### 1. Testing on Emulator
**Problem**: Emulators don't have real GPS hardware, location simulation is unreliable.

**Solution**: Always test on physical device. For emulator testing, use mock locations.

### 2. Permission Not Granted
**Problem**: Trying to get location without checking permission first.

**Solution**: Always check/request permission before accessing location.

```dart
// ❌ Wrong
final location = await locationService.getCurrentLocation();

// ✅ Right
final permission = await ref.read(locationPermissionServiceProvider.notifier).requestPermission();
if (permission == LocationPermissionStatus.granted) {
  final location = await locationService.getCurrentLocation();
}
```

### 3. Location Services Disabled
**Problem**: User has location services turned off in device settings.

**Solution**: Check `isLocationServiceEnabled()` and prompt user to enable.

### 4. Accuracy Too High
**Problem**: Using `LocationAccuracy.best` drains battery quickly.

**Solution**: For basic service, use `LocationAccuracy.high` or `medium`. Reserve `best` for active trip tracking.

### 5. Distance Filter Too Small
**Problem**: Using `distanceFilter: 0` causes excessive updates.

**Solution**: Use `distanceFilter: 10` (meters) for basic tracking. Cycling typically moves >10m between meaningful updates.

### 6. Forgetting Code Generation
**Problem**: Changes to Riverpod providers don't take effect.

**Solution**: Run `flutter pub run build_runner build` after creating/modifying providers.

## Resources

### Official Documentation
- [Geolocator Package](https://pub.dev/packages/geolocator)
- [Geolocator Platform Interface](https://pub.dev/documentation/geolocator_platform_interface/latest/)
- [Riverpod Async Providers](https://riverpod.dev/docs/concepts/providers#futureprovider)
- [Freezed Package](https://pub.dev/packages/freezed)

### Location Concepts
- [Android Location Best Practices](https://developer.android.com/training/location)
- [iOS Core Location](https://developer.apple.com/documentation/corelocation)
- [GPS Accuracy Modes](https://developer.android.com/reference/android/location/LocationManager)

### Related Tasks
- **Next**: T005 - Background Location Tracking
- **Related**: T007 - Sensor Integration
- **Uses**: T003 - Riverpod Code Generation Setup

## Next Steps

After completing T004, you'll be ready for:

1. **T005**: Background Location Tracking - Implement continuous location tracking with foreground service
2. **T006**: Battery-Optimized Location Strategy - Add motion-gated GPS and adaptive accuracy

## Notes

- This task focuses on **basic location capabilities** only
- Background tracking will be added in T005
- Battery optimization will be added in T006
- Keep location settings conservative for now (we'll optimize later)
- Test extensively on physical device
- Document any platform-specific quirks you encounter

---

**Created**: 2025-11-22
**Status**: Ready for implementation
**Assigned**: Next available developer
