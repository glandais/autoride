import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../domain/models/location_data.dart';

part 'location_utils.g.dart';

/// Calculate distance between two locations in meters
// TODO(T041): none of the three helpers in this file has a consumer in lib/ -
// callers use `LocationData.distanceTo` and `TripMetrics`' formatting getters
// directly. Keep or fold into those once the pipeline refactor settles.
@riverpod
double distanceBetween(
  Ref ref,
  LocationData start,
  LocationData end,
) {
  return start.distanceTo(end);
}

/// Format speed for display (km/h with 1 decimal)
@riverpod
String formatSpeed(Ref ref, double speedMs) {
  final speedKmh = speedMs * 3.6;
  return '${speedKmh.toStringAsFixed(1)} km/h';
}

/// Format distance for display
@riverpod
String formatDistance(Ref ref, double meters) {
  if (meters < 1000) {
    return '${meters.toStringAsFixed(0)} m';
  } else {
    final km = meters / 1000;
    return '${km.toStringAsFixed(2)} km';
  }
}
