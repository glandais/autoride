import 'package:flutter_test/flutter_test.dart';
import 'package:fit_dart_sdk/fit_dart_sdk.dart' hide ActivityType;

import 'package:autoride/features/trip_detection/domain/models/activity_confidence.dart';
import 'package:autoride/features/trip_detection/domain/models/trip.dart';
import 'package:autoride/features/trip_export/data/services/fit_activity_encoder.dart';

/// Round-trip tests: encode a trip, decode the bytes back with the same SDK a
/// Garmin/Strava importer would use, and assert on what came out. That is the
/// only check that means anything here — a byte-level expectation would just
/// restate the encoder.
void main() {
  final start = DateTime.utc(2026, 3, 17, 8, 0, 0);

  /// A short ride climbing gently north-east out of central Nantes.
  Trip buildTrip({
    int pointCount = 60,
    ActivityType activity = ActivityType.cycling,
  }) {
    final points = List.generate(pointCount, (i) {
      return RoutePoint(
        tripId: 1,
        latitude: 47.2184 + i * 0.0001,
        longitude: -1.5536 + i * 0.0001,
        timestamp: start.add(Duration(seconds: i)),
        altitude: 20.0 + i,
        accuracy: 5.0,
        speed: 5.5,
      );
    });

    return Trip(
      id: 1,
      startTime: start,
      endTime: start.add(Duration(seconds: pointCount)),
      distance: 830.0,
      duration: pointCount,
      detectedActivity: activity,
      confidenceScore: 0.87,
      avgSpeed: 19.8,
      maxSpeed: 32.4,
      routePoints: points,
    );
  }

  group('FitActivityEncoder.encode', () {
    test('produces a structurally valid activity file', () {
      final bytes = FitActivityEncoder.encode(buildTrip());
      final decoder = FitDecoder(bytes);

      expect(decoder.isFit(), isTrue);
      expect(decoder.checkIntegrity(), isTrue);

      final result = decoder.decode();
      expect(result.errors, isEmpty);
      expect(result.messages.fileIdMesgs.single.type, FitFile.activity);
      expect(result.messages.sessionMesgs, hasLength(1));
      expect(result.messages.lapMesgs, hasLength(1));
      expect(result.messages.activityMesgs, hasLength(1));
      // A start and a stop timer event bracket the records.
      expect(result.messages.eventMesgs, hasLength(2));
    });

    test('writes one record per route point, in time order', () {
      final trip = buildTrip();
      final records = FitDecoder(FitActivityEncoder.encode(trip))
          .decode()
          .messages
          .recordMesgs;

      expect(records, hasLength(trip.routePoints.length));
      for (var i = 0; i < records.length; i++) {
        expect(records[i].timestamp, trip.routePoints[i].timestamp);
      }
    });

    test('round-trips coordinates through semicircles within a meter', () {
      final trip = buildTrip(pointCount: 3);
      final records = FitDecoder(FitActivityEncoder.encode(trip))
          .decode()
          .messages
          .recordMesgs;

      const degreesPerSemicircle = 180 / 2147483648;
      for (var i = 0; i < records.length; i++) {
        final point = trip.routePoints[i];
        expect(
          records[i].positionLat! * degreesPerSemicircle,
          closeTo(point.latitude, 0.00001),
        );
        expect(
          records[i].positionLong! * degreesPerSemicircle,
          closeTo(point.longitude, 0.00001),
        );
      }
    });

    test('carries altitude, speed and GPS accuracy per record', () {
      final records = FitDecoder(
        FitActivityEncoder.encode(buildTrip(pointCount: 2)),
      ).decode().messages.recordMesgs;

      expect(records.first.enhancedAltitude, closeTo(20.0, 0.2));
      expect(records.first.enhancedSpeed, closeTo(5.5, 0.01));
      expect(records.first.gpsAccuracy, 5);
    });

    test('accumulates distance monotonically from the first point', () {
      final records = FitDecoder(FitActivityEncoder.encode(buildTrip()))
          .decode()
          .messages
          .recordMesgs;

      expect(records.first.distance, 0.0);
      for (var i = 1; i < records.length; i++) {
        expect(records[i].distance!, greaterThan(records[i - 1].distance!));
      }
    });

    test('summarizes the session with the trip metrics', () {
      final trip = buildTrip();
      final session = FitDecoder(FitActivityEncoder.encode(trip))
          .decode()
          .messages
          .sessionMesgs
          .single;

      expect(session.sport, Sport.cycling);
      expect(session.startTime, trip.startTime);
      expect(session.totalDistance, closeTo(trip.distance, 0.01));
      expect(session.totalTimerTime, closeTo(trip.duration.toDouble(), 0.01));
      expect(session.totalElapsedTime, closeTo(60.0, 0.01));
      // Speeds are km/h in the model and m/s in FIT.
      expect(session.avgSpeed, closeTo(19.8 / 3.6, 0.01));
      expect(session.maxSpeed, closeTo(32.4 / 3.6, 0.01));
      expect(session.numLaps, 1);
    });

    test('reports the climb and ignores the descent on a monotonic ascent', () {
      // 60 points, +1 m each. The 3 m noise gate only banks a delta once it
      // clears the threshold, so the climb registers in 3 m steps (20 -> 77)
      // and the trailing 2 m stay unbanked: 57, not the raw 59.
      final session = FitDecoder(FitActivityEncoder.encode(buildTrip()))
          .decode()
          .messages
          .sessionMesgs
          .single;

      expect(session.totalAscent, 57);
      expect(session.totalDescent, 0);
    });

    test('maps the detected activity onto a FIT sport', () {
      Sport? sportOf(ActivityType activity) =>
          FitDecoder(FitActivityEncoder.encode(buildTrip(activity: activity)))
              .decode()
              .messages
              .sessionMesgs
              .single
              .sport;

      expect(sportOf(ActivityType.cycling), Sport.cycling);
      expect(sportOf(ActivityType.running), Sport.running);
      expect(sportOf(ActivityType.walking), Sport.walking);
      expect(sportOf(ActivityType.driving), Sport.driving);
      expect(sportOf(ActivityType.unknown), Sport.generic);
      expect(sportOf(ActivityType.stationary), Sport.generic);
    });

    test('still produces a valid file for a trip with no route points', () {
      final trip = buildTrip(
        pointCount: 0,
      ).copyWith(endTime: start.add(const Duration(minutes: 5)), duration: 300);
      final result = FitDecoder(FitActivityEncoder.encode(trip)).decode();

      expect(result.errors, isEmpty);
      expect(result.messages.recordMesgs, isEmpty);
      expect(
        result.messages.sessionMesgs.single.totalDistance,
        closeTo(830.0, 0.01),
      );
    });

    test('sorts route points that arrive out of order', () {
      final trip = buildTrip(pointCount: 3);
      final shuffled = trip.copyWith(
        routePoints: [
          trip.routePoints[2],
          trip.routePoints[0],
          trip.routePoints[1],
        ],
      );
      final records = FitDecoder(FitActivityEncoder.encode(shuffled))
          .decode()
          .messages
          .recordMesgs;

      expect(
        records.map((r) => r.timestamp),
        trip.routePoints.map((p) => p.timestamp),
      );
    });
  });

  group('FitActivityEncoder.fileNameFor', () {
    test('names the file after the trip start, zero-padded', () {
      expect(
        FitActivityEncoder.fileNameFor(buildTrip()),
        'autoride-2026-03-17-0800.fit',
      );
    });
  });
}
