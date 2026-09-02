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
Duration _samplingPeriodFor(Ref ref) =>
    _periodForRate(ref.watch(currentPowerModeProvider).sensorSamplingRate);

Duration _periodForRate(int rateHz) =>
    Duration(microseconds: (1000000 / rateHz).round());

/// Accelerometer samples [motionDataStream] dropped to hold the configured
/// rate, read and reset by the coordinator's heartbeat.
///
/// Process-wide and outside Riverpod, like [batteryAuditThrottle]: the sensor
/// providers rebuild on every power-mode change and the counter has to outlive
/// that, and the reader is a different provider from the writer.
class MotionRateHold {
  int dropped = 0;

  /// The drops since the last call, and zero the counter.
  int takeDropped() {
    final n = dropped;
    dropped = 0;
    return n;
  }
}

/// The process-wide rate-hold counter. See [MotionRateHold].
final MotionRateHold motionRateHold = MotionRateHold();

/// The clock [motionDataStream] paces itself on.
///
/// A provider purely so a test can hold the pacing to an injected timeline:
/// wall-clock milliseconds are exactly what the rate hold measures, and a test
/// that pushed samples as fast as the event loop allows would otherwise see
/// them dropped as a burst.
@riverpod
DateTime Function() motionClock(Ref ref) => DateTime.now;

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
/// Halving the merged rate did not *set* it: the accelerometer still ran at
/// whatever the OS granted for the requested period — 55.6 Hz backgrounded and
/// 83 Hz foregrounded on a Pixel 6a against a configured 50, 51.4 Hz on an
/// iPhone (L-086). So this provider now **holds the merged stream to the
/// configured rate itself** (T045), dropping the surplus accelerometer samples.
///
/// Two reasons, and the second is the important one:
///
/// * every sample costs a full pass through the coordinator — window insert,
///   GPS-gate evaluation, detector, audit throttling — so 83 Hz foregrounded is
///   two thirds more of that work than the power mode asked for;
/// * without it `PowerModeConfig.sensorSamplingRate` is decorative. Dropping
///   from 50 Hz in `normal` to 20 Hz in `critical` only lengthens a *requested*
///   period, and an OS that rounds it to its own supported rate can hand back
///   55 Hz in either mode. Enforcing the rate here is what makes the whole
///   battery-mode ladder change anything the pipeline can feel.
///
/// Nothing downstream counts samples: the stationary and motion windows average
/// over `stationaryWindowDuration` and age on wall time, and the detectors count
/// one detection per `detectionEvaluationInterval` whatever the sample rate.
/// `stationaryWindowMaxSamples` (128) was in fact being *approached* at 83 Hz
/// over a 1.5 s window, and is now comfortably clear.
///
/// What it does change, and this is the risk to carry into the next device run:
/// in `critical` mode the configured 20 Hz becomes real for the first time, so
/// that same window holds ~30 samples instead of ~83 and its Nyquist limit
/// drops to 10 Hz — while `accelerationStdDev`, the quantity the stationary
/// verdict is built on, is measuring exactly the high-frequency vibration of a
/// rolling bike. 20 Hz has never been validated on a device. A control run in
/// `critical` is what would close that.
///
/// `hb` stays the measurement of record: `mn` counts what the coordinator
/// received, `dr` what this hold dropped, and `(mn + dr) / (dt / 1000)` is what
/// the OS actually delivered against the `hz` that was asked for. Without `dr`
/// this change would have blinded the very instrument that found L-086.
@riverpod
Stream<MotionData> motionDataStream(Ref ref) {
  final controller = StreamController<MotionData>();

  GyroscopeData? lastGyro;

  // Read rather than watched: watching would rebuild this provider (and close
  // the controller under its subscribers) on every power-mode change, where
  // today only the sensor providers beneath it rebuild and the merged stream
  // survives.
  final clock = ref.read(motionClockProvider);
  var period = _periodForRate(
    ref.read(currentPowerModeProvider).sensorSamplingRate,
  );
  ref.listen(currentPowerModeProvider, (previous, next) {
    period = _periodForRate(next.sensorSamplingRate);
  });

  /// Start of the next sampling slot. Scheduling from the *slot* rather than
  /// from the sample that filled it is what makes the long-run average equal
  /// the configured rate: from an 18 ms source against a 20 ms period, resetting
  /// to "now" on every emit would compound the 2 ms of lateness and halve the
  /// rate to 27 Hz.
  DateTime? nextSlot;

  bool dueAt(DateTime now) {
    final slot = nextSlot;
    if (slot != null && now.isBefore(slot)) {
      // Unless the slot is further ahead than one period can explain, which
      // only a **backwards** wall clock can produce — an NTP correction, a
      // manual time change. Without this the pacer would refuse every sample
      // until the clock caught up again: minutes of silent detection death,
      // with `hb.mn` reading zero and nothing saying why. (`clk` already
      // journals a drift of more than 2 s, so the case is not hypothetical.)
      if (slot.difference(now) <= period) return false;
      nextSlot = now.add(period);
      return true;
    }

    // A slot more than one period behind means the stream stopped and started
    // again — the process was suspended, or the sensor providers rebuilt. Catch
    // up from `now` instead of firing a burst to make up the lost slots.
    final base = (slot == null || now.difference(slot) > period) ? now : slot;
    nextSlot = base.add(period);
    return true;
  }

  void emit(AccelerometerData accel) {
    final gyro = lastGyro;
    // Nothing to pair with yet: the first accelerometer samples of a session
    // arrive before the gyroscope has produced anything.
    if (gyro == null || controller.isClosed) return;

    final now = clock();
    if (!dueAt(now)) {
      // Counted, because `hb.mn` is taken downstream of this drop: without it
      // `mn / (dt / 1000)` would read `hz` for ever and the measurement that
      // found L-086 in the first place — what the OS really delivers against
      // what was asked — would be gone.
      motionRateHold.dropped++;
      return;
    }

    controller.add(
      MotionData(accelerometer: accel, gyroscope: gyro, timestamp: now),
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
