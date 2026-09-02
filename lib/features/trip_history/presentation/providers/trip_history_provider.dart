import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:autoride/features/trip_detection/domain/models/trip.dart';
import 'package:autoride/features/trip_history/data/repositories/trip_repository.dart';
import 'package:autoride/features/trip_history/domain/models/trip_filter.dart';
import 'package:autoride/features/trip_history/presentation/providers/trip_filter_provider.dart';

part 'trip_history_provider.g.dart';

/// Trip history notifier
/// Manages the list of trips with refresh and filtering capabilities
@riverpod
class TripHistory extends _$TripHistory {
  @override
  Future<List<Trip>> build() async {
    // Watched, not read: changing the filter is what reloads the list.
    return _loadTrips(ref.watch(tripFilterControllerProvider));
  }

  /// Load the trips matching [filter], most recent first.
  ///
  /// The date window is pushed down to SQL — it is the criterion that can
  /// discard most of the table — and the remaining criteria are applied in
  /// memory, because they compose and the repository's single-criterion
  /// queries do not.
  Future<List<Trip>> _loadTrips(TripFilter filter) async {
    final repository = await ref.read(tripRepositoryProvider.future);

    final now = DateTime.now();
    final from = filter.startBoundary(now);

    final trips = from == null
        ? await repository.getAllTrips(orderBy: 'start_time DESC')
        : await repository.getTripsByDateRange(startDate: from, endDate: now);

    return trips.where(filter.matches).toList();
  }

  /// Refresh trip list
  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
      () => _loadTrips(ref.read(tripFilterControllerProvider)),
    );
  }

  /// Delete a trip and refresh the list
  Future<void> deleteTrip(int tripId) async {
    try {
      final repository = await ref.read(tripRepositoryProvider.future);
      await repository.deleteTrip(tripId);

      // Refresh list after deletion
      await refresh();
    } catch (e) {
      // Error will be caught by AsyncValue.guard in refresh()
      rethrow;
    }
  }

  /// Confirm a trip and refresh the list
  Future<void> confirmTrip(int tripId) async {
    try {
      final repository = await ref.read(tripRepositoryProvider.future);
      await repository.confirmTrip(tripId);

      // Refresh list after confirmation
      await refresh();
    } catch (e) {
      rethrow;
    }
  }
}

/// Trip count provider
/// Provides the total number of trips
// TODO(T031): no consumer in lib/ - the history screen renders a plain list and
// no summary/statistics UI reads this yet. Same for `totalDistance` and
// `tripsGroupedByDate` below.
@riverpod
Future<int> tripCount(Ref ref) async {
  final repository = await ref.watch(tripRepositoryProvider.future);
  return repository.getTripCount();
}

/// Total distance provider
/// Provides the total distance across all trips
@riverpod
Future<double> totalDistance(Ref ref) async {
  final repository = await ref.watch(tripRepositoryProvider.future);
  return repository.getTotalDistance();
}

/// Trip list grouped by date
/// Helper provider to organize trips by date for UI display
@riverpod
Future<Map<String, List<Trip>>> tripsGroupedByDate(Ref ref) async {
  final trips = await ref.watch(tripHistoryProvider.future);

  final Map<String, List<Trip>> grouped = {};

  for (final trip in trips) {
    final dateKey = _getDateLabel(trip.startTime);
    if (!grouped.containsKey(dateKey)) {
      grouped[dateKey] = [];
    }
    grouped[dateKey]!.add(trip);
  }

  return grouped;
}

/// Helper function to generate date labels for grouping
String _getDateLabel(DateTime date) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final yesterday = today.subtract(const Duration(days: 1));
  final tripDate = DateTime(date.year, date.month, date.day);

  if (tripDate == today) {
    return 'Today';
  }
  if (tripDate == yesterday) {
    return 'Yesterday';
  }
  if (tripDate.isAfter(today.subtract(const Duration(days: 7)))) {
    return 'This Week';
  }

  // Format: "January 15, 2024"
  final months = [
    '',
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  return '${months[date.month]} ${date.day}, ${date.year}';
}
