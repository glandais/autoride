import 'dart:math' as math;

import '../../domain/models/motion_data.dart';
import '../../../../core/constants/app_constants.dart';

/// One retained sensor reading, reduced to the two scalars the stationary
/// verdict needs. Keeping the scalars (rather than the whole [MotionData])
/// keeps the buffer small: at 50 Hz a 1.5 s window holds ~75 entries.
class _WindowSample {
  const _WindowSample(this.time, this.accelerationMagnitude, this.rotation);

  final DateTime time;
  final double accelerationMagnitude;
  final double rotation;
}

/// Sliding time window over recent motion samples, used to decide whether the
/// rider is standing still.
///
/// Why a window at all: the stop detector used to test a *single* 50 Hz sample
/// against instantaneous thresholds (|accel − g| ≤ 1 m/s² AND gyro ≤
/// 0.2 rad/s). With the phone carried in a pocket or a pannier that test
/// almost never holds — the body sways, the bag settles — so a stopped rider
/// read as "moving", auto-pause practically never fired and the 5-minute
/// auto-stop was unreachable. Averaging over ~1.5 s separates "the phone
/// wobbles a bit while the bike is at a standstill" from "the bike is rolling".
///
/// The window is deliberately plain Dart (no Riverpod, no freezed): it is
/// mutable scratch state owned by `TripStopDetector`, not part of its
/// observable state, and it is directly unit-testable on its own.
class StationaryWindow {
  final List<_WindowSample> _samples = <_WindowSample>[];

  /// Number of samples currently retained.
  int get length => _samples.length;

  bool get isEmpty => _samples.isEmpty;

  /// Add [motion], stamped with the evaluation time [now], and drop everything
  /// older than [AppConstants.stationaryWindowDuration].
  ///
  /// [now] rather than `motion.timestamp` is used for ageing so tests can drive
  /// the window deterministically with injected timestamps.
  void add(MotionData motion, DateTime now) {
    _samples.add(
      _WindowSample(
        now,
        motion.accelerometer.magnitude,
        motion.gyroscope.magnitude,
      ),
    );

    final cutoff = now.subtract(AppConstants.stationaryWindowDuration);
    _samples.removeWhere((sample) => sample.time.isBefore(cutoff));

    // Belt and braces: an unexpectedly high sample rate (or a clock that never
    // advances) must not grow the buffer without bound.
    if (_samples.length > AppConstants.stationaryWindowMaxSamples) {
      _samples.removeRange(
        0,
        _samples.length - AppConstants.stationaryWindowMaxSamples,
      );
    }
  }

  /// Population standard deviation of the accelerometer magnitude over the
  /// window.
  ///
  /// Standard deviation rather than the mean, because the mean is dominated by
  /// gravity (~9.8 m/s²) in every orientation, while the *spread* is exactly
  /// the vibration a rolling bike produces. A single retained sample yields 0
  /// by definition — that is intentional: with no spread information the
  /// rotation criterion below is what decides.
  double get accelerationStdDev {
    if (_samples.length < 2) return 0.0;

    final mean =
        _samples.fold<double>(0.0, (sum, s) => sum + s.accelerationMagnitude) /
        _samples.length;
    final variance =
        _samples.fold<double>(0.0, (sum, s) {
          final delta = s.accelerationMagnitude - mean;
          return sum + delta * delta;
        }) /
        _samples.length;

    return math.sqrt(variance);
  }

  /// Mean gyroscope magnitude over the window (rad/s).
  double get averageRotation {
    if (_samples.isEmpty) return 0.0;
    return _samples.fold<double>(0.0, (sum, s) => sum + s.rotation) /
        _samples.length;
  }

  /// Whether the retained samples look like a device that is not travelling.
  ///
  /// Both criteria must hold: little acceleration spread AND little average
  /// rotation. See [AppConstants.stationaryAccelerationStdDevMax] and
  /// [AppConstants.stationaryRotationAverageMax] for the values and why.
  bool get isCalm =>
      accelerationStdDev <= AppConstants.stationaryAccelerationStdDevMax &&
      averageRotation <= AppConstants.stationaryRotationAverageMax;

  /// Whether the acceleration spread alone looks stationary.
  ///
  /// Used when a fresh GPS fix already says the bike is not moving: a phone can
  /// rotate freely in a pocket at a red light, so the rotation criterion is
  /// dropped in that case, but sustained vibration would still contradict the
  /// fix.
  bool get isVibrationFree =>
      accelerationStdDev <= AppConstants.stationaryAccelerationStdDevMax;

  void clear() => _samples.clear();
}
