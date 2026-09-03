import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../core/audit/audit_event.dart';
import '../../../../core/audit/audit_log.dart';
import '../../../../core/constants/app_constants.dart';
import '../../domain/models/activity_confidence.dart';
import '../../domain/models/location_data.dart';
import '../../domain/models/motion_data.dart';
import '../../domain/models/trip.dart';
import '../../domain/models/trip_state.dart';
import '../../domain/models/trip_stop_state.dart';
import 'battery_optimizer.dart';
import 'motion_state_window.dart';
import 'gps_speed_estimator.dart';
import 'pre_trip_location_buffer.dart';
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

  /// Recent motion samples, averaged into the [MotionState] that drives the GPS
  /// gate. Cleared on session teardown: samples from before a suspension say
  /// nothing about the rider now.
  final MotionStateWindow _motionStateWindow = MotionStateWindow();

  /// Fixes received while the GPS gate was open but no trip was recording yet.
  /// Replayed into the recorder when a trip is confirmed, so the ride starts
  /// where the rider actually set off instead of where the detector made up its
  /// mind (L-076). Cleared whenever the history stops being trustworthy: the
  /// gate closing, the session being suspended, a trip starting or ending.
  final PreTripLocationBuffer _preTripLocations = PreTripLocationBuffer();

  /// Supplies the speed the provider omitted, before any consumer sees the fix
  /// (T048, L-087). Placed at ingestion on purpose: the start confidence and
  /// the pre-trip buffer's riding-tail cut are two consumers of one number, and
  /// a correction applied to only one of them is how the 2026-09-03 iPhone
  /// managed to detect its departure and still back-date it by 3 s instead of
  /// 1.3 km.
  final GpsSpeedEstimator _gpsSpeedEstimator = GpsSpeedEstimator();

  /// The pre-trip fixes currently buffered, oldest first.
  @visibleForTesting
  List<LocationData> get debugPreTripLocations => _preTripLocations.locations;

  /// Reference instant for the GPS-loss watchdog (L-074): the reception time of
  /// the last fix, or the moment the current trip started while none has
  /// arrived yet. `null` disarms the watchdog — there is nothing to watch
  /// outside a trip, and it is cleared while a stop is already in flight so the
  /// 1 s tick cannot fire the stop twice.
  DateTime? _gpsWatchdogReference;

  bool _isAnalyzing = false;
  bool _disposed = false;

  /// True from the moment this coordinator decides to start a trip until the
  /// recorder has answered.
  ///
  /// The motion stream runs at ~50 Hz and `_onMotionData` is `async`: every
  /// sample that arrives while `startRecording` is awaiting its database write
  /// re-enters `_analyzeForTripStart` with the state machine still in
  /// `Detecting` and a detector that keeps answering `shouldStart` for the rest
  /// of the evaluation interval. On 2026-09-02 that turned one departure into
  /// two trips in the same millisecond (L-080). The recorder now rejects the
  /// second call, but rejecting it here is what keeps the departure a *single*
  /// decision: no second pre-trip buffer hand-off, no `StateError` to unwind,
  /// and one `start` in the log per departure.
  bool _startInFlight = false;

  // Heartbeat counters (T043). Three integers every 30 s, and they are what
  // makes a gap in the audit log readable at all: `n < expected` means the OS
  // froze the 1 Hz timer (the process was suspended), while `n` intact with
  // `mn == 0` means the process ran but `sensors_plus` delivered nothing —
  // opposite verdicts for items 3 and 8 of the device checklist, and
  // indistinguishable from a plain hole in the timestamps.
  /// False while the counters below describe a period the log was NOT
  /// recording. Enabling the log mid-ride (the normal flow: start riding, then
  /// flip the switch) would otherwise make the first `hb` report a single tick
  /// over a `dt` of minutes — which is exactly the signature of the OS having
  /// frozen the 1 Hz timer, and would invert items 3 and 8 of the checklist.
  bool _heartbeatArmed = false;

  int _heartbeatTicks = 0;
  int _heartbeatMotionSamples = 0;
  int _heartbeatFixes = 0;
  DateTime? _heartbeatSince;
  DateTime? _lastSensorSampleEmit;

  /// Throttle state for the `start` audit event — see [_emitStartEval].
  DateTime? _lastStartEvalEmit;
  int? _lastStartEvalStreak;

  /// Throttle state for the `stop` audit event — see [_emitStopEval].
  DateTime? _lastStopEvalEmit;
  int? _lastStopEvalStationary;
  int? _lastStopEvalMovement;

  /// Throttle state for the `res` audit event — see [_emitResumeEval].
  DateTime? _lastResumeEvalEmit;
  DateTime? _lastResumeEvalMovingSince;

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
      _cleanup('dispose');
      _closeSession();
    });

    return const TripState.idle();
  }

  /// Start listening for trip start conditions
  Future<void> startListening() async {
    _stopRequestedAfterTrip = false;
    if (_isAnalyzing) return;
    _isAnalyzing = true;
    // Belt and braces against a claim that outlived its session: nothing else
    // clears it, and a stuck claim would silently stop this coordinator from
    // ever starting a trip again.
    _startInFlight = false;

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

    _resetHeartbeat();
    AuditLog.emit(
      AuditEvent.session,
      () => <String, Object?>{
        'a': 'start',
        'trip': ref.read(tripStateMachineProvider).hasActiveTrip,
      },
      critical: true,
    );
  }

  void _resetHeartbeat() {
    _heartbeatArmed = true;
    _heartbeatSince = now();
    _heartbeatTicks = 0;
    _heartbeatMotionSamples = 0;
    _heartbeatFixes = 0;
  }

  /// Emit the liveness proof if a heartbeat interval has elapsed.
  ///
  /// `dt` is real elapsed time, not `interval * ticks`: the gap between the two
  /// is precisely what a Doze suspension looks like from inside the process.
  void _emitHeartbeat() {
    final since = _heartbeatSince;
    if (since == null) return;

    final at = now();
    final elapsed = at.difference(since);
    if (elapsed < AppConstants.auditHeartbeatInterval) return;

    final ticks = _heartbeatTicks;
    final motion = _heartbeatMotionSamples;
    final fixes = _heartbeatFixes;
    // Taken (and zeroed) here rather than counted in this class: the drop
    // happens upstream, in `motionDataStream`, and this is the only reader.
    final dropped = motionRateHold.takeDropped();
    _resetHeartbeat();

    AuditLog.emit(
      AuditEvent.heartbeat,
      () => <String, Object?>{
        'n': ticks,
        'mn': motion,
        'fn': fixes,
        'dt': elapsed.inMilliseconds,
        // Samples `motionDataStream` dropped to hold the configured rate
        // (T045). `mn` alone would now read `hz` for ever — the rate hold sits
        // upstream of the counter — and the comparison that found L-086 would
        // be gone: it is `(mn + dr) / (dt / 1000)` that says what the OS really
        // delivered, and `mn / (dt / 1000)` that says what the pipeline paid
        // for.
        'dr': dropped,
        // The rate the power mode in force asks for, next to the samples
        // actually received: it is the only honest way to read a sampling
        // period the OS treats as a hint (L-086). Reading it out of the
        // header's `k` instead would need the reader to first work out which
        // mode was in force at this instant.
        'hz': ref.read(currentPowerModeProvider).sensorSamplingRate,
      },
    );
  }

  /// Discard the pre-trip buffer, saying why.
  ///
  /// Always through here rather than `clear()` directly: an analyst asking
  /// "why did the ride start at the corner instead of at my door" needs to see
  /// which of the four events dropped the approach, and silence looks exactly
  /// like "the buffer never filled".
  void _clearPreTripBuffer(String why) {
    if (_preTripLocations.isEmpty) return;
    _emitBuffer('clear', why: why);
    _preTripLocations.clear();
  }

  /// One `buf` line describing the pre-trip buffer.
  ///
  /// Verbose-only, and the fields are computed inside the closure: the buffer
  /// is touched on every fix, so nothing may be allocated on the path where
  /// the log is off or at normal level. Emitted *before* a `clear` and *after*
  /// an `add`, so `n` always counts the fixes the line is about.
  void _emitBuffer(String action, {String? why, int? kept}) {
    if (!AuditLog.verbose) return;
    AuditLog.emitVerbose(AuditEvent.buffer, () {
      final fixes = _preTripLocations.locations;
      return <String, Object?>{
        'a': action,
        'n': fixes.length,
        'sp': fixes.isEmpty
            ? 0
            : fixes.last.timestamp
                  .difference(fixes.first.timestamp)
                  .inMilliseconds,
        'kp': kept,
        'why': why,
      };
    });
  }

  /// Run one supervisor tick by hand.
  ///
  /// Seam for the tests, same reason as [startDetectionTimer]: the heartbeat
  /// covers 30 real seconds, which no test can wait for.
  @visibleForTesting
  void debugDetectionTick() => _onDetectionTick();

  /// One tick of the 1 Hz supervisor.
  void _onDetectionTick() {
    if (_disposed) return;
    if (AuditLog.enabled) {
      // Re-arm lazily on the first tick after an off->on flip, so the interval
      // that gets reported only ever covers time the log was actually on.
      if (!_heartbeatArmed) _resetHeartbeat();
      _heartbeatTicks++;
      _emitHeartbeat();
    } else {
      // Disabled hot path: a static load and a bool store, no allocation.
      _heartbeatArmed = false;
    }
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

  /// Motion state over the last [AppConstants.stationaryWindowDuration], using
  /// the same thresholds as the windowed analysis in [MotionWindow.state].
  ///
  /// Windowed rather than per-sample: see [MotionStateWindow] for what the
  /// single-sample verdict did to the gate.
  MotionState get _motionState => _motionStateWindow.state;

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

    AuditLog.emit(
      AuditEvent.gate,
      () => <String, Object?>{
        'a': 'open',
        'why': ref.read(tripStateMachineProvider).hasActiveTrip
            ? 'trip'
            : 'motion',
      },
    );

    _closeLocationSubscription = ref.container
        .listen(
          locationStreamProvider(),
          (previous, next) => next.when(
            data: _onLocationData,
            error: (error, stackTrace) {
              // GPS unavailable - continue with motion-only detection
              AuditLog.emit(
                AuditEvent.gpsResubscribe,
                () => <String, Object?>{'a': 'error', 'ex': error.toString()},
                critical: true,
              );
              _lastLocation = null;
              _gpsSpeedEstimator.reset();
              _clearPreTripBuffer('gpsError');
            },
            loading: () {},
          ),
        )
        .close;
  }

  /// Cancel the location subscription and forget the last fix, so detection
  /// degrades to motion-only instead of reasoning about a stale position.
  /// [why] is journalled as-is: a gate closed by session teardown must not read
  /// as a stationary timeout, which is a statement about the *rider*.
  void _closeGpsGate(String why) {
    if (_closeLocationSubscription != null) {
      AuditLog.emit(
        AuditEvent.gate,
        () => <String, Object?>{'a': 'close', 'why': why},
      );
    }
    _cancelGpsInactivityTimer();
    _closeLocationSubscription?.call();
    _closeLocationSubscription = null;
    _lastLocation = null;
    _gpsSpeedEstimator.reset();
    // The gate closing means the rider stood still long enough for the buffered
    // approach to have stopped describing a departure.
    _clearPreTripBuffer(why);
  }

  /// Arm the inactivity timeout once, on the first stationary sample after
  /// movement. Re-arming on every stationary sample would push the deadline
  /// forward forever and GPS would never stop.
  void _scheduleGpsGateClose() {
    if (_closeLocationSubscription == null) return;
    if (_gpsInactivityTimer != null) return;

    AuditLog.emit(
      AuditEvent.gate,
      () => <String, Object?>{
        'a': 'sched',
        'in': gpsInactivityTimeout.inSeconds,
        'why': 'stationary',
      },
    );

    _gpsInactivityTimer = startGpsInactivityTimer(() {
      _gpsInactivityTimer = null;
      if (_disposed) return;
      if (ref.read(tripStateMachineProvider).hasActiveTrip) return;
      _closeGpsGate('inactivityTimeout');
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
      AuditLog.emit(
        AuditEvent.session,
        () => <String, Object?>{'a': 'stop', 'why': 'deferredUntilTripEnds'},
        critical: true,
      );
      _stopRequestedAfterTrip = true;
      return;
    }

    _stopNow();
  }

  void _stopNow() {
    // Only a session that was actually running can stop: `stopListening()` on
    // an idle coordinator is a no-op, and journalling a `stop` for it would
    // invent a session that never existed.
    if (_isAnalyzing) {
      AuditLog.emit(
        AuditEvent.session,
        () => <String, Object?>{'a': 'stop'},
        critical: true,
      );
    }
    _stopRequestedAfterTrip = false;
    // `emitSuspend: false`: the teardown below is the *stop* already recorded
    // above, not a suspend-and-restart. Two session events for one stop made
    // the session count in an exported log wrong.
    _suspendListening(emitSuspend: false);
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
  void _suspendListening({bool emitSuspend = true}) {
    if (_isAnalyzing && emitSuspend) {
      AuditLog.emit(
        AuditEvent.session,
        () => <String, Object?>{'a': 'suspend'},
        critical: true,
      );
    }
    _cleanup(emitSuspend ? 'session' : 'stop');
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
      AuditLog.emit(
        AuditEvent.gpsWatchdog,
        () => <String, Object?>{
          'a': 'arm',
          'lim': gpsLossStopTimeout.inSeconds,
          // Which instant the countdown runs from decides whether a slow first
          // fix can end a ride; item 10 of the checklist is unreadable without
          // it.
          'ref': _lastLocation == null ? 'tripStart' : 'lastFix',
        },
        critical: true,
      );
    } else if (!next.hasActiveTrip) {
      if (_gpsWatchdogReference != null) {
        AuditLog.emit(
          AuditEvent.gpsWatchdog,
          () => <String, Object?>{'a': 'disarm'},
        );
      }
      _gpsWatchdogReference = null;
    }

    AuditLog.emit(
      AuditEvent.stateChange,
      () => <String, Object?>{'f': previous?.stateName, 'to': next.stateName},
      critical: true,
    );

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
    // Retained before anything reads the window: the gate, the audit sample and
    // the detector must all see the same sample included.
    _motionStateWindow.add(motion, now());

    if (AuditLog.enabled) {
      _heartbeatMotionSamples++;
      _emitSensorSample(motion);
    }

    // Motion drives the GPS gate before it drives detection, so the detector
    // sees the location only while GPS is legitimately running.
    _updateGpsGate(_motionState);

    // Get current state machine state
    final currentState = ref.read(tripStateMachineProvider);

    // Analyze based on current state
    await currentState.mapOrNull(
      idle: (_) async {
        // In idle, look for a trip start. The transition into `Detecting` is
        // made by `_analyzeForTripStart` itself, and only once the detector has
        // actually counted a positive detection — see there.
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

  /// One verbose-level sensor aggregate per second.
  ///
  /// Throttled hard on purpose: the stream is 50 Hz, and recording it raw would
  /// be tens of megabytes an hour and would cost more battery than the pipeline
  /// it is meant to explain. One sample a second is enough to see the shape of
  /// a ride against the stationary thresholds.
  void _emitSensorSample(MotionData motion) {
    if (!AuditLog.verbose) return;

    final at = now();
    final last = _lastSensorSampleEmit;
    if (last != null &&
        at.difference(last) < AppConstants.auditSensorSampleInterval) {
      return;
    }
    _lastSensorSampleEmit = at;

    AuditLog.emitVerbose(
      AuditEvent.sensors,
      () => <String, Object?>{
        'am': motion.accelerometer.magnitude,
        'gm': motion.gyroscope.magnitude,
        'ms': _motionState.name,
      },
    );
  }

  /// One `start` audit event per evaluation interval, plus every event that
  /// carries a decision.
  ///
  /// Unthrottled, this fired once per motion sample: a T043 log was 107 757
  /// `start` lines out of 108 870 — 99 % of the file, ~110 a second — which
  /// buries every other event, blows through the log's retention in minutes,
  /// and makes the write cost itself the dominant term in any battery
  /// measurement the log was meant to support (checklist item 4).
  ///
  /// [AppConstants.detectionEvaluationInterval] is the right period because it
  /// is the rate at which a *detection* is actually counted
  /// (`TripStartDetector.analyzeForTripStart`); samples in between only refresh
  /// the confidence score. The two exceptions are never dropped: `shouldStart`
  /// is the departure decision, and a change in the streak is the transition
  /// that explains how the detector got there.
  void _emitStartEval(
    MotionData motion, {
    required int counted,
    required bool shouldStart,
  }) {
    if (!AuditLog.enabled) return;

    final at = now();
    final last = _lastStartEvalEmit;
    final throttled =
        last != null &&
        at.difference(last) < AppConstants.detectionEvaluationInterval;
    if (throttled && !shouldStart && counted == _lastStartEvalStreak) return;

    _lastStartEvalEmit = at;
    _lastStartEvalStreak = counted;

    final detectorState = ref.read(tripStartDetectorProvider);
    final fix = _lastLocation;
    AuditLog.emit(
      AuditEvent.startEval,
      () => <String, Object?>{
        'c': detectorState.confidence,
        'n': counted,
        'go': shouldStart,
        'mag': motion.accelerometer.magnitude,
        'gyr': motion.gyroscope.magnitude,
        'spk': fix?.speedKmh,
        // Whether that speed was allowed to enter `c`, or whether the fix was
        // ruled unfit and the score is motion-only (T048).
        if (fix != null) 'vt': fix.speedIsTrustworthyAt(at),
      },
    );
  }

  /// Handle incoming location data
  void _onLocationData(LocationData rawLocation) {
    // Everything below — the last fix the detectors score against, the buffer,
    // the log — sees the refined fix, so there is exactly one answer in the
    // process to "how fast is this rider going".
    //
    // The gap bound is read from the power mode in force rather than fixed,
    // because it has to sit above the update interval that mode requests; a
    // fixed 30 s against a 30 s interval derived nothing on Android at all.
    final location = _gpsSpeedEstimator.refine(
      rawLocation,
      maxGap: ref.read(currentPowerModeProvider).derivedSpeedMaxGap,
    );
    _lastLocation = location;

    if (AuditLog.enabled) {
      _heartbeatFixes++;
      // `gt` is the provider's own timestamp — on a real GNSS fix, disciplined
      // by the satellites. The median of `t - gt` over a run of fixes is what
      // lets a log be aligned against a FIT recorded on a second device, whose
      // clock is not this one's.
      AuditLog.emit(
        AuditEvent.fix,
        () => <String, Object?>{
          'lat': location.latitude,
          'lon': location.longitude,
          'ac': location.accuracy,
          // `sp` stays the provider's own number, so a log still says what the
          // OS said. `dsp` appears only when T048 replaced it, which makes the
          // substitution countable rather than invisible.
          'sp': rawLocation.speed,
          if (!identical(location, rawLocation)) 'dsp': location.speed,
          'al': location.altitude,
          'hd': location.heading,
          'gt': location.timestamp.millisecondsSinceEpoch,
        },
      );
    }

    // Buffer only while no trip is recording. During a trip the gate is pinned
    // open and the recorder holds its own subscription, so accumulating here
    // would grow a list nobody reads.
    if (ref.read(tripStateMachineProvider).hasActiveTrip) {
      _clearPreTripBuffer('recording');
    } else {
      _preTripLocations.add(location, now());
      _emitBuffer('add');
    }

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

    AuditLog.emit(
      AuditEvent.gpsWatchdog,
      () => <String, Object?>{
        'a': 'fire',
        'el': elapsed.inSeconds,
        'lim': gpsLossStopTimeout.inSeconds,
        'ref': 'lastFix',
      },
      critical: true,
    );

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
    // A departure already being acted on. Evaluating this sample could only
    // produce a second one (L-080), and the detector's verdict for it is
    // answered by the trip that is starting.
    if (_startInFlight) return;

    // Call trip start detector
    final shouldStart = await ref
        .read(tripStartDetectorProvider.notifier)
        // The injected clock, not `DateTime.now()`: T048's freshness arm is
        // part of the confidence now, so the detector needs the coordinator's
        // notion of time for a test to be able to age a fix (L-089).
        .analyzeForTripStart(motion, _lastLocation, now: now());

    // Enter `Detecting` only once the detector has counted at least one
    // positive detection (L-075). It used to be entered on the *first motion
    // sample of any kind*, so a phone merely being carried sat in `Detecting`
    // permanently, hit `detectionTimeoutSeconds` every 30 s and paid the
    // timeout's teardown each time. `startDetecting()` is idle-only, so this is
    // idempotent — and it must also run on the sample that starts the trip,
    // because `startTripWithId` transitions out of `Detecting` and nothing
    // else.
    final counted = ref.read(tripStartDetectorProvider).consecutiveDetections;

    _emitStartEval(motion, counted: counted, shouldStart: shouldStart);

    if (shouldStart || counted > 0) {
      ref.read(tripStateMachineProvider.notifier).startDetecting();
    }

    if (shouldStart) {
      // Re-checked, because the guard at the top of this method only rejects
      // samples that arrive *after* a departure was decided. A sample that
      // entered before it is parked on the detector's `await` above and lands
      // here too — the very interleaving that produced trips 5 and 6 (L-080).
      // Claimed on the same synchronous run as the check, and released in the
      // `finally` below — which is why everything that can throw between here
      // and the recorder call sits inside the `try`: a claim released nowhere
      // else would stop this coordinator from ever starting another trip, for
      // the life of the process and without a line in the log to say so.
      if (_startInFlight) return;
      _startInFlight = true;

      try {
        // Get confidence score from detector
        final detector = ref.read(tripStartDetectorProvider);
        final confidence = detector.confidence;

        // Hand the recorder the fixes already collected during detection, cut
        // back to the first one at cycling speed (L-076): the gate opens on any
        // movement, so the head of the buffer is usually the walk to the bike
        // and must not become part of the ride. Emptied either way — confirmed
        // or failed, this departure is no longer pending.
        final priorLocations = _preTripLocations.ridingTail;
        // `kp` against `n` is what shows the riding-tail cut working: a walk to
        // the bike that was correctly dropped reads as n > kp.
        _emitBuffer('tail', kept: priorLocations.length);
        _preTripLocations.clear();

        // Trigger trip recording (T015)
        // This will create trip in database and update state machine
        await ref
            .read(tripRecorderServiceProvider.notifier)
            .startRecording(
              confidenceScore: confidence,
              activity: ActivityType.cycling,
              priorLocations: priorLocations,
            );
      } catch (e, stackTrace) {
        // startRecording writes to the DB and can throw. Without this guard the
        // exception escapes the stream callback unhandled, the trip silently
        // fails to start, and the UI never learns about it. Reset to idle so the
        // detector can retry on the next motion sample.
        _logger.error('Failed to start trip recording', e, stackTrace);
        // Except when the recorder rejected us because it already owns a start
        // (the manual button won the race): the rejection necessarily arrives
        // *before* the winner reaches `startTripWithId`, so the state machine
        // still reads `detecting` and this teardown would leave the winner's
        // trip published to a database row nothing drives. Asking
        // `hasActiveTrip` cannot tell the two apart — during that window it is
        // false either way — which is why the recorder throws a type.
        if (e is! TripAlreadyStartingError) {
          ref.read(tripStateMachineProvider.notifier).stopTrip();
          ref.read(tripStartDetectorProvider.notifier).reset();
          if (!_disposed) {
            state = AsyncValue.error(e, stackTrace);
          }
        }
        return;
      } finally {
        _startInFlight = false;
      }

      // The provider can be disposed while `startRecording` is awaited (the
      // session torn down, the app killed): every `ref.read` below would then
      // throw inside a callback launched with `unawaited`, i.e. as an unhandled
      // asynchronous error.
      if (_disposed) return;

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

    _emitStopEval(decision);

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

    _emitResumeEval(shouldResume: shouldResume);

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

      // Only the decision, never the `continue` that this branch produces once
      // a second for the whole pause: `res` already reports the paused state,
      // and a second 1 Hz line beside it would say the same thing twice. The
      // decision itself must be here, though — a trip ended by `maxPause` (the
      // way trip 6 of the 2026-09-02 run ended, L-081) used to leave no `stop`
      // line at all, so the log showed the end of a ride with nothing deciding
      // it.
      if (decision != StopDecision.continueTrip) _emitStopEval(decision);

      if (decision == StopDecision.stopTrip) {
        // Stop trip after extended pause
        await _finalizeAndStopTrip();
      }
    }
  }

  /// One `stop` audit event per evaluation interval, plus every event that
  /// carries a decision or a counter change.
  ///
  /// Unthrottled, this fired once per motion sample: the 2026-09-02 Pixel log
  /// held 33 036 `stop` lines with inter-event gaps of 1–12 ms, and together
  /// with `win` and `res` they were 90 % of the file — enough for a verbose
  /// session to purge its own header, `sess start` and `perm` lines through the
  /// 20 MB retention bound inside two hours (L-085). Same throttle as
  /// [_emitStartEval], and the same two exceptions: a decision other than
  /// `continue` is what the reader is looking for, and a change in `cs`/`cm` is
  /// the transition that explains how the detector got there. Both counters
  /// only advance once per [AppConstants.detectionEvaluationInterval] anyway,
  /// so nothing observable is lost between two lines.
  void _emitStopEval(StopDecision decision) {
    if (!AuditLog.enabled) return;

    final stopState = ref.read(tripStopDetectorProvider);
    final stationary = stopState.consecutiveStationaryDetections;
    final movement = stopState.consecutiveMovementDetections;

    final at = now();
    final last = _lastStopEvalEmit;
    final throttled =
        last != null &&
        at.difference(last) < AppConstants.detectionEvaluationInterval;
    if (throttled &&
        decision == StopDecision.continueTrip &&
        stationary == _lastStopEvalStationary &&
        movement == _lastStopEvalMovement) {
      return;
    }

    _lastStopEvalEmit = at;
    _lastStopEvalStationary = stationary;
    _lastStopEvalMovement = movement;

    AuditLog.emit(
      AuditEvent.stopEval,
      () => <String, Object?>{
        'd': decision.name,
        'sta': stopState.isStationary,
        'cs': stationary,
        'cm': movement,
        // Seconds since the *stationary onset*, which is not the recorded
        // pause: the state machine only pauses `minPause` later, so the
        // trip's own `pau` reads ~`minPause` less. See [AuditEvent.stopEval].
        'so': stopState.pauseDuration.inSeconds,
      },
    );
  }

  /// One `res` audit event per evaluation interval, plus every resume decision
  /// and every restart of the sustained-movement timer. Same rationale as
  /// [_emitStopEval] — 23 535 lines on the same run, all of them while a
  /// single trip was paused.
  ///
  /// The timer, not `cm`, is what the throttle keys on: `shouldResumeTrip`
  /// decides on `movementStartTime` — set on the first moving sample, cleared
  /// by any stationary one — and never touches the consecutive-movement
  /// counter. Keying on `cm` would show a flat `res {go:false}` once a second
  /// while the timer started and restarted invisibly underneath, which is
  /// precisely what L-082 has to be diagnosed from. `mv` carries it in
  /// milliseconds because the defect there is 100 ms wide.
  void _emitResumeEval({required bool shouldResume}) {
    if (!AuditLog.enabled) return;

    final stopState = ref.read(tripStopDetectorProvider);
    final movingSince = stopState.movementStartTime;

    final at = now();
    final last = _lastResumeEvalEmit;
    final throttled =
        last != null &&
        at.difference(last) < AppConstants.detectionEvaluationInterval;
    if (throttled &&
        !shouldResume &&
        movingSince == _lastResumeEvalMovingSince) {
      return;
    }

    _lastResumeEvalEmit = at;
    _lastResumeEvalMovingSince = movingSince;

    AuditLog.emit(
      AuditEvent.resumeEval,
      () => <String, Object?>{
        'go': shouldResume,
        'cm': stopState.consecutiveMovementDetections,
        'mv': movingSince == null
            ? 0
            : at.difference(movingSince).inMilliseconds,
        'so': stopState.pauseDuration.inSeconds,
      },
    );
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
    final finalTrip = await ref
        .read(tripRecorderServiceProvider.notifier)
        .stopRecording();

    // Reset both detectors. The START detector matters as much as the stop one:
    // its `consecutiveDetections` streak survives a recording, so without this
    // a single strong sample arriving within `tripStartDetectionWindowSeconds`
    // of the last positive detection would start the *next* trip on that one
    // sample, defeating the consecutive-detection rule entirely (L-074).
    ref.read(tripStopDetectorProvider.notifier).reset();
    ref.read(tripStartDetectorProvider.notifier).reset();

    // Anything buffered during the ride (there should be nothing — see
    // `_onLocationData`) belongs to the trip that just ended, not to the next.
    _clearPreTripBuffer('tripEnd');

    // THIS is a false start: a recording the recorder threw away because it was
    // shorter than `minTripDurationSeconds` (L-068). Backing off for
    // `tripStartCooldownPeriodSeconds` is worth its blind window here, because
    // whatever motion just fooled the detector into starting a trip is still
    // going on. The cooldown must follow `reset()`, which returns the detector
    // to `initial()` — the two only compose in this order.
    //
    // `discarded` alone stopped being the right test when L-081 gave the
    // recorder a second reason to throw a recording away: too few route points.
    // A ride of eleven minutes through an urban canyon whose fixes were all
    // rejected by the accuracy filter is discarded too, and it is not a false
    // start — the detector was right, GPS was not there. Arming the cooldown on
    // it would blind the detector for another 30 s just as the rider comes back
    // into the open, and would journal a `falseStart` that never happened.
    final tooShort =
        (finalTrip?.duration ?? 0) < AppConstants.minTripDurationSeconds;
    if (finalTrip?.status == TripStatus.discarded && tooShort) {
      AuditLog.emit(
        AuditEvent.cooldown,
        () => <String, Object?>{
          'a': 'arm',
          'd': AppConstants.tripStartCooldownPeriodSeconds,
          'why': 'falseStart',
        },
        critical: true,
      );
      _logger.info('Trip discarded as a false start — backing off');
      ref.read(tripStartDetectorProvider.notifier).activateCooldown();
    }

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

  /// Give up on a `Detecting` phase that has run for
  /// `AppConstants.detectionTimeoutSeconds` without confirming a ride.
  ///
  /// Nothing *happened* here: no trip was started, so there is nothing to back
  /// off from. The timeout therefore costs exactly one streak reset and a
  /// return to idle — detection stays live and the very next cycling-shaped
  /// sample can start a trip (L-075).
  ///
  /// It used to do two more things, and both made the detector blind for up to
  /// 30 s at a time: it armed `tripStartCooldownPeriodSeconds` of cooldown
  /// (during which `analyzeForTripStart` returns `false` unconditionally), and
  /// it tore the motion/GPS subscriptions down to restart them 100 ms later.
  /// Combined with entering `Detecting` on any motion sample at all, that gave
  /// a roughly 50 % detection duty cycle for anyone whose phone was moving —
  /// walking to the bike, riding in a car — and a real departure landing inside
  /// a cooldown was missed for up to half a minute. The cooldown now lives
  /// where a false start really occurs: a started-then-discarded trip, in
  /// [_finalizeAndStopTrip].
  void _checkDetectionTimeout() {
    final stateMachine = ref.read(tripStateMachineProvider.notifier);

    if (stateMachine.hasDetectionTimedOut()) {
      AuditLog.emit(
        AuditEvent.detectionTimeout,
        () => <String, Object?>{
          'el': AppConstants.detectionTimeoutSeconds,
          'n': ref.read(tripStartDetectorProvider).consecutiveDetections,
        },
      );

      // Detection timed out - return to idle
      stateMachine.stopTrip();

      // Drop the (unconfirmed) streak so the next window starts clean.
      ref.read(tripStartDetectorProvider.notifier).reset();
    }
  }

  /// Clean up resources. [gateWhy] is what the GPS gate's `close` event will
  /// report — see [_closeGpsGate].
  void _cleanup(String gateWhy) {
    _detectionTimer?.cancel();
    _detectionTimer = null;

    _closeMotionSubscription?.call();
    _closeMotionSubscription = null;

    // Samples from before a suspension describe a rider the session can no
    // longer vouch for; a resumed session must re-fill the window before the
    // gate acts on it.
    _motionStateWindow.clear();

    // Nothing supervises the watchdog while the timer is down.
    _gpsWatchdogReference = null;

    // Suspending the session also closes the GPS gate: the recorder owns its
    // own location subscription while a trip runs, so nothing is lost. Closing
    // the gate clears the pre-trip buffer too.
    _closeGpsGate(gateWhy);
  }
}
