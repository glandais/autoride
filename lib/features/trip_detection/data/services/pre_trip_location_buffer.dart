import '../../domain/models/location_data.dart';
import '../../../../core/constants/app_constants.dart';

/// One retained fix plus the instant it was received.
///
/// The reception time, not `location.timestamp`, is what ages the buffer: a fix
/// replayed from a plugin cache (or one carrying a skewed device clock) must not
/// be able to evict the rest of the window, and the tests drive the ageing with
/// an injected clock. The *timestamp* is still what ends up on the route point.
class _BufferedFix {
  const _BufferedFix(this.receivedAt, this.location);

  final DateTime receivedAt;
  final LocationData location;
}

/// Bounded buffer of the GPS fixes received while the gate was open but no trip
/// was recording yet.
///
/// Why it exists: the coordinator opens the GPS gate on the first moving sample,
/// but the trip is only confirmed a few seconds later — three consecutive
/// detections, up to `detectionTimeoutSeconds` of `Detecting` — and the recorder
/// then opens its *own* location subscription and starts counting distance from
/// its second fix. Everything in between used to be thrown away, so every ride
/// began 10-40 s and 50-200 m after the rider actually set off. This buffer is
/// what gets replayed into the recorder at `startRecording` (L-076).
///
/// Deliberately plain Dart, like `StationaryWindow`: mutable scratch state owned
/// by `TripDetectionCoordinator`, not part of any observable state, and directly
/// unit-testable on its own.
class PreTripLocationBuffer {
  final List<_BufferedFix> _fixes = <_BufferedFix>[];

  /// Number of fixes currently retained.
  int get length => _fixes.length;

  bool get isEmpty => _fixes.isEmpty;

  bool get isNotEmpty => _fixes.isNotEmpty;

  /// The retained fixes, oldest first.
  List<LocationData> get locations =>
      _fixes.map((fix) => fix.location).toList(growable: false);

  /// Add [location], received at [now], and enforce both bounds.
  void add(LocationData location, DateTime now) {
    _fixes.add(_BufferedFix(now, location));

    final cutoff = now.subtract(AppConstants.preTripLocationBufferDuration);
    _fixes.removeWhere((fix) => fix.receivedAt.isBefore(cutoff));

    if (_fixes.length > AppConstants.preTripLocationBufferMaxPoints) {
      _fixes.removeRange(
        0,
        _fixes.length - AppConstants.preTripLocationBufferMaxPoints,
      );
    }
  }

  void clear() => _fixes.clear();

  /// The part of the buffer that is worth prefixing onto the trip.
  ///
  /// See [ridingTailOf].
  List<LocationData> get ridingTail => ridingTailOf(locations);

  /// The suffix of [fixes] starting at the first one moving at least
  /// [AppConstants.cyclingSpeedMin], or an empty list if none is.
  ///
  /// The gate opens on *any* movement, walking included, so the raw buffer
  /// routinely starts with the approach to the bike — fixes that would put the
  /// trip's origin at the front door and inflate its distance with a walk. The
  /// first fix at cycling speed is where the ride demonstrably began, so
  /// everything from there on is kept and everything before it is dropped.
  ///
  /// The *tail* is kept whole rather than filtering fix by fix: once rolling, a
  /// legitimate slow moment (a junction, a hill, a red light a few seconds after
  /// setting off) is part of the ride, and cutting those out would break the
  /// route into disconnected jumps.
  ///
  /// Returns an empty list when nothing reached cycling speed — a walk that
  /// happened to trip the detector prefixes nothing, and the trip starts at
  /// confirmation exactly as it did before.
  static List<LocationData> ridingTailOf(List<LocationData> fixes) {
    final start = fixes.indexWhere(
      (fix) => fix.speedKmh >= AppConstants.cyclingSpeedMin,
    );
    if (start < 0) return const <LocationData>[];
    return fixes.sublist(start);
  }
}
