import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/utils/logger.dart';
import '../../../onboarding/data/services/onboarding_service.dart';
import '../../../settings/data/services/settings_service.dart';
import '../../data/services/location_permission_service.dart';
import '../../data/services/trip_detection_coordinator.dart';
import '../../data/services/trip_recorder_service.dart';
import '../../data/services/trip_state_machine.dart';
import '../../domain/models/activity_confidence.dart';
import '../../domain/models/auto_detection_state.dart';
import '../../domain/models/trip_state.dart';
import '../../services/background_location_service.dart';

part 'auto_detection_controller.g.dart';

const _logger = Logger('AutoDetectionController');

/// Lifecycle owner for automatic trip detection (audit #11 / L-001).
///
/// Nothing used to start [TripDetectionCoordinator], so detection could never
/// run. This provider is the entry point: the app root instantiates it once and
/// it lives for the whole app run (`keepAlive`), watching
///
///   * the persisted "Automatic detection" setting,
///   * location permission,
///   * whether onboarding is complete,
///
/// and starting or stopping the coordinator whenever their conjunction flips.
/// It also owns the Android foreground service, which is started while a trip
/// is being recorded (so the OS keeps the process — and with it the main
/// isolate's GPS stream — alive) and whose notification it keeps up to date.
@Riverpod(keepAlive: true)
class AutoDetectionController extends _$AutoDetectionController {
  /// Container-owned (see [TripDetectionCoordinator] for why): kept open for
  /// the app's lifetime so trip transitions are seen even when no screen is.
  void Function()? _closeTripStateSubscription;

  /// Open only while a trip is recording; feeds the foreground notification.
  void Function()? _closeMetricsSubscription;

  /// Last value applied to the coordinator by the *automatic* path. The manual
  /// start path deliberately does not touch it, so turning the setting on later
  /// still starts detection.
  bool _appliedShouldListen = false;

  bool _permissionRechecked = false;
  bool _foregroundServiceRunning = false;
  String? _lastNotificationContent;
  DateTime? _lastNotificationAt;

  @override
  AutoDetectionState build() {
    ref.onDispose(() {
      _closeTripStateSubscription?.call();
      _closeTripStateSubscription = null;
      _closeMetricsSubscription?.call();
      _closeMetricsSubscription = null;
    });

    // Opened once, not per rebuild.
    _closeTripStateSubscription ??= ref.container
        .listen(tripStateMachineProvider, _onTripStateChanged)
        .close;

    final settings = ref.watch(settingsServiceProvider);
    final permission = ref.watch(locationPermissionServiceProvider);
    final onboarding = ref.watch(onboardingServiceProvider);

    final next = AutoDetectionState(
      // Settings default to "on", but only once they are actually loaded:
      // detection must not start on a guess.
      enabled: settings.value?.detection.automaticDetectionEnabled ?? false,
      permissionGranted: permission.value == LocationPermissionStatus.granted,
      onboardingComplete: onboarding.value == false,
    );

    // Onboarding requests location through `PermissionHandlerService`, which
    // leaves this provider's cached (pre-request) status stale — detection
    // would then wait for an app restart. Re-read it once, right after
    // onboarding completes.
    if (next.onboardingComplete &&
        !next.permissionGranted &&
        !_permissionRechecked) {
      _permissionRechecked = true;
      scheduleMicrotask(refreshPermission);
    }

    // Applied off the build: `startListening` opens subscriptions and touches
    // other providers, which must not happen while this one is building.
    final shouldListen = next.shouldListen;
    scheduleMicrotask(() => _applyAutomatic(shouldListen));

    return next;
  }

  /// Re-read the location permission, which the OS can change behind the app's
  /// back (system settings). Called on app resume by the root widget.
  void refreshPermission() {
    if (!ref.mounted) return;
    ref.invalidate(locationPermissionServiceProvider);
  }

  // ---------------------------------------------------------------------------
  // Detection lifecycle
  // ---------------------------------------------------------------------------

  void _applyAutomatic(bool shouldListen) {
    if (!ref.mounted) return;
    if (shouldListen == _appliedShouldListen) return;
    _appliedShouldListen = shouldListen;

    final coordinator = ref.read(tripDetectionCoordinatorProvider.notifier);
    if (shouldListen) {
      _logger.info('Automatic detection enabled - starting coordinator');
      unawaited(coordinator.startListening());
    } else {
      // A trip in progress is not interrupted: the coordinator defers the
      // teardown until that trip finishes.
      _logger.info('Automatic detection disabled - stopping coordinator');
      coordinator.stopListening();
    }
  }

  /// Start a trip right now, whatever the "Automatic detection" setting says.
  ///
  /// Backs the tracking screen's manual start button. The coordinator is
  /// started too — auto-pause and auto-stop are driven by its motion
  /// subscription — and, when automatic detection is off, released again as
  /// soon as this trip ends.
  Future<void> startTripManually() async {
    if (ref.read(tripStateMachineProvider).hasActiveTrip) return;

    final coordinator = ref.read(tripDetectionCoordinatorProvider.notifier);
    await coordinator.startListening();

    // `startTripWithId` only transitions out of the detecting state, so the
    // manual path takes the same route the detector does.
    ref.read(tripStateMachineProvider.notifier).startDetecting();

    try {
      await ref
          .read(tripRecorderServiceProvider.notifier)
          .startRecording(confidenceScore: 1.0, activity: ActivityType.cycling);
    } catch (e, stackTrace) {
      _logger.error('Manual trip start failed', e, stackTrace);
      ref.read(tripStateMachineProvider.notifier).stopTrip();
      if (!state.shouldListen) coordinator.stopListening();
      rethrow;
    }

    if (!state.shouldListen) {
      // Detection is off: this session exists only for the manual ride. The
      // call is deferred by the coordinator until the trip ends.
      coordinator.stopListening();
    }
  }

  // ---------------------------------------------------------------------------
  // Foreground service (audit #7/#8 / L-007)
  //
  // The service no longer polls GPS of its own; the foreground stream is the
  // single source of truth. Its only job is to hold the foreground-service
  // notification for the duration of a recording so Android keeps the process
  // (and therefore the main isolate's position stream) alive.
  // ---------------------------------------------------------------------------

  void _onTripStateChanged(TripState? previous, TripState next) {
    final recording = next.hasActiveTrip;

    if (recording && !_foregroundServiceRunning) {
      _foregroundServiceRunning = true;
      _lastNotificationContent = null;
      _lastNotificationAt = null;
      unawaited(_startForegroundService());
      _closeMetricsSubscription ??= ref.container
          .listen(tripRecorderServiceProvider, _onMetrics)
          .close;
    } else if (!recording && _foregroundServiceRunning) {
      _foregroundServiceRunning = false;
      _closeMetricsSubscription?.call();
      _closeMetricsSubscription = null;
      unawaited(_stopForegroundService());
    }
  }

  Future<void> _startForegroundService() async {
    try {
      final service = ref.read(backgroundLocationServiceProvider.notifier);
      await service.initialize();
      await service.startTracking();
    } catch (e, stackTrace) {
      // Recording continues without it (the app is then only reliable in the
      // foreground), so this must not take the trip down.
      _logger.error('Failed to start the foreground service', e, stackTrace);
    }
  }

  Future<void> _stopForegroundService() async {
    try {
      await ref.read(backgroundLocationServiceProvider.notifier).stopTracking();
    } catch (e, stackTrace) {
      _logger.error('Failed to stop the foreground service', e, stackTrace);
    }
  }

  /// How often the notification text may change. Overridden in tests.
  @visibleForTesting
  Duration get notificationUpdateInterval =>
      AppConstants.notificationUpdateInterval;

  void _onMetrics(
    AsyncValue<TripMetrics>? previous,
    AsyncValue<TripMetrics> next,
  ) {
    final metrics = next.value;
    if (metrics == null || !_foregroundServiceRunning) return;

    // The recorder ticks once a second; the notification does not need to.
    final now = DateTime.now();
    final last = _lastNotificationAt;
    if (last != null && now.difference(last) < notificationUpdateInterval) {
      return;
    }

    final content =
        '${metrics.formattedDistance} • ${metrics.formattedDuration}';
    if (content == _lastNotificationContent) return;
    _lastNotificationContent = content;
    _lastNotificationAt = now;

    ref
        .read(backgroundLocationServiceProvider.notifier)
        .updateNotification(
          title: 'AutoRide - Trip in progress',
          content: content,
        );
  }
}
