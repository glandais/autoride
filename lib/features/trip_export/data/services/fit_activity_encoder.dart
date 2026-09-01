import 'dart:typed_data';

import 'package:fit_dart_sdk/fit_dart_sdk.dart' hide ActivityType;

import 'package:autoride/features/trip_detection/domain/models/activity_confidence.dart';
import 'package:autoride/features/trip_detection/domain/models/location_data.dart';
import 'package:autoride/features/trip_detection/domain/models/trip.dart';

/// Encodes a recorded [Trip] as a Garmin FIT *activity* file.
///
/// Pure Dart on purpose: no `dart:io`, no plugin, no provider. It takes a trip
/// and returns bytes, which is what makes it testable off-device — writing and
/// sharing those bytes is [TripExportService]'s job.
///
/// The message sequence is the one every FIT reader expects of an activity —
/// `file_id`, `device_info`, a timer `start` event, the records, a timer `stop`
/// event, then the `lap` / `session` / `activity` summaries. Readers reject a
/// file that omits `file_id`, and most ignore records that no session covers.
abstract final class FitActivityEncoder {
  /// Semicircles per degree: 2^31 / 180, FIT's angular unit.
  static const double _semicirclesPerDegree = 2147483648 / 180;

  /// Altitude noise gate, in meters.
  ///
  /// GPS altitude wanders by a meter or two while standing still; summing raw
  /// deltas would report hundreds of meters of climbing on a flat ride.
  static const double _elevationThresholdMeters = 3.0;

  /// Encode [trip] and its route points as FIT bytes.
  ///
  /// A trip with no route points still produces a valid file: the summary
  /// messages carry the recorded distance and durations, there are simply no
  /// `record` messages to plot.
  static Uint8List encode(Trip trip) {
    final points = List<RoutePoint>.of(trip.routePoints)
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

    final start = trip.startTime;
    final end = trip.endTime;
    final elapsed = trip.tripDuration.inMilliseconds / 1000.0;
    // FIT keeps the two apart the way the model does: total_elapsed_time is
    // start-to-finish including the stops, total_timer_time is moving time
    // only. The trip stores the pause *total* and not the intervals, so there
    // is nothing to emit per-pause timer events from.
    final moving = trip.movingDuration.inSeconds.toDouble();
    final elevation = _elevation(points);

    return encodeFit((encoder) {
      encoder.write(
        FileIdMesg()
          ..type = FitFile.activity
          ..manufacturer = Manufacturer.development
          ..product = 0
          ..serialNumber = 0
          ..timeCreated = start,
      );

      encoder.write(
        DeviceInfoMesg()
          ..deviceIndex = DeviceIndexValues.creator
          ..manufacturer = Manufacturer.development
          ..productName = 'AutoRide'
          ..timestamp = start,
      );

      encoder.write(
        EventMesg()
          ..timestamp = start
          ..event = Event.timer
          ..eventType = EventType.start,
      );

      var distance = 0.0;
      RoutePoint? previous;
      for (final point in points) {
        if (previous != null) {
          distance += previous.toLocationData().distanceTo(
            point.toLocationData(),
          );
        }
        encoder.write(_record(point, distance));
        previous = point;
      }

      encoder.write(
        EventMesg()
          ..timestamp = end
          ..event = Event.timer
          ..eventType = EventType.stop,
      );

      encoder.write(
        LapMesg()
          ..messageIndex = 0
          ..timestamp = end
          ..startTime = start
          ..totalElapsedTime = elapsed
          ..totalTimerTime = moving
          ..totalDistance = trip.distance
          ..totalAscent = elevation.ascent
          ..totalDescent = elevation.descent
          ..sport = _sportFor(trip.detectedActivity)
          ..event = Event.lap
          ..eventType = EventType.stop
          ..avgSpeed = _msFromKmh(trip.avgSpeed)
          ..maxSpeed = _msFromKmh(trip.maxSpeed)
          ..startPositionLat = _semicircles(points.firstOrNull?.latitude)
          ..startPositionLong = _semicircles(points.firstOrNull?.longitude),
      );

      encoder.write(
        SessionMesg()
          ..messageIndex = 0
          ..timestamp = end
          ..startTime = start
          ..totalElapsedTime = elapsed
          ..totalTimerTime = moving
          ..totalMovingTime = moving
          ..totalDistance = trip.distance
          ..totalAscent = elevation.ascent
          ..totalDescent = elevation.descent
          ..firstLapIndex = 0
          ..numLaps = 1
          ..sport = _sportFor(trip.detectedActivity)
          ..subSport = SubSport.generic
          ..event = Event.session
          ..eventType = EventType.stop
          ..avgSpeed = _msFromKmh(trip.avgSpeed)
          ..maxSpeed = _msFromKmh(trip.maxSpeed)
          ..startPositionLat = _semicircles(points.firstOrNull?.latitude)
          ..startPositionLong = _semicircles(points.firstOrNull?.longitude),
      );

      encoder.write(
        ActivityMesg()
          ..timestamp = end
          ..numSessions = 1
          // FIT's local_timestamp is wall-clock time with no zone attached; the
          // SDK writes whatever UTC instant it is given, so the offset has to be
          // folded in here.
          ..localTimestamp = end.toUtc().add(end.timeZoneOffset)
          ..totalTimerTime = moving
          ..type = Activity.manual
          ..event = Event.activity
          ..eventType = EventType.stop,
      );
    });
  }

  /// Suggested file name, e.g. `autoride-2026-09-01-0742.fit`.
  static String fileNameFor(Trip trip) {
    String two(int value) => value.toString().padLeft(2, '0');
    final t = trip.startTime;
    return 'autoride-${t.year}-${two(t.month)}-${two(t.day)}'
        '-${two(t.hour)}${two(t.minute)}.fit';
  }

  static RecordMesg _record(RoutePoint point, double distance) {
    final record = RecordMesg()
      ..timestamp = point.timestamp
      ..distance = distance;

    record.positionLat = _semicircles(point.latitude);
    record.positionLong = _semicircles(point.longitude);

    final altitude = point.altitude;
    if (altitude != null) {
      // enhanced_altitude carries the full uint32 range; `altitude` is a
      // uint16 that clips below -500 m and above ~9000 m.
      record.enhancedAltitude = altitude;
    }

    final speed = point.speed;
    if (speed != null) {
      record.enhancedSpeed = speed;
    }

    final accuracy = point.accuracy;
    if (accuracy != null) {
      record.gpsAccuracy = accuracy.round().clamp(0, 254);
    }

    return record;
  }

  /// Degrees to semicircles, or null when there is no coordinate to convert.
  static int? _semicircles(double? degrees) {
    if (degrees == null) return null;
    return (degrees * _semicirclesPerDegree).round();
  }

  /// km/h to m/s, FIT's speed unit.
  static double? _msFromKmh(double? kmh) => kmh == null ? null : kmh / 3.6;

  /// Total climb and descent, ignoring wander below [_elevationThresholdMeters].
  static ({int ascent, int descent}) _elevation(List<RoutePoint> points) {
    var ascent = 0.0;
    var descent = 0.0;
    double? reference;

    for (final point in points) {
      final altitude = point.altitude;
      if (altitude == null) continue;
      if (reference == null) {
        reference = altitude;
        continue;
      }
      final delta = altitude - reference;
      if (delta.abs() < _elevationThresholdMeters) continue;
      if (delta > 0) {
        ascent += delta;
      } else {
        descent -= delta;
      }
      reference = altitude;
    }

    return (ascent: ascent.round(), descent: descent.round());
  }

  /// Map the detected activity onto a FIT sport.
  ///
  /// [ActivityType.stationary] and [ActivityType.unknown] have no sport of
  /// their own; `generic` is FIT's "some activity" and is what readers fall
  /// back to anyway.
  static Sport _sportFor(ActivityType activity) => switch (activity) {
    ActivityType.cycling => Sport.cycling,
    ActivityType.running => Sport.running,
    ActivityType.walking => Sport.walking,
    ActivityType.driving => Sport.driving,
    ActivityType.stationary || ActivityType.unknown => Sport.generic,
  };
}
