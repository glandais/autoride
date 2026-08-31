import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:autoride/features/trip_detection/domain/models/trip.dart';
import 'package:autoride/features/trip_detection/domain/models/activity_confidence.dart';
import 'package:autoride/features/trip_history/data/repositories/trip_repository.dart';

part 'trip_history_provider.g.dart';

/// Trip history notifier
/// Manages the list of trips with refresh and filtering capabilities
@riverpod
class TripHistory extends _$TripHistory {
  @override
  Future<List<Trip>> build() async {
    return _loadTrips();
  }

  /// Load all trips from repository
  Future<List<Trip>> _loadTrips({
    ActivityType? filterActivity,
    bool? confirmedOnly,
  }) async {
    final repository = await ref.read(tripRepositoryProvider.future);

    if (confirmedOnly == true) {
      return repository.getConfirmedTrips();
    }

    if (filterActivity != null) {
      return repository.getTripsByActivity(filterActivity);
    }

    return repository.getAllTrips(orderBy: 'start_time DESC');
  }

  /// Refresh trip list
  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _loadTrips());
  }

  /// Filter trips by activity type
  Future<void> filterByActivity(ActivityType? activity) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _loadTrips(filterActivity: activity));
  }

  /// Show only confirmed trips
  Future<void> showConfirmedOnly() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _loadTrips(confirmedOnly: true));
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
    '', 'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December'
  ];
  return '${months[date.month]} ${date.day}, ${date.year}';
}
