import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
// `Override` is not re-exported by flutter_riverpod.
import 'package:riverpod_annotation/riverpod_annotation.dart' show Override;

import 'package:autoride/features/trip_detection/data/services/location_service.dart';
import 'package:autoride/features/trip_detection/data/services/trip_recorder_service.dart';
import 'package:autoride/features/trip_detection/data/services/trip_state_machine.dart';
import 'package:autoride/features/trip_detection/domain/models/auto_detection_state.dart';
import 'package:autoride/features/trip_detection/domain/models/location_data.dart';
import 'package:autoride/features/trip_detection/domain/models/trip.dart';
import 'package:autoride/features/trip_detection/domain/models/trip_state.dart';
import 'package:autoride/features/trip_detection/presentation/screens/trip_tracking_screen.dart';
import 'package:autoride/features/trip_detection/presentation/widgets/trip_map_view.dart';

import '../../../../helpers/widget/fake_trip_providers.dart';
import '../../../../helpers/widget/pump_app.dart';

// ===========================================================================
// The tracking screen is the only place a trip can be started by hand
// (L-001/#11) and the only live view of a recording, and had no widget
// coverage (L-013). Everything it reads is behind an overridable provider
// since T041, so no GPS, database or foreground service is involved here.
// ===========================================================================

void main() {
  late RecorderLog recorder;
  late AutoDetectionLog detection;

  setUp(() {
    recorder = RecorderLog();
    detection = AutoDetectionLog();
  });

  List<Override> overrides({
    TripState initialTripState = const TripState.idle(),
    List<RoutePoint> routePoints = const [],
  }) => [
    ...tripSurfaceOverrides(
      recorder: recorder,
      detection: detection,
      initialTripState: initialTripState,
    ),
    // The recorder's GPS subscription is faked away; the screen only reads
    // the same stream for its marker.
    locationStreamProvider.overrideWith(
      (ref, settings) => const Stream<LocationData>.empty(),
    ),
    activeRoutePointsProvider.overrideWith((ref) async => routePoints),
  ];

  Future<void> pumpScreen(
    WidgetTester tester, {
    TripState initialTripState = const TripState.idle(),
    List<RoutePoint> routePoints = const [],
  }) async {
    await pumpAppWidget(
      tester,
      const TripTrackingScreen(),
      overrides: overrides(
        initialTripState: initialTripState,
        routePoints: routePoints,
      ),
    );
    await tester.pumpAndSettle();
  }

  ProviderContainer containerOf(WidgetTester tester) =>
      ProviderScope.containerOf(
        tester.element(find.byType(TripTrackingScreen)),
      );

  group('TripTrackingScreen - idle view', () {
    testWidgets('shows the detection status and the manual start button', (
      tester,
    ) async {
      await pumpScreen(tester);

      expect(find.text('No trip in progress'), findsOneWidget);
      expect(find.text('Watching for a ride'), findsOneWidget);
      expect(find.text('Detecting'), findsOneWidget);
      expect(find.byKey(const Key('manual-start-trip-button')), findsOneWidget);
    });

    testWidgets('explains why detection is idle instead of showing it as on', (
      tester,
    ) async {
      detection.state = const AutoDetectionState(
        enabled: false,
        permissionGranted: true,
        onboardingComplete: true,
      );
      await pumpScreen(tester);

      expect(find.text('Automatic detection is off'), findsOneWidget);
      expect(find.text('Off'), findsOneWidget);
      // The manual button stays available whatever detection is doing.
      expect(find.byKey(const Key('manual-start-trip-button')), findsOneWidget);
    });

    testWidgets('reports a missing location permission', (tester) async {
      detection.state = const AutoDetectionState(
        enabled: true,
        permissionGranted: false,
        onboardingComplete: true,
      );
      await pumpScreen(tester);

      expect(find.text('Location permission required'), findsOneWidget);
    });

    testWidgets(
      'the start button starts a trip and switches to the trip view',
      (tester) async {
        await pumpScreen(tester);

        await tester.tap(find.byKey(const Key('manual-start-trip-button')));
        await tester.pumpAndSettle();

        expect(detection.manualStartCalls, 1);
        expect(recorder.startedWithConfidence, [1.0]);
        expect(
          containerOf(tester).read(tripStateMachineProvider).hasActiveTrip,
          isTrue,
        );
        expect(find.text('Active Trip'), findsOneWidget);
        expect(find.text('Pause Trip'), findsOneWidget);
      },
    );

    testWidgets('a failed start is reported and leaves the screen idle', (
      tester,
    ) async {
      detection.throwOnManualStart = true;
      await pumpScreen(tester);

      await tester.tap(find.byKey(const Key('manual-start-trip-button')));
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.textContaining('Could not start the trip'), findsOneWidget);
      expect(find.text('No trip in progress'), findsOneWidget);
    });
  });

  group('TripTrackingScreen - active trip', () {
    final activeTrip = TripState.active(tripId: 1, startTime: DateTime.now());

    testWidgets('shows the metrics the recorder publishes', (tester) async {
      recorder.metrics = const TripMetrics(
        distanceMeters: 1500,
        durationSeconds: 300,
        routePointCount: 12,
        avgSpeedKmh: 18.0,
        maxSpeedKmh: 31.5,
      );
      await pumpScreen(tester, initialTripState: activeTrip);

      expect(find.text('Active'), findsOneWidget);
      expect(find.text('1.50 km'), findsOneWidget);
      expect(find.text('5m 0s'), findsOneWidget);
      expect(find.text('18.0 km/h'), findsOneWidget);
      expect(find.text('31.5 km/h'), findsOneWidget);
    });

    testWidgets('metrics update as the recorder ticks', (tester) async {
      await pumpScreen(tester, initialTripState: activeTrip);
      expect(find.text('0 m'), findsOneWidget);

      final fake = containerOf(
        tester,
      ).read(tripRecorderServiceProvider.notifier) as FakeTripRecorderService;
      fake.publish(
        const TripMetrics(
          distanceMeters: 2400,
          durationSeconds: 605,
          routePointCount: 30,
          avgSpeedKmh: 14.3,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('2.40 km'), findsOneWidget);
      expect(find.text('10m 5s'), findsOneWidget);
      expect(find.text('14.3 km/h'), findsOneWidget);
    });

    testWidgets('pause and resume dispatch to the recorder', (tester) async {
      await pumpScreen(tester, initialTripState: activeTrip);

      await tester.tap(find.text('Pause Trip'));
      await tester.pumpAndSettle();

      expect(recorder.pauseCalls, 1);
      expect(find.text('Paused'), findsOneWidget);
      expect(find.text('Resume Trip'), findsOneWidget);

      await tester.tap(find.text('Resume Trip'));
      await tester.pumpAndSettle();

      expect(recorder.resumeCalls, 1);
      expect(find.text('Active'), findsOneWidget);
      expect(find.text('Pause Trip'), findsOneWidget);
    });

    testWidgets('stopping asks for confirmation first', (tester) async {
      await pumpScreen(tester, initialTripState: activeTrip);

      await tester.tap(find.text('Stop Trip').last);
      await tester.pumpAndSettle();

      expect(find.text('Stop Trip?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(recorder.stopCalls, 0);
      expect(find.text('Active'), findsOneWidget);
    });

    testWidgets('confirming the stop ends the recording and leaves the screen', (
      tester,
    ) async {
      final observer = RecordingNavigatorObserver();
      await pumpAppWidget(
        tester,
        const _TrackingHost(),
        overrides: overrides(initialTripState: activeTrip),
        navigatorObserver: observer,
      );
      await tester.tap(find.text('open tracking'));
      await tester.pumpAndSettle();
      expect(find.byType(TripTrackingScreen), findsOneWidget);

      await tester.tap(find.text('Stop Trip').last);
      await tester.pumpAndSettle();
      // The dialog's confirm button, not the screen's (which is now behind it).
      await tester.tap(find.widgetWithText(ElevatedButton, 'Stop Trip'));
      await tester.pumpAndSettle();

      expect(recorder.stopCalls, 1);
      expect(find.byType(TripTrackingScreen), findsNothing);
      expect(observer.popped, isNotEmpty);
    });
  });

  group('TripTrackingScreen - map', () {
    // The map is rendered but never asserted on pixel-wise: its tiles are
    // network resources the test binding refuses, which flutter_map reports
    // through `errorTileCallback` rather than throwing.
    testWidgets('renders with no location fix and no route', (tester) async {
      await pumpScreen(
        tester,
        initialTripState: TripState.active(
          tripId: 1,
          startTime: DateTime.now(),
        ),
      );

      expect(find.byType(TripMapView), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders a route once points exist', (tester) async {
      final now = DateTime.now();
      await pumpScreen(
        tester,
        initialTripState: TripState.active(tripId: 1, startTime: now),
        routePoints: [
          RoutePoint(
            tripId: 1,
            latitude: 48.85,
            longitude: 2.35,
            timestamp: now,
          ),
          RoutePoint(
            tripId: 1,
            latitude: 48.86,
            longitude: 2.36,
            timestamp: now.add(const Duration(seconds: 30)),
          ),
        ],
      );

      expect(find.byType(TripMapView), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}

/// Host that pushes the tracking screen onto a route, so the screen's
/// `Navigator.pop()` after a confirmed stop has somewhere to go.
class _TrackingHost extends StatelessWidget {
  const _TrackingHost();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const TripTrackingScreen(),
              ),
            ),
            child: const Text('open tracking'),
          ),
        ),
      ),
    );
  }
}
