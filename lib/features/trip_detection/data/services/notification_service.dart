import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:autoride/core/audit/audit_event.dart';
import 'package:autoride/core/audit/audit_log.dart';
import 'package:autoride/core/constants/app_constants.dart';
import 'package:autoride/core/navigation/app_navigator.dart';
import 'package:autoride/features/settings/data/services/settings_service.dart';
import 'package:autoride/features/trip_detection/data/services/trip_recorder_service.dart';
import 'package:autoride/core/utils/logger.dart';

part 'notification_service.g.dart';

const _logger = Logger('NotificationService');

/// Payload of the notifications that point at the live tracking screen.
const _trackingPayload = 'tracking';

/// Payload prefix of the trip-completed notification: `trip:<id>`.
const _tripPayloadPrefix = 'trip:';

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
    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );

    // iOS initialization
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _notifications.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: handleNotificationResponse,
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
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(trackingChannel);

    await _notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(eventsChannel);
  }

  /// Route a notification tap.
  ///
  /// Public (and not `_onNotificationTap`) so tests can drive a tap without a
  /// platform channel; production only ever reaches it through the plugin's
  /// `onDidReceiveNotificationResponse`.
  @visibleForTesting
  void handleNotificationResponse(NotificationResponse response) {
    // Handle notification actions
    final action = response.actionId;

    if (action == 'pause') {
      // Trigger pause action
      _runAction(
        'pause',
        () => ref.read(tripRecorderServiceProvider.notifier).pauseRecording(),
      );
    } else if (action == 'resume') {
      // Trigger resume action
      _runAction(
        'resume',
        () => ref.read(tripRecorderServiceProvider.notifier).resumeRecording(),
      );
    } else if (action == 'stop') {
      // Trigger stop action - this will trigger state machine stopTrip()
      // which shows the trip completion notification
      _runAction(
        'stop',
        () => ref.read(tripRecorderServiceProvider.notifier).stopRecording(),
      );
    } else if (action == 'view_details') {
      // User tapped "View Details" on the trip completion notification.
      _navigate(response.payload);
    } else if (response.notificationResponseType ==
        NotificationResponseType.selectedNotification) {
      // User tapped the notification body.
      _navigate(response.payload);
    }
  }

  /// Send the user where the tapped notification points.
  ///
  /// The payload is what carries the destination: the ongoing and trip-start
  /// notifications say `tracking`, the completion one says `trip:<id>`. An
  /// unknown or id-less payload falls back to the home shell rather than doing
  /// nothing — a tap that opens the app on nothing reads as a broken
  /// notification.
  void _navigate(String? payload) {
    final navigator = ref.read(appNavigatorProvider);

    if (payload == _trackingPayload) {
      _emitNavigation('track');
      navigator.goToTripTracking();
      return;
    }

    final tripId = payload != null && payload.startsWith(_tripPayloadPrefix)
        ? int.tryParse(payload.substring(_tripPayloadPrefix.length))
        : null;

    if (tripId != null) {
      _emitNavigation('detail');
      navigator.goToTripDetail(tripId);
      return;
    }

    _emitNavigation('home');
    navigator.goToHome();
  }

  /// A tap is a user action the pipeline never sees; without this line the log
  /// shows a screen change with no cause.
  void _emitNavigation(String destination) {
    AuditLog.emit(
      AuditEvent.notification,
      () => <String, Object?>{'a': 'nav', 'k': destination},
      critical: true,
    );
  }

  /// Run a notification action, swallowing the result but never the error.
  ///
  /// `handleNotificationResponse` is a synchronous platform callback, so these
  /// actions
  /// are fire-and-forget. Without this guard a thrown StateError (e.g. stop with
  /// no active trip) or a repository exception becomes an unhandled async error.
  void _runAction(String name, Future<void> Function() action) {
    // Critical: a trip stopped from the notification never reaches the
    // detection pipeline, so without this line the log shows a ride ending for
    // no reason the journal can account for.
    AuditLog.emit(
      AuditEvent.notification,
      () => <String, Object?>{'a': 'action', 'k': name},
      critical: true,
    );
    Future(() async {
      try {
        await action();
      } catch (e, stackTrace) {
        _logger.error('Notification action "$name" failed', e, stackTrace);
      }
    });
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
        : '$minutes:${seconds.toString().padLeft(2, '0')}';
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

    // Verbose: the ongoing notification is refreshed on every metrics update,
    // so at normal level this would be one line per second for nothing.
    AuditLog.emitVerbose(
      AuditEvent.notification,
      () => <String, Object?>{'a': 'show', 'k': 'fg'},
    );

    await _notifications.show(
      id: AppConstants.foregroundNotificationId,
      title: 'AutoRide - Trip in Progress',
      body:
          'Distance: $distanceKm km • Duration: $durationStr • Speed: $speedKmh km/h',
      notificationDetails: NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      ),
      payload: _trackingPayload,
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

    AuditLog.emit(
      AuditEvent.notification,
      () => <String, Object?>{'a': 'show', 'k': 'start'},
    );

    await _notifications.show(
      id: AppConstants.tripStartNotificationId,
      title: 'Trip Started',
      body: 'Your cycling trip is now being tracked',
      notificationDetails: NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      ),
      payload: _trackingPayload,
    );

    // Auto-dismiss after 5 seconds
    Future.delayed(const Duration(seconds: 5), () {
      AuditLog.emit(
        AuditEvent.notification,
        () => <String, Object?>{'a': 'cancel', 'k': 'start'},
      );
      _notifications.cancel(id: AppConstants.tripStartNotificationId);
    });
  }

  // Show trip stop notification
  /// Announce a finished ride.
  ///
  /// [tripId] is the row the "View Details" action opens. It is nullable
  /// because a ride that failed to persist still has to be announced — the tap
  /// then falls back to the history list.
  Future<void> showTripStopNotification({
    required double distance,
    required Duration duration,
    required double avgSpeed,
    int? tripId,
  }) async {
    final settings = await ref.read(settingsServiceProvider.future);

    if (!settings.tripNotificationsEnabled) {
      return; // User disabled trip notifications
    }

    final distanceKm = (distance / 1000).toStringAsFixed(1);
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final durationStr = hours > 0 ? '${hours}h ${minutes}m' : '${minutes}m';
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

    AuditLog.emit(
      AuditEvent.notification,
      () => <String, Object?>{'a': 'show', 'k': 'stop'},
    );

    await _notifications.show(
      id: AppConstants.tripStopNotificationId,
      title: 'Trip Completed',
      body:
          'Distance: $distanceKm km • Duration: $durationStr • Avg Speed: $avgSpeedKmh km/h',
      notificationDetails: NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      ),
      payload: tripId == null ? null : '$_tripPayloadPrefix$tripId',
    );
  }

  // Cancel foreground notification
  Future<void> cancelForegroundNotification() async {
    AuditLog.emit(
      AuditEvent.notification,
      () => <String, Object?>{'a': 'cancel', 'k': 'fg'},
    );
    await _notifications.cancel(id: AppConstants.foregroundNotificationId);
  }

  // Request notification permissions (Android 13+, iOS)
  Future<bool> requestPermissions() async {
    // Android
    final androidImpl = _notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();

    if (androidImpl != null) {
      final granted = await androidImpl.requestNotificationsPermission();
      if (granted != true) {
        return false;
      }
    }

    // iOS
    final iosImpl = _notifications
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();

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
