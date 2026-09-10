import '../../domain/models/location_data.dart';
import '../../../../core/constants/app_constants.dart';

/// Accumulates the speed evidence of a recording, so a ride that was probably
/// made in a car can be **flagged** (T053, L-106).
///
/// **This class decides nothing any more.** It answers one question —
/// [looksLikeVehicle] — and the only thing that reads it is
/// `Trip.suspectedVehicle`, which paints a badge in History. It cannot end a
/// recording and it cannot discard one.
///
/// **Why it lost that power.** T051 gave it a live arm because the motion fit
/// cannot tell a car from a bicycle: replayed over the 2026-09-07 log, a real
/// ride and a drive to the shops score **0.331 and 0.298**, with every
/// percentile of the acceleration spread matching to two digits. Speed looked
/// like the axis that separated them. It is not:
///
/// | recording | measured | >= 35 km/h | share | max |
/// |---|---|---|---|---|
/// | the 2026-09-07 drive | 37 | 10 | 27.0 % | **39.3** |
/// | 2026-09-09 morning commute | 42 | 6 | 14.3 % | 39.9 |
/// | sporting ride #1 | 354 | 98 | **27.7 %** | 46.7 |
/// | sporting ride #2 | 2 800 | 1 554 | **55.5 %** | **59.9** |
///
/// The drive has the **lowest maximum in the corpus**, and its share is
/// indistinguishable from a real ride's. A town car is slow with bursts; a
/// sporting cyclist is fast continuously. On 2026-09-09 the live arm deleted
/// **71.8 km** of real rides, one of them cut into seven fragments first, and
/// the Karoo files recorded alongside say the app had measured every metre of
/// them correctly.
///
/// So the thresholds below over-flag a fast rider by construction, and that is
/// accepted: the cost of a badge is not the cost of a ride. **They are not to
/// be recalibrated** — the mode of travel will be classified from the inertial
/// unit (the T034 capture feeding a model), not from a speed.
///
/// **Why only *provider-measured* speeds count.** The derived speed T048 adds
/// (`dsp`) is computed from the displacement between two fixes, so it inherits
/// their accuracy: on the 2026-09-06 log, every reading above 40 km/h during
/// the *bicycle* ride is a derived one from a fix accurate to 23-38 m — 55.7,
/// 54.6, 52.4 km/h on a night ride that averaged 16.8. Feeding those here would
/// flag real rides on GPS noise. So a fix is evidence only when it carries a
/// measured speed ([LocationData.hasReportedSpeed]) and is accurate enough for
/// that speed to be believed — the same predicate the start path uses.
///
/// Deliberately plain Dart, like [StationaryWindow] and `PreTripLocationBuffer`:
/// mutable scratch state owned by `TripRecorderService`, directly unit-testable.
class VehicleSpeedWatch {
  int _measured = 0;
  int _above = 0;

  /// Fixes that carried a believable measured speed, over the whole recording.
  /// Reported as `vmf` on every trip ending.
  int get measuredFixes => _measured;

  /// How many of those were at or above [AppConstants.vehicleSpeedKmh].
  /// Reported as `vfx` on every trip ending.
  int get vehicleFixes => _above;

  /// Offer [fix] to the watch. Fixes with no believable measured speed are not
  /// evidence either way and are ignored, not counted as slow.
  void add(LocationData fix) {
    if (!fix.hasReportedSpeed) return;
    if (!fix.accuracy.isFinite ||
        fix.accuracy > AppConstants.speedTrustMaxAccuracyMeters) {
      return;
    }

    _measured++;
    if (fix.speedKmh >= AppConstants.vehicleSpeedKmh) _above++;
  }

  /// Whether the recording as a whole was probably made in a vehicle.
  ///
  /// Enough fast fixes *and* a large enough share of the evidence, because a
  /// long ride accumulates four artefacts eventually while a short drive does
  /// not have many fixes to begin with.
  ///
  /// A recording with no measured speed at all — the case on an Android phone
  /// whose provider reports 0 throughout (L-088), and on the 2026-09-06 iPhone
  /// ride — answers **false**: no evidence is not evidence.
  bool get looksLikeVehicle {
    if (_above < AppConstants.vehicleSpeedMinFixes) return false;
    return _above >= _measured * AppConstants.vehicleSpeedMinShare;
  }

  void reset() {
    _measured = 0;
    _above = 0;
  }
}
