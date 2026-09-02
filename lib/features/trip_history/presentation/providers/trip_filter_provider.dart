import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:autoride/features/trip_history/domain/models/trip_filter.dart';

part 'trip_filter_provider.g.dart';

/// The criteria the history list is currently showing.
///
/// Held apart from `TripHistory` so the filter survives a reload of the list
/// and so the app bar can render its badge without watching the trips
/// themselves.
@riverpod
class TripFilterController extends _$TripFilterController {
  @override
  TripFilter build() => const TripFilter();

  /// Replace the whole filter (what the dialog returns).
  void apply(TripFilter filter) => state = filter;

  /// Back to showing everything.
  void clear() => state = const TripFilter();
}
