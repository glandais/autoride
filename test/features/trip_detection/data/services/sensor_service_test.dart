import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:autoride/core/constants/app_constants.dart';
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

    /// Injected clock: the merged stream holds itself to the configured
    /// sampling period, so a test pushing samples as fast as the event loop
    /// allows would have them dropped as a burst. Advanced by [pushAccel].
    late DateTime clock;

    setUp(() {
      clock = DateTime(2026, 1, 1, 12);
      accelController = StreamController<AccelerometerData>.broadcast();
      gyroController = StreamController<GyroscopeData>.broadcast();
      container = ProviderContainer(
        overrides: [
          accelerometerStreamProvider.overrideWith(
            (ref) => accelController.stream,
          ),
          gyroscopeStreamProvider.overrideWith((ref) => gyroController.stream),
          motionClockProvider.overrideWith(
            (ref) =>
                () => clock,
          ),
        ],
      );
    });

    /// Advance the clock past one sampling slot, then push an accelerometer
    /// sample — i.e. a source running at exactly the configured rate.
    Future<void> pushAccel(AccelerometerData accel) async {
      clock = clock.add(const Duration(milliseconds: 21));
      accelController.add(accel);
      await pumpEventQueue();
    }

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

      await pushAccel(
        AccelerometerData(
          x: 0.0,
          y: 0.0,
          z: 9.8,
          timestamp: DateTime(2026, 1, 1, 0, 0, 1),
        ),
      );

      expect(emitted, hasLength(2));
      // ... and the pairing carries the most recent gyroscope reading.
      expect(emitted.last.gyroscope.x, 0.2);
    });

    test('holds the merged stream to the configured rate (L-086, T045)', () async {
      final emitted = <MotionData>[];
      container.listen(motionDataStreamProvider, (previous, next) {
        next.whenData(emitted.add);
      });
      await pumpEventQueue();

      gyroController.add(
        GyroscopeData(x: 0.1, y: 0.1, z: 0.1, timestamp: DateTime(2026)),
      );
      await pumpEventQueue();

      // A source running at 83 Hz — what a Pixel 6a delivered foregrounded for
      // a configured 50 (L-086). Two seconds of it.
      const sourcePeriod = Duration(milliseconds: 12);
      final start = clock;
      for (var i = 0; i < 167; i++) {
        clock = clock.add(sourcePeriod);
        accelController.add(
          AccelerometerData(x: 0.0, y: 0.0, z: 9.8, timestamp: clock),
        );
        await pumpEventQueue();
      }

      final elapsed = clock.difference(start).inMilliseconds / 1000;
      final rate = emitted.length / elapsed;
      expect(
        rate,
        closeTo(AppConstants.sensorSamplingRateNormal.toDouble(), 2.0),
        reason: 'the surplus is dropped, not passed to the coordinator',
      );
    });

    test(
      'a source slower than the configured rate is passed through whole',
      () async {
        final emitted = <MotionData>[];
        container.listen(motionDataStreamProvider, (previous, next) {
          next.whenData(emitted.add);
        });
        await pumpEventQueue();

        gyroController.add(
          GyroscopeData(x: 0.1, y: 0.1, z: 0.1, timestamp: DateTime(2026)),
        );
        await pumpEventQueue();

        // The rate is a ceiling, never a floor: the OS's period is still a
        // request, and nothing here may invent samples it did not deliver.
        for (var i = 0; i < 20; i++) {
          clock = clock.add(const Duration(milliseconds: 100));
          accelController.add(
            AccelerometerData(x: 0.0, y: 0.0, z: 9.8, timestamp: clock),
          );
          await pumpEventQueue();
        }

        expect(emitted, hasLength(20));
      },
    );

    test('a gap in the stream does not become a catch-up burst', () async {
      final emitted = <MotionData>[];
      container.listen(motionDataStreamProvider, (previous, next) {
        next.whenData(emitted.add);
      });
      await pumpEventQueue();

      gyroController.add(
        GyroscopeData(x: 0.1, y: 0.1, z: 0.1, timestamp: DateTime(2026)),
      );
      await pushAccel(
        AccelerometerData(x: 0.0, y: 0.0, z: 9.8, timestamp: clock),
      );
      expect(emitted, hasLength(1));

      // The process was suspended for two minutes — 6 000 slots went by. The
      // samples that arrive next must be paced from now, not let through in a
      // burst to make up for them.
      clock = clock.add(const Duration(minutes: 2));
      for (var i = 0; i < 5; i++) {
        clock = clock.add(const Duration(milliseconds: 4));
        accelController.add(
          AccelerometerData(x: 0.0, y: 0.0, z: 9.8, timestamp: clock),
        );
        await pumpEventQueue();
      }

      expect(emitted, hasLength(2));
    });

    test('a power-mode change reaches the merged stream without breaking it', () async {
      // The one thing `ref.read` plus a listener has to buy over `ref.watch`:
      // the period follows the mode, and the controller — with every consumer's
      // subscription — survives the change.
      final mode = _MutablePowerMode();
      final localAccel = StreamController<AccelerometerData>.broadcast();
      final localGyro = StreamController<GyroscopeData>.broadcast();
      var localClock = DateTime(2026, 1, 1, 12);
      final localContainer = ProviderContainer(
        overrides: [
          accelerometerStreamProvider.overrideWith((ref) => localAccel.stream),
          gyroscopeStreamProvider.overrideWith((ref) => localGyro.stream),
          motionClockProvider.overrideWith(
            (ref) =>
                () => localClock,
          ),
          currentPowerModeProvider.overrideWith(() => mode),
        ],
      );
      addTearDown(() async {
        localContainer.dispose();
        await localAccel.close();
        await localGyro.close();
      });

      final out = <MotionData>[];
      localContainer.listen(motionDataStreamProvider, (previous, next) {
        next.whenData(out.add);
      });
      await pumpEventQueue();
      localGyro.add(
        GyroscopeData(x: 0.1, y: 0.1, z: 0.1, timestamp: DateTime(2026)),
      );
      await pumpEventQueue();

      Future<int> pushTwoSeconds() async {
        final before = out.length;
        for (var i = 0; i < 167; i++) {
          localClock = localClock.add(const Duration(milliseconds: 12));
          localAccel.add(
            AccelerometerData(x: 0.0, y: 0.0, z: 9.8, timestamp: localClock),
          );
          await pumpEventQueue();
        }
        return out.length - before;
      }

      final atNormal = await pushTwoSeconds();
      mode.set(PowerModeConfig.critical);
      await pumpEventQueue();
      final atCritical = await pushTwoSeconds();

      expect(
        atNormal / 2.0,
        closeTo(AppConstants.sensorSamplingRateNormal.toDouble(), 2.0),
      );
      expect(
        atCritical / 2.0,
        closeTo(AppConstants.sensorSamplingRateCritical.toDouble(), 2.0),
        reason: 'the listener, not a rebuild, is what carries the new period',
      );
    });

    test('a wall clock that jumps backwards does not stop the stream', () async {
      final emitted = <MotionData>[];
      container.listen(motionDataStreamProvider, (previous, next) {
        next.whenData(emitted.add);
      });
      await pumpEventQueue();

      gyroController.add(
        GyroscopeData(x: 0.1, y: 0.1, z: 0.1, timestamp: DateTime(2026)),
      );
      await pushAccel(
        AccelerometerData(x: 0.0, y: 0.0, z: 9.8, timestamp: clock),
      );
      expect(emitted, hasLength(1));

      // An NTP correction pulls the wall clock two seconds back. Pacing from a
      // slot that is now in the future would refuse every sample until the
      // clock caught up: two seconds of silent detection death, with `hb.mn`
      // reading zero and nothing in the log saying why.
      clock = clock.subtract(const Duration(seconds: 2));
      for (var i = 0; i < 5; i++) {
        clock = clock.add(const Duration(milliseconds: 21));
        accelController.add(
          AccelerometerData(x: 0.0, y: 0.0, z: 9.8, timestamp: clock),
        );
        await pumpEventQueue();
      }

      expect(emitted.length, greaterThan(1));
    });

    test('the drops are counted so the OS rate stays measurable', () async {
      motionRateHold.takeDropped();
      addTearDown(motionRateHold.takeDropped);

      container.listen(motionDataStreamProvider, (previous, next) {
        next.whenData((_) {});
      });
      await pumpEventQueue();
      gyroController.add(
        GyroscopeData(x: 0.1, y: 0.1, z: 0.1, timestamp: DateTime(2026)),
      );
      await pumpEventQueue();

      var emitted = 0;
      container.listen(motionDataStreamProvider, (previous, next) {
        next.whenData((_) => emitted++);
      });
      for (var i = 0; i < 167; i++) {
        clock = clock.add(const Duration(milliseconds: 12));
        accelController.add(
          AccelerometerData(x: 0.0, y: 0.0, z: 9.8, timestamp: clock),
        );
        await pumpEventQueue();
      }

      // `hb.mn` is counted downstream of the drop, so without `dr` the log
      // could no longer say what the OS delivered — the comparison that found
      // L-086.
      expect(motionRateHold.dropped + emitted, 167);
      expect(motionRateHold.dropped, greaterThan(0));
    });

    test('a slower power mode really slows the merged stream', () async {
      // Without the rate hold, `sensorSamplingRate` only lengthened a period
      // the OS was free to round back down: `critical` and `normal` could
      // deliver the same 55 Hz. Here the modes have to differ.
      Future<int> emittedOverTwoSeconds(PowerModeConfig mode) async {
        final localAccel = StreamController<AccelerometerData>.broadcast();
        final localGyro = StreamController<GyroscopeData>.broadcast();
        var localClock = DateTime(2026, 1, 1, 12);
        final localContainer = ProviderContainer(
          overrides: [
            accelerometerStreamProvider.overrideWith(
              (ref) => localAccel.stream,
            ),
            gyroscopeStreamProvider.overrideWith((ref) => localGyro.stream),
            motionClockProvider.overrideWith(
              (ref) =>
                  () => localClock,
            ),
            currentPowerModeProvider.overrideWith(() => _FixedPowerMode(mode)),
          ],
        );
        addTearDown(() async {
          localContainer.dispose();
          await localAccel.close();
          await localGyro.close();
        });

        final out = <MotionData>[];
        localContainer.listen(motionDataStreamProvider, (previous, next) {
          next.whenData(out.add);
        });
        await pumpEventQueue();
        localGyro.add(
          GyroscopeData(x: 0.1, y: 0.1, z: 0.1, timestamp: DateTime(2026)),
        );
        await pumpEventQueue();

        for (var i = 0; i < 167; i++) {
          localClock = localClock.add(const Duration(milliseconds: 12));
          localAccel.add(
            AccelerometerData(x: 0.0, y: 0.0, z: 9.8, timestamp: localClock),
          );
          await pumpEventQueue();
        }
        return out.length;
      }

      final normal = await emittedOverTwoSeconds(PowerModeConfig.normal);
      final critical = await emittedOverTwoSeconds(PowerModeConfig.critical);

      expect(critical, lessThan(normal));
      expect(
        critical / 2.0,
        closeTo(AppConstants.sensorSamplingRateCritical.toDouble(), 2.0),
      );
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
/// Power mode a test can change while the merged stream is running.
class _MutablePowerMode extends CurrentPowerMode {
  @override
  PowerModeConfig build() => PowerModeConfig.normal;

  void set(PowerModeConfig config) => state = config;
}

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
