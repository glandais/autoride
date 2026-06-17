import 'package:flutter_test/flutter_test.dart';
import 'package:autoride/features/trip_detection/data/services/motion_detection_service.dart';

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
}
