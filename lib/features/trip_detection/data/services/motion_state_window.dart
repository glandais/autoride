import '../../domain/models/motion_data.dart';
import '../../../../core/constants/app_constants.dart';

/// Sliding time window over recent motion samples, reduced to a single
/// [MotionState].
///
/// Why a window at all: the GPS gate used to classify one *isolated* sample per
/// call, which at the sensor rate makes the verdict flap between `stationary`
/// and `moving` on nothing but sensor noise. Each flap to `moving` cancels the
/// gate's inactivity timer and each flap back re-arms it, so the 30 s stationary
/// timeout only ever elapses if not a single noisy sample lands in the whole
/// half-minute — and GPS stays on. A T043 log caught it: 93 `gate sched` lines
/// for one `gate close` on a phone lying still on a table.
///
/// Averaging over [AppConstants.stationaryWindowDuration] is what separates
/// "the phone twitched" from "the bike is rolling". The verdict itself stays in
/// `MotionWindow.state` — this class only owns the retention.
///
/// Deliberately plain Dart (no Riverpod, no freezed), like `StationaryWindow`
/// which it mirrors: mutable scratch state owned by its holder, directly
/// unit-testable. It keeps whole [MotionData] values rather than scalars
/// because `MotionWindow.state` needs both magnitudes and the classification
/// thresholds that go with them.
class MotionStateWindow {
  final List<MotionData> _samples = <MotionData>[];

  /// Reception instants, parallel to [_samples]: ageing runs on when a sample
  /// was *seen*, not on the timestamp it carries.
  final List<DateTime> _seenAt = <DateTime>[];

  /// Number of samples currently retained.
  int get length => _samples.length;

  bool get isEmpty => _samples.isEmpty;

  /// Motion state averaged over the retained samples, or [MotionState.unknown]
  /// while the window is empty — which is exactly what the gate reads as "not
  /// enough information to change anything".
  MotionState get state {
    if (_samples.isEmpty) return MotionState.unknown;

    return MotionWindow(
      samples: _samples,
      startTime: _seenAt.first,
      endTime: _seenAt.last,
    ).state;
  }

  /// Add [motion], stamped with the evaluation time [now], and drop everything
  /// older than [AppConstants.stationaryWindowDuration].
  ///
  /// [now] rather than `motion.timestamp` is used for ageing so tests can drive
  /// the window deterministically with injected timestamps.
  void add(MotionData motion, DateTime now) {
    _samples.add(motion);
    _seenAt.add(now);

    final cutoff = now.subtract(AppConstants.stationaryWindowDuration);
    var expired = 0;
    while (expired < _seenAt.length && _seenAt[expired].isBefore(cutoff)) {
      expired++;
    }

    // Belt and braces: an unexpectedly high sample rate (or a clock that never
    // advances) must not grow the buffer without bound.
    final overflow = _samples.length - AppConstants.stationaryWindowMaxSamples;
    final drop = expired > overflow ? expired : overflow;
    if (drop > 0) {
      _samples.removeRange(0, drop);
      _seenAt.removeRange(0, drop);
    }
  }

  void clear() {
    _samples.clear();
    _seenAt.clear();
  }
}
