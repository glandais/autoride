import 'dart:async';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../domain/models/activity_confidence.dart';
import '../../domain/models/location_data.dart';
import '../../domain/models/motion_data.dart';
import '../../domain/models/trip_state.dart';
import '../../domain/models/trip_stop_state.dart';
import 'sensor_service.dart';
import 'location_service.dart';
import 'trip_start_detector.dart';
import 'trip_stop_detector.dart';
import 'trip_state_machine.dart';
import 'trip_recorder_service.dart';
import '../../../../core/utils/logger.dart';

part 'trip_detection_coordinator.g.dart';

const _logger = Logger('TripDetectionCoordinator');

/// Coordinates trip detection by combining motion and location data
///
/// Listens to sensor and GPS streams, analyzes data for trip start/stop,
/// and manages state machine transitions.
@riverpod
class TripDetectionCoordinator extends _$TripDetectionCoordinator {
  Timer? _detectionTimer;
  StreamSubscription<MotionData>? _motionSubscription;
  StreamSubscription<LocationData>? _locationSubscription;

  LocationData? _lastLocation;
  bool _isAnalyzing = false;
  bool _disposed = false;

  @override
  Future<TripState> build() async {
    // Initialize with idle state
    ref.onDispose(() {
      _disposed = true;
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
      onError: (Object error, StackTrace stackTrace) {
        // The motion stream is the heartbeat of detection. If it errors, tear
        // down consistently and surface the failure rather than leaving a
        // half-running coordinator with no visible error.
        _logger.error('Motion stream error', error, stackTrace);
        _cleanup();
        _isAnalyzing = false;
        if (!_disposed) {
          state = AsyncValue.error(error, stackTrace);
        }
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

    // Analyze based on current state
    await currentState.mapOrNull(
      idle: (_) async {
        // In idle, start detection phase
        ref.read(tripStateMachineProvider.notifier).startDetecting();
        await _analyzeForTripStart(motion);
      },
      detecting: (_) async {
        // In detecting, continue analysis for trip start
        await _analyzeForTripStart(motion);
      },
      active: (_) async {
        // In active, check for trip stop/pause
        await _analyzeForTripStop(motion);
      },
      paused: (_) async {
        // In paused, check for resume or stop
        await _analyzeForResume(motion);
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
      // Get confidence score from detector
      final detector = ref.read(tripStartDetectorProvider);
      final confidence = detector.confidence;

      try {
        // Trigger trip recording (T015)
        // This will create trip in database and update state machine
        await ref.read(tripRecorderServiceProvider.notifier).startRecording(
              confidenceScore: confidence,
              activity: ActivityType.cycling,
            );
      } catch (e, stackTrace) {
        // startRecording writes to the DB and can throw. Without this guard the
        // exception escapes the stream callback unhandled, the trip silently
        // fails to start, and the UI never learns about it. Reset to idle so the
        // detector can retry on the next motion sample.
        _logger.error('Failed to start trip recording', e, stackTrace);
        ref.read(tripStateMachineProvider.notifier).stopTrip();
        ref.read(tripStartDetectorProvider.notifier).reset();
        if (!_disposed) {
          state = AsyncValue.error(e, stackTrace);
        }
        return;
      }

      // Update coordinator state
      final stateMachineState = ref.read(tripStateMachineProvider);
      state = AsyncValue.data(stateMachineState);

      // Stop analyzing (trip has started)
      stopListening();
    }
  }

  /// Analyze motion and location for trip stop/pause
  Future<void> _analyzeForTripStop(MotionData motion) async {
    // Call trip stop detector
    final decision = await ref
        .read(tripStopDetectorProvider.notifier)
        .analyzeForTripStop(motion, _lastLocation);

    if (decision == StopDecision.pauseTrip) {
      // Pause trip
      ref.read(tripStateMachineProvider.notifier).pauseTrip();

      // Update coordinator state
      final stateMachineState = ref.read(tripStateMachineProvider);
      state = AsyncValue.data(stateMachineState);
    } else if (decision == StopDecision.stopTrip) {
      // Stop trip
      await _finalizeAndStopTrip();
    }
  }

  /// Analyze motion and location for trip resume or stop
  Future<void> _analyzeForResume(MotionData motion) async {
    // Check if should resume trip
    final shouldResume = ref
        .read(tripStopDetectorProvider.notifier)
        .shouldResumeTrip(motion, _lastLocation);

    if (shouldResume) {
      // Resume trip
      ref.read(tripStateMachineProvider.notifier).resumeTrip();

      // Reset stop detector
      ref.read(tripStopDetectorProvider.notifier).reset();

      // Update coordinator state
      final stateMachineState = ref.read(tripStateMachineProvider);
      state = AsyncValue.data(stateMachineState);
    } else {
      // Still paused - check if should stop
      final decision = await ref
          .read(tripStopDetectorProvider.notifier)
          .analyzeForTripStop(motion, _lastLocation);

      if (decision == StopDecision.stopTrip) {
        // Stop trip after extended pause
        await _finalizeAndStopTrip();
      }
    }
  }

  /// Finalize trip data and stop trip
  Future<void> _finalizeAndStopTrip() async {
    // Stop recording and save trip (T015)
    // This calculates final metrics and saves to database
    // Note: stopRecording() calls TripStateMachine.stopTrip() which triggers
    // trip completion notification (implemented in T025)
    await ref.read(tripRecorderServiceProvider.notifier).stopRecording();

    // Reset stop detector
    ref.read(tripStopDetectorProvider.notifier).reset();

    // Update coordinator state
    final stateMachineState = ref.read(tripStateMachineProvider);
    state = AsyncValue.data(stateMachineState);

    // Return to listening for next trip
    stopListening();
    await Future.delayed(const Duration(milliseconds: 100));
    if (_disposed) return; // Provider torn down during the delay
    await startListening();
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
        if (!_disposed) {
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
