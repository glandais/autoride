---
name: platform-config
description: Android API level and iOS version handling for AutoRide, including PlatformInfoService runtime detection, permission strategy per OS version, the privacy manifest, and what keeps the iOS process alive and relaunches it (T046). Use when working with AndroidManifest.xml, Info.plist, PrivacyInfo.xcprivacy, ios/Runner Swift code, background location permissions, notification permissions, required-reason API declarations, entitlements, or any code branching on Android 10/11/13+ or iOS 14/17+.
---

# Platform Configuration (AutoRide)

### Android

**API Level Handling**:
- Use `PlatformInfoService` to detect API level at runtime
- Android 10+ (API 29): Background location is separate permission
- Android 11+ (API 30): Background location requires settings navigation
- Android 13+ (API 33): Notification permission required

**Configuration Files**:
- `android/app/src/main/AndroidManifest.xml`: All permissions and service config
- See inline comments for detailed explanation of each permission

**Runtime Detection**:
```dart
final platformInfo = await ref.read(platformInfoServiceProvider.future);

if (platformInfo.isAndroid11Plus) {
  // Background location requires settings navigation
  await openAppSettings();
} else if (platformInfo.isAndroid10Plus) {
  // Can request background permission directly
  await requestBackgroundPermission();
}

if (platformInfo.isAndroid13Plus) {
  // Must request notification permission
  await requestNotificationPermission();
}
```

### iOS

**Version Handling**:
- Use `PlatformInfoService` to detect iOS version at runtime
- iOS 14+: User can choose "Allow Once" (temporary permission)
- iOS 17+: Privacy manifest required (PrivacyInfo.xcprivacy)

**Configuration Files**:
- `ios/Runner/Info.plist`: Permission descriptions and background modes
- `ios/Runner/PrivacyInfo.xcprivacy`: Privacy manifest (iOS 17+)
- `ios/Runner/AutoRideBackgroundSession.swift`: process survival + relaunch (T046)
- See inline comments for App Store compliance notes

**Keeping the process alive is platform configuration, not a runtime concern (T046)**:

On Android the foreground service holds the process whatever the pipeline is doing (L-067). iOS
has no such holder: the **CoreLocation session is the process's reason to be scheduled**, so the
motion-gated GPS design closed the only one and the OS suspended the app 40 s later — taking with
it the sensors that were supposed to re-open the gate (L-084). The two platforms therefore need
different things from their configuration, and neither substitutes for the other. Three rules
follow, and they are the ones to check before touching anything iOS-side:

1. **Something must always hold a CoreLocation session while detection is on.**
   `ios/Runner/AutoRideBackgroundSession.swift` runs a coarse 3 km session for exactly as long as
   the Dart GPS gate is closed, and stops it when geolocator's fine one takes over. The
   coordinator hands it the *complement* of the gate — never both at once, because a 3 km fix
   reaching the detection pipeline would cap the start confidence the way L-087's bogus 0 km/h did.
2. **Only three APIs relaunch a terminated iOS app**, and `geolocator` exposes none of them:
   `startMonitoringSignificantLocationChanges`, region monitoring, `startMonitoringVisits`. This
   is the one place in AutoRide where the "Flutter only" constraint could not hold. Monitoring is
   re-armed **synchronously** in `didFinishLaunchingWithOptions`, before `super` and before any
   Dart runs, from a `UserDefaults` flag: the event that relaunched the process is delivered only
   to a manager already monitoring by the time launch returns.
3. **Nothing else has to be declared, and this was verified rather than assumed** (2026-09-03,
   against Apple's documentation):
   - `Info.plist` needs nothing new. `UIBackgroundModes` containing `location` is the *only*
     requirement for `allowsBackgroundLocationUpdates` — and setting that property **without** the
     key is a fatal error that terminates the app.
   - No entitlement and no capability exist for any of the three APIs. AutoRide carries no
     `.entitlements` file at all, and does not need one.
   - CoreLocation is **not** a required-reason API. There are exactly five categories —
     `FileTimestamp`, `SystemBootTime`, `DiskSpace`, `ActiveKeyboards`, `UserDefaults` — and no
     location API is in any of them. Location is covered by `NSPrivacyCollectedDataTypes` plus the
     `NSLocation*UsageDescription` keys.
   - The `UserDefaults` reason **is** `CA92.1` ("only accessible to the app itself"), not
     `1C8F.1`, which is the App Group case. It was `1C8F.1` until 2026-09-03 in a project with no
     App Group — a false statement in the manifest. If a future change adds an App Group, that is
     when `1C8F.1` becomes the right answer, and not before.

Assumed limits, which are iOS's and have no API: a user force-quitting from the app switcher stops
all background delivery until they reopen the app; after a reboot nothing runs until the first
unlock, then nothing until the first significant change. Both are documented in
`tasks/T046-ios-background-survival.md` rather than worked around. That file also holds the
five-run device protocol — none of the above is validated by a test suite.

**Runtime Detection**:
```dart
final platformInfo = await ref.read(platformInfoServiceProvider.future);

if (platformInfo.isIos14Plus) {
  // Handle "Allow Once" temporary permission
  // Re-request on next app launch if needed
}

if (platformInfo.isIos17Plus) {
  // Privacy manifest is required for App Store submission
  // File is included automatically in build
}
```

### Platform Info Service

**Purpose**: Runtime detection of Android API levels and iOS versions for adaptive behavior

**Usage**:
```dart
// Get platform info
final platformInfo = await ref.read(platformInfoServiceProvider.future);

// Check specific API levels
if (platformInfo.isAndroid13Plus) { /* ... */ }
if (platformInfo.isIos17Plus) { /* ... */ }

// Get platform description
final service = ref.read(platformInfoServiceProvider.notifier);
final description = service.getPlatformDescription();
// Returns: "Android 13 (API 33)" or "iOS 17.0"

// Check if emulator
if (service.isEmulator()) {
  print('⚠️ Running on emulator. Use physical device for accurate testing.');
}
```

**Files**:
- `lib/core/platform/models/platform_info.dart`: Platform info model
- `lib/core/platform/services/platform_info_service.dart`: Platform detection service
- `lib/core/utils/platform_config_validator.dart`: Configuration validator

---
