import 'package:flutter_test/flutter_test.dart';

import 'package:autoride/core/constants/app_constants.dart';
import 'package:autoride/features/trip_detection/data/services/vehicle_speed_watch.dart';
import 'package:autoride/features/trip_detection/domain/models/location_data.dart';

final _t0 = DateTime(2026, 9, 7, 12, 45);

LocationData _fix({
  required double speedKmh,
  required int atSeconds,
  double accuracy = 3.5,
}) {
  return LocationData(
    latitude: 48.8566,
    longitude: 2.3522,
    accuracy: accuracy,
    altitude: 35.0,
    speed: speedKmh / 3.6,
    heading: 90.0,
    timestamp: _t0.add(Duration(seconds: atSeconds)),
  );
}

/// Feed a `(speed, second)` trace and report whether the live arm ever fired.
bool _replay(VehicleSpeedWatch watch, List<List<double>> trace) {
  for (final point in trace) {
    watch.add(_fix(speedKmh: point[0], atSeconds: point[1].round()));
  }
  return watch.hasFired;
}

void main() {
  group('VehicleSpeedWatch — the real traces', () {
    // The two recordings of `autoride-audit-20260907-1337.ndjson.gz`, reduced
    // to the fixes that carry a *measured* speed the app is allowed to believe.
    // These are the whole evidence base for the thresholds, so they are pinned
    // here rather than paraphrased: if a threshold moves, this is what says
    // which of the two rides moved with it.

    /// The 2026-09-06 night ride: 3.5 km at 16.8 km/h. Eleven measured speeds,
    /// the fastest 31.6 km/h. (Its readings *above* 40 km/h are all derived
    /// ones from fixes accurate to 23-38 m, which is exactly why derived speeds
    /// are not evidence here.)
    const bikeRide = <double>[
      22.4,
      22.3,
      26.0,
      26.2,
      22.9,
      22.9,
      25.5,
      28.8,
      31.6,
      25.6,
      0.8,
    ];

    /// The 2026-09-07 drive to the shops, as `[speed, second]` — the seconds
    /// matter, because the live arm needs its evidence to span real time.
    const carTrip = <List<double>>[
      [25.1, 255],
      [25.1, 256],
      [30.7, 260],
      [29.1, 281],
      [32.1, 283],
      [34.8, 284],
      [31.7, 285],
      [32.6, 287],
      [32.8, 289],
      [38.0, 333],
      [38.0, 335],
      [37.9, 337],
      [39.3, 339],
      [39.2, 341],
      [5.8, 383],
      [3.1, 441],
      [3.4, 1369],
      [10.3, 1406],
      [32.7, 1458],
      [25.7, 1501],
      [29.4, 1503],
      [32.3, 1505],
      [31.5, 1507],
      [21.6, 1520],
      [27.8, 1523],
      [37.4, 1525],
      [37.4, 1527],
      [37.7, 1529],
      [37.3, 1531],
      [36.9, 1533],
      [34.4, 1535],
      [34.0, 1537],
      [34.2, 1539],
      [34.2, 1541],
      [31.9, 1543],
      [31.1, 1545],
      [24.1, 1548],
    ];

    test('the drive to the shops is refused at the end, not live', () {
      final watch = VehicleSpeedWatch();

      // T052, L-102: the live arm no longer answers at town speeds. This drive
      // peaks at 39.3 km/h, and so does a bicycle descent — see the group
      // below. Nothing here is fast enough for the live threshold.
      expect(_replay(watch, carTrip), isFalse);

      // The end-of-ride arm still refuses it, and on its own evidence: ten of
      // the thirty-seven measured fixes are at or above 35 km/h — 27.0 %, over
      // the quarter it needs.
      expect(watch.looksLikeVehicle, isTrue);
      expect(watch.measuredFixes, 37);
      expect(watch.vehicleFixes, 10);
    });

    test(
      'the live arm answers on a road, at four fixes over its own threshold',
      () {
        final watch = VehicleSpeedWatch();

        // Three fast fixes: not yet.
        expect(_replay(watch, motorwaySample.sublist(0, 3)), isFalse);

        // The fourth closes a six-second span above `vehicleLiveSpeedKmh`.
        watch.add(_fix(speedKmh: 54.0, atSeconds: 6));
        expect(watch.hasFired, isTrue);
        expect(watch.looksLikeVehicle, isTrue);
      },
    );

    /// The 2026-09-09 morning commute, as `[speed, second]` — the descent that
    /// L-102 is about, taken from `autoride-audit-20260909-1802.ndjson.gz`.
    /// Seconds are relative to the first of these fixes.
    ///
    /// Six measured fixes at or above 35 km/h spanning ten seconds, peaking at
    /// **39.9** — faster than the drive above, and held longer. This is the
    /// trace that proves peak speed and sustain cannot separate the two.
    const descent = <List<double>>[
      [30.1, 0],
      [30.1, 1],
      [28.2, 4],
      [31.5, 7],
      [35.6, 9],
      [37.6, 11],
      [39.1, 13],
      [39.1, 15],
      [39.5, 17],
      [39.9, 19],
      [34.5, 21],
      [28.0, 24],
      [19.3, 27],
    ];

    test('the descent does not end the ride (T052, L-102)', () {
      final watch = VehicleSpeedWatch();

      // Under 1.0.0+14 this fired at the fourth fix above 35 and deleted
      // 1 561 m of a real commute.
      expect(_replay(watch, descent), isFalse);
    });

    test('the commute that contained it is not a vehicle either', () {
      final watch = VehicleSpeedWatch();

      // The descent, then the rest of the ride — 42 measured fixes in all, of
      // which 6 are at or above 35 km/h. 14.3 %, under the quarter the
      // end-of-ride arm needs, against the drive's 27.0 %.
      //
      // The share is the whole point: read on the truncated recording the veto
      // itself produced (4 of 11) it is 36 %, and the ride looks like a car
      // *because* it was cut short.
      _replay(watch, descent);
      for (var i = 0; i < 29; i++) {
        watch.add(_fix(speedKmh: 18.0 + (i % 7), atSeconds: 40 + i * 30));
      }

      expect(watch.hasFired, isFalse);
      expect(watch.measuredFixes, 42);
      expect(watch.vehicleFixes, 6);
      expect(
        watch.vehicleFixes / watch.measuredFixes,
        lessThan(AppConstants.vehicleSpeedMinShare),
      );
      expect(watch.looksLikeVehicle, isFalse);
    });

    test('the night ride does not', () {
      final watch = VehicleSpeedWatch();

      for (var i = 0; i < bikeRide.length; i++) {
        watch.add(_fix(speedKmh: bikeRide[i], atSeconds: i * 10));
      }

      expect(watch.hasFired, isFalse);
      expect(watch.looksLikeVehicle, isFalse);
      expect(watch.measuredFixes, bikeRide.length);
      expect(watch.vehicleFixes, 0);
    });
  });

  group('VehicleSpeedWatch — what counts as evidence', () {
    test('a fix with no measured speed is not evidence either way', () {
      // iOS reports exactly 0 on fixes taken at 20 km/h (L-098). Counting those
      // as slow would let a drive through every rule that reads a share.
      final watch = VehicleSpeedWatch();

      for (var i = 0; i < 20; i++) {
        watch.add(_fix(speedKmh: 0.0, atSeconds: i * 5));
      }

      expect(watch.measuredFixes, 0);
      expect(watch.looksLikeVehicle, isFalse);
    });

    test('a coarse fix is not evidence, however fast it claims to be', () {
      final watch = VehicleSpeedWatch();

      for (var i = 0; i < 10; i++) {
        watch.add(
          _fix(
            speedKmh: 90.0,
            atSeconds: i * 5,
            accuracy: AppConstants.speedTrustMaxAccuracyMeters + 1,
          ),
        );
      }

      expect(watch.measuredFixes, 0);
      expect(watch.hasFired, isFalse);
    });

    test('a burst of fast fixes inside a second does not fire it', () {
      // The count alone would be satisfied by four fixes 200 ms apart, which is
      // one GPS hiccup rather than a road.
      final watch = VehicleSpeedWatch();

      for (var i = 0; i < AppConstants.vehicleSpeedWindowFixes; i++) {
        final at = _t0.add(Duration(milliseconds: i * 200));
        watch.add(
          LocationData(
            latitude: 48.8566,
            longitude: 2.3522,
            accuracy: 3.5,
            altitude: 35.0,
            speed: 50.0 / 3.6,
            heading: 90.0,
            timestamp: at,
          ),
        );
      }

      expect(watch.hasFired, isFalse);
      // …and the same six fixes spread over the sustain window do fire it.
      expect(
        watch.looksLikeVehicle,
        isTrue,
        reason: 'the share arm still sees them',
      );
    });

    test('one artefact in a long ride is not a vehicle', () {
      final watch = VehicleSpeedWatch();

      for (var i = 0; i < 60; i++) {
        final speed = i == 30 ? 55.0 : 22.0;
        watch.add(_fix(speedKmh: speed, atSeconds: i * 10));
      }

      expect(watch.hasFired, isFalse);
      expect(watch.looksLikeVehicle, isFalse);
    });

    test('reset forgets the recording', () {
      final watch = VehicleSpeedWatch();
      _replay(watch, motorwaySample);
      expect(watch.hasFired, isTrue);

      watch.reset();

      expect(watch.hasFired, isFalse);
      expect(watch.looksLikeVehicle, isFalse);
      expect(watch.measuredFixes, 0);
      expect(watch.vehicleFixes, 0);
    });
  });
}

/// Four fixes above `vehicleLiveSpeedKmh`, spanning more than the sustain
/// window — the shortest trace that fires the live arm since T052.
///
/// Deliberately not the drive's own 38-39.3 km/h burst: those are *town* car
/// speeds, and a bicycle descent reaches 39.9 (L-102). The live arm's job is
/// the road, where nothing on two wheels follows.
const motorwaySample = <List<double>>[
  [52.0, 0],
  [51.0, 2],
  [55.0, 4],
  [54.0, 6],
];
