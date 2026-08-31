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
// TODO(T041): nothing in lib/ constructs `tripDetectionCoordinatorProvider`, so
// automatic detection has no entry point and `startListening()` is only reached
// by the coordinator restarting itself. See BLOCKED-pipeline-refactor.md #11.
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
  bool _isAnalyzing = false;
  bool _disposed = false;

  /// How long the rider may stay stationary before the GPS gate closes.
  /// Overridden in tests so the timeout is observable without waiting 30 s.
  @visibleForTesting
  Duration get gpsInactivityTimeout => AppConstants.gpsInactivityTimeout;

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
    if (_isAnalyzing) return;
    _isAnalyzing = true;

    // A detection session owns its own lifetime (audit #2).
    _releaseSessionLink ??= ref.keepAlive().close;

    // Keep the session collaborators alive for as long as we are listening.
    if (_sessionSubscriptionClosers.isEmpty) {
      _sessionSubscriptionClosers.addAll([
        ref.container.listen(tripStateMachineProvider, (_, _) {}).close,
        ref.container.listen(tripStartDetectorProvider, (_, _) {}).close,
        ref.container.listen(tripStopDetectorProvider, (_, _) {}).close,
      ]);
    }

    // Start listening to the motion stream through its provider so overrides
    // apply and a single shared sensor subscription is used (audit #5).
    _closeMotionSubscription = ref.container.listen(
      motionDataStreamProvider,
      (previous, next) => next.when(
        data: (motion) => unawaited(_onMotionData(motion)),
        error: _onMotionStreamError,
        loading: () {},
      ),
    ).close;

    // GPS is NOT subscribed here. It is gated on motion (audit #3): the gate
    // opens on the first moving/cycling sample and closes again after
    // `gpsInactivityTimeout` of stationary. A trip that is already in progress
    // needs speed for auto-pause/stop, so evaluate the gate once now — it opens
    // immediately in that case.
    _updateGpsGate(MotionState.unknown);

    // Set up periodic check for detection timeout
    _detectionTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _checkDetectionTimeout(),
    );
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

    _closeLocationSubscription = ref.container.listen(
      locationStreamProvider(),
      (previous, next) => next.when(
        data: _onLocationData,
        error: (error, stackTrace) {
          // GPS unavailable - continue with motion-only detection
          _lastLocation = null;
        },
        loading: () {},
      ),
    ).close;
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

    _gpsInactivityTimer = Timer(gpsInactivityTimeout, () {
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
  void stopListening() {
    _suspendListening();
    _closeSession();
  }

  /// The motion stream is the heartbeat of detection. If it errors, tear down
  /// consistently and surface the failure rather than leaving a half-running
  /// coordinator with no visible error. This is unrecoverable for the session,
  /// so the keepAlive link is released too.
  void _onMotionStreamError(Object error, StackTrace stackTrace) {
    _logger.error('Motion stream error', error, stackTrace);
    stopListening();
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
        await ref.read(tripRecorderServiceProvider.notifier).startRecording(
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

      // Update coordinator state
      final stateMachineState = ref.read(tripStateMachineProvider);
      state = AsyncValue.data(stateMachineState);

      // Stop analyzing (trip has started). The session link stays open: the
      // trip this coordinator just started must not be torn down with it.
      _suspendListening();
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
      final decision = await ref
          .read(tripStopDetectorProvider.notifier)
          .analyzeForTripStop(motion, _lastLocation);

      if (decision == StopDecision.stopTrip) {
        // Stop trip after extended pause
        await _finalizeAndStopTrip();
      }
    }
  }

  /// Finalize trip data and stop trip
  Future<void> _finalizeAndStopTrip() async {
    // Stop recording and save trip (T015)
    // This calculates final metrics and saves to database
    // Note: stopRecording() calls TripStateMachine.stopTrip() which triggers
    // trip completion notification (implemented in T025)
    await ref.read(tripRecorderServiceProvider.notifier).stopRecording();

    // Reset stop detector
    ref.read(tripStopDetectorProvider.notifier).reset();

    // Update coordinator state
    final stateMachineState = ref.read(tripStateMachineProvider);
    state = AsyncValue.data(stateMachineState);

    // Return to listening for next trip (same session, so the keepAlive link
    // is deliberately kept open across the restart).
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

      // Activate cooldown to prevent immediate restart
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

    // Suspending the session also closes the GPS gate: the recorder owns its
    // own location subscription while a trip runs, so nothing is lost.
    _closeGpsGate();
  }
}
