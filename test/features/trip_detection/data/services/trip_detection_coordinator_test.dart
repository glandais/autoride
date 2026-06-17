import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:autoride/features/trip_detection/data/services/trip_detection_coordinator.dart';
import 'package:autoride/features/trip_detection/data/services/trip_state_machine.dart';
import 'package:autoride/features/trip_detection/data/services/trip_recorder_service.dart';
import 'package:autoride/features/trip_detection/data/services/notification_service.dart';
import 'package:autoride/features/trip_detection/data/services/location_permission_service.dart';
import 'package:autoride/features/trip_detection/domain/models/trip_state.dart';

// ===========================================================================
// COVERAGE NOTE / KNOWN LIMITATION  (audit finding #13)
// ===========================================================================
// TripDetectionCoordinator's entire decision-routing surface is PRIVATE and is
// driven exclusively by its motion stream:
//
//   startListening()  ->  motionDataStream(ref).listen(_onMotionData)
//   _onMotionData()   ->  _analyzeForTripStart / _analyzeForTripStop /
//                         _analyzeForResume  ->  startRecording / pauseTrip /
//                         resumeTrip / stopRecording / timeout handling
//
// Crucially, startListening() obtains the motion source by calling the
// *top-level* function `motionDataStream(ref)` (see
// trip_detection_coordinator.dart:46) and the location source by calling the
// top-level `locationStream(ref)` (line 57) DIRECTLY, NOT via
// `ref.watch(motionDataStreamProvider)` / `ref.watch(locationStreamProvider)`.
//
// Therefore overriding `motionDataStreamProvider` or `locationStreamProvider`
// on the ProviderContainer has NO effect: the coordinator always builds the
// real sensor/GPS streams (sensors_plus / Geolocator), which are unavailable in
// a unit-test environment and emit errors that the coordinator swallows via its
// stream onError handlers.
//
// Because there is also NO public method that accepts a MotionData/LocationData
// (the only public surface is build / startListening / stopListening), the
// following routing behaviors CANNOT be unit-tested here without a production
// change that injects the motion/location streams through an overridable
// provider (or exposes the analyze* methods):
//
//   * idle -> startDetecting() on first motion
//   * a positive trip-start detection triggering startRecording()
//   * a pauseTrip decision -> TripStateMachine.pauseTrip()
//   * a stopTrip decision -> _finalizeAndStopTrip() / stopRecording()
//   * resume logic from the paused state
//   * detection-timeout path (_checkDetectionTimeout) and cooldown activation
//
// Additionally, startListening() ITSELF cannot be exercised in a unit test:
// it subscribes to the real motionDataStream, whose internal `_mergeStreams`
// (sensor_service.dart) listens to `gyroscopeEventStream` / accelerometer
// plugin streams WITHOUT an onError forwarder. The sensors_plus plugin throws
// MissingPluginException when listened in a test, and that error escapes to the
// test zone uncaught (the coordinator's own onError cannot catch an error that
// the inner merge subscription drops). So calling startListening() reliably
// produces an uncaught zone error unrelated to the coordinator's own logic.
//
// What IS reachable WITHOUT touching any real plugin stream (covered below):
//   * build() initializes to TripState.idle
//   * stopListening() is safe to call when nothing was started (no streams are
//     ever created, so no plugins are touched) and leaves the machine idle
//   * the coordinator never transitions the state machine purely from build
//
// The overrides below stub out every collaborator the coordinator could touch
// (state machine, recorder, notification, location permission) so that the
// reachable exercises do not hit real plugins.
// ===========================================================================

/// State-machine double that performs transitions without reading other
/// providers (avoids the recorder<->machine circular dependency the production
/// machine would create; see trip_recorder_service_test.dart for details).
class _TestTripStateMachine extends TripStateMachine {
  @override
  TripState build() => const TripState.idle();

  @override
  void startDetecting() {
    state.mapOrNull(
      idle: (_) =>
          state = TripState.detecting(detectionStartTime: DateTime.now()),
    );
  }

  @override
  void startTripWithId(int tripId) {
    state.mapOrNull(
      detecting: (_) =>
          state = TripState.active(tripId: tripId, startTime: DateTime.now()),
    );
  }

  @override
  void pauseTrip() {
    state.mapOrNull(
      active: (a) => state = TripState.paused(
        tripId: a.tripId,
        startTime: a.startTime,
        pauseStartTime: DateTime.now(),
      ),
    );
  }

  @override
  void resumeTrip() {
    state.mapOrNull(
      paused: (p) =>
          state = TripState.active(tripId: p.tripId, startTime: p.startTime),
    );
  }

  @override
  void stopTrip() {
    state.mapOrNull(
      detecting: (_) => state = const TripState.idle(),
      active: (_) => state = const TripState.idle(),
      paused: (_) => state = const TripState.idle(),
    );
  }
}

/// Recorder double that never persists or starts a real location stream.
class _MockTripRecorderService extends TripRecorderService {
  @override
  Future<TripMetrics> build() async {
    return const TripMetrics(
      distanceMeters: 0,
      durationSeconds: 0,
      routePointCount: 0,
    );
  }
}

/// Notification double that skips all plugin calls.
class _MockNotificationService extends NotificationService {
  @override
  Future<void> build() async {}

  @override
  Future<void> showTripStartNotification() async {}

  @override
  Future<void> showTripStopNotification({
    required double distance,
    required Duration duration,
    required double avgSpeed,
  }) async {}

  @override
  Future<void> cancelForegroundNotification() async {}
}

/// Permission double reporting "denied" so the real locationStream errors
/// cleanly (swallowed by the coordinator) instead of hitting the plugin.
class _MockLocationPermissionService extends LocationPermissionService {
  @override
  Future<LocationPermissionStatus> build() async {
    return LocationPermissionStatus.denied;
  }
}

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({
      'tripNotificationsEnabled': true,
      'showOngoingNotification': true,
      'soundOnTripStartStop': false,
      'autoPauseEnabled': true,
      'minDistanceMeters': 500.0,
    });
  });

  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer(
      overrides: [
        tripStateMachineProvider.overrideWith(_TestTripStateMachine.new),
        tripRecorderServiceProvider.overrideWith(_MockTripRecorderService.new),
        notificationServiceProvider.overrideWith(_MockNotificationService.new),
        locationPermissionServiceProvider
            .overrideWith(_MockLocationPermissionService.new),
      ],
    );
    // Keep the coordinator alive (autoDispose) for the whole test.
    container.listen(tripDetectionCoordinatorProvider, (_, _) {});
  });

  tearDown(() {
    container.dispose();
  });

  Future<TripDetectionCoordinator> readCoordinator() async {
    await container.read(tripDetectionCoordinatorProvider.future);
    return container.read(tripDetectionCoordinatorProvider.notifier);
  }

  group('TripDetectionCoordinator - build', () {
    test('initializes in idle state', () async {
      final state =
          await container.read(tripDetectionCoordinatorProvider.future);

      state.when(
        idle: () => expect(true, isTrue),
        detecting: (_) => fail('Should be idle'),
        active: (_, _) => fail('Should be idle'),
        paused: (_, _, _) => fail('Should be idle'),
      );
    });
  });

  group('TripDetectionCoordinator - lifecycle (no real streams)', () {
    // NOTE: startListening() is intentionally NOT called here. It subscribes to
    // the real sensors_plus motion stream which throws an uncaught
    // MissingPluginException in the test zone (see the coverage note at the top
    // of this file). Only the no-stream paths are exercised.

    test('stopListening before any startListening is safe', () async {
      final coordinator = await readCoordinator();

      // No streams were ever created, so this only runs _cleanup() on nulls.
      coordinator.stopListening();

      // Provider remains in a valid state and the machine is untouched.
      expect(
        container.read(tripDetectionCoordinatorProvider).hasValue,
        isTrue,
      );
      expect(
        container.read(tripStateMachineProvider).hasActiveTrip,
        isFalse,
      );
    });

    test('repeated stopListening calls are safe (idempotent cleanup)',
        () async {
      final coordinator = await readCoordinator();

      coordinator.stopListening();
      coordinator.stopListening();

      expect(
        container.read(tripStateMachineProvider).hasActiveTrip,
        isFalse,
      );
    });

    test('coordinator does not auto-start a trip from build alone', () async {
      await readCoordinator();

      // Building the coordinator must not transition the state machine.
      final tripState = container.read(tripStateMachineProvider);
      expect(tripState.isRecording, isFalse);
      expect(tripState.hasActiveTrip, isFalse);
    });
  });
}
