import 'dart:async';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:sensors_plus/sensors_plus.dart';
import '../../domain/models/motion_data.dart';
import '../../../../core/constants/app_constants.dart';

part 'sensor_service.g.dart';

/// Accelerometer stream provider
/// Streams raw accelerometer data at configured sampling rate
@riverpod
Stream<AccelerometerData> accelerometerStream(
  Ref ref,
) async* {
  // Convert Hz to Duration for sampling period
  final samplingPeriod = Duration(
    microseconds: (1000000 / AppConstants.sensorSamplingRate).round(),
  );

  yield* accelerometerEventStream(samplingPeriod: samplingPeriod)
      .map((event) => AccelerometerData.fromEvent(event));
}

/// Gyroscope stream provider
/// Streams raw gyroscope data at configured sampling rate
@riverpod
Stream<GyroscopeData> gyroscopeStream(
  Ref ref,
) async* {
  // Convert Hz to Duration for sampling period
  final samplingPeriod = Duration(
    microseconds: (1000000 / AppConstants.sensorSamplingRate).round(),
  );

  yield* gyroscopeEventStream(samplingPeriod: samplingPeriod)
      .map((event) => GyroscopeData.fromEvent(event));
}

/// Combined motion data stream provider
/// Combines accelerometer and gyroscope into single stream
@riverpod
Stream<MotionData> motionDataStream(
  Ref ref,
) async* {
  // Get streams directly by calling the provider functions
  final accelStream = accelerometerStream(ref);
  final gyroStream = gyroscopeStream(ref);

  // Combine the streams
  // Note: This is a simplified combination - both streams emit at similar rates
  AccelerometerData? lastAccel;
  GyroscopeData? lastGyro;

  await for (final accelOrGyro in _mergeStreams(accelStream, gyroStream)) {
    if (accelOrGyro is AccelerometerData) {
      lastAccel = accelOrGyro;
    } else if (accelOrGyro is GyroscopeData) {
      lastGyro = accelOrGyro;
    }

    // Yield combined data when both sensors have data
    if (lastAccel != null && lastGyro != null) {
      yield MotionData(
        accelerometer: lastAccel,
        gyroscope: lastGyro,
        timestamp: DateTime.now(),
      );
    }
  }
}

/// Helper to merge two streams
Stream<dynamic> _mergeStreams(
  Stream<AccelerometerData> stream1,
  Stream<GyroscopeData> stream2,
) async* {
  final controller = StreamController<dynamic>();

  final sub1 = stream1.listen(controller.add);
  final sub2 = stream2.listen(controller.add);

  try {
    yield* controller.stream;
  } finally {
    await sub1.cancel();
    await sub2.cancel();
    await controller.close();
  }
}

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
