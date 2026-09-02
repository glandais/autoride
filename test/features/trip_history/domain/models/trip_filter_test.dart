import 'package:flutter_test/flutter_test.dart';

import 'package:autoride/features/trip_detection/domain/models/activity_confidence.dart';
import 'package:autoride/features/trip_detection/domain/models/trip.dart';
import 'package:autoride/features/trip_history/domain/models/trip_filter.dart';

Trip _trip({
  ActivityType activity = ActivityType.cycling,
  bool confirmed = false,
}) {
  final start = DateTime(2026, 9, 2, 8);
  return Trip(
    id: 1,
    startTime: start,
    endTime: start.add(const Duration(minutes: 20)),
    distance: 4200,
    duration: 1200,
    detectedActivity: activity,
    confidenceScore: 0.9,
    userConfirmed: confirmed,
  );
}

void main() {
  group('TripFilter - active state', () {
    test('the default filter shows everything', () {
      const filter = TripFilter();

      expect(filter.isActive, isFalse);
      expect(filter.activeCriteriaCount, 0);
    });

    test('each criterion counts once', () {
      const filter = TripFilter(
        activity: ActivityType.cycling,
        confirmedOnly: true,
        dateRange: TripDateRange.thisWeek,
      );

      expect(filter.isActive, isTrue);
      expect(filter.activeCriteriaCount, 3);
    });
  });

  group('TripFilter - date boundary', () {
    // Boundaries are taken off midnight, not off `now`: a ride recorded this
    // morning must not drop out of "Today" as the day goes on.
    final now = DateTime(2026, 9, 2, 14, 30);

    test('"all time" has no boundary', () {
      expect(const TripFilter().startBoundary(now), isNull);
    });

    test('"today" starts at midnight', () {
      const filter = TripFilter(dateRange: TripDateRange.today);

      expect(filter.startBoundary(now), DateTime(2026, 9, 2));
    });

    test('the rolling windows count back from midnight', () {
      expect(
        const TripFilter(dateRange: TripDateRange.thisWeek).startBoundary(now),
        DateTime(2026, 8, 26),
      );
      expect(
        const TripFilter(dateRange: TripDateRange.thisMonth).startBoundary(now),
        DateTime(2026, 8, 3),
      );
    });
  });

  group('TripFilter - matching', () {
    test('the default filter matches every trip', () {
      expect(const TripFilter().matches(_trip()), isTrue);
      expect(
        const TripFilter().matches(_trip(activity: ActivityType.walking)),
        isTrue,
      );
    });

    test('an activity filter rejects the other activities', () {
      const filter = TripFilter(activity: ActivityType.cycling);

      expect(filter.matches(_trip()), isTrue);
      expect(filter.matches(_trip(activity: ActivityType.driving)), isFalse);
    });

    test('"confirmed only" rejects unconfirmed trips', () {
      const filter = TripFilter(confirmedOnly: true);

      expect(filter.matches(_trip(confirmed: true)), isTrue);
      expect(filter.matches(_trip()), isFalse);
    });

    // The two criteria compose, which the repository's single-criterion
    // queries could not do.
    test('criteria are combined, not alternatives', () {
      const filter = TripFilter(
        activity: ActivityType.cycling,
        confirmedOnly: true,
      );

      expect(filter.matches(_trip(confirmed: true)), isTrue);
      expect(filter.matches(_trip()), isFalse);
      expect(
        filter.matches(_trip(activity: ActivityType.walking, confirmed: true)),
        isFalse,
      );
    });
  });
}
