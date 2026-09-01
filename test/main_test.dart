import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:autoride/features/trip_detection/data/services/location_service.dart';
import 'package:autoride/features/trip_detection/data/services/trip_state_machine.dart';
import 'package:autoride/features/trip_detection/domain/models/location_data.dart';
import 'package:autoride/features/trip_detection/domain/models/trip_state.dart';
import 'package:autoride/features/trip_detection/presentation/screens/trip_tracking_screen.dart';
import 'package:autoride/features/trip_history/presentation/screens/trip_history_screen.dart';
import 'package:autoride/main.dart';

import 'helpers/widget/fake_trip_providers.dart';
import 'helpers/widget/pump_app.dart';

// ===========================================================================
// HomeShell renders a single tab at a time (`_screens[_currentIndex]`), so a
// tab tap unmounts the tracking screen. T041 made a recording survive that by
// pinning the session for the duration of the trip; these tests assert that
// guarantee where the user meets it — at the widget layer — and that the Trip
// tab (permanently disabled before T041, L-001) is reachable in both states.
// ===========================================================================

void main() {
  late RecorderLog recorder;
  late AutoDetectionLog detection;

  setUp(() {
    recorder = RecorderLog();
    detection = AutoDetectionLog();
  });

  Future<ProviderContainer> pumpShell(
    WidgetTester tester, {
    TripState initialTripState = const TripState.idle(),
  }) async {
    await pumpAppWidget(
      tester,
      const HomeShell(),
      overrides: [
        ...tripSurfaceOverrides(
          recorder: recorder,
          detection: detection,
          initialTripState: initialTripState,
        ),
        locationStreamProvider
            .overrideWith((ref, settings) => const Stream<LocationData>.empty()),
        activeRoutePointsProvider.overrideWith((ref) async => []),
      ],
    );
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(tester.element(find.byType(HomeShell)));
  }

  Future<void> tapTab(WidgetTester tester, String label) async {
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  group('HomeShell - navigation', () {
    testWidgets('opens on history and can reach the Trip tab while idle',
        (tester) async {
      await pumpShell(tester);

      expect(find.byType(TripHistoryScreen), findsOneWidget);
      expect(find.text('Trip'), findsOneWidget);
      expect(find.text('Settings'), findsOneWidget);

      await tapTab(tester, 'Trip');

      expect(find.byType(TripTrackingScreen), findsOneWidget);
      expect(find.byKey(const Key('manual-start-trip-button')), findsOneWidget);
    });

    testWidgets('labels the Trip tab "Active Trip" while recording',
        (tester) async {
      await pumpShell(
        tester,
        initialTripState: TripState.active(tripId: 1, startTime: DateTime.now()),
      );

      // Once as the tab label, once as the tracking screen's own title after
      // the tab is opened.
      expect(find.text('Active Trip'), findsOneWidget);

      await tapTab(tester, 'Active Trip');

      expect(find.byType(TripTrackingScreen), findsOneWidget);
      expect(find.text('Pause Trip'), findsOneWidget);
    });
  });

  group('HomeShell - session survives tab switching (T041)', () {
    testWidgets('a running trip is still running after a tab round trip',
        (tester) async {
      final container = await pumpShell(tester);

      await tapTab(tester, 'Trip');
      await tester.tap(find.byKey(const Key('manual-start-trip-button')));
      await tester.pumpAndSettle();
      expect(container.read(tripStateMachineProvider).hasActiveTrip, isTrue);
      final buildsWhileRecording = recorder.buildCalls;

      // Leave the tracking screen entirely: HomeShell renders one tab, so the
      // screen — and every provider only it listened to — is unmounted.
      await tapTab(tester, 'History');
      expect(find.byType(TripTrackingScreen), findsNothing);
      expect(find.byType(TripHistoryScreen), findsOneWidget);

      // The recording, and the trip id it is writing to, are untouched.
      expect(container.read(tripStateMachineProvider).hasActiveTrip, isTrue);
      expect(container.read(tripStateMachineProvider).currentTripId, 1);
      expect(recorder.stopCalls, 0);

      await tapTab(tester, 'Active Trip');

      expect(find.byType(TripTrackingScreen), findsOneWidget);
      expect(find.text('Pause Trip'), findsOneWidget);
      // The session was never torn down and rebuilt behind the user's back.
      expect(recorder.buildCalls, buildsWhileRecording);
    });
  });
}
