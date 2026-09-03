import '../../domain/models/location_data.dart';
import '../../../../core/constants/app_constants.dart';

/// Fills in the speed a location provider failed to report, from the
/// displacement between consecutive fixes (T048, L-087).
///
/// Why it exists: `LocationData.fromPosition` copies `position.speed` straight
/// through, and on the 2026-09-03 ride iOS reported exactly 0 on 192 of the 219
/// fixes of a 19 km/h outing. A zero is not "standing still" there, it is the
/// absence of a measurement — but everything downstream read it as a
/// measurement, and two of them acted on it:
///
/// * trip-start confidence, where a fix scoring `speedScore` 0 caps the total
///   at 0.60 against a 0.7 threshold and vetoes a genuine departure;
/// * the pre-trip buffer's riding-tail cut, which looks for the first fix at
///   `cyclingSpeedMin` and found none in a buffer that held the whole
///   departure — which is why that trip's back-date recovered 3 s instead of
///   the 1.3 km already ridden.
///
/// Deliberately plain Dart, like `PreTripLocationBuffer`: mutable scratch state
/// owned by `TripDetectionCoordinator`, not part of any observable state, and
/// directly unit-testable.
///
/// It refuses far more often than it derives. Two accurate fixes far enough
/// apart to have moved beyond their own noise are the only case where the
/// quotient means anything; the 2026-09-03 Pixel — whose consecutive 300 m
/// network fixes walk backwards along the road — must produce nothing at all,
/// and does.
class GpsSpeedEstimator {
  LocationData? _previous;

  /// The last fix seen, whatever came of it.
  LocationData? get previous => _previous;

  /// Forget the position history.
  ///
  /// Called when the GPS gate closes or errors: after such a gap the next fix
  /// has no continuity with this one, and a displacement measured across the
  /// gap describes a journey, not a speed. The `maxGap` bound would reject most
  /// of those anyway; this makes it certain rather than probable.
  void reset() => _previous = null;

  /// [fix], with a derived speed substituted when the provider reported none
  /// and the geometry supports one — otherwise [fix] unchanged.
  ///
  /// A fix that already carries a speed is returned untouched: the provider's
  /// own Doppler solution beats anything computed from two positions, and this
  /// must not second-guess it.
  ///
  /// [maxGap] comes from the power mode in force
  /// (`PowerModeConfig.derivedSpeedMaxGap`) and is not a constant: a bound at
  /// or below the interval the mode asks the OS for can never fire, which is
  /// how this class derived nothing at all on Android in its first version.
  LocationData refine(LocationData fix, {required Duration maxGap}) {
    final previous = _previous;
    _previous = fix;

    if (fix.hasReportedSpeed) return fix;

    final derived = _derivedSpeed(previous, fix, maxGap);
    if (derived == null) return fix;

    return fix.copyWith(speed: derived);
  }

  /// Speed in m/s implied by the move from [previous] to [current], or null
  /// when that move cannot support one.
  static double? _derivedSpeed(
    LocationData? previous,
    LocationData current,
    Duration maxGap,
  ) {
    if (previous == null) return null;

    // Both ends must be fixes whose *position* is worth measuring against. A
    // 300 m fix does not become informative by being subtracted from another
    // one (L-088).
    if (!previous.accuracy.isFinite || !current.accuracy.isFinite) return null;
    final worstAccuracy = previous.accuracy > current.accuracy
        ? previous.accuracy
        : current.accuracy;
    if (worstAccuracy > AppConstants.speedTrustMaxAccuracyMeters) return null;

    final gap = current.timestamp.difference(previous.timestamp);
    if (gap < AppConstants.derivedSpeedMinGap) return null;
    if (gap > maxGap) return null;

    // Movement has to be visible above the noise it is measured through,
    // otherwise two jittering fixes at a standstill invent a speed.
    final distance = current.distanceTo(previous);
    if (distance < worstAccuracy) return null;

    final speed = distance / (gap.inMilliseconds / 1000);

    // An implausible quotient means the positions were wrong, not that the
    // rider was fast. Reported as "no speed", which is what it is.
    if (speed * 3.6 > AppConstants.maxCyclingSpeedKmh) return null;

    return speed;
  }
}
