import 'package:flutter_test/flutter_test.dart';

import 'package:autoride/core/constants/app_constants.dart';
import 'package:autoride/features/trip_detection/data/services/pre_trip_location_buffer.dart';
import 'package:autoride/features/trip_detection/domain/models/location_data.dart';

final _t0 = DateTime(2026, 1, 1, 8);

LocationData _fix({required double speedKmh, int index = 0}) {
  return LocationData(
    latitude: 48.8566 + index * 0.0002,
    longitude: 2.3522,
    accuracy: 5.0,
    altitude: 35.0,
    speed: speedKmh / 3.6,
    heading: 90.0,
    timestamp: _t0.add(Duration(seconds: index)),
  );
}

void main() {
  group('PreTripLocationBuffer.ridingTailOf', () {
    test('drops the walk and keeps the tail from the first cycling fix', () {
      final walk = [
        _fix(speedKmh: 0.0, index: 0),
        _fix(speedKmh: 4.5, index: 1),
        _fix(speedKmh: 5.0, index: 2),
      ];
      final ride = [
        _fix(speedKmh: 9.0, index: 3),
        _fix(speedKmh: 18.0, index: 4),
        _fix(speedKmh: 22.0, index: 5),
      ];

      final tail = PreTripLocationBuffer.ridingTailOf([...walk, ...ride]);

      expect(tail, equals(ride));
    });

    test('keeps a slow fix that comes AFTER the ride has started', () {
      // A junction or a red light seconds after setting off is part of the
      // ride: cutting it out would leave a hole in the route.
      final fixes = [
        _fix(speedKmh: 3.0, index: 0),
        _fix(speedKmh: 12.0, index: 1),
        _fix(speedKmh: 1.0, index: 2),
        _fix(speedKmh: 16.0, index: 3),
      ];

      final tail = PreTripLocationBuffer.ridingTailOf(fixes);

      expect(tail, equals(fixes.sublist(1)));
    });

    test('returns nothing when no fix reached cycling speed', () {
      final tail = PreTripLocationBuffer.ridingTailOf([
        _fix(speedKmh: 0.0, index: 0),
        _fix(speedKmh: 3.0, index: 1),
        _fix(speedKmh: AppConstants.cyclingSpeedMin - 0.1, index: 2),
      ]);

      expect(tail, isEmpty);
    });

    test('a fix exactly at cyclingSpeedMin opens the tail', () {
      final threshold = _fix(speedKmh: AppConstants.cyclingSpeedMin, index: 1);

      final tail = PreTripLocationBuffer.ridingTailOf([
        _fix(speedKmh: 2.0, index: 0),
        threshold,
      ]);

      expect(tail, equals([threshold]));
    });

    test('an empty buffer prefixes nothing', () {
      expect(PreTripLocationBuffer.ridingTailOf(const []), isEmpty);
    });
  });

  group('PreTripLocationBuffer bounds', () {
    test('drops fixes older than preTripLocationBufferDuration', () {
      final buffer = PreTripLocationBuffer();

      buffer.add(_fix(speedKmh: 20.0, index: 0), _t0);
      buffer.add(
        _fix(speedKmh: 20.0, index: 1),
        _t0.add(const Duration(seconds: 10)),
      );
      expect(buffer.length, 2);

      // Ages both of the above out (they were received at t0 and t0+10s).
      final late = _t0
          .add(AppConstants.preTripLocationBufferDuration)
          .add(const Duration(seconds: 11));
      buffer.add(_fix(speedKmh: 20.0, index: 2), late);

      expect(buffer.length, 1);
      expect(
        buffer.locations.single.timestamp,
        _t0.add(const Duration(seconds: 2)),
      );
    });

    test('keeps a fix exactly on the age boundary', () {
      final buffer = PreTripLocationBuffer();

      buffer.add(_fix(speedKmh: 20.0, index: 0), _t0);
      buffer.add(
        _fix(speedKmh: 20.0, index: 1),
        _t0.add(AppConstants.preTripLocationBufferDuration),
      );

      expect(buffer.length, 2);
    });

    test('caps the point count even with a clock that never advances', () {
      final buffer = PreTripLocationBuffer();
      const total = AppConstants.preTripLocationBufferMaxPoints + 20;

      for (var i = 0; i < total; i++) {
        buffer.add(_fix(speedKmh: 20.0, index: i), _t0);
      }

      expect(buffer.length, AppConstants.preTripLocationBufferMaxPoints);
      // The OLDEST are the ones dropped: the newest fix is still there.
      expect(
        buffer.locations.last.timestamp,
        _t0.add(
          const Duration(
            seconds: AppConstants.preTripLocationBufferMaxPoints + 19,
          ),
        ),
      );
    });

    test('clear() empties it', () {
      final buffer = PreTripLocationBuffer();
      buffer.add(_fix(speedKmh: 20.0), _t0);

      buffer.clear();

      expect(buffer.isEmpty, isTrue);
      expect(buffer.ridingTail, isEmpty);
    });

    test('ridingTail applies the écrémage to the retained fixes', () {
      final buffer = PreTripLocationBuffer();
      buffer.add(_fix(speedKmh: 2.0, index: 0), _t0);
      buffer.add(_fix(speedKmh: 4.0, index: 1), _t0);
      buffer.add(_fix(speedKmh: 15.0, index: 2), _t0);
      buffer.add(_fix(speedKmh: 17.0, index: 3), _t0);

      expect(buffer.ridingTail.map((f) => f.speedKmh), [
        closeTo(15.0, 0.001),
        closeTo(17.0, 0.001),
      ]);
    });
  });
}
