import 'package:flutter_test/flutter_test.dart';

import 'package:autoride/core/constants/app_constants.dart';
import 'package:autoride/features/trip_detection/data/services/battery_optimizer.dart';
import 'package:autoride/features/trip_detection/data/services/gps_speed_estimator.dart';
import 'package:autoride/features/trip_detection/domain/models/location_data.dart';

final _t0 = DateTime(2026, 9, 3, 17, 19);

/// One degree of latitude ≈ 111 320 m, which is what turns the metre distances
/// below into coordinates without hard-coding a second geodesy.
const _metresPerDegreeLat = 111320.0;

LocationData _fix({
  required int atSeconds,
  double northMetres = 0.0,
  double speed = 0.0,
  double accuracy = 10.0,
}) {
  return LocationData(
    latitude: 47.2185 + northMetres / _metresPerDegreeLat,
    longitude: -1.5977,
    accuracy: accuracy,
    altitude: 35.0,
    speed: speed,
    heading: 0.0,
    timestamp: _t0.add(Duration(seconds: atSeconds)),
  );
}

/// The gap bound is per power mode; every test but the two about the bound
/// itself runs in `normal`, the mode a phone above 50 % battery is in.
extension _RefineInNormalMode on GpsSpeedEstimator {
  LocationData refineNormal(LocationData fix) =>
      refine(fix, maxGap: PowerModeConfig.normal.derivedSpeedMaxGap);
}

void main() {
  group('GpsSpeedEstimator', () {
    test('derives the speed iOS omitted, from the displacement (L-087)', () {
      // The 2026-09-03 iPhone, verbatim: 61 m in 7 s on two accurate fixes,
      // both reporting `sp` 0, three minutes before the trip started.
      final estimator = GpsSpeedEstimator();

      estimator.refineNormal(_fix(atSeconds: 0));
      final refined = estimator.refineNormal(
        _fix(atSeconds: 7, northMetres: 61),
      );

      expect(refined.speedKmh, closeTo(31.4, 0.5));
      expect(
        refined.speedKmh,
        greaterThanOrEqualTo(AppConstants.cyclingSpeedMin),
        reason: 'this is the fix the riding-tail cut has to find',
      );
    });

    test('leaves a provider-reported speed alone', () {
      final estimator = GpsSpeedEstimator();

      estimator.refineNormal(_fix(atSeconds: 0));
      final refined = estimator.refineNormal(
        _fix(atSeconds: 7, northMetres: 61, speed: 5.0),
      );

      expect(refined.speed, 5.0);
    });

    test('derives nothing from the first fix of a run', () {
      final estimator = GpsSpeedEstimator();

      expect(
        estimator.refineNormal(_fix(atSeconds: 0, northMetres: 61)).speed,
        0.0,
      );
    });

    test('derives nothing from coarse fixes (L-088)', () {
      // The Pixel's cell/wifi ladder: 300 m fixes whose positions walk
      // backwards along the road. Subtracting two of them measures nothing.
      final estimator = GpsSpeedEstimator();

      estimator.refineNormal(_fix(atSeconds: 0, accuracy: 300.0));
      final refined = estimator.refineNormal(
        _fix(atSeconds: 31, northMetres: 160, accuracy: 300.0),
      );

      expect(refined.speed, 0.0);
    });

    test('derives nothing when the move stays inside the fix noise', () {
      // 8 m apart on 10 m fixes is a phone on a table, not a rider.
      final estimator = GpsSpeedEstimator();

      estimator.refineNormal(_fix(atSeconds: 0));
      final refined = estimator.refineNormal(
        _fix(atSeconds: 5, northMetres: 8),
      );

      expect(refined.speed, 0.0);
    });

    test('derives nothing across a gap too short to mean anything', () {
      final estimator = GpsSpeedEstimator();

      estimator.refineNormal(_fix(atSeconds: 0));
      final refined = estimator.refineNormal(
        _fix(atSeconds: 0, northMetres: 61),
      );

      expect(refined.speed, 0.0);
    });

    test('derives nothing across a gap longer than the bound', () {
      final estimator = GpsSpeedEstimator();
      final bound = PowerModeConfig.normal.derivedSpeedMaxGap;

      estimator.refineNormal(_fix(atSeconds: 0));
      final refined = estimator.refineNormal(
        _fix(atSeconds: bound.inSeconds + 1, northMetres: 200),
      );

      expect(refined.speed, 0.0);
    });

    test('the bound clears the update interval the mode itself asks for', () {
      // The regression this exists for: T048 first shipped a fixed 30 s
      // bound against a `locationUpdateNormal` of exactly 30 s, and the
      // 2026-09-03 Pixel — whose fixes land 30.7 s apart because
      // `intervalDuration` is a request served with jitter — derived a speed
      // 0 times across two rides. 14 pairs accurate to 14–43 m were refused
      // for 0.7 s.
      for (final mode in [
        PowerModeConfig.normal,
        PowerModeConfig.medium,
        PowerModeConfig.low,
        PowerModeConfig.critical,
      ]) {
        expect(
          mode.derivedSpeedMaxGap,
          greaterThan(mode.locationUpdateInterval),
          reason:
              'a bound at or below ${mode.name}\'s own update interval can '
              'never fire',
        );
      }

      final estimator = GpsSpeedEstimator();
      estimator.refine(
        _fix(atSeconds: 0),
        maxGap: PowerModeConfig.normal.derivedSpeedMaxGap,
      );
      // 187 m in 31 s = 21.7 km/h — the 2026-09-03 Pixel morning ride,
      // verbatim.
      final refined = estimator.refine(
        _fix(atSeconds: 31, northMetres: 187, accuracy: 32.0),
        maxGap: PowerModeConfig.normal.derivedSpeedMaxGap,
      );

      expect(refined.speedKmh, closeTo(21.7, 0.5));
      expect(
        refined.speedKmh,
        greaterThanOrEqualTo(AppConstants.cyclingSpeedMin),
      );
    });

    test('rejects an implausible quotient rather than reporting it', () {
      // 61 m in 1 s = 220 km/h: the positions were wrong, the rider was not
      // fast. Answering "no speed" is the honest reading.
      final estimator = GpsSpeedEstimator();

      estimator.refineNormal(_fix(atSeconds: 0));
      final refined = estimator.refineNormal(
        _fix(atSeconds: 1, northMetres: 61),
      );

      expect(refined.speed, 0.0);
    });

    test('reset forgets the position history', () {
      final estimator = GpsSpeedEstimator();

      estimator.refineNormal(_fix(atSeconds: 0));
      estimator.reset();
      final refined = estimator.refineNormal(
        _fix(atSeconds: 7, northMetres: 61),
      );

      expect(refined.speed, 0.0);
    });

    test('chains: every fix anchors the next one', () {
      final estimator = GpsSpeedEstimator();

      estimator.refineNormal(_fix(atSeconds: 0));
      estimator.refineNormal(_fix(atSeconds: 5, northMetres: 30));
      final third = estimator.refineNormal(
        _fix(atSeconds: 10, northMetres: 60),
      );

      // 30 m in 5 s = 21.6 km/h, measured against the *second* fix and not the
      // first — a stale anchor would read 60 m in 10 s and happen to agree, so
      // this only bites when the pace changes.
      expect(third.speedKmh, closeTo(21.6, 0.5));
    });
  });

  group('LocationData.speedIsTrustworthyAt', () {
    test('trusts an accurate, fresh fix', () {
      final fix = _fix(atSeconds: 0);

      expect(
        fix.speedIsTrustworthyAt(_t0.add(const Duration(seconds: 2))),
        isTrue,
      );
    });

    test('refuses a fix coarser than the speed can justify (L-088)', () {
      final fix = _fix(
        atSeconds: 0,
        accuracy: AppConstants.speedTrustMaxAccuracyMeters + 1,
      );

      expect(fix.speedIsTrustworthyAt(_t0), isFalse);
    });

    test('refuses a fix older than the freshness bound (L-089)', () {
      final fix = _fix(atSeconds: 0);
      final now = _t0
          .add(AppConstants.speedTrustMaxAge)
          .add(const Duration(seconds: 1));

      expect(fix.speedIsTrustworthyAt(now), isFalse);
    });

    test('measures age either way round, so a skewed clock cannot pass', () {
      final fix = _fix(atSeconds: 60);

      expect(fix.speedIsTrustworthyAt(_t0), isFalse);
    });
  });
}
