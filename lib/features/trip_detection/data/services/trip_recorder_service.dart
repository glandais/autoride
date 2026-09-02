import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../domain/models/activity_confidence.dart';
import '../../domain/models/location_data.dart';
import '../../domain/models/trip.dart';
import '../../domain/models/trip_state.dart';
import '../../../trip_history/data/repositories/trip_repository.dart';
import '../../../../core/audit/audit_event.dart';
import '../../../../core/audit/audit_log.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/utils/logger.dart';
import 'trip_state_machine.dart';
import 'location_service.dart';

part 'trip_recorder_service.g.dart';

const _logger = Logger('TripRecorderService');

/// Real-time trip metrics exposed to UI
class TripMetrics {
  const TripMetrics({
    required this.distanceMeters,
    required this.durationSeconds,
    required this.routePointCount,
    this.avgSpeedKmh,
    this.maxSpeedKmh,
  });

  final double distanceMeters;
  final int durationSeconds;
  final int routePointCount;
  final double? avgSpeedKmh;
  final double? maxSpeedKmh;

  TripMetrics copyWith({
    double? distanceMeters,
    int? durationSeconds,
    double? avgSpeedKmh,
    double? maxSpeedKmh,
    int? routePointCount,
  }) {
    return TripMetrics(
      distanceMeters: distanceMeters ?? this.distanceMeters,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      avgSpeedKmh: avgSpeedKmh ?? this.avgSpeedKmh,
      maxSpeedKmh: maxSpeedKmh ?? this.maxSpeedKmh,
      routePointCount: routePointCount ?? this.routePointCount,
    );
  }

  double get distanceKm => distanceMeters / 1000.0;

  String get formattedDistance {
    if (distanceKm < 1) {
      return '${distanceMeters.toStringAsFixed(0)} m';
    }
    return '${distanceKm.toStringAsFixed(2)} km';
  }

  String get formattedDuration {
    final hours = durationSeconds ~/ 3600;
    final minutes = (durationSeconds % 3600) ~/ 60;
    final seconds = durationSeconds % 60;

    if (hours > 0) {
      return '${hours}h ${minutes}m ${seconds}s';
    } else if (minutes > 0) {
      return '${minutes}m ${seconds}s';
    }
    return '${seconds}s';
  }
}

/// Thrown by [TripRecorderService.startRecording] when this recorder already
/// owns a start — one that is still in flight, or one that has published its
/// trip.
///
/// A distinct type because the two callers of `startRecording` (the coordinator
/// and the manual button) race each other, and the loser must be able to tell
/// "you are too late, a ride is starting" from "the database write failed".
/// Answering that question with `hasActiveTrip` does not work: the rejection
/// necessarily happens *before* the winner reaches `startTripWithId`, so the
/// state machine still reads `detecting` and the loser's teardown would end the
/// ride the winner just began (L-080).
///
/// Extends [StateError] so the long-standing "double startRecording throws a
/// StateError" contract still holds for callers that only care that it threw.
class TripAlreadyStartingError extends StateError {
  TripAlreadyStartingError(super.message);
}

@riverpod
class TripRecorderService extends _$TripRecorderService {
  // Dependencies (initialized in build)
  TripRepository? _repository;
  TripStateMachine? _stateMachine;

  // State
  Trip? _activeTrip;
  final List<RoutePoint> _routePointBuffer = [];

  /// Route points this recording has kept, buffered and already-flushed alike.
  ///
  /// `_routePointBuffer.length` cannot answer "how much of this ride was
  /// recorded": it empties on every flush, so it reads 0 for most of a long
  /// ride. The stop path needs the cumulative figure to tell a ride from a
  /// recording of nothing (L-081), and the live metrics were reporting the
  /// buffer's length as the trip's point count, which sawtoothed back to zero
  /// every `routePointBufferSize` fixes.
  int _routePointsRecorded = 0;

  /// Held as the subscription's `close` tear-off (`ProviderSubscription` is not
  /// exported by `riverpod_annotation`).
  ///
  /// Opened on `ref.container`, not on `ref`: `ref.keepAlive()` only prevents
  /// *disposal*, and Riverpod 3 deactivates the subscriptions an element opened
  /// itself as soon as nothing listens to that element. A recording whose
  /// screen is unmounted would therefore stop receiving GPS fixes while still
  /// reporting an active trip. Container-owned subscriptions stay active and
  /// are closed by hand on stop and on dispose.
  void Function()? _closeLocationSubscription;
  void Function()? _closeStateMachineSubscription;
  LocationData? _lastLocation;
  Timer? _flushTimer;
  Timer? _metricsTimer;

  // Pause tracking.
  //
  // Kept as a `Duration`, i.e. at millisecond resolution, and rounded to whole
  // seconds only where it is written out (the 30 s snapshot and the final
  // trip). Accumulating `.inSeconds` per pause instead truncated up to 999 ms
  // *each time*, so a ride with many short stops — every red light on a
  // commute — drifted its moving time upwards by seconds (L-073).
  DateTime? _pauseStartTime;
  Duration _totalPauseDuration = Duration.zero;

  // Metrics
  double _totalDistanceMeters = 0.0;
  double _maxSpeedKmh = 0.0;

  /// Set for the lifetime of a recording, so the in-progress trip held in the
  /// fields above survives the last listener going away (a tab switch, the
  /// tracking screen unmounting). Released in [stopRecording], on a failed
  /// [startRecording], and on dispose (audit #2).
  void Function()? _releaseSessionLink;

  /// True from the *synchronous* entry into [startRecording] until that call
  /// has returned, successfully or not.
  ///
  /// `_activeTrip` alone cannot carry the "a trip is starting" invariant: it is
  /// assigned only after `await saveTrip`, so two callers landing in the same
  /// evaluation interval both read `null`, both write a row, and the first trip
  /// is orphaned `active` with no `st` and no stop — exactly what trips 5 and 6
  /// of the 2026-09-02 control run were (L-080). Dart's single thread is what
  /// makes this flag sufficient: nothing can interleave between the test and
  /// the set below, because neither awaits.
  bool _startInFlight = false;

  @override
  Future<TripMetrics> build() async {
    // Deliberately `read`, not `watch`: this build registers the teardown
    // below, and Riverpod runs `onDispose` on every recomputation. Watching a
    // dependency here would silently cancel the location subscription and both
    // timers of a LIVE recording while `_activeTrip` stayed non-null — the trip
    // would look active and record nothing (L-010). With no watched
    // dependencies this provider never recomputes, so teardown means teardown.
    _repository = await ref.read(tripRepositoryProvider.future);
    _stateMachine = ref.read(tripStateMachineProvider.notifier);

    // Listen to state machine changes. This subscription also keeps the
    // (autoDispose) state machine alive for as long as the recorder lives, so a
    // recording session owns its state machine too. It is opened on the
    // container rather than on `ref` for the reason documented on
    // [_closeLocationSubscription].
    _closeStateMachineSubscription?.call();
    _closeStateMachineSubscription = ref.container
        .listen(
          tripStateMachineProvider,
          (previous, next) => _handleStateChange(previous, next),
        )
        .close;

    // Cleanup on dispose
    ref.onDispose(() {
      _stopLocationStream();
      _closeStateMachineSubscription?.call();
      _closeStateMachineSubscription = null;
      _stopFlushTimer();
      _stopMetricsTimer();
      _closeSession();
    });

    return const TripMetrics(
      distanceMeters: 0.0,
      durationSeconds: 0,
      avgSpeedKmh: null,
      maxSpeedKmh: null,
      routePointCount: 0,
    );
  }

  /// Start recording a new trip.
  ///
  /// [priorLocations] are fixes the caller already received *before* the trip
  /// was confirmed — the coordinator's pre-trip buffer (L-076). They are
  /// replayed, oldest first, through the same filters as live fixes, and the
  /// first one that survives them becomes the trip's `startTime`. Callers with
  /// no trustworthy history (the manual start button) pass nothing and get the
  /// previous behaviour: the trip starts now, at zero.
  Future<void> startRecording({
    required double confidenceScore,
    required ActivityType activity,
    List<LocationData> priorLocations = const [],
  }) async {
    if (_activeTrip != null || _startInFlight) {
      throw TripAlreadyStartingError(
        _activeTrip != null
            ? 'Trip already recording'
            : 'Trip start already in flight',
      );
    }
    _startInFlight = true;

    // Own the session for as long as the trip lasts.
    _releaseSessionLink ??= ref.keepAlive().close;

    try {
      await _startRecording(
        confidenceScore: confidenceScore,
        activity: activity,
        priorLocations: priorLocations,
      );
    } catch (_) {
      // A failure AFTER `startTripWithId` would otherwise leave the worst of
      // both states: `_activeTrip` set (so every later start throws for the
      // life of the process) and a state machine saying `active` (so the UI
      // shows a ride with no location stream, no flush timer and no metrics
      // ticker behind it, until the GPS watchdog eventually notices). Roll the
      // publication back; the database row stays `active` for
      // `TripRecoveryService` to close at the next launch, exactly as it does
      // after a process kill.
      //
      // Defence in depth, and untested for that reason: every await after the
      // publication is individually guarded today (the route-point flush and
      // the back-dating write both swallow their own failures), so no current
      // path reaches this branch. It exists so that adding one does not
      // resurrect the wedge.
      if (_activeTrip != null) {
        _activeTrip = null;
        _stopLocationStream();
        _stopFlushTimer();
        _stopMetricsTimer();
        _stateMachine?.stopTrip();
      }
      // Nothing is recording, so the session must not stay pinned.
      _closeSession();
      rethrow;
    } finally {
      _startInFlight = false;
    }
  }

  Future<void> _startRecording({
    required double confidenceScore,
    required ActivityType activity,
    List<LocationData> priorLocations = const [],
  }) async {
    // Lazily resolve the collaborators normally set by build(): on a fresh
    // launch the manual start button can fire before the async build — which
    // awaits the database open — has completed, and `_repository!` then threw
    // "Null check operator used on a null value" (first on-device iOS run,
    // 2026-09-01).
    _repository ??= await ref.read(tripRepositoryProvider.future);
    _stateMachine ??= ref.read(tripStateMachineProvider.notifier);

    // Create initial trip in database
    final initialTrip = Trip(
      startTime: DateTime.now(),
      endTime: DateTime.now(), // Temporary
      distance: 0.0,
      duration: 0,
      avgSpeed: null,
      maxSpeed: null,
      detectedActivity: activity,
      confidenceScore: confidenceScore,
      // Written as `active`: the row exists only so route points have a trip
      // to hang off. It stays out of history until the stop path (or, if the
      // process is killed first, the startup recovery) finalizes it.
      status: TripStatus.active,
      routePoints: [],
    );

    // Save to database to get real ID
    _activeTrip = await _repository!.saveTrip(initialTrip);

    // Update state machine with database ID
    _stateMachine!.startTripWithId(_activeTrip!.id!);

    AuditLog.emit(
      AuditEvent.trip,
      () => <String, Object?>{
        'a': 'start',
        'id': _activeTrip!.id,
        'conf': confidenceScore,
        'act': activity.name,
        // Zero prior locations is what a manual start looks like: the button
        // deliberately prefixes nothing, since a button press has no
        // trustworthy history behind it.
        'pre': priorLocations.length,
      },
      critical: true,
    );

    // Reset metrics
    _totalDistanceMeters = 0.0;
    _maxSpeedKmh = 0.0;
    _totalPauseDuration = Duration.zero;
    _routePointsRecorded = 0;
    _lastLocation = null;

    // Do NOT clear the buffer: it may still hold points from a previous trip
    // whose final flush failed. Each RoutePoint carries its own trip id, so
    // retrying here (and on the periodic flush below) persists them to the
    // right trip instead of discarding them.
    if (_routePointBuffer.isNotEmpty) {
      await _flushRoutePointBuffer(
        maxAttempts: AppConstants.routePointFlushMaxAttempts,
      );
    }

    // Replay whatever the caller already saw. Deliberately AFTER the leftover
    // flush above (those points belong to the previous trip and must not be
    // interleaved with this one's) and BEFORE the location stream opens, so the
    // prefix and the live fixes form one continuous, chronological route and
    // `_lastLocation` is already the last prefixed point when the first live fix
    // arrives.
    await _replayPriorLocations(priorLocations);

    // Start location stream
    _startLocationStream();

    // Start flush timer (backup for distance filter)
    _startFlushTimer();

    // Start metrics ticker so elapsed time keeps advancing even when no new
    // GPS point arrives (red lights, sparse fixes, distance-filtered updates).
    _startMetricsTimer();

    // Update UI state
    _updateMetrics();
  }

  /// Pause trip recording
  Future<void> pauseRecording() async {
    if (_activeTrip == null) return;

    _pauseStartTime = DateTime.now();
    _stateMachine!.pauseTrip();

    AuditLog.emit(
      AuditEvent.trip,
      () => <String, Object?>{
        'a': 'pause',
        'id': _activeTrip!.id,
        'dist': _totalDistanceMeters,
      },
      critical: true,
    );

    // Don't cancel location stream, just stop recording points
    // This allows us to detect resume (motion) faster
  }

  /// Resume trip recording
  Future<void> resumeRecording() async {
    if (_activeTrip == null || _pauseStartTime == null) return;

    // Calculate pause duration
    _totalPauseDuration += DateTime.now().difference(_pauseStartTime!);
    _pauseStartTime = null;

    _stateMachine!.resumeTrip();
    _updateMetrics();

    AuditLog.emit(
      AuditEvent.trip,
      () => <String, Object?>{
        'a': 'resume',
        'id': _activeTrip!.id,
        // The running total is what decides how much of a ride counted as
        // moving time, so it is worth carrying at every pause boundary.
        'pau': _totalPauseDuration.inSeconds,
      },
      critical: true,
    );
  }

  /// Stop recording and save the final trip.
  ///
  /// Returns `null` — and changes nothing — when no trip is being recorded.
  /// "Stop" is a request from a human (the tracking screen's button, the
  /// notification's Stop action) that races with the automatic stop and with
  /// itself: a second tap, or a tap on a notification whose trip the
  /// coordinator has just finalized, is an ordinary outcome, not a programming
  /// error. It used to throw a `StateError` that all three call sites either
  /// logged and swallowed or — in the tracking screen — let escape into an
  /// unhandled async error, so nothing ever depended on the exception (L-074).
  Future<Trip?> stopRecording() async {
    if (_activeTrip == null) {
      _logger.warning('stopRecording() called with no active trip - ignoring');
      return null;
    }

    try {
      return await _stopRecording();
    } finally {
      // Release the session on every exit path, including failures: nothing is
      // recording any more, so the provider may be disposed normally again.
      _closeSession();
    }
  }

  Future<Trip> _stopRecording() async {
    // Stop the periodic snapshot first: a tick landing after the final write
    // below would put the row back to `active` (see _persistPartialMetrics).
    _stopFlushTimer();

    // If still paused, calculate final pause duration
    if (_pauseStartTime != null) {
      _totalPauseDuration += DateTime.now().difference(_pauseStartTime!);
      _pauseStartTime = null;
    }

    // Flush remaining route points before finalizing. This is the last chance
    // to persist the tail of the ride, so retry; if it still fails the points
    // stay buffered (they carry their own trip id) and are retried by the next
    // startRecording, rather than being discarded.
    final flushed = await _flushRoutePointBuffer(
      maxAttempts: AppConstants.routePointFlushMaxAttempts,
    );
    if (!flushed) {
      _logger.error(
        'Final route-point flush failed after '
        '${AppConstants.routePointFlushMaxAttempts} attempts: '
        '${_routePointBuffer.length} points kept buffered for retry '
        'for trip ${_activeTrip!.id}',
      );
    }

    // Calculate final metrics. `duration` is the MOVING time and
    // `pauseDuration` the stopped time; the millisecond-resolution pause total
    // is rounded here, once, rather than at every pause.
    final endTime = DateTime.now();
    final elapsed = endTime.difference(_activeTrip!.startTime);
    final activeDuration = _movingSeconds(elapsed, _totalPauseDuration);
    final avgSpeed = activeDuration > 0
        ? (_totalDistanceMeters / activeDuration) *
              3.6 // m/s to km/h
        : null;

    // Update trip with final metrics
    final candidate = _activeTrip!.copyWith(
      endTime: endTime,
      distance: _totalDistanceMeters,
      duration: activeDuration,
      pauseDuration: _totalPauseDuration.inSeconds,
      avgSpeed: avgSpeed,
      maxSpeed: _maxSpeedKmh > 0 ? _maxSpeedKmh : null,
    );

    // A recording that is too short (a false start: a bump, a mis-tap on the
    // manual start button) or that produced no usable route points (a ride the
    // app has no record of — L-081) is deleted rather than kept as a
    // `discarded` row: `route_points` cascades on the trip's primary key, so
    // one delete removes the whole thing and leaves no debris behind.
    final discarded = !candidate.isRideWorthKeeping(_routePointsRecorded);
    final finalTrip = candidate.copyWith(
      status: discarded ? TripStatus.discarded : TripStatus.completed,
    );

    AuditLog.emit(
      AuditEvent.trip,
      () => <String, Object?>{
        'a': discarded ? 'discard' : 'stop',
        'id': finalTrip.id,
        'dist': finalTrip.distance,
        'dur': finalTrip.duration,
        'pau': finalTrip.pauseDuration,
        'avg': finalTrip.avgSpeed,
        'max': finalTrip.maxSpeed,
        // Total points kept by this recording. It is what the discard decision
        // above turns on, so a `discard` line has to carry it: a 0 m trip with
        // `n` 0 is L-081's case, one with points is a rider who really did go
        // nowhere.
        'n': _routePointsRecorded,
        'pts': flushed ? null : _routePointBuffer.length,
      },
      critical: true,
    );

    if (discarded) {
      _logger.info(
        'Discarding trip ${candidate.id}: ${candidate.duration}s / '
        '$_routePointsRecorded point(s), against a '
        '${AppConstants.minTripDurationSeconds}s and '
        '${AppConstants.minTripRoutePoints}-point minimum',
      );
      try {
        await _repository!.deleteTrip(candidate.id!);
      } catch (e, stackTrace) {
        // Leave the row `active` rather than lying about it: the startup
        // recovery will re-evaluate and delete it on the next launch.
        _logger.error(
          'Failed to delete discarded trip ${candidate.id}',
          e,
          stackTrace,
        );
      }
    } else {
      await _repository!.updateTrip(finalTrip);
    }

    // Cleanup
    _stopLocationStream();
    _stopFlushTimer();
    _stopMetricsTimer();
    _activeTrip = null;
    // Only drop the buffer if it was actually persisted (see above).
    if (flushed) {
      _routePointBuffer.clear();
    }
    _lastLocation = null;
    _totalDistanceMeters = 0.0;
    _maxSpeedKmh = 0.0;
    _totalPauseDuration = Duration.zero;
    _routePointsRecorded = 0;

    // Update state machine. The finalized trip is handed over explicitly: the
    // end-of-trip notification must report the numbers just written to the
    // database, not this provider's live metrics — which the reset above has
    // already zeroed by the time the machine would read them (L-069). A
    // discarded trip must not announce itself as a recorded ride.
    _stateMachine!.stopTrip(discarded: discarded, finalTrip: finalTrip);

    // Reset UI metrics
    state = const AsyncValue.data(
      TripMetrics(
        distanceMeters: 0.0,
        durationSeconds: 0,
        avgSpeedKmh: null,
        maxSpeedKmh: null,
        routePointCount: 0,
      ),
    );

    return finalTrip;
  }

  /// Handle state machine changes
  void _handleStateChange(TripState? previous, TripState next) {
    // This allows external state changes to trigger recording actions
    // For example, manual pause/resume from UI
    if (previous?.isRecording == true && next.isRecording == false) {
      // Paused
      _pauseStartTime ??= DateTime.now();
    } else if (previous?.isRecording == false && next.isRecording == true) {
      // Resumed
      if (_pauseStartTime != null) {
        _totalPauseDuration += DateTime.now().difference(_pauseStartTime!);
        _pauseStartTime = null;
      }
    }
  }

  /// Start location stream subscription.
  ///
  /// Subscribes through `locationStreamProvider`, not by calling the generated
  /// `locationStream(ref)` function: that bypassed overrides (making this path
  /// untestable) and opened a second, unmanaged GPS subscription (audit #5).
  void _startLocationStream() {
    _closeLocationSubscription?.call();
    _closeLocationSubscription = ref.container
        .listen(
          locationStreamProvider(),
          (previous, next) => next.when(
            data: _handleLocationUpdate,
            error: (error, stackTrace) {
              // Surface GPS errors instead of dropping them silently. Recording
              // continues; the metrics ticker keeps elapsed time advancing.
              _logger.error(
                'Location stream error during recording',
                error,
                stackTrace,
              );
            },
            loading: () {},
          ),
        )
        .close;
  }

  /// Stop location stream subscription
  void _stopLocationStream() {
    _closeLocationSubscription?.call();
    _closeLocationSubscription = null;
  }

  /// Release the recording session's keepAlive link.
  void _closeSession() {
    _releaseSessionLink?.call();
    _releaseSessionLink = null;
  }

  /// Replay the fixes received before this trip was confirmed (L-076).
  ///
  /// They go through [_recordLocation] — the very same filters, distance
  /// accumulation, max-speed update and route-point buffering as a live fix — so
  /// there is exactly one definition of what a recorded point is. The trip's
  /// `startTime` is then moved back to the first point that survived those
  /// filters: without that the ride would carry the metres but be timed from the
  /// confirmation, and its duration and average speed would both be wrong. If
  /// nothing survives, the trip keeps the `now` it was created with.
  Future<void> _replayPriorLocations(List<LocationData> locations) async {
    if (locations.isEmpty) return;

    final ordered = [...locations]
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

    DateTime? firstKept;
    for (final location in ordered) {
      if (_recordLocation(location)) {
        firstKept ??= location.timestamp;
      }
    }

    final trip = _activeTrip;
    if (firstKept == null || trip == null) return;
    // Only ever backwards: a buffered fix stamped in the future (a clock jump)
    // must not push the start past the moment the ride was confirmed.
    if (!firstKept.isBefore(trip.startTime)) return;

    _activeTrip = trip.copyWith(startTime: firstKept);

    AuditLog.emit(
      AuditEvent.backdate,
      () => <String, Object?>{
        'id': trip.id,
        'k': ordered.length,
        'm': _totalDistanceMeters,
        'ts': firstKept!.millisecondsSinceEpoch,
        'was': trip.startTime.millisecondsSinceEpoch,
      },
      critical: true,
    );

    _logger.info(
      'Trip ${trip.id} back-dated to $firstKept from '
      '${ordered.length} pre-trip fixes '
      '(${_totalDistanceMeters.toStringAsFixed(0)} m already covered)',
    );

    // `updateTrip` writes the whole row (`Trip.toMap` includes `start_time`), so
    // the 30 s snapshot and the final write would carry this anyway. Doing it
    // now as well means a process death in the first 30 s leaves the recovery a
    // row whose start is the real one rather than the confirmation instant.
    try {
      await _repository!.updateTrip(_activeTrip!);
    } catch (e, stackTrace) {
      // Best effort: the in-memory trip is already correct, and the next
      // snapshot rewrites the row.
      _logger.error(
        'Failed to persist the back-dated start of trip ${trip.id}',
        e,
        stackTrace,
      );
    }

    _updateMetrics();
  }

  /// Handle new location update
  void _handleLocationUpdate(LocationData location) {
    if (_activeTrip == null) return;

    // Don't record during pause
    final currentState = ref.read(tripStateMachineProvider);
    if (!currentState.isRecording) return;

    _recordLocation(location);
  }

  /// Apply the recording filters to [location] and, if it passes all of them,
  /// fold it into the trip. Returns whether the point was kept.
  ///
  /// Split out of [_handleLocationUpdate] so the pre-trip replay can reuse it
  /// without depending on the state machine's phase: the replay runs inside
  /// [_startRecording], and factoring the guards out makes it independent of
  /// where `startTripWithId` happens to sit in that sequence.
  bool _recordLocation(LocationData location) {
    if (_activeTrip == null) return false;

    // Filter by accuracy
    if (location.accuracy > AppConstants.maxLocationAccuracyMeters) {
      _auditDroppedPoint(location, 'acc');
      return false; // Poor GPS fix, skip
    }

    // Filter by speed (outlier rejection)
    if (location.speedKmh > AppConstants.maxCyclingSpeedKmh) {
      _auditDroppedPoint(location, 'speed');
      return false; // Unlikely for cycling, probably GPS error
    }

    // Filter by distance
    if (_lastLocation != null) {
      final distance = location.distanceTo(_lastLocation!);

      // Skip if too close (GPS drift)
      if (distance < AppConstants.minRoutePointDistanceMeters) {
        _auditDroppedPoint(location, 'dist', distance: distance);
        return false;
      }

      // Update total distance
      _totalDistanceMeters += distance;
    }

    // Update max speed
    if (location.speedKmh > _maxSpeedKmh) {
      _maxSpeedKmh = location.speedKmh;
    }

    // Create route point
    final routePoint = RoutePoint.fromLocationData(location, _activeTrip!.id!);

    // Add to buffer
    _routePointBuffer.add(routePoint);
    _routePointsRecorded++;
    _lastLocation = location;

    // Update UI metrics
    _updateMetrics();

    if (AuditLog.enabled) {
      AuditLog.emit(
        AuditEvent.routePoint,
        () => <String, Object?>{
          'a': 'keep',
          'd': _totalDistanceMeters,
          'spk': location.speedKmh,
          'ac': location.accuracy,
        },
      );
    }

    // Flush if buffer full
    if (_routePointBuffer.length >= AppConstants.routePointBufferSize) {
      _flushRoutePointBuffer();
    }

    return true;
  }

  /// A fix the recording filters rejected, and why.
  ///
  /// Verbose-only: on a normal ride most fixes are rejected by the 15 m
  /// distance filter, so at normal level this would be the single largest
  /// contributor to the file for very little insight. It earns its place when
  /// the question is why a route has a hole in it.
  void _auditDroppedPoint(
    LocationData location,
    String reason, {
    double? distance,
  }) {
    if (!AuditLog.verbose) return;
    AuditLog.emitVerbose(
      AuditEvent.routePoint,
      () => <String, Object?>{
        'a': 'drop',
        'why': reason,
        'ac': location.accuracy,
        'spk': location.speedKmh,
        'd': distance,
      },
    );
  }

  /// Flush route point buffer to database.
  ///
  /// Returns true if the buffer was persisted (or was already empty), false if
  /// every attempt failed. On failure the points are kept in the buffer to be
  /// retried on the next flush rather than dropped silently.
  Future<bool> _flushRoutePointBuffer({int maxAttempts = 1}) async {
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      if (_routePointBuffer.isEmpty) return true;

      try {
        final count = _routePointBuffer.length;
        final startedAt = DateTime.now();
        await _repository!.saveRoutePoints(_routePointBuffer);
        _routePointBuffer.clear();

        AuditLog.emit(
          AuditEvent.flush,
          () => <String, Object?>{
            'a': 'points',
            'n': count,
            'ms': DateTime.now().difference(startedAt).inMilliseconds,
            'ok': true,
          },
        );
        return true;
      } catch (e, stackTrace) {
        _logger.error(
          'Failed to flush ${_routePointBuffer.length} route points '
          '(attempt $attempt/$maxAttempts); keeping them buffered for retry',
          e,
          stackTrace,
        );
        if (attempt < maxAttempts) {
          await Future<void>.delayed(AppConstants.routePointFlushRetryDelay);
        }
      }
    }

    return false;
  }

  /// Start periodic flush timer
  void _startFlushTimer() {
    _flushTimer = Timer.periodic(
      const Duration(seconds: AppConstants.maxRecordingIntervalSeconds),
      (_) => _flushProgress(),
    );
  }

  /// Run one periodic-flush cycle by hand.
  ///
  /// The timer that normally drives it fires every
  /// `AppConstants.maxRecordingIntervalSeconds`, which no test can wait for.
  @visibleForTesting
  Future<void> debugFlushProgress() => _flushProgress();

  /// Persist the buffered points *and* the metrics computed so far.
  ///
  /// Distance, max speed and the pause total live only in memory during a
  /// ride, so a process death used to leave a trip row reading 0 m / 0 s no
  /// matter how far the rider had got. Writing them on the existing 30 s flush
  /// (not per point) means the startup recovery has real numbers to fall back
  /// on when the route points alone are not enough.
  Future<void> _flushProgress() async {
    await _flushRoutePointBuffer();
    await _persistPartialMetrics();
  }

  /// Snapshot the in-memory metrics onto the active trip row.
  ///
  /// `endTime` is provisional (now), `duration` excludes the pauses
  /// accumulated so far — including one in progress — and `pause_duration`
  /// records exactly what was excluded, so a process death leaves a row whose
  /// two counters still add up (L-073). Same arithmetic as the live metrics.
  /// The row stays `active`: only a stop or the recovery finalizes it.
  Future<void> _persistPartialMetrics() async {
    final trip = _activeTrip;
    // `_flushTimer == null` means a stop is under way (it cancels the timer
    // before finalizing): a tick whose buffer flush was still in flight must
    // not overwrite the final row with a stale `active` snapshot.
    if (trip == null || _flushTimer == null) return;

    final now = DateTime.now();
    final pauseSoFar = _pauseTotalAt(now);
    final activeDuration = _movingSeconds(
      now.difference(trip.startTime),
      pauseSoFar,
    );

    try {
      await _repository!.updateTrip(
        trip.copyWith(
          endTime: now,
          distance: _totalDistanceMeters,
          duration: activeDuration,
          pauseDuration: pauseSoFar.inSeconds,
          avgSpeed: activeDuration > 0
              ? (_totalDistanceMeters / activeDuration) * 3.6
              : null,
          maxSpeed: _maxSpeedKmh > 0 ? _maxSpeedKmh : null,
          status: TripStatus.active,
        ),
      );
    } catch (e, stackTrace) {
      // Best-effort: a failed snapshot must never interrupt a ride. The next
      // tick retries, and the recovery still has the route points.
      _logger.error(
        'Failed to persist partial metrics for trip ${trip.id}',
        e,
        stackTrace,
      );
    }
  }

  /// Stop flush timer
  void _stopFlushTimer() {
    _flushTimer?.cancel();
    _flushTimer = null;
  }

  /// Start periodic metrics ticker.
  ///
  /// Route points are distance-filtered, so without this the live duration and
  /// average speed freeze whenever the rider is slow/stopped or GPS is sparse.
  void _startMetricsTimer() {
    _metricsTimer?.cancel();
    _metricsTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _updateMetrics(),
    );
  }

  /// Stop metrics ticker
  void _stopMetricsTimer() {
    _metricsTimer?.cancel();
    _metricsTimer = null;
  }

  /// Update UI metrics
  void _updateMetrics() {
    if (_activeTrip == null) return;

    final now = DateTime.now();

    // Calculate active duration (exclude pauses, the one in progress included)
    final activeDuration = _movingSeconds(
      now.difference(_activeTrip!.startTime),
      _pauseTotalAt(now),
    );

    final avgSpeed = activeDuration > 0
        ? (_totalDistanceMeters / activeDuration) *
              3.6 // m/s to km/h
        : null;

    state = AsyncValue.data(
      TripMetrics(
        distanceMeters: _totalDistanceMeters,
        durationSeconds: activeDuration,
        avgSpeedKmh: avgSpeed,
        maxSpeedKmh: _maxSpeedKmh > 0 ? _maxSpeedKmh : null,
        routePointCount: _routePointsRecorded,
      ),
    );
  }

  /// Total time paused as of [now], including a pause still in progress.
  Duration _pauseTotalAt(DateTime now) {
    final start = _pauseStartTime;
    if (start == null) return _totalPauseDuration;
    return _totalPauseDuration + now.difference(start);
  }

  /// Whole seconds of movement in [elapsed] once [paused] is taken out.
  ///
  /// Rounds once, at the point of use, and never returns a negative: clock
  /// adjustments (or a pause that outlives the recording by a few ms) must not
  /// produce a trip of −3 s.
  static int _movingSeconds(Duration elapsed, Duration paused) {
    final moving = elapsed - paused;
    return moving.isNegative ? 0 : moving.inSeconds;
  }
}
