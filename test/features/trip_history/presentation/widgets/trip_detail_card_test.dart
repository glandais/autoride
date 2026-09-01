import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:autoride/features/trip_detection/domain/models/activity_confidence.dart';
import 'package:autoride/features/trip_detection/domain/models/trip.dart';
import 'package:autoride/features/trip_history/presentation/widgets/trip_detail_card.dart';

/// The stopped time is only worth a tile when there is one: rides recorded
/// before schema v3 (L-073) carry `pauseDuration == 0`, and so does a ride
/// that never stopped.
void main() {
  Trip tripWith({int duration = 2700, int pauseDuration = 0}) => Trip(
    id: 1,
    startTime: DateTime(2026, 9, 1, 8),
    endTime: DateTime(
      2026,
      9,
      1,
      8,
    ).add(Duration(seconds: duration + pauseDuration)),
    distance: 12000.0,
    duration: duration,
    pauseDuration: pauseDuration,
    detectedActivity: ActivityType.cycling,
    confidenceScore: 0.9,
    avgSpeed: 16.0,
    maxSpeed: 31.0,
  );

  Future<void> pumpCard(WidgetTester tester, Trip trip) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: TripDetailCard(trip: trip)),
        ),
      ),
    );
  }

  testWidgets('a ride without stops shows neither Stopped nor Total', (
    tester,
  ) async {
    await pumpCard(tester, tripWith());

    expect(find.text('Duration'), findsOneWidget);
    expect(find.text('45m 0s'), findsOneWidget);
    expect(find.text('Stopped'), findsNothing);
    expect(find.text('Total'), findsNothing);
    expect(find.text('Moving'), findsNothing);
  });

  testWidgets('a ride with stops shows Moving, Stopped and Total', (
    tester,
  ) async {
    await pumpCard(tester, tripWith(duration: 2700, pauseDuration: 480));

    // The headline duration keeps its value and gains an unambiguous label.
    expect(find.text('Duration'), findsNothing);
    expect(find.text('Moving'), findsOneWidget);
    expect(find.text('45m 0s'), findsOneWidget);

    expect(find.text('Stopped'), findsOneWidget);
    expect(find.text('8m 0s'), findsOneWidget);

    expect(find.text('Total'), findsOneWidget);
    expect(find.text('53m 0s'), findsOneWidget);
  });
}
