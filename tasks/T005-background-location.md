# T005: Background Location Tracking

## Overview

Implement background location tracking using flutter_background_service to enable continuous trip tracking even when the app is backgrounded or closed. This is critical for automatic bike trip detection, allowing AutoRide to track trips without requiring the user to keep the app open.

**Status**: ☐ Pending
**Dependencies**: T004 (Basic Location Service)
**Estimate**: 3-4 hours
**Phase**: Phase 2 - Core Location & Sensors

## Prerequisites

Before starting this task, ensure:
- ✅ T004 completed (LocationService, LocationPermissionService, LocationData implemented)
- ✅ flutter_background_service dependency in pubspec.yaml
- ✅ Physical Android and iOS devices for testing (emulators insufficient)
- ✅ Understanding of foreground service requirements on both platforms

## Objectives

1. Configure flutter_background_service for location tracking
2. Implement background location service with foreground notification
3. Set up platform-specific permissions (Android & iOS)
4. Handle background location permission requests
5. Create integration layer between background service and existing LocationService
6. Ensure battery-efficient background tracking (<5% per hour)

## Implementation Steps

### Step 1: Create Background Service Infrastructure

Create the services directory:

```bash
mkdir -p lib/features/trip_detection/services
```

**File**: `lib/features/trip_detection/services/background_location_service.dart`

```dart
import 'dart:async';
import 'dart:ui';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';
import 'package:geolocator/geolocator.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'background_location_service.g.dart';

/// Background service entry point
/// This function runs in a separate isolate
@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  // Initialize DartPluginRegistrant for background isolate
  DartPluginRegistrant.ensureInitialized();

  if (service is AndroidServiceInstance) {
    // Handle foreground/background transitions
    service.on('setAsForeground').listen((event) {
      service.setAsForegroundService();
    });

    service.on('setAsBackground').listen((event) {
      service.setAsBackgroundService();
    });
  }

  // Stop service when requested
  service.on('stopService').listen((event) {
    service.stopSelf();
  });

  // Location tracking with battery-optimized settings
  Timer.periodic(const Duration(seconds: 30), (timer) async {
    if (service is AndroidServiceInstance) {
      if (await service.isForegroundService()) {
        try {
          // Get current location with optimized settings
          final position = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.medium, // Balance accuracy and battery
              distanceFilter: 15, // Update every 15 meters (cycling distance)
              timeLimit: Duration(seconds: 30),
            ),
          );

          // Update foreground notification with live data
          service.setForegroundNotificationInfo(
            title: "AutoRide - Tracking Trip",
            content: "Speed: ${(position.speed * 3.6).toStringAsFixed(1)} km/h",
          );

          // Send location data to main isolate
          service.invoke(
            'update',
            {
              "latitude": position.latitude,
              "longitude": position.longitude,
              "speed": position.speed,
              "accuracy": position.accuracy,
              "timestamp": position.timestamp.millisecondsSinceEpoch,
            },
          );
        } catch (e) {
          // Handle location errors gracefully
          service.invoke('error', {"message": e.toString()});
        }
      }
    }
  });
}

@riverpod
class BackgroundLocationService extends _$BackgroundLocationService {
  final service = FlutterBackgroundService();

  @override
  Future<bool> build() async {
    return await _isServiceRunning();
  }

  /// Initialize background service (call once at app startup)
  Future<void> initialize() async {
    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onStart,
        autoStart: false, // Don't auto-start on boot
        isForegroundMode: true, // Critical: keeps service alive
        notificationChannelId: 'autoride_tracking',
        initialNotificationTitle: 'AutoRide',
        initialNotificationContent: 'Initializing trip tracking...',
        foregroundServiceNotificationId: 888,
        foregroundServiceTypes: [AndroidForegroundType.location],
      ),
      iosConfiguration: IosConfiguration(
        autoStart: false,
        onForeground: onStart,
        onBackground: onIosBackground,
      ),
    );
  }

  /// Start background location tracking
  Future<void> startTracking() async {
    final isRunning = await service.isRunning();
    if (!isRunning) {
      await service.startService();
      state = AsyncValue.data(true);
    }
  }

  /// Stop background location tracking
  Future<void> stopTracking() async {
    final isRunning = await service.isRunning();
    if (isRunning) {
      service.invoke("stopService");
      state = AsyncValue.data(false);
    }
  }

  /// Listen to location updates from background service
  Stream<Map<String, dynamic>?> get locationUpdates {
    return service.on('update');
  }

  /// Listen to errors from background service
  Stream<Map<String, dynamic>?> get errors {
    return service.on('error');
  }

  Future<bool> _isServiceRunning() async {
    return await service.isRunning();
  }
}

/// iOS background handler
@pragma('vm:entry-point')
bool onIosBackground(ServiceInstance service) {
  WidgetsFlutterBinding.ensureInitialized();
  return true;
}
```

### Step 2: Extend LocationPermissionService for Background Permission

**File**: `lib/features/trip_detection/data/services/location_permission_service.dart`

Add the following method to the `LocationPermissionService` class:

```dart
/// Request background location permission (Android 10+, iOS Always)
/// Must be called AFTER foreground permission is granted
Future<LocationPermissionStatus> requestBackgroundPermission() async {
  // First ensure foreground permission is granted
  final currentStatus = await checkPermission();
  if (currentStatus != LocationPermissionStatus.granted) {
    // Must have foreground permission first
    return currentStatus;
  }

  // Request always permission (includes background)
  final permission = await Geolocator.requestPermission();

  final status = switch (permission) {
    LocationPermission.always => LocationPermissionStatus.granted,
    LocationPermission.whileInUse => LocationPermissionStatus.denied, // Needs always for background
    LocationPermission.denied => LocationPermissionStatus.denied,
    LocationPermission.deniedForever => LocationPermissionStatus.deniedForever,
    _ => LocationPermissionStatus.notDetermined,
  };

  state = AsyncValue.data(status);
  return status;
}

/// Check if background location permission is granted
Future<bool> hasBackgroundPermission() async {
  final permission = await Geolocator.checkPermission();
  return permission == LocationPermission.always;
}
```

### Step 3: Configure Android Platform

**File**: `android/app/src/main/AndroidManifest.xml`

Update the manifest with all required permissions and service configuration:

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <!-- Location Permissions -->
    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
    <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />

    <!-- Background Location Permission (Android 10+) -->
    <uses-permission android:name="android.permission.ACCESS_BACKGROUND_LOCATION" />

    <!-- Foreground Service Permissions (Android 9+) -->
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_LOCATION" />

    <!-- Wake Lock (keeps service alive) -->
    <uses-permission android:name="android.permission.WAKE_LOCK" />

    <!-- Internet (for future features) -->
    <uses-permission android:name="android.permission.INTERNET"/>

    <application
        android:label="AutoRide"
        android:name="${applicationName}"
        android:icon="@mipmap/ic_launcher">

        <!-- Background Location Service -->
        <service
            android:name="id.flutter.flutter_background_service.BackgroundService"
            android:foregroundServiceType="location"
            android:exported="false" />

        <activity
            android:name=".MainActivity"
            android:exported="true"
            android:launchMode="singleTop"
            android:taskAffinity=""
            android:theme="@style/LaunchTheme"
            android:configChanges="orientation|keyboardHidden|keyboard|screenSize|smallestScreenSize|locale|layoutDirection|fontScale|screenLayout|density|uiMode"
            android:hardwareAccelerated="true"
            android:windowSoftInputMode="adjustResize">
            <meta-data
              android:name="io.flutter.embedding.android.NormalTheme"
              android:resource="@style/NormalTheme"
              />
            <intent-filter>
                <action android:name="android.intent.action.MAIN"/>
                <category android:name="android.intent.category.LAUNCHER"/>
            </intent-filter>
        </activity>

        <meta-data
            android:name="flutterEmbedding"
            android:value="2" />
    </application>

    <queries>
        <intent>
            <action android:name="android.intent.action.PROCESS_TEXT"/>
            <data android:mimeType="text/plain"/>
        </intent>
    </queries>
</manifest>
```

### Step 4: Configure iOS Platform

**File**: `ios/Runner/Info.plist`

Add location usage descriptions and background modes:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!-- Location Usage Descriptions (REQUIRED) -->
    <key>NSLocationWhenInUseUsageDescription</key>
    <string>AutoRide needs location access to automatically detect your bike trips.</string>

    <key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
    <string>AutoRide needs background location to track trips while the app is closed or in the background.</string>

    <key>NSLocationAlwaysUsageDescription</key>
    <string>AutoRide needs background location to track trips while the app is closed.</string>

    <!-- Background Modes (REQUIRED for background location) -->
    <key>UIBackgroundModes</key>
    <array>
        <string>location</string>
        <string>fetch</string>
        <string>processing</string>
    </array>

    <!-- Existing keys remain unchanged -->
    <key>CFBundleDevelopmentRegion</key>
    <string>$(DEVELOPMENT_LANGUAGE)</string>
    <key>CFBundleDisplayName</key>
    <string>AutoRide</string>
    <key>CFBundleExecutable</key>
    <string>$(EXECUTABLE_NAME)</string>
    <key>CFBundleIdentifier</key>
    <string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>autoride</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$(FLUTTER_BUILD_NAME)</string>
    <key>CFBundleSignature</key>
    <string>????</string>
    <key>CFBundleVersion</key>
    <string>$(FLUTTER_BUILD_NUMBER)</string>
    <key>LSRequiresIPhoneOS</key>
    <true/>
    <key>UILaunchStoryboardName</key>
    <string>LaunchScreen</string>
    <key>UIMainStoryboardFile</key>
    <string>Main</string>
    <key>UISupportedInterfaceOrientations</key>
    <array>
        <string>UIInterfaceOrientationPortrait</string>
        <string>UIInterfaceOrientationLandscapeLeft</string>
        <string>UIInterfaceOrientationLandscapeRight</string>
    </array>
    <key>UISupportedInterfaceOrientations~ipad</key>
    <array>
        <string>UIInterfaceOrientationPortrait</string>
        <string>UIInterfaceOrientationPortraitUpsideDown</string>
        <string>UIInterfaceOrientationLandscapeLeft</string>
        <string>UIInterfaceOrientationLandscapeRight</string>
    </array>
    <key>CADisableMinimumFrameDurationOnPhone</key>
    <true/>
    <key>UIApplicationSupportsIndirectInputEvents</key>
    <true/>
</dict>
</plist>
```

### Step 5: Create Integration Provider

Create presentation providers directory:

```bash
mkdir -p lib/features/trip_detection/presentation/providers
```

**File**: `lib/features/trip_detection/presentation/providers/location_tracking_provider.dart`

```dart
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../data/services/location_permission_service.dart';
import '../../services/background_location_service.dart';
import '../../domain/models/location_data.dart';

part 'location_tracking_provider.g.dart';

@riverpod
class LocationTracking extends _$LocationTracking {
  @override
  Stream<LocationData?> build() async* {
    // Listen to background service updates
    final backgroundService = ref.watch(backgroundLocationServiceProvider.notifier);

    await for (final update in backgroundService.locationUpdates) {
      if (update != null) {
        yield LocationData(
          latitude: update['latitude'] as double,
          longitude: update['longitude'] as double,
          accuracy: update['accuracy'] as double,
          altitude: 0.0, // Not available in simplified update
          speed: update['speed'] as double,
          heading: 0.0, // Not available in simplified update
          timestamp: DateTime.fromMillisecondsSinceEpoch(
            update['timestamp'] as int,
          ),
        );
      }
    }
  }

  /// Start background location tracking
  /// Requests background permission if not granted
  Future<void> startBackgroundTracking() async {
    // Check and request background permission
    final permissionService = ref.read(locationPermissionServiceProvider.notifier);

    // First check if we have foreground permission
    final currentStatus = await permissionService.checkPermission();
    if (currentStatus != LocationPermissionStatus.granted) {
      // Request foreground permission first
      final foregroundStatus = await permissionService.requestPermission();
      if (foregroundStatus != LocationPermissionStatus.granted) {
        throw LocationTrackingException(
          'Foreground location permission required',
          LocationTrackingErrorType.permissionDenied,
        );
      }
    }

    // Now request background permission
    final backgroundStatus = await permissionService.requestBackgroundPermission();
    if (backgroundStatus != LocationPermissionStatus.granted) {
      throw LocationTrackingException(
        'Background location permission required for trip tracking',
        LocationTrackingErrorType.backgroundPermissionDenied,
      );
    }

    // Initialize and start background service
    final backgroundService = ref.read(backgroundLocationServiceProvider.notifier);
    await backgroundService.initialize();
    await backgroundService.startTracking();
  }

  /// Stop background location tracking
  Future<void> stopBackgroundTracking() async {
    final backgroundService = ref.read(backgroundLocationServiceProvider.notifier);
    await backgroundService.stopTracking();
  }

  /// Check if background tracking is currently active
  Future<bool> isTrackingActive() async {
    final backgroundService = ref.read(backgroundLocationServiceProvider);
    return backgroundService.value ?? false;
  }
}

/// Exception types for location tracking
enum LocationTrackingErrorType {
  permissionDenied,
  backgroundPermissionDenied,
  serviceNotAvailable,
  unknown,
}

/// Custom exception for location tracking errors
class LocationTrackingException implements Exception {
  final String message;
  final LocationTrackingErrorType type;

  LocationTrackingException(this.message, this.type);

  @override
  String toString() => 'LocationTrackingException: $message';
}
```

### Step 6: Run Code Generation

Generate the required files:

```bash
flutter pub run build_runner build --delete-conflicting-outputs
```

Or start the watcher:

```bash
flutter pub run build_runner watch
```

### Step 7: Create Unit Tests

**File**: `test/features/trip_detection/services/background_location_service_test.dart`

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:autoride/features/trip_detection/services/background_location_service.dart';

void main() {
  group('BackgroundLocationService', () {
    test('should initialize service configuration', () async {
      // This test verifies service can be created
      // Actual functionality requires platform channel testing
      expect(BackgroundLocationService, isNotNull);
    });

    // Note: Full integration tests require physical devices
    // as background services don't work in emulators
  });
}
```

## Testing

### Manual Testing Checklist

**Critical: Test on Physical Devices Only** (emulators don't support background location properly)

#### Android Testing (Test on Android 10, 11, 12+)

1. **Initial Setup**:
   - [ ] Install app on physical Android device
   - [ ] Grant "While using app" permission when prompted
   - [ ] Verify foreground location works

2. **Background Permission Flow**:
   - [ ] Request background tracking
   - [ ] On Android 10: Should see "Allow all the time" option
   - [ ] On Android 11+: Should redirect to settings with instruction
   - [ ] Grant "Allow all the time" permission
   - [ ] Verify background permission granted

3. **Foreground Service**:
   - [ ] Start background tracking
   - [ ] Verify notification appears with "AutoRide - Tracking Trip"
   - [ ] Verify notification shows live speed updates
   - [ ] Notification should be persistent (can't be swiped away)

4. **Background Tracking**:
   - [ ] Press home button (app in background)
   - [ ] Notification should remain visible
   - [ ] Move around (walk/bike) for 5 minutes
   - [ ] Return to app - verify location updates were received
   - [ ] Check battery usage (should be <5% for 1 hour)

5. **App Killed**:
   - [ ] Swipe app away from recent apps
   - [ ] Notification should remain
   - [ ] Service should continue (verify with logcat)
   - [ ] Reopen app - verify tracking still active

6. **Stop Tracking**:
   - [ ] Stop tracking from app
   - [ ] Verify notification disappears
   - [ ] Verify service stops (no battery drain)

#### iOS Testing (Test on iOS 14, 15, 16+)

1. **Initial Setup**:
   - [ ] Install app on physical iOS device
   - [ ] Grant "While Using App" permission
   - [ ] Verify foreground location works

2. **Background Permission Flow**:
   - [ ] Request background tracking
   - [ ] Should see "Change to Always Allow" prompt
   - [ ] Select "Change to Always Allow"
   - [ ] Verify background permission granted

3. **Background Tracking**:
   - [ ] Start background tracking
   - [ ] Background app
   - [ ] Move around for 5 minutes
   - [ ] Return to app - verify location updates received
   - [ ] Check battery usage in Settings

4. **App Terminated**:
   - [ ] Force quit app (swipe up in app switcher)
   - [ ] iOS may terminate background location
   - [ ] Document behavior (iOS is more restrictive)

### Integration Testing

**File**: `integration_test/background_tracking_test.dart`

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:autoride/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Background tracking complete flow', (tester) async {
    app.main();
    await tester.pumpAndSettle();

    // This is a placeholder - actual implementation requires:
    // 1. Permission granting automation (difficult on real devices)
    // 2. Background app simulation
    // 3. Location update verification
    // 4. Battery usage measurement

    // For now, manual testing on physical devices is more reliable
  });
}
```

### Battery Profiling

**Android**:
```bash
# Run app on device
flutter run --release

# Monitor with Android Studio Battery Profiler:
# 1. Open Android Studio
# 2. View → Tool Windows → Profiler
# 3. Select device and app
# 4. Choose "Energy" profiler
# 5. Start tracking, measure for 1 hour

# Target: <5% battery drain per hour
```

**iOS**:
```bash
# Run app on device
flutter run --release

# Monitor with Xcode Energy Log:
# 1. Window → Devices and Simulators
# 2. Select device
# 3. View Device Logs
# 4. Filter by "Energy"
# 5. Monitor location energy usage

# Target: Low energy impact
```

## Acceptance Criteria

- [ ] Background service starts successfully on Android and iOS
- [ ] Foreground notification appears on Android with live speed display
- [ ] Location updates continue when app is backgrounded
- [ ] Background location permission requested progressively (foreground → background)
- [ ] Service stops cleanly when tracking ends
- [ ] Notification disappears when tracking stops
- [ ] Battery usage <5% per hour during active tracking
- [ ] AndroidManifest.xml has all required permissions and service configuration
- [ ] Info.plist has location descriptions and background modes
- [ ] Code generation files created (.g.dart)
- [ ] Unit tests created (even if basic)
- [ ] Flutter analyze passes with no errors
- [ ] Physical device testing confirms functionality on Android 10+ and iOS 14+

## Common Pitfalls

### 1. Service Killed by Android OS
**Problem**: Android aggressively kills background services to save battery.

**Solution**:
- Use foreground service (`isForegroundMode: true`)
- Show persistent notification (can't be dismissed)
- Set `foregroundServiceType="location"` in manifest

**Detection**: Monitor with `adb logcat` - look for service lifecycle events

### 2. Background Permission Denied (Android 11+)
**Problem**: Android 11+ doesn't show "Allow all the time" in initial dialog.

**Solution**:
- Request foreground permission first
- Then request background permission
- User must manually select "Allow all the time" in settings
- Provide guidance to open settings

**Code Example**:
```dart
if (Platform.isAndroid) {
  final androidInfo = await DeviceInfoPlugin().androidInfo;
  if (androidInfo.version.sdkInt >= 30) {
    // Android 11+ - guide user to settings
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Background Permission'),
        content: Text(
          'For continuous tracking, please:\n'
          '1. Tap Settings below\n'
          '2. Select Location\n'
          '3. Choose "Allow all the time"'
        ),
        actions: [
          TextButton(
            onPressed: () => Geolocator.openAppSettings(),
            child: Text('Open Settings'),
          ),
        ],
      ),
    );
  }
}
```

### 3. Excessive Battery Drain
**Problem**: Battery drains faster than acceptable (>5% per hour).

**Solution**:
- Use `LocationAccuracy.medium` not `best`
- Set `distanceFilter: 15` (meters)
- Increase update interval (30s is good for cycling)
- Only run service during active trips

**Profiling**:
```bash
# Android
adb shell dumpsys batterystats --reset
# Use app for 1 hour
adb shell dumpsys batterystats

# Look for location wakelock usage
```

### 4. Notification Not Showing (Android)
**Problem**: Foreground service runs but no notification appears.

**Solution**:
- Verify `foregroundServiceType="location"` in AndroidManifest.xml
- Check notification channel is created
- Ensure `isForegroundMode: true` in configuration

**Debug**:
```bash
adb logcat | grep "Notification"
```

### 5. iOS Background Location Stops
**Problem**: iOS terminates background location after some time.

**Solution**:
- iOS is more restrictive than Android
- Background location works best with "significant location changes" mode
- May need to wake app periodically with background fetch
- Document iOS limitations in app

### 6. App Crashes in Background
**Problem**: App crashes when running in background isolate.

**Solution**:
- Ensure `DartPluginRegistrant.ensureInitialized()` is called
- Don't use UI-related code in background service
- Catch and handle all exceptions in service
- Use `@pragma('vm:entry-point')` on service functions

## Resources

### Official Documentation
- [flutter_background_service](https://pub.dev/packages/flutter_background_service)
- [Geolocator Platform Setup](https://pub.dev/packages/geolocator#setup)
- [Android Foreground Services](https://developer.android.com/develop/background-work/services/foreground-services)
- [iOS Background Location](https://developer.apple.com/documentation/corelocation/getting_the_user_s_location/handling_location_events_in_the_background)

### Platform-Specific Guides
- [Android Background Location Best Practices](https://developer.android.com/training/location/permissions)
- [iOS Location Permission Guide](https://developer.apple.com/documentation/corelocation/requesting_authorization_to_use_location_services)

### Battery Optimization
- [Android Battery Optimization](https://developer.android.com/topic/performance/power)
- [iOS Energy Efficiency Guide](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/EnergyGuide-iOS/)

### Related Tasks
- **Previous**: T004 - Basic Location Service
- **Next**: T006 - Battery-Optimized Location Strategy (depends on T005, T007)
- **Related**: T007 - Sensor Integration (can be done in parallel)

## Next Steps

After completing T005, you'll be ready for:

1. **T006**: Battery-Optimized Location Strategy
   - Motion-gated GPS activation
   - Adaptive accuracy based on movement
   - Power state awareness

2. **T007**: Sensor Integration (can start in parallel with T006)
   - Accelerometer and gyroscope setup
   - Basic movement detection

## Notes

- **Physical Device Testing is Mandatory**: Background services don't work properly in emulators
- **Platform Differences**: Android and iOS handle background location differently
- **Battery is Critical**: Users will uninstall if battery drain is excessive
- **Progressive Permissions**: Ask for background permission only when needed (first trip start)
- **Graceful Degradation**: App should work even if background permission is denied
- **User Education**: Explain why background permission is needed

---

**Created**: 2025-11-22
**Status**: Ready for implementation
**Assigned**: Next available developer
