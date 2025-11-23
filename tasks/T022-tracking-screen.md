# T022 - Trip Tracking Screen (Active Trip)

**Status**: ⏳ In Progress
**Dependencies**: T015 (Trip Recording), T020 (Theme & Design System)
**Estimate**: 5-6 hours
**Started**: 2025-11-22

---

## Objective

Create a real-time trip tracking screen that displays live trip statistics, route visualization on a map, and trip control buttons (pause/resume/stop). Implement auto-navigation when trips start and manual access via FloatingActionButton.

---

## User Story

**As a cyclist**, I want to see my active trip in real-time with a map showing my route, current speed, distance traveled, and trip duration, so I can monitor my ride progress and control the trip recording.

---

## Requirements

### Functional Requirements

1. **Real-Time Trip Statistics**
   - Display current distance (formatted: "5.2 km" or "850 m")
   - Display trip duration (formatted: "1h 23m 45s" or "15m 30s")
   - Display average speed (km/h)
   - Display maximum speed (km/h)
   - Update automatically as trip progresses

2. **Map Visualization**
   - Display OpenStreetMap tiles using flutter_map
   - Show route as polyline (blue line connecting route points)
   - Display current location marker (animated)
   - Auto-center map on current location (follow mode)
   - Handle location permission errors gracefully

3. **Trip Controls**
   - **Pause Button**: Pause trip recording (shown when Active)
   - **Resume Button**: Resume trip recording (shown when Paused)
   - **Stop Button**: End trip with confirmation dialog
   - State-aware UI (buttons change based on trip state)

4. **Navigation**
   - **Auto-navigation**: Automatically open screen when trip becomes Active
   - **Manual access**: FloatingActionButton on HomePage when trip is active
   - Allow user to navigate away and return to tracking screen

5. **Stop Confirmation**
   - Show AlertDialog before stopping trip
   - Display trip summary in dialog (distance, duration)
   - Confirm/Cancel options
   - Navigate to trip history after confirmation

### Non-Functional Requirements

1. **Performance**
   - Smooth map rendering (60 fps)
   - Efficient polyline updates (don't redraw entire route)
   - Minimal battery impact from map rendering

2. **Responsiveness**
   - UI updates within 100ms of new location data
   - Map animations smooth and fluid
   - No jank during location updates

3. **Error Handling**
   - Handle location service failures gracefully
   - Display error state if GPS unavailable
   - Fallback UI if map tiles fail to load

4. **Accessibility**
   - Semantic labels for all interactive elements
   - Sufficient color contrast for stats
   - Screen reader support for trip metrics

---

## Technical Design

### Architecture Overview

```
TripTrackingScreen (ConsumerStatefulWidget)
├── AppBar (StatusBadge, Menu)
├── Body
│   ├── TripMapView (flutter_map widget)
│   │   ├── OSM Tile Layer
│   │   ├── Polyline Layer (route)
│   │   └── Marker Layer (current location)
│   ├── TripStatsGrid (2x2 grid of StatCards)
│   │   ├── Distance StatCard
│   │   ├── Duration StatCard
│   │   ├── Avg Speed StatCard
│   │   └── Max Speed StatCard
│   └── TripControlButtons
│       ├── Pause/Resume Button (primary)
│       └── Stop Button (secondary)
└── Navigation Logic
    ├── Auto-navigation listener (main.dart)
    └── Manual FAB (HomePage)
```

### State Management

**Providers to Watch**:
```dart
// Trip state (Idle/Detecting/Active/Paused)
final tripState = ref.watch(tripStateMachineProvider);

// Real-time trip metrics
final metricsAsync = ref.watch(tripRecorderServiceProvider);

// Current location (for map centering)
final locationAsync = ref.watch(locationServiceProvider);
```

**State Handling**:
```dart
// Handle AsyncValue states
metricsAsync.when(
  data: (metrics) {
    // Display stats
    // Update map polyline
  },
  loading: () => CircularProgressIndicator(),
  error: (error, stackTrace) => ErrorWidget(error),
);

// Handle trip state transitions
final isPaused = tripState is _Paused;
final isActive = tripState is _Active;
```

### Widget Breakdown

#### 1. TripTrackingScreen
**File**: `lib/features/trip_detection/presentation/screens/trip_tracking_screen.dart`

**Responsibilities**:
- Coordinate all child widgets
- Watch providers for state changes
- Handle navigation logic
- Manage map controller lifecycle

**Key Fields**:
```dart
class _TripTrackingScreenState extends ConsumerState<TripTrackingScreen> {
  late MapController _mapController;
  bool _isFollowingLocation = true;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }
}
```

#### 2. TripMapView
**File**: `lib/features/trip_detection/presentation/widgets/trip_map_view.dart`

**Responsibilities**:
- Render OpenStreetMap tiles
- Draw route polyline from route points
- Display current location marker
- Handle map interactions (pan, zoom)

**Props**:
```dart
TripMapView({
  required MapController controller,
  required List<LatLng> routePoints,
  required LatLng? currentLocation,
  required bool followLocation,
  required VoidCallback onMapMoved,
})
```

**Map Configuration**:
- Tile source: OpenStreetMap (https://tile.openstreetmap.org/{z}/{x}/{y}.png)
- Initial zoom: 15
- Max zoom: 18
- Min zoom: 10
- Polyline color: `AppColors.primary` (blue)
- Polyline width: 4.0
- Marker: Custom bike icon or CircleMarker

#### 3. TripStatsGrid
**File**: `lib/features/trip_detection/presentation/widgets/trip_stats_grid.dart`

**Responsibilities**:
- Display 2x2 grid of trip statistics
- Use existing StatCard widget
- Format values using TripMetrics helpers

**Props**:
```dart
TripStatsGrid({
  required TripMetrics metrics,
})
```

**Layout**:
```dart
GridView.count(
  crossAxisCount: 2,
  shrinkWrap: true,
  physics: NeverScrollableScrollPhysics(),
  mainAxisSpacing: AppSpacing.md,
  crossAxisSpacing: AppSpacing.md,
  children: [
    StatCard(label: "Distance", value: metrics.formattedDistance, icon: Icons.route),
    StatCard(label: "Duration", value: metrics.formattedDuration, icon: Icons.timer),
    StatCard(label: "Avg Speed", value: "${metrics.avgSpeedKmh?.toStringAsFixed(1) ?? '--'} km/h", icon: Icons.speed),
    StatCard(label: "Max Speed", value: "${metrics.maxSpeedKmh?.toStringAsFixed(1) ?? '--'} km/h", icon: Icons.trending_up),
  ],
)
```

#### 4. TripControlButtons
**File**: `lib/features/trip_detection/presentation/widgets/trip_control_buttons.dart`

**Responsibilities**:
- Render Pause/Resume and Stop buttons
- Handle button press events
- State-aware button labels/icons

**Props**:
```dart
TripControlButtons({
  required bool isPaused,
  required VoidCallback onPauseResume,
  required VoidCallback onStop,
})
```

**Button Logic**:
```dart
// Primary button (Pause/Resume)
ElevatedButton.icon(
  onPressed: onPauseResume,
  icon: Icon(isPaused ? Icons.play_circle : Icons.pause_circle),
  label: Text(isPaused ? 'Resume' : 'Pause'),
)

// Secondary button (Stop)
OutlinedButton.icon(
  onPressed: onStop,
  icon: Icon(Icons.stop_circle),
  label: Text('Stop Trip'),
  style: OutlinedButton.styleFrom(
    foregroundColor: Theme.of(context).colorScheme.error,
  ),
)
```

#### 5. StopConfirmationDialog
**File**: `lib/features/trip_detection/presentation/widgets/stop_confirmation_dialog.dart`

**Responsibilities**:
- Display trip summary before stopping
- Confirm user intent to stop trip
- Return boolean (confirm/cancel)

**Props**:
```dart
StopConfirmationDialog({
  required TripMetrics metrics,
})
```

**Dialog Content**:
```dart
AlertDialog(
  title: Text('Stop Trip?'),
  content: Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text('Are you sure you want to stop this trip?'),
      SizedBox(height: AppSpacing.md),
      // Summary stats
      Text('Distance: ${metrics.formattedDistance}'),
      Text('Duration: ${metrics.formattedDuration}'),
    ],
  ),
  actions: [
    TextButton(
      onPressed: () => Navigator.of(context).pop(false),
      child: Text('Cancel'),
    ),
    ElevatedButton(
      onPressed: () => Navigator.of(context).pop(true),
      child: Text('Stop Trip'),
      style: ElevatedButton.styleFrom(
        backgroundColor: Theme.of(context).colorScheme.error,
      ),
    ),
  ],
)
```

**Usage**:
```dart
final confirmed = await showDialog<bool>(
  context: context,
  builder: (context) => StopConfirmationDialog(metrics: currentMetrics),
);

if (confirmed == true) {
  // Proceed with stopping trip
}
```

---

## Navigation Implementation

### Auto-Navigation (main.dart)

**Approach**: Use `ref.listen()` to detect trip state changes and auto-navigate.

```dart
class MyApp extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Listen for trip state changes
    ref.listen(tripStateMachineProvider, (previous, next) {
      // Auto-navigate when trip becomes Active (from Idle or Detecting)
      if (previous is! _Active && next is _Active) {
        // Get navigator key or context
        final navigator = navigatorKey.currentState;
        navigator?.pushNamed('/trip-tracking');
      }
    });

    return MaterialApp(
      navigatorKey: navigatorKey,
      routes: {
        '/': (context) => HomePage(),
        '/trip-tracking': (context) => TripTrackingScreen(),
        // ... other routes
      },
    );
  }
}
```

**Alternative**: Use GoRouter for declarative navigation.

### Manual Access (HomePage FAB)

**Approach**: Show FloatingActionButton when `tripState.hasActiveTrip == true`.

```dart
class HomePage extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tripState = ref.watch(tripStateMachineProvider);

    return Scaffold(
      appBar: AppBar(title: Text('AutoRide')),
      body: // ... home content,
      floatingActionButton: tripState.hasActiveTrip
        ? FloatingActionButton.extended(
            onPressed: () {
              Navigator.of(context).pushNamed('/trip-tracking');
            },
            icon: Icon(Icons.directions_bike),
            label: Text('View Trip'),
          )
        : null,
    );
  }
}
```

---

## Map Integration Details

### Dependencies

```yaml
# pubspec.yaml
dependencies:
  flutter_map: ^7.0.2
  latlong2: ^0.9.0  # Coordinate handling for flutter_map
```

### OSM Tile Configuration

```dart
TileLayer(
  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
  userAgentPackageName: 'com.autoride.app',
  maxNativeZoom: 19,
  maxZoom: 19,
)
```

**Attribution**: Display OSM attribution in UI:
```dart
RichAttributionWidget(
  attributions: [
    TextSourceAttribution(
      'OpenStreetMap contributors',
      onTap: () => launchUrl(Uri.parse('https://openstreetmap.org/copyright')),
    ),
  ],
)
```

### Polyline Rendering

```dart
// Convert route points to LatLng
final routePoints = trip.routePoints.map((point) {
  return LatLng(point.latitude, point.longitude);
}).toList();

// Render polyline
PolylineLayer(
  polylines: [
    Polyline(
      points: routePoints,
      strokeWidth: 4.0,
      color: Theme.of(context).colorScheme.primary,
      borderStrokeWidth: 2.0,
      borderColor: Colors.white,
    ),
  ],
)
```

### Current Location Marker

```dart
MarkerLayer(
  markers: [
    if (currentLocation != null)
      Marker(
        point: currentLocation,
        width: 40,
        height: 40,
        builder: (context) => Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 4,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Icon(
            Icons.navigation,
            color: Colors.white,
            size: 20,
          ),
        ),
      ),
  ],
)
```

### Auto-Follow Logic

```dart
// Center map on current location when new location received
ref.listen(locationServiceProvider, (previous, next) {
  next.whenData((location) {
    if (_isFollowingLocation) {
      _mapController.move(
        LatLng(location.latitude, location.longitude),
        _mapController.camera.zoom,
      );
    }
  });
});

// Disable follow mode when user manually pans map
void _onMapMoved() {
  setState(() {
    _isFollowingLocation = false;
  });
}

// Re-enable follow mode button
IconButton(
  icon: Icon(_isFollowingLocation ? Icons.my_location : Icons.location_searching),
  onPressed: () {
    setState(() {
      _isFollowingLocation = true;
    });
    // Immediately center on current location
    final location = ref.read(locationServiceProvider).value;
    if (location != null) {
      _mapController.move(
        LatLng(location.latitude, location.longitude),
        15.0,
      );
    }
  },
)
```

---

## Error Handling

### Location Service Errors

```dart
// Handle location permission denied
metricsAsync.when(
  data: (metrics) => // normal UI,
  loading: () => Center(child: CircularProgressIndicator()),
  error: (error, stack) {
    if (error is LocationServiceException) {
      return ErrorStateWidget(
        icon: Icons.location_off,
        title: 'Location Unavailable',
        message: 'Please enable location services to track your trip.',
        action: ElevatedButton(
          onPressed: () => Geolocator.openLocationSettings(),
          child: Text('Open Settings'),
        ),
      );
    }
    return ErrorStateWidget(
      icon: Icons.error_outline,
      title: 'Error',
      message: error.toString(),
    );
  },
);
```

### Map Tile Loading Errors

```dart
TileLayer(
  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
  errorTileCallback: (tile, error, stackTrace) {
    // Log error, show placeholder tile
    debugPrint('Map tile error: $error');
  },
  // Fallback to cached tiles if network unavailable
  fallbackUrl: null, // Uses last cached tiles
)
```

---

## Testing Strategy

### Widget Tests

**File**: `test/features/trip_detection/presentation/trip_tracking_screen_test.dart`

**Test Cases**:
1. **Displays trip stats correctly**
   ```dart
   testWidgets('displays trip metrics', (tester) async {
     final metrics = TripMetrics(
       distanceMeters: 5234.5,
       durationSeconds: 1845,
       routePointCount: 15,
       avgSpeedKmh: 18.5,
       maxSpeedKmh: 32.1,
     );

     final container = ProviderContainer(
       overrides: [
         tripRecorderServiceProvider.overrideWith((ref) {
           return AsyncValue.data(metrics);
         }),
       ],
     );

     await tester.pumpWidget(
       UncontrolledProviderScope(
         container: container,
         child: MaterialApp(home: TripTrackingScreen()),
       ),
     );

     expect(find.text('5.2 km'), findsOneWidget);
     expect(find.text('30m 45s'), findsOneWidget);
   });
   ```

2. **Shows correct button states**
   ```dart
   testWidgets('shows resume button when paused', (tester) async {
     final container = ProviderContainer(
       overrides: [
         tripStateMachineProvider.overrideWith((ref) {
           return TripState.paused(tripId: 1);
         }),
       ],
     );

     await tester.pumpWidget(
       UncontrolledProviderScope(
         container: container,
         child: MaterialApp(home: TripTrackingScreen()),
       ),
     );

     expect(find.text('Resume'), findsOneWidget);
     expect(find.text('Pause'), findsNothing);
   });
   ```

3. **Shows stop confirmation dialog**
   ```dart
   testWidgets('shows confirmation before stopping', (tester) async {
     // ... setup

     await tester.tap(find.text('Stop Trip'));
     await tester.pumpAndSettle();

     expect(find.text('Stop Trip?'), findsOneWidget);
     expect(find.text('Cancel'), findsOneWidget);
   });
   ```

4. **Handles loading state**
   ```dart
   testWidgets('shows loading indicator', (tester) async {
     final container = ProviderContainer(
       overrides: [
         tripRecorderServiceProvider.overrideWith((ref) {
           return AsyncValue.loading();
         }),
       ],
     );

     await tester.pumpWidget(
       UncontrolledProviderScope(
         container: container,
         child: MaterialApp(home: TripTrackingScreen()),
       ),
     );

     expect(find.byType(CircularProgressIndicator), findsOneWidget);
   });
   ```

5. **Handles error state**
   ```dart
   testWidgets('shows error message', (tester) async {
     final container = ProviderContainer(
       overrides: [
         tripRecorderServiceProvider.overrideWith((ref) {
           return AsyncValue.error(Exception('GPS error'), StackTrace.empty);
         }),
       ],
     );

     await tester.pumpWidget(
       UncontrolledProviderScope(
         container: container,
         child: MaterialApp(home: TripTrackingScreen()),
       ),
     );

     expect(find.byType(ErrorStateWidget), findsOneWidget);
   });
   ```

### Physical Device Testing

**Test Scenarios**:
1. Start cycling trip → verify auto-navigation to tracking screen
2. View real-time stats updating as you ride
3. Verify map displays route correctly with current location
4. Test pause → verify button changes to Resume
5. Test resume → verify recording continues
6. Navigate away from screen → use FAB to return
7. Test stop → verify confirmation dialog → trip saves correctly
8. Test in low GPS coverage area (tunnels, buildings)
9. Test battery impact over 30-minute ride

**Expected Behavior**:
- Stats update every 15m (distance filter)
- Map polyline extends smoothly
- No map jank or stuttering
- Battery drain < 5% per hour

---

## Implementation Checklist

### Phase 1: Dependencies & Setup
- [ ] Add flutter_map and latlong2 to pubspec.yaml
- [ ] Run `flutter pub get`
- [ ] Verify dependencies installed correctly

### Phase 2: Widget Creation
- [ ] Create TripMapView widget with OSM tiles
- [ ] Create TripStatsGrid widget
- [ ] Create TripControlButtons widget
- [ ] Create StopConfirmationDialog widget
- [ ] Test each widget in isolation

### Phase 3: Main Screen
- [ ] Create TripTrackingScreen structure
- [ ] Integrate all widgets
- [ ] Wire up provider watching
- [ ] Implement pause/resume/stop handlers
- [ ] Add error handling for AsyncValue states

### Phase 4: Navigation
- [ ] Add auto-navigation listener in main.dart
- [ ] Add manual FAB to HomePage
- [ ] Test navigation from both triggers
- [ ] Handle back navigation gracefully

### Phase 5: Map Integration
- [ ] Implement polyline rendering from route points
- [ ] Add current location marker
- [ ] Implement auto-follow logic
- [ ] Add manual re-center button
- [ ] Handle map interaction (pan/zoom)

### Phase 6: Testing
- [ ] Write widget tests for TripTrackingScreen
- [ ] Write widget tests for child widgets
- [ ] Run `flutter analyze` (must pass)
- [ ] Run `flutter test` (all tests must pass)
- [ ] Test on physical device with real GPS

### Phase 7: Polish
- [ ] Add loading states (shimmer for stats)
- [ ] Add error states (location unavailable)
- [ ] Verify accessibility (semantic labels)
- [ ] Test dark theme support
- [ ] Optimize map performance

---

## Acceptance Criteria

- ✅ Trip tracking screen displays when trip becomes Active
- ✅ Real-time stats (distance, duration, avg speed, max speed) update automatically
- ✅ Map displays route as blue polyline
- ✅ Current location marker visible and animates
- ✅ Map auto-centers on current location (follow mode)
- ✅ Pause button pauses trip recording and changes to Resume
- ✅ Resume button resumes trip recording and changes to Pause
- ✅ Stop button shows confirmation dialog with trip summary
- ✅ Confirmation dialog allows cancel or confirm
- ✅ Auto-navigation works when trip starts
- ✅ Manual FAB allows return to tracking screen
- ✅ All widget tests pass
- ✅ `flutter analyze` passes with no errors
- ✅ Physical device test successful (30+ minute ride)
- ✅ Battery impact acceptable (<5% per hour)

---

## Notes & Considerations

### Map Performance
- **Polyline optimization**: Don't redraw entire polyline on every location update
  - Use `PolylineLayer` with single polyline that updates its points list
  - Consider simplifying polyline if point count exceeds 1000 (Douglas-Peucker algorithm)

- **Tile caching**: flutter_map automatically caches tiles, but consider:
  - Preload tiles for expected route if possible
  - Handle offline mode gracefully (show cached tiles)

### Battery Optimization
- Map rendering is GPU-intensive
- Consider reducing map frame rate when backgrounded
- Test with battery profiler on physical device
- May need to add "Map" toggle to hide map and save battery

### Future Enhancements (separate tasks)
- [ ] Add route elevation profile
- [ ] Add speed graph overlay
- [ ] Support multiple map tile sources (satellite view)
- [ ] Add waypoint markers (start, stops, resume points)
- [ ] Export route as GPX file
- [ ] Share route with others

---

## Reference Files

**Dependencies**:
- `lib/features/trip_detection/data/services/trip_recorder_service.dart` - Trip recording logic
- `lib/features/trip_detection/data/services/trip_state_machine.dart` - Trip state management
- `lib/features/trip_detection/domain/models/trip.dart` - Trip model
- `lib/features/trip_detection/domain/models/route_point.dart` - Route point model
- `lib/core/theme/app_colors.dart` - Color system
- `lib/shared/widgets/stat_card.dart` - Reusable stat display widget

**Similar Patterns**:
- `lib/features/onboarding/presentation/screens/onboarding_screen.dart` - Screen structure pattern
- `lib/features/onboarding/presentation/widgets/onboarding_page.dart` - Widget composition pattern

---

**Last Updated**: 2025-11-22
**Assigned To**: Claude
**Priority**: High (Core feature)
