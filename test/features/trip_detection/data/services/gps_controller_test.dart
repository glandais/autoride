import 'package:flutter_test/flutter_test.dart';
import 'package:autoride/features/trip_detection/data/services/gps_controller.dart';

void main() {
  group('GPSState enum', () {
    test('should have all four GPS states', () {
      expect(GPSState.values.length, equals(4));
      expect(GPSState.values, contains(GPSState.inactive));
      expect(GPSState.values, contains(GPSState.activating));
      expect(GPSState.values, contains(GPSState.active));
      expect(GPSState.values, contains(GPSState.stopping));
    });
  });

  // ---------------------------------------------------------------------------
  // GPSController force/getter behavior.
  //
  // We instantiate the notifier directly (GPSController()) so we can exercise
  // the synchronous force/getter API without Riverpod's eager build(), which
  // subscribes to the motion stream -> sensors_plus event stream (no platform
  // in unit tests). forceStartGPS()/forceStopGPS()/getCurrentState()/
  // isGPSActive() operate purely on the internal GPS state field and never
  // touch `ref`, so direct instantiation is safe.
  //
  // NOTE: GPSController is part of a deferred larger refactor; these tests
  // assert its CURRENT behavior only. The motion-gated build() stream and the
  // inactivity timer (which fires inside build() via ref.onDispose) are not
  // unit-testable without a stream seam, so they are not covered here.
  // ---------------------------------------------------------------------------
  group('GPSController force/getter methods', () {
    test('initial state is inactive and GPS is not active', () {
      final controller = GPSController();

      expect(controller.getCurrentState(), equals(GPSState.inactive));
      expect(controller.isGPSActive(), isFalse);
    });

    test('forceStartGPS transitions inactive -> active', () async {
      final controller = GPSController();

      await controller.forceStartGPS();

      expect(controller.getCurrentState(), equals(GPSState.active));
      expect(controller.isGPSActive(), isTrue);
    });

    test('forceStartGPS is idempotent when already active', () async {
      final controller = GPSController();

      await controller.forceStartGPS();
      await controller.forceStartGPS(); // second call is a no-op

      expect(controller.getCurrentState(), equals(GPSState.active));
      expect(controller.isGPSActive(), isTrue);
    });

    test('forceStopGPS transitions active -> inactive', () async {
      final controller = GPSController();

      await controller.forceStartGPS();
      expect(controller.isGPSActive(), isTrue);

      await controller.forceStopGPS();

      expect(controller.getCurrentState(), equals(GPSState.inactive));
      expect(controller.isGPSActive(), isFalse);
    });

    test('forceStopGPS is a no-op when already inactive', () async {
      final controller = GPSController();

      await controller.forceStopGPS();

      expect(controller.getCurrentState(), equals(GPSState.inactive));
      expect(controller.isGPSActive(), isFalse);
    });

    test('start/stop can be cycled repeatedly', () async {
      final controller = GPSController();

      await controller.forceStartGPS();
      await controller.forceStopGPS();
      await controller.forceStartGPS();

      expect(controller.getCurrentState(), equals(GPSState.active));
      expect(controller.isGPSActive(), isTrue);
    });
  });
}
