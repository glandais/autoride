import 'dart:async';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../domain/models/location_data.dart';
import '../../domain/models/motion_data.dart';
import '../../domain/models/trip_state.dart';
import 'sensor_service.dart';
import 'location_service.dart';
import 'trip_start_detector.dart';
import 'trip_state_machine.dart';

part 'trip_detection_coordinator.g.dart';

/// Coordinates trip detection by combining motion and location data
///
/// Listens to sensor and GPS streams, analyzes data for trip start,
/// and manages state machine transitions.
@riverpod
class TripDetectionCoordinator extends _$TripDetectionCoordinator {
  Timer? _detectionTimer;
  StreamSubscription<MotionData>? _motionSubscription;
  StreamSubscription<LocationData>? _locationSubscription;

  LocationData? _lastLocation;
  bool _isAnalyzing = false;

  @override
  Future<TripState> build() async {
    // Initialize with idle state
    ref.onDispose(() {
      _cleanup();
    });

    return const TripState.idle();
  }

  /// Start listening for trip start conditions
  Future<void> startListening() async {
    if (_isAnalyzing) return;
    _isAnalyzing = true;

    // Start listening to motion stream
    final motionStream = motionDataStream(ref);
    _motionSubscription = motionStream.listen(
      _onMotionData,
      onError: (error) {
        // Handle stream errors
        _isAnalyzing = false;
      },
    );

    // Start listening to location stream (may have permission issues)
    try {
      final locStream = locationStream(ref);
      _locationSubscription = locStream.listen(
        _onLocationData,
        onError: (error) {
          // GPS unavailable - continue with motion-only detection
          _lastLocation = null;
        },
      );
    } catch (e) {
      // Location not available - continue with motion-only
      _lastLocation = null;
    }

    // Set up periodic check for detection timeout
    _detectionTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _checkDetectionTimeout(),
    );
  }

  /// Stop listening
  void stopListening() {
    _cleanup();
    _isAnalyzing = false;
  }

  /// Handle incoming motion data
  Future<void> _onMotionData(MotionData motion) async {
    // Get current state machine state
    final currentState = ref.read(tripStateMachineProvider);

    // Only analyze in Idle or Detecting states
    await currentState.mapOrNull(
      idle: (_) async {
        // In idle, start detection phase
        ref.read(tripStateMachineProvider.notifier).startDetecting();
        await _analyzeForTripStart(motion);
      },
      detecting: (_) async {
        // In detecting, continue analysis
        await _analyzeForTripStart(motion);
      },
    );
  }

  /// Handle incoming location data
  void _onLocationData(LocationData location) {
    _lastLocation = location;
  }

  /// Analyze motion and location for trip start
  Future<void> _analyzeForTripStart(MotionData motion) async {
    // Call trip start detector
    final shouldStart = await ref
        .read(tripStartDetectorProvider.notifier)
        .analyzeForTripStart(motion, _lastLocation);

    if (shouldStart) {
      // Trigger trip start
      await ref.read(tripStateMachineProvider.notifier).startTrip();

      // Update coordinator state
      final stateMachineState = ref.read(tripStateMachineProvider);
      state = AsyncValue.data(stateMachineState);

      // Stop analyzing (trip has started)
      stopListening();
    }
  }

  /// Check if detection phase has timed out
  void _checkDetectionTimeout() {
    final stateMachine = ref.read(tripStateMachineProvider.notifier);

    if (stateMachine.hasDetectionTimedOut()) {
      // Detection timed out - return to idle
      stateMachine.stopTrip();

      // Activate cooldown to prevent immediate restart
      ref.read(tripStartDetectorProvider.notifier).activateCooldown();

      // Reset and restart listening
      stopListening();
      Future.delayed(const Duration(milliseconds: 100), () {
        if (_isAnalyzing) {
          startListening();
        }
      });
    }
  }

  /// Clean up resources
  void _cleanup() {
    _detectionTimer?.cancel();
    _detectionTimer = null;

    _motionSubscription?.cancel();
    _motionSubscription = null;

    _locationSubscription?.cancel();
    _locationSubscription = null;

    _lastLocation = null;
  }
}
