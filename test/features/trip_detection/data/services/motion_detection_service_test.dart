import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:autoride/core/constants/app_constants.dart';
import 'package:autoride/features/trip_detection/data/services/motion_detection_service.dart';
import 'package:autoride/features/trip_detection/data/services/sensor_service.dart';
import 'package:autoride/features/trip_detection/domain/models/motion_data.dart';

/// Cycling-profile sample (accel magnitude sqrt(118) ~ 10.86 > 10.5, gyro
/// magnitude sqrt(1.5) ~ 1.22 > 0.5) with a unique timestamp so every emission
/// notifies listeners.
MotionData _cyclingSample(int index) {
  final timestamp = DateTime(2026, 1, 1).add(Duration(milliseconds: index));
  return MotionData(
    accelerometer:
        AccelerometerData(x: 3.0, y: 3.0, z: 10.0, timestamp: timestamp),
    gyroscope: GyroscopeData(x: 1.0, y: 0.5, z: 0.5, timestamp: timestamp),
    timestamp: timestamp,
  );
}

void main() {
  // ---------------------------------------------------------------------------
  // MotionDetectionService public API.
  //
  // We instantiate the notifier directly (MotionDetectionService()) so we can
  // exercise the buffer-reading methods without going through Riverpod's eager
  // build(), which subscribes to motionDataStream -> the sensors_plus event
  // stream (no platform implementation in unit tests). getCurrentWindow(),
  // clearBuffer(), isMoving() and isPotentiallyCycling() never touch `ref`, so
  // this is safe.
  //
  // IMPORTANT LIMITATION:
  // The sliding-window buffer is private (`_buffer`) and is ONLY populated by
  // the build() stream, which calls `motionDataStream(ref)` directly (the
  // generated provider function, NOT `ref.watch(motionDataStreamProvider)`).
  // Because production code bypasses the provider, overriding
  // `motionDataStreamProvider` has no effect, and there is no public seam to
  // inject buffer samples. Consequently the buffer-eviction (FIFO past
  // AppConstants.sensorBufferSize) and the populated-window paths CANNOT be
  // exercised without a production change (e.g. exposing an injectable stream
  // or a buffer-add seam). We cover the empty-buffer behavior here and document
  // the gap.
  // ---------------------------------------------------------------------------
  group('MotionDetectionService empty-buffer behavior', () {
    test('getCurrentWindow returns null when buffer is empty', () {
      final service = MotionDetectionService();
      expect(service.getCurrentWindow(), isNull);
    });

    test('isMoving returns false when buffer is empty', () async {
      final service = MotionDetectionService();
      expect(await service.isMoving(), isFalse);
    });

    test('isPotentiallyCycling returns false when buffer is empty', () async {
      final service = MotionDetectionService();
      expect(await service.isPotentiallyCycling(), isFalse);
    });

    test('clearBuffer on an empty buffer is a no-op (still null window)', () {
      final service = MotionDetectionService();
      service.clearBuffer();
      expect(service.getCurrentWindow(), isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // Since T041 / audit #5 the buffer is fed through `motionDataStreamProvider`
  // (`ref.listen`) instead of a direct call to the generated function, so it can
  // finally be driven from a test.
  // ---------------------------------------------------------------------------
  group('MotionDetectionService fed through the provider', () {
    late StreamController<MotionData> motionController;
    late ProviderContainer container;

    setUp(() {
      motionController = StreamController<MotionData>.broadcast();
      container = ProviderContainer(
        overrides: [
          motionDataStreamProvider
              .overrideWith((ref) => motionController.stream),
        ],
      );
    });

    tearDown(() async {
      container.dispose();
      await motionController.close();
    });

    Future<void> feed(int count) async {
      for (var i = 0; i < count; i++) {
        motionController.add(_cyclingSample(i));
      }
      await pumpEventQueue();
    }

    test('emits a motion state once a full analysis window is buffered',
        () async {
      container.listen(motionDetectionServiceProvider, (_, _) {});
      await pumpEventQueue();

      await feed(AppConstants.pedalingCycleSamples);

      final state = container.read(motionDetectionServiceProvider);
      expect(state.hasValue, isTrue);
      expect(state.value, MotionState.cycling);

      final window = container
          .read(motionDetectionServiceProvider.notifier)
          .getCurrentWindow();
      expect(window, isNotNull);
      expect(window!.samples, hasLength(AppConstants.pedalingCycleSamples));
    });

    test(
        'L-003 regression: CurrentMotionState mirrors the service without '
        'starting a second loop over the shared buffer', () async {
      container.listen(motionDetectionServiceProvider, (_, _) {});
      container.listen(currentMotionStateProvider, (_, _) {});
      await pumpEventQueue();

      await feed(AppConstants.pedalingCycleSamples);

      // Each sample must land in the buffer exactly ONCE. Calling
      // `notifier.build()` from CurrentMotionState used to start a second
      // `await for` over the same instance, doubling every sample.
      final window = container
          .read(motionDetectionServiceProvider.notifier)
          .getCurrentWindow();
      expect(window!.samples, hasLength(AppConstants.pedalingCycleSamples));

      expect(
        container.read(currentMotionStateProvider).value,
        MotionState.cycling,
      );
    });
  });
}
