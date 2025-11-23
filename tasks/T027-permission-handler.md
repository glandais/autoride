# T027: Permission Handler Implementation

**Phase**: Phase 7 - Permissions & Platform
**Dependencies**: T003 (Riverpod Code Generation Setup)
**Estimate**: 2-3 hours
**Status**: ☐ Pending

---

## Overview

Create a comprehensive permission management system using the `permission_handler` package to handle runtime permissions across Android and iOS. This task implements progressive permission requests with clear rationale dialogs, proper state handling, and integration with the settings screen.

**Goal**: Build a robust, user-friendly permission system that requests permissions at appropriate times with clear rationale, handles all permission states gracefully, and provides easy access to permission management in settings.

---

## Objectives

1. ✅ Create custom permission exceptions (already referenced in error_handler.dart)
2. ☐ Implement comprehensive PermissionHandlerService using permission_handler
3. ☐ Add rationale dialog system for progressive permission requests
4. ☐ Support multiple permission types (location, notifications, activity recognition)
5. ☐ Integrate with settings screen for background location permission
6. ☐ Handle all permission states (granted, denied, permanently denied, restricted)
7. ☐ Provide permission status monitoring and checking
8. ☐ Add tests for permission handling logic

---

## Context & Problem

**Current State**:
- ✅ `permission_handler` package already installed (v12.0.1)
- ✅ Basic location permission handling via Geolocator in `location_permission_service.dart`
- ✅ Onboarding flow requests location permissions during first launch
- ❌ Missing: Comprehensive permission handler service
- ❌ Missing: Custom exception definitions (referenced but not defined)
- ❌ Missing: Notification permission handling (Android 13+)
- ❌ Missing: Rationale dialog system
- ❌ Missing: Settings screen integration (TODO comment at line 80)

**Why We Need This**:
1. **Platform Requirements**: Android 10+ requires progressive permission flow
2. **User Trust**: Clear rationale before requesting permissions improves acceptance rates
3. **Notification Support**: Android 13+ requires runtime notification permission
4. **Future ML Features**: Activity recognition permission needed for T016-T019
5. **Better UX**: Proper handling of denied/permanently denied states

---

## Design Decisions

### Permission Types to Support

```dart
enum AppPermission {
  locationWhenInUse,      // Foreground location
  locationAlways,         // Background location
  notification,           // Push notifications (Android 13+)
  activityRecognition,    // For ML features (future)
}
```

**Rationale**:
- **locationWhenInUse**: Required for basic trip tracking
- **locationAlways**: Optional, for automatic trip detection
- **notification**: Required for foreground service notification (Android 13+)
- **activityRecognition**: Future use for ML-based activity detection

### Progressive Permission Strategy

**Flow**:
1. **Onboarding**: Request locationWhenInUse and notification (basic features)
2. **Settings Toggle**: Request locationAlways when user enables background tracking
3. **Future Features**: Request activityRecognition when ML features are enabled

**Why Progressive?**:
- Better user experience (not overwhelming)
- Higher acceptance rates (clear context)
- Platform best practices (Android/iOS guidelines)

### Rationale Dialog System

**Components**:
- Pre-request dialog explaining why permission is needed
- Benefits list for each permission type
- Privacy notes reassuring users
- Skip option for optional permissions

**Example Flow**:
```
User toggles "Background location" in settings
  → Show rationale dialog
  → User taps "Allow"
  → Request permission via permission_handler
  → Handle result (granted/denied/permanentlyDenied)
  → Update UI state
```

---

## Technical Specification

### File Structure

```
lib/core/
├── permissions/
│   ├── models/
│   │   ├── permission_status.dart      # Custom permission status enum
│   │   └── permission_rationale.dart   # Rationale data model
│   ├── services/
│   │   └── permission_handler_service.dart  # Main permission service
│   ├── widgets/
│   │   └── permission_rationale_dialog.dart # Rationale dialog
│   └── exceptions/
│       └── permission_exceptions.dart   # Custom exceptions
```

---

## Implementation Steps

### Step 1: Define Custom Exceptions

**File**: `lib/core/permissions/exceptions/permission_exceptions.dart`

```dart
/// Base exception for permission-related errors
abstract class PermissionException implements Exception {
  final String message;
  final AppPermission permission;

  const PermissionException(this.message, this.permission);

  @override
  String toString() => message;
}

/// Permission was denied by the user
class PermissionDeniedException extends PermissionException {
  const PermissionDeniedException(AppPermission permission)
      : super('Permission denied', permission);
}

/// Permission was permanently denied (requires settings)
class PermissionPermanentlyDeniedException extends PermissionException {
  const PermissionPermanentlyDeniedException(AppPermission permission)
      : super('Permission permanently denied. Please enable in settings.', permission);
}

/// Permission request already in progress
class PermissionRequestInProgressException extends PermissionException {
  const PermissionRequestInProgressException(AppPermission permission)
      : super('Permission request is already in progress', permission);
}

/// Location service is disabled
class LocationServiceDisabledException implements Exception {
  final String message;
  const LocationServiceDisabledException([this.message = 'Location service is disabled']);

  @override
  String toString() => message;
}
```

**Why These Exceptions?**:
- Already referenced in `error_handler.dart` (lines 24-26, 60-65)
- Clear distinction between temporary denial and permanent denial
- Prevents duplicate permission requests
- Allows proper error handling in UI layer

---

### Step 2: Create Permission Status Model

**File**: `lib/core/permissions/models/permission_status.dart`

```dart
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:permission_handler/permission_handler.dart' as ph;

part 'permission_status.freezed.dart';

enum AppPermission {
  locationWhenInUse,
  locationAlways,
  notification,
  activityRecognition,
}

@freezed
sealed class AppPermissionStatus with _$AppPermissionStatus {
  const AppPermissionStatus._();

  const factory AppPermissionStatus({
    required AppPermission permission,
    required bool isGranted,
    required bool isDenied,
    required bool isPermanentlyDenied,
    required bool isRestricted,
    required bool isLimited,
  }) = _AppPermissionStatus;

  factory AppPermissionStatus.fromPermissionHandlerStatus(
    AppPermission permission,
    ph.PermissionStatus status,
  ) {
    return AppPermissionStatus(
      permission: permission,
      isGranted: status.isGranted,
      isDenied: status.isDenied,
      isPermanentlyDenied: status.isPermanentlyDenied,
      isRestricted: status.isRestricted,
      isLimited: status.isLimited,
    );
  }

  bool get canRequest => !isPermanentlyDenied && !isRestricted;
  bool get needsSettings => isPermanentlyDenied;
}
```

**Why Freezed Model?**:
- Immutable state representation
- Type safety for permission status
- Convenient status checking methods
- Consistent with existing codebase patterns

---

### Step 3: Create Rationale Data Model

**File**: `lib/core/permissions/models/permission_rationale.dart`

```dart
import 'package:flutter/material.dart';
import 'permission_status.dart';

class PermissionRationale {
  final AppPermission permission;
  final String title;
  final String description;
  final IconData icon;
  final List<String> benefits;
  final String? privacyNote;
  final bool isOptional;

  const PermissionRationale({
    required this.permission,
    required this.title,
    required this.description,
    required this.icon,
    required this.benefits,
    this.privacyNote,
    this.isOptional = false,
  });

  static const locationWhenInUse = PermissionRationale(
    permission: AppPermission.locationWhenInUse,
    title: 'Location Permission',
    description: 'AutoRide needs location access to track your cycling routes.',
    icon: Icons.location_on,
    benefits: [
      'Record your cycling routes on a map',
      'Calculate distance, speed, and duration',
      'Mark trip start and end locations',
    ],
    privacyNote: 'Your location data stays on your device. We never share or upload it.',
  );

  static const locationAlways = PermissionRationale(
    permission: AppPermission.locationAlways,
    title: 'Background Location',
    description: 'Enable automatic trip detection even when the app is closed.',
    icon: Icons.auto_awesome,
    benefits: [
      'Completely automatic - no need to start/stop manually',
      'Battery optimized - only uses GPS when cycling',
      'Never miss a trip - records every ride',
    ],
    privacyNote: 'Background location is only used for trip detection.',
    isOptional: true,
  );

  static const notification = PermissionRationale(
    permission: AppPermission.notification,
    title: 'Notification Permission',
    description: 'Stay informed about your active trips.',
    icon: Icons.notifications_active,
    benefits: [
      'See trip progress in notification',
      'Control tracking from notification',
      'Battery status updates',
    ],
  );

  static const activityRecognition = PermissionRationale(
    permission: AppPermission.activityRecognition,
    title: 'Activity Recognition',
    description: 'Improve trip detection accuracy with activity recognition.',
    icon: Icons.directions_bike,
    benefits: [
      'Better cycling detection accuracy',
      'Distinguish cycling from other activities',
      'Reduce false trip detections',
    ],
    isOptional: true,
  );

  static PermissionRationale forPermission(AppPermission permission) {
    return switch (permission) {
      AppPermission.locationWhenInUse => locationWhenInUse,
      AppPermission.locationAlways => locationAlways,
      AppPermission.notification => notification,
      AppPermission.activityRecognition => activityRecognition,
    };
  }
}
```

---

### Step 4: Implement Permission Handler Service

**File**: `lib/core/permissions/services/permission_handler_service.dart`

```dart
import 'package:permission_handler/permission_handler.dart' as ph;
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:geolocator/geolocator.dart';
import '../models/permission_status.dart';
import '../exceptions/permission_exceptions.dart';

part 'permission_handler_service.g.dart';

@riverpod
class PermissionHandlerService extends _$PermissionHandlerService {
  final Set<AppPermission> _requestsInProgress = {};

  @override
  Future<void> build() async {
    // Initialize by checking all permissions
    await _checkAllPermissions();
  }

  /// Map AppPermission to permission_handler Permission
  ph.Permission _toPermissionHandler(AppPermission permission) {
    return switch (permission) {
      AppPermission.locationWhenInUse => ph.Permission.locationWhenInUse,
      AppPermission.locationAlways => ph.Permission.locationAlways,
      AppPermission.notification => ph.Permission.notification,
      AppPermission.activityRecognition => ph.Permission.activityRecognition,
    };
  }

  /// Check all permissions status
  Future<void> _checkAllPermissions() async {
    // Can be used to initialize state if needed
  }

  /// Check if location service is enabled
  Future<bool> isLocationServiceEnabled() async {
    return await Geolocator.isLocationServiceEnabled();
  }

  /// Check permission status
  Future<AppPermissionStatus> checkPermission(AppPermission permission) async {
    final phPermission = _toPermissionHandler(permission);
    final status = await phPermission.status;

    return AppPermissionStatus.fromPermissionHandlerStatus(
      permission,
      status,
    );
  }

  /// Request permission with error handling
  Future<AppPermissionStatus> requestPermission(
    AppPermission permission, {
    bool showRationale = true,
  }) async {
    // Prevent duplicate requests
    if (_requestsInProgress.contains(permission)) {
      throw PermissionRequestInProgressException(permission);
    }

    _requestsInProgress.add(permission);

    try {
      // Special handling for location permissions
      if (permission == AppPermission.locationWhenInUse ||
          permission == AppPermission.locationAlways) {
        // Check if location service is enabled first
        final serviceEnabled = await isLocationServiceEnabled();
        if (!serviceEnabled) {
          throw const LocationServiceDisabledException();
        }
      }

      // Special handling for background location (Android 10+)
      if (permission == AppPermission.locationAlways) {
        // Must have foreground permission first
        final foregroundStatus = await checkPermission(
          AppPermission.locationWhenInUse,
        );
        if (!foregroundStatus.isGranted) {
          throw const PermissionDeniedException(
            AppPermission.locationWhenInUse,
          );
        }
      }

      // Request the permission
      final phPermission = _toPermissionHandler(permission);
      final status = await phPermission.request();

      final result = AppPermissionStatus.fromPermissionHandlerStatus(
        permission,
        status,
      );

      // Throw exceptions for denied states
      if (result.isPermanentlyDenied) {
        throw PermissionPermanentlyDeniedException(permission);
      }

      if (result.isDenied && !showRationale) {
        throw PermissionDeniedException(permission);
      }

      return result;
    } finally {
      _requestsInProgress.remove(permission);
    }
  }

  /// Request multiple permissions at once
  Future<Map<AppPermission, AppPermissionStatus>> requestPermissions(
    List<AppPermission> permissions,
  ) async {
    final results = <AppPermission, AppPermissionStatus>{};

    for (final permission in permissions) {
      try {
        final status = await requestPermission(permission);
        results[permission] = status;
      } catch (e) {
        // Continue requesting other permissions even if one fails
        final status = await checkPermission(permission);
        results[permission] = status;
      }
    }

    return results;
  }

  /// Open app settings
  Future<bool> openAppSettings() async {
    return await ph.openAppSettings();
  }

  /// Check if permission is granted
  Future<bool> isGranted(AppPermission permission) async {
    final status = await checkPermission(permission);
    return status.isGranted;
  }

  /// Check if permission should show rationale
  /// (true if denied but not permanently)
  Future<bool> shouldShowRationale(AppPermission permission) async {
    final phPermission = _toPermissionHandler(permission);
    final status = await phPermission.status;
    return status.isDenied && !status.isPermanentlyDenied;
  }
}
```

**Key Features**:
- ✅ Prevents duplicate permission requests
- ✅ Checks location service enabled before requesting
- ✅ Enforces progressive flow (foreground → background)
- ✅ Throws appropriate exceptions for error handling
- ✅ Supports multiple permission requests
- ✅ Provides utility methods for permission checking

---

### Step 5: Create Rationale Dialog Widget

**File**: `lib/core/permissions/widgets/permission_rationale_dialog.dart`

```dart
import 'package:flutter/material.dart';
import '../../../core/theme/app_spacing.dart';
import '../models/permission_rationale.dart';

class PermissionRationaleDialog extends StatelessWidget {
  const PermissionRationaleDialog({
    super.key,
    required this.rationale,
    required this.onAllow,
    this.onDeny,
  });

  final PermissionRationale rationale;
  final VoidCallback onAllow;
  final VoidCallback? onDeny;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      icon: Icon(
        rationale.icon,
        size: 48,
        color: theme.colorScheme.primary,
      ),
      title: Text(rationale.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Description
            Text(
              rationale.description,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.lg),

            // Benefits
            Text(
              rationale.isOptional ? 'Benefits:' : 'Required for:',
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: AppSpacing.sm),
            ...rationale.benefits.map(
              (benefit) => Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.check_circle,
                      size: 16,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: Text(
                        benefit,
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Privacy note
            if (rationale.privacyNote != null) ...[
              const SizedBox(height: AppSpacing.md),
              Container(
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.privacy_tip,
                      size: 16,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: Text(
                        rationale.privacyNote!,
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        // Deny/Skip button
        if (rationale.isOptional)
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              onDeny?.call();
            },
            child: const Text('Skip'),
          ),
        if (!rationale.isOptional)
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              onDeny?.call();
            },
            child: const Text('Not Now'),
          ),

        // Allow button
        FilledButton(
          onPressed: () {
            Navigator.of(context).pop();
            onAllow();
          },
          child: const Text('Allow'),
        ),
      ],
    );
  }

  /// Show the dialog
  static Future<bool?> show(
    BuildContext context,
    PermissionRationale rationale,
  ) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => PermissionRationaleDialog(
        rationale: rationale,
        onAllow: () => Navigator.of(context).pop(true),
        onDeny: () => Navigator.of(context).pop(false),
      ),
    );
  }
}
```

---

### Step 6: Integrate with Settings Screen

**File**: `lib/features/settings/presentation/widgets/location_settings_section.dart`

**Changes**:

Replace the TODO section (lines 78-89) with:

```dart
onChanged: (value) async {
  if (value) {
    // Show rationale dialog
    final shouldRequest = await PermissionRationaleDialog.show(
      context,
      PermissionRationale.locationAlways,
    );

    if (shouldRequest == true) {
      // Request background location permission
      final service = ref.read(permissionHandlerServiceProvider.notifier);

      try {
        final status = await service.requestPermission(
          AppPermission.locationAlways,
        );

        if (status.isGranted) {
          // Update setting
          ref.read(settingsServiceProvider.notifier).updatePartial(
                (s) => s.copyWith(backgroundLocationEnabled: true),
              );
        } else if (status.isPermanentlyDenied) {
          // Show settings dialog
          if (context.mounted) {
            _showOpenSettingsDialog(context, ref);
          }
        }
      } on PermissionDeniedException {
        // User denied, don't update setting
      } on LocationServiceDisabledException {
        // Show enable location service dialog
        if (context.mounted) {
          _showEnableLocationDialog(context);
        }
      }
    }
  } else {
    // Just disable the setting
    ref.read(settingsServiceProvider.notifier).updatePartial(
          (s) => s.copyWith(backgroundLocationEnabled: false),
        );
  }
},
```

Add helper methods:

```dart
void _showOpenSettingsDialog(BuildContext context, WidgetRef ref) {
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Permission Required'),
      content: const Text(
        'Background location permission is permanently denied. '
        'Please enable it in app settings.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () async {
            Navigator.of(context).pop();
            await ref
                .read(permissionHandlerServiceProvider.notifier)
                .openAppSettings();
          },
          child: const Text('Open Settings'),
        ),
      ],
    ),
  );
}

void _showEnableLocationDialog(BuildContext context) {
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Location Service Disabled'),
      content: const Text(
        'Please enable location services in your device settings to use background tracking.',
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}
```

**Add import**:
```dart
import '../../../core/permissions/widgets/permission_rationale_dialog.dart';
import '../../../core/permissions/models/permission_rationale.dart';
import '../../../core/permissions/models/permission_status.dart';
import '../../../core/permissions/services/permission_handler_service.dart';
import '../../../core/permissions/exceptions/permission_exceptions.dart';
```

---

### Step 7: Update Error Handler

**File**: `lib/core/utils/error_handler.dart`

**Add import**:
```dart
import '../permissions/exceptions/permission_exceptions.dart';
```

**Update imports** (lines 1-4) to include the new exceptions file.

**Note**: The error handler already references these exceptions correctly, so no code changes needed beyond the import.

---

### Step 8: Add Tests

**File**: `test/core/permissions/services/permission_handler_service_test.dart`

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:autoride/core/permissions/services/permission_handler_service.dart';
import 'package:autoride/core/permissions/models/permission_status.dart';
import 'package:autoride/core/permissions/exceptions/permission_exceptions.dart';

void main() {
  group('PermissionHandlerService', () {
    test('should map AppPermission to permission_handler Permission', () {
      // Test the mapping logic (if exposed for testing)
    });

    test('should prevent duplicate permission requests', () async {
      // Test that requesting same permission twice throws exception
    });

    test('should throw LocationServiceDisabledException when service disabled', () async {
      // Mock Geolocator.isLocationServiceEnabled to return false
      // Verify exception is thrown
    });

    test('should require foreground permission before background', () async {
      // Request background without foreground
      // Verify PermissionDeniedException is thrown
    });

    test('should handle permanently denied status', () async {
      // Mock permanently denied status
      // Verify PermissionPermanentlyDeniedException is thrown
    });
  });
}
```

**Note**: Full test implementation can be done after service is working on device.

---

## Verification Steps

### Manual Testing

1. **Settings Screen Integration**:
   ```bash
   flutter run
   # Navigate to Settings → Location Settings
   # Toggle "Background location" ON
   # Verify rationale dialog appears
   # Tap "Allow" → verify system permission dialog
   # Grant permission → verify setting updates to ON
   # Toggle OFF → verify no dialog, setting updates
   ```

2. **Permission Denial Flow**:
   ```bash
   # Toggle background location ON
   # Deny permission in system dialog
   # Verify setting stays OFF
   # Try again, deny permanently
   # Verify "Open Settings" dialog appears
   ```

3. **Location Service Disabled**:
   ```bash
   # Disable location service in device settings
   # Try to enable background location
   # Verify "Enable Location Service" dialog appears
   ```

### Automated Testing

```bash
# Run tests
flutter test test/core/permissions/

# Should pass:
# - Permission mapping tests
# - Duplicate request prevention
# - Service disabled handling
# - Progressive permission enforcement
```

### Quality Gates

```bash
# 1. Code generation
flutter pub run build_runner build --delete-conflicting-outputs

# 2. Static analysis (MUST pass)
flutter analyze

# 3. Tests (should pass)
flutter test

# 4. Physical device testing
flutter run --release
# Test all permission flows on physical device
```

---

## Edge Cases & Error Handling

### Edge Case 1: Permission Request Already in Progress

**Scenario**: User taps toggle rapidly while permission dialog is showing

**Handling**: Throw `PermissionRequestInProgressException`, caught by UI to prevent duplicate dialogs

### Edge Case 2: Location Service Disabled

**Scenario**: User tries to enable background location with GPS disabled

**Handling**: Throw `LocationServiceDisabledException`, show dialog to enable service

### Edge Case 3: Permission Permanently Denied

**Scenario**: User previously denied permission with "Don't ask again"

**Handling**: Detect permanently denied state, show "Open Settings" dialog

### Edge Case 4: iOS "Allow Once" Selection

**Scenario**: iOS user selects "Allow Once" instead of "While Using"

**Handling**: Treat as temporary grant, request again on next app launch

### Edge Case 5: Android 10+ Background Permission

**Scenario**: Android 10+ requires two-step flow for background location

**Handling**:
1. First verify foreground permission granted
2. Then request background permission (shows system settings on Android 11+)

---

## Testing Strategy

### Unit Tests

```dart
// Test permission mapping
test('maps AppPermission to permission_handler Permission')

// Test state management
test('prevents duplicate permission requests')
test('clears request lock after completion')

// Test validation
test('requires foreground before background permission')
test('checks location service enabled')

// Test exception handling
test('throws PermissionDeniedException when denied')
test('throws PermissionPermanentlyDeniedException when permanently denied')
test('throws LocationServiceDisabledException when service disabled')
```

### Integration Tests

```dart
// Test full permission flow
testWidgets('shows rationale → requests → updates UI')

// Test error handling
testWidgets('shows settings dialog on permanently denied')
testWidgets('shows enable service dialog when GPS disabled')

// Test settings integration
testWidgets('background location toggle works end-to-end')
```

### Manual Device Testing

**Test Matrix**:
- [ ] Android 10 (two-step background permission)
- [ ] Android 11+ (settings redirect for background)
- [ ] Android 13+ (notification permission)
- [ ] iOS 14+ (Allow Once vs While Using vs Always)

**Test Scenarios**:
- [ ] First-time permission request → Grant
- [ ] First-time permission request → Deny
- [ ] Second request after denial → Grant
- [ ] Permanent denial → Open settings flow
- [ ] Location service disabled → Enable prompt
- [ ] Background permission without foreground → Error

---

## Dependencies

**External Packages**:
- ✅ `permission_handler: ^12.0.1` (already installed)
- ✅ `geolocator: ^14.0.2` (already installed, for service check)
- ✅ `riverpod_annotation: ^3.0.3` (already installed)
- ✅ `freezed_annotation: ^3.0.0` (already installed)

**Internal Dependencies**:
- ✅ T003: Riverpod Code Generation Setup (complete)
- ✅ T020: App Theme & Design System (for dialog styling)
- ✅ T024: Settings Screen (for integration)

**Files to Modify**:
- ✅ `lib/features/settings/presentation/widgets/location_settings_section.dart` (line 78-89)
- ✅ `lib/core/utils/error_handler.dart` (add import)

**Files to Create**:
- `lib/core/permissions/exceptions/permission_exceptions.dart`
- `lib/core/permissions/models/permission_status.dart`
- `lib/core/permissions/models/permission_rationale.dart`
- `lib/core/permissions/services/permission_handler_service.dart`
- `lib/core/permissions/widgets/permission_rationale_dialog.dart`
- `test/core/permissions/services/permission_handler_service_test.dart`

---

## Platform-Specific Notes

### Android 10+ (API 29+)

**Two-Step Background Permission**:
1. Request `ACCESS_FINE_LOCATION` first (foreground)
2. Then request `ACCESS_BACKGROUND_LOCATION` (shows settings on Android 11+)

**Manifest Requirements** (already configured):
```xml
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_BACKGROUND_LOCATION" />
```

### Android 13+ (API 33+)

**Notification Permission Required**:
- Runtime permission required for POST_NOTIFICATIONS
- Already declared in AndroidManifest.xml (line 17)
- Should be requested during onboarding

### iOS 14+

**Permission Options**:
- "Allow Once" - temporary, ask again next launch
- "Allow While Using" - foreground only
- "Allow Always" - background allowed

**Info.plist Requirements** (need to verify):
```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>AutoRide needs location to track your cycling routes</string>

<key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
<string>AutoRide needs background location to automatically detect trips</string>
```

---

## Success Criteria

### Functional Requirements

- ✅ Background location toggle in settings works with rationale dialog
- ✅ All permission states handled gracefully (granted, denied, permanently denied)
- ✅ Location service disabled detection works
- ✅ "Open Settings" flow works for permanently denied permissions
- ✅ Progressive permission flow enforced (foreground → background)
- ✅ No duplicate permission requests possible

### Code Quality

- ✅ `flutter analyze` passes with no errors
- ✅ All freezed models generate correctly
- ✅ Exception handling is comprehensive
- ✅ Code follows existing patterns (Riverpod, Freezed)

### Testing

- ✅ Unit tests pass for permission service logic
- ✅ Manual testing on Android 10+, 13+ successful
- ✅ Manual testing on iOS 14+ successful (if iOS device available)
- ✅ All permission flows tested on physical device

### Documentation

- ✅ Code is well-commented
- ✅ Edge cases are documented
- ✅ Platform differences are noted

---

## Lessons Learned

(To be filled after implementation)

### What Worked Well

-

### Challenges Encountered

-

### Best Practices Identified

-

---

## Next Steps

**After T027**:
- **T028**: Platform-Specific Configuration
  - Verify iOS Info.plist descriptions
  - Review Android manifest configuration
  - Test platform-specific permission behaviors

**Integration with Existing Features**:
- Update onboarding flow to use new permission service (optional improvement)
- Add notification permission request for Android 13+
- Prepare for activity recognition permission (T016-T019)

---

## References

- [permission_handler package](https://pub.dev/packages/permission_handler)
- [Android 10+ Background Location](https://developer.android.com/training/location/permissions)
- [Android 13+ Notification Permission](https://developer.android.com/develop/ui/views/notifications/notification-permission)
- [iOS Location Permission](https://developer.apple.com/documentation/corelocation/requesting_authorization_to_use_location_services)
- [Flutter Permission Best Practices](https://docs.flutter.dev/development/data-and-backend/state-mgmt/options#riverpod)

---

**Created**: 2025-11-23
**Status**: Ready for implementation
**Next Task**: T028 - Platform-Specific Configuration
