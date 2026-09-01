import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../domain/models/activity_confidence.dart';
import '../../domain/models/location_data.dart';
import '../../domain/models/trip.dart';
import '../../domain/models/trip_state.dart';
import '../../../trip_history/data/repositories/trip_repository.dart';
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

@riverpod
class TripRecorderService extends _$TripRecorderService {
  // Dependencies (initialized in build)
  TripRepository? _repository;
  TripStateMachine? _stateMachine;

  // State
  Trip? _activeTrip;
  final List<RoutePoint> _routePointBuffer = [];

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

  // Pause tracking
  DateTime? _pauseStartTime;
  int _totalPauseDurationSeconds = 0;

  // Metrics
  double _totalDistanceMeters = 0.0;
  double _maxSpeedKmh = 0.0;

  /// Set for the lifetime of a recording, so the in-progress trip held in the
  /// fields above survives the last listener going away (a tab switch, the
  /// tracking screen unmounting). Released in [stopRecording], on a failed
  /// [startRecording], and on dispose (audit #2).
  void Function()? _releaseSessionLink;

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

  /// Start recording a new trip
  Future<void> startRecording({
    required double confidenceScore,
    required ActivityType activity,
  }) async {
    if (_activeTrip != null) {
      throw StateError('Trip already recording');
    }

    // Own the session for as long as the trip lasts.
    _releaseSessionLink ??= ref.keepAlive().close;

    try {
      await _startRecording(
        confidenceScore: confidenceScore,
        activity: activity,
      );
    } catch (_) {
      // Nothing is recording, so the session must not stay pinned.
      _closeSession();
      rethrow;
    }
  }

  Future<void> _startRecording({
    required double confidenceScore,
    required ActivityType activity,
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

    // Reset metrics
    _totalDistanceMeters = 0.0;
    _maxSpeedKmh = 0.0;
    _totalPauseDurationSeconds = 0;
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

    // Don't cancel location stream, just stop recording points
    // This allows us to detect resume (motion) faster
  }

  /// Resume trip recording
  Future<void> resumeRecording() async {
    if (_activeTrip == null || _pauseStartTime == null) return;

    // Calculate pause duration
    final pauseDuration = DateTime.now().difference(_pauseStartTime!);
    _totalPauseDurationSeconds += pauseDuration.inSeconds;
    _pauseStartTime = null;

    _stateMachine!.resumeTrip();
    _updateMetrics();
  }

  /// Stop recording and save final trip
  Future<Trip> stopRecording() async {
    if (_activeTrip == null) {
      throw StateError('No active trip to stop');
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
      final pauseDuration = DateTime.now().difference(_pauseStartTime!);
      _totalPauseDurationSeconds += pauseDuration.inSeconds;
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

    // Calculate final metrics
    final endTime = DateTime.now();
    final totalDuration = endTime.difference(_activeTrip!.startTime).inSeconds;
    final activeDuration = totalDuration - _totalPauseDurationSeconds;
    final avgSpeed = activeDuration > 0
        ? (_totalDistanceMeters / activeDuration) *
              3.6 // m/s to km/h
        : null;

    // Update trip with final metrics
    final candidate = _activeTrip!.copyWith(
      endTime: endTime,
      distance: _totalDistanceMeters,
      duration: activeDuration,
      avgSpeed: avgSpeed,
      maxSpeed: _maxSpeedKmh > 0 ? _maxSpeedKmh : null,
    );

    // A recording shorter than `minTripDurationSeconds` is a false start (a
    // bump, a mis-tap on the manual start button). It is deleted rather than
    // kept as a `discarded` row: `route_points` cascades on the trip's primary
    // key, so one delete removes the whole thing and leaves no debris behind.
    final discarded = !candidate.isValidTrip;
    final finalTrip = candidate.copyWith(
      status: discarded ? TripStatus.discarded : TripStatus.completed,
    );

    if (discarded) {
      _logger.info(
        'Discarding trip ${candidate.id}: ${candidate.duration}s is below the '
        '${AppConstants.minTripDurationSeconds}s minimum',
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
    _totalPauseDurationSeconds = 0;

    // Update state machine. A discarded trip must not announce itself as a
    // recorded ride.
    _stateMachine!.stopTrip(discarded: discarded);

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
        final pauseDuration = DateTime.now().difference(_pauseStartTime!);
        _totalPauseDurationSeconds += pauseDuration.inSeconds;
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

  /// Handle new location update
  void _handleLocationUpdate(LocationData location) {
    if (_activeTrip == null) return;

    // Don't record during pause
    final currentState = ref.read(tripStateMachineProvider);
    if (!currentState.isRecording) return;

    // Filter by accuracy
    if (location.accuracy > AppConstants.maxLocationAccuracyMeters) {
      return; // Poor GPS fix, skip
    }

    // Filter by speed (outlier rejection)
    if (location.speedKmh > AppConstants.maxCyclingSpeedKmh) {
      return; // Unlikely for cycling, probably GPS error
    }

    // Filter by distance
    if (_lastLocation != null) {
      final distance = location.distanceTo(_lastLocation!);

      // Skip if too close (GPS drift)
      if (distance < AppConstants.minRoutePointDistanceMeters) {
        return;
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
    _lastLocation = location;

    // Update UI metrics
    _updateMetrics();

    // Flush if buffer full
    if (_routePointBuffer.length >= AppConstants.routePointBufferSize) {
      _flushRoutePointBuffer();
    }
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
        await _repository!.saveRoutePoints(_routePointBuffer);
        _routePointBuffer.clear();
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
  /// `endTime` is provisional (now), and `duration` excludes the pauses
  /// accumulated so far, including one in progress — the same arithmetic the
  /// live metrics use. The row stays `active`: only a stop or the recovery
  /// finalizes it.
  Future<void> _persistPartialMetrics() async {
    final trip = _activeTrip;
    // `_flushTimer == null` means a stop is under way (it cancels the timer
    // before finalizing): a tick whose buffer flush was still in flight must
    // not overwrite the final row with a stale `active` snapshot.
    if (trip == null || _flushTimer == null) return;

    final now = DateTime.now();
    var activeDuration =
        now.difference(trip.startTime).inSeconds - _totalPauseDurationSeconds;
    if (_pauseStartTime != null) {
      activeDuration -= now.difference(_pauseStartTime!).inSeconds;
    }

    try {
      await _repository!.updateTrip(
        trip.copyWith(
          endTime: now,
          distance: _totalDistanceMeters,
          duration: activeDuration,
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
    final totalDuration = now.difference(_activeTrip!.startTime).inSeconds;

    // Calculate active duration (exclude pauses)
    int activeDuration = totalDuration - _totalPauseDurationSeconds;
    if (_pauseStartTime != null) {
      // Currently paused - exclude current pause duration
      final currentPauseDuration = now.difference(_pauseStartTime!).inSeconds;
      activeDuration -= currentPauseDuration;
    }

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
        routePointCount: _routePointBuffer.length,
      ),
    );
  }
}
