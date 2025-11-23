import 'dart:async';
import 'dart:ui';
import 'package:flutter/widgets.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../../core/constants/app_constants.dart';

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
        notificationChannelId: AppConstants.tripTrackingChannelId,
        initialNotificationTitle: 'AutoRide',
        initialNotificationContent: 'Initializing trip tracking...',
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

  /// Start background location tracking
  Future<void> startTracking() async {
    final isRunning = await service.isRunning();
    if (!isRunning) {
      await service.startService();
      state = const AsyncValue.data(true);
    }
  }

  /// Stop background location tracking
  Future<void> stopTracking() async {
    final isRunning = await service.isRunning();
    if (isRunning) {
      service.invoke("stopService");
      state = const AsyncValue.data(false);
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
