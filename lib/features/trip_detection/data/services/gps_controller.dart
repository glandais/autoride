import 'dart:async';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../domain/models/motion_data.dart';
import 'motion_detection_service.dart';
import '../../../../core/constants/app_constants.dart';

part 'gps_controller.g.dart';

/// GPS state
enum GPSState {
  inactive,    // GPS not running
  activating,  // GPS starting up
  active,      // GPS running
  stopping,    // GPS shutting down
}

/// Motion-gated GPS controller
/// Only activates GPS when movement is detected by sensors
@riverpod
class GPSController extends _$GPSController {
  Timer? _inactivityTimer;
  GPSState _gpsState = GPSState.inactive;

  @override
  Stream<GPSState> build() async* {
    // Initialize with inactive state
    yield _gpsState;

    // Listen to motion state changes
    final motionServiceNotifier = ref.read(motionDetectionServiceProvider.notifier);
    final motionStream = motionServiceNotifier.build();

    await for (final motionState in motionStream) {
      final newGPSState = await _handleMotionState(motionState);
      if (newGPSState != _gpsState) {
        _gpsState = newGPSState;
        yield _gpsState;
      }
    }
  }

  /// Handle motion state changes and determine GPS state
  Future<GPSState> _handleMotionState(MotionState motionState) async {
    switch (motionState) {
      case MotionState.stationary:
        return await _handleStationary();

      case MotionState.moving:
      case MotionState.cycling:
        return await _handleMovement();

      case MotionState.unknown:
        return _gpsState; // Maintain current state
    }
  }

  /// Handle stationary state
  Future<GPSState> _handleStationary() async {
    // Cancel any existing inactivity timer
    _inactivityTimer?.cancel();

    // Start inactivity timer
    _inactivityTimer = Timer(AppConstants.gpsInactivityTimeout, () {
      _stopGPS();
    });

    return _gpsState;
  }

  /// Handle movement detected
  Future<GPSState> _handleMovement() async {
    // Cancel inactivity timer
    _inactivityTimer?.cancel();

    // Start GPS if not already active
    if (_gpsState == GPSState.inactive) {
      await _startGPS();
      return GPSState.active;
    }

    return _gpsState;
  }

  /// Start GPS tracking
  Future<void> _startGPS() async {
    if (_gpsState != GPSState.inactive) return;

    _gpsState = GPSState.activating;

    // Note: Actual GPS start will be handled by LocationService
    // This controller just manages the state and triggers based on motion
    // Integration with BackgroundLocationService happens at higher level
    // Power mode is accessed via currentPowerModeProvider when needed

    _gpsState = GPSState.active;
  }

  /// Stop GPS tracking
  Future<void> _stopGPS() async {
    if (_gpsState == GPSState.inactive) return;

    _gpsState = GPSState.stopping;

    // Note: Actual GPS stop will be handled by LocationService
    // This controller just manages the state

    _gpsState = GPSState.inactive;
  }

  /// Force GPS activation (for manual trip start)
  Future<void> forceStartGPS() async {
    await _startGPS();
  }

  /// Force GPS deactivation (for manual trip stop)
  Future<void> forceStopGPS() async {
    await _stopGPS();
  }

  /// Get current GPS state
  GPSState getCurrentState() => _gpsState;

  /// Check if GPS is currently active
  bool isGPSActive() {
    return _gpsState == GPSState.active || _gpsState == GPSState.activating;
  }
}
