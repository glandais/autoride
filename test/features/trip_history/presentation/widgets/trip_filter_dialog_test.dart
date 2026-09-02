import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:autoride/features/trip_detection/domain/models/activity_confidence.dart';
import 'package:autoride/features/trip_history/domain/models/trip_filter.dart';
import 'package:autoride/features/trip_history/presentation/widgets/trip_filter_dialog.dart';

void main() {
  testWidgets('Apply returns the selected criteria', (tester) async {
    TripFilter? applied;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () async {
                applied = await showTripFilterDialog(
                  context,
                  current: const TripFilter(),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ChoiceChip, 'Last 7 days'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Cycling'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Apply'));
    await tester.pumpAndSettle();

    expect(
      applied,
      const TripFilter(
        activity: ActivityType.cycling,
        confirmedOnly: true,
        dateRange: TripDateRange.thisWeek,
      ),
    );
  });

  // Dismissing must leave the caller's filter alone, which is why a cancel
  // returns null rather than an empty filter.
  testWidgets('Cancel returns null, not an empty filter', (tester) async {
    const initial = TripFilter(activity: ActivityType.cycling);
    TripFilter? applied = initial;
    var closed = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () async {
                applied = await showTripFilterDialog(context, current: initial);
                closed = true;
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(closed, isTrue);
    expect(applied, isNull);
  });

  testWidgets('Clear returns the empty filter', (tester) async {
    TripFilter? applied;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () async {
                applied = await showTripFilterDialog(
                  context,
                  current: const TripFilter(
                    activity: ActivityType.driving,
                    confirmedOnly: true,
                    dateRange: TripDateRange.today,
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Clear'));
    await tester.pumpAndSettle();

    expect(applied, const TripFilter());
    expect(applied!.isActive, isFalse);
  });

  testWidgets('the dialog opens on the current filter', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: TripFilterDialog(
          initialFilter: TripFilter(
            activity: ActivityType.walking,
            dateRange: TripDateRange.today,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    ChoiceChip chip(String label) =>
        tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, label));

    expect(chip('Walking').selected, isTrue);
    expect(chip('Cycling').selected, isFalse);
    expect(chip('Today').selected, isTrue);
    expect(chip('All time').selected, isFalse);
  });

  // `copyWith` cannot write a null back, so resetting the activity goes
  // through a fresh value — and must not drag the other criteria back to
  // their defaults on the way.
  testWidgets('picking "All" clears the activity and keeps the rest', (
    tester,
  ) async {
    TripFilter? applied;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () async {
                applied = await showTripFilterDialog(
                  context,
                  current: const TripFilter(
                    activity: ActivityType.driving,
                    confirmedOnly: true,
                    dateRange: TripDateRange.today,
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'All'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Apply'));
    await tester.pumpAndSettle();

    expect(
      applied,
      const TripFilter(confirmedOnly: true, dateRange: TripDateRange.today),
    );
  });

  // A stationary "trip" is not something the recorder ever writes; offering it
  // would be a filter that always returns nothing.
  testWidgets('stationary is not offered as a filter', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: TripFilterDialog(initialFilter: TripFilter())),
    );
    await tester.pumpAndSettle();

    expect(find.widgetWithText(ChoiceChip, 'Stationary'), findsNothing);
    expect(find.widgetWithText(ChoiceChip, 'Cycling'), findsOneWidget);
  });
}
