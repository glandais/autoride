import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:autoride/features/trip_detection/domain/models/trip.dart';
import 'package:autoride/features/trip_history/data/repositories/trip_repository.dart';

part 'trip_detail_provider.g.dart';

/// Trip detail provider
/// Loads a single trip with its route points by ID
@riverpod
Future<Trip> tripDetail(Ref ref, int tripId) async {
  final repository = await ref.watch(tripRepositoryProvider.future);
  final trip = await repository.getTripById(tripId);

  if (trip == null) {
    throw TripNotFoundException('Trip with ID $tripId not found');
  }

  return trip;
}

/// Trip route points provider
/// Loads only the route points for a trip (alternative to loading full trip)
@riverpod
Future<List<RoutePoint>> tripRoutePoints(Ref ref, int tripId) async {
  final repository = await ref.watch(tripRepositoryProvider.future);
  return repository.getRoutePoints(tripId);
}

/// Exception thrown when a trip is not found
class TripNotFoundException implements Exception {
  TripNotFoundException(this.message);

  final String message;

  @override
  String toString() => 'TripNotFoundException: $message';
}
