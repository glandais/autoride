---
name: platform-config
description: Android API level and iOS version handling for AutoRide, including PlatformInfoService runtime detection, permission strategy per OS version, and the privacy manifest. Use when working with AndroidManifest.xml, Info.plist, PrivacyInfo.xcprivacy, background location permissions, notification permissions, or any code branching on Android 10/11/13+ or iOS 14/17+.
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
- See inline comments for App Store compliance notes

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
