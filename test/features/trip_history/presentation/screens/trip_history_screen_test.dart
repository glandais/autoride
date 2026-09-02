import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:autoride/features/trip_detection/domain/models/activity_confidence.dart';
import 'package:autoride/features/trip_detection/domain/models/trip.dart';
import 'package:autoride/features/trip_history/domain/models/trip_filter.dart';
import 'package:autoride/features/trip_history/presentation/providers/trip_filter_provider.dart';
import 'package:autoride/features/trip_history/presentation/providers/trip_history_provider.dart';
import 'package:autoride/features/trip_history/presentation/screens/trip_history_screen.dart';
import 'package:autoride/shared/widgets/empty_state.dart';

Trip _trip({
  required int id,
  ActivityType activity = ActivityType.cycling,
  bool confirmed = false,
}) {
  final start = DateTime.now().subtract(Duration(hours: id));
  return Trip(
    id: id,
    startTime: start,
    endTime: start.add(const Duration(minutes: 20)),
    distance: 4200,
    duration: 1200,
    detectedActivity: activity,
    confidenceScore: 0.9,
    userConfirmed: confirmed,
  );
}

/// Stands in for the repository-backed list: holds trips in memory and applies
/// the same filter the real notifier does, so the screen's own wiring — badge,
/// dialog, empty state — is what the test exercises.
class _FakeTripHistory extends TripHistory {
  _FakeTripHistory(this.all);

  final List<Trip> all;

  @override
  Future<List<Trip>> build() async {
    final filter = ref.watch(tripFilterControllerProvider);
    return all.where(filter.matches).toList();
  }
}

void main() {
  Future<void> pumpScreen(WidgetTester tester, List<Trip> trips) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tripHistoryProvider.overrideWith(() => _FakeTripHistory(trips)),
        ],
        child: const MaterialApp(home: TripHistoryScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the filter button opens the dialog', (tester) async {
    await pumpScreen(tester, [_trip(id: 1)]);

    await tester.tap(find.byTooltip('Filter trips'));
    await tester.pumpAndSettle();

    expect(find.text('Filter Trips'), findsOneWidget);
  });

  testWidgets('applying a filter narrows the list and badges the button', (
    tester,
  ) async {
    await pumpScreen(tester, [
      _trip(id: 1),
      _trip(id: 2, activity: ActivityType.driving),
    ]);

    expect(find.byType(Card), findsNWidgets(2));
    expect(find.byType(Badge), findsOneWidget);
    expect(tester.widget<Badge>(find.byType(Badge)).isLabelVisible, isFalse);

    await tester.tap(find.byTooltip('Filter trips'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Cycling'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Apply'));
    await tester.pumpAndSettle();

    expect(find.byType(Card), findsOneWidget);
    expect(tester.widget<Badge>(find.byType(Badge)).isLabelVisible, isTrue);
    expect(find.text('1'), findsOneWidget);
  });

  // An empty filtered list is a different story from an app with no rides in
  // it, and offers a way out instead of an explanation.
  testWidgets('a filter that matches nothing offers a reset', (tester) async {
    await pumpScreen(tester, [_trip(id: 1)]);

    await tester.tap(find.byTooltip('Filter trips'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(SwitchListTile)); // confirmed only
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Apply'));
    await tester.pumpAndSettle();

    expect(find.text('No Matching Trips'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Clear filters'));
    await tester.pumpAndSettle();

    expect(find.byType(EmptyState), findsNothing);
    expect(find.byType(Card), findsOneWidget);
  });

  testWidgets('an unfiltered empty history keeps its own empty state', (
    tester,
  ) async {
    await pumpScreen(tester, []);

    expect(find.text('No Trips Yet'), findsOneWidget);
    expect(find.text('Clear filters'), findsNothing);
  });

  testWidgets('dismissing the dialog leaves the filter untouched', (
    tester,
  ) async {
    await pumpScreen(tester, [
      _trip(id: 1),
      _trip(id: 2, activity: ActivityType.driving),
    ]);

    await tester.tap(find.byTooltip('Filter trips'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Cycling'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(find.byType(Card), findsNWidgets(2));
    expect(tester.widget<Badge>(find.byType(Badge)).isLabelVisible, isFalse);
  });
}
