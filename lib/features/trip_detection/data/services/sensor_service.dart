import 'dart:async';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:sensors_plus/sensors_plus.dart';
import '../../domain/models/motion_data.dart';
import 'battery_optimizer.dart';

part 'sensor_service.g.dart';

/// Sampling period for the current power mode (audit #4).
///
/// `sensors_plus` takes a sampling period rather than a rate, so the per-mode
/// Hz values in [PowerModeConfig] are converted here. Both sensor providers
/// watch the power mode, so dropping to a lower mode rebuilds them with a
/// slower period; consumers subscribe through the providers and keep receiving
/// samples across that rebuild.
Duration _samplingPeriodFor(Ref ref) {
  final rate = ref.watch(currentPowerModeProvider).sensorSamplingRate;
  return Duration(microseconds: (1000000 / rate).round());
}

/// Accelerometer stream provider
/// Streams raw accelerometer data at the current power mode's sampling rate
@riverpod
Stream<AccelerometerData> accelerometerStream(
  Ref ref,
) async* {
  final samplingPeriod = _samplingPeriodFor(ref);

  yield* accelerometerEventStream(samplingPeriod: samplingPeriod)
      .map((event) => AccelerometerData.fromEvent(event));
}

/// Gyroscope stream provider
/// Streams raw gyroscope data at the current power mode's sampling rate
@riverpod
Stream<GyroscopeData> gyroscopeStream(
  Ref ref,
) async* {
  final samplingPeriod = _samplingPeriodFor(ref);

  yield* gyroscopeEventStream(samplingPeriod: samplingPeriod)
      .map((event) => GyroscopeData.fromEvent(event));
}

/// Combined motion data stream provider
/// Combines accelerometer and gyroscope into single stream
///
/// Both sources are consumed through their *providers* (not by calling the
/// generated functions), so a single shared subscription per sensor is opened
/// and tests can inject fakes by overriding
/// [accelerometerStreamProvider] / [gyroscopeStreamProvider].
@riverpod
Stream<MotionData> motionDataStream(Ref ref) {
  final controller = StreamController<MotionData>();

  AccelerometerData? lastAccel;
  GyroscopeData? lastGyro;

  void emitIfReady() {
    final accel = lastAccel;
    final gyro = lastGyro;
    if (accel == null || gyro == null || controller.isClosed) return;

    controller.add(
      MotionData(
        accelerometer: accel,
        gyroscope: gyro,
        timestamp: DateTime.now(),
      ),
    );
  }

  // Forward errors as well as data: an accelerometer/gyroscope failure must
  // reach the merged stream's consumer (the coordinator's error handler)
  // instead of silently stopping detection with no diagnostic.
  void forwardError(Object error, StackTrace stackTrace) {
    if (!controller.isClosed) controller.addError(error, stackTrace);
  }

  ref.listen(accelerometerStreamProvider, (previous, next) {
    next.when(
      data: (data) {
        lastAccel = data;
        emitIfReady();
      },
      error: forwardError,
      loading: () {},
    );
  });

  ref.listen(gyroscopeStreamProvider, (previous, next) {
    next.when(
      data: (data) {
        lastGyro = data;
        emitIfReady();
      },
      error: forwardError,
      loading: () {},
    );
  });

  ref.onDispose(controller.close);

  return controller.stream;
}

// TODO(T041): `sensorServiceProvider` has no consumer in lib/ - no code checks
// sensor availability before starting detection.
@riverpod
class SensorService extends _$SensorService {
  @override
  Future<bool> build() async {
    // Check if sensors are available
    return await _checkSensorAvailability();
  }

  /// Check if accelerometer and gyroscope are available
  Future<bool> _checkSensorAvailability() async {
    try {
      // Try to get a single reading from each sensor
      await accelerometerEventStream()
          .timeout(const Duration(seconds: 2))
          .first;
      await gyroscopeEventStream()
          .timeout(const Duration(seconds: 2))
          .first;
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Test if sensors are responding
  Future<bool> areSensorsWorking() async {
    return await _checkSensorAvailability();
  }
}
