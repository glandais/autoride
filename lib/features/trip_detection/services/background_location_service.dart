import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/constants/app_constants.dart';
import '../data/services/notification_service.dart';

part 'background_location_service.g.dart';

/// Background service entry point. Runs in a separate isolate.
///
/// It deliberately does **no** location work (audit #7/#8 / L-007). The
/// foreground stream (`locationStreamProvider`, consumed by the recorder and
/// the detection coordinator) is the single source of truth for a trip; the
/// isolate's only job is to hold the Android foreground-service notification
/// so the OS keeps the process — and with it that stream — alive for as long
/// as automatic detection is listening (and, of course, for the duration of a
/// recording).
///
/// Riverpod is unavailable here, so the main isolate pushes notification text
/// across with `service.invoke('updateNotification', …)`.
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

    // Live trip status pushed by the main isolate.
    service.on('updateNotification').listen((event) async {
      if (event == null) return;
      if (!await service.isForegroundService()) return;

      service.setForegroundNotificationInfo(
        title: (event['title'] as String?) ?? 'AutoRide',
        content: (event['content'] as String?) ?? '',
      );
    });
  }

  // Stop service when requested
  service.on('stopService').listen((event) {
    service.stopSelf();
  });
}

/// `keepAlive`, and it has to be: the only consumer is
/// `AutoDetectionController`, which reaches the notifier through
/// `ref.read(...notifier)` and never watches or listens to it. An autoDispose
/// element read that way has no subscriber, so Riverpod destroys it at the
/// first async gap — the one inside `await initialize()` — and the `state =`
/// at the end of [startTracking] then throws
/// `Cannot use the Ref of backgroundLocationServiceProvider after it has been
/// disposed`. The controller swallows that exception, so the foreground
/// service simply never started (audit of 2026-09-02: not one `fgs` line in
/// the whole iPhone log). It is a race, and Android only ever won it by a few
/// milliseconds.
///
/// Being alive for the app's lifetime also means one single
/// `FlutterBackgroundService()` instance instead of a new one — plus a new
/// `build()` — on every `ref.read`.
@Riverpod(keepAlive: true)
class BackgroundLocationService extends _$BackgroundLocationService {
  final service = FlutterBackgroundService();

  @override
  Future<bool> build() async {
    return await _isServiceRunning();
  }

  /// Initialize background service (call once at app startup)
  Future<void> initialize() async {
    // The foreground-service notification is posted on
    // `tripTrackingChannelId`, and Android kills the process with
    // `CannotPostForegroundServiceNotificationException` when that channel
    // does not exist yet. `NotificationService` is what creates it, so it has
    // to have finished before the service is configured — otherwise the very
    // first launch after an install crash-loops until the OS restricts the
    // app.
    await ref.read(notificationServiceProvider.future);

    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onStart,
        autoStart: false, // Don't auto-start on boot
        isForegroundMode: true, // Critical: keeps service alive
        notificationChannelId: AppConstants.tripTrackingChannelId,
        initialNotificationTitle: AppConstants.notificationTitleDetecting,
        initialNotificationContent: AppConstants.notificationContentDetecting,
        foregroundServiceNotificationId: AppConstants.foregroundNotificationId,
        foregroundServiceTypes: [AndroidForegroundType.location],
      ),
      iosConfiguration: IosConfiguration(
        autoStart: false,
        onForeground: onStart,
        onBackground: onIosBackground,
      ),
    );
  }

  /// Start the foreground service that keeps the app alive while recording.
  ///
  /// The `ref.mounted` guards are belt and braces on top of the `keepAlive`
  /// above: the platform call has already gone through by then, and losing the
  /// cached flag must never take the service down with it.
  Future<void> startTracking() async {
    final isRunning = await service.isRunning();
    if (!isRunning) {
      await service.startService();
      if (ref.mounted) state = const AsyncValue.data(true);
    }
  }

  /// Stop the foreground service.
  Future<void> stopTracking() async {
    final isRunning = await service.isRunning();
    if (isRunning) {
      service.invoke('stopService');
      if (ref.mounted) state = const AsyncValue.data(false);
    }
  }

  /// Push live trip status into the foreground-service notification.
  ///
  /// The notification belongs to the service (same id and channel as
  /// `AppConstants.foregroundNotificationId`), so it is updated from the
  /// isolate rather than through flutter_local_notifications.
  void updateNotification({required String title, required String content}) {
    service.invoke('updateNotification', {'title': title, 'content': content});
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
