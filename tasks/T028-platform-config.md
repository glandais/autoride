# T028: Platform-Specific Configuration

**Phase**: Phase 7 - Permissions & Platform
**Dependencies**: T027 (Permission Handler Implementation)
**Estimate**: 1-2 hours
**Status**: ✅ Complete
**Completed**: 2025-11-23

---

## Overview

Review, validate, and enhance platform-specific configurations (AndroidManifest.xml, Info.plist) to ensure production-readiness, app store compliance, and optimal integration with the permission handling system implemented in T027. This task focuses on documentation, validation, and minor enhancements rather than major configuration changes.

**Goal**: Ensure all platform configurations are production-ready, properly documented, compliant with latest platform requirements (Android 14, iOS 17), and optimally integrated with existing permission and notification systems.

---

## Objectives

1. ✅ Validate existing AndroidManifest.xml configuration against Android 8-14 requirements
2. ✅ Validate existing Info.plist configuration against iOS 13-17 requirements
3. ☐ Add comprehensive inline documentation to AndroidManifest.xml
4. ☐ Enhance Info.plist descriptions for App Store compliance
5. ☐ Create iOS Privacy Manifest (PrivacyInfo.xcprivacy) for iOS 17+
6. ☐ Implement Platform Info Service for runtime API detection
7. ☐ Create platform configuration validation utilities
8. ☐ Document platform-specific testing procedures
9. ☐ Verify app store submission readiness

---

## Context & Problem

**Current State**:
- ✅ **AndroidManifest.xml**: All required permissions configured (from T005, T025)
  - Location permissions (fine, coarse, background)
  - Foreground service permissions
  - Notification permission (Android 13+)
  - Background service declaration
- ✅ **Info.plist**: Basic location descriptions and background modes (from T005)
  - Location usage descriptions (When In Use, Always)
  - Background modes (location, fetch, processing)
- ✅ **T027**: Permission handler service implemented
- ✅ **T025**: Notification service with channels configured

**Why We Need This**:
1. **Production Readiness**: Current configs work but lack documentation and validation
2. **App Store Compliance**: iOS 17+ requires Privacy Manifest for tracking APIs
3. **Best Practices**: Need comprehensive comments for future maintenance
4. **Runtime Detection**: Need utilities to detect API levels and adjust behavior
5. **Testing Documentation**: Need platform-specific testing procedures
6. **Future-Proofing**: Prepare for Android 15, iOS 18 changes

**What's Missing**:
- ❌ Inline documentation in AndroidManifest.xml explaining each permission
- ❌ Enhanced Info.plist descriptions for better App Store compliance
- ❌ iOS Privacy Manifest (PrivacyInfo.xcprivacy) for iOS 17+
- ❌ Platform Info Service for runtime API detection
- ❌ Configuration validation utilities
- ❌ Comprehensive platform testing documentation

---

## Design Decisions

### Android Strategy

**Target API Levels**:
- **Minimum SDK**: API 26 (Android 8.0) - For modern location APIs
- **Target SDK**: API 34 (Android 14) - Latest stable version
- **Compile SDK**: API 34 (Android 14)

**Permission Philosophy**:
- **Progressive Disclosure**: Request permissions when needed, not all at once
- **User Education**: Clear descriptions via T027 rationale dialogs
- **Graceful Degradation**: App works even if permissions denied

**API-Specific Handling**:
```yaml
API 26-28 (Android 8-9):
  - Basic foreground service support
  - Background location permission not separate

API 29 (Android 10):
  - ACCESS_BACKGROUND_LOCATION introduced
  - Two-step permission flow required

API 30+ (Android 11+):
  - Background location requires settings navigation
  - User must manually select "Allow all the time"

API 31+ (Android 12+):
  - Precise vs approximate location options
  - Foreground service type required

API 33+ (Android 13+):
  - POST_NOTIFICATIONS runtime permission required
  - Notification channels creation before posting
```

### iOS Strategy

**Target iOS Versions**:
- **Minimum Deployment**: iOS 13.0 - For modern location APIs
- **Current Target**: iOS 17.0 - Latest features

**Permission Philosophy**:
- **Transparency**: Clear, honest descriptions in Info.plist
- **Minimal Scope**: Request only what's needed
- **Privacy First**: Comply with Apple's privacy guidelines

**iOS Version Handling**:
```yaml
iOS 13:
  - Basic location permissions
  - Background location requires "Always Allow"

iOS 14:
  - "Allow Once" option introduced
  - Approximate location option
  - Must handle temporary permissions

iOS 15:
  - Enhanced privacy indicators
  - Location button for temporary access

iOS 16:
  - No major permission changes
  - Continued privacy emphasis

iOS 17:
  - Privacy Manifest required for tracking APIs
  - Must declare reason for API usage
```

---

## Technical Specification

### File Structure

```
android/app/src/main/
└── AndroidManifest.xml          # Enhanced with documentation

ios/Runner/
├── Info.plist                   # Enhanced descriptions
└── PrivacyInfo.xcprivacy        # NEW: Privacy manifest

lib/core/
├── platform/                    # NEW: Platform utilities
│   ├── models/
│   │   └── platform_info.dart
│   └── services/
│       └── platform_info_service.dart
└── utils/
    └── platform_config_validator.dart  # NEW: Validation

test/core/platform/
└── platform_info_service_test.dart
```

---

## Implementation Steps

### Step 1: Enhance AndroidManifest.xml Documentation

**File**: `android/app/src/main/AndroidManifest.xml`

**Action**: Add comprehensive inline comments explaining each permission and configuration.

**Enhanced Version**:

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <!--
    ============================================
    LOCATION PERMISSIONS
    ============================================
    Required for core trip tracking functionality.
    Progressive disclosure: Requested via T027 PermissionHandlerService.
    -->

    <!--
    ACCESS_FINE_LOCATION:
    - Required for precise GPS coordinates
    - Accuracy: ~5-10 meters (ideal for cycling routes)
    - Battery impact: Moderate (optimized in T006)
    - Requested: During onboarding (T021)
    - API Level: All (26+)
    -->
    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />

    <!--
    ACCESS_COARSE_LOCATION:
    - Fallback for approximate location (~100 meters)
    - Used when user denies fine location
    - Battery impact: Low
    - API Level: All (26+)
    - Note: Android 12+ allows user to choose "Approximate" location
    -->
    <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />

    <!--
    ACCESS_BACKGROUND_LOCATION:
    - Required for automatic trip detection when app is closed
    - Introduced: Android 10 (API 29)
    - Request flow: Foreground permission → Background permission
    - Android 11+: User must manually enable in settings
    - Requested: When user enables background tracking in settings (T024)
    - Battery optimization: Motion-gated GPS (T006)
    -->
    <uses-permission android:name="android.permission.ACCESS_BACKGROUND_LOCATION" />

    <!--
    ============================================
    FOREGROUND SERVICE PERMISSIONS
    ============================================
    Required for reliable background location tracking.
    Android kills background services aggressively - foreground service prevents this.
    -->

    <!--
    FOREGROUND_SERVICE:
    - Allows app to run foreground service
    - Required: Android 9+ (API 28+)
    - Shows persistent notification (cannot be dismissed)
    - Prevents service from being killed by Android
    -->
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE" />

    <!--
    FOREGROUND_SERVICE_LOCATION:
    - Declares foreground service will use location
    - Required: Android 10+ (API 29+)
    - Must match android:foregroundServiceType in service declaration
    - Enforced strictly in Android 14+ (API 34+)
    -->
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_LOCATION" />

    <!--
    ============================================
    SYSTEM PERMISSIONS
    ============================================
    -->

    <!--
    WAKE_LOCK:
    - Prevents device from sleeping during active tracking
    - Used by flutter_background_service
    - Battery impact: Minimal (only during active trips)
    - Automatically released when service stops
    -->
    <uses-permission android:name="android.permission.WAKE_LOCK" />

    <!--
    POST_NOTIFICATIONS:
    - Required for showing notifications on Android 13+ (API 33+)
    - Runtime permission (requested via T027)
    - Required for foreground service notification
    - Requested: During onboarding (T021)
    - Note: Apps targeting API 33+ MUST request this
    -->
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>

    <!--
    INTERNET:
    - Future use: Trip sync, map tiles, etc.
    - Currently: Not actively used
    - No runtime permission required
    -->
    <uses-permission android:name="android.permission.INTERNET"/>

    <application
        android:label="autoride"
        android:name="${applicationName}"
        android:icon="@mipmap/ic_launcher">

        <!--
        ============================================
        BACKGROUND LOCATION SERVICE
        ============================================
        Service declaration for flutter_background_service.
        Runs in foreground mode with persistent notification.

        Configuration:
        - android:name: Must match flutter_background_service package
        - android:foregroundServiceType: "location" (required for location tracking)
        - android:exported: "false" (not accessible from other apps)

        Usage:
        - Started by BackgroundLocationService (T005)
        - Managed by LocationTracking provider
        - Notification created by NotificationService (T025)
        -->
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

    <!--
    Required for text processing functionality.
    See: https://developer.android.com/training/package-visibility
    -->
    <queries>
        <intent>
            <action android:name="android.intent.action.PROCESS_TEXT"/>
            <data android:mimeType="text/plain"/>
        </intent>
    </queries>
</manifest>
```

**Changes Made**:
- ✅ Added comprehensive comments for each permission
- ✅ Documented API level requirements
- ✅ Explained battery impact and usage patterns
- ✅ Cross-referenced related tasks (T006, T021, T024, T025, T027)
- ✅ Added section headers for better organization
- ✅ Documented service configuration details

---

### Step 2: Enhance Info.plist Descriptions

**File**: `ios/Runner/Info.plist`

**Action**: Improve location usage descriptions for better App Store compliance and user clarity.

**Enhanced Version**:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>$(DEVELOPMENT_LANGUAGE)</string>
	<key>CFBundleDisplayName</key>
	<string>Autoride</string>
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

	<!--
	============================================
	LOCATION PERMISSION DESCRIPTIONS
	============================================
	CRITICAL: These descriptions appear in iOS permission dialogs.
	Apple Review Guidelines require clear, specific explanations.
	-->

	<!--
	When In Use Permission:
	Requested: During onboarding (T021)
	Used for: Trip tracking when app is open
	iOS 14+: User can choose "Allow Once", "While Using", or "Don't Allow"
	-->
	<key>NSLocationWhenInUseUsageDescription</key>
	<string>AutoRide tracks your location to record cycling routes, calculate distance and speed, and map your trips while you're using the app.</string>

	<!--
	Always Permission (Background Location):
	Requested: When user enables automatic trip detection in settings (T024)
	Used for: Automatic trip start/stop detection
	iOS Requirement: Must explain BOTH foreground and background use
	Apple Guidelines: Must clearly explain why background access is needed
	-->
	<key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
	<string>AutoRide needs background location access to automatically detect when you start cycling, even when the app is closed. This enables hands-free trip tracking without needing to manually start or stop recording. Your location data stays private on your device and is never shared.</string>

	<!--
	Legacy Always Permission:
	Required for: iOS 10 compatibility (though our min is iOS 13)
	Apple requires this even if not supporting iOS 10
	-->
	<key>NSLocationAlwaysUsageDescription</key>
	<string>AutoRide needs background location access to automatically detect your cycling trips when the app is closed.</string>

	<!--
	============================================
	BACKGROUND MODES
	============================================
	Declares app capabilities for background execution.
	Required for background location tracking.
	-->
	<key>UIBackgroundModes</key>
	<array>
		<!-- Location updates while app is in background -->
		<string>location</string>
		<!-- Periodic background updates -->
		<string>fetch</string>
		<!-- Background processing tasks -->
		<string>processing</string>
	</array>
</dict>
</plist>
```

**Improvements**:
- ✅ Enhanced NSLocationWhenInUseUsageDescription with specific use cases
- ✅ Improved NSLocationAlwaysAndWhenInUseUsageDescription with privacy assurance
- ✅ Added inline comments explaining each key
- ✅ Documented when each permission is requested
- ✅ Added App Store compliance notes

---

### Step 3: Create iOS Privacy Manifest

**File**: `ios/Runner/PrivacyInfo.xcprivacy` (NEW)

**Why Needed**:
- **iOS 17+**: Apple requires Privacy Manifest for apps using certain APIs
- **App Store Requirement**: Starting Spring 2024, required for tracking APIs
- **Our Use Case**: We use location APIs, which require declaration

**Action**: Create new privacy manifest file.

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<!--
	============================================
	PRIVACY TRACKING DOMAINS
	============================================
	Domains used for tracking. AutoRide does NOT track users.
	-->
	<key>NSPrivacyTrackingDomains</key>
	<array>
		<!-- No tracking domains - we don't track users -->
	</array>

	<!--
	============================================
	PRIVACY TRACKING ENABLED
	============================================
	Does this app track users? NO - AutoRide is privacy-focused.
	All data stays on device, nothing is uploaded or shared.
	-->
	<key>NSPrivacyTracking</key>
	<false/>

	<!--
	============================================
	PRIVACY COLLECTED DATA TYPES
	============================================
	Declares what data is collected and how it's used.
	Required for App Privacy Details in App Store listing.
	-->
	<key>NSPrivacyCollectedDataTypes</key>
	<array>
		<!--
		Location Data:
		- Collected: YES (core functionality)
		- Linked to User: NO (stays on device)
		- Used for Tracking: NO
		- Purpose: App functionality only
		-->
		<dict>
			<key>NSPrivacyCollectedDataType</key>
			<string>NSPrivacyCollectedDataTypeLocation</string>
			<key>NSPrivacyCollectedDataTypeLinked</key>
			<false/>
			<key>NSPrivacyCollectedDataTypeTracking</key>
			<false/>
			<key>NSPrivacyCollectedDataTypePurposes</key>
			<array>
				<string>NSPrivacyCollectedDataTypePurposeAppFunctionality</string>
			</array>
		</dict>

		<!--
		Device ID (for local database):
		- Collected: YES (device identifier for local storage)
		- Linked to User: NO
		- Used for Tracking: NO
		- Purpose: App functionality only
		-->
		<dict>
			<key>NSPrivacyCollectedDataType</key>
			<string>NSPrivacyCollectedDataTypeDeviceID</string>
			<key>NSPrivacyCollectedDataTypeLinked</key>
			<false/>
			<key>NSPrivacyCollectedDataTypeTracking</key>
			<false/>
			<key>NSPrivacyCollectedDataTypePurposes</key>
			<array>
				<string>NSPrivacyCollectedDataTypePurposeAppFunctionality</string>
			</array>
		</dict>
	</array>

	<!--
	============================================
	PRIVACY ACCESSED API TYPES
	============================================
	Required APIs that need privacy declaration (iOS 17+).
	Must declare WHY we use each API category.
	-->
	<key>NSPrivacyAccessedAPITypes</key>
	<array>
		<!--
		File Timestamp APIs:
		Used for SQLite database (trip storage)
		Reason: 0A2A.1 - Accessing files in app container
		-->
		<dict>
			<key>NSPrivacyAccessedAPIType</key>
			<string>NSPrivacyAccessedAPICategoryFileTimestamp</string>
			<key>NSPrivacyAccessedAPITypeReasons</key>
			<array>
				<string>0A2A.1</string>
			</array>
		</dict>

		<!--
		User Defaults APIs:
		Used for app settings (SharedPreferences)
		Reason: 1C8F.1 - Accessing user defaults in app group
		-->
		<dict>
			<key>NSPrivacyAccessedAPIType</key>
			<string>NSPrivacyAccessedAPICategoryUserDefaults</string>
			<key>NSPrivacyAccessedAPITypeReasons</key>
			<array>
				<string>1C8F.1</string>
			</array>
		</dict>
	</array>
</dict>
</plist>
```

**API Reason Codes** (Apple Documentation):
- **0A2A.1**: Accessing files in app container, not using file timestamp
- **1C8F.1**: Accessing user defaults in app container or group

**Note**: These codes must match Apple's official reasons. See: [Apple Privacy Manifest Documentation](https://developer.apple.com/documentation/bundleresources/privacy_manifest_files)

---

### Step 4: Create Platform Info Service

**File**: `lib/core/platform/models/platform_info.dart`

```dart
import 'package:freezed_annotation/freezed_annotation.dart';

part 'platform_info.freezed.dart';

/// Platform information for runtime adaptation
@freezed
sealed class PlatformInfo with _$PlatformInfo {
  const PlatformInfo._();

  const factory PlatformInfo({
    required PlatformType type,
    required String version,
    required int apiLevel, // Android only
    required bool isPhysicalDevice,
  }) = _PlatformInfo;

  /// Check if Android API level meets minimum requirement
  bool androidApiAtLeast(int minimumApiLevel) {
    return type == PlatformType.android && apiLevel >= minimumApiLevel;
  }

  /// Check if iOS version meets minimum requirement
  bool iosVersionAtLeast(int major, [int minor = 0]) {
    if (type != PlatformType.ios) return false;

    final parts = version.split('.');
    final currentMajor = int.tryParse(parts[0]) ?? 0;
    final currentMinor = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;

    if (currentMajor > major) return true;
    if (currentMajor == major && currentMinor >= minor) return true;
    return false;
  }

  /// Check if running on Android 10+ (scoped storage, background location changes)
  bool get isAndroid10Plus => androidApiAtLeast(29);

  /// Check if running on Android 11+ (background location requires settings)
  bool get isAndroid11Plus => androidApiAtLeast(30);

  /// Check if running on Android 12+ (precise vs approximate location)
  bool get isAndroid12Plus => androidApiAtLeast(31);

  /// Check if running on Android 13+ (notification permission required)
  bool get isAndroid13Plus => androidApiAtLeast(33);

  /// Check if running on iOS 14+ (Allow Once, approximate location)
  bool get isIos14Plus => iosVersionAtLeast(14);

  /// Check if running on iOS 17+ (privacy manifest required)
  bool get isIos17Plus => iosVersionAtLeast(17);
}

enum PlatformType {
  android,
  ios,
  web,
  other,
}
```

**File**: `lib/core/platform/services/platform_info_service.dart`

```dart
import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../models/platform_info.dart';

part 'platform_info_service.g.dart';

@riverpod
class PlatformInfoService extends _$PlatformInfoService {
  @override
  Future<PlatformInfo> build() async {
    return await _getPlatformInfo();
  }

  Future<PlatformInfo> _getPlatformInfo() async {
    final deviceInfo = DeviceInfoPlugin();

    if (Platform.isAndroid) {
      final androidInfo = await deviceInfo.androidInfo;
      return PlatformInfo(
        type: PlatformType.android,
        version: androidInfo.version.release,
        apiLevel: androidInfo.version.sdkInt,
        isPhysicalDevice: androidInfo.isPhysicalDevice,
      );
    } else if (Platform.isIOS) {
      final iosInfo = await deviceInfo.iosInfo;
      return PlatformInfo(
        type: PlatformType.ios,
        version: iosInfo.systemVersion,
        apiLevel: 0, // Not applicable for iOS
        isPhysicalDevice: iosInfo.isPhysicalDevice,
      );
    } else {
      return const PlatformInfo(
        type: PlatformType.other,
        version: 'unknown',
        apiLevel: 0,
        isPhysicalDevice: false,
      );
    }
  }

  /// Get user-friendly platform description
  String getPlatformDescription() {
    final info = state.valueOrNull;
    if (info == null) return 'Unknown';

    return switch (info.type) {
      PlatformType.android => 'Android ${info.version} (API ${info.apiLevel})',
      PlatformType.ios => 'iOS ${info.version}',
      _ => 'Unknown platform',
    };
  }

  /// Check if emulator/simulator (for testing warnings)
  bool isEmulator() {
    final info = state.valueOrNull;
    return info?.isPhysicalDevice == false;
  }
}
```

**Usage Example**:

```dart
// In PermissionHandlerService or BackgroundLocationService
final platformInfo = await ref.read(platformInfoServiceProvider.future);

if (platformInfo.isAndroid11Plus) {
  // Show settings navigation guidance for background permission
  _showBackgroundPermissionGuidance();
} else if (platformInfo.isAndroid10Plus) {
  // Can request background permission directly
  await _requestBackgroundPermission();
}

if (platformInfo.isAndroid13Plus) {
  // Must request notification permission
  await _requestNotificationPermission();
}
```

**Dependencies**:
- Requires `device_info_plus` package (add to pubspec.yaml)

---

### Step 5: Create Configuration Validator

**File**: `lib/core/utils/platform_config_validator.dart`

```dart
import 'dart:io';
import 'package:flutter/foundation.dart';

/// Validates platform configuration at app startup
/// Helps catch configuration issues during development
class PlatformConfigValidator {
  /// Validate all platform configurations
  static Future<List<ConfigValidationIssue>> validateAll() async {
    final issues = <ConfigValidationIssue>[];

    if (Platform.isAndroid) {
      issues.addAll(await _validateAndroid());
    } else if (Platform.isIOS) {
      issues.addAll(await _validateIOS());
    }

    return issues;
  }

  /// Validate Android configuration
  static Future<List<ConfigValidationIssue>> _validateAndroid() async {
    final issues = <ConfigValidationIssue>[];

    // These checks are informational - actual permission checks
    // happen via permission_handler at runtime

    if (kDebugMode) {
      debugPrint('✅ Android configuration check:');
      debugPrint('  - Location permissions: Declared in AndroidManifest.xml');
      debugPrint('  - Background service: Configured');
      debugPrint('  - Notification channels: Created by NotificationService');
    }

    return issues;
  }

  /// Validate iOS configuration
  static Future<List<ConfigValidationIssue>> _validateIOS() async {
    final issues = <ConfigValidationIssue>[];

    if (kDebugMode) {
      debugPrint('✅ iOS configuration check:');
      debugPrint('  - Location descriptions: Set in Info.plist');
      debugPrint('  - Background modes: Configured');
      debugPrint('  - Privacy manifest: Created for iOS 17+');
    }

    return issues;
  }

  /// Print configuration status to console (development only)
  static Future<void> printConfigStatus() async {
    if (!kDebugMode) return;

    debugPrint('');
    debugPrint('='.padRight(50, '='));
    debugPrint('Platform Configuration Status');
    debugPrint('='.padRight(50, '='));

    final issues = await validateAll();

    if (issues.isEmpty) {
      debugPrint('✅ All configuration checks passed');
    } else {
      debugPrint('⚠️  Configuration issues found:');
      for (final issue in issues) {
        debugPrint('  - ${issue.severity.name}: ${issue.message}');
      }
    }

    debugPrint('='.padRight(50, '='));
    debugPrint('');
  }
}

/// Configuration validation issue
class ConfigValidationIssue {
  final ConfigIssueSeverity severity;
  final String message;
  final String? suggestion;

  const ConfigValidationIssue({
    required this.severity,
    required this.message,
    this.suggestion,
  });
}

enum ConfigIssueSeverity {
  error,
  warning,
  info,
}
```

**Usage in main.dart**:

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Validate configuration in debug mode
  if (kDebugMode) {
    await PlatformConfigValidator.printConfigStatus();
  }

  runApp(const ProviderScope(child: MyApp()));
}
```

---

### Step 6: Add Package Dependencies

**File**: `pubspec.yaml`

**Action**: Ensure `device_info_plus` is added for PlatformInfoService.

```yaml
dependencies:
  # ... existing dependencies
  device_info_plus: ^10.1.0  # Platform info (Android API level, iOS version)
```

**Run**:
```bash
flutter pub get
```

---

### Step 7: Run Code Generation

Generate Riverpod and Freezed code:

```bash
flutter pub run build_runner build --delete-conflicting-outputs
```

---

### Step 8: Update CLAUDE.md

**File**: `CLAUDE.md`

**Action**: Add platform configuration notes to the "Platform-Specific Notes" section.

**Add Section**:

```markdown
## Platform Configuration Reference

### Android

**API Level Handling**:
- Use `PlatformInfoService` to detect API level at runtime
- Android 10+ (API 29): Background location is separate permission
- Android 11+ (API 30): Background location requires settings navigation
- Android 13+ (API 33): Notification permission required

**Configuration Files**:
- `android/app/src/main/AndroidManifest.xml`: All permissions and service config
- See inline comments for detailed explanation of each permission

### iOS

**Version Handling**:
- Use `PlatformInfoService` to detect iOS version at runtime
- iOS 14+: User can choose "Allow Once" (temporary permission)
- iOS 17+: Privacy manifest required (PrivacyInfo.xcprivacy)

**Configuration Files**:
- `ios/Runner/Info.plist`: Permission descriptions and background modes
- `ios/Runner/PrivacyInfo.xcprivacy`: Privacy manifest (iOS 17+)
- See inline comments for App Store compliance notes
```

---

## Verification Steps

### Static Validation

```bash
# 1. Verify Android configuration
# Check that all permissions are declared
grep -E "permission|foregroundServiceType" android/app/src/main/AndroidManifest.xml

# 2. Verify iOS configuration
# Check that location descriptions exist
grep -E "NSLocation|UIBackgroundModes" ios/Runner/Info.plist

# 3. Verify iOS privacy manifest exists
ls -la ios/Runner/PrivacyInfo.xcprivacy

# 4. Run code generation
flutter pub run build_runner build --delete-conflicting-outputs

# 5. Static analysis
flutter analyze

# 6. Verify PlatformInfoService works
flutter test test/core/platform/
```

### Runtime Validation (Android)

**Test on Physical Device** (API 29, 30, 33+):

1. **Install and Launch**:
   ```bash
   flutter run --release
   ```

2. **Check Platform Info**:
   - App should print platform info in debug console
   - Verify API level detection is correct

3. **Permission Flow** (Android 10+):
   - Request foreground location → Should work
   - Request background location → Should show appropriate flow
   - Android 11+: Should guide to settings

4. **Notification Permission** (Android 13+):
   - App should request notification permission
   - Verify channel created by NotificationService

5. **Background Service**:
   - Start trip tracking
   - Verify foreground service notification appears
   - Check notification cannot be dismissed

### Runtime Validation (iOS)

**Test on Physical Device** (iOS 13+):

1. **Install and Launch**:
   ```bash
   flutter run --release
   ```

2. **Check Platform Info**:
   - App should print iOS version
   - Verify version detection is correct

3. **Permission Descriptions**:
   - Request location permission
   - Verify description matches Info.plist
   - Text should be clear and specific

4. **Background Permission**:
   - Request "Always Allow"
   - Verify background modes work
   - Test with app backgrounded

5. **Privacy Manifest** (iOS 17+):
   - No runtime verification needed
   - Validated by App Store during submission

---

## Testing Strategy

### Unit Tests

**File**: `test/core/platform/platform_info_service_test.dart`

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:autoride/core/platform/models/platform_info.dart';

void main() {
  group('PlatformInfo', () {
    test('androidApiAtLeast returns true for equal or higher API', () {
      const info = PlatformInfo(
        type: PlatformType.android,
        version: '11',
        apiLevel: 30,
        isPhysicalDevice: true,
      );

      expect(info.androidApiAtLeast(29), true);
      expect(info.androidApiAtLeast(30), true);
      expect(info.androidApiAtLeast(31), false);
    });

    test('isAndroid11Plus correctly identifies API 30+', () {
      const api30 = PlatformInfo(
        type: PlatformType.android,
        version: '11',
        apiLevel: 30,
        isPhysicalDevice: true,
      );

      const api29 = PlatformInfo(
        type: PlatformType.android,
        version: '10',
        apiLevel: 29,
        isPhysicalDevice: true,
      );

      expect(api30.isAndroid11Plus, true);
      expect(api29.isAndroid11Plus, false);
    });

    test('iosVersionAtLeast correctly compares versions', () {
      const ios14 = PlatformInfo(
        type: PlatformType.ios,
        version: '14.5',
        apiLevel: 0,
        isPhysicalDevice: true,
      );

      expect(ios14.iosVersionAtLeast(14), true);
      expect(ios14.iosVersionAtLeast(14, 5), true);
      expect(ios14.iosVersionAtLeast(15), false);
    });

    test('isIos17Plus correctly identifies iOS 17+', () {
      const ios17 = PlatformInfo(
        type: PlatformType.ios,
        version: '17.0',
        apiLevel: 0,
        isPhysicalDevice: true,
      );

      const ios16 = PlatformInfo(
        type: PlatformType.ios,
        version: '16.6',
        apiLevel: 0,
        isPhysicalDevice: true,
      );

      expect(ios17.isIos17Plus, true);
      expect(ios16.isIos17Plus, false);
    });
  });
}
```

### Manual Testing Checklist

#### Android Testing

**Test Matrix**:
- [ ] Android 8 (API 26) - Minimum supported version
- [ ] Android 10 (API 29) - Background location introduced
- [ ] Android 11 (API 30) - Background location settings navigation
- [ ] Android 13 (API 33) - Notification permission required
- [ ] Android 14 (API 34) - Target SDK version

**Test Scenarios**:

1. **Platform Detection**:
   - [ ] PlatformInfoService correctly detects API level
   - [ ] Debug console shows correct Android version
   - [ ] isAndroid10Plus, isAndroid11Plus, isAndroid13Plus work correctly

2. **Permission Flow (API 29)**:
   - [ ] Can request background location directly (in permission dialog)
   - [ ] "Allow all the time" option visible

3. **Permission Flow (API 30+)**:
   - [ ] Background location request opens settings
   - [ ] User must manually select "Allow all the time"
   - [ ] App detects when permission granted

4. **Notification Permission (API 33+)**:
   - [ ] App requests POST_NOTIFICATIONS permission
   - [ ] Notification permission denial handled gracefully
   - [ ] Foreground service works after permission granted

5. **Configuration Validation**:
   - [ ] PlatformConfigValidator prints config status
   - [ ] No errors in debug console
   - [ ] All required permissions declared

#### iOS Testing

**Test Matrix**:
- [ ] iOS 13 - Minimum supported version
- [ ] iOS 14 - Allow Once introduced
- [ ] iOS 15 - Enhanced privacy indicators
- [ ] iOS 17 - Privacy manifest required

**Test Scenarios**:

1. **Platform Detection**:
   - [ ] PlatformInfoService correctly detects iOS version
   - [ ] Debug console shows correct version string
   - [ ] isIos14Plus, isIos17Plus work correctly

2. **Permission Descriptions**:
   - [ ] "When In Use" permission shows enhanced description
   - [ ] "Always Allow" permission shows clear explanation
   - [ ] Privacy assurance text is visible

3. **Permission Options (iOS 14+)**:
   - [ ] "Allow Once" option available
   - [ ] "While Using App" option available
   - [ ] "Change to Always Allow" flow works
   - [ ] Approximate location option available

4. **Background Modes**:
   - [ ] Background location works when "Always" granted
   - [ ] App continues tracking in background
   - [ ] Background modes configured correctly

5. **Privacy Manifest (iOS 17+)**:
   - [ ] PrivacyInfo.xcprivacy exists in Xcode project
   - [ ] File is included in build
   - [ ] App builds without privacy warnings

---

## Platform-Specific Notes

### Android Permissions Evolution

```yaml
Android 8-9 (API 26-28):
  background_location: Combined with foreground permission
  request_flow: Single permission request
  user_choice: Allow/Deny

Android 10 (API 29):
  background_location: Separate ACCESS_BACKGROUND_LOCATION permission
  request_flow: Two-step (foreground → background)
  user_choice: Allow all the time/Allow only while using/Deny
  notes: Can request both in same dialog

Android 11+ (API 30+):
  background_location: Must request separately
  request_flow: Foreground → Background (opens settings)
  user_choice: User must manually enable in settings
  dialog_change: "Allow all the time" removed from initial dialog
  guidance: Must provide clear instructions to open settings

Android 12+ (API 31+):
  new_option: Approximate location
  user_choice: Precise/Approximate location
  notes: User can downgrade from precise to approximate

Android 13+ (API 33+):
  notification_permission: POST_NOTIFICATIONS required
  request_timing: Must request before showing notifications
  foreground_service: Requires notification permission
  breaking_change: Apps targeting API 33+ MUST request this
```

### iOS Permissions Evolution

```yaml
iOS 13:
  permissions: When In Use, Always
  request_flow: Standard iOS permission dialog
  notes: First version we support

iOS 14:
  new_option: Allow Once (temporary permission)
  approximate_location: User can choose approximate location
  user_experience: More granular control
  impact: Must handle temporary permissions (re-request on next launch)

iOS 15:
  privacy_indicators: Visual indicators when location used
  no_permission_changes: Same permission model as iOS 14
  notes: Increased user awareness of location usage

iOS 16:
  no_major_changes: Same permission model
  notes: Continued privacy emphasis

iOS 17:
  privacy_manifest: Required for apps using tracking APIs
  requirement: Must declare API usage reasons
  enforcement: App Store rejection if missing
  impact: PrivacyInfo.xcprivacy required
```

### Platform Differences Summary

| Feature | Android | iOS |
|---------|---------|-----|
| **Background Permission** | Separate permission (API 29+) | "Always Allow" option |
| **Request Flow** | Two-step (API 30+) | Single dialog with options |
| **Temporary Permission** | Not available | "Allow Once" (iOS 14+) |
| **Approximate Location** | Available (API 31+) | Available (iOS 14+) |
| **Notification Permission** | Required (API 33+) | Not required |
| **Privacy Manifest** | Not required | Required (iOS 17+) |
| **Settings Navigation** | Required (API 30+) | Optional |

---

## Edge Cases & Error Handling

### Edge Case 1: Android 11+ Background Permission

**Scenario**: User tries to enable background location on Android 11+

**Expected Behavior**:
- App detects API 30+
- Shows guidance dialog explaining settings navigation
- Opens settings with deep link
- Guides user to select "Allow all the time"

**Implementation** (in T027 PermissionHandlerService):
```dart
if (platformInfo.isAndroid11Plus) {
  // Show guidance dialog before opening settings
  await _showBackgroundLocationGuidance();
  await openAppSettings();
}
```

### Edge Case 2: iOS "Allow Once" Selection

**Scenario**: iOS 14+ user selects "Allow Once"

**Expected Behavior**:
- Permission granted temporarily
- Location works for current session
- Permission expires when app is terminated
- Must re-request on next app launch

**Implementation**:
- Check permission status on app launch
- Re-request if not permanently granted
- Inform user about temporary nature

### Edge Case 3: Android 13+ Missing Notification Permission

**Scenario**: App tries to show foreground service notification without permission

**Expected Behavior**:
- Android 13+ blocks notification
- Foreground service may be killed
- App detects missing permission
- Requests notification permission

**Implementation**:
```dart
if (platformInfo.isAndroid13Plus) {
  final notificationGranted = await permissionHandler.isGranted(
    AppPermission.notification,
  );

  if (!notificationGranted) {
    await permissionHandler.requestPermission(AppPermission.notification);
  }
}
```

### Edge Case 4: Emulator Detection Warning

**Scenario**: Developer runs app on emulator

**Expected Behavior**:
- PlatformInfoService detects emulator
- Shows warning about limited functionality
- Suggests testing on physical device

**Implementation**:
```dart
if (platformInfo.isEmulator()) {
  debugPrint('⚠️  Running on emulator. Location and sensors may not work correctly.');
  debugPrint('   Please test on a physical device for accurate results.');
}
```

### Edge Case 5: Platform Info Service Failure

**Scenario**: Device info plugin fails to get platform info

**Expected Behavior**:
- Service returns safe default values
- App continues to function
- Logs error for debugging

**Implementation**:
```dart
try {
  return await _getPlatformInfo();
} catch (e) {
  debugPrint('Error getting platform info: $e');
  // Return safe defaults
  return const PlatformInfo(
    type: PlatformType.other,
    version: 'unknown',
    apiLevel: 0,
    isPhysicalDevice: false,
  );
}
```

---

## Common Pitfalls

### Pitfall 1: Missing iOS Privacy Manifest (iOS 17+)

**Problem**: App rejected by App Store for missing privacy manifest

**Symptoms**:
- App builds and runs fine
- App Store submission rejected
- Error: "Missing Privacy Manifest"

**Solution**:
- Ensure `PrivacyInfo.xcprivacy` exists in `ios/Runner/`
- File must be added to Xcode project
- Build and verify file is included in bundle

**Verification**:
```bash
# Check file exists
ls -la ios/Runner/PrivacyInfo.xcprivacy

# Verify in Xcode project
# Open ios/Runner.xcworkspace
# Check PrivacyInfo.xcprivacy is in project navigator
# Ensure "Target Membership" includes Runner
```

### Pitfall 2: Android 11+ Background Permission Not Working

**Problem**: Background location permission request does nothing on Android 11+

**Symptoms**:
- Permission dialog appears but doesn't have "Allow all the time" option
- User grants permission but background location doesn't work
- PermissionHandlerService shows permission denied

**Solution**:
- Android 11+ removed "Allow all the time" from initial dialog
- Must open settings and guide user to manually enable
- Check API level with PlatformInfoService

**Code Fix**:
```dart
if (platformInfo.isAndroid11Plus) {
  // Must open settings
  await openAppSettings();
  // Show guidance overlay/dialog
} else {
  // Can request directly
  await permission.request();
}
```

### Pitfall 3: iOS Permission Descriptions Too Generic

**Problem**: App Store rejects app for vague permission descriptions

**Symptoms**:
- App rejected during review
- Feedback: "Permission description doesn't clearly explain usage"

**Solution**:
- Use specific, detailed descriptions in Info.plist
- Explain WHAT data is collected
- Explain WHY it's needed
- Explain HOW it benefits user
- Include privacy assurance

**Good Example**:
```xml
<string>AutoRide tracks your location to record cycling routes, calculate distance and speed, and map your trips. Your location data stays private on your device and is never shared.</string>
```

**Bad Example**:
```xml
<string>This app needs location to work.</string>
```

### Pitfall 4: Notification Permission Not Requested (Android 13+)

**Problem**: Foreground service notification doesn't appear on Android 13+

**Symptoms**:
- Service starts but notification missing
- Android may kill service
- NotificationService fails silently

**Solution**:
- Always request POST_NOTIFICATIONS on Android 13+
- Request BEFORE starting foreground service
- Check permission status with PlatformInfoService

**Code**:
```dart
if (platformInfo.isAndroid13Plus) {
  await permissionHandler.requestPermission(AppPermission.notification);
}
await backgroundLocationService.startTracking();
```

### Pitfall 5: Foreground Service Type Not Declared

**Problem**: Foreground service crashes on Android 14+

**Symptoms**:
- Service starts on Android 13 but crashes on Android 14
- Error: "ForegroundServiceType not declared"

**Solution**:
- Ensure `android:foregroundServiceType="location"` in AndroidManifest.xml
- Matches `foregroundServiceTypes: [AndroidForegroundType.location]` in service config

**Verification**:
```bash
grep "foregroundServiceType" android/app/src/main/AndroidManifest.xml
# Should show: android:foregroundServiceType="location"
```

---

## Success Criteria

### Functional Requirements

- ✅ All platform configurations validated and documented
- ✅ PlatformInfoService correctly detects API levels and iOS versions
- ✅ Configuration validator runs without errors
- ✅ Enhanced permission descriptions in Info.plist
- ✅ Comprehensive comments in AndroidManifest.xml
- ✅ iOS Privacy Manifest created and included
- ✅ Platform-specific permission flows work on all supported versions

### Code Quality

- ✅ `flutter analyze` passes with no errors
- ✅ All Freezed models generate correctly
- ✅ Unit tests pass for PlatformInfo model
- ✅ Code follows existing patterns (Riverpod, Freezed)
- ✅ Inline documentation is comprehensive

### Testing

- ✅ Manual testing on Android 10, 11, 13 successful
- ✅ Manual testing on iOS 14, 17 successful (if device available)
- ✅ Platform detection works correctly
- ✅ Permission flows work on all API levels
- ✅ Configuration validation passes

### Documentation

- ✅ All configuration files have inline comments
- ✅ Platform differences documented
- ✅ Edge cases documented
- ✅ CLAUDE.md updated with platform notes

---

## App Store Compliance Checklist

### Android (Google Play)

**Pre-Submission**:
- [ ] Target SDK is API 34 (Android 14)
- [ ] All permissions have clear use case
- [ ] Dangerous permissions requested at runtime
- [ ] Privacy policy includes location data usage
- [ ] App works without optional permissions

**Permission Declarations**:
- [ ] Location permissions justified in store listing
- [ ] Background location use explained to users
- [ ] Foreground service type matches usage

**Testing**:
- [ ] Tested on Android 8, 10, 11, 13, 14
- [ ] Permission flows work on all versions
- [ ] Background location works reliably
- [ ] Battery usage is acceptable

### iOS (App Store)

**Pre-Submission**:
- [ ] Minimum deployment target is iOS 13
- [ ] Info.plist descriptions are specific and clear
- [ ] Privacy manifest included (iOS 17+)
- [ ] Background modes justified
- [ ] App works without optional permissions

**Privacy**:
- [ ] Location usage clearly explained
- [ ] Privacy policy linked in App Store listing
- [ ] Data collection disclosed in privacy manifest
- [ ] No tracking (or ATT implemented if tracking)

**Testing**:
- [ ] Tested on iOS 13, 14, 15, 17
- [ ] Permission descriptions appear correctly
- [ ] Background location works when granted
- [ ] "Allow Once" handled properly (iOS 14+)

---

## Resources

### Official Documentation

**Android**:
- [Android Permissions Overview](https://developer.android.com/guide/topics/permissions/overview)
- [Request Runtime Permissions](https://developer.android.com/training/permissions/requesting)
- [Background Location Limits](https://developer.android.com/training/location/permissions)
- [Foreground Services](https://developer.android.com/develop/background-work/services/foreground-services)
- [Android 13 Notification Permission](https://developer.android.com/develop/ui/views/notifications/notification-permission)

**iOS**:
- [Requesting Authorization to Use Location Services](https://developer.apple.com/documentation/corelocation/requesting_authorization_to_use_location_services)
- [Privacy Manifest Files](https://developer.apple.com/documentation/bundleresources/privacy_manifest_files)
- [App Store Review Guidelines - Location](https://developer.apple.com/app-store/review/guidelines/#location-services)
- [Background Execution](https://developer.apple.com/documentation/uikit/app_and_environment/scenes/preparing_your_ui_to_run_in_the_background)

### Flutter Packages

- [permission_handler](https://pub.dev/packages/permission_handler)
- [device_info_plus](https://pub.dev/packages/device_info_plus)
- [geolocator](https://pub.dev/packages/geolocator)
- [flutter_background_service](https://pub.dev/packages/flutter_background_service)

### Platform Guides

- [Android API Levels](https://apilevels.com/)
- [iOS Version History](https://en.wikipedia.org/wiki/IOS_version_history)
- [Flutter Platform Integration](https://docs.flutter.dev/platform-integration)

---

## Next Steps

**After T028**:

1. **Testing Phase**:
   - Comprehensive testing on multiple Android versions
   - Comprehensive testing on multiple iOS versions
   - Battery profiling and optimization

2. **Optional Improvements**:
   - Automated UI tests for permission flows
   - Analytics for permission grant rates
   - A/B testing different permission rationale messages

3. **Future Tasks**:
   - **T029**: Unit Tests (Business Logic)
   - **T030**: Widget Tests (UI Components)
   - **T032**: Battery Profiling & Optimization

---

## Notes

- This task is primarily **documentation and validation**, not major code changes
- Most configurations were set up in T005 (Background Location) and T025 (Notifications)
- Focus is on **production readiness** and **app store compliance**
- PlatformInfoService enables **runtime adaptation** to different platform versions
- Privacy manifest is **critical** for iOS 17+ App Store approval

---

**Created**: 2025-11-23
**Status**: Ready for implementation
**Next Task**: T029 - Unit Tests OR continue with ML integration (T016-T019)
