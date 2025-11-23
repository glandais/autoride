# T023 - Trip History Screen

**Status**: ⏳ In Progress
**Assignee**: Claude
**Estimated Time**: 3-4 hours
**Phase**: Phase 6 - User Interface (Task 6.1.3)

## Overview

Create a comprehensive trip history feature that allows users to view all recorded trips, see detailed statistics for individual trips, and visualize trip routes on a map.

## Dependencies

- ✅ **T010** - Trip Repository Implementation (provides data layer)
- ✅ **T020** - App Theme & Design System (provides UI components and theme)

## Objectives

1. Create a list view of all recorded trips with key statistics
2. Implement trip detail view with comprehensive stats
3. Display trip routes on an interactive map
4. Support filtering by activity type (cycling, walking, etc.)
5. Handle empty states, loading states, and errors gracefully

## Technical Requirements

### Data Layer (Already Complete)

**Available from TripRepository**:
```dart
// Fetching trips
- getAllTrips({int? limit, int? offset, String orderBy = 'start_time DESC'})
- getTripById(int id)
- getTripsByDateRange(DateTime startDate, DateTime endDate, {bool includeRoutePoints = true})
- getTripsByActivity(ActivityType activityType)
- getConfirmedTrips()

// Aggregate data
- getTripCount()
- getTotalDistance()

// Individual trip route
- getRoutePoints(int tripId)

// Modifications
- confirmTrip(int tripId)
- deleteTrip(int tripId)
- deleteAllTrips()
```

**Trip Model Properties**:
```dart
Trip {
  int? id,
  DateTime startTime,
  DateTime endTime,
  double distance,         // meters
  double duration,         // seconds
  double avgSpeed,         // m/s
  double maxSpeed,         // m/s
  ActivityType detectedActivity,
  double confidenceScore,  // 0.0-1.0
  bool userConfirmed,
  List<RoutePoint> routePoints
}

// Extension methods
trip.formattedDuration   // "HH:MM:SS"
trip.formattedDistance   // "X.XX km"
trip.isValidTrip        // duration >= 60s
```

### Files to Create

#### 1. Providers (with Riverpod code generation)

**`lib/features/trip_history/presentation/providers/trip_history_provider.dart`**
- Manage trip list state
- Support pagination and filtering
- Handle loading/error states
- Provide refresh capability

**`lib/features/trip_history/presentation/providers/trip_detail_provider.dart`**
- Load individual trip with route points
- Provide trip statistics
- Handle route data for map display

#### 2. Screens

**`lib/features/trip_history/presentation/screens/trip_history_screen.dart`**
- Main list view of all trips
- Pull-to-refresh functionality
- Date grouping (Today, Yesterday, This Week, etc.)
- Empty state for no trips
- Navigation to trip detail

**`lib/features/trip_history/presentation/screens/trip_detail_screen.dart`**
- Detailed trip statistics
- Route map visualization
- Trip metadata (start/end time, detection confidence)
- Action buttons (confirm, delete)

#### 3. Widgets

**`lib/features/trip_history/presentation/widgets/trip_list_item.dart`**
- Individual trip card for list view
- Show preview stats (distance, duration, activity type)
- Activity badge with icon
- Tap to navigate to detail

**`lib/features/trip_history/presentation/widgets/trip_detail_card.dart`**
- Comprehensive trip statistics card
- Use existing `StatCard` widgets
- Display formatted values

**`lib/features/trip_history/presentation/widgets/trip_route_map.dart`**
- Static map with trip route polyline
- Start/end markers
- Use `flutter_map` package
- Zoom controls (optional)

**`lib/features/trip_history/presentation/widgets/trip_filter_chips.dart`** (Optional)
- Filter chips for activity types
- Show trip count per type
- Toggle filtering

## Implementation Guide

### Step 1: Create Providers

**Critical Patterns** (from CLAUDE.md):
- ⚠️ Use `Ref ref`, NOT `TripHistoryRef` or other specific types
- ⚠️ Add `part 'filename.g.dart';` directive
- ⚠️ Use `@riverpod` annotation for code generation

**Trip History Provider Pattern**:
```dart
import 'package:riverpod_annotation/riverpod_annotation.dart';
part 'trip_history_provider.g.dart';

@riverpod
class TripHistory extends _$TripHistory {
  @override
  Future<List<Trip>> build() async {
    final repository = await ref.watch(tripRepositoryProvider.future);
    return repository.getAllTrips(orderBy: 'start_time DESC');
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final repository = await ref.read(tripRepositoryProvider.future);
      return repository.getAllTrips(orderBy: 'start_time DESC');
    });
  }
}
```

**Trip Detail Provider Pattern**:
```dart
@riverpod
Future<Trip> tripDetail(Ref ref, int tripId) async {
  final repository = await ref.watch(tripRepositoryProvider.future);
  return repository.getTripById(tripId);
}
```

### Step 2: Create Trip List Screen

**Key Features**:
- Use `ConsumerWidget` or `ConsumerStatefulWidget`
- Handle AsyncValue with `.when()` pattern
- Date grouping logic for list organization
- Pull-to-refresh using `RefreshIndicator`
- Empty state using existing `EmptyState` widget

**UI Structure**:
```
TripHistoryScreen
├── AppBar (title: "Trip History", actions: [filter button])
├── RefreshIndicator
│   └── ListView.builder
│       ├── Date header (if new date)
│       └── TripListItem (for each trip)
└── EmptyState (when no trips)
```

**Date Grouping Logic**:
```dart
String getDateLabel(DateTime date) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final yesterday = today.subtract(const Duration(days: 1));
  final tripDate = DateTime(date.year, date.month, date.day);

  if (tripDate == today) return 'Today';
  if (tripDate == yesterday) return 'Yesterday';
  if (tripDate.isAfter(today.subtract(const Duration(days: 7)))) {
    return 'This Week';
  }
  return DateFormat('MMMM d, yyyy').format(date);
}
```

### Step 3: Create Trip Detail Screen

**Key Features**:
- Load trip with route points
- Display comprehensive statistics using `StatCard`
- Show route map using `TripRouteMap` widget
- Action buttons (confirm trip, delete trip)
- Back navigation

**UI Structure**:
```
TripDetailScreen
├── AppBar (title: activity type, actions: [delete button])
├── SingleChildScrollView
│   ├── TripRouteMap (route visualization)
│   ├── TripDetailCard (statistics)
│   │   ├── StatCard (Distance)
│   │   ├── StatCard (Duration)
│   │   ├── StatCard (Avg Speed)
│   │   ├── StatCard (Max Speed)
│   │   └── StatCard (Confidence)
│   ├── Metadata section (start/end times)
│   └── Confirm button (if not confirmed)
```

### Step 4: Create Reusable Widgets

**TripListItem Widget**:
```dart
class TripListItem extends StatelessWidget {
  final Trip trip;
  final VoidCallback onTap;

  // Display:
  // - Activity icon + badge (StatusBadge)
  // - Start time (formatted)
  // - Distance + Duration (formatted)
  // - Confidence indicator (if low)
  // - Confirmation indicator (if confirmed)
}
```

**TripDetailCard Widget**:
```dart
class TripDetailCard extends StatelessWidget {
  final Trip trip;

  // Use existing StatCard widgets
  // Layout in Grid or Wrap
  // Apply theme colors and spacing
}
```

**TripRouteMap Widget**:
```dart
class TripRouteMap extends StatelessWidget {
  final List<RoutePoint> routePoints;

  // Use flutter_map package
  // Display polyline from route points
  // Add start marker (green) and end marker (red)
  // Auto-zoom to fit route bounds
  // Optional: show elevation profile
}
```

### Step 5: Integrate with App Navigation

**Update Main Navigation** (if not already done):
```dart
// In main.dart or app navigation
bottomNavigationBar: BottomNavigationBar(
  items: [
    BottomNavigationBarItem(icon: Icon(Icons.map), label: 'Track'),
    BottomNavigationBarItem(icon: Icon(Icons.history), label: 'History'),
    BottomNavigationBarItem(icon: Icon(Icons.settings), label: 'Settings'),
  ],
)
```

**Route to Trip Detail**:
```dart
Navigator.push(
  context,
  MaterialPageRoute(
    builder: (context) => TripDetailScreen(tripId: trip.id!),
  ),
);
```

## UI/UX Considerations

### Theme Usage (from AppColors and AppSpacing)

**Colors**:
- Activity badges: `AppColors.success` (cycling), `AppColors.warning` (walking)
- Trip confirmed: `AppColors.success`
- Low confidence: `AppColors.warning`
- Error states: `AppColors.error`

**Spacing**:
- Card padding: `AppSpacing.md`
- List item padding: `AppSpacing.sm`
- Section spacing: `AppSpacing.lg`
- Screen padding: `AppSpacing.md`

### Activity Type Icons

```dart
IconData getActivityIcon(ActivityType type) {
  switch (type) {
    case ActivityType.cycling:
      return Icons.directions_bike;
    case ActivityType.walking:
      return Icons.directions_walk;
    case ActivityType.running:
      return Icons.directions_run;
    case ActivityType.driving:
      return Icons.directions_car;
    default:
      return Icons.help_outline;
  }
}
```

### Empty State

**When no trips**:
```dart
EmptyState(
  icon: Icons.history,
  title: 'No Trips Yet',
  message: 'Start tracking your first bike trip!',
  actionLabel: 'Start Tracking',
  onAction: () => Navigator.pop(context), // Return to tracking screen
)
```

### Loading States

**Use AsyncValue pattern**:
```dart
tripHistoryAsync.when(
  data: (trips) => TripList(trips: trips),
  loading: () => Center(child: CircularProgressIndicator()),
  error: (error, stack) => ErrorWidget(
    message: 'Failed to load trips',
    onRetry: () => ref.refresh(tripHistoryProvider),
  ),
)
```

### Error Handling

**Database errors**:
- Show user-friendly error messages
- Provide retry button
- Log errors for debugging

**Empty route points**:
- Show message: "Route data not available"
- Hide map widget gracefully

**Deletion confirmation**:
- Show confirmation dialog before deleting
- Update UI immediately after deletion
- Show snackbar confirmation

## Testing Strategy

### Unit Tests (Optional for this task)

**Provider tests**:
```dart
test('tripHistory provider fetches all trips', () async {
  final container = ProviderContainer(
    overrides: [
      tripRepositoryProvider.overrideWithValue(mockRepository),
    ],
  );

  final trips = await container.read(tripHistoryProvider.future);
  expect(trips.length, greaterThan(0));
});
```

### Widget Tests (Optional for this task)

**Screen tests**:
- Test empty state rendering
- Test loading state rendering
- Test list rendering with mock data
- Test navigation to detail

### Manual Testing (Required)

**Test scenarios**:
1. ✅ View empty trip history (no trips recorded)
2. ✅ View trip history with multiple trips
3. ✅ Pull to refresh trip list
4. ✅ Navigate to trip detail
5. ✅ View trip route on map
6. ✅ Confirm unconfirmed trip
7. ✅ Delete trip with confirmation
8. ✅ Filter trips by activity type (if implemented)
9. ✅ Date grouping displays correctly
10. ✅ Theme colors and spacing consistent

**Physical device testing**:
- Test with real trip data (actual GPS coordinates)
- Verify map rendering performance
- Check memory usage with large trip lists
- Test offline behavior (cached trips)

## Quality Gates

**Before marking T023 complete**:

1. ✅ All files created and implemented
2. ✅ Run `flutter pub run build_runner build` (providers generated)
3. ✅ Run `flutter analyze` - MUST pass with 0 warnings
4. ✅ Manual testing on physical device completed
5. ✅ No unused imports or variables
6. ✅ `const` constructors used where possible
7. ✅ Empty states, loading states, error states all handled
8. ✅ Navigation works bidirectionally
9. ✅ Theme and spacing consistent with design system
10. ✅ Documentation updated (this file marked ✅)

## Common Pitfalls to Avoid

**From CLAUDE.md Lessons Learned**:

1. ⚠️ **Mistake #2**: Use `Ref ref`, not `TripHistoryRef` or specific ref types
2. ⚠️ **Mistake #3**: Run `flutter analyze` to catch unused imports/variables
3. ⚠️ **Best Practice**: Use `const` constructors where possible
4. ⚠️ **Best Practice**: Call provider functions directly, not with `.stream` property
5. ⚠️ **Best Practice**: Test on physical device for realistic GPS data rendering

## Resources

**Existing Code References**:
- Trip model: `lib/features/trip_detection/domain/models/trip.dart`
- Trip repository: `lib/features/trip_history/data/repositories/trip_repository.dart`
- Theme system: `lib/core/theme/`
- Existing widgets: `lib/shared/widgets/`
- Similar screen: `lib/features/trip_detection/presentation/screens/trip_tracking_screen.dart`

**External Resources**:
- [flutter_map documentation](https://docs.fleaflet.dev/)
- [Riverpod AsyncValue](https://riverpod.dev/docs/concepts/async_value)
- [Flutter ListView.builder](https://api.flutter.dev/flutter/widgets/ListView-class.html)

## Definition of Done

- [ ] All 8 files created and implemented
- [ ] Code generation completed successfully
- [ ] Flutter analyze passes with 0 warnings
- [ ] Manual testing completed on physical device
- [ ] Empty/loading/error states verified
- [ ] Navigation tested bidirectionally
- [ ] Theme consistency verified
- [ ] Documentation updated in tasks/TASKS.md

## Time Tracking

- **Estimated**: 3-4 hours
- **Actual**: _[To be filled upon completion]_

## Notes

_[Add any implementation notes, decisions, or discoveries here]_

---

**Created**: 2025-11-23
**Last Updated**: 2025-11-23
