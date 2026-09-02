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
///
/// The period is a **request, not a contract**: Android rounds it to a rate the
/// sensor actually supports and speeds the stream up while the app is
/// foregrounded, and iOS has its own floor. A 2026-09-02 log measured 55.6 Hz
/// backgrounded and 83 Hz foregrounded on a Pixel 6a for a configured 50, and
/// 51.4 Hz on an iPhone (L-086). What the app receives is therefore always to
/// be read from the `hb` event — `mn` samples over `dt` ms, against the `hz`
/// the same line carries — and never assumed from this number.
Duration _samplingPeriodFor(Ref ref) {
  final rate = ref.watch(currentPowerModeProvider).sensorSamplingRate;
  return Duration(microseconds: (1000000 / rate).round());
}

/// Accelerometer stream provider
/// Streams raw accelerometer data at the current power mode's sampling rate
@riverpod
Stream<AccelerometerData> accelerometerStream(Ref ref) async* {
  final samplingPeriod = _samplingPeriodFor(ref);

  yield* accelerometerEventStream(samplingPeriod: samplingPeriod)
      .map((event) => AccelerometerData.fromEvent(event));
}

/// Gyroscope stream provider
/// Streams raw gyroscope data at the current power mode's sampling rate
@riverpod
Stream<GyroscopeData> gyroscopeStream(Ref ref) async* {
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
///
/// The **accelerometer is the pacer**: one `MotionData` per accelerometer
/// sample, carrying the most recent gyroscope reading. Emitting on *either*
/// sensor instead made the merged stream run at twice the configured rate —
/// two independent 50 Hz sources interleave into ~100 Hz — and every sample
/// costs a full pass through the coordinator: gate re-evaluation, detector,
/// audit. A T043 log measured 108 Hz on a Pixel 6a and 103 Hz on an iPhone in
/// `normal` mode, where `PowerModeConfig.sensorSamplingRate` asks for 50. The
/// gyroscope is sampled-and-held rather than dropped: it is an input to the
/// verdict, not a trigger for one.
///
/// This halves the merged rate; it does not *set* it. The result is one
/// `MotionData` per accelerometer sample, and the accelerometer runs at
/// whatever rate the OS grants for the requested period — 55.6 Hz
/// backgrounded and 83 Hz foregrounded on the Pixel 6a of the following run,
/// against a configured 50 (L-086, correcting `07fabee`'s "the configured rate
/// exactly"). Whether to hold the pipeline to the configured rate by dropping
/// the surplus is a detection-and-battery decision, and belongs to T045 with
/// the rest of the motion arithmetic.
@riverpod
Stream<MotionData> motionDataStream(Ref ref) {
  final controller = StreamController<MotionData>();

  GyroscopeData? lastGyro;

  void emit(AccelerometerData accel) {
    final gyro = lastGyro;
    // Nothing to pair with yet: the first accelerometer samples of a session
    // arrive before the gyroscope has produced anything.
    if (gyro == null || controller.isClosed) return;

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
    next.when(data: emit, error: forwardError, loading: () {});
  });

  ref.listen(gyroscopeStreamProvider, (previous, next) {
    next.when(
      data: (data) => lastGyro = data,
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
      await gyroscopeEventStream().timeout(const Duration(seconds: 2)).first;
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
