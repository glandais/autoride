import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../domain/models/location_data.dart';
import '../../domain/models/trip.dart';
import '../../../trip_history/data/repositories/trip_repository.dart';
import '../../../../core/utils/logger.dart';

part 'trip_recovery_service.g.dart';

const _logger = Logger('TripRecoveryService');

/// What a recovery pass did, so callers (and tests) can assert on it and the
/// launch path can log a single line.
class TripRecoveryReport {
  const TripRecoveryReport({
    this.completed = const [],
    this.deleted = const [],
    this.failed = 0,
  });

  /// Trips closed with metrics recomputed from their persisted route points.
  final List<Trip> completed;

  /// Ids of trips that were removed (nothing worth keeping, or too short).
  final List<int> deleted;

  /// Trips that could not be finalized because the database rejected the
  /// write; they stay `active` and are retried at the next launch.
  final int failed;

  int get inspected => completed.length + deleted.length + failed;

  bool get isEmpty => inspected == 0;

  @override
  String toString() =>
      'TripRecoveryReport(completed: ${completed.length}, '
      'deleted: ${deleted.length}, failed: $failed)';
}

/// Closes trips that a process death left mid-recording.
///
/// A trip row is inserted when recording *starts*, so if the app is killed
/// during a ride the row survives as `active` with the metrics it last
/// snapshotted (the recorder writes those every 30 s). Nothing resumes such a
/// recording — the sensors and the GPS session are gone — so recovery is
/// strictly about closing the books:
///
/// * metrics are recomputed from the route points that did reach the database,
///   which is the most trustworthy record available;
/// * `endTime` becomes the last point's timestamp, so a trip killed at 09:20
///   does not stretch to whenever the app is next opened;
/// * the pause total is read back off the row: since schema v3 (L-073) the
///   recorder snapshots it on the same 30 s flush, so `duration` is
///   (end − start) − `pauseDuration`, floored at 0. Only the pause that was
///   still in progress when the process died (at most one flush interval) is
///   lost, and a row with no snapshot — pre-v3, or killed inside the first
///   30 s — falls back to end − start. That over-counts a ride with long
///   stops, which is the safe direction: it keeps the trip above the validity
///   threshold rather than silently deleting a real ride;
/// * anything still too short (or with no usable points) is deleted, route
///   points included, via the `ON DELETE CASCADE` on `route_points.trip_id`.
class TripRecoveryService {
  const TripRecoveryService(this._repository);

  final TripRepository _repository;

  /// Finalize every `active` trip. Safe to call when none exist.
  Future<TripRecoveryReport> recoverInterruptedTrips() async {
    final interrupted = await _repository.getTripsByStatus(TripStatus.active);
    if (interrupted.isEmpty) {
      return const TripRecoveryReport();
    }

    _logger.info('Found ${interrupted.length} interrupted trip(s) to finalize');

    final completed = <Trip>[];
    final deleted = <int>[];
    var failed = 0;

    for (final trip in interrupted) {
      final tripId = trip.id;
      if (tripId == null) continue;

      try {
        final points = await _repository.getRoutePoints(tripId);
        final recovered = rebuildFromRoutePoints(trip, points);

        // The point-count arm cannot actually decide here — `rebuild` already
        // returned null for anything under two points — but this site applies
        // the whole rule on purpose, so recovery and the live stop path cannot
        // drift apart if `minTripRoutePoints` ever moves.
        if (recovered == null || !recovered.isRideWorthKeeping(points.length)) {
          await _repository.deleteTrip(tripId);
          deleted.add(tripId);
          _logger.info(
            'Deleted interrupted trip $tripId: '
            '${points.length} point(s), '
            '${recovered?.duration ?? 0}s — below the minimum',
          );
        } else {
          await _repository.updateTrip(recovered);
          completed.add(recovered);
          _logger.info(
            'Recovered trip $tripId: ${recovered.distance.toStringAsFixed(0)} m '
            'over ${recovered.duration}s from ${points.length} point(s)',
          );
        }
      } catch (e, stackTrace) {
        failed++;
        _logger.error(
          'Failed to finalize interrupted trip $tripId; it stays active and '
          'will be retried at the next launch',
          e,
          stackTrace,
        );
      }
    }

    return TripRecoveryReport(
      completed: completed,
      deleted: deleted,
      failed: failed,
    );
  }

  /// Recompute a killed trip's metrics from its persisted [points].
  ///
  /// Returns null when there is nothing to rebuild from (fewer than two
  /// points cannot describe a ride), which the caller treats as "delete".
  /// Exposed for testing: this is the whole arithmetic of recovery.
  static Trip? rebuildFromRoutePoints(Trip trip, List<RoutePoint> points) {
    if (points.length < 2) return null;

    final ordered = [...points]
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

    var distanceMeters = 0.0;
    var maxSpeedKmh = 0.0;

    for (var i = 0; i < ordered.length; i++) {
      final speedKmh = ordered[i].speedKmh;
      if (speedKmh > maxSpeedKmh) maxSpeedKmh = speedKmh;

      if (i > 0) {
        distanceMeters += ordered[i - 1].toLocationData().distanceTo(
          ordered[i].toLocationData(),
        );
      }
    }

    final endTime = ordered.last.timestamp;
    // A snapshotted `endTime` can sit past the last point (the recorder writes
    // "now" every 30 s); the points are the harder evidence, so they win.
    //
    // The pause total, by contrast, cannot be derived from the points at all,
    // so the snapshot is the only source there is. Floored at 0: a snapshot
    // taken after the last surviving point can carry more pause than the
    // shortened span contains, and a negative ride is worse than a zero one
    // (it would be deleted as too short either way).
    final elapsedSeconds = endTime.difference(trip.startTime).inSeconds;
    final pauseSeconds = trip.pauseDuration < 0
        ? 0
        : (trip.pauseDuration > elapsedSeconds
              ? (elapsedSeconds > 0 ? elapsedSeconds : 0)
              : trip.pauseDuration);
    final durationSeconds = elapsedSeconds - pauseSeconds;

    return trip.copyWith(
      endTime: endTime,
      distance: distanceMeters,
      duration: durationSeconds,
      pauseDuration: pauseSeconds,
      avgSpeed: durationSeconds > 0
          ? (distanceMeters / durationSeconds) * 3.6
          : null,
      maxSpeed: maxSpeedKmh > 0 ? maxSpeedKmh : null,
      status: TripStatus.completed,
    );
  }
}

/// Runs [TripRecoveryService] once per app launch.
///
/// Kept alive so a tab switch or a rebuild cannot re-run it, and read from
/// `main.dart` right after the first frame — before automatic detection can
/// open a *new* recording, though the two do not conflict either way since a
/// fresh trip is inserted after this pass has read the table.
@Riverpod(keepAlive: true)
Future<TripRecoveryReport> tripRecovery(Ref ref) async {
  final repository = await ref.watch(tripRepositoryProvider.future);
  final report = await TripRecoveryService(repository)
      .recoverInterruptedTrips();

  if (!report.isEmpty) {
    _logger.info('Startup recovery: $report');
  }

  return report;
}
