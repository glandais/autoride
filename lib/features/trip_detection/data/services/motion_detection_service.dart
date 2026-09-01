import 'dart:async';
import 'dart:collection';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../domain/models/motion_data.dart';
import 'sensor_service.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/utils/provider_stream.dart';

part 'motion_detection_service.g.dart';

@riverpod
class MotionDetectionService extends _$MotionDetectionService {
  // Sliding window buffer for pattern analysis
  final Queue<MotionData> _buffer = Queue<MotionData>();

  @override
  Stream<MotionState> build() {
    final controller = StreamController<MotionState>();

    // Consume the motion data through its provider so a single shared sensor
    // subscription is used and tests can override `motionDataStreamProvider`.
    ref.listen(motionDataStreamProvider, (previous, next) {
      if (controller.isClosed) return;

      next.when(
        data: (motionData) {
          // Add to buffer
          _addToBuffer(motionData);

          // Periodically analyze buffer (every 1 second)
          if (_buffer.length >= AppConstants.pedalingCycleSamples) {
            // ~1s at 50Hz
            controller.add(_analyzeBuffer());
          }
        },
        error: controller.addError,
        loading: () {},
      );
    });

    ref.onDispose(controller.close);

    return controller.stream;
  }

  /// Add motion data to sliding window buffer
  void _addToBuffer(MotionData data) {
    _buffer.add(data);

    // Maintain buffer size limit (60 seconds at 50Hz = 3000 samples)
    while (_buffer.length > AppConstants.sensorBufferSize) {
      _buffer.removeFirst();
    }
  }

  /// Analyze buffer to determine motion state
  MotionState _analyzeBuffer() {
    if (_buffer.isEmpty) return MotionState.unknown;

    // Create motion window from recent samples
    final samples = _buffer.toList();
    final window = MotionWindow(
      samples: samples,
      startTime: samples.first.timestamp,
      endTime: samples.last.timestamp,
    );

    return window.state;
  }

  /// Get current motion window for analysis
  MotionWindow? getCurrentWindow() {
    if (_buffer.isEmpty) return null;

    final samples = _buffer.toList();
    return MotionWindow(
      samples: samples,
      startTime: samples.first.timestamp,
      endTime: samples.last.timestamp,
    );
  }

  /// Clear buffer (useful when stopping detection)
  void clearBuffer() {
    _buffer.clear();
  }

  /// Check if currently moving (any movement detected)
  Future<bool> isMoving() async {
    final window = getCurrentWindow();
    if (window == null) return false;

    return window.state != MotionState.stationary;
  }

  /// Check if potentially cycling (preliminary detection)
  Future<bool> isPotentiallyCycling() async {
    final window = getCurrentWindow();
    if (window == null) return false;

    return window.state == MotionState.cycling;
  }
}

/// Provider for current motion state (latest value)
@riverpod
class CurrentMotionState extends _$CurrentMotionState {
  @override
  Stream<MotionState> build() {
    // Re-expose the motion detection service's stream through its provider.
    // Calling `notifier.build()` here would start a SECOND `await for` loop over
    // the single shared `_buffer` of the same notifier instance, corrupting the
    // analysis window (L-003).
    return streamFromProvider(ref, motionDetectionServiceProvider);
  }
}
