import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../core/constants/app_constants.dart';
import '../../domain/models/activity_confidence.dart';
import '../../domain/models/location_data.dart';
import '../../domain/models/motion_data.dart';
import '../../domain/models/trip_state.dart';
import '../../domain/models/trip_stop_state.dart';
import 'sensor_service.dart';
import 'location_service.dart';
import 'trip_start_detector.dart';
import 'trip_stop_detector.dart';
import 'trip_state_machine.dart';
import 'trip_recorder_service.dart';
import '../../../../core/utils/logger.dart';

part 'trip_detection_coordinator.g.dart';

const _logger = Logger('TripDetectionCoordinator');

/// Coordinates trip detection by combining motion and location data
///
/// Listens to sensor and GPS streams, analyzes data for trip start/stop,
/// and manages state machine transitions.
///
/// Its lifetime is owned by `AutoDetectionController` (audit #11): that
/// keepAlive provider — instantiated by the app root — calls [startListening]
/// when the "Automatic detection" setting is on and the required permissions
/// are granted, and [stopListening] when either stops being true.
@riverpod
class TripDetectionCoordinator extends _$TripDetectionCoordinator {
  Timer? _detectionTimer;

  // Session subscriptions are opened on `ref.container`, not on `ref`, and are
  // held as their `close` tear-offs (neither `ProviderSubscription` nor
  // `KeepAliveLink` is exported by `riverpod_annotation`).
  //
  // Why the container: `ref.keepAlive()` only prevents *disposal*. When the
  // last listener of this provider goes away (a tab switch, the tracking screen
  // unmounting) Riverpod 3 deactivates every subscription the element itself
  // opened with `ref.listen`, so a kept-alive-but-unlistened coordinator would
  // silently stop receiving motion samples. Container-owned subscriptions stay
  // active; they must therefore be closed by hand (see `_cleanup` /
  // `_closeSession`, both wired to `ref.onDispose`).
  void Function()? _closeMotionSubscription;

  /// Non-null exactly while the GPS gate is OPEN (audit #3). Location is never
  /// subscribed to unconditionally: see [_updateGpsGate].
  void Function()? _closeLocationSubscription;

  /// Runs while the rider is stationary with the gate still open; firing it
  /// closes the gate. Restarted only on the stationary → stationary edge that
  /// follows movement, so the timeout measures a continuous stationary period.
  Timer? _gpsInactivityTimer;

  /// Closers for subscriptions that exist purely to keep the session-scoped
  /// collaborators (state machine, detectors) alive between two motion samples.
  /// They are `autoDispose`, and `ref.read` alone would let them be torn down —
  /// losing the consecutive-detection streaks the detection logic is built on.
  final List<void Function()> _sessionSubscriptionClosers = [];

  /// Set while a detection session is running, so this provider (and through
  /// its subscriptions the state machine and detectors) is not disposed when
  /// the last UI listener goes away — a tab switch must not kill detection.
  void Function()? _releaseSessionLink;

  LocationData? _lastLocation;

  /// Reference instant for the GPS-loss watchdog (L-074): the reception time of
  /// the last fix, or the moment the current trip started while none has
  /// arrived yet. `null` disarms the watchdog — there is nothing to watch
  /// outside a trip, and it is cleared while a stop is already in flight so the
  /// 1 s tick cannot fire the stop twice.
  DateTime? _gpsWatchdogReference;

  bool _isAnalyzing = false;
  bool _disposed = false;

  /// Set when [stopListening] is called while a trip is being recorded. The
  /// session is kept running so auto-pause/auto-stop still work, and the actual
  /// teardown happens once that trip finishes.
  bool _stopRequestedAfterTrip = false;

  /// How long the rider may stay stationary before the GPS gate closes.
  /// Overridden in tests so the timeout is observable without waiting 30 s.
  @visibleForTesting
  Duration get gpsInactivityTimeout => AppConstants.gpsInactivityTimeout;

  /// Arms the timer whose expiry closes the GPS gate.
  ///
  /// Seam for the tests: they substitute a manually fired timer so the gate's
  /// behaviour is asserted on the state transitions themselves instead of on
  /// wall-clock delays, which made "the gate closes after gpsInactivityTimeout"
  /// flaky whenever the shortened timeout elapsed inside a `pumpEventQueue`.
  @visibleForTesting
  Timer startGpsInactivityTimer(void Function() onElapsed) =>
      Timer(gpsInactivityTimeout, onElapsed);

  /// How long a recording trip may go without a GPS fix before it is stopped.
  /// Overridden in tests, like [gpsInactivityTimeout].
  @visibleForTesting
  Duration get gpsLossStopTimeout => AppConstants.gpsLossStopTimeout;

  /// Wall clock, as a seam: the GPS-loss watchdog compares instants, and tests
  /// move this forward instead of waiting ten real minutes.
  @visibleForTesting
  DateTime now() => DateTime.now();

  /// Arms the 1 Hz periodic check that drives [_checkDetectionTimeout] and the
  /// GPS-loss watchdog. Seam for the tests, for the same reason as
  /// [startGpsInactivityTimer]: they fire the tick by hand.
  @visibleForTesting
  Timer startDetectionTimer(void Function() onTick) =>
      Timer.periodic(const Duration(seconds: 1), (_) => onTick());

  @override
  Future<TripState> build() async {
    // Initialize with idle state
    ref.onDispose(() {
      _disposed = true;
      _cleanup();
      _closeSession();
    });

    return const TripState.idle();
  }

  /// Start listening for trip start conditions
  Future<void> startListening() async {
    _stopRequestedAfterTrip = false;
    if (_isAnalyzing) return;
    _isAnalyzing = true;

    // A detection session owns its own lifetime (audit #2).
    _releaseSessionLink ??= ref.keepAlive().close;

    // Keep the session collaborators alive for as long as we are listening.
    if (_sessionSubscriptionClosers.isEmpty) {
      _sessionSubscriptionClosers.addAll([
        ref.container
            .listen(tripStateMachineProvider, _onTripStateChanged)
            .close,
        ref.container.listen(tripStartDetectorProvider, (_, _) {}).close,
        ref.container.listen(tripStopDetectorProvider, (_, _) {}).close,
      ]);
    }

    // Start listening to the motion stream through its provider so overrides
    // apply and a single shared sensor subscription is used (audit #5).
    _closeMotionSubscription = ref.container
        .listen(
          motionDataStreamProvider,
          (previous, next) => next.when(
            data: (motion) => unawaited(_onMotionData(motion)),
            error: _onMotionStreamError,
            loading: () {},
          ),
        )
        .close;

    // GPS is NOT subscribed here. It is gated on motion (audit #3): the gate
    // opens on the first moving/cycling sample and closes again after
    // `gpsInactivityTimeout` of stationary. A trip that is already in progress
    // needs speed for auto-pause/stop, so evaluate the gate once now — it opens
    // immediately in that case.
    _updateGpsGate(MotionState.unknown);

    // A trip already in progress when the session starts (automatic detection
    // switched on mid-ride, a trip recovered at launch) sees no state
    // transition, so `_onTripStateChanged` will never arm its watchdog: do it
    // here instead.
    if (ref.read(tripStateMachineProvider).hasActiveTrip) {
      _gpsWatchdogReference ??= now();
    }

    // Set up the periodic checks: detection timeout, and the GPS-loss watchdog
    // that ends a trip whose positions stopped arriving.
    _detectionTimer = startDetectionTimer(_onDetectionTick);
  }

  /// One tick of the 1 Hz supervisor.
  void _onDetectionTick() {
    if (_disposed) return;
    _checkGpsLossTimeout();
    _checkDetectionTimeout();
  }

  // ---------------------------------------------------------------------------
  // Motion-gated GPS (audit #3 / L-004)
  //
  // The coordinator owns the only detection-phase GPS subscription, so gating
  // lives here rather than in a separate controller: it already sees every
  // motion sample and the trip state, which are exactly the two inputs.
  //
  //   gate CLOSED --(moving | cycling sample, or a trip in progress)--> OPEN
  //   gate OPEN   --(stationary for `gpsInactivityTimeout`, no trip)--> CLOSED
  //
  // `unknown` keeps the current gate. No trip data can be lost: while a trip is
  // being recorded the gate is pinned open, and the recorder holds its own
  // container-owned location subscription for the whole recording anyway.
  // ---------------------------------------------------------------------------

  /// Motion state of a single sample, using the same thresholds as the
  /// windowed analysis in [MotionWindow.state].
  MotionState _motionStateOf(MotionData motion) {
    return MotionWindow(
      samples: [motion],
      startTime: motion.timestamp,
      endTime: motion.timestamp,
    ).state;
  }

  /// Re-evaluate the GPS gate for [motionState].
  void _updateGpsGate(MotionState motionState) {
    // A recording (active or paused) trip always keeps GPS on: auto-pause and
    // auto-stop detection are speed-based.
    if (ref.read(tripStateMachineProvider).hasActiveTrip) {
      _cancelGpsInactivityTimer();
      _openGpsGate();
      return;
    }

    switch (motionState) {
      case MotionState.moving:
      case MotionState.cycling:
        _cancelGpsInactivityTimer();
        _openGpsGate();

      case MotionState.stationary:
        _scheduleGpsGateClose();

      case MotionState.unknown:
        // Not enough information to change anything.
        break;
    }
  }

  /// Subscribe to the location stream if the gate is not already open.
  void _openGpsGate() {
    if (_closeLocationSubscription != null) return;

    _closeLocationSubscription = ref.container
        .listen(
          locationStreamProvider(),
          (previous, next) => next.when(
            data: _onLocationData,
            error: (error, stackTrace) {
              // GPS unavailable - continue with motion-only detection
              _lastLocation = null;
            },
            loading: () {},
          ),
        )
        .close;
  }

  /// Cancel the location subscription and forget the last fix, so detection
  /// degrades to motion-only instead of reasoning about a stale position.
  void _closeGpsGate() {
    _cancelGpsInactivityTimer();
    _closeLocationSubscription?.call();
    _closeLocationSubscription = null;
    _lastLocation = null;
  }

  /// Arm the inactivity timeout once, on the first stationary sample after
  /// movement. Re-arming on every stationary sample would push the deadline
  /// forward forever and GPS would never stop.
  void _scheduleGpsGateClose() {
    if (_closeLocationSubscription == null) return;
    if (_gpsInactivityTimer != null) return;

    _gpsInactivityTimer = startGpsInactivityTimer(() {
      _gpsInactivityTimer = null;
      if (_disposed) return;
      if (ref.read(tripStateMachineProvider).hasActiveTrip) return;
      _closeGpsGate();
    });
  }

  void _cancelGpsInactivityTimer() {
    _gpsInactivityTimer?.cancel();
    _gpsInactivityTimer = null;
  }

  /// Stop listening and release the detection session.
  ///
  /// If a trip is currently being recorded the teardown is DEFERRED until that
  /// trip finishes: auto-pause and auto-stop are driven by this very motion
  /// subscription, so cutting it mid-ride would strand the trip (the user
  /// turning "Automatic detection" off must not break the ride in progress).
  void stopListening() {
    if (_isAnalyzing && ref.read(tripStateMachineProvider).hasActiveTrip) {
      _stopRequestedAfterTrip = true;
      return;
    }

    _stopNow();
  }

  void _stopNow() {
    _stopRequestedAfterTrip = false;
    _suspendListening();
    _closeSession();
  }

  /// The motion stream is the heartbeat of detection. If it errors, tear down
  /// consistently and surface the failure rather than leaving a half-running
  /// coordinator with no visible error. This is unrecoverable for the session,
  /// so the keepAlive link is released too.
  void _onMotionStreamError(Object error, StackTrace stackTrace) {
    _logger.error('Motion stream error', error, stackTrace);
    // Unconditional: with no motion samples there is nothing left to defer to,
    // so this tears down even if a trip is in progress.
    _stopNow();
    if (!_disposed) {
      state = AsyncValue.error(error, stackTrace);
    }
  }

  /// Tear down the streams and the timer but keep the session (and therefore
  /// this provider) alive — used by the paths that immediately restart, and
  /// while a trip that this coordinator started is being recorded.
  void _suspendListening() {
    _cleanup();
    _isAnalyzing = false;
  }

  /// Honour a deferred [stopListening] as soon as the trip it was waiting on
  /// ends — including when the trip is stopped from the UI or a notification
  /// action, which never reaches [_finalizeAndStopTrip].
  void _onTripStateChanged(TripState? previous, TripState next) {
    // Arm the GPS-loss watchdog on every transition into a recording, whoever
    // started it — the automatic path below, the manual start button or a
    // recovered trip. Counting from here (and not from the first fix) is what
    // makes "a trip that never got a fix at all" stoppable, while the grace
    // period before the first fix is exactly `gpsLossStopTimeout`.
    if (next.hasActiveTrip && previous?.hasActiveTrip != true) {
      _gpsWatchdogReference = now();
    } else if (!next.hasActiveTrip) {
      _gpsWatchdogReference = null;
    }

    if (!_stopRequestedAfterTrip) return;
    if (next.hasActiveTrip) return;

    // Deferred: `_stopNow` closes the very subscription this callback is
    // running inside.
    Future.microtask(() {
      if (_disposed) return;
      if (!_stopRequestedAfterTrip) return;
      _stopNow();
    });
  }

  /// Release the session keepAlive link and the collaborator subscriptions.
  void _closeSession() {
    for (final close in _sessionSubscriptionClosers) {
      close();
    }
    _sessionSubscriptionClosers.clear();

    _releaseSessionLink?.call();
    _releaseSessionLink = null;
  }

  /// Handle incoming motion data
  Future<void> _onMotionData(MotionData motion) async {
    // Motion drives the GPS gate before it drives detection, so the detector
    // sees the location only while GPS is legitimately running.
    _updateGpsGate(_motionStateOf(motion));

    // Get current state machine state
    final currentState = ref.read(tripStateMachineProvider);

    // Analyze based on current state
    await currentState.mapOrNull(
      idle: (_) async {
        // In idle, start detection phase
        ref.read(tripStateMachineProvider.notifier).startDetecting();
        await _analyzeForTripStart(motion);
      },
      detecting: (_) async {
        // In detecting, continue analysis for trip start
        await _analyzeForTripStart(motion);
      },
      active: (_) async {
        // In active, check for trip stop/pause
        await _analyzeForTripStop(motion);
      },
      paused: (_) async {
        // In paused, check for resume or stop
        await _analyzeForResume(motion);
      },
    );
  }

  /// Handle incoming location data
  void _onLocationData(LocationData location) {
    _lastLocation = location;

    // Reception time, not `location.timestamp`: a fix replayed from a plugin
    // cache (or one carrying a skewed device clock) still proves the position
    // stream is alive, which is the only thing the watchdog measures. Only
    // armed while a trip is recording — outside one there is nothing to stop.
    if (_gpsWatchdogReference != null) {
      _gpsWatchdogReference = now();
    }
  }

  /// Stop a recording trip that has gone [gpsLossStopTimeout] without a fix.
  ///
  /// The gate is pinned open for the whole recording ([_updateGpsGate]), so
  /// "no fix" here really means the OS is not delivering positions — the phone
  /// left indoors, location services switched off mid-ride, a wedged GPS chip
  /// — and not that the coordinator stopped asking. Without this the trip stays
  /// active for as long as the gyroscope sees any movement at all.
  void _checkGpsLossTimeout() {
    final reference = _gpsWatchdogReference;
    if (reference == null) return;
    if (!ref.read(tripStateMachineProvider).hasActiveTrip) {
      _gpsWatchdogReference = null;
      return;
    }

    final elapsed = now().difference(reference);
    if (elapsed < gpsLossStopTimeout) return;

    _logger.warning(
      'No GPS fix for ${elapsed.inSeconds}s (limit '
      '${gpsLossStopTimeout.inSeconds}s) — stopping the trip',
    );

    // Cleared before the await so a tick landing during the stop cannot
    // re-enter; the trip-state transition would clear it too, but only later.
    _gpsWatchdogReference = null;
    unawaited(_finalizeAndStopTrip());
  }

  /// Analyze motion and location for trip start
  Future<void> _analyzeForTripStart(MotionData motion) async {
    // Call trip start detector
    final shouldStart = await ref
        .read(tripStartDetectorProvider.notifier)
        .analyzeForTripStart(motion, _lastLocation);

    if (shouldStart) {
      // Get confidence score from detector
      final detector = ref.read(tripStartDetectorProvider);
      final confidence = detector.confidence;

      try {
        // Trigger trip recording (T015)
        // This will create trip in database and update state machine
        await ref
            .read(tripRecorderServiceProvider.notifier)
            .startRecording(
              confidenceScore: confidence,
              activity: ActivityType.cycling,
            );
      } catch (e, stackTrace) {
        // startRecording writes to the DB and can throw. Without this guard the
        // exception escapes the stream callback unhandled, the trip silently
        // fails to start, and the UI never learns about it. Reset to idle so the
        // detector can retry on the next motion sample.
        _logger.error('Failed to start trip recording', e, stackTrace);
        ref.read(tripStateMachineProvider.notifier).stopTrip();
        ref.read(tripStartDetectorProvider.notifier).reset();
        if (!_disposed) {
          state = AsyncValue.error(e, stackTrace);
        }
        return;
      }

      // The stop detector inherits whatever it accumulated during the previous
      // ride (or during a paused-then-resumed one), so a new recording starts
      // from a clean pause timer instead of one that may already be most of the
      // way to `maxPauseDurationSeconds`.
      ref.read(tripStopDetectorProvider.notifier).reset();

      // Update coordinator state
      final stateMachineState = ref.read(tripStateMachineProvider);
      state = AsyncValue.data(stateMachineState);

      // Keep listening. Motion (and, through the gate, location) must keep
      // flowing for the whole ride: `_analyzeForTripStop` / `_analyzeForResume`
      // are driven by the same motion subscription, so suspending here — as an
      // earlier version did — meant auto-pause and auto-stop could never fire
      // and a started trip could only be ended by hand.
    }
  }

  /// Analyze motion and location for trip stop/pause
  Future<void> _analyzeForTripStop(MotionData motion) async {
    // Call trip stop detector
    final decision = await ref
        .read(tripStopDetectorProvider.notifier)
        .analyzeForTripStop(motion, _lastLocation);

    if (decision == StopDecision.pauseTrip) {
      // Pause trip
      ref.read(tripStateMachineProvider.notifier).pauseTrip();

      // Update coordinator state
      final stateMachineState = ref.read(tripStateMachineProvider);
      state = AsyncValue.data(stateMachineState);
    } else if (decision == StopDecision.stopTrip) {
      // Stop trip
      await _finalizeAndStopTrip();
    }
  }

  /// Analyze motion and location for trip resume or stop
  Future<void> _analyzeForResume(MotionData motion) async {
    // Check if should resume trip
    final shouldResume = ref
        .read(tripStopDetectorProvider.notifier)
        .shouldResumeTrip(motion, _lastLocation);

    if (shouldResume) {
      // Resume trip
      ref.read(tripStateMachineProvider.notifier).resumeTrip();

      // Reset stop detector
      ref.read(tripStopDetectorProvider.notifier).reset();

      // Update coordinator state
      final stateMachineState = ref.read(tripStateMachineProvider);
      state = AsyncValue.data(stateMachineState);
    } else {
      // Still paused - check if should stop
      // `tripIsPaused: true`: while paused, intermittent movement must not
      // clear the accumulated pause — only a confirmed resume may, and that
      // path resets the detector above. Without this a rider who nudges the
      // bike every few seconds sat in a pause that could never end (L-070).
      final decision = await ref
          .read(tripStopDetectorProvider.notifier)
          .analyzeForTripStop(motion, _lastLocation, tripIsPaused: true);

      if (decision == StopDecision.stopTrip) {
        // Stop trip after extended pause
        await _finalizeAndStopTrip();
      }
    }
  }

  /// Finalize trip data and stop trip
  Future<void> _finalizeAndStopTrip() async {
    // Captured up front: stopping the recording flips the state machine to
    // idle, which lets `_onTripStateChanged` clear the flag before the check
    // below is reached — and the session would then be restarted anyway.
    final stopRequested = _stopRequestedAfterTrip;

    // Stop recording and save trip (T015)
    // This calculates final metrics and saves to database
    // Note: stopRecording() calls TripStateMachine.stopTrip() which triggers
    // trip completion notification (implemented in T025)
    await ref.read(tripRecorderServiceProvider.notifier).stopRecording();

    // Reset both detectors. The START detector matters as much as the stop one:
    // its `consecutiveDetections` streak survives a recording, so without this
    // a single strong sample arriving within `tripStartDetectionWindowSeconds`
    // of the last positive detection would start the *next* trip on that one
    // sample, defeating the consecutive-detection rule entirely (L-074).
    ref.read(tripStopDetectorProvider.notifier).reset();
    ref.read(tripStartDetectorProvider.notifier).reset();

    // Update coordinator state
    final stateMachineState = ref.read(tripStateMachineProvider);
    state = AsyncValue.data(stateMachineState);

    // A stop requested while the trip was running (the user turned automatic
    // detection off mid-ride) is honoured now that the ride is over.
    if (stopRequested) {
      _stopNow();
      return;
    }

    // Return to detecting for the next trip. The streams are restarted rather
    // than merely left running so the detectors and the GPS gate start from a
    // clean slate; the session (and its keepAlive link) is deliberately kept
    // open across the restart.
    _suspendListening();
    await Future.delayed(const Duration(milliseconds: 100));
    if (_disposed) return; // Provider torn down during the delay
    await startListening();
  }

  /// Check if detection phase has timed out
  void _checkDetectionTimeout() {
    final stateMachine = ref.read(tripStateMachineProvider.notifier);

    if (stateMachine.hasDetectionTimedOut()) {
      // Detection timed out - return to idle
      stateMachine.stopTrip();

      // Clear the streak first, then activate the cooldown: `reset()` returns
      // the state to `initial()`, so the two calls only compose in this order.
      ref.read(tripStartDetectorProvider.notifier).reset();
      ref.read(tripStartDetectorProvider.notifier).activateCooldown();

      // Reset and restart listening (same session).
      _suspendListening();
      Future.delayed(const Duration(milliseconds: 100), () {
        if (!_disposed) {
          startListening();
        }
      });
    }
  }

  /// Clean up resources
  void _cleanup() {
    _detectionTimer?.cancel();
    _detectionTimer = null;

    _closeMotionSubscription?.call();
    _closeMotionSubscription = null;

    // Nothing supervises the watchdog while the timer is down.
    _gpsWatchdogReference = null;

    // Suspending the session also closes the GPS gate: the recorder owns its
    // own location subscription while a trip runs, so nothing is lost.
    _closeGpsGate();
  }
}
