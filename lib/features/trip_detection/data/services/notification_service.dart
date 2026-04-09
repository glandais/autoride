import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:autoride/core/constants/app_constants.dart';
import 'package:autoride/features/settings/data/services/settings_service.dart';
import 'package:autoride/features/trip_detection/data/services/trip_recorder_service.dart';

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
      ref.read(tripRecorderServiceProvider.notifier).pauseRecording();
    } else if (action == 'resume') {
      // Trigger resume action
      ref.read(tripRecorderServiceProvider.notifier).resumeRecording();
    } else if (action == 'stop') {
      // Trigger stop action - this will trigger state machine stopTrip()
      // which shows the trip completion notification
      ref.read(tripRecorderServiceProvider.notifier).stopRecording();
    } else if (action == 'view_details') {
      // User tapped "View Details" on trip completion notification
      // TODO: Navigate to trip history/details screen
      // Note: Navigation from notification requires app-level navigation service
      // or deep linking, which is beyond scope of T025
    } else if (response.notificationResponseType ==
               NotificationResponseType.selectedNotification) {
      // User tapped notification body during active trip
      // TODO: Navigate to tracking screen
      // Note: Navigation from notification requires app-level navigation service
      // or deep linking, which is beyond scope of T025
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

    await _notifications.show(
      id: AppConstants.foregroundNotificationId,
      title: 'AutoRide - Trip in Progress',
      body: 'Distance: $distanceKm km • Duration: $durationStr • Speed: $speedKmh km/h',
      notificationDetails: NotificationDetails(android: androidDetails, iOS: iosDetails),
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
      id: AppConstants.tripStartNotificationId,
      title: 'Trip Started',
      body: 'Your cycling trip is now being tracked',
      notificationDetails: NotificationDetails(android: androidDetails, iOS: iosDetails),
    );

    // Auto-dismiss after 5 seconds
    Future.delayed(const Duration(seconds: 5), () {
      _notifications.cancel(id: AppConstants.tripStartNotificationId);
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
      id: AppConstants.tripStopNotificationId,
      title: 'Trip Completed',
      body: 'Distance: $distanceKm km • Duration: $durationStr • Avg Speed: $avgSpeedKmh km/h',
      notificationDetails: NotificationDetails(android: androidDetails, iOS: iosDetails),
    );
  }

  // Cancel foreground notification
  Future<void> cancelForegroundNotification() async {
    await _notifications.cancel(id: AppConstants.foregroundNotificationId);
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
