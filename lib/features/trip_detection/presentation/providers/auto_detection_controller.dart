import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../core/audit/audit_event.dart';
import '../../../../core/audit/audit_log.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/permissions/models/background_location_state.dart';
import '../../../../core/permissions/providers/background_location_status.dart';
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
/// It also owns the Android foreground service. That service runs for the whole
/// time the coordinator is listening — not just while a trip is being recorded —
/// because without it the process is suspended by Doze as soon as the screen
/// goes off, `sensors_plus` stops delivering, and automatic detection can never
/// fire with the phone in a pocket. Its notification has two phases (waiting for
/// a trip / live trip metrics) and this provider keeps it up to date.
@Riverpod(keepAlive: true)
class AutoDetectionController extends _$AutoDetectionController {
  /// Container-owned (see [TripDetectionCoordinator] for why): kept open for
  /// the app's lifetime so trip transitions are seen even when no screen is.
  void Function()? _closeTripStateSubscription;

  /// Open only while a trip is recording; feeds the foreground notification.
  void Function()? _closeMetricsSubscription;

  /// Container-owned, opened once: journals what the OS really grants for
  /// background location, in both directions.
  void Function()? _closeBackgroundStatusSubscription;

  /// Last value applied to the coordinator by the *automatic* path. The manual
  /// start path deliberately does not touch it, so turning the setting on later
  /// still starts detection.
  bool _appliedShouldListen = false;

  bool _permissionRechecked = false;

  /// Last value the `perm` line reported, so a rebuild that changes nothing
  /// stays silent. Held here rather than compared against `state`: reading
  /// `state` during the *first* `build()` throws "Tried to read the state of an
  /// uninitialized provider", which took the whole controller down as soon as
  /// the audit log was already installed — i.e. exactly on the cold starts the
  /// log exists to explain, and why neither 2026-09-02 iPhone session has a
  /// `perm` line.
  AutoDetectionState? _lastAuditedState;

  /// Same, for the `k:background` line: what the OS last reported. See
  /// [_emitBackgroundPermission].
  BackgroundLocationState? _lastAuditedBackgroundStatus;

  /// Mirrors the state machine: true exactly while a trip is being recorded.
  bool _recording = false;

  /// True from the synchronous entry into [startTripManually] until it returns.
  /// See there: `hasActiveTrip` only becomes true after the recorder's database
  /// write, so it cannot keep one tap from becoming two trips (L-080).
  bool _startInFlight = false;

  /// True while the foreground service has been asked to run. It is the
  /// disjunction of "detection is listening" and "a trip is recording", so
  /// neither phase can pull the service out from under the other.
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
      _closeBackgroundStatusSubscription?.call();
      _closeBackgroundStatusSubscription = null;
    });

    // Opened once, not per rebuild.
    _closeTripStateSubscription ??= ref.container
        .listen(tripStateMachineProvider, _onTripStateChanged)
        .close;

    // The app root refreshes this on every resume, precisely because the user
    // can flip "Always" back to "While Using" in system settings behind the
    // app's back. Listening rather than reading once is what puts both
    // directions in the log.
    _closeBackgroundStatusSubscription ??= ref.container.listen(
      backgroundLocationStatusProvider,
      (previous, next) {
        // Only the settled value. `refresh()` invalidates the provider, so
        // every app resume produced an `AsyncLoading` carrying the previous
        // value and then an `AsyncData` — two identical `perm k:background`
        // lines a millisecond apart, which read as a permission that had
        // changed twice (L-086).
        if (next.isLoading || next.hasError) return;
        _emitBackgroundPermission(next.value, 'change');
      },
    ).close;

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

    if (AuditLog.enabled && next != _lastAuditedState) {
      _lastAuditedState = next;
      // Which of the three inputs is false is exactly what explains "detection
      // never started" on a device, and none of it is visible after the fact.
      AuditLog.emit(
        AuditEvent.permission,
        () => <String, Object?>{
          'k': 'autoDetection',
          'en': next.enabled,
          'loc': next.permissionGranted,
          'onb': next.onboardingComplete,
          'go': next.shouldListen,
        },
        critical: true,
      );
    }

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

  /// Journal what the OS actually grants for background location.
  ///
  /// The existing `perm` line with `k` = autoDetection cannot answer this: its
  /// `loc` comes from [LocationPermissionStatus], which folds iOS "While
  /// Using" into `granted` — and "While Using" is exactly the setting under
  /// which iOS terminates the process minutes after the app is backgrounded.
  /// The 2026-09-02 iPhone audit ends in a 40-minute hole with no way to tell
  /// that case from a CoreLocation misconfiguration, because neither log line
  /// carried the answer.
  ///
  /// [why] separates the line emitted on each session start from the ones a
  /// change of authorisation produces, so a reader can tell a downgrade
  /// mid-session from the state detection started in.
  void _emitBackgroundPermission(BackgroundLocationState? status, String why) {
    if (status == null) return;
    if (!AuditLog.enabled) return;

    // A re-read that returns what the OS already reported is not an event.
    // The `session` line is always emitted: it says which state detection
    // started in, which is the question it exists to answer.
    if (why != 'session' && status == _lastAuditedBackgroundStatus) return;
    _lastAuditedBackgroundStatus = status;

    AuditLog.emit(
      AuditEvent.permission,
      () => <String, Object?>{
        'k': 'background',
        'why': why,
        'alw': status.permission.isGranted,
        'acc': status.accuracy.name,
        'issue': status.issue?.name,
      },
      critical: true,
    );
  }

  void _applyAutomatic(bool shouldListen) {
    if (!ref.mounted) return;
    if (shouldListen == _appliedShouldListen) return;
    _appliedShouldListen = shouldListen;

    final coordinator = ref.read(tripDetectionCoordinatorProvider.notifier);
    if (shouldListen) {
      _logger.info('Automatic detection enabled - starting coordinator');
      // Unconditionally, ahead of the coordinator's `sess start`: the
      // change-driven line below may well have been emitted before the log was
      // even switched on, which is how both 2026-09-02 iPhone sessions ended
      // up without one.
      _emitBackgroundPermission(
        ref.read(backgroundLocationStatusProvider).value,
        'session',
      );
      unawaited(coordinator.startListening());
    } else {
      // A trip in progress is not interrupted: the coordinator defers the
      // teardown until that trip finishes.
      _logger.info('Automatic detection disabled - stopping coordinator');
      coordinator.stopListening();
    }

    // The sensors are only delivered while the process is alive, which off a
    // foreground service means "while the screen is on".
    _syncForegroundService();
  }

  /// Start a trip right now, whatever the "Automatic detection" setting says.
  ///
  /// Backs the tracking screen's manual start button. The coordinator is
  /// started too — auto-pause and auto-stop are driven by its motion
  /// subscription — and, when automatic detection is off, released again as
  /// soon as this trip ends.
  Future<void> startTripManually() async {
    if (ref.read(tripStateMachineProvider).hasActiveTrip) return;
    // `hasActiveTrip` alone is the guard L-080 showed to be insufficient: it
    // only becomes true at `startTripWithId`, i.e. after the recorder's
    // database write, so a second tap — or a tap landing while the coordinator
    // is starting a trip — sails past it. Claimed synchronously, before the
    // audit line and before the first `await`, so a rejected tap writes no
    // second `trip start` either.
    if (_startInFlight) return;
    _startInFlight = true;

    try {
      await _startTripManually();
    } finally {
      _startInFlight = false;
    }
  }

  Future<void> _startTripManually() async {
    AuditLog.emit(
      AuditEvent.trip,
      () => <String, Object?>{'a': 'start', 'man': true},
      critical: true,
    );

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
      // Not when the coordinator won the race: it is what the recorder's
      // rejection means, and that rejection lands *before* the winner reaches
      // `startTripWithId` — so `hasActiveTrip` is still false here and cannot
      // be the discriminant. Stopping anyway would end the ride the
      // coordinator just began (L-080, the manual side of the same
      // re-entrancy).
      if (e is TripAlreadyStartingError) {
        // A trip *is* starting — the coordinator's, one motion sample ahead of
        // this tap. The user asked for a ride and is getting one, so this is
        // not an error to put in front of them (the tracking screen turns a
        // throw into a "Could not start the trip" snackbar).
        return;
      }
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
  // Foreground service (audit #7/#8 / L-007, then L-067)
  //
  // The service does no GPS work of its own; the foreground stream is the
  // single source of truth. Its only job is to hold the foreground-service
  // notification — and with it a running process — for as long as the app needs
  // sensors or GPS: the whole detection session, plus any recording. Running it
  // only during a recording (the original scope) meant the detection phase was
  // Doze-suspended with the screen off, so a trip could never start
  // automatically with the phone in a pocket.
  //
  // Android constraints this relies on:
  //   * the service type is `location`, so it may only be started while the
  //     location permission is granted — guaranteed here, since
  //     `shouldListen` requires it;
  //   * Android 12+ forbids starting a foreground service from the background.
  //     Both start paths run with the app in the foreground (app launch, the
  //     settings toggle, the manual start button).
  // ---------------------------------------------------------------------------

  void _onTripStateChanged(TripState? previous, TripState next) {
    final recording = next.hasActiveTrip;
    if (recording == _recording) return;
    _recording = recording;

    if (recording) {
      _closeMetricsSubscription ??= ref.container
          .listen(tripRecorderServiceProvider, _onMetrics)
          .close;
    } else {
      _closeMetricsSubscription?.call();
      _closeMetricsSubscription = null;
    }

    _syncForegroundService();
  }

  /// Brings the foreground service in line with the two things that need it.
  ///
  /// Idempotent, and called from both the detection path and the trip path so
  /// that a trip starting or ending inside a live detection session neither
  /// restarts nor stops the service — only its notification changes phase.
  void _syncForegroundService() {
    final shouldRun = _appliedShouldListen || _recording;

    if (shouldRun == _foregroundServiceRunning) {
      // Already in the right place; only the phase may have changed.
      if (shouldRun && !_recording) {
        _resetNotificationThrottle();
        _pushDetectingNotification();
      } else if (shouldRun) {
        // Entering a recording: let the first metrics tick through at once.
        _resetNotificationThrottle();
      }
      return;
    }

    _foregroundServiceRunning = shouldRun;
    _resetNotificationThrottle();

    if (shouldRun) {
      unawaited(_startForegroundService());
    } else {
      unawaited(_stopForegroundService());
    }
  }

  void _resetNotificationThrottle() {
    _lastNotificationContent = null;
    _lastNotificationAt = null;
  }

  void _pushDetectingNotification() {
    _lastNotificationContent = AppConstants.notificationContentDetecting;
    _lastNotificationAt = DateTime.now();
    ref
        .read(backgroundLocationServiceProvider.notifier)
        .updateNotification(
          title: AppConstants.notificationTitleDetecting,
          content: AppConstants.notificationContentDetecting,
        );
  }

  /// Which OS the `fgs` lines describe.
  ///
  /// The foreground service is an Android concept. On iOS `startService()` only
  /// spins up a second FlutterEngine and holds no notification, so an `fgs
  /// start` there says nothing about whether the process survives being
  /// backgrounded — that rests on `UIBackgroundModes: location` plus an
  /// "Always" authorisation, which the `perm` line with `k` = background
  /// reports. Without this field a reader compares the two devices' logs and
  /// concludes the wrong thing.
  String get _platformTag => switch (defaultTargetPlatform) {
    TargetPlatform.android => 'android',
    TargetPlatform.iOS => 'ios',
    final other => other.name,
  };

  Future<void> _startForegroundService() async {
    try {
      final service = ref.read(backgroundLocationServiceProvider.notifier);
      await service.initialize();
      await service.startTracking();

      // Item 8 of the device checklist stands on this: without the foreground
      // service the process is Doze-suspended during the listening phase and
      // `sensors_plus` delivers nothing.
      AuditLog.emit(
        AuditEvent.foregroundService,
        () => <String, Object?>{'a': 'start', 'plat': _platformTag},
        critical: true,
      );
    } catch (e, stackTrace) {
      // Detection and recording continue without it (the app is then only
      // reliable while the screen is on), so this must not take them down.
      //
      // Journalled as well as logged: a swallowed failure used to leave no
      // `fgs` line at all, which reads exactly like "never called" — the 2026-
      // 09-02 iPhone audit cost an investigation to that ambiguity.
      _logger.error('Failed to start the foreground service', e, stackTrace);
      AuditLog.emit(
        AuditEvent.foregroundService,
        () => <String, Object?>{
          'a': 'fail',
          'plat': _platformTag,
          'ex': e.toString(),
        },
        critical: true,
      );
    }
  }

  Future<void> _stopForegroundService() async {
    try {
      await ref.read(backgroundLocationServiceProvider.notifier).stopTracking();
      AuditLog.emit(
        AuditEvent.foregroundService,
        () => <String, Object?>{'a': 'stop', 'plat': _platformTag},
        critical: true,
      );
    } catch (e, stackTrace) {
      _logger.error('Failed to stop the foreground service', e, stackTrace);
      AuditLog.emit(
        AuditEvent.foregroundService,
        () => <String, Object?>{
          'a': 'fail',
          'plat': _platformTag,
          'ex': e.toString(),
        },
        critical: true,
      );
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
          title: AppConstants.notificationTitleTrip,
          content: content,
        );
  }
}
