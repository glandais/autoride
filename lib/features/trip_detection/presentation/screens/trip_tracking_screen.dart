import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:autoride/features/trip_detection/data/services/trip_state_machine.dart';
import 'package:autoride/features/trip_detection/data/services/trip_recorder_service.dart';
import 'package:autoride/features/trip_detection/data/services/location_service.dart';
import 'package:autoride/features/trip_history/data/repositories/trip_repository.dart';
import 'package:autoride/features/trip_detection/domain/models/trip.dart';
import 'package:autoride/features/trip_detection/domain/models/auto_detection_state.dart';
import 'package:autoride/features/trip_detection/domain/models/location_data.dart';
import 'package:autoride/features/trip_detection/domain/models/trip_state.dart';
import 'package:autoride/features/trip_detection/presentation/providers/auto_detection_controller.dart';
import 'package:autoride/features/trip_detection/presentation/widgets/trip_map_view.dart';
import 'package:autoride/features/trip_detection/presentation/widgets/trip_stats_grid.dart';
import 'package:autoride/features/trip_detection/presentation/widgets/trip_control_buttons.dart';
import 'package:autoride/features/trip_detection/presentation/widgets/stop_confirmation_dialog.dart';
import 'package:autoride/shared/widgets/status_badge.dart';
import 'package:autoride/shared/widgets/error_view.dart';
import 'package:autoride/shared/widgets/loading_view.dart';
import 'package:autoride/core/theme/app_spacing.dart';
import 'package:autoride/core/theme/app_colors.dart';
import 'package:autoride/core/utils/error_handler.dart';

part 'trip_tracking_screen.g.dart';

/// Provider to load route points for the active trip
@riverpod
Future<List<RoutePoint>> activeRoutePoints(
  Ref ref,
) async {
  final tripState = ref.watch(tripStateMachineProvider);

  // Only load if there's an active trip
  if (!tripState.hasActiveTrip || tripState.currentTripId == null) {
    return [];
  }

  final repository = await ref.watch(tripRepositoryProvider.future);
  return repository.getRoutePoints(tripState.currentTripId!);
}

/// Trip tracking screen showing real-time trip statistics and map
///
/// Features:
/// - Live trip metrics (distance, duration, speeds)
/// - Map with route polyline and current location
/// - Pause/Resume/Stop controls
/// - Auto-update as trip progresses
class TripTrackingScreen extends ConsumerStatefulWidget {
  const TripTrackingScreen({super.key});

  @override
  ConsumerState<TripTrackingScreen> createState() => _TripTrackingScreenState();
}

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

  void _onMapMoved() {
    setState(() {
      _isFollowingLocation = false;
    });
  }

  /// Re-center on the current position.
  ///
  /// The marker is fed by whatever GPS is already running (see [build]), so
  /// when the motion gate is closed there is nothing to center on: take a
  /// single on-demand fix rather than holding a stream open for the button.
  Future<void> _recenterMap() async {
    setState(() {
      _isFollowingLocation = true;
    });

    var location = _currentLocation();
    if (location == null) {
      try {
        location = await ref
            .read(locationServiceProvider.notifier)
            .getCurrentLocation();
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ErrorHandler.getErrorMessage(e))),
        );
        return;
      }
    }

    if (location != null && mounted) {
      _mapController.move(
        LatLng(location.latitude, location.longitude),
        15.0,
      );
    }
  }

  /// Current position for the map marker, WITHOUT opening GPS of its own.
  ///
  /// While a trip is recording the recorder already holds a subscription to
  /// `locationStreamProvider()`, so reading the same provider is free (Riverpod
  /// shares the one underlying position stream). Outside a trip the motion gate
  /// may legitimately have GPS off (audit #3): the screen then shows the last
  /// fix the app happened to obtain instead of forcing the receiver back on,
  /// which is exactly what `LocationService.build()` used to do (L-025).
  LocationData? _currentLocation() {
    final hasActiveTrip = ref.read(tripStateMachineProvider).hasActiveTrip;
    if (hasActiveTrip) {
      final live = ref.read(locationStreamProvider()).value;
      if (live != null) return live;
    }
    return ref.read(locationServiceProvider).value;
  }

  Future<void> _handleManualStart() async {
    try {
      await ref.read(autoDetectionControllerProvider.notifier)
          .startTripManually();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not start the trip: '
              '${ErrorHandler.getErrorMessage(e)}'),
        ),
      );
    }
  }

  Future<void> _handlePauseResume() async {
    final tripState = ref.read(tripStateMachineProvider);

    // Use pattern matching to determine pause/resume
    tripState.mapOrNull(
      paused: (_) async {
        // Resume trip
        await ref.read(tripRecorderServiceProvider.notifier).resumeRecording();
      },
      active: (_) async {
        // Pause trip
        await ref.read(tripRecorderServiceProvider.notifier).pauseRecording();
      },
    );
  }

  Future<void> _handleStop() async {
    final metricsAsync = ref.read(tripRecorderServiceProvider);

    // Get current metrics for confirmation dialog (use when to handle async state)
    final metrics = metricsAsync.when(
      data: (data) => data,
      loading: () => null,
      error: (_, _) => null,
    );
    if (metrics == null) return;

    // Show confirmation dialog
    final confirmed = await showStopConfirmationDialog(context, metrics);

    if (confirmed == true && mounted) {
      // Stop recording
      await ref.read(tripRecorderServiceProvider.notifier).stopRecording();

      if (mounted) {
        // Navigate back to home/history
        Navigator.of(context).pop();

        // Could optionally navigate to trip detail screen
        // Navigator.of(context).pushNamed('/trip-detail', arguments: trip);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tripState = ref.watch(tripStateMachineProvider);

    if (!tripState.hasActiveTrip) {
      return _buildIdleScreen(context);
    }

    final metricsAsync = ref.watch(tripRecorderServiceProvider);
    // Fed by the recorder's own GPS subscription — no extra receiver time.
    final currentLocation = ref.watch(locationStreamProvider()).value ??
        ref.watch(locationServiceProvider).value;
    final routePointsAsync = ref.watch(activeRoutePointsProvider);

    // Check if trip is paused
    final isPaused = tripState.map(
      idle: (_) => false,
      detecting: (_) => false,
      active: (_) => false,
      paused: (_) => true,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Active Trip'),
        actions: [
          // Status badge
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.md),
            child: StatusBadge(
              label: isPaused ? 'Paused' : 'Active',
              color: isPaused ? AppColors.tripPaused : AppColors.tripActive,
              icon: isPaused ? Icons.pause : Icons.directions_bike,
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Map view (takes 40% of screen)
            Expanded(
              flex: 4,
              child: Stack(
                children: [
                  // Map
                  routePointsAsync.when(
                    data: (routePoints) => TripMapView(
                      controller: _mapController,
                      routePoints: routePoints,
                      currentLocation: currentLocation,
                      followLocation: _isFollowingLocation,
                      onMapMoved: _onMapMoved,
                    ),
                    loading: () => const LoadingView.inline(
                      message: 'Loading map...',
                    ),
                    error: (error, stack) => ErrorView.generic(
                      message: 'Failed to load map: ${ErrorHandler.getErrorMessage(error)}',
                    ),
                  ),

                  // Re-center button (bottom-right)
                  if (!_isFollowingLocation)
                    Positioned(
                      bottom: AppSpacing.md,
                      right: AppSpacing.md,
                      child: FloatingActionButton.small(
                        onPressed: _recenterMap,
                        backgroundColor: theme.colorScheme.surface,
                        child: Icon(
                          Icons.my_location,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // Stats and controls (takes 60% of screen)
            Expanded(
              flex: 6,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Trip statistics
                    metricsAsync.when(
                      data: (metrics) => TripStatsGrid(metrics: metrics),
                      loading: () => const LoadingView.inline(
                        message: 'Loading metrics...',
                      ),
                      error: (error, stack) => Padding(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        child: ErrorView.generic(
                          message: ErrorHandler.getErrorMessage(error),
                          onRetry: () => ref.refresh(tripRecorderServiceProvider),
                        ),
                      ),
                    ),

                    const SizedBox(height: AppSpacing.lg),

                    // Control buttons
                    TripControlButtons(
                      isPaused: isPaused,
                      onPauseResume: _handlePauseResume,
                      onStop: _handleStop,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Shown when no trip is being recorded: the state of automatic detection,
  /// plus the manual start button (audit #11 — "force start").
  Widget _buildIdleScreen(BuildContext context) {
    final theme = Theme.of(context);
    final detection = ref.watch(autoDetectionControllerProvider);
    final isDetecting = ref.watch(tripStateMachineProvider).maybeMap(
          detecting: (_) => true,
          orElse: () => false,
        );

    final statusLabel = isDetecting
        ? 'Analyzing motion…'
        : (detection.blockedReason ?? 'Watching for a ride');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Trip'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.md),
            child: StatusBadge(
              label: detection.shouldListen ? 'Detecting' : 'Off',
              color: detection.shouldListen
                  ? AppColors.tripActive
                  : AppColors.tripPaused,
              icon: detection.shouldListen
                  ? Icons.radar
                  : Icons.pause_circle_outline,
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(
                Icons.directions_bike,
                size: 72,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                'No trip in progress',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                statusLabel,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              FilledButton.icon(
                key: const Key('manual-start-trip-button'),
                onPressed: _handleManualStart,
                icon: const Icon(Icons.play_arrow),
                label: const Text('Start ride now'),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Starts recording immediately, whether or not automatic '
                'detection is on.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
