import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:autoride/features/trip_detection/domain/models/activity_confidence.dart';
import 'package:autoride/features/trip_detection/domain/models/trip.dart';

part 'trip_filter.freezed.dart';

/// Time window the history list is restricted to.
enum TripDateRange {
  all,
  today,
  thisWeek,
  thisMonth;

  String get label => switch (this) {
    TripDateRange.all => 'All time',
    TripDateRange.today => 'Today',
    TripDateRange.thisWeek => 'Last 7 days',
    TripDateRange.thisMonth => 'Last 30 days',
  };
}

/// The criteria the trip history list is narrowed by.
///
/// The default value — every field unset — means "show everything", which is
/// what makes [TripFilterExtensions.isActive] the single test for whether the
/// list the user is looking at is a filtered one.
@freezed
sealed class TripFilter with _$TripFilter {
  const TripFilter._();

  const factory TripFilter({
    ActivityType? activity,
    @Default(false) bool confirmedOnly,
    @Default(TripDateRange.all) TripDateRange dateRange,
  }) = _TripFilter;
}

extension TripFilterExtensions on TripFilter {
  /// Whether anything is being filtered out.
  bool get isActive =>
      activity != null || confirmedOnly || dateRange != TripDateRange.all;

  /// How many criteria are set, for the badge on the filter button.
  int get activeCriteriaCount =>
      (activity != null ? 1 : 0) +
      (confirmedOnly ? 1 : 0) +
      (dateRange != TripDateRange.all ? 1 : 0);

  /// Oldest start time to keep, or `null` for [TripDateRange.all].
  ///
  /// Taken relative to [now] rather than to `DateTime.now()` so the boundary
  /// is testable, and so a single list load uses one consistent clock.
  DateTime? startBoundary(DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    return switch (dateRange) {
      TripDateRange.all => null,
      TripDateRange.today => today,
      TripDateRange.thisWeek => today.subtract(const Duration(days: 7)),
      TripDateRange.thisMonth => today.subtract(const Duration(days: 30)),
    };
  }

  /// Whether [trip] passes the non-date criteria.
  ///
  /// The date window is applied by the query instead (see `startBoundary`), so
  /// this deliberately ignores it.
  bool matches(Trip trip) {
    if (activity != null && trip.detectedActivity != activity) return false;
    if (confirmedOnly && !trip.userConfirmed) return false;
    return true;
  }
}
