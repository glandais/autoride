import '../../domain/models/location_data.dart';
import '../../../../core/constants/app_constants.dart';

/// Watches a recording for the one thing that separates a car from a bicycle.
///
/// **Why speed, and only speed.** The motion window the trip-start fit uses
/// (T050) cannot tell the two apart, and that is measured, not assumed: over
/// the 2026-09-07 log, replaying the fit across the `win` statistics of a real
/// ride and of a drive to the shops gives a mean motion score of **0.331 and
/// 0.298**, with 23.0 % and 22.6 % of windows above the confidence threshold.
/// Every percentile of the acceleration spread matches to two digits. A car
/// with a phone in it shakes exactly like a bicycle with a phone on it, so no
/// accelerometer threshold can ever refuse one without refusing the other.
///
/// What differs is how fast it goes, and for how long.
///
/// **Why only *provider-measured* speeds count.** The derived speed T048 adds
/// (`dsp`) is computed from the displacement between two fixes, so it inherits
/// their accuracy: on the same log, every reading above 40 km/h during the
/// *bicycle* ride is a derived one from a fix accurate to 23–38 m — 55.7, 54.6,
/// 52.4 km/h on a night ride that averaged 16.8. The car's evidence is the
/// opposite kind: `sp` reported by the OS itself, accurate to 3.5 m, five
/// consecutive fixes at 38.0 / 38.0 / 37.9 / 39.3 / 39.2. Feeding derived
/// speeds to this rule would discard real rides on GPS noise, which is the one
/// outcome worse than recording a drive.
///
/// So a fix is *evidence* here only when it carries a measured speed
/// ([LocationData.hasReportedSpeed]) and is accurate enough for that speed to
/// be believed — the same predicate the start path uses.
///
/// **Two arms, one statistic.** [isVehicleNow] is the live one: enough of the
/// last few pieces of evidence are above the threshold, over a span long enough
/// not to be one burst of noise. [looksLikeVehicle] is the end-of-ride one,
/// over everything the trip saw — it catches a drive whose speed bursts arrived
/// too far apart for the rolling window, and it is what the discard decision
/// reads.
///
/// Deliberately plain Dart, like [StationaryWindow] and `PreTripLocationBuffer`:
/// mutable scratch state owned by `TripRecorderService`, directly unit-testable.
class VehicleSpeedWatch {
  final List<_SpeedSample> _recent = <_SpeedSample>[];

  int _measured = 0;
  int _above = 0;
  bool _fired = false;

  /// Fixes that carried a believable measured speed, over the whole recording.
  int get measuredFixes => _measured;

  /// How many of those were above [AppConstants.vehicleSpeedKmh].
  int get vehicleFixes => _above;

  /// Whether the live arm has already fired during this recording.
  bool get hasFired => _fired;

  /// Offer [fix] to the watch. Fixes with no believable measured speed are not
  /// evidence either way and are ignored, not counted as slow.
  ///
  /// The window is spanned by the fixes' **own** timestamps, unlike
  /// `PreTripLocationBuffer`, which ages by reception time so a replayed cache
  /// cannot evict a window. The question here is different: over what period
  /// were these speeds *measured*. A fix that carries a measured speed and an
  /// accuracy under `speedTrustMaxAccuracyMeters` is a real GNSS fix, so its
  /// timestamp is satellite-disciplined — and a burst served from a cache
  /// shares old timestamps, which shrinks the span and is refused.
  void add(LocationData fix) {
    if (!fix.hasReportedSpeed) return;
    if (!fix.accuracy.isFinite ||
        fix.accuracy > AppConstants.speedTrustMaxAccuracyMeters) {
      return;
    }

    _measured++;
    final fast = fix.speedKmh >= AppConstants.vehicleSpeedKmh;
    if (fast) _above++;

    _recent.add(_SpeedSample(fix.timestamp, fast));
    if (_recent.length > AppConstants.vehicleSpeedWindowFixes) {
      _recent.removeRange(
        0,
        _recent.length - AppConstants.vehicleSpeedWindowFixes,
      );
    }

    if (isVehicleNow) _fired = true;
  }

  /// Whether the last few pieces of evidence say "this is a vehicle" *now*.
  ///
  /// Three conditions, and all three are needed:
  ///
  /// * at least [AppConstants.vehicleSpeedMinFixes] of the retained fixes are
  ///   above the threshold — one is a GPS artefact, four is a road;
  /// * they span at least [AppConstants.vehicleSustainSeconds] of wall clock,
  ///   so a burst of fixes 200 ms apart cannot satisfy the count on its own;
  /// * the window is full enough to have a majority in it at all.
  bool get isVehicleNow {
    if (_recent.length < AppConstants.vehicleSpeedMinFixes) return false;

    final fast = _recent.where((s) => s.fast).toList(growable: false);
    if (fast.length < AppConstants.vehicleSpeedMinFixes) return false;

    final span = fast.last.at.difference(fast.first.at);
    return span >= AppConstants.vehicleSustainSeconds;
  }

  /// Whether the recording as a whole was made in a vehicle.
  ///
  /// The live arm having fired is sufficient — it is the stronger evidence, and
  /// it is what stopped the ride. Otherwise the whole-trip shape has to say it:
  /// enough fast fixes *and* a large enough share of the evidence, because a
  /// long ride accumulates four artefacts eventually while a short drive does
  /// not have many fixes to begin with.
  ///
  /// A recording with no measured speed at all — the case on an Android phone
  /// whose provider reports 0 throughout (L-088), and on the 2026-09-06 iPhone
  /// ride — answers **false**: no evidence is not evidence.
  bool get looksLikeVehicle {
    if (_fired) return true;
    if (_above < AppConstants.vehicleSpeedMinFixes) return false;
    return _above >= _measured * AppConstants.vehicleSpeedMinShare;
  }

  void reset() {
    _recent.clear();
    _measured = 0;
    _above = 0;
    _fired = false;
  }
}

class _SpeedSample {
  const _SpeedSample(this.at, this.fast);

  final DateTime at;
  final bool fast;
}
