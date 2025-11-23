# T025 - Notifications & Foreground Service UI

**Status**: ⏳ In Progress
**Estimated Time**: 2.5 hours
**Dependencies**: T005 (Background Location), T022 (Tracking Screen)
**Phase**: 6 - User Interface (UI Polish)

---

## Overview

Implement comprehensive notification system for trip tracking with:
- Rich foreground notification with real-time trip metrics
- Trip start/stop event notifications
- Notification actions (pause/resume, stop)
- Full integration with user settings
- Android 13+ notification permission handling

---

## Current Implementation Status

### ✅ What Exists

1. **Basic Foreground Notification** (from T005)
   - Location: `lib/features/trip_detection/services/background_location_service.dart:48-51`
   - Simple text: "Speed: X.X km/h"
   - Notification channel ID: `autoride_tracking`
   - Notification ID: 888

2. **User Settings** (from T011/T024)
   - Location: `lib/features/settings/domain/models/user_settings.dart`
   - Settings available:
     - `tripNotificationsEnabled` (default: true)
     - `showOngoingNotification` (default: true)
     - `soundOnTripStartStop` (default: false)
   - UI: `lib/features/settings/presentation/widgets/notification_settings_section.dart`

3. **Trip State Management** (from T012-T015)
   - States: Idle, Detecting, Active, Paused
   - State machine: `lib/features/trip_detection/data/services/trip_state_machine.dart`
   - Metrics: Available via `TripRecorderService`

### ❌ What's Missing

1. No `flutter_local_notifications` package installed
2. No dedicated notification service layer
3. No rich notification features (actions, custom layouts)
4. No trip event notifications (start/stop alerts)
5. No integration with user settings
6. No Android 13+ notification permissions

---

## Implementation Steps

### Phase 1: Setup & Dependencies

#### 1.1 Add Package Dependency

**File**: `pubspec.yaml`

Add to dependencies section:
```yaml
dependencies:
  flutter_local_notifications: ^17.0.0
```

Run:
```bash
flutter pub get
```

#### 1.2 Android Permission Configuration

**File**: `android/app/src/main/AndroidManifest.xml`

Add permission for Android 13+ (API 33+):
```xml
<manifest>
    <!-- Existing permissions -->
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>

    <!-- Rest of manifest -->
</manifest>
```

**Note**: Already has foreground service permissions from T005.

#### 1.3 Update Constants

**File**: `lib/core/constants/app_constants.dart`

Add notification-related constants:
```dart
// Notification IDs
static const int foregroundNotificationId = 888;
static const int tripStartNotificationId = 100;
static const int tripStopNotificationId = 101;

// Notification Channels (Android)
static const String tripTrackingChannelId = 'autoride_tracking';
static const String tripTrackingChannelName = 'Trip Tracking';
static const String tripEventsChannelId = 'autoride_trip_events';
static const String tripEventsChannelName = 'Trip Events';

// Notification Update Intervals
static const Duration notificationUpdateInterval = Duration(seconds: 5);
```

---

### Phase 2: Create Notification Service

#### 2.1 Core Service Implementation

**File**: `lib/features/trip_detection/data/services/notification_service.dart`

Create notification service with Riverpod:

```dart
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:autoride/core/constants/app_constants.dart';
import 'package:autoride/features/settings/data/services/settings_service.dart';
import 'package:autoride/features/trip_detection/domain/models/trip.dart';

part 'notification_service.g.dart';

@riverpod
class NotificationService extends _$NotificationService {
  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  @override
  Future<void> build() async {
    await _initializeNotifications();
  }

  Future<void> _initializeNotifications() async {
    // Android initialization
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');

    // iOS initialization
    final iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
      onDidReceiveLocalNotification: (id, title, body, payload) async {
        // Handle iOS foreground notification
      },
    );

    final settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _notifications.initialize(
      settings,
      onDidReceiveNotificationResponse: _onNotificationTap,
    );

    await _createNotificationChannels();
  }

  Future<void> _createNotificationChannels() async {
    // Trip tracking channel (foreground service)
    const trackingChannel = AndroidNotificationChannel(
      AppConstants.tripTrackingChannelId,
      AppConstants.tripTrackingChannelName,
      description: 'Ongoing trip tracking notifications',
      importance: Importance.low, // Low importance = no sound/vibration
      playSound: false,
      enableVibration: false,
      showBadge: false,
    );

    // Trip events channel (start/stop alerts)
    const eventsChannel = AndroidNotificationChannel(
      AppConstants.tripEventsChannelId,
      AppConstants.tripEventsChannelName,
      description: 'Trip start and stop notifications',
      importance: Importance.high, // High importance = sound/heads-up
      playSound: true,
      enableVibration: true,
    );

    await _notifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(trackingChannel);

    await _notifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(eventsChannel);
  }

  void _onNotificationTap(NotificationResponse response) {
    // Handle notification actions
    final action = response.actionId;

    if (action == 'pause') {
      // Trigger pause action
      // TODO: Connect to TripStateMachine
    } else if (action == 'resume') {
      // Trigger resume action
      // TODO: Connect to TripStateMachine
    } else if (action == 'stop') {
      // Trigger stop action
      // TODO: Connect to TripStateMachine
    } else if (response.notificationResponseType ==
               NotificationResponseType.selectedNotification) {
      // User tapped notification body - open app
      // TODO: Navigate to tracking screen
    }
  }

  // Show foreground notification (active trip)
  Future<void> showForegroundNotification({
    required double distance,
    required Duration duration,
    required double currentSpeed,
  }) async {
    final settings = await ref.read(settingsServiceProvider.future);

    if (!settings.showOngoingNotification) {
      return; // User disabled ongoing notifications
    }

    final distanceKm = (distance / 1000).toStringAsFixed(1);
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    final durationStr = hours > 0
        ? '${hours}h ${minutes}m'
        : '${minutes}:${seconds.toString().padLeft(2, '0')}';
    final speedKmh = currentSpeed.toStringAsFixed(1);

    final androidDetails = AndroidNotificationDetails(
      AppConstants.tripTrackingChannelId,
      AppConstants.tripTrackingChannelName,
      channelDescription: 'Ongoing trip tracking notifications',
      importance: Importance.low,
      priority: Priority.low,
      ongoing: true,
      autoCancel: false,
      showWhen: false,
      playSound: false,
      enableVibration: false,
      styleInformation: BigTextStyleInformation(
        'Distance: $distanceKm km • Duration: $durationStr • Speed: $speedKmh km/h',
      ),
      actions: <AndroidNotificationAction>[
        const AndroidNotificationAction(
          'pause',
          'Pause',
          showsUserInterface: false,
        ),
        const AndroidNotificationAction(
          'stop',
          'Stop',
          showsUserInterface: false,
          cancelNotification: false,
        ),
      ],
    );

    final iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: false,
      subtitle: 'Distance: $distanceKm km • Duration: $durationStr',
    );

    await _notifications.show(
      AppConstants.foregroundNotificationId,
      'AutoRide - Trip in Progress',
      'Distance: $distanceKm km • Duration: $durationStr • Speed: $speedKmh km/h',
      NotificationDetails(android: androidDetails, iOS: iosDetails),
    );
  }

  // Show trip start notification
  Future<void> showTripStartNotification() async {
    final settings = await ref.read(settingsServiceProvider.future);

    if (!settings.tripNotificationsEnabled) {
      return; // User disabled trip notifications
    }

    final androidDetails = AndroidNotificationDetails(
      AppConstants.tripEventsChannelId,
      AppConstants.tripEventsChannelName,
      channelDescription: 'Trip start and stop notifications',
      importance: Importance.high,
      priority: Priority.high,
      playSound: settings.soundOnTripStartStop,
      enableVibration: true,
      styleInformation: const BigTextStyleInformation(
        'Your cycling trip is now being tracked',
      ),
    );

    final iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: settings.soundOnTripStartStop,
    );

    await _notifications.show(
      AppConstants.tripStartNotificationId,
      'Trip Started',
      'Your cycling trip is now being tracked',
      NotificationDetails(android: androidDetails, iOS: iosDetails),
    );

    // Auto-dismiss after 5 seconds
    Future.delayed(const Duration(seconds: 5), () {
      _notifications.cancel(AppConstants.tripStartNotificationId);
    });
  }

  // Show trip stop notification
  Future<void> showTripStopNotification({
    required double distance,
    required Duration duration,
    required double avgSpeed,
  }) async {
    final settings = await ref.read(settingsServiceProvider.future);

    if (!settings.tripNotificationsEnabled) {
      return; // User disabled trip notifications
    }

    final distanceKm = (distance / 1000).toStringAsFixed(1);
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final durationStr = hours > 0
        ? '${hours}h ${minutes}m'
        : '${minutes}m';
    final avgSpeedKmh = avgSpeed.toStringAsFixed(1);

    final androidDetails = AndroidNotificationDetails(
      AppConstants.tripEventsChannelId,
      AppConstants.tripEventsChannelName,
      channelDescription: 'Trip start and stop notifications',
      importance: Importance.high,
      priority: Priority.high,
      playSound: settings.soundOnTripStartStop,
      enableVibration: true,
      styleInformation: BigTextStyleInformation(
        'Distance: $distanceKm km • Duration: $durationStr • Avg Speed: $avgSpeedKmh km/h',
      ),
      actions: <AndroidNotificationAction>[
        const AndroidNotificationAction(
          'view_details',
          'View Details',
          showsUserInterface: true,
        ),
      ],
    );

    final iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: settings.soundOnTripStartStop,
      subtitle: 'Distance: $distanceKm km • Duration: $durationStr',
    );

    await _notifications.show(
      AppConstants.tripStopNotificationId,
      'Trip Completed',
      'Distance: $distanceKm km • Duration: $durationStr • Avg Speed: $avgSpeedKmh km/h',
      NotificationDetails(android: androidDetails, iOS: iosDetails),
    );
  }

  // Cancel foreground notification
  Future<void> cancelForegroundNotification() async {
    await _notifications.cancel(AppConstants.foregroundNotificationId);
  }

  // Request notification permissions (Android 13+, iOS)
  Future<bool> requestPermissions() async {
    // Android
    final androidImpl = _notifications.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();

    if (androidImpl != null) {
      final granted = await androidImpl.requestNotificationsPermission();
      if (granted != true) {
        return false;
      }
    }

    // iOS
    final iosImpl = _notifications.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();

    if (iosImpl != null) {
      final granted = await iosImpl.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
      if (granted != true) {
        return false;
      }
    }

    return true;
  }
}
```

**Key Features**:
- ✅ Two notification channels (tracking + events)
- ✅ Rich notification with stats
- ✅ Notification actions (pause, resume, stop)
- ✅ Integration with user settings
- ✅ Android 13+ permission handling
- ✅ Auto-dismiss for trip start notification

---

### Phase 3: Integrate with Trip State Machine

**File**: `lib/features/trip_detection/data/services/trip_state_machine.dart`

Add notification triggers to state transitions:

```dart
// Add near the top of the file
import 'package:autoride/features/trip_detection/data/services/notification_service.dart';

// In the _onStateChange method, add notification triggers:

void _onStateChange(TripState newState) {
  final oldState = state;
  state = newState;

  // Trigger notifications based on state transitions
  if (oldState is TripStateDetecting && newState is TripStateActive) {
    // Trip started
    ref.read(notificationServiceProvider.notifier).showTripStartNotification();
  } else if ((oldState is TripStateActive || oldState is TripStatePaused) &&
             newState is TripStateIdle) {
    // Trip stopped
    final trip = _getCurrentTrip(); // Get current trip data
    if (trip != null) {
      ref.read(notificationServiceProvider.notifier).showTripStopNotification(
        distance: trip.distanceMeters,
        duration: trip.duration,
        avgSpeed: trip.averageSpeed,
      );
    }
  }
}
```

**Note**: You'll need to add a method to get the current trip data from `TripRecorderService`.

---

### Phase 4: Update Background Location Service

**File**: `lib/features/trip_detection/services/background_location_service.dart`

Replace basic notification with NotificationService:

#### 4.1 Remove Old Notification Code

**Lines 48-51** (DELETE):
```dart
service.setForegroundNotificationInfo(
  title: "AutoRide",
  content: "Speed: ${location.speedKmh.toStringAsFixed(1)} km/h",
);
```

#### 4.2 Add Periodic Notification Updates

Add near the top of the `onStart` method:

```dart
import 'package:autoride/features/trip_detection/data/services/notification_service.dart';
import 'package:autoride/features/trip_detection/data/services/trip_recorder_service.dart';

// In onStart method, after initialization
Timer? notificationTimer;

// Create periodic timer for notification updates
notificationTimer = Timer.periodic(
  AppConstants.notificationUpdateInterval,
  (_) async {
    try {
      final container = ProviderContainer();

      // Get current trip state
      final stateMachine = await container.read(tripStateMachineProvider.future);

      if (stateMachine is TripStateActive) {
        // Get current metrics
        final recorder = await container.read(tripRecorderServiceProvider.future);
        final location = await container.read(locationServiceProvider.future);

        // Update foreground notification
        await container.read(notificationServiceProvider.notifier)
            .showForegroundNotification(
          distance: recorder.distanceMeters,
          duration: recorder.duration,
          currentSpeed: location.speedKmh,
        );
      }

      container.dispose();
    } catch (e) {
      print('Error updating notification: $e');
    }
  },
);

// Clean up timer when service stops
service.on('stopService').listen((_) {
  notificationTimer?.cancel();
});
```

**Note**: This creates a background timer that updates the foreground notification every 5 seconds with current trip metrics.

---

## Testing Requirements

### Quality Gates

Run these in order:

```bash
# 1. Code generation
flutter pub run build_runner build --delete-conflicting-outputs

# 2. Static analysis (MUST pass)
flutter analyze

# 3. Run on physical device
flutter run --release
```

### Manual Testing Checklist

**Physical Device Required**: Notifications must be tested on real devices.

#### Test Scenarios

1. **Trip Start Notification**
   - [ ] Start a trip (cycling motion detected)
   - [ ] Notification appears: "Trip Started"
   - [ ] Notification auto-dismisses after 5 seconds
   - [ ] Sound plays if enabled in settings
   - [ ] No sound if disabled in settings

2. **Foreground Notification (Active Trip)**
   - [ ] Notification shows: "AutoRide - Trip in Progress"
   - [ ] Stats update every 5 seconds (distance, duration, speed)
   - [ ] Notification has "Pause" and "Stop" actions
   - [ ] Notification persists when app is backgrounded
   - [ ] Notification respects `showOngoingNotification` setting

3. **Trip Stop Notification**
   - [ ] Stop a trip
   - [ ] Notification appears: "Trip Completed"
   - [ ] Shows final stats (distance, duration, avg speed)
   - [ ] Has "View Details" action
   - [ ] Sound plays if enabled in settings
   - [ ] Notification does NOT auto-dismiss

4. **Notification Actions**
   - [ ] Tap "Pause" → Trip pauses
   - [ ] Tap "Resume" → Trip resumes (if paused)
   - [ ] Tap "Stop" → Trip stops
   - [ ] Tap "View Details" → Opens trip history

5. **Settings Integration**
   - [ ] Disable `tripNotificationsEnabled` → No start/stop notifications
   - [ ] Disable `showOngoingNotification` → No foreground notification
   - [ ] Disable `soundOnTripStartStop` → No sound on trip events
   - [ ] Enable all settings → All notifications work

6. **Permission Handling**
   - [ ] Android 13+: Permission request on first launch
   - [ ] iOS: Permission request on first notification
   - [ ] Handle permission denial gracefully

7. **Background Behavior**
   - [ ] App backgrounded → Foreground notification continues
   - [ ] App killed → Service keeps running with notification
   - [ ] Notification tap → Opens app to tracking screen

### Platform-Specific Testing

**Android**:
- [ ] Test on Android 12 (API 31)
- [ ] Test on Android 13+ (API 33+) - notification permission
- [ ] Notification channels work correctly
- [ ] Notification actions trigger correctly

**iOS**:
- [ ] Test on iOS 13+
- [ ] Notification permission request
- [ ] Background notification updates
- [ ] Notification categories work

---

## Common Issues & Solutions

### Issue 1: Notification Not Showing

**Symptoms**: Notification methods called but nothing appears

**Solutions**:
1. Check notification permissions:
   ```dart
   await notificationService.requestPermissions();
   ```
2. Verify notification channel created (Android):
   ```bash
   adb shell dumpsys notification_listener
   ```
3. Check user settings:
   ```dart
   final settings = await ref.read(settingsServiceProvider.future);
   print(settings.showOngoingNotification);
   ```

### Issue 2: Notification Actions Not Working

**Symptoms**: Tapping notification actions does nothing

**Solutions**:
1. Verify `onDidReceiveNotificationResponse` callback is set
2. Check action IDs match exactly
3. Ensure `showsUserInterface` is set correctly for actions

### Issue 3: Permission Request Not Showing (Android 13+)

**Symptoms**: No permission dialog on Android 13+

**Solutions**:
1. Verify `POST_NOTIFICATIONS` in AndroidManifest.xml
2. Call `requestPermissions()` explicitly
3. Check targetSdkVersion is 33+

### Issue 4: Foreground Notification Not Updating

**Symptoms**: Notification shows but stats don't update

**Solutions**:
1. Verify timer is running in background service
2. Check provider container lifecycle
3. Ensure notification ID is consistent

---

## Implementation Checklist

### Phase 1: Setup ✅
- [ ] Add `flutter_local_notifications` to pubspec.yaml
- [ ] Update Android manifest with POST_NOTIFICATIONS
- [ ] Add constants to AppConstants
- [ ] Run `flutter pub get`

### Phase 2: Core Service ✅
- [ ] Create NotificationService class
- [ ] Initialize flutter_local_notifications
- [ ] Create notification channels
- [ ] Implement foreground notification method
- [ ] Implement trip start notification method
- [ ] Implement trip stop notification method
- [ ] Add notification action handlers
- [ ] Integrate with user settings

### Phase 3: Integration ✅
- [ ] Add notification triggers to TripStateMachine
- [ ] Update BackgroundLocationService
- [ ] Add periodic notification updates
- [ ] Handle notification action callbacks

### Phase 4: Testing ✅
- [ ] Run code generation
- [ ] Pass flutter analyze
- [ ] Test all scenarios on physical device
- [ ] Test on Android 12+
- [ ] Test on Android 13+ (permissions)
- [ ] Test on iOS

### Phase 5: Completion ✅
- [ ] Update TASKS.md to mark T025 complete
- [ ] Commit changes with task ID
- [ ] Update progress summary

---

## Expected Outcome

After completing this task:

✅ **Foreground Notification**:
- Rich notification with distance, duration, speed
- Updates every 5 seconds during active trip
- Notification actions work (pause, stop)
- Respects user settings

✅ **Trip Event Notifications**:
- Trip start notification appears automatically
- Trip stop notification shows final stats
- Optional sound effects based on settings

✅ **Permission Handling**:
- Android 13+ notification permission request
- iOS notification permission request
- Graceful fallback if permissions denied

✅ **User Settings Integration**:
- `tripNotificationsEnabled` → Controls start/stop notifications
- `showOngoingNotification` → Controls foreground notification
- `soundOnTripStartStop` → Controls sound effects

---

## Code Examples to Reference

### Freezed Pattern
See: `lib/features/trip_detection/domain/models/location_data.dart`

### Stream Provider Pattern
See: `lib/features/trip_detection/data/services/location_service.dart:85-105`

### State Machine Pattern
See: `lib/features/trip_detection/data/services/trip_state_machine.dart`

### Background Service Pattern
See: `lib/features/trip_detection/services/background_location_service.dart`

---

## Related Documentation

- [flutter_local_notifications](https://pub.dev/packages/flutter_local_notifications)
- [Android Notification Channels](https://developer.android.com/develop/ui/views/notifications/channels)
- [iOS User Notifications](https://developer.apple.com/documentation/usernotifications)
- [Flutter Background Service](https://pub.dev/packages/flutter_background_service)

---

**Created**: 2025-11-23
**Last Updated**: 2025-11-23
**Status**: In Progress
**Assigned**: Claude Code
