import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:autoride/features/trip_detection/data/services/battery_optimizer.dart';
import 'package:autoride/features/trip_detection/data/services/sensor_service.dart';
import 'package:autoride/features/trip_detection/domain/models/motion_data.dart';

/// Tests for the units declared in `sensor_service.dart`: the
/// `accelerometerStream` / `gyroscopeStream` / `motionDataStream` providers and
/// the `SensorService` availability check.
///
/// The sensor value-object and `SensorUtils` tests that used to make up this
/// file — and never imported anything from `sensor_service.dart` (L-026) — now
/// live in `test/features/trip_detection/domain/models/motion_data_test.dart`
/// and `sensor_utils_test.dart`.
void main() {
  late SensorsPlatform originalPlatform;

  setUp(() {
    originalPlatform = SensorsPlatform.instance;
  });

  tearDown(() {
    SensorsPlatform.instance = originalPlatform;
  });

  _FakeSensorsPlatform installPlatform({
    AccelerometerEvent? seedAccel,
    GyroscopeEvent? seedGyro,
    bool accelError = false,
    bool gyroError = false,
  }) {
    final platform = _FakeSensorsPlatform(
      seedAccel: seedAccel,
      seedGyro: seedGyro,
      accelError: accelError,
      gyroError: gyroError,
    );
    SensorsPlatform.instance = platform;
    addTearDown(platform.dispose);
    return platform;
  }

  ProviderContainer containerWith({
    PowerModeConfig powerMode = PowerModeConfig.normal,
  }) {
    final container = ProviderContainer(
      overrides: [
        currentPowerModeProvider.overrideWith(() => _FixedPowerMode(powerMode)),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  // ---------------------------------------------------------------------------
  // accelerometerStream / gyroscopeStream
  // ---------------------------------------------------------------------------

  group('accelerometerStream', () {
    test('maps platform events onto AccelerometerData', () async {
      final platform = installPlatform();

      final container = containerWith();
      final emitted = <AccelerometerData>[];
      container.listen(accelerometerStreamProvider, (_, next) {
        next.whenData(emitted.add);
      });
      await pumpEventQueue();

      platform.accel.add(AccelerometerEvent(1.0, 2.0, 3.0, DateTime(2026)));
      await pumpEventQueue();

      expect(emitted, hasLength(1));
      expect(emitted.single.x, 1.0);
      expect(emitted.single.y, 2.0);
      expect(emitted.single.z, 3.0);
    });

    test('requests the sampling period of the current power mode', () async {
      final platform = installPlatform();

      final container = containerWith();
      container.listen(accelerometerStreamProvider, (_, _) {});
      await pumpEventQueue();

      // 50 Hz normal mode -> 20 000 µs
      expect(
        platform.accelPeriods,
        equals([const Duration(microseconds: 20000)]),
      );
    });

    test('a lower power mode slows the requested period', () async {
      final platform = installPlatform();

      final container = containerWith(powerMode: PowerModeConfig.critical);
      container.listen(accelerometerStreamProvider, (_, _) {});
      await pumpEventQueue();

      // 20 Hz critical mode -> 50 000 µs
      expect(
        platform.accelPeriods,
        equals([const Duration(microseconds: 50000)]),
      );
    });
  });

  group('gyroscopeStream', () {
    test('maps platform events onto GyroscopeData', () async {
      final platform = installPlatform();

      final container = containerWith();
      final emitted = <GyroscopeData>[];
      container.listen(gyroscopeStreamProvider, (_, next) {
        next.whenData(emitted.add);
      });
      await pumpEventQueue();

      platform.gyro.add(GyroscopeEvent(0.1, 0.2, 0.3, DateTime(2026)));
      await pumpEventQueue();

      expect(emitted, hasLength(1));
      expect(emitted.single.x, 0.1);
      expect(emitted.single.z, 0.3);
    });

    test('requests the sampling period of the current power mode', () async {
      final platform = installPlatform();

      final container = containerWith(powerMode: PowerModeConfig.low);
      container.listen(gyroscopeStreamProvider, (_, _) {});
      await pumpEventQueue();

      // 25 Hz low mode -> 40 000 µs
      expect(
        platform.gyroPeriods,
        equals([const Duration(microseconds: 40000)]),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // motionDataStream merges the accelerometer and gyroscope PROVIDERS
  // (T041 / audit #5), so the merge itself is testable and each sensor is
  // subscribed to exactly once instead of once per consumer.
  // ---------------------------------------------------------------------------

  group('motionDataStream merge', () {
    late StreamController<AccelerometerData> accelController;
    late StreamController<GyroscopeData> gyroController;
    late ProviderContainer container;

    setUp(() {
      accelController = StreamController<AccelerometerData>.broadcast();
      gyroController = StreamController<GyroscopeData>.broadcast();
      container = ProviderContainer(
        overrides: [
          accelerometerStreamProvider.overrideWith(
            (ref) => accelController.stream,
          ),
          gyroscopeStreamProvider.overrideWith((ref) => gyroController.stream),
        ],
      );
    });

    tearDown(() async {
      container.dispose();
      await accelController.close();
      await gyroController.close();
    });

    test('emits nothing until both sensors have produced a sample', () async {
      final emitted = <MotionData>[];
      container.listen(motionDataStreamProvider, (previous, next) {
        next.whenData(emitted.add);
      });
      await pumpEventQueue();

      accelController.add(
        AccelerometerData(x: 3.0, y: 3.0, z: 10.0, timestamp: DateTime(2026)),
      );
      await pumpEventQueue();
      expect(emitted, isEmpty);

      // The gyroscope is sampled-and-held, not a trigger: it arriving does not
      // by itself produce a sample.
      gyroController.add(
        GyroscopeData(x: 1.0, y: 0.5, z: 0.5, timestamp: DateTime(2026)),
      );
      await pumpEventQueue();
      expect(emitted, isEmpty);

      accelController.add(
        AccelerometerData(
          x: 3.0,
          y: 3.0,
          z: 10.0,
          timestamp: DateTime(2026, 1, 1, 0, 0, 1),
        ),
      );
      await pumpEventQueue();

      expect(emitted, hasLength(1));
      expect(emitted.single.accelerometer.z, 10.0);
      expect(emitted.single.gyroscope.x, 1.0);
    });

    test('the accelerometer paces the merged stream', () async {
      final emitted = <MotionData>[];
      container.listen(motionDataStreamProvider, (previous, next) {
        next.whenData(emitted.add);
      });
      await pumpEventQueue();

      gyroController.add(
        GyroscopeData(x: 0.1, y: 0.1, z: 0.1, timestamp: DateTime(2026)),
      );
      accelController.add(
        AccelerometerData(x: 0.0, y: 0.0, z: 9.8, timestamp: DateTime(2026)),
      );
      await pumpEventQueue();
      expect(emitted, hasLength(1));

      // Two independent sensors at the same rate used to interleave into a
      // merged stream running at twice it — 108 Hz measured on a Pixel 6a for a
      // configured 50 — and every extra sample costs a full pass through the
      // coordinator. Gyroscope samples now only update the held value.
      for (var i = 0; i < 5; i++) {
        gyroController.add(
          GyroscopeData(
            x: 0.2,
            y: 0.2,
            z: 0.2,
            timestamp: DateTime(2026).add(Duration(milliseconds: i)),
          ),
        );
        await pumpEventQueue();
      }
      expect(emitted, hasLength(1));

      accelController.add(
        AccelerometerData(
          x: 0.0,
          y: 0.0,
          z: 9.8,
          timestamp: DateTime(2026, 1, 1, 0, 0, 1),
        ),
      );
      await pumpEventQueue();

      expect(emitted, hasLength(2));
      // ... and the pairing carries the most recent gyroscope reading.
      expect(emitted.last.gyroscope.x, 0.2);
    });

    test('forwards sensor errors to the merged stream', () async {
      container.listen(motionDataStreamProvider, (_, _) {});
      await pumpEventQueue();

      accelController.addError(StateError('accelerometer failure'));
      await pumpEventQueue();

      expect(container.read(motionDataStreamProvider).hasError, isTrue);
    });
  });

  // ---------------------------------------------------------------------------
  // SensorService — the availability probe
  // ---------------------------------------------------------------------------

  group('SensorService', () {
    test('reports available when both sensors produce a reading', () async {
      installPlatform(
        seedAccel: AccelerometerEvent(0.0, 0.0, 9.8, DateTime(2026)),
        seedGyro: GyroscopeEvent(0.0, 0.0, 0.0, DateTime(2026)),
      );

      final container = containerWith();

      expect(await container.read(sensorServiceProvider.future), isTrue);
    });

    test('reports unavailable when the accelerometer errors', () async {
      installPlatform(accelError: true);

      final container = containerWith();

      expect(await container.read(sensorServiceProvider.future), isFalse);
    });

    test('reports unavailable when only the accelerometer works', () async {
      installPlatform(
        seedAccel: AccelerometerEvent(0.0, 0.0, 9.8, DateTime(2026)),
        gyroError: true,
      );

      final container = containerWith();

      expect(await container.read(sensorServiceProvider.future), isFalse);
    });

    test('areSensorsWorking() re-probes the platform', () async {
      final platform = installPlatform(
        seedAccel: AccelerometerEvent(0.0, 0.0, 9.8, DateTime(2026)),
        seedGyro: GyroscopeEvent(0.0, 0.0, 0.0, DateTime(2026)),
      );

      final container = containerWith();
      await container.read(sensorServiceProvider.future);
      final probesAfterBuild = platform.accelSubscriptions;

      final notifier = container.read(sensorServiceProvider.notifier);
      expect(await notifier.areSensorsWorking(), isTrue);
      expect(platform.accelSubscriptions, greaterThan(probesAfterBuild));
    });
  });
}

/// Pins the power mode so the sampling-period conversion is deterministic.
class _FixedPowerMode extends CurrentPowerMode {
  _FixedPowerMode(this._config);

  final PowerModeConfig _config;

  @override
  PowerModeConfig build() => _config;
}

/// A `sensors_plus` platform that feeds controllable streams instead of the
/// device. `SensorsPlatform.instance` is the plugin's own seam, so no
/// production code needs a test-only hook.
class _FakeSensorsPlatform extends SensorsPlatform {
  _FakeSensorsPlatform({
    this.seedAccel,
    this.seedGyro,
    this.accelError = false,
    this.gyroError = false,
  });

  final AccelerometerEvent? seedAccel;
  final GyroscopeEvent? seedGyro;
  final bool accelError;
  final bool gyroError;

  final accel = StreamController<AccelerometerEvent>.broadcast();
  final gyro = StreamController<GyroscopeEvent>.broadcast();

  final accelPeriods = <Duration>[];
  final gyroPeriods = <Duration>[];

  int accelSubscriptions = 0;
  int gyroSubscriptions = 0;

  Future<void> dispose() async {
    await accel.close();
    await gyro.close();
  }

  @override
  Stream<AccelerometerEvent> accelerometerEventStream({
    Duration samplingPeriod = SensorInterval.normalInterval,
  }) {
    accelPeriods.add(samplingPeriod);
    accelSubscriptions++;
    if (accelError) {
      return Stream<AccelerometerEvent>.error(StateError('no accelerometer'));
    }
    final seed = seedAccel;
    if (seed != null) {
      return Stream<AccelerometerEvent>.value(seed);
    }
    return accel.stream;
  }

  @override
  Stream<GyroscopeEvent> gyroscopeEventStream({
    Duration samplingPeriod = SensorInterval.normalInterval,
  }) {
    gyroPeriods.add(samplingPeriod);
    gyroSubscriptions++;
    if (gyroError) {
      return Stream<GyroscopeEvent>.error(StateError('no gyroscope'));
    }
    final seed = seedGyro;
    if (seed != null) {
      return Stream<GyroscopeEvent>.value(seed);
    }
    return gyro.stream;
  }
}
